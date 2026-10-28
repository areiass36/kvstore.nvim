local band, bor, bxor, lshift, rshift, rol = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift, bit.rol

local MASK = 0xffffffff
local BLOCK_BYTES = 64
local SHA256_BLOCK_BYTES = 64
local KEY_BYTES = 32
local NONCE_BYTES = 12
local SALT_BYTES = 32
local TAG_BYTES = 32
local VAULT_INFO = "kvstore vault v1"
local ZERO_NONCE = string.rep("\0", NONCE_BYTES)

local M = {}

M.KEY_BYTES = KEY_BYTES
M.SALT_BYTES = SALT_BYTES
M.TAG_BYTES = TAG_BYTES

function M.random(length)
  return vim.uv.random(length)
end

local function word_at(text, index)
  local b1, b2, b3, b4 = text:byte(index, index + 3)
  return bor(b1, lshift(b2, 8), lshift(b3, 16), lshift(b4, 24))
end

local function quarter_round(state, a, b, c, d)
  state[a] = band(state[a] + state[b], MASK)
  state[d] = rol(bxor(state[d], state[a]), 16)
  state[c] = band(state[c] + state[d], MASK)
  state[b] = rol(bxor(state[b], state[c]), 12)
  state[a] = band(state[a] + state[b], MASK)
  state[d] = rol(bxor(state[d], state[a]), 8)
  state[c] = band(state[c] + state[d], MASK)
  state[b] = rol(bxor(state[b], state[c]), 7)
end

local function initial_state(key, nonce, counter)
  return {
    0x61707865,
    0x3320646e,
    0x79622d32,
    0x6b206574,
    word_at(key, 1),
    word_at(key, 5),
    word_at(key, 9),
    word_at(key, 13),
    word_at(key, 17),
    word_at(key, 21),
    word_at(key, 25),
    word_at(key, 29),
    band(counter, MASK),
    word_at(nonce, 1),
    word_at(nonce, 5),
    word_at(nonce, 9),
  }
end

local function keystream_block(key, nonce, counter)
  local state = initial_state(key, nonce, counter)
  local working = {}
  for i = 1, 16 do
    working[i] = state[i]
  end

  for _ = 1, 10 do
    quarter_round(working, 1, 5, 9, 13)
    quarter_round(working, 2, 6, 10, 14)
    quarter_round(working, 3, 7, 11, 15)
    quarter_round(working, 4, 8, 12, 16)
    quarter_round(working, 1, 6, 11, 16)
    quarter_round(working, 2, 7, 12, 13)
    quarter_round(working, 3, 8, 9, 14)
    quarter_round(working, 4, 5, 10, 15)
  end

  local bytes = {}
  for i = 1, 16 do
    local word = band(working[i] + state[i], MASK)
    bytes[i] = string.char(
      band(word, 0xff),
      band(rshift(word, 8), 0xff),
      band(rshift(word, 16), 0xff),
      band(rshift(word, 24), 0xff)
    )
  end
  return table.concat(bytes)
end

function M.chacha20(key, nonce, counter, data)
  assert(#key == KEY_BYTES, "chacha20 needs a 32 byte key")
  assert(#nonce == NONCE_BYTES, "chacha20 needs a 12 byte nonce")

  local chunks = {}
  local blocks = math.ceil(#data / BLOCK_BYTES)
  for index = 0, blocks - 1 do
    local keystream = keystream_block(key, nonce, counter + index)
    local offset = index * BLOCK_BYTES
    local plain = data:sub(offset + 1, offset + BLOCK_BYTES)
    local out = {}
    for i = 1, #plain do
      out[i] = string.char(bxor(plain:byte(i), keystream:byte(i)))
    end
    chunks[#chunks + 1] = table.concat(out)
  end
  return table.concat(chunks)
end

local function hex_to_bytes(hex)
  return (hex:gsub("%x%x", function(pair)
    return string.char(tonumber(pair, 16))
  end))
end

local function sha256(message)
  return hex_to_bytes(vim.fn.sha256(message))
end

M.sha256 = sha256

function M.hmac_sha256(key, message)
  if #key > SHA256_BLOCK_BYTES then
    key = sha256(key)
  end
  key = key .. string.rep("\0", SHA256_BLOCK_BYTES - #key)

  local inner, outer = {}, {}
  for i = 1, SHA256_BLOCK_BYTES do
    local byte = key:byte(i)
    inner[i] = string.char(bxor(byte, 0x36))
    outer[i] = string.char(bxor(byte, 0x5c))
  end

  return sha256(table.concat(outer) .. sha256(table.concat(inner) .. message))
end

function M.hkdf_sha256(ikm, salt, info, length)
  local prk = M.hmac_sha256(salt, ikm)
  local blocks = {}
  local previous = ""
  local produced = 0
  local counter = 1
  while produced < length do
    previous = M.hmac_sha256(prk, previous .. info .. string.char(counter))
    blocks[#blocks + 1] = previous
    produced = produced + #previous
    counter = counter + 1
  end
  return table.concat(blocks):sub(1, length)
end

function M.equal(left, right)
  if #left ~= #right then
    return false
  end
  local difference = 0
  for i = 1, #left do
    difference = bor(difference, bxor(left:byte(i), right:byte(i)))
  end
  return difference == 0
end

local function subkeys(master_key, salt)
  local okm = M.hkdf_sha256(master_key, salt, VAULT_INFO, KEY_BYTES + TAG_BYTES)
  return okm:sub(1, KEY_BYTES), okm:sub(KEY_BYTES + 1)
end

-- The nonce is all zeroes on purpose: the salt is fresh on every seal, so the
-- encryption key is fresh too and no key ever sees the same nonce twice.
function M.seal(master_key, plaintext, aad)
  local salt = M.random(SALT_BYTES)
  local enc_key, mac_key = subkeys(master_key, salt)
  local ciphertext = M.chacha20(enc_key, ZERO_NONCE, 1, plaintext)
  local tag = M.hmac_sha256(mac_key, (aad or "") .. salt .. ciphertext)
  return salt .. ciphertext .. tag
end

function M.open(master_key, sealed, aad)
  if #sealed < SALT_BYTES + TAG_BYTES then
    return nil, "sealed data is too short"
  end

  local salt = sealed:sub(1, SALT_BYTES)
  local ciphertext = sealed:sub(SALT_BYTES + 1, #sealed - TAG_BYTES)
  local tag = sealed:sub(#sealed - TAG_BYTES + 1)

  local enc_key, mac_key = subkeys(master_key, salt)
  if not M.equal(tag, M.hmac_sha256(mac_key, (aad or "") .. salt .. ciphertext)) then
    return nil, "authentication failed"
  end

  return M.chacha20(enc_key, ZERO_NONCE, 1, ciphertext)
end

return M

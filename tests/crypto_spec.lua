local crypto = require("kvstore.crypto")
local helpers = require("helpers")

local function from_hex(hex)
  return (hex:gsub("%s", ""):gsub("%x%x", function(pair)
    return string.char(tonumber(pair, 16))
  end))
end

local function to_hex(bytes)
  return (bytes:gsub(".", function(char)
    return string.format("%02x", char:byte())
  end))
end

local function flip_byte(data, index)
  local flipped = string.char(bit.bxor(data:byte(index), 0x01))
  return data:sub(1, index - 1) .. flipped .. data:sub(index + 1)
end

local SEQUENTIAL_KEY = from_hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
local MASTER_KEY = string.rep("k", 32)

describe("crypto.chacha20", function()
  it("reproduces the RFC 8439 section 2.3.2 keystream block", function()
    local nonce = from_hex("000000090000004a00000000")
    local keystream = crypto.chacha20(SEQUENTIAL_KEY, nonce, 1, string.rep("\0", 64))
    local expected = "10f1e7e4d13b5915500fdd1fa32071c4"
      .. "c7d1f4c733c068030422aa9ac3d46c4e"
      .. "d2826446079faa0914c2d705d98b02a2"
      .. "b5129cd1de164eb9cbd083e8a2503c4e"

    assert.equals(expected, to_hex(keystream))
  end)

  it("reproduces the RFC 8439 section 2.4.2 encryption vector", function()
    local nonce = from_hex("000000000000004a00000000")
    local plaintext = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip "
      .. "for the future, sunscreen would be it."
    local expected = "6e2e359a2568f98041ba0728dd0d6981"
      .. "e97e7aec1d4360c20a27afccfd9fae0b"
      .. "f91b65c5524733ab8f593dabcd62b357"
      .. "1639d624e65152ab8f530c359f0861d8"
      .. "07ca0dbf500d6a6156a38e088a22b65e"
      .. "52bc514d16ccf806818ce91ab7793736"
      .. "5af90bbf74a35be6b40b8eedf2785e42"
      .. "874d"

    assert.equals(expected, to_hex(crypto.chacha20(SEQUENTIAL_KEY, nonce, 1, plaintext)))
  end)

  it("is its own inverse", function()
    local nonce = string.rep("\0", 12)
    local plaintext = string.rep("the quick brown fox", 20)
    local ciphertext = crypto.chacha20(SEQUENTIAL_KEY, nonce, 1, plaintext)

    assert.are_not.equals(plaintext, ciphertext)
    assert.equals(plaintext, crypto.chacha20(SEQUENTIAL_KEY, nonce, 1, ciphertext))
  end)

  it("handles an empty input and a partial final block", function()
    local nonce = string.rep("\0", 12)
    assert.equals("", crypto.chacha20(SEQUENTIAL_KEY, nonce, 1, ""))

    local plaintext = string.rep("x", 65)
    local ciphertext = crypto.chacha20(SEQUENTIAL_KEY, nonce, 1, plaintext)
    assert.equals(65, #ciphertext)
    assert.equals(plaintext, crypto.chacha20(SEQUENTIAL_KEY, nonce, 1, ciphertext))
  end)
end)

describe("crypto.hmac_sha256", function()
  it("reproduces RFC 4231 test case 1", function()
    local mac = crypto.hmac_sha256(string.rep("\x0b", 20), "Hi There")
    assert.equals("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7", to_hex(mac))
  end)

  it("reproduces RFC 4231 test case 2", function()
    local mac = crypto.hmac_sha256("Jefe", "what do ya want for nothing?")
    assert.equals("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", to_hex(mac))
  end)

  it("reproduces RFC 4231 test case 7, where the key is longer than a block", function()
    local message = "This is a test using a larger than block-size key and a larger than block-size data. "
      .. "The key needs to be hashed before being used by the HMAC algorithm."
    local mac = crypto.hmac_sha256(string.rep("\xaa", 131), message)
    assert.equals("9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2", to_hex(mac))
  end)

  it("is byte exact over a message containing a NUL", function()
    local with_nul = crypto.hmac_sha256("key", "a\0b")
    local with_newline = crypto.hmac_sha256("key", "a\nb")
    assert.are_not.equals(to_hex(with_nul), to_hex(with_newline))
  end)
end)

describe("crypto.hkdf_sha256", function()
  it("reproduces RFC 5869 test case 1", function()
    local okm = crypto.hkdf_sha256(
      string.rep("\x0b", 22),
      from_hex("000102030405060708090a0b0c"),
      from_hex("f0f1f2f3f4f5f6f7f8f9"),
      42
    )

    assert.equals("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865", to_hex(okm))
  end)

  it("returns exactly the requested length", function()
    for _, length in ipairs({ 1, 31, 32, 33, 64, 100 }) do
      assert.equals(length, #crypto.hkdf_sha256("ikm", "salt", "info", length))
    end
  end)

  it("separates outputs by salt and by info", function()
    local base = crypto.hkdf_sha256("ikm", "salt", "info", 32)
    assert.are_not.equals(base, crypto.hkdf_sha256("ikm", "other salt", "info", 32))
    assert.are_not.equals(base, crypto.hkdf_sha256("ikm", "salt", "other info", 32))
  end)
end)

describe("crypto.equal", function()
  it("compares equal strings", function()
    assert.is_true(crypto.equal("abc", "abc"))
    assert.is_true(crypto.equal("", ""))
  end)

  it("rejects a difference in any position and a difference in length", function()
    assert.is_false(crypto.equal("abc", "abd"))
    assert.is_false(crypto.equal("abc", "bbc"))
    assert.is_false(crypto.equal("abc", "abcd"))
  end)
end)

describe("crypto.random", function()
  it("returns the requested number of bytes", function()
    assert.equals(32, #crypto.random(32))
    assert.equals(1, #crypto.random(1))
  end)

  it("does not repeat itself", function()
    assert.are_not.equals(crypto.random(32), crypto.random(32))
  end)
end)

describe("crypto isolation", function()
  it("starts no process", function()
    local calls = helpers.record_processes(function()
      local sealed = crypto.seal(MASTER_KEY, "payload", "KVST\1")
      assert.equals("payload", crypto.open(MASTER_KEY, sealed, "KVST\1"))
      crypto.hkdf_sha256("ikm", crypto.random(32), "info", 64)
    end)

    assert.same({}, calls)
  end)
end)

describe("crypto.seal and crypto.open", function()
  it("round-trips a value", function()
    local plaintext = '{"entries":{"global:token":"s3cr3t"}}'
    local sealed = crypto.seal(MASTER_KEY, plaintext, "KVST\1")

    assert.equals(plaintext, crypto.open(MASTER_KEY, sealed, "KVST\1"))
  end)

  it("round-trips an empty payload and a large payload", function()
    for _, plaintext in ipairs({ "", string.rep("payload ", 5000) }) do
      local sealed = crypto.seal(MASTER_KEY, plaintext, "")
      assert.equals(plaintext, crypto.open(MASTER_KEY, sealed, ""))
    end
  end)

  it("never puts the plaintext in the sealed output", function()
    local sealed = crypto.seal(MASTER_KEY, "a very recognisable secret", "")
    assert.is_nil(sealed:find("recognisable", 1, true))
  end)

  it("uses a fresh salt on every seal", function()
    local first = crypto.seal(MASTER_KEY, "same", "")
    local second = crypto.seal(MASTER_KEY, "same", "")

    assert.are_not.equals(first:sub(1, crypto.SALT_BYTES), second:sub(1, crypto.SALT_BYTES))
    assert.are_not.equals(first, second)
  end)

  it("rejects a flipped bit in any position", function()
    local sealed = crypto.seal(MASTER_KEY, "sixteen bytes!!!", "KVST\1")

    for index = 1, #sealed do
      local value, err = crypto.open(MASTER_KEY, flip_byte(sealed, index), "KVST\1")
      assert.is_nil(value, "a flipped bit at position " .. index .. " was accepted")
      assert.equals("authentication failed", err)
    end
  end)

  it("rejects a wrong master key", function()
    local sealed = crypto.seal(MASTER_KEY, "payload", "")
    local value, err = crypto.open(string.rep("x", 32), sealed, "")

    assert.is_nil(value)
    assert.equals("authentication failed", err)
  end)

  it("rejects a changed associated header", function()
    local sealed = crypto.seal(MASTER_KEY, "payload", "KVST\1")
    local value, err = crypto.open(MASTER_KEY, sealed, "KVST\2")

    assert.is_nil(value)
    assert.equals("authentication failed", err)
  end)

  it("rejects input that is too short to hold a salt and a tag", function()
    local value, err = crypto.open(MASTER_KEY, string.rep("\0", 63), "")

    assert.is_nil(value)
    assert.equals("sealed data is too short", err)
  end)

  it("rejects a truncated payload", function()
    local sealed = crypto.seal(MASTER_KEY, "a payload long enough to truncate", "")
    local value, err = crypto.open(MASTER_KEY, sealed:sub(1, #sealed - 1), "")

    assert.is_nil(value)
    assert.equals("authentication failed", err)
  end)
end)

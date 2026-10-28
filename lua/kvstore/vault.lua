local crypto = require("kvstore.crypto")

local MAGIC = "KVST"
local FORMAT_VERSION = 1
local HEADER = MAGIC .. string.char(FORMAT_VERSION)
local MINIMUM_SIZE = #HEADER + crypto.SALT_BYTES + crypto.TAG_BYTES
local LOCK_STALE_SECONDS = 10
local OWNER_ONLY_FILE = tonumber("600", 8)
local OWNER_ONLY_DIRECTORY = tonumber("700", 8)

local M = {}

M.MAGIC = MAGIC
M.FORMAT_VERSION = FORMAT_VERSION

local function ensure_directory(directory)
  if vim.fn.isdirectory(directory) == 1 then
    return true
  end
  local ok = pcall(vim.fn.mkdir, directory, "p", OWNER_ONLY_DIRECTORY)
  if not ok then
    return nil, string.format("the directory %s could not be created", directory)
  end
  return true
end

local function read_file(path)
  local fd = vim.uv.fs_open(path, "r", OWNER_ONLY_FILE)
  if not fd then
    return nil
  end
  local stat = vim.uv.fs_fstat(fd)
  local data = ""
  if stat and stat.size > 0 then
    data = vim.uv.fs_read(fd, stat.size, 0) or ""
  end
  vim.uv.fs_close(fd)
  return data
end

local function write_atomic(path, data)
  local prepared, directory_err = ensure_directory(vim.fs.dirname(path))
  if not prepared then
    return nil, directory_err
  end

  local temporary = string.format("%s.%d.tmp", path, vim.uv.os_getpid())
  local fd, open_err = vim.uv.fs_open(temporary, "w", OWNER_ONLY_FILE)
  if not fd then
    return nil, open_err
  end

  local written, write_err = vim.uv.fs_write(fd, data, 0)
  if written then
    vim.uv.fs_fsync(fd)
  end
  vim.uv.fs_close(fd)

  if not written then
    vim.uv.fs_unlink(temporary)
    return nil, write_err
  end

  local renamed, rename_err = vim.uv.fs_rename(temporary, path)
  if not renamed then
    vim.uv.fs_unlink(temporary)
    return nil, rename_err
  end
  return true
end

local function acquire_lock(path)
  local prepared, directory_err = ensure_directory(vim.fs.dirname(path))
  if not prepared then
    return nil, directory_err
  end

  local lock = path .. ".lock"
  local fd = vim.uv.fs_open(lock, "wx", OWNER_ONLY_FILE)
  if not fd then
    -- An instance that crashed mid-write would otherwise hold the vault forever.
    local stat = vim.uv.fs_stat(lock)
    if stat and os.time() - stat.mtime.sec >= LOCK_STALE_SECONDS then
      vim.uv.fs_unlink(lock)
      fd = vim.uv.fs_open(lock, "wx", OWNER_ONLY_FILE)
    end
  end

  if not fd then
    return nil, "the vault is locked by another neovim instance"
  end

  return function()
    vim.uv.fs_close(fd)
    vim.uv.fs_unlink(lock)
  end
end

local Vault = {}
Vault.__index = Vault

function M.default_path()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "kvstore", "vault.kvs")
end

function M.new(opts)
  opts = opts or {}
  assert(type(opts.master_key) == "function", "a vault needs a master key source")
  return setmetatable({
    path = opts.path or M.default_path(),
    master_key = opts.master_key,
  }, Vault)
end

-- Held for the lifetime of this vault, which is one command. Reaching a keystore
-- costs a process, and a single command needs the key up to four times.
function Vault:key()
  if self.held_key then
    return self.held_key
  end

  local key, err = self.master_key()
  if not key then
    return nil, err or "the master key is not available"
  end

  self.held_key = key
  return key
end

-- Answers whether the vault could be written to, without handing the key out.
-- An absent vault file reads as empty, so nothing else proves the key is
-- reachable before the user is asked for a value.
function Vault:usable()
  local key, err = self:key()
  if not key then
    return nil, err
  end
  return true
end

function Vault:entries()
  local data = read_file(self.path)
  if data == nil or data == "" then
    return {}
  end

  if data:sub(1, #MAGIC) ~= MAGIC then
    return nil, string.format("%s is not a kvstore vault", self.path)
  end

  local version = data:byte(#MAGIC + 1)
  if version ~= FORMAT_VERSION then
    return nil, string.format("the vault uses format version %d, which this plugin cannot read", version)
  end

  if #data < MINIMUM_SIZE then
    return nil, "the vault is corrupt: it is too short to hold a sealed payload"
  end

  local key, key_err = self:key()
  if not key then
    return nil, key_err
  end

  local plaintext = crypto.open(key, data:sub(#HEADER + 1), HEADER)
  if not plaintext then
    return nil, "the vault could not be opened: it is corrupt or the master key is wrong"
  end

  local decoded_ok, decoded = pcall(vim.json.decode, plaintext)
  if not decoded_ok or type(decoded) ~= "table" or type(decoded.entries) ~= "table" then
    return nil, "the vault could not be opened: its contents are unreadable"
  end
  return decoded.entries
end

function Vault:save(entries)
  local key, key_err = self:key()
  if not key then
    return nil, key_err
  end

  local payload = vim.json.encode({ entries = next(entries) ~= nil and entries or vim.empty_dict() })
  return write_atomic(self.path, HEADER .. crypto.seal(key, payload, HEADER))
end

local function modify(vault, change)
  local release, lock_err = acquire_lock(vault.path)
  if not release then
    return nil, lock_err
  end

  local entries, read_err = vault:entries()
  if not entries then
    release()
    return nil, read_err
  end

  local changed, change_err = change(entries)
  if not changed then
    release()
    return nil, change_err
  end

  local saved, save_err = vault:save(entries)
  release()
  if not saved then
    return nil, save_err
  end
  return true
end

function Vault:get(name)
  local entries, err = self:entries()
  if not entries then
    return nil, err
  end
  return entries[name]
end

function Vault:exists(name)
  local entries, err = self:entries()
  if not entries then
    return nil, err
  end
  return entries[name] ~= nil
end

function Vault:set(name, value)
  return modify(self, function(entries)
    entries[name] = value
    return true
  end)
end

function Vault:delete(name)
  return modify(self, function(entries)
    if entries[name] == nil then
      return nil, "the key does not exist"
    end
    entries[name] = nil
    return true
  end)
end

function Vault:list_names()
  local entries, err = self:entries()
  if not entries then
    return nil, err
  end

  local names = {}
  for name in pairs(entries) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

return M

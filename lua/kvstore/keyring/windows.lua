local process = require("kvstore.process")

local EXECUTABLE = "powershell.exe"
local OWNER_ONLY_FILE = tonumber("600", 8)
local OWNER_ONLY_DIRECTORY = tonumber("700", 8)

-- PowerShell only protects and unprotects. Every file access stays in Lua, which
-- keeps the WSL backend free of any path translation.
local PROTECT = [[
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$plain = [Convert]::FromBase64String('%s')
$blob = [Security.Cryptography.ProtectedData]::Protect($plain, $null, 'CurrentUser')
[Console]::Out.Write([Convert]::ToBase64String($blob))
]]

local UNPROTECT = [[
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$blob = [Convert]::FromBase64String('%s')
$plain = [Security.Cryptography.ProtectedData]::Unprotect($blob, $null, 'CurrentUser')
[Console]::Out.Write([Convert]::ToBase64String($plain))
]]

local function read_blob(path)
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
  return vim.trim(data)
end

local function write_blob(path, data)
  local directory = vim.fs.dirname(path)
  if vim.fn.isdirectory(directory) == 0 then
    vim.fn.mkdir(directory, "p", OWNER_ONLY_DIRECTORY)
  end

  local fd, open_err = vim.uv.fs_open(path, "w", OWNER_ONLY_FILE)
  if not fd then
    return nil, open_err
  end
  local written, write_err = vim.uv.fs_write(fd, data, 0)
  if written then
    vim.uv.fs_fsync(fd)
  end
  vim.uv.fs_close(fd)
  if not written then
    return nil, write_err
  end
  return true
end

-- Both the script and the key travel on stdin, so neither reaches an argument
-- list. The base64 alphabet cannot close the PowerShell quoting.
local function new(options)
  local backend = {
    name = options.name,
    executable = options.executable,
    detect = options.detect,
  }

  function backend.blob_path()
    return vim.fs.joinpath(vim.fn.stdpath("data"), "kvstore", options.blob_name or "master.dpapi")
  end

  local function run_script(script)
    return process.run({
      backend.executable,
      "-NoProfile",
      "-NonInteractive",
      "-NoLogo",
      "-Command",
      "-",
    }, { stdin = script })
  end

  function backend.get()
    local blob = read_blob(backend.blob_path())
    if not blob or blob == "" then
      return nil, "no master key has been stored for this user yet"
    end

    local output, err = run_script(string.format(UNPROTECT, blob))
    if not output then
      return nil, err
    end

    local decoded_ok, decoded = pcall(vim.base64.decode, vim.trim(output))
    if not decoded_ok or decoded == "" then
      return nil, "the protected master key could not be read"
    end
    return decoded
  end

  function backend.set(key)
    local output, err = run_script(string.format(PROTECT, vim.base64.encode(key)))
    if not output then
      return nil, err
    end

    local blob = vim.trim(output)
    if blob == "" then
      return nil, "the master key could not be protected"
    end
    return write_blob(backend.blob_path(), blob)
  end

  function backend.exists()
    local blob = read_blob(backend.blob_path())
    return blob ~= nil and blob ~= ""
  end

  function backend.delete()
    if not backend.exists() then
      return nil, "no master key has been stored for this user yet"
    end
    local removed, err = vim.uv.fs_unlink(backend.blob_path())
    if not removed then
      return nil, err
    end
    return true
  end

  return backend
end

local M = new({
  name = "windows",
  executable = EXECUTABLE,
  detect = function()
    return vim.fn.has("win32") == 1 and process.available(EXECUTABLE)
  end,
})

M.new = new

return M

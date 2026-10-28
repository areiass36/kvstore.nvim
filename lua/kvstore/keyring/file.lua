local process = require("kvstore.process")

local OWNER_ONLY_FILE = tonumber("600", 8)
local OWNER_ONLY_DIRECTORY = tonumber("700", 8)

local M = {}

M.name = "file"
M.warned = false

function M.key_path()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "kvstore", "master.key")
end

-- The last resort is always applicable, which is what makes it the last resort.
function M.detect()
  return true
end

function M.warn()
  if M.warned then
    return
  end
  M.warned = true

  vim.notify(
    string.format(
      "kvstore: no system keystore was detected, so the master key is kept in %s. "
        .. "It is readable only by you, which is weaker protection than a keystore.",
      M.key_path()
    ),
    vim.log.levels.WARN
  )
end

-- A file mode means nothing on Windows, so the equivalent there is to drop every
-- inherited entry and grant the current user alone.
local function restrict(path)
  if vim.fn.has("win32") == 1 then
    local user = os.getenv("USERNAME")
    if not user or user == "" then
      return nil, "the current windows user could not be determined"
    end
    local output, err = process.run({ "icacls", path, "/inheritance:r", "/grant:r", user .. ":F" })
    if not output then
      return nil, err
    end
    return true
  end

  local changed, err = vim.uv.fs_chmod(path, OWNER_ONLY_FILE)
  if not changed then
    return nil, err
  end
  return true
end

function M.get()
  local path = M.key_path()
  local fd = vim.uv.fs_open(path, "r", OWNER_ONLY_FILE)
  if not fd then
    return nil, "no master key has been stored for this user yet"
  end

  local stat = vim.uv.fs_fstat(fd)
  local data = ""
  if stat and stat.size > 0 then
    data = vim.uv.fs_read(fd, stat.size, 0) or ""
  end
  vim.uv.fs_close(fd)

  local encoded = vim.trim(data)
  if encoded == "" then
    return nil, "the master key file is empty"
  end

  local decoded_ok, decoded = pcall(vim.base64.decode, encoded)
  if not decoded_ok then
    return nil, "the master key file is not readable"
  end
  return decoded
end

function M.set(key)
  local path = M.key_path()
  local directory = vim.fs.dirname(path)
  if vim.fn.isdirectory(directory) == 0 then
    vim.fn.mkdir(directory, "p", OWNER_ONLY_DIRECTORY)
  end

  local fd, open_err = vim.uv.fs_open(path, "w", OWNER_ONLY_FILE)
  if not fd then
    return nil, open_err
  end

  local written, write_err = vim.uv.fs_write(fd, vim.base64.encode(key), 0)
  if written then
    vim.uv.fs_fsync(fd)
  end
  vim.uv.fs_close(fd)

  if not written then
    return nil, write_err
  end
  return restrict(path)
end

function M.exists()
  local stat = vim.uv.fs_stat(M.key_path())
  return stat ~= nil and stat.size > 0
end

function M.delete()
  if not M.exists() then
    return nil, "no master key has been stored for this user yet"
  end

  local removed, err = vim.uv.fs_unlink(M.key_path())
  if not removed then
    return nil, err
  end
  return true
end

return M

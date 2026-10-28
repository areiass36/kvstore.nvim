local process = require("kvstore.process")

local SERVICE = "kvstore"
local EXECUTABLE = "security"

local M = {}

M.name = "macos"

local function account()
  return os.getenv("USER") or "kvstore"
end

function M.detect()
  return vim.fn.has("mac") == 1 and process.available(EXECUTABLE)
end

function M.get()
  local output, err = process.run({
    EXECUTABLE,
    "find-generic-password",
    "-s",
    SERVICE,
    "-a",
    account(),
    "-w",
  })
  if not output then
    return nil, err
  end

  local encoded = vim.trim(output)
  if encoded == "" then
    return nil, "the keychain returned an empty master key"
  end

  local decoded_ok, decoded = pcall(vim.base64.decode, encoded)
  if not decoded_ok then
    return nil, "the master key in the keychain is not readable"
  end
  return decoded
end

-- security has no flag that reads a password from stdin, so the whole command is
-- fed to its interactive mode instead. The key travels in stdin either way.
function M.set(key)
  local script = table.concat({
    "add-generic-password",
    "-s",
    SERVICE,
    "-a",
    account(),
    "-U",
    "-w",
    vim.base64.encode(key),
  }, " ")

  local output, err = process.run({ EXECUTABLE, "-i" }, { stdin = script .. "\n" })
  if not output then
    return nil, err
  end
  return true
end

function M.exists()
  local output = process.run({
    EXECUTABLE,
    "find-generic-password",
    "-s",
    SERVICE,
    "-a",
    account(),
  })
  return output ~= nil
end

function M.delete()
  local output, err = process.run({
    EXECUTABLE,
    "delete-generic-password",
    "-s",
    SERVICE,
    "-a",
    account(),
  })
  if not output then
    return nil, err
  end
  return true
end

return M

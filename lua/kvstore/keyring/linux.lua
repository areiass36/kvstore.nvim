local process = require("kvstore.process")

local EXECUTABLE = "secret-tool"
local SERVICE = "kvstore"
local LABEL = "kvstore master key"

local M = {}

M.name = "linux"

local function account()
  return os.getenv("USER") or "kvstore"
end

local function attributes()
  return { "service", SERVICE, "account", account() }
end

local function command(action, extra)
  local argv = { EXECUTABLE, action }
  for _, value in ipairs(extra or {}) do
    argv[#argv + 1] = value
  end
  for _, value in ipairs(attributes()) do
    argv[#argv + 1] = value
  end
  return argv
end

function M.detect()
  return process.available(EXECUTABLE) and os.getenv("DBUS_SESSION_BUS_ADDRESS") ~= nil
end

function M.get()
  local output, err = process.run(command("lookup"))
  if not output then
    return nil, err
  end

  local encoded = vim.trim(output)
  if encoded == "" then
    return nil, "no master key has been stored for this user yet"
  end

  local decoded_ok, decoded = pcall(vim.base64.decode, encoded)
  if not decoded_ok then
    return nil, "the master key in the secret service is not readable"
  end
  return decoded
end

-- secret-tool store reads the secret from stdin, which is exactly what is needed.
function M.set(key)
  local output, err = process.run(command("store", { "--label=" .. LABEL }), { stdin = vim.base64.encode(key) .. "\n" })
  if not output then
    return nil, err
  end
  return true
end

function M.exists()
  local output = process.run(command("lookup"))
  return output ~= nil and vim.trim(output) ~= ""
end

function M.delete()
  if not M.exists() then
    return nil, "no master key has been stored for this user yet"
  end

  local output, err = process.run(command("clear"))
  if not output then
    return nil, err
  end
  return true
end

return M

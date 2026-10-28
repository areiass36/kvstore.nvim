local crypto = require("kvstore.crypto")

local ORDER = { "macos", "windows", "wsl", "linux", "file" }
local FALLBACK = "file"

local M = {}

M.ORDER = ORDER

function M.backend(name)
  local ok, backend = pcall(require, "kvstore.keyring." .. name)
  if not ok or type(backend) ~= "table" then
    return nil, string.format("there is no keystore backend named '%s'", tostring(name))
  end
  return backend
end

function M.detect()
  for _, name in ipairs(ORDER) do
    local backend = M.backend(name)
    if backend and backend.detect() then
      return backend
    end
  end
  return M.backend(FALLBACK)
end

function M.select(name)
  if name == nil or name == "auto" then
    return M.detect()
  end
  return M.backend(name)
end

-- The master key is generated on first use and never leaves this function except
-- to the caller that is about to open the vault with it.
function M.master_key(opts)
  local backend, err = M.select(opts and opts.backend)
  if not backend then
    return nil, err
  end

  if backend.warn then
    backend.warn()
  end

  if backend.exists() then
    return backend.get()
  end

  local key = crypto.random(crypto.KEY_BYTES)
  local stored, store_err = backend.set(key)
  if not stored then
    return nil, store_err
  end
  return key
end

return M

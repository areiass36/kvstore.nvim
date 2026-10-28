local commands = require("kvstore.commands")

local MINIMUM_VERSION = "nvim-0.12"

local DEFAULTS = {
  backend = "auto",
  confirm_value = false,
}

local M = {}

M.options = vim.deepcopy(DEFAULTS)

function M.setup(opts)
  if vim.fn.has(MINIMUM_VERSION) ~= 1 then
    error("kvstore needs neovim 0.12 or newer", 0)
  end

  M.options = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts or {})
  commands.register(M.options)
  return M.options
end

-- Reads the project scope first and falls back to the global one. Pass
-- { global = true } to read the global scope only.
function M.get(key, opts)
  return commands.read(key, opts or {}, M.options)
end

-- Stores a configuration value, always in the global scope. Any value vim.json
-- can encode is accepted. A caller passing a secret is responsible for where
-- that secret came from: a literal in a configuration file protects nothing.
function M.set(key, value)
  return commands.write(key, value, M.options)
end

return M

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

-- Reading is the whole point of a public interface, so it is here. There is no
-- public setter: a value only ever arrives through the prompt.
function M.get(key, opts)
  return commands.read(key, opts or {}, M.options)
end

return M

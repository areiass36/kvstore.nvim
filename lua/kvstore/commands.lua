local keyring = require("kvstore.keyring")
local scope = require("kvstore.scope")
local vault = require("kvstore.vault")

local GLOBAL_FLAG = "--global"

local M = {}

-- The only seam the tests replace, so a command never reaches the real vault or
-- the real keystore.
function M.open_vault(options)
  return vault.new({
    path = options and options.path,
    master_key = function()
      return keyring.master_key(options)
    end,
  })
end

local function fail(message)
  vim.notify("kvstore: " .. message, vim.log.levels.ERROR)
  return nil, message
end

local function inform(message)
  vim.notify("kvstore: " .. message, vim.log.levels.INFO)
end

local function missing(key, request)
  return string.format("'%s' is not stored in the %s scope", key, scope.label(request))
end

function M.parse(arguments)
  local request = { global = false }
  local keys = {}

  for _, argument in ipairs(arguments) do
    if argument == GLOBAL_FLAG then
      if request.global then
        return nil, string.format("%s was given twice", GLOBAL_FLAG)
      end
      request.global = true
    elseif argument:sub(1, 1) == "-" then
      return nil, string.format("unknown flag '%s'", argument)
    else
      keys[#keys + 1] = argument
    end
  end

  if #keys == 0 then
    return nil, "a key name is required"
  end
  if #keys > 1 then
    return nil, "only one key is accepted, and a value is never passed as an argument"
  end

  request.key = keys[1]
  return request
end

local function resolve(arguments)
  local request, parse_err = M.parse(arguments)
  if not request then
    return nil, parse_err
  end

  local name, scope_err = scope.resolve(request.key, request)
  if not name then
    return nil, scope_err
  end
  return request, name
end

local function confirmed_overwrite(key, request)
  local answer = vim.fn.confirm(
    string.format("kvstore: '%s' already exists in the %s scope. Overwrite?", key, scope.label(request)),
    "&No\n&Yes",
    1
  )
  return answer == 2
end

-- The value never leaves this function, so it goes out of scope as soon as the
-- vault has it. Returns nil with no reason when the user cancelled: an empty
-- line is indistinguishable from an interrupted prompt, so both cancel.
local function prompt_and_store(store, name, options)
  local value = vim.fn.inputsecret("Value: ")
  if value == "" then
    return nil, nil
  end

  if options and options.confirm_value and vim.fn.inputsecret("Value again: ") ~= value then
    return nil, "the two values did not match, nothing was stored"
  end

  return store:set(name, value)
end

function M.store(arguments, options)
  local request, name = resolve(arguments)
  if not request then
    return fail(name)
  end

  local store = M.open_vault(options)

  -- Asked before the prompt: no value is worth typing if it cannot be stored.
  local usable, usable_err = store:usable()
  if not usable then
    return fail(usable_err)
  end

  local exists, exists_err = store:exists(name)
  if exists == nil then
    return fail(exists_err)
  end

  if exists and not confirmed_overwrite(request.key, request) then
    return inform("nothing was stored")
  end

  local stored, store_err = prompt_and_store(store, name, options)
  if not stored then
    if store_err then
      return fail(store_err)
    end
    return inform("nothing was stored")
  end

  inform(string.format("stored '%s' in the %s scope", request.key, scope.label(request)))
  return true
end

function M.show(arguments, options)
  local request, name = resolve(arguments)
  if not request then
    return fail(name)
  end

  local value, err = M.open_vault(options):get(name)
  if err then
    return fail(err)
  end
  if value == nil then
    return fail(missing(request.key, request))
  end

  -- The one place a value is printed, and the only way to print it without
  -- leaving a copy in the message history.
  vim.api.nvim_echo({ { value } }, false, {})
  return true
end

function M.remove(arguments, options)
  local request, name = resolve(arguments)
  if not request then
    return fail(name)
  end

  local store = M.open_vault(options)
  local exists, exists_err = store:exists(name)
  if exists == nil then
    return fail(exists_err)
  end
  if not exists then
    return fail(missing(request.key, request))
  end

  local deleted, delete_err = store:delete(name)
  if not deleted then
    return fail(delete_err)
  end

  inform(string.format("removed '%s' from the %s scope", request.key, scope.label(request)))
  return true
end

-- The public read path. It reports through its return values and never notifies,
-- because a caller in a configuration decides what to do about a missing key.
function M.read(key, request, options)
  local name, scope_err = scope.resolve(key, request)
  if not name then
    return nil, scope_err
  end

  local value, err = M.open_vault(options):get(name)
  if err then
    return nil, err
  end
  if value == nil then
    return nil, missing(key, request)
  end
  return value
end

function M.complete(arglead, cmdline, options)
  local wants_global = cmdline:find(GLOBAL_FLAG, 1, true) ~= nil
  local candidates = {}

  if not wants_global and vim.startswith(GLOBAL_FLAG, arglead) then
    candidates[#candidates + 1] = GLOBAL_FLAG
  end

  -- Completion decrypts the vault. A keystore that cannot be reached must not
  -- turn a keypress into an error, so the flag is all the user gets.
  local ok, names = pcall(function()
    return M.open_vault(options):list_names()
  end)
  if not ok or not names then
    return candidates
  end

  for _, key in ipairs(scope.keys_in_scope(names, { global = wants_global })) do
    if vim.startswith(key, arglead) then
      candidates[#candidates + 1] = key
    end
  end
  return candidates
end

function M.register(options)
  local definitions = {
    KVStore = { handler = M.store, desc = "Store a value for a key, asking for the value without echoing it" },
    KVGet = { handler = M.show, desc = "Print the value of a key" },
    KVDelete = { handler = M.remove, desc = "Remove a key" },
  }

  for name, definition in pairs(definitions) do
    vim.api.nvim_create_user_command(name, function(arguments)
      definition.handler(arguments.fargs, options)
    end, {
      nargs = "*",
      desc = definition.desc,
      complete = function(arglead, cmdline)
        return M.complete(arglead, cmdline, options)
      end,
    })
  end
end

return M

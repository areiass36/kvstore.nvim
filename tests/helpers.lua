local M = {}

-- Replaces every way the plugin could start a process, so a test can assert that
-- a module is self contained, or inspect exactly what a backend would have run.
--
-- opts.respond(command, options) returns { code, stdout, stderr } for a call.
-- opts.executable(name) returns 0 or 1, standing in for vim.fn.executable.
function M.record_processes(fn, opts)
  opts = opts or {}
  local calls = {}

  local original = {
    system = vim.system,
    spawn = vim.uv.spawn,
    fn_system = vim.fn.system,
    fn_jobstart = vim.fn.jobstart,
    fn_executable = vim.fn.executable,
  }

  local function record(how, command, options)
    calls[#calls + 1] = { how = how, command = command, options = options }
  end

  local function respond(command, options)
    if opts.respond then
      local result = opts.respond(command, options) or {}
      return {
        code = result.code or 0,
        stdout = result.stdout or "",
        stderr = result.stderr or "",
      }
    end
    return { code = 0, stdout = "", stderr = "" }
  end

  vim.system = function(command, options)
    record("vim.system", command, options)
    local result = respond(command, options)
    return {
      wait = function()
        return result
      end,
    }
  end

  vim.uv.spawn = function(command, options)
    record("vim.uv.spawn", command, options)
    return nil, "process spawning is stubbed in tests"
  end

  vim.fn.system = function(command)
    record("vim.fn.system", command, nil)
    return ""
  end

  vim.fn.jobstart = function(command, options)
    record("vim.fn.jobstart", command, options)
    return -1
  end

  vim.fn.executable = function(name)
    if opts.executable then
      return opts.executable(name)
    end
    return 1
  end

  local ok, err = pcall(fn)

  vim.system = original.system
  vim.uv.spawn = original.spawn
  vim.fn.system = original.fn_system
  vim.fn.jobstart = original.fn_jobstart
  vim.fn.executable = original.fn_executable

  if not ok then
    error(err, 0)
  end
  return calls
end

-- Answers vim.fn.has for the duration of fn, so a detection rule can be tested
-- on a system it was not written for.
function M.with_has(answers, fn)
  local original = vim.fn.has
  vim.fn.has = function(feature)
    if answers[feature] ~= nil then
      return answers[feature]
    end
    return original(feature)
  end

  local ok, err = pcall(fn)
  vim.fn.has = original
  if not ok then
    error(err, 0)
  end
end

-- Sets environment variables for the duration of fn. A value of false unsets.
function M.with_env(variables, fn)
  local saved = {}
  for name, value in pairs(variables) do
    saved[name] = os.getenv(name) or false
    if value == false then
      vim.uv.os_unsetenv(name)
    else
      vim.uv.os_setenv(name, value)
    end
  end

  local ok, err = pcall(fn)

  for name, value in pairs(saved) do
    if value == false then
      vim.uv.os_unsetenv(name)
    else
      vim.uv.os_setenv(name, value)
    end
  end

  if not ok then
    error(err, 0)
  end
end

-- Redirects stdpath("data") at a temporary directory, so a backend that keeps a
-- file never touches the real one. Returns the undo function and the directory.
function M.redirect_data_directory()
  local directory = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(directory, "p")

  local original = vim.fn.stdpath
  vim.fn.stdpath = function(what)
    if what == "data" then
      return directory
    end
    return original(what)
  end

  return function()
    vim.fn.stdpath = original
  end, directory
end

-- True when the needle appears in any argument or in the environment of any
-- recorded call. The one place a secret must never be.
function M.leaked(calls, needle)
  for _, call in ipairs(calls) do
    for _, argument in ipairs(call.command or {}) do
      if type(argument) == "string" and argument:find(needle, 1, true) then
        return true, argument
      end
    end

    local env = call.options and call.options.env
    if type(env) == "table" then
      for name, value in pairs(env) do
        local entry = tostring(name) .. "=" .. tostring(value)
        if entry:find(needle, 1, true) then
          return true, entry
        end
      end
    end
  end
  return false
end

return M

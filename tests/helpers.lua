local M = {}

-- Replaces every way the plugin could start a process, so a test can assert that
-- a module is self contained or inspect what a backend would have run.
function M.record_processes(fn)
  local calls = {}
  local original = {
    system = vim.system,
    spawn = vim.uv.spawn,
    fn_system = vim.fn.system,
    fn_jobstart = vim.fn.jobstart,
  }

  local function record(how, command, options)
    calls[#calls + 1] = { how = how, command = command, options = options }
  end

  vim.system = function(command, options)
    record("vim.system", command, options)
    return {
      wait = function()
        return { code = 0, stdout = "", stderr = "" }
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

  local ok, err = pcall(fn)

  vim.system = original.system
  vim.uv.spawn = original.spawn
  vim.fn.system = original.fn_system
  vim.fn.jobstart = original.fn_jobstart

  if not ok then
    error(err, 0)
  end
  return calls
end

return M

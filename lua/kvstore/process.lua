local DEFAULT_TIMEOUT_MS = 10000
local REDACTED = "[redacted]"

local M = {}

local function replace_all(text, needle)
  local parts = {}
  local position = 1
  while true do
    local from, to = text:find(needle, position, true)
    if not from then
      break
    end
    parts[#parts + 1] = text:sub(position, from - 1)
    parts[#parts + 1] = REDACTED
    position = to + 1
  end
  parts[#parts + 1] = text:sub(position)
  return table.concat(parts)
end

-- A tool that fails may quote back what it read, so anything written to a child
-- is removed from the message before the message reaches the user.
local function redact(text, secret)
  if type(secret) ~= "string" or secret == "" then
    return text
  end

  local cleaned = replace_all(text, secret)
  local trimmed = vim.trim(secret)
  if trimmed ~= "" and trimmed ~= secret then
    cleaned = replace_all(cleaned, trimmed)
  end
  return cleaned
end

M.redact = redact

function M.available(executable)
  return vim.fn.executable(executable) == 1
end

-- The command is always an argument list, so nothing passes through a shell, and
-- a secret only ever travels in opts.stdin.
function M.run(command, opts)
  opts = opts or {}
  assert(type(command) == "table" and #command > 0, "a command is a non-empty argument list")

  local executable = command[1]
  if not M.available(executable) then
    return nil, string.format("%s was not found on this system", executable)
  end

  local started, result = pcall(function()
    return vim
      .system(command, {
        stdin = opts.stdin,
        text = false,
        timeout = opts.timeout or DEFAULT_TIMEOUT_MS,
      })
      :wait()
  end)

  if not started then
    return nil, string.format("%s could not be started: %s", executable, redact(tostring(result), opts.stdin))
  end

  if result.code ~= 0 then
    local detail = redact(vim.trim(result.stderr or ""), opts.stdin)
    if detail == "" then
      detail = string.format("exit code %d", result.code)
    end
    return nil, string.format("%s failed: %s", executable, detail)
  end

  return result.stdout or ""
end

return M

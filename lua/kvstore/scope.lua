local MAX_KEY_LENGTH = 128
local KEY_PATTERN = "^[A-Za-z0-9._%-]+$"

local M = {}

M.MAX_KEY_LENGTH = MAX_KEY_LENGTH

local function is_windows()
  return vim.fn.has("win32") == 1
end

local function normalize_directory(directory)
  local normalized = vim.fs.normalize(vim.uv.fs_realpath(directory) or directory)
  if #normalized > 1 then
    normalized = normalized:gsub("(.)/+$", "%1")
  end
  -- Windows paths are case insensitive, so the same directory reached through a
  -- differently cased path has to hash to the same project.
  if is_windows() then
    normalized = normalized:lower()
  end
  return normalized
end

function M.validate_key(key)
  if type(key) ~= "string" or key == "" then
    return nil, "a key name is required"
  end
  if #key > MAX_KEY_LENGTH then
    return nil, string.format("a key name is at most %d characters", MAX_KEY_LENGTH)
  end
  if not key:match(KEY_PATTERN) then
    return nil, "a key name may only contain letters, digits, '.', '_' and '-'"
  end
  return key
end

function M.project_directory()
  return normalize_directory(vim.uv.cwd())
end

function M.prefix(opts)
  if opts and opts.global then
    return "global:"
  end
  return string.format("project:%s:", vim.fn.sha256(M.project_directory()))
end

function M.resolve(key, opts)
  local valid, err = M.validate_key(key)
  if not valid then
    return nil, err
  end
  return M.prefix(opts) .. valid
end

function M.label(opts)
  if opts and opts.global then
    return "global"
  end
  return "project"
end

function M.keys_in_scope(names, opts)
  local prefix = M.prefix(opts)
  local keys = {}
  for _, name in ipairs(names) do
    if name:sub(1, #prefix) == prefix then
      keys[#keys + 1] = name:sub(#prefix + 1)
    end
  end
  table.sort(keys)
  return keys
end

return M

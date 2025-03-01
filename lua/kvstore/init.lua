local store_path = vim.fn.stdpath('data') .. '/kvstore.json'
local function load()
	local file = io.open(store_path, 'r')
	if not file then
		io.write(store_path, 'r')
		return {}
	end
	local content = file:read("*a")
	file:close()
	return vim.fn.json_decode(content)
end

local M = {}
M.store = {}

function M.save()
	local json = vim.fn.json_encode(M.store)
	vim.fn.writefile({ json }, store_path)
end

function M.setup()
	M.store = load()
end

function M.get(key)
	return M.store[key]
end

function M.set(key, value)
	M.store[key] = value
	M.save()
	return value
end

function M.has(key)
	return M.store[key] ~= nil
end

function M.delete(key)
	M.store[key] = nil
	M.save()
end

function M.get_or_set(key, callback)
	if M.store[key] ~= nil then
		return M.store[key]
	end
	local value = callback()
	return M.set(key, value)
end

M.setup()
return M

local file = require("kvstore.keyring.file")
local helpers = require("helpers")

local KEY = string.rep("F", 32)
local ENCODED = vim.base64.encode(KEY)

local function read_text(path)
  local fd = assert(vim.uv.fs_open(path, "r", 384))
  local stat = assert(vim.uv.fs_fstat(fd))
  local data = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  return data
end

describe("keyring.file", function()
  local restore

  before_each(function()
    restore = helpers.redirect_data_directory()
    file.warned = false
  end)

  after_each(function()
    restore()
    file.warned = false
  end)

  it("is the last resort and always applies", function()
    assert.equals("file", file.name)
    assert.is_true(file.detect())
  end)

  it("keeps the key beside the vault", function()
    assert.equals("master.key", vim.fs.basename(file.key_path()))
    assert.truthy(file.key_path():find("kvstore", 1, true))
  end)

  it("round-trips the key", function()
    local key
    helpers.record_processes(function()
      assert.is_true(file.set(KEY))
      key = file.get()
    end)

    assert.equals(KEY, key)
  end)

  it("stores the key encoded rather than raw", function()
    helpers.record_processes(function()
      file.set(KEY)
    end)

    local contents = read_text(file.key_path())
    assert.equals(ENCODED, vim.trim(contents))
    assert.is_nil(contents:find(KEY, 1, true))
  end)

  it("restricts the file to the owner", function()
    local calls = helpers.record_processes(function()
      assert.is_true(file.set(KEY))
    end)

    if vim.fn.has("win32") == 1 then
      local icacls = calls[1]
      assert.equals("icacls", icacls.command[1])
      assert.equals(file.key_path(), icacls.command[2])
      assert.equals("/inheritance:r", icacls.command[3])
      assert.truthy(icacls.command[5]:find(":F", 1, true))
      assert.is_false(helpers.leaked(calls, ENCODED))
      assert.is_false(helpers.leaked(calls, KEY))
    else
      assert.same({}, calls)
      local mode = assert(vim.uv.fs_stat(file.key_path())).mode % 512
      assert.equals(tonumber("600", 8), mode)
    end
  end)

  it("reports a failure to restrict the file", function()
    if vim.fn.has("win32") ~= 1 then
      return
    end

    local stored, err
    helpers.record_processes(function()
      stored, err = file.set(KEY)
    end, {
      respond = function()
        return { code = 1, stderr = "Access is denied." }
      end,
    })

    assert.is_nil(stored)
    assert.equals("icacls failed: Access is denied.", err)
  end)

  it("reports a missing key file", function()
    local key, err = file.get()

    assert.is_nil(key)
    assert.equals("no master key has been stored for this user yet", err)
  end)

  it("reports an empty key file", function()
    vim.fn.mkdir(vim.fs.dirname(file.key_path()), "p")
    local fd = assert(vim.uv.fs_open(file.key_path(), "w", 384))
    vim.uv.fs_write(fd, "   \n", 0)
    vim.uv.fs_close(fd)

    local key, err = file.get()
    assert.is_nil(key)
    assert.equals("the master key file is empty", err)
  end)

  it("reports a key file that is not base64", function()
    vim.fn.mkdir(vim.fs.dirname(file.key_path()), "p")
    local fd = assert(vim.uv.fs_open(file.key_path(), "w", 384))
    vim.uv.fs_write(fd, "not!base64!", 0)
    vim.uv.fs_close(fd)

    local key, err = file.get()
    assert.is_nil(key)
    assert.equals("the master key file is not readable", err)
  end)

  it("reports presence and deletes the key file", function()
    assert.is_false(file.exists())

    local deleted, err = file.delete()
    assert.is_nil(deleted)
    assert.equals("no master key has been stored for this user yet", err)

    helpers.record_processes(function()
      file.set(KEY)
    end)

    assert.is_true(file.exists())
    assert.is_true(file.delete())
    assert.is_false(file.exists())
  end)
end)

describe("keyring.file warning", function()
  local restore
  local notices
  local original_notify

  before_each(function()
    restore = helpers.redirect_data_directory()
    file.warned = false
    notices = {}
    original_notify = vim.notify
    vim.notify = function(message, level)
      notices[#notices + 1] = { message = message, level = level }
    end
  end)

  after_each(function()
    vim.notify = original_notify
    restore()
    file.warned = false
  end)

  it("warns once that the protection is weaker, and names the file", function()
    file.warn()
    file.warn()
    file.warn()

    assert.equals(1, #notices)
    assert.equals(vim.log.levels.WARN, notices[1].level)
    assert.truthy(notices[1].message:find("weaker", 1, true))
    assert.truthy(notices[1].message:find(file.key_path(), 1, true))
  end)

  it("never names the key in the warning", function()
    helpers.record_processes(function()
      file.set(KEY)
    end)
    file.warn()

    assert.is_nil(notices[1].message:find(ENCODED, 1, true))
    assert.is_nil(notices[1].message:find(KEY, 1, true))
  end)
end)

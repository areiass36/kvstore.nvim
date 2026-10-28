local kvstore = require("kvstore")
local commands = require("kvstore.commands")
local helpers = require("helpers")

describe("kvstore", function()
  local saved

  before_each(function()
    saved = { read = commands.read, write = commands.write, options = kvstore.options }
  end)

  after_each(function()
    commands.read = saved.read
    commands.write = saved.write
    kvstore.options = saved.options
  end)

  it("exposes setup, get and set and nothing else", function()
    local surface = {}
    for member in pairs(kvstore) do
      surface[#surface + 1] = member
    end
    table.sort(surface)

    assert.same({ "get", "options", "set", "setup" }, surface)
    assert.is_function(kvstore.setup)
    assert.is_function(kvstore.get)
    assert.is_function(kvstore.set)
  end)

  it("exposes no public delete", function()
    assert.is_nil(kvstore.delete)
    assert.is_nil(kvstore.remove)
  end)

  it("defaults to automatic backend detection and a single prompt", function()
    local options = kvstore.setup()

    assert.equals("auto", options.backend)
    assert.is_false(options.confirm_value)
    assert.same(options, kvstore.options)
  end)

  it("keeps the defaults a caller did not mention", function()
    local options = kvstore.setup({ confirm_value = true })

    assert.is_true(options.confirm_value)
    assert.equals("auto", options.backend)
  end)

  it("accepts a forced backend", function()
    assert.equals("file", kvstore.setup({ backend = "file" }).backend)
  end)

  it("registers the three commands", function()
    kvstore.setup()
    local defined = vim.api.nvim_get_commands({})

    for _, name in ipairs({ "KVStore", "KVGet", "KVDelete" }) do
      assert.truthy(defined[name], name .. " was not created")
    end
  end)

  it("refuses to start on an older neovim", function()
    helpers.with_has({ ["nvim-0.12"] = 0 }, function()
      assert.has_error(function()
        kvstore.setup()
      end, "kvstore needs neovim 0.12 or newer")
    end)
  end)

  it("reads through the same path as the commands", function()
    local seen
    commands.read = function(key, request, options)
      seen = { key = key, request = request, options = options }
      return "the-value"
    end

    kvstore.setup({ confirm_value = true })
    assert.equals("the-value", kvstore.get("token"))
    assert.equals("token", seen.key)
    assert.same({}, seen.request)
    assert.is_true(seen.options.confirm_value)
  end)

  it("passes the global scope through", function()
    local seen
    commands.read = function(_, request)
      seen = request
      return "the-value"
    end

    kvstore.get("token", { global = true })
    assert.is_true(seen.global)
  end)

  it("writes through the same path as the commands", function()
    local seen
    commands.write = function(key, value, options)
      seen = { key = key, value = value, options = options }
      return true
    end

    kvstore.setup({ confirm_value = true })
    assert.is_true(kvstore.set("api-key", { a = 1 }))
    assert.equals("api-key", seen.key)
    assert.same({ a = 1 }, seen.value)
    assert.is_true(seen.options.confirm_value)
  end)

  it("takes no scope on set, because it is always global", function()
    local seen
    commands.write = function(key, value)
      seen = { key = key, value = value }
      return true
    end

    kvstore.set("api-key", "v")
    assert.equals(2, vim.tbl_count(seen))
  end)

  it("returns nil and a reason for a value it cannot write", function()
    commands.write = function()
      return nil, "a value is required"
    end

    local written, err = kvstore.set("api-key", nil)
    assert.is_nil(written)
    assert.equals("a value is required", err)
  end)

  it("returns nil and a reason for a key it cannot read", function()
    commands.read = function()
      return nil, "'token' is not stored in the project scope"
    end

    local value, err = kvstore.get("token")
    assert.is_nil(value)
    assert.equals("'token' is not stored in the project scope", err)
  end)
end)

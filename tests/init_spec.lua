local kvstore = require("kvstore")
local commands = require("kvstore.commands")
local helpers = require("helpers")

describe("kvstore", function()
  local saved

  before_each(function()
    saved = { read = commands.read, options = kvstore.options }
  end)

  after_each(function()
    commands.read = saved.read
    kvstore.options = saved.options
  end)

  it("exposes setup and get and nothing else", function()
    local surface = {}
    for member in pairs(kvstore) do
      surface[#surface + 1] = member
    end
    table.sort(surface)

    assert.same({ "get", "options", "setup" }, surface)
    assert.is_function(kvstore.setup)
    assert.is_function(kvstore.get)
  end)

  it("has no public way to store a value", function()
    assert.is_nil(kvstore.set)
    assert.is_nil(kvstore.store)
    assert.is_nil(kvstore.delete)
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

  it("returns nil and a reason for a key it cannot read", function()
    commands.read = function()
      return nil, "'token' is not stored in the project scope"
    end

    local value, err = kvstore.get("token")
    assert.is_nil(value)
    assert.equals("'token' is not stored in the project scope", err)
  end)
end)

local commands = require("kvstore.commands")
local scope = require("kvstore.scope")
local vault = require("kvstore.vault")

local MASTER_KEY = string.rep("c", 32)
local SECRET = "a-very-secret-value"

local path
local notices
local echoes
local prompts
local answers
local saved

local function store_for(options)
  return vault.new({
    path = (options and options.path) or path,
    master_key = function()
      return MASTER_KEY
    end,
  })
end

local function notified()
  local messages = {}
  for _, notice in ipairs(notices) do
    messages[#messages + 1] = notice.message
  end
  return table.concat(messages, "\n")
end

local function last_error()
  for index = #notices, 1, -1 do
    if notices[index].level == vim.log.levels.ERROR then
      return notices[index].message
    end
  end
end

describe("commands", function()
  before_each(function()
    path = vim.fs.joinpath(vim.fs.normalize(vim.fn.tempname()), "vault.kvs")
    notices, echoes, prompts = {}, {}, {}
    answers = { secrets = {}, confirm = 1 }

    saved = {
      open_vault = commands.open_vault,
      notify = vim.notify,
      echo = vim.api.nvim_echo,
      inputsecret = vim.fn.inputsecret,
      confirm = vim.fn.confirm,
    }

    commands.open_vault = store_for

    vim.notify = function(message, level)
      notices[#notices + 1] = { message = message, level = level }
    end

    vim.api.nvim_echo = function(chunks, history, opts)
      echoes[#echoes + 1] = { chunks = chunks, history = history, opts = opts }
    end

    vim.fn.inputsecret = function(prompt)
      prompts[#prompts + 1] = prompt
      return table.remove(answers.secrets, 1) or ""
    end

    vim.fn.confirm = function()
      return answers.confirm
    end
  end)

  after_each(function()
    commands.open_vault = saved.open_vault
    vim.notify = saved.notify
    vim.api.nvim_echo = saved.echo
    vim.fn.inputsecret = saved.inputsecret
    vim.fn.confirm = saved.confirm
  end)

  describe("parse", function()
    it("accepts a single key", function()
      local request = commands.parse({ "token" })
      assert.equals("token", request.key)
      assert.is_false(request.global)
    end)

    it("accepts the flag before or after the key", function()
      for _, arguments in ipairs({ { "--global", "token" }, { "token", "--global" } }) do
        local request = commands.parse(arguments)
        assert.equals("token", request.key)
        assert.is_true(request.global)
      end
    end)

    it("requires a key", function()
      local request, err = commands.parse({})
      assert.is_nil(request)
      assert.equals("a key name is required", err)

      request, err = commands.parse({ "--global" })
      assert.is_nil(request)
      assert.equals("a key name is required", err)
    end)

    it("rejects a second positional argument and says why", function()
      local request, err = commands.parse({ "token", "hunter2" })

      assert.is_nil(request)
      assert.equals("only one key is accepted, and a value is never passed as an argument", err)
    end)

    it("rejects a repeated flag and an unknown flag", function()
      local request, err = commands.parse({ "--global", "--global", "token" })
      assert.is_nil(request)
      assert.equals("--global was given twice", err)

      request, err = commands.parse({ "--project", "token" })
      assert.is_nil(request)
      assert.equals("unknown flag '--project'", err)

      request, err = commands.parse({ "-g", "token" })
      assert.is_nil(request)
      assert.equals("unknown flag '-g'", err)
    end)
  end)

  describe("KVStore", function()
    it("asks for the value and stores it", function()
      answers.secrets = { SECRET }

      assert.is_true(commands.store({ "token" }, {}))
      assert.same({ "Value: " }, prompts)
      assert.equals(SECRET, store_for():get(scope.resolve("token", {})))
      assert.truthy(notified():find("stored 'token' in the project scope", 1, true))
    end)

    it("stores a global key separately from a project key", function()
      answers.secrets = { "global-value", "project-value" }
      commands.store({ "--global", "token" }, {})
      commands.store({ "token" }, {})

      local store = store_for()
      assert.equals("global-value", store:get("global:token"))
      assert.equals("project-value", store:get(scope.resolve("token", {})))
    end)

    it("cancels on empty input and stores nothing", function()
      answers.secrets = { "" }

      commands.store({ "token" }, {})

      assert.is_nil(store_for():get(scope.resolve("token", {})))
      assert.truthy(notified():find("nothing was stored", 1, true))
      assert.is_nil(last_error())
    end)

    it("keeps the existing value when the overwrite is declined", function()
      answers.secrets = { "first" }
      commands.store({ "token" }, {})

      answers.secrets = { "second" }
      answers.confirm = 1
      commands.store({ "token" }, {})

      assert.equals("first", store_for():get(scope.resolve("token", {})))
      assert.truthy(notified():find("nothing was stored", 1, true))
    end)

    it("keeps the existing value when the confirmation is interrupted", function()
      answers.secrets = { "first" }
      commands.store({ "token" }, {})

      answers.secrets = { "second" }
      answers.confirm = 0
      commands.store({ "token" }, {})

      assert.equals("first", store_for():get(scope.resolve("token", {})))
    end)

    it("does not ask for a value when the overwrite is declined", function()
      answers.secrets = { "first" }
      commands.store({ "token" }, {})
      prompts = {}

      answers.confirm = 1
      commands.store({ "token" }, {})

      assert.same({}, prompts)
    end)

    it("overwrites when the confirmation is accepted", function()
      answers.secrets = { "first" }
      commands.store({ "token" }, {})

      answers.secrets = { "second" }
      answers.confirm = 2
      commands.store({ "token" }, {})

      assert.equals("second", store_for():get(scope.resolve("token", {})))
    end)

    it("asks twice when confirm_value is set", function()
      answers.secrets = { SECRET, SECRET }

      assert.is_true(commands.store({ "token" }, { confirm_value = true }))
      assert.same({ "Value: ", "Value again: " }, prompts)
      assert.equals(SECRET, store_for():get(scope.resolve("token", {})))
    end)

    it("stores nothing when the two entries differ", function()
      answers.secrets = { SECRET, "mistyped" }

      commands.store({ "token" }, { confirm_value = true })

      assert.is_nil(store_for():get(scope.resolve("token", {})))
      assert.equals("kvstore: the two values did not match, nothing was stored", last_error())
    end)

    it("rejects a bad key name before asking for anything", function()
      commands.store({ "my key" }, {})

      assert.same({}, prompts)
      assert.truthy(last_error():find("may only contain", 1, true))
    end)

    it("rejects a value given as an argument before asking for anything", function()
      commands.store({ "token", SECRET }, {})

      assert.same({}, prompts)
      assert.equals("kvstore: only one key is accepted, and a value is never passed as an argument", last_error())
    end)

    it("never puts the value in a message", function()
      answers.secrets = { SECRET }
      commands.store({ "token" }, {})
      answers.secrets = { SECRET }
      answers.confirm = 2
      commands.store({ "token" }, {})

      assert.is_nil(notified():find(SECRET, 1, true))
    end)

    it("reports a vault that cannot be opened", function()
      commands.open_vault = function()
        return vault.new({
          path = path,
          master_key = function()
            return nil, "the keystore is unavailable"
          end,
        })
      end

      commands.store({ "token" }, {})

      assert.same({}, prompts)
      assert.equals("kvstore: the keystore is unavailable", last_error())
    end)
  end)

  describe("KVGet", function()
    it("prints the value without adding it to the message history", function()
      answers.secrets = { SECRET }
      commands.store({ "token" }, {})

      assert.is_true(commands.show({ "token" }, {}))
      assert.equals(1, #echoes)
      assert.same({ { SECRET } }, echoes[1].chunks)
      assert.is_false(echoes[1].history)
      assert.same({}, echoes[1].opts)
    end)

    it("never puts the value in a message", function()
      answers.secrets = { SECRET }
      commands.store({ "token" }, {})
      commands.show({ "token" }, {})

      assert.is_nil(notified():find(SECRET, 1, true))
    end)

    it("prints a value that is not a string as json", function()
      commands.write("options", { retries = 3 }, {})

      assert.is_true(commands.show({ "--global", "options" }, {}))
      assert.equals('{"retries":3}', echoes[1].chunks[1][1])
      assert.is_false(echoes[1].history)
    end)

    it("reports a missing key and names the scope", function()
      commands.show({ "absent" }, {})
      assert.equals("kvstore: 'absent' is not stored in the project scope", last_error())

      commands.show({ "--global", "absent" }, {})
      assert.equals("kvstore: 'absent' is not stored in the global scope", last_error())
      assert.same({}, echoes)
    end)

    it("does not answer a project key from the global scope", function()
      answers.secrets = { SECRET }
      commands.store({ "token" }, {})

      commands.show({ "--global", "token" }, {})

      assert.same({}, echoes)
      assert.equals("kvstore: 'token' is not stored in the global scope", last_error())
    end)

    it("reports a corrupt vault instead of printing anything", function()
      answers.secrets = { SECRET }
      commands.store({ "token" }, {})

      local fd = assert(vim.uv.fs_open(path, "r+", 384))
      vim.uv.fs_write(fd, "ruined", 40)
      vim.uv.fs_close(fd)

      commands.show({ "token" }, {})

      assert.same({}, echoes)
      assert.truthy(last_error():find("corrupt or the master key is wrong", 1, true))
    end)
  end)

  describe("KVDelete", function()
    it("removes a key", function()
      answers.secrets = { SECRET }
      commands.store({ "token" }, {})

      assert.is_true(commands.remove({ "token" }, {}))
      assert.is_nil(store_for():get(scope.resolve("token", {})))
      assert.truthy(notified():find("removed 'token' from the project scope", 1, true))
    end)

    it("reports a missing key and names the scope", function()
      commands.remove({ "absent" }, {})
      assert.equals("kvstore: 'absent' is not stored in the project scope", last_error())
    end)

    it("does not remove a global key without the flag", function()
      answers.secrets = { SECRET }
      commands.store({ "--global", "token" }, {})

      commands.remove({ "token" }, {})

      assert.equals(SECRET, store_for():get("global:token"))
      assert.equals("kvstore: 'token' is not stored in the project scope", last_error())
    end)
  end)

  describe("read", function()
    it("returns the value without notifying", function()
      answers.secrets = { SECRET }
      commands.store({ "token" }, {})
      notices = {}

      assert.equals(SECRET, commands.read("token", {}, {}))
      assert.same({}, notices)
      assert.same({}, echoes)
    end)

    it("reports a missing key through its return values", function()
      local value, err = commands.read("absent", {}, {})

      assert.is_nil(value)
      assert.equals("'absent' is not stored in the project or the global scope", err)
      assert.same({}, notices)
    end)

    it("reports a missing key in the global scope alone when asked", function()
      local value, err = commands.read("absent", { global = true }, {})

      assert.is_nil(value)
      assert.equals("'absent' is not stored in the global scope", err)
    end)

    it("reports a bad key name through its return values", function()
      local value, err = commands.read("my key", {}, {})

      assert.is_nil(value)
      assert.truthy(err:find("may only contain", 1, true))
    end)

    it("falls back to the global scope when the project has no such key", function()
      answers.secrets = { SECRET }
      commands.store({ "--global", "token" }, {})

      assert.equals(SECRET, commands.read("token", { global = true }, {}))
      assert.equals(SECRET, commands.read("token", {}, {}))
    end)

    it("prefers the project value when both scopes hold the key", function()
      answers.secrets = { "global-value", "project-value" }
      commands.store({ "--global", "token" }, {})
      commands.store({ "token" }, {})

      assert.equals("project-value", commands.read("token", {}, {}))
      assert.equals("global-value", commands.read("token", { global = true }, {}))
    end)

    it("does not fall back when the global scope is asked for explicitly", function()
      answers.secrets = { SECRET }
      commands.store({ "token" }, {})

      local value, err = commands.read("token", { global = true }, {})
      assert.is_nil(value)
      assert.equals("'token' is not stored in the global scope", err)
    end)

    it("consults both scopes with a single keystore read", function()
      answers.secrets = { SECRET }
      commands.store({ "--global", "token" }, {})

      local reads = 0
      commands.open_vault = function()
        return vault.new({
          path = path,
          master_key = function()
            reads = reads + 1
            return MASTER_KEY
          end,
        })
      end

      assert.equals(SECRET, commands.read("token", {}, {}))
      assert.equals(1, reads)
    end)
  end)

  describe("write", function()
    it("stores in the global scope and is readable from any project", function()
      assert.is_true(commands.write("api-key", "k-123", {}))

      assert.equals("k-123", store_for():get("global:api-key"))
      assert.is_nil(store_for():get(scope.resolve("api-key", {})))
      assert.equals("k-123", commands.read("api-key", {}, {}))
    end)

    it("never notifies and never echoes", function()
      commands.write("api-key", "k-123", {})

      assert.same({}, notices)
      assert.same({}, echoes)
    end)

    it("keeps the type of every value vim.json can encode", function()
      local cases = {
        text = "a string",
        empty = "",
        count = 42,
        ratio = 4.5,
        enabled = true,
        disabled = false,
        options = { retries = 3, hosts = { "a", "b" }, nested = { deep = true } },
        list = { 1, 2, 3 },
      }

      for key, value in pairs(cases) do
        assert.is_true(commands.write(key, value, {}), key)
      end

      for key, value in pairs(cases) do
        assert.same(value, commands.read(key, {}, {}), key)
      end

      assert.equals("number", type(commands.read("count", {}, {})))
      assert.equals(42, commands.read("count", {}, {}))
      assert.equals("boolean", type(commands.read("enabled", {}, {})))
      assert.is_false(commands.read("disabled", {}, {}))
    end)

    it("stores a value that json represents as null", function()
      assert.is_true(commands.write("nothing", vim.NIL, {}))
      assert.equals(vim.NIL, commands.read("nothing", {}, {}))
    end)

    it("overwrites without asking, because no one is at the keyboard", function()
      commands.write("api-key", "first", {})
      assert.is_true(commands.write("api-key", "second", {}))

      assert.equals("second", commands.read("api-key", {}, {}))
      assert.same({}, prompts)
    end)

    it("rejects a missing value", function()
      local written, err = commands.write("api-key", nil, {})

      assert.is_nil(written)
      assert.equals("a value is required", err)
      assert.is_nil(store_for():get("global:api-key"))
    end)

    it("rejects a value json cannot encode, before touching the vault", function()
      local written, err = commands.write("api-key", function() end, {})

      assert.is_nil(written)
      assert.truthy(err:find("cannot be stored", 1, true))
      assert.is_nil(store_for():get("global:api-key"))
    end)

    it("rejects a bad key name", function()
      local written, err = commands.write("my key", "v", {})

      assert.is_nil(written)
      assert.truthy(err:find("may only contain", 1, true))
    end)

    it("reports a keystore it cannot reach", function()
      commands.open_vault = function()
        return vault.new({
          path = path,
          master_key = function()
            return nil, "the keystore is unavailable"
          end,
        })
      end

      local written, err = commands.write("api-key", "v", {})
      assert.is_nil(written)
      assert.equals("the keystore is unavailable", err)
    end)
  end)

  describe("complete", function()
    it("offers the flag until it is present", function()
      assert.truthy(vim.tbl_contains(commands.complete("", "KVGet ", {}), "--global"))
      assert.is_false(vim.tbl_contains(commands.complete("", "KVGet --global ", {}), "--global"))
    end)

    it("offers the keys of the scope being addressed", function()
      answers.secrets = { "1", "2", "3" }
      commands.store({ "project-key" }, {})
      commands.store({ "--global", "global-key" }, {})
      commands.store({ "--global", "another" }, {})

      assert.same({ "--global", "project-key" }, commands.complete("", "KVGet ", {}))
      assert.same({ "another", "global-key" }, commands.complete("", "KVGet --global ", {}))
    end)

    it("filters by what has been typed", function()
      answers.secrets = { "1", "2" }
      commands.store({ "token" }, {})
      commands.store({ "trailer" }, {})

      assert.same({ "token", "trailer" }, commands.complete("t", "KVGet t", {}))
      assert.same({ "token" }, commands.complete("to", "KVGet to", {}))
    end)

    it("stays quiet when the vault cannot be opened", function()
      commands.open_vault = function()
        return vault.new({
          path = path,
          master_key = function()
            return nil, "the keystore is unavailable"
          end,
        })
      end

      assert.same({ "--global" }, commands.complete("", "KVGet ", {}))
      assert.same({}, notices)
    end)
  end)
end)

describe("commands.register", function()
  it("creates the three commands", function()
    commands.register({})
    local defined = vim.api.nvim_get_commands({})

    for _, name in ipairs({ "KVStore", "KVGet", "KVDelete" }) do
      assert.truthy(defined[name], name .. " was not created")
      assert.equals("*", defined[name].nargs)
      assert.truthy(defined[name].definition ~= "")
    end
  end)
end)

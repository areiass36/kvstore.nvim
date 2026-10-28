local linux = require("kvstore.keyring.linux")
local helpers = require("helpers")

local KEY = string.rep("X", 32)
local ENCODED = vim.base64.encode(KEY)

local function account()
  return os.getenv("USER") or "kvstore"
end

describe("keyring.linux", function()
  it("is named after its system", function()
    assert.equals("linux", linux.name)
  end)

  it("needs both secret-tool and a session bus", function()
    helpers.with_env({ DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus" }, function()
      helpers.record_processes(function()
        assert.is_true(linux.detect())
      end, {
        executable = function()
          return 1
        end,
      })

      helpers.record_processes(function()
        assert.is_false(linux.detect())
      end, {
        executable = function()
          return 0
        end,
      })
    end)

    helpers.with_env({ DBUS_SESSION_BUS_ADDRESS = false }, function()
      helpers.record_processes(function()
        assert.is_false(linux.detect())
      end, {
        executable = function()
          return 1
        end,
      })
    end)
  end)
end)

describe("keyring.linux get", function()
  it("looks the key up by its attributes and decodes it", function()
    local key
    local calls = helpers.record_processes(function()
      key = linux.get()
    end, {
      respond = function()
        return { code = 0, stdout = ENCODED .. "\n" }
      end,
    })

    assert.equals(KEY, key)
    assert.same({
      "secret-tool",
      "lookup",
      "service",
      "kvstore",
      "account",
      account(),
    }, calls[1].command)
  end)

  it("reports an empty lookup as nothing stored", function()
    local key, err
    helpers.record_processes(function()
      key, err = linux.get()
    end, {
      respond = function()
        return { code = 0, stdout = "" }
      end,
    })

    assert.is_nil(key)
    assert.equals("no master key has been stored for this user yet", err)
  end)

  it("reports a value that is not base64", function()
    local key, err
    helpers.record_processes(function()
      key, err = linux.get()
    end, {
      respond = function()
        return { code = 0, stdout = "not!base64!" }
      end,
    })

    assert.is_nil(key)
    assert.equals("the master key in the secret service is not readable", err)
  end)

  it("reports a secret service that is unreachable", function()
    local key, err
    helpers.record_processes(function()
      key, err = linux.get()
    end, {
      respond = function()
        return { code = 1, stderr = "Cannot autolaunch D-Bus without X11 $DISPLAY" }
      end,
    })

    assert.is_nil(key)
    assert.equals("secret-tool failed: Cannot autolaunch D-Bus without X11 $DISPLAY", err)
  end)
end)

describe("keyring.linux set", function()
  it("sends the key on stdin, where secret-tool expects it", function()
    local stored
    local calls = helpers.record_processes(function()
      stored = linux.set(KEY)
    end)

    assert.is_true(stored)
    assert.same({
      "secret-tool",
      "store",
      "--label=kvstore master key",
      "service",
      "kvstore",
      "account",
      account(),
    }, calls[1].command)
    assert.equals(ENCODED .. "\n", calls[1].options.stdin)
  end)

  it("never puts the key in an argument or in the environment", function()
    local calls = helpers.record_processes(function()
      linux.set(KEY)
    end)

    assert.is_false(helpers.leaked(calls, ENCODED))
    assert.is_false(helpers.leaked(calls, KEY))
  end)

  it("propagates a failure", function()
    local stored, err
    helpers.record_processes(function()
      stored, err = linux.set(KEY)
    end, {
      respond = function()
        return { code = 1, stderr = "the collection is locked" }
      end,
    })

    assert.is_nil(stored)
    assert.equals("secret-tool failed: the collection is locked", err)
  end)
end)

describe("keyring.linux exists and delete", function()
  it("reports presence from a non-empty lookup", function()
    helpers.record_processes(function()
      assert.is_true(linux.exists())
    end, {
      respond = function()
        return { code = 0, stdout = ENCODED }
      end,
    })

    helpers.record_processes(function()
      assert.is_false(linux.exists())
    end, {
      respond = function()
        return { code = 0, stdout = "" }
      end,
    })
  end)

  it("clears the stored attributes", function()
    local deleted
    local calls = helpers.record_processes(function()
      deleted = linux.delete()
    end, {
      respond = function()
        return { code = 0, stdout = ENCODED }
      end,
    })

    assert.is_true(deleted)
    assert.same({
      "secret-tool",
      "clear",
      "service",
      "kvstore",
      "account",
      account(),
    }, calls[2].command)
  end)

  it("reports a delete when nothing is stored", function()
    local deleted, err
    helpers.record_processes(function()
      deleted, err = linux.delete()
    end, {
      respond = function()
        return { code = 0, stdout = "" }
      end,
    })

    assert.is_nil(deleted)
    assert.equals("no master key has been stored for this user yet", err)
  end)
end)

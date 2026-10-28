local macos = require("kvstore.keyring.macos")
local helpers = require("helpers")

local KEY = string.rep("K", 32)
local ENCODED = vim.base64.encode(KEY)

describe("keyring.macos", function()
  it("is named after its system", function()
    assert.equals("macos", macos.name)
  end)

  it("applies only on macos and only when security is installed", function()
    helpers.with_has({ mac = 1 }, function()
      helpers.record_processes(function()
        assert.is_true(macos.detect())
      end, {
        executable = function()
          return 1
        end,
      })

      helpers.record_processes(function()
        assert.is_false(macos.detect())
      end, {
        executable = function()
          return 0
        end,
      })
    end)

    helpers.with_has({ mac = 0 }, function()
      helpers.record_processes(function()
        assert.is_false(macos.detect())
      end)
    end)
  end)
end)

describe("keyring.macos get", function()
  it("asks the keychain for the password and decodes it", function()
    local key
    local calls = helpers.record_processes(function()
      key = macos.get()
    end, {
      respond = function()
        return { code = 0, stdout = ENCODED .. "\n" }
      end,
    })

    assert.equals(KEY, key)
    assert.same({
      "security",
      "find-generic-password",
      "-s",
      "kvstore",
      "-a",
      os.getenv("USER") or "kvstore",
      "-w",
    }, calls[1].command)
  end)

  it("reports what the keychain said when it fails", function()
    local key, err
    helpers.record_processes(function()
      key, err = macos.get()
    end, {
      respond = function()
        return { code = 44, stderr = "The specified item could not be found." }
      end,
    })

    assert.is_nil(key)
    assert.equals("security failed: The specified item could not be found.", err)
  end)

  it("reports an empty password", function()
    local key, err
    helpers.record_processes(function()
      key, err = macos.get()
    end, {
      respond = function()
        return { code = 0, stdout = "\n" }
      end,
    })

    assert.is_nil(key)
    assert.equals("the keychain returned an empty master key", err)
  end)

  it("reports a password that is not base64", function()
    local key, err
    helpers.record_processes(function()
      key, err = macos.get()
    end, {
      respond = function()
        return { code = 0, stdout = "not!base64!" }
      end,
    })

    assert.is_nil(key)
    assert.equals("the master key in the keychain is not readable", err)
  end)
end)

describe("keyring.macos set", function()
  it("drives the interactive mode so the key stays out of the argument list", function()
    local stored
    local calls = helpers.record_processes(function()
      stored = macos.set(KEY)
    end)

    assert.is_true(stored)
    assert.same({ "security", "-i" }, calls[1].command)
    assert.truthy(calls[1].options.stdin:find("add-generic-password", 1, true))
    assert.truthy(calls[1].options.stdin:find(ENCODED, 1, true))
  end)

  it("never puts the key in an argument or in the environment", function()
    local calls = helpers.record_processes(function()
      macos.set(KEY)
    end)

    assert.is_false(helpers.leaked(calls, ENCODED))
    assert.is_false(helpers.leaked(calls, KEY))
  end)

  it("propagates a failure", function()
    local stored, err
    helpers.record_processes(function()
      stored, err = macos.set(KEY)
    end, {
      respond = function()
        return { code = 1, stderr = "User interaction is not allowed." }
      end,
    })

    assert.is_nil(stored)
    assert.equals("security failed: User interaction is not allowed.", err)
  end)
end)

describe("keyring.macos exists and delete", function()
  it("reports presence from the exit code", function()
    helpers.record_processes(function()
      assert.is_true(macos.exists())
    end)

    helpers.record_processes(function()
      assert.is_false(macos.exists())
    end, {
      respond = function()
        return { code = 44 }
      end,
    })
  end)

  it("deletes the keychain item", function()
    local deleted
    local calls = helpers.record_processes(function()
      deleted = macos.delete()
    end)

    assert.is_true(deleted)
    assert.same({
      "security",
      "delete-generic-password",
      "-s",
      "kvstore",
      "-a",
      os.getenv("USER") or "kvstore",
    }, calls[1].command)
  end)

  it("propagates a delete failure", function()
    local deleted, err
    helpers.record_processes(function()
      deleted, err = macos.delete()
    end, {
      respond = function()
        return { code = 44, stderr = "not found" }
      end,
    })

    assert.is_nil(deleted)
    assert.equals("security failed: not found", err)
  end)
end)

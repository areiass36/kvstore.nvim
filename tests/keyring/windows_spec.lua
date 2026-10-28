local windows = require("kvstore.keyring.windows")
local helpers = require("helpers")

local KEY = string.rep("W", 32)
local ENCODED = vim.base64.encode(KEY)

-- Stands in for DPAPI by echoing back whatever the script was given, so protect
-- and unprotect become the identity and a real round-trip can be tested.
local function identity_dpapi(_, options)
  return { code = 0, stdout = options.stdin:match("FromBase64String%('([^']*)'%)") }
end

describe("keyring.windows", function()
  local restore

  before_each(function()
    restore = helpers.redirect_data_directory()
  end)

  after_each(function()
    restore()
  end)

  it("is named after its system and keeps the blob beside the vault", function()
    assert.equals("windows", windows.name)
    assert.equals("master.dpapi", vim.fs.basename(windows.blob_path()))
    assert.truthy(windows.blob_path():find("kvstore", 1, true))
  end)

  it("applies only on windows and only when powershell is installed", function()
    helpers.with_has({ win32 = 1 }, function()
      helpers.record_processes(function()
        assert.is_true(windows.detect())
      end, {
        executable = function()
          return 1
        end,
      })

      helpers.record_processes(function()
        assert.is_false(windows.detect())
      end, {
        executable = function()
          return 0
        end,
      })
    end)

    helpers.with_has({ win32 = 0 }, function()
      helpers.record_processes(function()
        assert.is_false(windows.detect())
      end)
    end)
  end)

  it("protects the key through powershell and writes the blob itself", function()
    local stored
    local calls = helpers.record_processes(function()
      stored = windows.set(KEY)
    end, { respond = identity_dpapi })

    assert.is_true(stored)
    assert.same({
      "powershell.exe",
      "-NoProfile",
      "-NonInteractive",
      "-NoLogo",
      "-Command",
      "-",
    }, calls[1].command)
    assert.truthy(calls[1].options.stdin:find("ProtectedData%]::Protect"))
    assert.truthy(windows.exists())
  end)

  it("never puts the key in an argument or in the environment", function()
    local calls = helpers.record_processes(function()
      windows.set(KEY)
    end, { respond = identity_dpapi })

    assert.is_false(helpers.leaked(calls, ENCODED))
    assert.is_false(helpers.leaked(calls, KEY))
    assert.truthy(calls[1].options.stdin:find(ENCODED, 1, true))
  end)

  it("round-trips the key through the blob file", function()
    local key
    helpers.record_processes(function()
      assert.is_true(windows.set(KEY))
      key = windows.get()
    end, { respond = identity_dpapi })

    assert.equals(KEY, key)
  end)

  it("reports a missing blob rather than asking powershell", function()
    local key, err
    local calls = helpers.record_processes(function()
      key, err = windows.get()
    end, { respond = identity_dpapi })

    assert.is_nil(key)
    assert.equals("no master key has been stored for this user yet", err)
    assert.same({}, calls)
  end)

  it("reports a blob that powershell cannot unprotect", function()
    local key, err
    helpers.record_processes(function()
      assert.is_true(windows.set(KEY))
    end, { respond = identity_dpapi })

    helpers.record_processes(function()
      key, err = windows.get()
    end, {
      respond = function()
        return { code = 1, stderr = "Key not valid for use in specified state." }
      end,
    })

    assert.is_nil(key)
    assert.equals("powershell.exe failed: Key not valid for use in specified state.", err)
  end)

  it("reports presence and deletes the blob", function()
    assert.is_false(windows.exists())

    local deleted, err = windows.delete()
    assert.is_nil(deleted)
    assert.equals("no master key has been stored for this user yet", err)

    helpers.record_processes(function()
      windows.set(KEY)
    end, { respond = identity_dpapi })

    assert.is_true(windows.exists())
    assert.is_true(windows.delete())
    assert.is_false(windows.exists())
  end)
end)

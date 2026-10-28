local windows = require("kvstore.keyring.windows")
local wsl = require("kvstore.keyring.wsl")
local helpers = require("helpers")

local KEY = string.rep("L", 32)

local function identity_dpapi(_, options)
  return { code = 0, stdout = options.stdin:match("FromBase64String%('([^']*)'%)") }
end

describe("keyring.wsl", function()
  local restore

  before_each(function()
    restore = helpers.redirect_data_directory()
  end)

  after_each(function()
    restore()
  end)

  it("is a separate backend from the windows one", function()
    assert.equals("wsl", wsl.name)
    assert.equals("windows", windows.name)
    assert.are_not.equals(windows.detect, wsl.detect)
  end)

  it("applies only inside wsl and only when the interop binary is reachable", function()
    helpers.with_env({ WSL_DISTRO_NAME = "Ubuntu" }, function()
      helpers.record_processes(function()
        assert.is_true(wsl.detect())
      end, {
        executable = function()
          return 1
        end,
      })

      helpers.record_processes(function()
        assert.is_false(wsl.detect())
      end, {
        executable = function()
          return 0
        end,
      })
    end)

    helpers.with_env({ WSL_DISTRO_NAME = false }, function()
      helpers.record_processes(function()
        assert.is_false(wsl.detect())
      end)
    end)
  end)

  it("reaches dpapi through the interop binary", function()
    local calls = helpers.record_processes(function()
      wsl.set(KEY)
    end, { respond = identity_dpapi })

    assert.equals("powershell.exe", calls[1].command[1])
    assert.same({ "-NoProfile", "-NonInteractive", "-NoLogo", "-Command", "-" }, {
      calls[1].command[2],
      calls[1].command[3],
      calls[1].command[4],
      calls[1].command[5],
      calls[1].command[6],
    })
  end)

  it("round-trips the key without any path translation", function()
    local key
    helpers.record_processes(function()
      assert.is_true(wsl.set(KEY))
      key = wsl.get()
    end, { respond = identity_dpapi })

    assert.equals(KEY, key)
  end)

  it("does not take its executable from the windows backend", function()
    local original = windows.executable
    windows.executable = "should-not-be-used.exe"

    local calls = helpers.record_processes(function()
      wsl.set(KEY)
    end, { respond = identity_dpapi })

    windows.executable = original
    assert.equals("powershell.exe", calls[1].command[1])
  end)
end)

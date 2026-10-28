local process = require("kvstore.process")
local helpers = require("helpers")

describe("process.run", function()
  it("requires a non-empty argument list", function()
    assert.has_error(function()
      process.run("echo hello")
    end, "a command is a non-empty argument list")

    assert.has_error(function()
      process.run({})
    end, "a command is a non-empty argument list")
  end)

  it("reports a tool that is not installed", function()
    local output, err
    helpers.record_processes(function()
      output, err = process.run({ "definitely-not-installed", "--version" })
    end, {
      executable = function()
        return 0
      end,
    })

    assert.is_nil(output)
    assert.equals("definitely-not-installed was not found on this system", err)
  end)

  it("does not start a process when the tool is missing", function()
    local calls = helpers.record_processes(function()
      process.run({ "absent" })
    end, {
      executable = function()
        return 0
      end,
    })

    assert.same({}, calls)
  end)

  it("returns stdout on success", function()
    local output
    helpers.record_processes(function()
      output = process.run({ "tool", "argument" })
    end, {
      respond = function()
        return { code = 0, stdout = "the output" }
      end,
    })

    assert.equals("the output", output)
  end)

  it("passes the command as a list and never as a shell string", function()
    local calls = helpers.record_processes(function()
      process.run({ "tool", "--flag", "value" })
    end)

    assert.equals(1, #calls)
    assert.equals("vim.system", calls[1].how)
    assert.same({ "tool", "--flag", "value" }, calls[1].command)
  end)

  it("sets no environment for the child", function()
    local calls = helpers.record_processes(function()
      process.run({ "tool" }, { stdin = "a secret" })
    end)

    assert.is_nil(calls[1].options.env)
  end)

  it("hands a secret to the child on stdin", function()
    local calls = helpers.record_processes(function()
      process.run({ "tool", "store" }, { stdin = "the-secret" })
    end)

    assert.equals("the-secret", calls[1].options.stdin)
    assert.is_false(helpers.leaked(calls, "the-secret"))
  end)

  it("reports a failing exit code with the message from the tool", function()
    local output, err
    helpers.record_processes(function()
      output, err = process.run({ "tool" })
    end, {
      respond = function()
        return { code = 1, stderr = "the keystore is locked\n" }
      end,
    })

    assert.is_nil(output)
    assert.equals("tool failed: the keystore is locked", err)
  end)

  it("reports the exit code when the tool says nothing", function()
    local output, err
    helpers.record_processes(function()
      output, err = process.run({ "tool" })
    end, {
      respond = function()
        return { code = 3, stderr = "" }
      end,
    })

    assert.is_nil(output)
    assert.equals("tool failed: exit code 3", err)
  end)

  it("removes the stdin from a message the tool quotes back", function()
    local output, err
    helpers.record_processes(function()
      output, err = process.run({ "tool" }, { stdin = "add-password -w hunter2\n" })
    end, {
      respond = function()
        return { code = 1, stderr = "unknown command: add-password -w hunter2" }
      end,
    })

    assert.is_nil(output)
    assert.is_nil(err:find("hunter2", 1, true))
    assert.truthy(err:find("[redacted]", 1, true))
  end)

  it("reports a process that cannot be started at all", function()
    local original = vim.system
    vim.system = function()
      error("spawn failed")
    end
    local original_executable = vim.fn.executable
    vim.fn.executable = function()
      return 1
    end

    local output, err = process.run({ "tool" }, { stdin = "hunter2" })

    vim.system = original
    vim.fn.executable = original_executable

    assert.is_nil(output)
    assert.truthy(err:find("could not be started", 1, true))
    assert.is_nil(err:find("hunter2", 1, true))
  end)
end)

describe("process.redact", function()
  it("leaves a message alone when there is no secret", function()
    assert.equals("all fine", process.redact("all fine", nil))
    assert.equals("all fine", process.redact("all fine", ""))
  end)

  it("removes every occurrence", function()
    assert.equals("[redacted] and [redacted]", process.redact("hunter2 and hunter2", "hunter2"))
  end)

  it("removes the secret without its trailing newline too", function()
    assert.equals("saw [redacted] here", process.redact("saw hunter2 here", "hunter2\n"))
  end)
end)

describe("process.available", function()
  it("asks neovim whether the tool is executable", function()
    helpers.record_processes(function()
      assert.is_true(process.available("anything"))
    end, {
      executable = function()
        return 1
      end,
    })

    helpers.record_processes(function()
      assert.is_false(process.available("anything"))
    end, {
      executable = function()
        return 0
      end,
    })
  end)
end)

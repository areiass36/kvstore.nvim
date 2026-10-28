local keyring = require("kvstore.keyring")
local crypto = require("kvstore.crypto")
local helpers = require("helpers")

local KEY = string.rep("R", 32)

local function with_detection(answers, fn)
  local saved = {}
  for _, name in ipairs(keyring.ORDER) do
    local backend = keyring.backend(name)
    saved[name] = backend.detect
    backend.detect = function()
      return answers[name] == true
    end
  end

  local ok, err = pcall(fn)

  for _, name in ipairs(keyring.ORDER) do
    keyring.backend(name).detect = saved[name]
  end

  if not ok then
    error(err, 0)
  end
end

local function fake_backend(overrides)
  local backend = {
    name = "fake",
    stored = nil,
    detect = function()
      return true
    end,
  }
  backend.exists = function()
    return backend.stored ~= nil
  end
  backend.get = function()
    return backend.stored
  end
  backend.set = function(key)
    backend.stored = key
    return true
  end
  backend.delete = function()
    backend.stored = nil
    return true
  end

  -- Applied onto the same table, so the closures above see the overrides.
  for member, value in pairs(overrides or {}) do
    backend[member] = value
  end
  return backend
end

describe("keyring", function()
  it("tries the backends in the documented order", function()
    assert.same({ "macos", "windows", "wsl", "linux", "file" }, keyring.ORDER)
  end)

  it("gives every backend the same interface", function()
    for _, name in ipairs(keyring.ORDER) do
      local backend = assert(keyring.backend(name), name .. " does not load")
      assert.equals(name, backend.name)
      for _, member in ipairs({ "detect", "get", "set", "exists", "delete" }) do
        assert.is_function(backend[member], name .. " is missing " .. member)
      end
    end
  end)

  it("rejects a backend that does not exist", function()
    local backend, err = keyring.backend("telepathy")

    assert.is_nil(backend)
    assert.equals("there is no keystore backend named 'telepathy'", err)
  end)

  it("picks the first backend that applies", function()
    with_detection({ linux = true, file = true }, function()
      assert.equals("linux", keyring.detect().name)
    end)

    with_detection({ wsl = true, linux = true }, function()
      assert.equals("wsl", keyring.detect().name)
    end)

    with_detection({ macos = true, windows = true, wsl = true, linux = true }, function()
      assert.equals("macos", keyring.detect().name)
    end)
  end)

  it("falls back to the file backend when nothing applies", function()
    with_detection({}, function()
      assert.equals("file", keyring.detect().name)
    end)
  end)

  it("lets no backend put the master key in an argument or in the environment", function()
    local sentinel = "SENTINEL" .. string.rep("s", 24)
    local encoded = vim.base64.encode(sentinel)
    local restore = helpers.redirect_data_directory()

    for _, name in ipairs(keyring.ORDER) do
      local backend = keyring.backend(name)
      local calls = helpers.record_processes(function()
        backend.set(sentinel)
        backend.get()
        backend.exists()
        backend.delete()
      end)

      local leaked_raw, raw_argument = helpers.leaked(calls, sentinel)
      local leaked_encoded, encoded_argument = helpers.leaked(calls, encoded)
      assert.is_false(leaked_raw, name .. " exposed the key in " .. tostring(raw_argument))
      assert.is_false(leaked_encoded, name .. " exposed the key in " .. tostring(encoded_argument))
    end

    restore()
  end)

  it("honours a forced backend and treats auto as detection", function()
    assert.equals("file", keyring.select("file").name)
    assert.equals("linux", keyring.select("linux").name)

    with_detection({ file = true }, function()
      assert.equals("file", keyring.select("auto").name)
      assert.equals("file", keyring.select(nil).name)
    end)
  end)
end)

describe("keyring.master_key", function()
  local original_backend

  before_each(function()
    original_backend = keyring.backend
  end)

  after_each(function()
    keyring.backend = original_backend
  end)

  local function serve(backend)
    keyring.backend = function(name)
      if name == "fake" then
        return backend
      end
      return original_backend(name)
    end
  end

  it("returns the key that is already stored", function()
    local backend = fake_backend({ stored = KEY })
    serve(backend)

    assert.equals(KEY, keyring.master_key({ backend = "fake" }))
  end)

  it("generates and stores a key of the right size on first use", function()
    local backend = fake_backend()
    serve(backend)

    local key = keyring.master_key({ backend = "fake" })

    assert.equals(crypto.KEY_BYTES, #key)
    assert.equals(key, backend.stored)
  end)

  it("generates a different key for a different user", function()
    local first = fake_backend()
    local second = fake_backend()

    serve(first)
    local one = keyring.master_key({ backend = "fake" })
    serve(second)
    local two = keyring.master_key({ backend = "fake" })

    assert.are_not.equals(one, two)
  end)

  it("propagates a backend that cannot store the key", function()
    serve(fake_backend({
      set = function()
        return nil, "the keystore is locked"
      end,
    }))

    local key, err = keyring.master_key({ backend = "fake" })
    assert.is_nil(key)
    assert.equals("the keystore is locked", err)
  end)

  it("propagates a backend that cannot read the key", function()
    serve(fake_backend({
      exists = function()
        return true
      end,
      get = function()
        return nil, "the keystore is unavailable"
      end,
    }))

    local key, err = keyring.master_key({ backend = "fake" })
    assert.is_nil(key)
    assert.equals("the keystore is unavailable", err)
  end)

  it("reports an unknown forced backend", function()
    local key, err = keyring.master_key({ backend = "telepathy" })

    assert.is_nil(key)
    assert.equals("there is no keystore backend named 'telepathy'", err)
  end)

  it("warns when the backend asks to warn", function()
    local warned = 0
    serve(fake_backend({
      stored = KEY,
      warn = function()
        warned = warned + 1
      end,
    }))

    keyring.master_key({ backend = "fake" })
    assert.equals(1, warned)
  end)

  it("starts no process of its own", function()
    local backend = fake_backend({ stored = KEY })
    serve(backend)

    local calls = helpers.record_processes(function()
      keyring.master_key({ backend = "fake" })
    end)

    assert.same({}, calls)
  end)
end)

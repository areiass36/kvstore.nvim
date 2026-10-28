local vault = require("kvstore.vault")
local crypto = require("kvstore.crypto")
local helpers = require("helpers")

local MASTER_KEY = string.rep("m", 32)
local OTHER_KEY = string.rep("o", 32)

local function temporary_path()
  local directory = vim.fn.tempname()
  return vim.fs.joinpath(vim.fs.normalize(directory), "kvstore", "vault.kvs")
end

local function new_vault(opts)
  opts = opts or {}
  return vault.new({
    path = opts.path or temporary_path(),
    master_key = opts.master_key or function()
      return MASTER_KEY
    end,
  })
end

local function read_raw(path)
  local fd = assert(vim.uv.fs_open(path, "r", 384))
  local stat = assert(vim.uv.fs_fstat(fd))
  local data = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  return data
end

local function write_raw(path, data)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local fd = assert(vim.uv.fs_open(path, "w", 384))
  vim.uv.fs_write(fd, data, 0)
  vim.uv.fs_close(fd)
end

describe("vault", function()
  it("requires a master key source", function()
    assert.has_error(function()
      vault.new({ path = temporary_path() })
    end, "a vault needs a master key source")
  end)

  it("puts the default vault in the neovim data directory", function()
    local path = vault.default_path()
    assert.equals("vault.kvs", vim.fs.basename(path))
    assert.truthy(path:find("kvstore", 1, true))
  end)
end)

describe("vault entries", function()
  it("reads as empty when the file does not exist", function()
    local store = new_vault()

    assert.same({}, store:entries())
    assert.is_nil(store:get("global:absent"))
    assert.is_false(store:exists("global:absent"))
    assert.same({}, store:list_names())
  end)

  it("round-trips a value", function()
    local store = new_vault()

    assert.is_true(store:set("global:token", "s3cr3t"))
    assert.equals("s3cr3t", store:get("global:token"))
    assert.is_true(store:exists("global:token"))
  end)

  it("creates the vault directory on the first write", function()
    local path = temporary_path()
    assert.equals(0, vim.fn.isdirectory(vim.fs.dirname(path)))

    assert.is_true(new_vault({ path = path }):set("global:a", "1"))
    assert.equals(1, vim.fn.isdirectory(vim.fs.dirname(path)))
  end)

  it("keeps several entries and overwrites one in place", function()
    local store = new_vault()
    store:set("global:a", "1")
    store:set("global:b", "2")
    store:set("global:a", "3")

    assert.equals("3", store:get("global:a"))
    assert.equals("2", store:get("global:b"))
    assert.same({ "global:a", "global:b" }, store:list_names())
  end)

  it("does not lose an entry written by another vault handle on the same file", function()
    local path = temporary_path()
    new_vault({ path = path }):set("global:first", "1")
    new_vault({ path = path }):set("global:second", "2")

    local reader = new_vault({ path = path })
    assert.equals("1", reader:get("global:first"))
    assert.equals("2", reader:get("global:second"))
  end)

  it("stores a value with awkward bytes unchanged", function()
    local store = new_vault()
    local awkward = 'a"b\\c\nd\te\0f{}[]:,ü€'

    store:set("global:awkward", awkward)
    assert.equals(awkward, store:get("global:awkward"))
  end)

  it("deletes an entry and reports a missing one", function()
    local store = new_vault()
    store:set("global:a", "1")

    assert.is_true(store:delete("global:a"))
    assert.is_false(store:exists("global:a"))

    local deleted, err = store:delete("global:a")
    assert.is_nil(deleted)
    assert.equals("the key does not exist", err)
  end)

  it("returns sorted names", function()
    local store = new_vault()
    store:set("global:zebra", "1")
    store:set("global:apple", "2")
    store:set("project:abc:mango", "3")

    assert.same({ "global:apple", "global:zebra", "project:abc:mango" }, store:list_names())
  end)
end)

describe("vault usable", function()
  it("confirms a reachable master key without returning it", function()
    assert.is_true(new_vault():usable())
  end)

  it("reports an unreachable master key even when no vault file exists", function()
    local store = new_vault({
      master_key = function()
        return nil, "the keystore is unavailable"
      end,
    })

    local usable, err = store:usable()
    assert.is_nil(usable)
    assert.equals("the keystore is unavailable", err)
    assert.same({}, store:entries())
  end)
end)

describe("vault master key handling", function()
  it("reaches the key source once however many operations one vault performs", function()
    local reads = 0
    local store = vault.new({
      path = temporary_path(),
      master_key = function()
        reads = reads + 1
        return MASTER_KEY
      end,
    })

    store:usable()
    store:set("global:a", "1")
    store:get("global:a")
    store:exists("global:a")
    store:list_names()
    store:delete("global:a")

    assert.equals(1, reads)
  end)

  it("reaches the key source again for a new vault", function()
    local reads = 0
    local path = temporary_path()
    local function source()
      reads = reads + 1
      return MASTER_KEY
    end

    vault.new({ path = path, master_key = source }):set("global:a", "1")
    vault.new({ path = path, master_key = source }):get("global:a")

    assert.equals(2, reads)
  end)

  it("does not hold on to a failure", function()
    local attempts = 0
    local store = vault.new({
      path = temporary_path(),
      master_key = function()
        attempts = attempts + 1
        if attempts == 1 then
          return nil, "the keystore is locked"
        end
        return MASTER_KEY
      end,
    })

    local usable, err = store:usable()
    assert.is_nil(usable)
    assert.equals("the keystore is locked", err)

    assert.is_true(store:usable())
    assert.is_true(store:set("global:a", "1"))
    assert.equals(2, attempts)
  end)
end)

describe("vault on disk", function()
  it("never writes the value or the key name in the clear", function()
    local path = temporary_path()
    new_vault({ path = path }):set("global:recognisable-name", "recognisable-value")
    local raw = read_raw(path)

    assert.is_nil(raw:find("recognisable-value", 1, true))
    assert.is_nil(raw:find("recognisable-name", 1, true))
    assert.is_nil(raw:find("entries", 1, true))
  end)

  it("writes the documented header and leaves no temporary file behind", function()
    local path = temporary_path()
    new_vault({ path = path }):set("global:a", "1")
    local raw = read_raw(path)

    assert.equals("KVST", raw:sub(1, 4))
    assert.equals(vault.FORMAT_VERSION, raw:byte(5))
    assert.is_true(#raw >= 5 + crypto.SALT_BYTES + crypto.TAG_BYTES)

    local leftovers = vim.fn.glob(vim.fs.dirname(path) .. "/*.tmp", false, true)
    assert.same({}, leftovers)
  end)

  it("uses a fresh salt on every write", function()
    local path = temporary_path()
    local store = new_vault({ path = path })

    store:set("global:a", "1")
    local first = read_raw(path)
    store:set("global:a", "1")
    local second = read_raw(path)

    assert.are_not.equals(first, second)
  end)

  it("restricts the vault to the owner where the system has file modes", function()
    if vim.fn.has("win32") == 1 then
      return
    end

    local path = temporary_path()
    new_vault({ path = path }):set("global:a", "1")

    local mode = assert(vim.uv.fs_stat(path)).mode % 512
    assert.equals(tonumber("600", 8), mode)
  end)
end)

describe("vault format", function()
  it("stamps the current version on every write", function()
    local path = temporary_path()
    new_vault({ path = path }):set("global:a", "1")

    assert.equals(2, read_raw(path):byte(5))
    assert.equals(2, vault.FORMAT_VERSION)
  end)

  it("reads a version 1 vault, whose values were all strings", function()
    local path = temporary_path()
    local header = "KVST" .. string.char(1)
    local payload = vim.json.encode({ entries = { ["global:legacy"] = "from-v1" } })
    write_raw(path, header .. crypto.seal(MASTER_KEY, payload, header))

    assert.equals("from-v1", new_vault({ path = path }):get("global:legacy"))
  end)

  it("migrates a version 1 vault to version 2 on the first write", function()
    local path = temporary_path()
    local header = "KVST" .. string.char(1)
    local payload = vim.json.encode({ entries = { ["global:legacy"] = "from-v1" } })
    write_raw(path, header .. crypto.seal(MASTER_KEY, payload, header))
    assert.equals(1, read_raw(path):byte(5))

    local store = new_vault({ path = path })
    assert.is_true(store:set("global:fresh", { added = true }))

    assert.equals(2, read_raw(path):byte(5))
    assert.equals("from-v1", store:get("global:legacy"))
    assert.same({ added = true }, store:get("global:fresh"))
  end)

  it("keeps the type of any value json can encode", function()
    local store = new_vault()
    local cases = {
      ["global:text"] = "a string",
      ["global:empty-text"] = "",
      ["global:count"] = 42,
      ["global:ratio"] = 4.5,
      ["global:yes"] = true,
      ["global:no"] = false,
      ["global:table"] = { a = 1, b = { "x", "y" } },
      ["global:list"] = { 1, 2, 3 },
      ["global:empty-table"] = {},
      ["global:null"] = vim.NIL,
    }

    for name, value in pairs(cases) do
      assert.is_true(store:set(name, value), name)
    end

    for name, value in pairs(cases) do
      assert.same(value, store:get(name), name)
    end

    assert.equals(42, store:get("global:count"))
    assert.equals("number", type(store:get("global:count")))
    assert.is_false(store:get("global:no"))
    assert.is_true(store:exists("global:null"))
  end)

  it("reports contents it cannot encode instead of writing them", function()
    local path = temporary_path()
    local store = new_vault({ path = path })
    store:set("global:a", "1")

    local written, err = store:set("global:bad", function() end)
    assert.is_nil(written)
    assert.truthy(err:find("could not be encoded", 1, true))

    assert.equals("1", new_vault({ path = path }):get("global:a"))
  end)
end)

describe("vault failures", function()
  it("reports a file that is not a vault", function()
    local path = temporary_path()
    write_raw(path, string.rep("not a vault at all", 10))

    local entries, err = new_vault({ path = path }):entries()
    assert.is_nil(entries)
    assert.truthy(err:find("is not a kvstore vault", 1, true))
  end)

  it("reports an unsupported format version", function()
    local path = temporary_path()
    write_raw(path, "KVST" .. string.char(99) .. string.rep("\0", 64))

    local entries, err = new_vault({ path = path }):entries()
    assert.is_nil(entries)
    assert.equals("the vault uses format version 99, which this plugin cannot read", err)
  end)

  it("reports a truncated vault", function()
    local path = temporary_path()
    write_raw(path, "KVST" .. string.char(1) .. string.rep("\0", 10))

    local entries, err = new_vault({ path = path }):entries()
    assert.is_nil(entries)
    assert.equals("the vault is corrupt: it is too short to hold a sealed payload", err)
  end)

  it("reports a flipped byte anywhere in the sealed payload", function()
    local path = temporary_path()
    new_vault({ path = path }):set("global:a", "1")
    local raw = read_raw(path)

    for index = 6, #raw do
      local corrupted = raw:sub(1, index - 1) .. string.char(bit.bxor(raw:byte(index), 0x01)) .. raw:sub(index + 1)
      write_raw(path, corrupted)

      local entries, err = new_vault({ path = path }):entries()
      assert.is_nil(entries, "a flipped bit at position " .. index .. " was accepted")
      assert.equals("the vault could not be opened: it is corrupt or the master key is wrong", err)
    end
  end)

  it("reports a wrong master key", function()
    local path = temporary_path()
    new_vault({ path = path }):set("global:a", "1")

    local store = new_vault({
      path = path,
      master_key = function()
        return OTHER_KEY
      end,
    })

    local entries, err = store:entries()
    assert.is_nil(entries)
    assert.equals("the vault could not be opened: it is corrupt or the master key is wrong", err)
  end)

  it("propagates a master key that cannot be reached", function()
    local path = temporary_path()
    new_vault({ path = path }):set("global:a", "1")

    local store = new_vault({
      path = path,
      master_key = function()
        return nil, "the keystore is unavailable"
      end,
    })

    local entries, err = store:entries()
    assert.is_nil(entries)
    assert.equals("the keystore is unavailable", err)

    local written, write_err = store:set("global:b", "2")
    assert.is_nil(written)
    assert.equals("the keystore is unavailable", write_err)
  end)
end)

describe("vault isolation", function()
  it("starts no process", function()
    local store = new_vault()
    local calls = helpers.record_processes(function()
      store:set("global:a", "1")
      store:get("global:a")
      store:exists("global:a")
      store:list_names()
      store:delete("global:a")
    end)

    assert.same({}, calls)
  end)
end)

describe("vault locking", function()
  it("refuses to write while another instance holds the lock", function()
    local path = temporary_path()
    local store = new_vault({ path = path })
    store:set("global:a", "1")
    write_raw(path .. ".lock", "")

    local written, err = store:set("global:b", "2")
    assert.is_nil(written)
    assert.equals("the vault is locked by another neovim instance", err)

    assert.is_nil(store:get("global:b"))
    assert.equals("1", store:get("global:a"))
  end)

  it("takes over a stale lock", function()
    local path = temporary_path()
    local store = new_vault({ path = path })
    store:set("global:a", "1")

    local lock = path .. ".lock"
    write_raw(lock, "")
    local long_ago = os.time() - 120
    assert(vim.uv.fs_utime(lock, long_ago, long_ago))

    assert.is_true(store:set("global:b", "2"))
    assert.equals("2", store:get("global:b"))
  end)

  it("releases the lock after a write and after a failed write", function()
    local path = temporary_path()
    local store = new_vault({ path = path })

    assert.is_true(store:set("global:a", "1"))
    assert.is_nil(vim.uv.fs_stat(path .. ".lock"))

    store:delete("global:absent")
    assert.is_nil(vim.uv.fs_stat(path .. ".lock"))
  end)

  it("does not take the lock to read", function()
    local path = temporary_path()
    local store = new_vault({ path = path })
    store:set("global:a", "1")
    write_raw(path .. ".lock", "")

    assert.equals("1", store:get("global:a"))
  end)
end)

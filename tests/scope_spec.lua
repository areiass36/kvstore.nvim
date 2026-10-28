local scope = require("kvstore.scope")

local function temporary_directory()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  return vim.fs.normalize(path)
end

describe("scope.validate_key", function()
  it("accepts letters, digits, dot, underscore and hyphen", function()
    for _, key in ipairs({ "token", "AWS_KEY", "api.key", "my-key", "k", "a1.b_c-d" }) do
      assert.equals(key, scope.validate_key(key))
    end
  end)

  it("accepts a key of the maximum length and rejects one byte more", function()
    local longest = string.rep("a", scope.MAX_KEY_LENGTH)
    assert.equals(longest, scope.validate_key(longest))

    local value, err = scope.validate_key(longest .. "a")
    assert.is_nil(value)
    assert.equals("a key name is at most 128 characters", err)
  end)

  it("rejects an empty key and a missing key", function()
    for _, key in ipairs({ "", nil }) do
      local value, err = scope.validate_key(key)
      assert.is_nil(value)
      assert.equals("a key name is required", err)
    end
  end)

  it("rejects a colon, which separates the fields of a stored name", function()
    local value, err = scope.validate_key("global:token")
    assert.is_nil(value)
    assert.equals("a key name may only contain letters, digits, '.', '_' and '-'", err)
  end)

  it("rejects whitespace, control characters and non-ascii", function()
    for _, key in ipairs({ "my key", "key\n", "key\0", "key\t", "chave-única", "ключ", "key/sub", "../key" }) do
      assert.is_nil(scope.validate_key(key), "accepted " .. vim.inspect(key))
    end
  end)
end)

describe("scope.prefix", function()
  it("is a literal prefix for the global scope", function()
    assert.equals("global:", scope.prefix({ global = true }))
  end)

  it("is the hash of the working directory for the project scope", function()
    local prefix = scope.prefix({})
    assert.equals("project:" .. vim.fn.sha256(scope.project_directory()) .. ":", prefix)
    assert.truthy(prefix:match("^project:%x+:$"))
  end)

  it("treats a missing options table as the project scope", function()
    assert.equals(scope.prefix({}), scope.prefix(nil))
  end)
end)

describe("scope.resolve", function()
  it("builds a global stored name", function()
    assert.equals("global:token", scope.resolve("token", { global = true }))
  end)

  it("builds a project stored name", function()
    assert.equals(scope.prefix({}) .. "token", scope.resolve("token", {}))
  end)

  it("keeps the two scopes apart for the same key", function()
    assert.are_not.equals(scope.resolve("token", { global = true }), scope.resolve("token", {}))
  end)

  it("propagates a key name error", function()
    local value, err = scope.resolve("bad key", {})
    assert.is_nil(value)
    assert.equals("a key name may only contain letters, digits, '.', '_' and '-'", err)
  end)
end)

describe("scope.project_directory", function()
  local original

  before_each(function()
    original = vim.uv.cwd()
  end)

  after_each(function()
    vim.uv.chdir(original)
  end)

  it("follows the working directory", function()
    local first = scope.project_directory()
    local other = temporary_directory()
    vim.uv.chdir(other)

    assert.are_not.equals(first, scope.project_directory())
  end)

  it("is stable across calls and free of a trailing separator", function()
    vim.uv.chdir(temporary_directory())
    local directory = scope.project_directory()

    assert.equals(directory, scope.project_directory())
    assert.is_nil(directory:match("/$"))
  end)

  it("resolves a symlinked directory to its real path", function()
    local real = temporary_directory()
    local link = vim.fn.tempname()
    if not vim.uv.fs_symlink(real, link, { dir = true, junction = true }) then
      -- Creating a link needs a privilege the test runner may not hold.
      return
    end

    vim.uv.chdir(real)
    local through_real = scope.project_directory()
    vim.uv.chdir(link)
    local through_link = scope.project_directory()

    assert.equals(through_real, through_link)
  end)

  it("hashes a differently cased path to the same project on windows", function()
    if vim.fn.has("win32") ~= 1 then
      return
    end

    local directory = temporary_directory()
    vim.uv.chdir(directory:lower())
    local lowered = scope.prefix({})
    vim.uv.chdir(directory:upper():gsub("/$", ""))
    local uppered = scope.prefix({})

    assert.equals(lowered, uppered)
  end)
end)

describe("scope.keys_in_scope", function()
  it("keeps only the names of the requested scope and strips the prefix", function()
    local project = scope.prefix({})
    local names = {
      "global:zebra",
      "global:apple",
      project .. "token",
      "project:" .. string.rep("f", 64) .. ":other-project-key",
    }

    assert.same({ "apple", "zebra" }, scope.keys_in_scope(names, { global = true }))
    assert.same({ "token" }, scope.keys_in_scope(names, {}))
  end)

  it("returns an empty list when nothing matches", function()
    assert.same({}, scope.keys_in_scope({}, { global = true }))
    assert.same({}, scope.keys_in_scope({ "global:a" }, {}))
  end)
end)

describe("scope.label", function()
  it("names the scope for a message", function()
    assert.equals("global", scope.label({ global = true }))
    assert.equals("project", scope.label({}))
    assert.equals("project", scope.label(nil))
  end)
end)

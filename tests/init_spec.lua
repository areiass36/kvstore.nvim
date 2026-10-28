local kvstore = require("kvstore")

describe("kvstore", function()
  it("exposes setup", function()
    assert.is_function(kvstore.setup)
  end)

  it("defaults the options to an empty table", function()
    kvstore.setup()
    assert.same({}, kvstore.options)
  end)
end)

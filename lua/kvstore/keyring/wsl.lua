local process = require("kvstore.process")
local windows = require("kvstore.keyring.windows")

local EXECUTABLE = "powershell.exe"

-- WSL reaches the Windows user's DPAPI through interop, so the mechanism is the
-- Windows one with a different detection rule.
return windows.new({
  name = "wsl",
  executable = EXECUTABLE,
  detect = function()
    return os.getenv("WSL_DISTRO_NAME") ~= nil and process.available(EXECUTABLE)
  end,
})

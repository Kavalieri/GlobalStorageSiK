-- Regression guard for additional terminals linked on upper/lower floors.
-- TerminalNetworkHeight is a maximum Z difference; 0 deliberately means
-- unlimited, while the configured maximum (20) must accept ordinary floors.
require = function() return nil end
GlobalStorageSiK = {}
SandboxVars = { GlobalStorageSiK = {
	TerminalNetworkRange = 40,
	TerminalNetworkHeight = 20,
} }

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_Sandbox.lua")

local anchor = { x = 100, y = 100, z = 0 }
assert(GlobalStorageSiK.Sandbox.getTerminalNetworkHeight() == 20,
	"configured terminal floor limit was not read")
assert(GlobalStorageSiK.Sandbox.isWithinNetworkRange(anchor, 100, 100, 1) == true,
	"first upper floor was rejected with the maximum configured limit")
assert(GlobalStorageSiK.Sandbox.isWithinNetworkRange(anchor, 100, 100, 20) == true,
	"inclusive maximum floor difference was rejected")
assert(GlobalStorageSiK.Sandbox.isWithinNetworkRange(anchor, 100, 100, 21) == false,
	"floor difference above the configured maximum was accepted")

SandboxVars.GlobalStorageSiK.TerminalNetworkHeight = 0
assert(GlobalStorageSiK.Sandbox.isWithinNetworkRange(anchor, 100, 100, 100) == true,
	"zero no longer means unlimited vertical coverage")
assert(GlobalStorageSiK.Sandbox.isWithinNetworkRange(anchor, 141, 100, 1) == false,
	"vertical coverage bypassed the independent horizontal range")

print("PASS terminal network height contract")

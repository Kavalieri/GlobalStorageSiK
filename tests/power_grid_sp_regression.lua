-- Regression coverage for SP building power and the Global Storage sandbox
-- override. B42 exposes municipal grid power separately from local effective
-- electricity, and either source must keep a network operational.

package.loaded["GS_Sandbox"] = true
package.loaded["GS_Network"] = true

GlobalStorageSiK = {
	Sandbox = {},
	Network = {},
}

local requiresPower = true
local controller = { x = 10, y = 20, z = 0 }
local live = {}
local squares = {}

GlobalStorageSiK.Sandbox.requiresPower = function() return requiresPower end
GlobalStorageSiK.Sandbox.enableBatteryCompat = function() return false end
GlobalStorageSiK.Sandbox.enableFuelConsumption = function() return false end
GlobalStorageSiK.Network.getRegistry = function()
	return { defaultNetworkId = "net", networks = { net = { controller = controller } } }
end
GlobalStorageSiK.Network.getLiveContainers = function() return live end

getCell = function()
	return { getGridSquare = function(_self, x, y, z)
		return squares[tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)]
	end }
end
SandboxVars = { GeneratorTileRange = 1, ElecShut = 2, ElecShutModifier = 14 }

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_Power.lua")

local function setSquare(x, y, z, grid, effective)
	squares[tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)] = {
		hasGridPower = function() return grid end,
		haveElectricity = function() return effective end,
	}
end

setSquare(10, 20, 0, true, false)
assert(GlobalStorageSiK.Power.networkPowered("net") == true,
	"municipal grid power must be accepted in SP even when haveElectricity is false")

setSquare(10, 20, 0, false, false)
setSquare(11, 20, 0, true, false)
assert(GlobalStorageSiK.Power.networkPowered("net") == true,
	"nearby building grid power must be accepted by the controller area scan")

squares = {}
setSquare(30, 40, 0, true, false)
live = { { object = { getSquare = function()
	return squares["30:40:0"]
end } } }
assert(GlobalStorageSiK.Power.networkPowered("net") == true,
	"a powered linked container must keep the network operational")

requiresPower = false
squares = {}
live = {}
assert(GlobalStorageSiK.Power.networkPowered("net") == true,
	"the Global Storage sandbox power requirement must bypass every world check")

requiresPower = true
SandboxVars.ElecShutModifier = -1
assert(GlobalStorageSiK.Power.networkPowered("net") == true,
	"vanilla never-shut-off modifier must keep the network operational")

print("power_grid_sp_regression: OK")

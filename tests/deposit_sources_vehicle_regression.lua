-- DEV32.3 regression harness. Run from GlobalStorageSiK-Repo:
-- lua51.exe tests/deposit_sources_vehicle_regression.lua
--
-- This protects the B42 vehicle-source contract without claiming an in-game
-- test: BaseVehicle itself is never an ItemContainer; accessible part
-- containers are collected individually and inaccessible parts stay out.

package.loaded["GS_Sandbox"] = true
package.loaded["GS_BulkFilters"] = true
package.loaded["GS_I18n"] = true
package.loaded["GS_Zones"] = true
package.loaded["GS_Network"] = true
package.loaded["GS_Utils"] = true

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected=" .. tostring(expected)
			.. " actual=" .. tostring(actual), 2)
	end
end

local function javaList(values)
	return {
		size = function() return #values end,
		get = function(_, index) return values[index + 1] end,
	}
end

instanceof = function(value, className)
	return value and value.className == className
end

local playerSquare = {
	getX = function() return 10 end,
	getY = function() return 20 end,
	getZ = function() return 0 end,
}
playerSquare.DistToProper = function(_, other) return other == playerSquare and 0 or 99 end

local function emptyObjects()
	return javaList({})
end
playerSquare.getObjects = emptyObjects
playerSquare.getSpecialObjects = emptyObjects

local function vehicleContainer(part)
	local container = {
		getParent = function() return part.vehicle end,
		getVehiclePart = function() return part end,
		isInCharacterInventory = function() return false end,
	}
	return container
end

local truckBed = { id = "TruckBed", index = 0 }
local lockedGlovebox = { id = "GloveBox", index = 1 }
truckBed.container = vehicleContainer(truckBed)
lockedGlovebox.container = vehicleContainer(lockedGlovebox)
for _, part in ipairs({ truckBed, lockedGlovebox }) do
	part.getIndex = function(self) return self.index end
	part.getItemContainer = function(self) return self.container end
end

local vehicle = {
	className = "BaseVehicle",
	getSquare = function() return playerSquare end,
	getPartCount = function() return 2 end,
	getPartByIndex = function(_, index)
		return ({ truckBed, lockedGlovebox })[index + 1]
	end,
	canAccessContainer = function(_, index)
		vehicleAccessCalls = (vehicleAccessCalls or 0) + 1
		return index == 0
	end,
}
truckBed.vehicle = vehicle
lockedGlovebox.vehicle = vehicle

local cell = {
	getGridSquare = function(_, x, y, z)
		if x == 10 and y == 20 and z == 0 then return playerSquare end
		return nil
	end,
	getVehicles = function() return { vehicle } end,
}
playerSquare.getCell = function() return cell end

local player = {
	getSquare = function() return playerSquare end,
	getVehicle = function() return nil end,
	getInventory = function() return nil end,
}

GlobalStorageSiK = {
	Sandbox = { getTerminalProximityRange = function() return 3 end },
	Zones = { getRegistry = function() return { nodes = {} } end },
	Network = {
		getRegistry = function() return { networks = {} } end,
		ensureRegistry = function() end,
	},
	Utils = {},
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_DepositSources.lua")

assertEqual(GlobalStorageSiK.DepositSources.canPlayerAccessContainer(player, truckBed.container), true,
	"accessible TruckBed must pass the per-part access check")
assertEqual(GlobalStorageSiK.DepositSources.canPlayerAccessContainer(player, lockedGlovebox.container), false,
	"locked GloveBox must fail the per-part access check")
local nearby = GlobalStorageSiK.DepositSources.collectNearbyContainers(player)
assertEqual(vehicleAccessCalls, 5, "scan must check each vehicle part and revalidate the accepted one")
assertEqual(#nearby, 1, "only the accessible vehicle part may be collected")
assertEqual(nearby[1], truckBed.container, "TruckBed must remain available")
assertEqual(nearby[1] == lockedGlovebox.container, false, "locked GloveBox must remain excluded")

-- Una clave de destino explícita jamás debe degradar a inventario principal.
-- El servidor consume este helper antes de retirar: acepta el TruckBed aún
-- accesible y rechaza cualquier contenedor que pertenezca a una red GS.
local sources = GlobalStorageSiK.DepositSources
local originalResolve = sources.resolveContainerKey
local originalNodeCheck = sources.isNetworkNodeContainer
sources.resolveContainerKey = function() return truckBed.container end
local resolved, reason = sources.resolveExternalTarget(player, "vehicle:10,20,0:TruckBed")
assertEqual(resolved, truckBed.container, "accessible vehicle target must resolve")
assertEqual(reason, nil, "accessible vehicle target must not report a reason")
sources.isNetworkNodeContainer = function() return true end
resolved, reason = sources.resolveExternalTarget(player, "vehicle:10,20,0:TruckBed")
assertEqual(resolved, nil, "any GS node target must be rejected")
assertEqual(reason, "network_node", "GS node rejection must be explicit")
sources.resolveContainerKey = originalResolve
sources.isNetworkNodeContainer = originalNodeCheck

print("deposit_sources_vehicle_regression: OK")

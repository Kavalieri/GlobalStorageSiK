-- Regression test for cooking-appliance exclusion. Run from repository root:
-- lua51.exe tests/container_eligibility_regression.lua

package.loaded["GS_Config"] = true
package.loaded["GS_Zones"] = true
package.loaded["GS_ZoneScanner"] = true
package.loaded["GS_Sandbox"] = true
package.loaded["GS_ZonePriority"] = true

GlobalStorageSiK = {
	Sandbox = {
		getMaxNodes = function() return 128 end,
	},
	Network = {
		containerRangeEnabled = function() return false end,
	},
	ZonePriority = {
		zoneArea = function() return 100 end,
	},
	I18n = {
		text = function(key) return key end,
	},
}

instanceof = function(obj, className)
	return obj and obj.className == className
end

local function mockContainer(containerType)
	return {
		getType = function() return containerType end,
	}
end

local function mockObject(className, containerType)
	local container = mockContainer(containerType)
	return {
		className = className,
		getContainerByIndex = function(_, index)
			if index == 0 then return container end
			return nil
		end,
		getContainer = function() return container end,
	}
end

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected=" .. tostring(expected)
			.. " actual=" .. tostring(actual), 2)
	end
end

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_Utils.lua")

local cookingClasses = { "IsoStove", "IsoBarbecue", "IsoFireplace" }
for i = 1, #cookingClasses do
	local eligible, reason = GlobalStorageSiK.Utils.isNetworkStorageContainer(
		mockObject(cookingClasses[i], "custom_modded_chamber"), 0)
	assertEqual(eligible, false, cookingClasses[i] .. " must be excluded")
	assertEqual(reason, "cooking", cookingClasses[i] .. " rejection reason")
end

local cookingTypes = {
	"stove", "woodstove", "oven", "microwave", "barbecue",
	"barbecuepropane", "fireplace", "campfire",
}
for i = 1, #cookingTypes do
	local eligible, reason = GlobalStorageSiK.Utils.isNetworkStorageContainer(
		mockObject("IsoObject", cookingTypes[i]), 0)
	assertEqual(eligible, false, cookingTypes[i] .. " must be excluded")
	assertEqual(reason, "cooking", cookingTypes[i] .. " rejection reason")
end

local storageTypes = { "crate", "counter", "fridge", "freezer" }
for i = 1, #storageTypes do
	local eligible, reason = GlobalStorageSiK.Utils.isNetworkStorageContainer(
		mockObject("IsoObject", storageTypes[i]), 0)
	assertEqual(eligible, true, storageTypes[i] .. " must remain valid storage")
	assertEqual(reason, nil, storageTypes[i] .. " must not have a rejection reason")
end

local eligible, reason = GlobalStorageSiK.Utils.isNetworkStorageContainer({}, 0)
assertEqual(eligible, false, "missing container must be rejected")
assertEqual(reason, "missing", "missing container must not be classified as cooking")

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_ZoneRefresh.lua")

local registry = {
	networks = {},
	zones = {},
	nodes = {
		oven_node = { id = "oven_node", zoneId = "zone_a" },
		crate_node = { id = "crate_node", zoneId = "zone_a" },
	},
}
local zone = { id = "zone_a", networkId = "network_a" }
local detected = {
	{
		id = "crate_node", zoneId = "zone_a", x = 1, y = 1, z = 0,
		name = "Crate", displayName = "Crate", enabled = true,
	},
}
local summary = GlobalStorageSiK.ZoneRefresh.mergeScanResults(
	registry, zone, detected, 100, true, { oven_node = true })

assertEqual(registry.nodes.oven_node, nil, "old cooking metadata must be removed")
assertEqual(registry.nodes.crate_node ~= nil, true, "normal storage metadata must remain")
assertEqual(summary.removedIneligible, 1, "removed cooking metadata count")
assertEqual(summary.offline, 0, "removed cooking node must not become offline")

print("container_eligibility_regression: OK")

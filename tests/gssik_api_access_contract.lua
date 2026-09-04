local repo = (... and ... ~= "") and ... or "."

local providers = {}
local generation = 0

GlobalStorageSiK = {
	AddonRegistry = {
		MAX_ADDONS = 32,
		_prepareDefinition = function() return false, "ERR_SCHEMA", nil end,
		_allocateGeneration = function() return 1 end,
		_commitPrepared = function() end,
		_removeIfGeneration = function() return false end,
		_count = function() return 0 end,
		_publicCopy = function(value) return value end,
		get = function() return nil end,
		listActive = function() return {} end,
	},
	DiskProgramming = {
		_prepareAddonProgram = function() return true, "OK", nil end,
		_commitAddonProgram = function() end,
		_removeAddonProgramIfGeneration = function() return false end,
	},
	TerminalAccess = {
		MAX_WIRELESS_PROVIDERS = 2,
		_wirelessProviders = providers,
		_prepareWirelessProvider = function(definition)
			if type(definition) ~= "table" or type(definition.id) ~= "string"
				or definition.id == "" or type(definition.hasAccess) ~= "function" then
				return false, "ERR_SCHEMA", nil
			end
			return true, "OK", { id = definition.id, hasAccess = definition.hasAccess }
		end,
		_allocateWirelessProviderGeneration = function()
			generation = generation + 1
			return generation
		end,
		_countWirelessProviders = function() return #providers end,
		_commitWirelessProvider = function(definition, currentGeneration)
			definition._gssikGeneration = currentGeneration
			for index = 1, #providers do
				if providers[index].id == definition.id then
					providers[index] = definition
					return
				end
			end
			providers[#providers + 1] = definition
		end,
		_removeWirelessProviderIfGeneration = function(id, currentGeneration)
			for index = 1, #providers do
				local current = providers[index]
				if current.id == id and current._gssikGeneration == currentGeneration then
					table.remove(providers, index)
					return true
				end
			end
			return false
		end,
	},
	Addons = {
		isInstalled = function(networkId, anchor, addonId)
			return networkId == "network" and anchor.x == 1 and addonId == "tablet"
		end,
		serializeForTerminal = function()
			return { tablet = { itemType = "Example.Antenna", nested = { tier = 3 } } }
		end,
	},
}

package.preload["GS_AddonRegistry"] = function() return GlobalStorageSiK.AddonRegistry end
package.preload["GS_DiskProgramming"] = function() return GlobalStorageSiK.DiskProgramming end
package.preload["GS_TerminalAccess"] = function() return GlobalStorageSiK.TerminalAccess end

dofile(repo .. "/GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GSSiK_API.lua")

local available, capabilityCode = GSSiK.API.Capabilities.has("Access", "1.0.0")
assert(available == true and capabilityCode == "OK", "Access capability must be negotiated")

local invalid, invalidCode = GSSiK.API.Access.registerProvider({ id = "tablet" })
assert(invalid == false and invalidCode == "ERR_SCHEMA", "invalid provider must be rejected")

local firstOk, firstCode, first = GSSiK.API.Access.registerProvider({
	id = "tablet",
	hasAccess = function() return true end,
})
assert(firstOk == true and firstCode == "OK" and first, "first provider registration failed")

local secondOk, secondCode, second = GSSiK.API.Access.registerProvider({
	id = "tablet",
	hasAccess = function() return false end,
})
assert(secondOk == true and secondCode == "OK" and second, "provider replacement failed")
assert(#providers == 1, "replacement must not duplicate provider")
assert(first:dispose() == false, "stale handle must not remove current provider generation")
assert(#providers == 1, "stale disposal removed current provider")
assert(second:dispose() == true and #providers == 0, "current provider disposal failed")
assert(second:dispose() == false, "provider disposal must be idempotent")

local installOk, installCode, installed = GSSiK.API.Installation.isInstalled(
	"network", { x = 1, y = 2, z = 0 }, "tablet"
)
assert(installOk == true and installCode == "OK" and installed == true,
	"installation state query failed")
local getOk, getCode, descriptor = GSSiK.API.Installation.get(
	"network", { x = 1, y = 2, z = 0 }, "tablet"
)
assert(getOk == true and getCode == "OK" and descriptor.nested.tier == 3,
	"installation descriptor query failed")
descriptor.nested.tier = 99
local _, _, fresh = GSSiK.API.Installation.get("network", { x = 1, y = 2, z = 0 }, "tablet")
assert(fresh.nested.tier == 3, "installation descriptor leaked internal mutable state")

print("gssik_api_access_contract: OK")

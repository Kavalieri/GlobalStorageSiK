-- GSSiK.API must finish publishing its namespace before product internals that
-- can require GS_Addons are loaded. This reproduces the PZ startup load order
-- that previously re-entered GSSiK_API through TerminalAccess.

local originalRequire = require
local required = {}

GlobalStorageSiK = {}

local definitions = {}
local registryGeneration = 0
GlobalStorageSiK.AddonRegistry = {
	MAX_ADDONS = 32,
	_prepareDefinition = function(definition)
		if type(definition) ~= "table" or type(definition.id) ~= "string" then
			return false, "ERR_SCHEMA", nil
		end
		return true, "OK", definition
	end,
	_allocateGeneration = function()
		registryGeneration = registryGeneration + 1
		return registryGeneration
	end,
	_commitPrepared = function(definition, generation)
		definition._generation = generation
		definitions[definition.id] = definition
	end,
	_removeIfGeneration = function(addonId, generation)
		local current = definitions[addonId]
		if not current or current._generation ~= generation then return false end
		definitions[addonId] = nil
		return true
	end,
	_count = function() return 0 end,
	_publicCopy = function(definition) return definition end,
	get = function(addonId) return definitions[addonId] end,
	listActive = function() return {} end,
}

local function installDiskContract()
	GlobalStorageSiK.DiskProgramming = {
		_prepareAddonProgram = function() return true, "OK", nil end,
		_commitAddonProgram = function() return true end,
		_removeAddonProgramIfGeneration = function() return false end,
	}
end

local function installAccessContract()
	GlobalStorageSiK.TerminalAccess = {
		MAX_WIRELESS_PROVIDERS = 8,
		_wirelessProviders = {},
		_prepareWirelessProvider = function(definition) return true, "OK", definition end,
		_allocateWirelessProviderGeneration = function() return 1 end,
		_countWirelessProviders = function() return 0 end,
		_commitWirelessProvider = function(definition, generation)
			definition._generation = generation
			GlobalStorageSiK.TerminalAccess._wirelessProviders[1] = definition
		end,
		_removeWirelessProviderIfGeneration = function() return true end,
	}
end

require = function(moduleName)
	required[#required + 1] = moduleName
	if moduleName == "GS_AddonRegistry" or moduleName == "GS_DebugRelay" then return true end
	if moduleName == "GS_DiskProgramming" then installDiskContract() return true end
	if moduleName == "GS_TerminalAccess" then installAccessContract() return true end
	error("unexpected require: " .. tostring(moduleName))
end

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GSSiK_API.lua")

assert(type(GSSiK) == "table" and type(GSSiK.API) == "table"
	and type(GSSiK.API.Addon.register) == "function",
	"public API must be complete after loading the facade")
assert(GlobalStorageSiK.DiskProgramming == nil and GlobalStorageSiK.TerminalAccess == nil,
	"facade load must not eagerly enter DiskProgramming or TerminalAccess")

local ok, code = GSSiK.API.Addon.register({
	id = "LoadOrderFixture",
	recipeNames = {},
})
assert(ok == true and code == "OK" and type(GlobalStorageSiK.DiskProgramming) == "table",
	"addon registration must resolve DiskProgramming lazily")
assert(GlobalStorageSiK.TerminalAccess == nil,
	"addon registration must not load the unrelated access subsystem")

local accessOk, accessCode = GSSiK.API.Access.registerProvider({ id = "fixture" })
assert(accessOk == true and accessCode == "OK" and type(GlobalStorageSiK.TerminalAccess) == "table",
	"access registration must resolve TerminalAccess lazily")

require = originalRequire
print("gssik_api_lazy_dependency_regression: OK")

-- Real Core API integration for all three official addon registration files.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

for _, moduleName in ipairs({
	"GS_Config", "GS_CraftUtils", "GS_Sandbox", "GS_InventorySync",
	"GS_TerminalAccess", "GS_AddonRegistry", "GS_DiskProgramming", "GSSiK_API",
}) do
	package.loaded[moduleName] = true
end

GlobalStorageSiK = {
	CraftUtils = {},
	Sandbox = {},
	TerminalAccess = {},
}
SandboxVars = {
	GlobalStorageSiK = { RequireRecipeBooks = true },
	GSSiK_Addon_Craft = {},
	GSSiK_Addon_Builder = {},
	GSSiK_Addon_Tablet = {},
}

local loggerNamespaces = {
	GSSiK_Addon_Craft_Log = "GSSiK_Addon_Craft",
	GSSiK_Addon_Builder_Log = "GSSiK_Addon_Builder",
	GSSiK_Addon_Tablet_Log = "GSSiK_Addon_Tablet",
}
for moduleName, namespace in pairs(loggerNamespaces) do
	package.preload[moduleName] = function()
		_G[namespace] = _G[namespace] or {}
		_G[namespace].Log = { debug = function() end }
		return _G[namespace].Log
	end
end

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(shared .. "GS_AddonRegistry.lua")
dofile(shared .. "GS_DiskProgramming.lua")
dofile(shared .. "GSSiK_API.lua")

local registerFiles = {
	"addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/media/lua/shared/GSSiK_Addon_Craft_Register.lua",
	"addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/media/lua/shared/GSSiK_Addon_Builder_Register.lua",
	"addons/GSSiK_Addon_Tablet/Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/GSSiK_Addon_Tablet_Register.lua",
}
for index = 1, #registerFiles do dofile(registerFiles[index]) end

local expected = {
	Craft = { programId = "craft", output = "GSSiK_Addon_Craft.GS_FloppyDisk_Craft" },
	Builder = { programId = "builder", output = "GSSiK_Addon_Builder.GS_FloppyDisk_Builder" },
	TabletLink = { programId = "tablet", output = "GSSiK_Addon_Tablet.GS_FloppyDisk_Tablet" },
}

for addonId, contract in pairs(expected) do
	local definition = GlobalStorageSiK.AddonRegistry.get(addonId)
	local program = GlobalStorageSiK.DiskProgramming.PROGRAMS[contract.programId]
	assert(definition ~= nil, addonId .. " was not committed to the real registry")
	assert(program ~= nil, addonId .. " disk program was not committed atomically")
	assert(program.outputItem == contract.output and definition.installDiskItem == contract.output,
		addonId .. " disk output/install item contract diverged")
	assert(definition._generation
		== GlobalStorageSiK.DiskProgramming._programGenerations[contract.programId],
		addonId .. " addon/program generations diverged")
	assert(type(definition.resolveRecipeBookRequirement) == "function",
		addonId .. " resolver was not retained internally")
	local publicOk, publicCode, publicDefinition = GSSiK.API.Addon.get(addonId)
	assert(publicOk == true and publicCode == "OK",
		addonId .. " is not visible through the public query")
	assert(publicDefinition.resolveRecipeBookRequirement == nil,
		addonId .. " public descriptor leaked its executable resolver")
end

local activeOk, activeCode, active = GSSiK.API.Addon.listActive()
assert(activeOk == true and activeCode == "OK" and #active == 3,
	"public active list must contain the three official addons")

print("gssik_api_official_addon_integration_regression: OK")

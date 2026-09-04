-- Official Craft/Builder/Tablet registration migration contract.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

package.loaded["GSSiK_API"] = true

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

local cases = {
	{
		name = "Craft",
		path = "addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/media/lua/shared/GSSiK_Addon_Craft_Register.lua",
		id = "Craft",
		programId = "craft",
		programRecipe = "Program GS Craft Install Disk",
		installDisk = "GSSiK_Addon_Craft.GS_FloppyDisk_Craft",
		sandboxGroup = "GSSiK_Addon_Craft",
		localRecipe = "Build GS 3D Printer",
		localOption = "Recipe_Printer3D_RequireBook",
	},
	{
		name = "Builder",
		path = "addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/media/lua/shared/GSSiK_Addon_Builder_Register.lua",
		id = "Builder",
		programId = "builder",
		programRecipe = "Program GS Builder Install Disk",
		installDisk = "GSSiK_Addon_Builder.GS_FloppyDisk_Builder",
		sandboxGroup = "GSSiK_Addon_Builder",
		localRecipe = "Build GS Digital Whiteboard",
		localOption = "Recipe_DigitalWhiteboard_RequireBook",
	},
	{
		name = "Tablet",
		path = "addons/GSSiK_Addon_Tablet/Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/GSSiK_Addon_Tablet_Register.lua",
		id = "TabletLink",
		programId = "tablet",
		programRecipe = "Program GS Tablet Install Disk",
		installDisk = "GSSiK_Addon_Tablet.GS_FloppyDisk_Tablet",
		sandboxGroup = "GSSiK_Addon_Tablet",
		localRecipe = "Build GS WiFi Antenna",
		localOption = "Recipe_WifiAntenna_RequireBook",
	},
}

local function readFile(path)
	local handle = assert(io.open(path, "rb"))
	local source = handle:read("*a")
	handle:close()
	return source
end

local function contains(values, expected)
	for index = 1, #values do
		if values[index] == expected then return true end
	end
	return false
end

for index = 1, #cases do
	local fixture = cases[index]
	local calls = 0
	local captured = nil
	GSSiK = {
		API = {
			Addon = {
				register = function(definition)
					calls = calls + 1
					captured = definition
					return true, "OK", { id = definition.id }
				end,
			},
		},
	}
	SandboxVars = {
		GlobalStorageSiK = { RequireRecipeBooks = true },
		[fixture.sandboxGroup] = {},
	}
	local reconciler = nil
	Events = {
		OnGameStart = { Add = function(handler) reconciler = handler end },
	}

	dofile(fixture.path)
	assert(calls == 1, fixture.name .. " must perform one aggregate registration call")
	assert(type(reconciler) == "function",
		fixture.name .. " must reconcile registration after client startup")
	reconciler()
	assert(calls == 2, fixture.name .. " startup reconciliation must use the public registration API")
	assert(captured.id == fixture.id, fixture.name .. " addon ID changed")
	assert(type(captured.diskProgram) == "table",
		fixture.name .. " must include diskProgram in the aggregate definition")
	assert(captured.diskProgram.id == fixture.programId,
		fixture.name .. " disk program ID changed")
	assert(captured.diskProgram.recipeName == fixture.programRecipe,
		fixture.name .. " disk recipe changed")
	assert(captured.diskProgram.outputItem == fixture.installDisk,
		fixture.name .. " disk output must match installDiskItem")
	assert(captured.installDiskItem == fixture.installDisk,
		fixture.name .. " install disk changed")
	assert(contains(captured.recipeNames, fixture.programRecipe),
		fixture.name .. " disk recipe must remain declared in recipeNames")

	local resolver = captured.resolveRecipeBookRequirement
	assert(type(resolver) == "function", fixture.name .. " resolver must remain addon-owned")
	SandboxVars[fixture.sandboxGroup][fixture.localOption] = false
	assert(resolver(fixture.localRecipe) == false,
		fixture.name .. " local false override must win")
	SandboxVars[fixture.sandboxGroup][fixture.localOption] = true
	assert(resolver(fixture.localRecipe) == true,
		fixture.name .. " local true override must win")
	SandboxVars[fixture.sandboxGroup][fixture.localOption] = nil
	assert(resolver(fixture.localRecipe) == nil,
		fixture.name .. " must abstain when no addon-owned override exists")
	assert(resolver("Unknown recipe") == nil,
		fixture.name .. " unknown recipes must abstain for the Core fallback")

	local source = readFile(fixture.path)
	assert(source:find('require "GSSiK_API"', 1, true),
		fixture.name .. " must require the public product API")
	assert(not source:find('require "GS_AddonRegistry"', 1, true),
		fixture.name .. " still imports AddonRegistry internals")
	assert(not source:find('require "GS_DiskProgramming"', 1, true),
		fixture.name .. " still imports DiskProgramming internals")
	assert(not source:find('require "GS_Sandbox"', 1, true),
		fixture.name .. " still imports Core sandbox internals")
	assert(not source:find("GlobalStorageSiK.AddonRegistry", 1, true),
		fixture.name .. " still calls AddonRegistry internals")
	assert(not source:find("GlobalStorageSiK.DiskProgramming", 1, true),
		fixture.name .. " still calls DiskProgramming internals")
	assert(not source:find("SandboxVars.GlobalStorageSiK", 1, true),
		fixture.name .. " still reads Core-owned sandbox state")
	assert(source:find("Events.OnGameStart", 1, true),
		fixture.name .. " must declare a post-startup public registration reconciliation")

	local modInfoPath = fixture.path:gsub("media/lua/shared/[^/]+$", "mod.info")
	local modInfo = readFile(modInfoPath)
	assert(modInfo:find("require=SiKUIFramework,GlobalStorageSiK", 1, true),
		fixture.name .. " must declare the framework and Core dependencies")

	GSSiK.API.Addon.register = function()
		return false, "ERR_FIXTURE", nil
	end
	local failureOk, failure = pcall(dofile, fixture.path)
	assert(failureOk == false and tostring(failure):find("ERR_FIXTURE", 1, true),
		fixture.name .. " registration failure must stop load with the stable code")
end

print("gssik_api_official_addon_registration_regression: OK")

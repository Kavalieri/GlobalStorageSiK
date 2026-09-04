-- Addon diagnostics must distinguish an activated ModID from a definition
-- that actually reached the public registry. Run from GlobalStorageSiK-Repo.

for _, moduleName in ipairs({
	"GS_Config", "GS_CraftUtils", "GS_Sandbox", "GS_InventorySync",
	"GS_TerminalAccess", "GS_AddonRegistry", "GS_DiskProgramming", "GSSiK_API",
}) do package.loaded[moduleName] = true end

GlobalStorageSiK = { CraftUtils = {}, Sandbox = {}, TerminalAccess = {} }
SandboxVars = {
	GlobalStorageSiK = { RequireRecipeBooks = true },
	GSSiK_Addon_Craft = {}, GSSiK_Addon_Builder = {}, GSSiK_Addon_Tablet = {},
}
Events = { OnGameStart = { Add = function() end } }

for moduleName, namespace in pairs({
	GSSiK_Addon_Craft_Log = "GSSiK_Addon_Craft",
	GSSiK_Addon_Builder_Log = "GSSiK_Addon_Builder",
	GSSiK_Addon_Tablet_Log = "GSSiK_Addon_Tablet",
}) do
	package.preload[moduleName] = function()
		_G[namespace] = _G[namespace] or {}
		_G[namespace].Log = { debug = function() end }
		return _G[namespace].Log
	end
end

local activated = {
	"GlobalStorageSiK", "GSSiK_Addon_Craft", "GSSiK_Addon_Builder",
	"GSSiK_Addon_Tablet",
}
function getActivatedMods()
	return {
		size = function() return #activated end,
		get = function(_, index) return activated[index + 1] end,
	}
end

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(shared .. "GS_AddonRegistry.lua")
dofile(shared .. "GS_DiskProgramming.lua")
dofile(shared .. "GSSiK_API.lua")

local registrations = {
	"addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/media/lua/shared/GSSiK_Addon_Craft_Register.lua",
	"addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/media/lua/shared/GSSiK_Addon_Builder_Register.lua",
	"addons/GSSiK_Addon_Tablet/Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/GSSiK_Addon_Tablet_Register.lua",
}

dofile(registrations[1])
dofile(registrations[2])
local ok, code, snapshot = GSSiK.API.Addon.diagnose()
assert(ok == true and code == "OK", "diagnostic API failed")
assert(#snapshot.registered == 2 and #snapshot.attempts == 2,
	"missing addon must remain visible as an activated-vs-registered mismatch")
assert(#snapshot.activatedModIds == 4 and snapshot.activatedSource == "available",
	"activated ModID catalog was not captured")
for index = 1, #snapshot.attempts do
	assert(snapshot.attempts[index].registered == true
		and snapshot.attempts[index].code == "OK",
		"successful registration attempt lost its result")
end

dofile(registrations[3])
local completeOk, _, complete = GSSiK.API.Addon.diagnose()
assert(completeOk == true and #complete.registered == 3 and #complete.attempts == 3,
	"third addon did not reconcile into the diagnostic catalog")
local seen = {}
for index = 1, #complete.registered do
	local row = complete.registered[index]
	assert(not seen[row.id], "duplicate addon in diagnostic catalog: " .. tostring(row.id))
	seen[row.id] = true
end
assert(seen.Craft and seen.Builder and seen.TabletLink,
	"diagnostic catalog omitted an official addon")

print("gssik_api_addon_diagnostics_regression: OK absent=actionable complete=3")

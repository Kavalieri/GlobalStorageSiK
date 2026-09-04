-- Client diagnostics must expose the complete addon discovery chain without
-- relying on a generic Addon.list failure. Run from GlobalStorageSiK-Repo.

for _, moduleName in ipairs({ "GS_I18n", "GS_Log", "GSSiK_API", "GS_Addons",
	"GS_CraftUtils", "GS_NetClient", "GS_AddonManageUI" }) do
	package.loaded[moduleName] = true
end
package.loaded["GS_UI_Framework"] = {}
package.loaded["GlobalStorageSiK/UI/Generated/TabAddons"] = { surface = {} }

local logs = {}
GlobalStorageSiK = {
	I18n = { text = function(key) return key end },
	Log = {
		debug = function(category, message)
			logs[#logs + 1] = tostring(category) .. ":" .. tostring(message)
		end,
		error = function() end,
	},
	CraftUtils = {}, Client = {}, Network = { getDefaultNetworkId = function() return "network" end },
	AddonManageUI = { show = function() end },
}

local defs = {
	{ id = "Craft", modId = "GSSiK_Addon_Craft", titleKey = "craft" },
	{ id = "Builder", modId = "GSSiK_Addon_Builder", titleKey = "builder" },
	{ id = "TabletLink", modId = "GSSiK_Addon_Tablet", titleKey = "tablet" },
}
local attempts = {}
for index = 1, #defs do
	attempts[index] = { id = defs[index].id, modId = defs[index].modId,
		registered = true, code = "OK", sequence = index }
end
GSSiK = { API = { Addon = {
	list = function() return true, "OK", defs end,
	isActive = function() return true, "OK", true end,
	diagnose = function()
		return true, "OK", { registered = defs, attempts = attempts,
			activatedSource = "available", activatedModIds = {
				"GSSiK_Addon_Craft", "GSSiK_Addon_Builder", "GSSiK_Addon_Tablet",
			} }
	end,
} } }

SiK = { UI = { SurfaceHost = { mount = function()
	return { refresh = function() end, reflow = function() end,
		getBounds = function() return { x = 0, y = 0, w = 1, h = 1 } end }
end } } }

local path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Addons.lua"
dofile(path)
local terminal = { playerNum = 0, terminalState = {
	networkId = "network", terminalAnchor = { x = 1, y = 2, z = 0 }, installedAddons = {},
} }
local context = GlobalStorageSiK.TerminalAddons.context(terminal)
assert(#context.data.addons.cards == 3, "all three official addons must reach the client catalog")
GlobalStorageSiK.TerminalAddons.buildPanel({}, terminal)

local joined = table.concat(logs, "\n")
for _, def in ipairs(defs) do
	assert(joined:find("catalog_item stage=context id=" .. def.id, 1, true),
		"context diagnostic omitted " .. def.id)
	assert(joined:find("catalog_item stage=mounted id=" .. def.id, 1, true),
		"mounted diagnostic omitted " .. def.id)
	assert(joined:find("modId=" .. def.modId, 1, true), "diagnostic omitted ModID " .. def.modId)
end
assert(joined:find("registered=true", 1, true)
	and joined:find("available=true mounted=false cause=available", 1, true),
	"context diagnostic did not distinguish catalog from mounted surface")
assert(joined:find("available=true mounted=true cause=available", 1, true),
	"mounted diagnostic did not confirm the visible surface")

print("addon_client_catalog_diagnostics_contract: OK catalog, registration, availability and mount")

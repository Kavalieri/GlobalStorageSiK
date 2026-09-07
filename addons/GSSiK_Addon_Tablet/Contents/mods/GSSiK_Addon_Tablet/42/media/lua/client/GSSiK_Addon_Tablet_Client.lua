--[[
	GSSiK Addon Tablet - Cliente
	Autor: SiK
	Fecha: 2025-06-27
]]

require "GSSiK_Addon_Tablet_Register"
require "GSSiK_Addon_Tablet_ItemHooks"
require "GSSiK_Addon_Tablet_Access"
require "GSSiK_Addon_Tablet_NetworkSelector"

local API = require "GSSiK_API_Client"

GSSiK_Addon_Tablet._itemRegistrations = GSSiK_Addon_Tablet._itemRegistrations or {}
for index = 1, #GSSiK_Addon_Tablet._itemRegistrations do
	GSSiK_Addon_Tablet._itemRegistrations[index]:dispose()
end
GSSiK_Addon_Tablet._itemRegistrations = {}

local function registerTablet(fullType, labelKey)
	local ok, code, registration = API.ItemActions.registerTablet({
		fullType = fullType,
		labelKey = labelKey,
		onUse = GSSiK_Addon_Tablet.NetworkSelector.onUseTablet,
	})
	if not ok then
		error("GSSiK Addon Tablet registration failed: " .. tostring(code))
	end
	GSSiK_Addon_Tablet._itemRegistrations[#GSSiK_Addon_Tablet._itemRegistrations + 1] = registration
end

registerTablet(GSSiK_Addon_Tablet.ITEM_TABLET, "IGUI_GSSiK_UseAccessTablet")
registerTablet(GSSiK_Addon_Tablet.ITEM_TABLET_CRAFT, "IGUI_GSSiK_UseCraftTablet")
registerTablet(GSSiK_Addon_Tablet.ITEM_TABLET_BUILDER, "IGUI_GSSiK_UseBuilderTablet")
registerTablet(GSSiK_Addon_Tablet.ITEM_TABLET_MASTER, "IGUI_GSSiK_UseMasterTablet")

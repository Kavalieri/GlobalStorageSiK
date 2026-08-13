--[[
	GSSiK Addon Tablet - Hooks de ítem
	Autor: SiK
	Fecha: 2026-08-04
]]

require "GS_I18n"

GSSiK_Addon_Tablet = GSSiK_Addon_Tablet or {}
GSSiK_Addon_Tablet.ItemHooks = {}

---@param item InventoryItem
---@param key string
local function applyDisplayName(item, key)
	if not item or not key then
		return
	end
	local name = GlobalStorageSiK.I18n.text(key)
	if name and name ~= "" and item.setName then
		item:setName(name)
	end
end

---@param item InventoryItem
function GSSiK_Addon_Tablet.ItemHooks.onCreateTablet(item)
	applyDisplayName(item, "IGUI_GSSiK_AccessTabletName")
end

---@param item InventoryItem
function GSSiK_Addon_Tablet.ItemHooks.onCreateCraftTablet(item)
	applyDisplayName(item, "IGUI_GSSiK_CraftTabletName")
end

---@param item InventoryItem
function GSSiK_Addon_Tablet.ItemHooks.onCreateBuilderTablet(item)
	applyDisplayName(item, "IGUI_GSSiK_BuilderTabletName")
end

---@param item InventoryItem
function GSSiK_Addon_Tablet.ItemHooks.onCreateMasterTablet(item)
	applyDisplayName(item, "IGUI_GSSiK_MasterTabletName")
end

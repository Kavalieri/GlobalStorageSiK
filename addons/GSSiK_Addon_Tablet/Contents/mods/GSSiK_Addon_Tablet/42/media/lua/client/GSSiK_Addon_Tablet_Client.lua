--[[
	GSSiK Addon Tablet - Cliente
	Autor: SiK
	Fecha: 2025-06-27
]]

require "GSSiK_Addon_Tablet_Register"
require "GSSiK_Addon_Tablet_ItemHooks"
require "GSSiK_Addon_Tablet_Access"
require "GS_ItemActions"

GlobalStorageSiK.ItemActions.registerTabletItem(GSSiK_Addon_Tablet.ITEM_TABLET, "IGUI_GSSiK_UseAccessTablet")
GlobalStorageSiK.ItemActions.registerTabletItem(GSSiK_Addon_Tablet.ITEM_TABLET_CRAFT, "IGUI_GSSiK_UseCraftTablet")
GlobalStorageSiK.ItemActions.registerTabletItem(GSSiK_Addon_Tablet.ITEM_TABLET_BUILDER, "IGUI_GSSiK_UseBuilderTablet")
GlobalStorageSiK.ItemActions.registerTabletItem(GSSiK_Addon_Tablet.ITEM_TABLET_MASTER, "IGUI_GSSiK_UseMasterTablet")

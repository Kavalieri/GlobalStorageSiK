--[[
	GSSiK Addon Tablet - Cliente
	Autor: SiK
	Fecha: 2025-06-27
]]

require "GSSiK_Addon_Tablet_Register"
require "GSSiK_Addon_Tablet_ItemHooks"
require "GSSiK_Addon_Tablet_Access"
require "GSSiK_Addon_Tablet_NetworkSelector"
require "GS_ItemActions"

GlobalStorageSiK.ItemActions.registerTabletItem(GSSiK_Addon_Tablet.ITEM_TABLET,
	"IGUI_GSSiK_UseAccessTablet", GSSiK_Addon_Tablet.NetworkSelector.onUseTablet)
GlobalStorageSiK.ItemActions.registerTabletItem(GSSiK_Addon_Tablet.ITEM_TABLET_CRAFT,
	"IGUI_GSSiK_UseCraftTablet", GSSiK_Addon_Tablet.NetworkSelector.onUseTablet)
GlobalStorageSiK.ItemActions.registerTabletItem(GSSiK_Addon_Tablet.ITEM_TABLET_BUILDER,
	"IGUI_GSSiK_UseBuilderTablet", GSSiK_Addon_Tablet.NetworkSelector.onUseTablet)
GlobalStorageSiK.ItemActions.registerTabletItem(GSSiK_Addon_Tablet.ITEM_TABLET_MASTER,
	"IGUI_GSSiK_UseMasterTablet", GSSiK_Addon_Tablet.NetworkSelector.onUseTablet)

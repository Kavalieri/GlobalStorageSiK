-- Wireless capability contract regression for Tablet 0.0.2.17-dev1.4.

package.path = package.path .. ";./Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/?.lua"

local registeredProvider = nil
local installedType = nil
local installed = false
local inventoryCounts = {}

local inventory = {
	getItemCountRecurse = function(_, fullType) return inventoryCounts[fullType] or 0 end,
}
local player = { getInventory = function() return inventory end }

SandboxVars = { GSSiK_Addon_Tablet = {} }
GSSiK = {
	API = {
		Access = {
			registerProvider = function(provider)
				registeredProvider = provider
				return true, "OK", { dispose = function() return true end }
			end,
		},
		Installation = {
			isInstalled = function() return true, "OK", installed end,
			get = function()
				if not installed then return false, "ERR_NOT_FOUND", nil end
				return true, "OK", { itemType = installedType }
			end,
		},
	},
}
GSSiK_Addon_Tablet = {
	Sandbox = {
		getTier1Range = function() return 25 end,
		getTier2Range = function() return 50 end,
		getTier3Range = function() return 100 end,
	},
	Log = { debug = function() end },
}

package.preload["GSSiK_Addon_Tablet_ItemHooks"] = function() return {} end
package.preload["GSSiK_Addon_Tablet_Sandbox"] = function() return GSSiK_Addon_Tablet.Sandbox end
package.preload["GSSiK_Addon_Tablet_Log"] = function() return GSSiK_Addon_Tablet.Log end
package.preload["GSSiK_API"] = function() return GSSiK.API end

dofile("Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/GSSiK_Addon_Tablet_Access.lua")
assert(registeredProvider ~= nil, "wireless provider was not registered")
assert(registeredProvider.id == "TabletLink", "wireless provider identity changed")
assert(registeredProvider.capabilities and registeredProvider.capabilities.remoteTerminal == true,
	"remote terminal capability must be declared by Tablet")
assert(registeredProvider.hasAccess and registeredProvider.getRangeForNetwork,
	"wireless provider is missing authority inputs")

inventoryCounts[GSSiK_Addon_Tablet.ITEM_TABLET] = 1
assert(registeredProvider.hasAccess(player) == true, "base tablet must grant candidate access")
assert(registeredProvider.getRangeForNetwork(player, "n1", {}) == 0,
	"network without an installed antenna must have zero range")

installed = true
installedType = nil
assert(registeredProvider.getRangeForNetwork(player, "n1", {}) == 25,
	"legacy installation without itemType must retain conservative T1 range")
installedType = "GSSiK_Addon_Tablet.GS_WifiAntenna"
assert(registeredProvider.getRangeForNetwork(player, "n1", {}) == 25, "T1 range mismatch")
installedType = "GSSiK_Addon_Tablet.GS_WifiAntenna_T2"
assert(registeredProvider.getRangeForNetwork(player, "n1", {}) == 50, "T2 range mismatch")
installedType = "GSSiK_Addon_Tablet.GS_WifiAntenna_T3"
assert(registeredProvider.getRangeForNetwork(player, "n1", {}) == 100, "T3 range mismatch")
installedType = "GSSiK_Addon_Tablet.NotAnAntenna"
assert(registeredProvider.getRangeForNetwork(player, "n1", {}) == 0,
	"unknown installed itemType must never inherit T1 coverage")

print("PASS tablet_remote_provider_contract_regression")

-- Contract regression for Tablet tier registration through the public API.
-- Pure Lua 5.1: product registration is captured through neutral Core stubs.

package.path = package.path .. ";./Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/?.lua"

local registeredAddon = nil

SandboxVars = { GSSiK_Addon_Tablet = {} }
GSSiK = {
	API = {
		Addon = {
			register = function(definition)
				registeredAddon = definition
				return true, "registered"
			end,
		},
	},
}

package.preload["GSSiK_API"] = function() return GSSiK.API end

dofile("Contents/mods/GSSiK_Addon_Tablet/42/media/lua/shared/GSSiK_Addon_Tablet_Register.lua")

assert(registeredAddon and registeredAddon.id == "TabletLink", "TabletLink was not registered")
assert(#registeredAddon.moduleItemTypes == 3, "Tablet must declare exactly T1/T2/T3 module types")
assert(#registeredAddon.tierItems == 3, "Tablet must declare exactly three progression tiers")

local expected = {
	"GSSiK_Addon_Tablet.GS_WifiAntenna",
	"GSSiK_Addon_Tablet.GS_WifiAntenna_T2",
	"GSSiK_Addon_Tablet.GS_WifiAntenna_T3",
}
for i = 1, #expected do
	assert(registeredAddon.moduleItemTypes[i] == expected[i], "moduleItemTypes tier order changed")
	assert(registeredAddon.tierItems[i].item == expected[i], "tierItems progression order changed")
	assert(type(registeredAddon.tierItems[i].recipeName) == "string"
		and registeredAddon.tierItems[i].recipeName ~= "", "tier recipe is missing")
end

assert(registeredAddon.replaceInstalled == nil, "direct installed-to-installed replacement is forbidden")
assert(registeredAddon.upgradeInstalled == nil, "direct upgrade operation is forbidden")

print("PASS tablet_tier_contract_regression")

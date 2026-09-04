-- Author regression for the generic atomic addon-uninstall contract.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

for _, name in ipairs({
	"GS_Network", "GS_AddonRegistry", "GS_Permissions", "GS_I18n", "GS_Log",
	"GS_InventorySync", "GS_CraftUtils", "GS_Sandbox", "GS_ReaderAddon",
}) do
	package.loaded[name] = true
end
package.loaded["GSSiK_API"] = true

local anchor = { x = 12, y = 34, z = 0 }
local key = "12_34_0"
local registry = {
	networks = {
		net = { addonInstalls = { [key] = {} } },
	},
}
local syncSucceeds = false
local createdTypes = {}
local syncItems = {}
local transmissions = 0
local order = {}

GlobalStorageSiK = {
	MODDATA_KEY = "GlobalStorageSiK_Network",
	Config = { ITEM_TERMINAL_READER = "GlobalStorageSiK.Reader" },
	Network = {
		getRegistry = function() return registry end,
		ensureRegistry = function() end,
	},
	AddonRegistry = {
		get = function(addonId)
			if addonId == "TabletLink" then
				return { id = addonId, itemType = "Tablet.DefaultModule" }
			end
			return nil
		end,
	},
	Permissions = { isAdminPlayer = function() return true end },
	I18n = { remote = function(keyName) return keyName end },
	Log = { debug = function() end, error = function() end },
	InventorySync = {
		addToPlayer = function(_, item)
			order[#order + 1] = "deliver"
			syncItems[#syncItems + 1] = item
			-- The registry must still be authoritative while delivery is attempted.
			assert(registry.networks.net.addonInstalls[key].TabletLink ~= nil,
				"uninstall removed the registry before exact delivery was confirmed")
			return syncSucceeds
		end,
	},
	CraftUtils = { getElectricityLevel = function() return 10 end },
	Sandbox = { getAddonInstallSkillRequired = function() return 0 end },
	isAuthoritative = function() return true end,
}
GSSiK = { API = { Addon = {
	get = function(addonId)
		local definition = GlobalStorageSiK.AddonRegistry.get(addonId)
		return definition ~= nil, definition and nil or "ERR_NOT_FOUND", definition
	end,
	isActive = function(addonId)
		return true, nil, GlobalStorageSiK.AddonRegistry.get(addonId) ~= nil
	end,
} } }

local inventory = {
	getItemCount = function() return 1 end,
	getItemCountRecurse = function() return 1 end,
}
local player = { getInventory = function() return inventory end }

instanceItem = function(fullType)
	createdTypes[#createdTypes + 1] = fullType
	return { fullType = fullType }
end

ModData = {
	transmit = function(keyName)
		order[#order + 1] = "transmit"
		transmissions = transmissions + 1
		assert(keyName == GlobalStorageSiK.MODDATA_KEY, "wrong ModData key")
		assert(registry.networks.net.addonInstalls[key].TabletLink == nil,
			"registry must be removed before transmitting the successful commit")
	end,
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_Addons.lua")
GlobalStorageSiK.Addons.hasRequiredSkill = function() return true end
GlobalStorageSiK.Addons.hasReaderAvailable = function() return true end

local function installRecord(itemType, tier)
	registry.networks.net.addonInstalls[key].TabletLink = {
		itemType = itemType,
		tier = tier,
	}
end

-- Failed delivery/synchronization is a rollback-free no-op: the exact record
-- remains installed and no registry transmission is allowed.
installRecord("Tablet.AntennaT3", 3)
syncSucceeds = false
local ok = GlobalStorageSiK.Addons.uninstall(player, "net", anchor, "TabletLink")
assert(ok == false, "failed delivery must fail uninstall")
assert(registry.networks.net.addonInstalls[key].TabletLink.itemType == "Tablet.AntennaT3",
	"failed uninstall did not preserve the exact installed type")
assert(registry.networks.net.addonInstalls[key].TabletLink.tier == 3,
	"failed uninstall did not preserve addon metadata")
assert(transmissions == 0, "failed uninstall transmitted a registry mutation")
assert(createdTypes[1] == "Tablet.AntennaT3", "failure attempted the wrong tier")

-- A successful transaction delivers the exact recorded type first, then
-- removes and transmits the registry exactly once.
order = {}
syncSucceeds = true
ok = GlobalStorageSiK.Addons.uninstall(player, "net", anchor, "TabletLink")
assert(ok == true, "confirmed delivery must complete uninstall")
assert(syncItems[#syncItems].fullType == "Tablet.AntennaT3",
	"successful uninstall returned a fallback instead of the exact tier")
assert(registry.networks.net.addonInstalls[key].TabletLink == nil,
	"successful uninstall retained the registry entry")
assert(transmissions == 1, "successful uninstall must transmit exactly once")
assert(order[1] == "deliver" and order[2] == "transmit",
	"transaction order must be deliver -> remove/commit -> transmit")

print("addons_uninstall_transaction_regression: OK")

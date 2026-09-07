-- Dynamic contract for exact_group: only a complete, certified capture at the
-- current inventory revision can resolve physical identities.

for _, name in ipairs({ "GS_Network", "GS_Router", "GS_Zones", "GS_ItemSnapshot",
	"GS_ZoneRefresh", "GS_NativeProduct", "GS_CategoryResolution", "GS_Permissions" }) do
	package.loaded[name] = true
end

local registry = {
	_inventoryRevision = { net = 3 }, _snapshotRevision = { net = 3 },
	zones = { zone = { networkId = "net" } }, nodes = {},
}
local rowKey = "Base.VHS_Retail\31sprite:\31media:214"
local player = { getUsername = function() return "Kava" end }
GlobalStorageSiK = {
	Network = {
		getRegistry = function() return registry end,
		ensureRegistry = function(value)
			value._inventoryRevision = value._inventoryRevision or {}
		end,
		getDefaultNetworkId = function() return "net" end,
	},
	Zones = { getRegistry = function() return registry end },
	Permissions = { canAccessZone = function() return true end },
	I18n = {}, ItemSnapshot = {}, NativeProduct = {}, CategoryResolution = {}, ZoneRefresh = {},
}

local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/"
dofile(root .. "shared/GS_Index.lua")

local function put(snapshot)
	registry.nodes = { node = { id = "node", zoneId = "zone", itemSnapshot = snapshot } }
end

put(nil)
local missing, missingReason = GlobalStorageSiK.Index.resolveExactGroup("net", player, rowKey, 3)
assert(not missing and missingReason == "selection_stale", "missing snapshot became a valid exact selection")

put({ row = { fullType = "Base.VHS_Retail", mediaIndex = 214, itemIds = nil, count = 2 } })
local legacy, legacyReason = GlobalStorageSiK.Index.resolveExactGroup("net", player, rowKey, 3)
assert(not legacy and legacyReason == "selection_stale", "legacy count without physical IDs was accepted")

put({ row = { fullType = "Base.VHS_Retail", mediaIndex = 214, itemIds = { 11, 12 }, count = 2 } })
local valid, validReason = GlobalStorageSiK.Index.resolveExactGroup("net", player, rowKey, 3)
assert(valid and not validReason and valid.count == 2, "complete current snapshot did not resolve")
assert(valid.refs[1].itemId == 11 and valid.refs[2].itemId == 12,
	"valid snapshot lost its physical identities")

registry._snapshotRevision.net = 2
local staleRevision, staleReason = GlobalStorageSiK.Index.resolveExactGroup("net", player, rowKey, 3)
assert(not staleRevision and staleReason == "selection_stale", "older certified snapshot was accepted")
print("PASS withdraw capture consistency contract")

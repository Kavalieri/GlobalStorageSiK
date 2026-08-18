-- Regression test for MP identity collisions. Run from the repository root:
-- lua51.exe tests/permissions_identity_regression.lua

package.loaded["GS_Network"] = true

local registry = { networks = {}, zones = {}, nodes = {} }
local migrationLogs = {}

GlobalStorageSiK = {
	MODDATA_KEY = "GlobalStorageSiK",
	isMultiplayerActive = function() return true end,
	isAuthoritative = function() return true end,
	Network = {
		getRegistry = function() return registry end,
		ensureRegistry = function(value)
			value.networks = value.networks or {}
			value.zones = value.zones or {}
			value.nodes = value.nodes or {}
		end,
	},
	I18n = {
		remote = function(key) return key end,
	},
	Log = {
		info = function(category, event, detail)
			migrationLogs[#migrationLogs + 1] = category .. ":" .. event .. ":" .. detail
		end,
	},
}

local function vector(values)
	return {
		size = function() return #values end,
		get = function(_, index) return values[index + 1] end,
	}
end

local function player(username, forename, surname, displayName, descriptorId, persistentSqlId)
	local modData = {}
	local descriptor = {
		getID = function() return descriptorId end,
		getForename = function() return forename end,
		getSurname = function() return surname end,
	}
	return {
		getDescriptor = function() return descriptor end,
		getSqlId = function() return persistentSqlId end,
		getModData = function() return modData end,
		transmitModData = function() end,
		getUsername = function() return username end,
		getDisplayName = function() return displayName end,
		isAccessLevel = function() return false end,
	}
end

local kava = player("KavaAccount", "Kava", "", "Kava", 7, 101)
local supernavos = player("SuperAccount", "Supernavos", "", "Supernavos", 7, 202)
local sarini = player("Sarini13", "Sarini", "Trece", "Sarini13", 9, 303)
local imposter = player("OtherAccount", "Otro", "Jugador", "Otro", 9, 404)
local unicodePlayer = player("玩家账户", "凯", "瓦", "凯瓦", 11, 505)
local adminKalva = player("admin", "Kalva", "", "admin", 15, 909)
adminKalva.getSqlId = nil -- dedicated B42 path from the reported runtime error
local noAccount = player("", "Sin", "Cuenta", "Sin Cuenta", 7, 606)
local uuidFallback = player("FallbackAccount", "Fallback", "", "Fallback", 13, nil)
local online = vector({ kava, supernavos, sarini, imposter, unicodePlayer })

getOnlinePlayers = function() return online end
getActivePlayers = function() return online end
getPlayerFromUsername = function(wanted)
	for i = 0, online:size() - 1 do
		local current = online:get(i)
		if current:getUsername():lower() == tostring(wanted):lower() then return current end
	end
	return nil
end

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_Permissions.lua")

local Permissions = GlobalStorageSiK.Permissions
local OWNER = Permissions.ROLE_OWNER
local MEMBER = Permissions.ROLE_MEMBER

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected=" .. tostring(expected)
			.. " actual=" .. tostring(actual), 2)
	end
end

-- Reproduce production corruption: two players expose descriptor ID 7 in
-- different MP processes and the legacy owner record was overwritten visually.
registry.networks.owner_collision = {
	id = "owner_collision",
	owner = "Kava",
	ownerAccount = "KavaAccount",
	ownerCharacterId = "character:7",
	allowedUsers = {},
	allowedFactions = {},
	adminUsers = {},
	characterPermissions = {
		["character:7"] = {
			name = "Supernavos",
			displayName = "Supernavos",
			username = "SuperAccount",
			role = OWNER,
		},
	},
	memberZoneDenials = {},
}

local kavaId = Permissions.getCharacterId(kava)
local supernavosId = Permissions.getCharacterId(supernavos)
assert(kavaId:match("^character:gsc_") ~= nil,
	"Kava must have a server-owned character UUID")
assert(supernavosId:match("^character:gsc_") ~= nil,
	"Supernavos must have a server-owned character UUID")
assert(kavaId ~= supernavosId, "same descriptor ID must not collide")
assertEqual(Permissions.getCharacterId(noAccount), "",
	"MP identity without an authoritative account must fail closed")
local fallbackId = Permissions.getCharacterId(uuidFallback)
assert(fallbackId:match("^character:gsc_") ~= nil,
	"every character must use a server-owned character UUID")
assertEqual(Permissions.getCharacterId(uuidFallback), fallbackId,
	"the generated character UUID must remain stable in player modData")

-- Dedicated B42 may expose the account through getDisplayName(). The UI must
-- still present the SurvivorDesc character name and keep the account internal.
assertEqual(Permissions.getCharacterName(adminKalva), "Kalva",
	"the descriptor must provide the exact character name")
assertEqual(Permissions.getPlayerDisplayName(adminKalva), "Kalva",
	"an account display name must never replace the character name")
local adminNetwork = {
	id = "admin_kalva",
	owner = "Kalva",
	ownerAccount = "admin",
	ownerCharacterId = "account:admin|sql:909",
	allowedUsers = {},
	adminUsers = {},
	memberZoneDenials = {},
	characterPermissions = {
		["account:admin|sql:909"] = {
			name = "Kalva", displayName = "admin", username = "admin", role = OWNER,
		},
	},
}
registry.networks.admin_kalva = adminNetwork
assertEqual(Permissions.isOwnerPlayer(adminKalva, "admin_kalva"), true,
	"the DEV4 dedicated owner must migrate to its UUID")
assertEqual(adminNetwork.owner, "Kalva", "owner presentation must use the character")
assertEqual(adminNetwork.ownerAccount, "admin", "the account must remain the authorization anchor")
assert(adminNetwork.ownerCharacterId:match("^character:gsc_") ~= nil,
	"the migrated owner key must be the character UUID")
assertEqual(adminNetwork.characterPermissions["account:admin|sql:909"], nil,
	"the DEV4 account/sql record must be removed after migration")
assertEqual(adminNetwork.characterPermissions[adminNetwork.ownerCharacterId].displayName, "Kalva",
	"the persisted UI label must use the character")
local adminSerialized = Permissions.serialize("admin_kalva", adminKalva)
assertEqual(adminSerialized.memberEntries[1].name, "Kalva",
	"the management modal must receive the character name")
assertEqual(adminSerialized.memberEntries[1].displayName, "Kalva",
	"the management modal must not receive the account as its primary label")
assertEqual(Permissions.isOwnerPlayer(supernavos, "owner_collision"), false,
	"the colliding player must never inherit ownership")
assertEqual(Permissions.canAccess(supernavos, "owner_collision"), false,
	"the colliding player must never inherit access")
assertEqual(Permissions.isOwnerPlayer(kava, "owner_collision"), true,
	"the authoritative owner account must repair its identity")

local repaired = registry.networks.owner_collision
assertEqual(repaired.ownerCharacterId, kavaId, "owner ID must be migrated")
assertEqual(repaired.owner, "Kava", "owner character name must keep exact case")
assertEqual(repaired.ownerAccount, "KavaAccount", "owner account must keep exact case")
assertEqual(repaired.characterPermissions["character:7"], nil,
	"ambiguous legacy owner record must be removed")
assertEqual(repaired.characterPermissions[kavaId].displayName, "Kava",
	"owner UI record must be rebuilt from the real owner")
assertEqual(Permissions.canAccess(supernavos, "owner_collision"), false,
	"the colliding player must remain denied after owner migration")

local serialized = Permissions.serialize("owner_collision", kava)
assertEqual(serialized.memberEntries[1].displayName, "Kava",
	"the management modal must show the repaired owner")
assertEqual(serialized.playerRole, OWNER, "Kava must retain the real owner role")

-- A legacy member record is migratable only when both account and nominal
-- membership agree. An unrelated player sharing the descriptor ID is denied.
registry.networks.member_collision = {
	id = "member_collision",
	owner = "Kava",
	ownerAccount = "KavaAccount",
	ownerCharacterId = kavaId,
	allowedUsers = { "Sarini13" },
	allowedFactions = {},
	adminUsers = {},
	characterPermissions = {
		["character:9"] = {
			name = "Sarini Trece",
			displayName = "Sarini13",
			username = "Sarini13",
			role = MEMBER,
		},
	},
	memberZoneDenials = { ["character:9"] = { zone_a = true } },
}

assertEqual(Permissions.canAccess(imposter, "member_collision"), false,
	"an unrelated account must not migrate a colliding member ID")
assertEqual(Permissions.canAccess(sarini, "member_collision"), true,
	"the matching account and nominal member must migrate")
assertEqual(registry.networks.member_collision.characterPermissions[Permissions.getCharacterId(sarini)].role,
	MEMBER, "the migrated member must retain its role")
assertEqual(registry.networks.member_collision.memberZoneDenials[Permissions.getCharacterId(sarini)].zone_a,
	true, "legacy zone denials must follow the verified member")
assertEqual(Permissions.countBackupMembers("member_collision"), 1,
	"a UUID member must remain visible to backup-member accounting")

-- Offline ownership transfer must be anchored to an account that is already
-- present in the server-side membership. It remains deliberately unbound to a
-- character until that account connects with a persistent character ID.
registry.networks.offline_transfer = {
	id = "offline_transfer",
	owner = "Kava",
	ownerAccount = "KavaAccount",
	ownerCharacterId = kavaId,
	allowedUsers = { "OfflineAccount" },
	allowedFactions = {},
	adminUsers = {},
	characterPermissions = {
		[kavaId] = { name = "Kava", displayName = "Kava", username = "KavaAccount", role = OWNER },
	},
	memberZoneDenials = {},
}
local spoofOk = Permissions.transferOwner(
	"offline_transfer", kava, "Intruso", true, "NotAMember", "")
assertEqual(spoofOk, false, "the client cannot transfer ownership to an unregistered account")
local offlineOk = Permissions.transferOwner(
	"offline_transfer", kava, "OfflineAccount", true, "OfflineAccount", "")
assertEqual(offlineOk, true, "an existing offline member account can receive ownership")
assertEqual(registry.networks.offline_transfer.ownerAccount, "OfflineAccount",
	"offline ownership must persist the exact account")
assertEqual(registry.networks.offline_transfer.ownerCharacterId, "",
	"offline ownership must not invent a character ID")
local offlinePlayer = player("OfflineAccount", "Propietaria", "Offline", "OfflineAccount", 7, 808)
assertEqual(Permissions.isOwnerPlayer(offlinePlayer, "offline_transfer"), true,
	"the offline owner account must bind to its persistent character when it connects")
assertEqual(registry.networks.offline_transfer.ownerCharacterId, Permissions.getCharacterId(offlinePlayer),
	"the connected offline owner must receive its account-scoped character ID")
assertEqual(registry.networks.offline_transfer.owner, "Propietaria Offline",
	"the owner presentation must refresh from the connected character")

-- Death succession must operate on the account-scoped owner ID. A new
-- character from the former account cannot reclaim a network already handed
-- to its configured backup member.
local sariniId = Permissions.getCharacterId(sarini)
registry.networks.owner_death = {
	id = "owner_death",
	owner = "Kava",
	ownerAccount = "KavaAccount",
	ownerCharacterId = kavaId,
	allowedUsers = { "Sarini Trece" },
	allowedFactions = {},
	adminUsers = { "Sarini Trece" },
	characterPermissions = {
		[kavaId] = { name = "Kava", displayName = "Kava", username = "KavaAccount", role = OWNER },
		[sariniId] = { name = "Sarini Trece", displayName = "Sarini13", username = "Sarini13", role = Permissions.ROLE_ADMIN },
	},
	memberZoneDenials = {},
}
Permissions.handleOwnerDeath(kava)
assertEqual(registry.networks.owner_death.ownerCharacterId, sariniId,
	"the configured backup admin must inherit ownership")
assertEqual(registry.networks.owner_death.owner, "Sarini Trece",
	"successor name must keep exact case")
local replacementKava = player("KavaAccount", "Kava", "Nueva", "Kava Nueva", 12, 101)
assert(Permissions.getCharacterId(replacementKava) ~= kavaId,
	"a replacement character reusing the same account/sql slot must receive another UUID")
registry.networks.uuid_no_inherit = {
	id = "uuid_no_inherit",
	owner = "Kava",
	ownerAccount = "KavaAccount",
	ownerCharacterId = kavaId,
	allowedUsers = {}, allowedFactions = {}, adminUsers = {}, memberZoneDenials = {},
	characterPermissions = {
		[kavaId] = { name = "Kava", username = "KavaAccount", role = OWNER },
	},
}
assertEqual(Permissions.canAccess(replacementKava, "uuid_no_inherit"), false,
	"a replacement character must not inherit access from the reused account/sql slot")
assertEqual(Permissions.isOwnerPlayer(replacementKava, "owner_death"), false,
	"a replacement character must not reclaim transferred ownership")

-- Unicode and capitalization are presentation data, not authorization keys.
local fresh = { id = "unicode", allowedUsers = {}, adminUsers = {}, memberZoneDenials = {} }
assertEqual(Permissions.initializeOwner(fresh, unicodePlayer), true,
	"a Unicode owner must be initialized")
assertEqual(fresh.owner, "凯 瓦", "Unicode character name must be preserved")
assertEqual(fresh.ownerAccount, "玩家账户", "Unicode account must be preserved")
assertEqual(fresh.characterPermissions[fresh.ownerCharacterId].displayName, "凯 瓦",
	"Unicode character name must be preserved as the visible label")
local unsafe = { id = "unsafe", allowedUsers = {}, adminUsers = {}, memberZoneDenials = {} }
assertEqual(Permissions.initializeOwner(unsafe, noAccount), false,
	"a new MP owner without an authoritative account must be rejected")

assert(#migrationLogs >= 2, "owner and member migrations must emit diagnostics")
print("permissions_identity_regression: OK")

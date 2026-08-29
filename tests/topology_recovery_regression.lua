-- DEV32.2 regression harness. Run from GlobalStorageSiK-Repo:
-- lua51.exe tests/topology_recovery_regression.lua
--
-- It loads the real GS_Server dispatcher and captures its serialized
-- actionResult packets through a fake dedicated-server transport. This is not
-- an in-game certification; it protects the server contract between QA runs.

local now = 1000
local registry = { networks = {}, zones = {}, nodes = {} }
local packets = {}
local allow = true
local coverageAllows = true

getTimestampMs = function() return now end
isClient = function() return true end
isServer = function() return false end
sendServerCommand = function(_, module, command, payload)
	packets[#packets + 1] = { module = module, command = command, payload = payload }
end

local function eventList()
	return { Add = function() end }
end
Events = {
	OnClientCommand = eventList(), OnTick = eventList(), OnCreatePlayer = eventList(),
	OnPlayerDeath = eventList(), OnInitGlobalModData = eventList(),
}
ModData = {
	getOrCreate = function() return registry end,
	transmit = function() end,
}

local required = {
	"GS_Config", "GS_I18n", "GS_Utils", "GS_Sandbox", "GS_Zones", "GS_ZoneScanner", "GS_ZonePriority",
	"GS_ZoneRefresh", "GS_Network", "GS_Index", "GS_RuleSanitizer", "GS_RuleCoverage",
	"GS_NetworkCapacity", "GS_Power", "GS_Transfer", "GS_InventorySync", "GS_TransferLock",
	"GS_Redistribute", "GS_RedistributeJob", "GS_ZoneScanJob", "GS_Bulk", "GS_Deposit",
	"GS_Categories", "GS_CraftCatalog", "GS_Permissions", "GS_TerminalAccess",
	"GS_TerminalManifest", "GS_TerminalRegistry", "GS_TerminalRecovery", "GS_TerminalPlace",
	"GS_TerminalPlacementIntent", "GS_TerminalRecord", "GS_NetworkResolve", "GS_NetworkManager",
	"GS_NodeNaming", "GS_TerminalRecipes", "GS_CraftUtils", "GS_PCAcquire", "GS_ReaderAcquire",
	"GS_DiskProgramming", "GS_AddonRecipes", "GS_ItemSnapshot", "GS_FuelConsumption", "GS_Log",
	"GS_NativeAuditServer", "GS_NativeCorpusServer", "GS_Debug", "GS_NetTrace",
}
for i = 1, #required do package.loaded[required[i]] = true end

GlobalStorageSiK = {
	MOD_ID = "GlobalStorageSiK", MODDATA_KEY = "GlobalStorageSiK", TEST_HARNESS = true,
	I18n = { remote = function(key) return key end, scanReasonCode = function() return "UNKN" end },
	Sandbox = { debugMode = function() return false end, getMaxNodes = function() return 128 end,
		getTerminalProximityRange = function() return 20 end, getWirelessRange = function() return 0 end },
	Log = { info = function() end, debug = function() end, detail = function() end, warn = function() end },
	Network = {
		resolveCommandNetworkId = function(_, args) return args.networkId end,
		findWorldObject = function(node) return node and node.worldObject or nil end,
		getDefaultNetworkId = function() return "net_a" end,
		getDisplayName = function() return "Harness network" end,
		containerRangeEnabled = function() return false end,
	},
	Utils = {
		getObjectContainer = function(object) return object and {} or nil end,
		isNetworkStorageContainer = function(object) return object ~= nil end,
	},
	Permissions = {
		canAccess = function() return allow end, isAdminPlayer = function() return allow end,
		isOwnerPlayer = function() return allow end, isServerStaff = function() return false end,
		canAccessZone = function() return true end, serialize = function() return {} end,
	},
	RedistributeJob = { isActive = function() return false end },
	ZoneScanJob = { isActive = function() return false end, getStatus = function() return nil end },
	RuleCoverage = { prepareNewRule = function() return coverageAllows end },
	ZonePriority = { zoneArea = function() return 100 end, ensurePriorities = function() end, sortSerialized = function() end },
	Index = { buildRows = function() return {} end, getInventoryRevision = function() return 0 end,
		getSnapshotRevision = function() return 0 end },
	Power = { networkPowered = function() return true end, serializeConsumption = function() return {} end },
	Categories = { serialize = function() return {} end },
	NetworkCapacity = { compute = function() return { perNode = {}, perZone = {} } end,
		serialize = function() return {} end },
	TerminalAccess = { getWirelessRangeForPlayer = function() return 0 end },
	Addons = { canShowTerminalCraftTab = function() return false end,
		canShowTerminalBuildTab = function() return false end },
	Debug = { log = function() end },
}

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected=" .. tostring(expected)
			.. " actual=" .. tostring(actual), 2)
	end
end

local function assertTrue(value, message)
	if not value then error(message or "assertion failed", 2) end
end

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_Zones.lua")
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_ZoneRefresh.lua")
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_Server.lua")

local function signature(sprite)
	return { sprite = sprite, containerType = "crate", containerIndex = 0 }
end

local function reset(nodes)
	registry = {
		networks = {},
		zones = {
			zone_a = { id = "zone_a", networkId = "net_a", name = "A" },
			zone_b = { id = "zone_b", networkId = "net_a", name = "B" },
		},
		nodes = nodes or {}, legacyRuleSanitizerByNetwork = { net_a = 4 },
	}
	packets = {}
	coverageAllows = true
	allow = true
end

local admin = { getUsername = function() return "Kava" end }
local function dispatch(command, args)
	GlobalStorageSiK.Server.dispatchClientCommandForTest("GlobalStorageSiK", command, admin, args)
	for i = #packets, 1, -1 do
		if packets[i].command == "actionResult" then return packets[i].payload end
	end
	return nil
end

local function oldNode()
	return {
		id = "old", zoneId = "zone_a", offline = true, lastSeenMs = 10,
		physicalSignature = signature("crate_a"), displayName = "Nevera cocina",
		priority = 20, notes = "comida", membership = "active", enabled = true,
		rules = { { op = "OR", condition = { type = "item", itemType = "Base.Apple" } } },
	}
end

local function freshNode(id, zoneId, sprite)
	return {
		id = id, zoneId = zoneId or "zone_a", offline = false, discoveredAtMs = 20,
		lastSeenMs = 20, physicalSignature = signature(sprite or "crate_a"),
		name = "Armario", membership = "auto", worldObject = {}, storedCapacity = { capacity = 80 },
	}
end

-- Unique compatible proposal and confirmed migration through the REAL dispatcher.
local old = oldNode()
local target = freshNode("new")
reset({ old = old, new = target })
local proposal = dispatch("requestRebindProposal", { networkId = "net_a", nodeId = "old" })
assertTrue(proposal.ok and proposal.rebindProposal and proposal.token,
	"unique compatible candidate must serialize a server proposal")
local result = dispatch("rebindNode", { networkId = "net_a", nodeId = "old", rebindToken = proposal.token })
assertTrue(result.ok, "confirmed token must rebind through handler")
assertEqual(registry.nodes.old, nil, "source is deleted only after destination configuration is written")
assertEqual(registry.nodes.new.displayName, "Nevera cocina", "visible logical name must move once")
assertEqual(registry.nodes.new.priority, 20, "priority must move once")
assertEqual(registry.nodes.new.rules[1].condition.itemType, "Base.Apple", "rules must move once")
assertEqual(registry.nodes.new.zoneId, "zone_a", "target physical zone must be retained")
assertEqual(registry.nodes.new.storedCapacity.capacity, 80, "capacity is physical and retained")

-- More than one compatible discovery never selects locally or issues a token.
reset({ old = oldNode(), one = freshNode("one"), two = freshNode("two") })
local choice = dispatch("requestRebindProposal", { networkId = "net_a", nodeId = "old" })
assertTrue(choice.ok and choice.rebindCandidates and #choice.candidates == 2 and not choice.token,
	"ambiguity must serialize only the authoritative candidate list")
local chosen = dispatch("requestRebindProposal", {
	networkId = "net_a", nodeId = "old", targetNodeId = "two",
})
assertTrue(chosen.ok and chosen.rebindProposal and chosen.targetId == "two",
	"only an explicit server-listed target can receive a token")

-- Stale revisions, permissions and incompatible signatures preserve both records.
now = now + 1
registry.nodes.old = oldNode()
registry.nodes.one = freshNode("one")
registry.nodes.two = nil
local stale = dispatch("requestRebindProposal", { networkId = "net_a", nodeId = "old" })
registry.nodes.one.lastSeenMs = 21
local staleResult = dispatch("rebindNode", { networkId = "net_a", nodeId = "old", rebindToken = stale.token })
assertEqual(staleResult.ok, false, "stale proposal must be rejected")
assertTrue(registry.nodes.old ~= nil and registry.nodes.one ~= nil, "stale rejection must not mutate records")
allow = false
local denied = dispatch("requestRebindProposal", { networkId = "net_a", nodeId = "old" })
assertEqual(denied.ok, false, "permission rejection must serialize a failure")
assertTrue(registry.nodes.old ~= nil, "permission rejection must not mutate records")
allow = true
reset({ old = oldNode(), mismatch = freshNode("mismatch", "zone_a", "different_sprite") })
local conflict = dispatch("requestRebindProposal", { networkId = "net_a", nodeId = "old" })
assertEqual(conflict.ok, false, "signature mismatch must be rejected")
assertEqual(conflict.message, "IGUI_GS_NodeRebindConflict", "mismatch reason must be explicit")
assertTrue(registry.nodes.old ~= nil and registry.nodes.mismatch ~= nil, "mismatch cannot migrate configuration")

-- A target in another zone retains that zone; a coverage collision aborts before erase.
reset({ old = oldNode(), new = freshNode("new", "zone_b") })
coverageAllows = false
local blocked = dispatch("requestRebindProposal", { networkId = "net_a", nodeId = "old" })
local blockedResult = dispatch("rebindNode", { networkId = "net_a", nodeId = "old", rebindToken = blocked.token })
assertEqual(blockedResult.ok, false, "coverage preflight must reject")
assertTrue(registry.nodes.old ~= nil and registry.nodes.new ~= nil, "failed preflight must preserve records")
coverageAllows = true
local accepted = dispatch("requestRebindProposal", { networkId = "net_a", nodeId = "old" })
local moved = dispatch("rebindNode", { networkId = "net_a", nodeId = "old", rebindToken = accepted.token })
assertTrue(moved.ok, "zone-compatible rebind must pass after coverage preflight")
assertEqual(registry.nodes.new.zoneId, "zone_b", "destination zone must win")

-- The scan merge itself refreshes mutable physical fields for one ID without
-- overwriting player configuration, and never normalizes an anomalous signature.
reset({
	same = {
		id = "same", zoneId = "zone_a", membership = "active", displayName = "Nombre de Kava",
		priority = 10, rules = { { op = "OR", condition = { type = "item", itemType = "Base.Apple" } } },
		physicalSignature = signature("crate_a"), storedCapacity = { capacity = 20 },
	},
})
local observed = {
	id = "same", x = 1, y = 2, z = 0, name = "Nombre físico nuevo", enabled = true,
	physicalSignature = signature("crate_a"), storedCapacity = { capacity = 90 }, itemSnapshot = { Base = 1 },
}
GlobalStorageSiK.ZoneRefresh.mergeScanResults(registry, registry.zones.zone_a, { observed }, now, true, {})
assertEqual(registry.nodes.same.displayName, "Nombre de Kava", "same ID must retain visible player name")
assertEqual(registry.nodes.same.priority, 10, "same ID must retain logical configuration")
assertEqual(registry.nodes.same.storedCapacity.capacity, 90, "same ID must refresh mutable capacity")
observed.physicalSignature = signature("other_sprite")
GlobalStorageSiK.ZoneRefresh.mergeScanResults(registry, registry.zones.zone_a, { observed }, now + 1, true, {})
assertEqual(registry.nodes.same.physicalSignature.sprite, "crate_a", "signature anomaly must retain prior identity")
assertEqual(registry.nodes.same.physicalAnomaly.code, "SIG", "signature anomaly must be recorded")

reset({ old = oldNode() })
local discovered = freshNode("different")
GlobalStorageSiK.ZoneRefresh.mergeScanResults(registry, registry.zones.zone_a, { discovered }, now, true, {})
assertEqual(registry.nodes.old.offline, true, "new ID must leave the old physical record offline")
assertTrue(registry.nodes.different and registry.nodes.different.rules == nil,
	"new ID must be a clean physical discovery with no inherited configuration")

print("topology_recovery_regression: OK")

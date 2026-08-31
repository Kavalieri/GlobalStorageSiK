-- Authoritative semantic selection is resolved once from a captured revision.
-- The resulting ticket is immutable and exposed only in bounded, sequenced
-- micro-batches; UI detail pages never participate in physical identity.

for _, name in ipairs({
	"GS_Network", "GS_Router", "GS_Zones", "GS_ItemSnapshot", "GS_ZoneRefresh",
	"GS_NativeProduct", "GS_CategoryResolution", "GS_Permissions",
}) do package.loaded[name] = true end

local registry = {
	_inventoryRevision = { net = 9 },
	zones = {
		z1 = { networkId = "net" }, z2 = { networkId = "net" },
		zDenied = { networkId = "net" }, zOther = { networkId = "other" },
	},
	nodes = {},
}

local function row(ids, mediaIndex)
	return {
		fullType = "Base.VHS_Retail", mediaIndex = mediaIndex,
		itemIds = ids, count = #ids,
	}
end

local first, second = {}, {}
for i = 1, 17 do first[#first + 1] = 18 - i end
for i = 18, 34 do second[#second + 1] = i end
second[#second + 1] = 17 -- duplicate across nodes must not duplicate authority.
registry.nodes.a = { zoneId = "z1", itemSnapshot = { a = row(first, 214) } }
registry.nodes.b = { zoneId = "z2", itemSnapshot = { b = row(second, 214) } }
registry.nodes.otherMedia = { zoneId = "z1", itemSnapshot = { c = row({ 90 }, 315) } }
registry.nodes.excluded = { zoneId = "z1", membership = "excluded", itemSnapshot = { d = row({ 91 }, 214) } }
registry.nodes.disabled = { zoneId = "z1", enabled = false, itemSnapshot = { e = row({ 92 }, 214) } }
registry.nodes.offline = { zoneId = "z1", offline = true, itemSnapshot = { f = row({ 93 }, 214) } }
registry.nodes.denied = { zoneId = "zDenied", itemSnapshot = { g = row({ 94 }, 214) } }
registry.nodes.otherNetwork = { zoneId = "zOther", itemSnapshot = { h = row({ 95 }, 214) } }

GlobalStorageSiK = {
	I18n = { getScriptItem = function() return nil end },
	Network = {
		getRegistry = function() return registry end,
		ensureRegistry = function(value)
			value._inventoryRevision = value._inventoryRevision or {}
		end,
		getDefaultNetworkId = function() return "net" end,
	},
	Zones = { getRegistry = function() return registry end },
	Permissions = {
		canAccessZone = function(_, _, zoneId) return zoneId ~= "zDenied" end,
	},
	ItemSnapshot = {}, NativeProduct = {}, CategoryResolution = {}, ZoneRefresh = {},
}

local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/"
dofile(root .. "shared/GS_Index.lua")

local parentKey = "Base.VHS_Retail\31sprite:\31media:214"
local player = {
	getUsername = function() return "Kava" end,
	getPlayerNum = function() return 0 end,
}
local otherPlayer = {
	getUsername = function() return "Other" end,
	getPlayerNum = function() return 1 end,
}

local resolved, reason = GlobalStorageSiK.Index.resolveExactGroup("net", player, parentKey, 9)
assert(resolved and not reason, "captured semantic group did not resolve")
assert(resolved.count == 34 and #resolved.refs == 34,
	"complete group must include every accessible physical unit exactly once")
for i = 1, 34 do
	assert(resolved.refs[i].itemId == i and resolved.refs[i].fullType == "Base.VHS_Retail",
		"authoritative group is incomplete, duplicated, or nondeterministically ordered at " .. tostring(i))
end
local stale, staleReason = GlobalStorageSiK.Index.resolveExactGroup("net", player, parentKey, 8)
assert(not stale and staleReason == "selection_stale",
	"a semantic selector captured against an old revision must be rejected")

local clock = 1000
getTimestampMs = function() return clock end
package.loaded["GS_Index"] = true
local Tickets = dofile(root .. "server/GS_WithdrawSelectionTickets.lua")
local ticket, ticketReason = Tickets.start(player, "net", "inventory", "operation-1",
	parentKey, 9, { mode = "FAST", batchUnits = 25, batchDelayMs = 75 })
assert(ticket and not ticketReason, "valid exact group did not create a ticket")
assert(ticket.count == 34 and ticket.pacing.batchUnits == 10,
	"ticket must freeze the complete group and clamp physical micro-batches to ten")

-- A ticket is a frozen selection: later registry mutations affect new starts,
-- never the already-authorized sequence.
registry._inventoryRevision.net = 10
registry.nodes.a.itemSnapshot.a.itemIds[#registry.nodes.a.itemSnapshot.a.itemIds + 1] = 99
local rejected, rejectReason = Tickets.start(player, "net", "inventory", "operation-stale",
	parentKey, 9, { batchUnits = 10 })
assert(not rejected and rejectReason == "selection_stale",
	"new tickets must reject a revision that became stale")

local wrongPlayer, wrongPlayerReason = Tickets.take(otherPlayer, ticket.id, "net", "inventory",
	"operation-1", 1, 10)
assert(not wrongPlayer and wrongPlayerReason == "ticket_mismatch",
	"ticket must remain bound to its player")
local wrongSequence, wrongSequenceReason = Tickets.take(player, ticket.id, "net", "inventory",
	"operation-1", 2, 10)
assert(not wrongSequence and wrongSequenceReason == "ticket_sequence",
	"future or replayed sequence numbers must not advance the ticket")

local contextTicket = assert(Tickets.start(player, "net", "inventory", "operation-context",
	parentKey, 10, { batchUnits = 10 }))
local wrongTarget, wrongTargetReason = Tickets.take(player, contextTicket.id, "net", "backpack",
	"operation-context", 1, 10)
assert(not wrongTarget and wrongTargetReason == "ticket_mismatch",
	"changing destination must reject the bound ticket")
local destroyedContext, destroyedContextReason = Tickets.take(player, contextTicket.id, "net", "inventory",
	"operation-context", 1, 10)
assert(not destroyedContext and destroyedContextReason == "ticket_expired",
	"a same-player context change must destroy the old ticket immediately")

local allIds = {}
local expectedSizes = { 10, 10, 10, 4 }
for sequence = 1, #expectedSizes do
	local batch, batchReason = Tickets.take(player, ticket.id, "net", "inventory",
		"operation-1", sequence, 99)
	assert(batch and not batchReason, "ticket batch failed at sequence " .. tostring(sequence))
	assert(batch.requested == expectedSizes[sequence] and #batch.itemIds <= 10,
		"ticket emitted an invalid micro-batch at sequence " .. tostring(sequence))
	if sequence == 1 then
		local replay = assert(Tickets.take(player, ticket.id, "net", "inventory",
			"operation-1", sequence, 10))
		for i = 1, #batch.itemIds do
			assert(replay.itemIds[i] == batch.itemIds[i],
				"uncommitted retry must observe the same frozen micro-batch")
		end
	end
	for i = 1, #batch.itemIds do allIds[#allIds + 1] = batch.itemIds[i] end
	local remaining, complete = Tickets.commit(ticket.id, batch.requested)
	assert(remaining == 34 - #allIds and complete == (#allIds == 34),
		"commit did not advance exactly the attempted units")
end
assert(#allIds == 34, "ticket did not expose the complete frozen group")
for i = 1, 34 do assert(allIds[i] == i, "ticket sequence reordered unit " .. tostring(i)) end
local expired, expiredReason = Tickets.take(player, ticket.id, "net", "inventory",
	"operation-1", 5, 10)
assert(not expired and expiredReason == "ticket_expired",
	"completed ticket must be removed instead of remaining reusable")

print("withdraw_exact_group_ticket_regression: OK")

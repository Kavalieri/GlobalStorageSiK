-- Authoritative, single-unit loans for addons whose vanilla operation replaces
-- an item. No client command can attest a replacement. Product-specific content
-- and device validation stay in the trusted addon callbacks.
require "GS_Config"
require "GS_Permissions"
require "GS_TerminalAccess"
require "GS_TerminalRegistry"
require "GS_Addons"
require "GS_Transfer"
require "GS_TransferLock"
require "GS_InventorySync"
require "GS_Index"

local Lease = {}
GlobalStorageSiK.ItemLease = Lease
local GS = GlobalStorageSiK
local KEY = "GlobalStorageSiK_ItemLease_v1"
local MAX_INVENTORY = 8192

local function text(value, limit)
	return type(value) == "string" and #value > 0 and #value <= limit
end

local function integer(value, maximum)
	return type(value) == "number" and value >= 0 and value <= maximum
		and value == math.floor(value)
end

local function anchorValid(anchor)
	return type(anchor) == "table" and integer(anchor.x, 1000000)
		and integer(anchor.y, 1000000) and type(anchor.z) == "number"
		and anchor.z >= -32 and anchor.z <= 32 and anchor.z == math.floor(anchor.z)
end

local function copy(record)
	if not record then return nil end
	local result = {}
	for key, value in pairs(record) do
		if key == "anchor" then result.anchor = { x = value.x, y = value.y, z = value.z }
		else result[key] = value end
	end
	return result
end

local function slot(player, addonId, create)
	if not GS.isAuthoritative() or not player or not text(addonId, 64) or not ModData then return nil end
	local identity = GS.Permissions.getCharacterId(player)
	if not text(identity, 240) then return nil end
	local store = ModData.getOrCreate(KEY)
	local actor = store[identity]
	if not actor and create then actor = {}; store[identity] = actor end
	return actor, actor and actor[addonId]
end

local function findHeld(player, id)
	local inventory = player and player:getInventory()
	return inventory and inventory:getItemById(id) or nil
end

local function authorize(player, record)
	if not GS.isAuthoritative() then return false, "authority_required" end
	if not player or player:isDead() then return false, "no_player" end
	if not text(record.networkId, 160) or not text(record.addonId, 64)
		or not anchorValid(record.anchor) then return false, "invalid_request" end
	if not GS.Permissions.canAccess(player, record.networkId) then return false, "no_permission" end
	if not GS.AddonRegistry.isModActive(record.addonId)
		or not GS.Addons.isInstalled(record.networkId, record.anchor, record.addonId) then
		return false, "addon_unavailable"
	end
	if not GS.TerminalRegistry.squareHasTerminal(record.anchor.x, record.anchor.y, record.anchor.z) then
		return false, "no_terminal"
	end
	if GS.Network.findNetworkIdAtTerminal(record.anchor.x, record.anchor.y, record.anchor.z,
		{ activeOnly = true }) ~= record.networkId then return false, "terminal_mismatch" end
	local allowed, _, _, reason = GS.TerminalAccess.evaluate(player, record.networkId,
		record.anchor, { ignoreSession = true, strictDistance = true })
	return allowed == true, reason
end

local function locked(player, record, callback)
	return GS.TransferLock.withNetworkLock(record.networkId, player, "item_lease", callback)
end

local function inventoryIds(player)
	local items = player:getInventory():getItems()
	if items:size() > MAX_INVENTORY then return nil end
	local ids = {}
	for i = 0, items:size() - 1 do ids[tostring(items:get(i):getID())] = true end
	return ids
end

-- One persistent slot per actor/addon: unresolved loans are never expired.
-- Monotonic sequence rejects old requests without an unbounded receipt list.
function Lease.get(player, addonId)
	local actor, record = slot(player, addonId, false)
	if not GS.isAuthoritative() then return false, "authority_required" end
	if not player or not text(addonId, 64) then return false, "invalid_request" end
	return true, "OK", copy(record), record and record.sequence + 1 or 1
end

function Lease.check(player, addonId, sequence)
	local _, record = slot(player, addonId, false)
	if not record or record.sequence ~= sequence then return false, "unknown_loan" end
	return authorize(player, record)
end

function Lease.checkAccess(player, addonId, networkId, anchor)
	return authorize(player, { addonId = addonId, networkId = networkId, anchor = anchor })
end

-- Read-only pages for a trusted addon predicate. Cursors are hints, never proof
-- of ownership: borrow resolves the exact unit again. No background scan/cache.
function Lease.listCandidates(player, args, inspect)
	if type(args) ~= "table" or type(inspect) ~= "function"
		or not integer(args.node or 1, 1000000) or (args.node or 1) < 1
		or not integer(args.offset or 0, 1000000) then return false, "invalid_request" end
	local allowed, reason = authorize(player, args)
	if not allowed then return false, reason end
	local live = GS.Permissions.filterLiveContainers(player, args.networkId,
		GS.Network.getLiveContainers(args.networkId))
	local ordered = {}
	for i = 1, #live do ordered[i] = live[i] end
	table.sort(ordered, function(a, b) return tostring(a.entry.id) < tostring(b.entry.id) end)
	local node, offset, scanned, visited = args.node or 1, args.offset or 0, 0, 0
	local rows = {}
	while node <= #ordered and scanned < 1024 and visited < 128 and #rows < 100 do
		local source = ordered[node]
		local items = source.container and source.container:getItems()
		visited = visited + 1
		while items and offset < items:size() and scanned < 1024 and #rows < 100 do
			local item = items:get(offset)
			offset, scanned = offset + 1, scanned + 1
			local ok, fingerprint = pcall(inspect, item)
			if ok and text(fingerprint, 240) then
				rows[#rows + 1] = { itemId = item:getID(), fullType = item:getFullType(),
					sourceNodeId = source.entry.id, fingerprint = fingerprint }
			end
		end
		if not items or offset >= items:size() then node, offset = node + 1, 0 end
	end
	return true, "OK", { rows = rows, hasMore = node <= #ordered, node = node, offset = offset,
		inventoryRevision = GS.Index.getInventoryRevision(args.networkId) }
end

function Lease.borrow(player, args, inspect)
	if type(args) ~= "table" or not integer(args.sequence, 2147483646) or args.sequence < 1
		or not integer(args.itemId, 9007199254740991) or not text(args.fullType, 160)
		or not text(args.sourceNodeId, 240) or not text(args.contextKey, 240)
		or type(inspect) ~= "function" then return false, "invalid_request" end
	local allowed, reason = authorize(player, args)
	if not allowed then return false, reason end
	local actor, previous = slot(player, args.addonId, true)
	if not actor then return false, "identity_unavailable" end
	if previous then
		if args.sequence == previous.sequence then
			if args.itemId ~= previous.originalId or args.networkId ~= previous.networkId
				or args.contextKey ~= previous.contextKey then return false, "request_conflict" end
			return true, "replayed", copy(previous)
		end
		if args.sequence <= previous.sequence then return false, "stale_request" end
		if previous.state ~= "settled" then return false, "loan_pending", copy(previous) end
	end
	return locked(player, args, function()
		local source
		local live = GS.Permissions.filterLiveContainers(player, args.networkId,
			GS.Network.getLiveContainers(args.networkId))
		for i = 1, #live do
			if live[i].entry and live[i].entry.id == args.sourceNodeId then
				source = live[i].container and live[i].container:getItemById(args.itemId)
				break
			end
		end
		if not source or source:getFullType() ~= args.fullType then return false, "source_unavailable" end
		local inspected, fingerprint = pcall(inspect, source)
		if not inspected or not text(fingerprint, 240) then return false, "item_rejected" end
		local record = {
			ownerId = GS.Permissions.getCharacterId(player),
			addonId = args.addonId, sequence = args.sequence, networkId = args.networkId,
			originalId = args.itemId, itemId = args.itemId, fullType = args.fullType,
			sourceNodeId = args.sourceNodeId, contextKey = args.contextKey, fingerprint = fingerprint,
			anchor = { x = args.anchor.x, y = args.anchor.y, z = args.anchor.z }, state = "withdrawing",
		}
		actor[args.addonId] = record
		local ok, why, moved, ids = GS.InventorySync.withBatch(function()
			return GS.Transfer.withdrawType(player, args.fullType, args.networkId, 1,
				player:getInventory(), nil, nil, { args.itemId }, nil, nil, 1, args.sourceNodeId)
		end)
		if moved ~= 1 or not ids or tostring(ids[1]) ~= tostring(args.itemId) then
			-- A failed physical transfer does not authorize fabricating a replacement.
			if moved == 0 and not findHeld(player, args.itemId)
				and source:getContainer() ~= player:getInventory() then record.state = "settled"
			else record.state = "unresolved" end
			return false, why or "withdraw_failed", copy(record)
		end
		record.state = "held"
		return true, "OK", copy(record)
	end)
end

local function current(player, addonId, sequence, contextKey)
	local _, record = slot(player, addonId, false)
	if not record or record.sequence ~= sequence or record.contextKey ~= contextKey then return nil end
	return record
end

-- Explicit recovery of an abandoned device. The trusted addon resolves ref
-- from its persisted device, never from a client's claimed owner/sequence.
-- Only responsibility moves: the physical item remains inside that device.
function Lease.adoptActive(player, addonId, ref, verify)
	if not GS.isAuthoritative() or type(ref) ~= "table" or type(verify) ~= "function"
		or not text(addonId, 64) or not text(ref.ownerId, 240)
		or not text(ref.contextKey, 240) or not integer(ref.sequence, 2147483646) then
		return false, "invalid_request"
	end
	local store = ModData.getOrCreate(KEY)
	local sourceActor = store[ref.ownerId]
	local source = sourceActor and sourceActor[addonId]
	if not source or source.state ~= "active" or source.sequence ~= ref.sequence
		or source.contextKey ~= ref.contextKey then return false, "invalid_transition" end
	local allowed, reason = authorize(player, source)
	if not allowed then return false, reason end
	return locked(player, source, function()
		if source.state ~= "active" or source.sequence ~= ref.sequence
			or source.contextKey ~= ref.contextKey then return false, "invalid_transition" end
		local owner = GS.Permissions.findOnlineCharacter(source.ownerId)
		-- getOnlinePlayers may be an empty Java list in real SP. Preserve
		-- ownership for every local split-screen character as well.
		if not owner and getNumActivePlayers and getSpecificPlayer then
			for i = 0, getNumActivePlayers() - 1 do
				local candidate = getSpecificPlayer(i)
				if candidate and GS.Permissions.getCharacterId(candidate) == source.ownerId then owner = candidate; break end
			end
		end
		if owner and not owner:isDead() then return false, "owner_online" end
		local destination, previous = slot(player, addonId, true)
		if not destination or destination == sourceActor then return false, "invalid_transition" end
		if previous and previous.state ~= "settled" then return false, "loan_pending" end
		local sequence = previous and previous.sequence + 1 or 1
		if sequence > 2147483646 then return false, "sequence_limit" end
		local checked, accepted = pcall(verify, source.fingerprint)
		if not checked or accepted ~= true then return false, "device_mismatch" end
		local adopted = copy(source)
		adopted.ownerId, adopted.sequence = GS.Permissions.getCharacterId(player), sequence
		adopted.handoffTo, adopted.handoffSequence = nil, nil
		destination[addonId] = adopted
		source.state, source.handoffTo, source.handoffSequence = "settled", adopted.ownerId, sequence
		return true, "OK", copy(adopted)
	end)
end

-- Synchronous trusted-side observation around the real vanilla insertion.
-- verify receives the saved content fingerprint and validates the device state.
function Lease.consume(player, addonId, sequence, contextKey, invoke, verify)
	local record = current(player, addonId, sequence, contextKey)
	if not record or record.state ~= "held" or type(invoke) ~= "function"
		or type(verify) ~= "function" then return false, "invalid_transition" end
	local allowed, reason = authorize(player, record)
	if not allowed then return false, reason end
	local item = findHeld(player, record.itemId)
	if not item or item:getFullType() ~= record.fullType then return false, "item_unavailable" end
	record.state = "consuming"
	local invoked = pcall(invoke, item)
	local checked, accepted = pcall(verify, record.fingerprint)
	if not invoked or not checked or accepted ~= true or findHeld(player, record.itemId) then
		record.state = "unresolved"
		return false, "consumption_unconfirmed", copy(record)
	end
	record.state = "active"
	return true, "OK", copy(record)
end

-- Snapshot only the actor's main inventory for this one synchronous vanilla
-- operation. An identical item already held before eject can never be accepted.
function Lease.replace(player, addonId, sequence, contextKey, invoke, verify, matches)
	local record = current(player, addonId, sequence, contextKey)
	if not record or record.state ~= "active" or type(invoke) ~= "function"
		or type(verify) ~= "function" or type(matches) ~= "function" then return false, "invalid_transition" end
	local before = inventoryIds(player)
	if not before then return false, "inventory_limit" end
	record.state = "replacing"
	local invoked = pcall(invoke)
	local checked, empty = pcall(verify)
	local items, successor, count = player:getInventory():getItems(), nil, 0
	if items:size() <= MAX_INVENTORY then
		for i = 0, items:size() - 1 do
			local item = items:get(i)
			if not before[tostring(item:getID())] and item:getFullType() == record.fullType then
				local matched, accepted = pcall(matches, item, record.fingerprint)
				if matched and accepted == true then successor = item; count = count + 1 end
			end
		end
	end
	if not invoked or not checked or empty ~= true or count ~= 1 then
		record.state = "unresolved"
		return false, "replacement_unconfirmed", copy(record)
	end
	record.itemId = tonumber(tostring(successor:getID()))
	record.state = "held"
	return true, "OK", copy(record)
end

-- Recovery does not require the addon to remain installed or a window open.
-- Existing Core permissions, power, capacity and routing still govern deposit.
function Lease.returnItem(player, addonId, sequence)
	local _, record = slot(player, addonId, false)
	if not record or record.sequence ~= sequence then return false, "unknown_loan" end
	if record.state == "settled" then return true, "replayed", copy(record) end
	if record.state ~= "held" then return false, "loan_unresolved", copy(record) end
	if not GS.Permissions.canAccess(player, record.networkId) then return false, "no_permission", copy(record) end
	return locked(player, record, function()
		local item = findHeld(player, record.itemId)
		if not item then
			-- An ordinary/vanilla deposit may already have completed the return.
			-- Reconcile only this exact physical ID in live containers, not a
			-- snapshot, count, or another equivalent unit.
			local live = GS.Permissions.filterLiveContainers(player, record.networkId,
				GS.Network.getLiveContainers(record.networkId))
			for i = 1, #live do
				local stored = live[i].container and live[i].container:getItemById(record.itemId)
				if stored and stored:getFullType() == record.fullType then
					record.state = "settled"
					return true, "reconciled", copy(record)
				end
			end
			return false, "item_unavailable", copy(record)
		end
		if item:getFullType() ~= record.fullType then return false, "item_unavailable", copy(record) end
		local ok, reason = GS.InventorySync.withBatch(function()
			return GS.Transfer.depositItem(player, item, record.networkId,
				{ preferredNodeId = record.sourceNodeId })
		end)
		if ok then record.state = "settled" end
		return ok == true, reason or "OK", copy(record)
	end)
end

-- Called after the existing physical Core deposit, never before mutation.
function Lease.settleByExactItem(player, networkId, item)
	local actor = slot(player, "_lookup", false)
	if not actor or not item then return false end
	local settled = false
	for _, record in pairs(actor) do
		if record.state == "held" and record.networkId == networkId
			and tostring(record.itemId) == tostring(item:getID()) and record.fullType == item:getFullType() then
			record.state = "settled"
			settled = true
		end
	end
	return settled
end

return Lease

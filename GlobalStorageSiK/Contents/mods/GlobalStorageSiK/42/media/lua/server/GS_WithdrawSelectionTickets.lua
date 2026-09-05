require "GS_Index"

GlobalStorageSiK = GlobalStorageSiK or {}
GlobalStorageSiK.WithdrawSelectionTickets = GlobalStorageSiK.WithdrawSelectionTickets or {}

local Tickets = GlobalStorageSiK.WithdrawSelectionTickets
local TTL_MS = 30000
local MAX_TICKETS_PER_PLAYER = 4
local MAX_REFS = 100000
local serial = 0
local records = {}
local nextSweepMs = 0

local function nowMs()
	if getTimestampMs then return tonumber(getTimestampMs()) or 0 end
	if getTimestamp then return (tonumber(getTimestamp()) or 0) * 1000 end
	return 0
end

local function playerKey(player)
	local username = nil
	if player and player.getUsername then
		local ok, value = pcall(function() return player:getUsername() end)
		if ok then username = value end
	end
	local playerNum = player and player.getPlayerNum and player:getPlayerNum() or -1
	return tostring(username or "?") .. "\31" .. tostring(playerNum)
end

local function sweepExpired(now)
	local expired = {}
	for ticketId, ticket in pairs(records) do
		if now <= 0 or now < (ticket.touchedMs or 0)
			or now - (ticket.touchedMs or ticket.createdMs or 0) > TTL_MS then
			expired[#expired + 1] = ticketId
		end
	end
	for i = 1, #expired do records[expired[i]] = nil end
end

local function countForPlayer(key)
	local count = 0
	for _, ticket in pairs(records) do
		if ticket.playerKey == key then count = count + 1 end
	end
	return count
end

--- Called by the existing authoritative scheduler; no additional event hook.
function Tickets.update()
	local now = nowMs()
	if now > 0 and now < nextSweepMs and nextSweepMs - now <= 1000 then return end
	nextSweepMs = now + 1000
	sweepExpired(now)
end

---@return table|nil ticket
---@return string|nil reason
function Tickets.start(player, networkId, targetKey, pacingId, rowKey, revision, pacing, sourceNodeId)
	local now = nowMs()
	sweepExpired(now)
	if now <= 0 then return nil, "clock_unavailable" end
	local key = playerKey(player)
	if countForPlayer(key) >= MAX_TICKETS_PER_PLAYER then return nil, "ticket_limit" end
	local selection, reason = GlobalStorageSiK.Index.resolveExactGroup(
		networkId, player, rowKey, revision, sourceNodeId)
	if not selection then return nil, reason end
	if #selection.refs > MAX_REFS then return nil, "selection_too_large" end
	serial = serial + 1
	local ticketId = tostring(now) .. "-" .. tostring(serial)
	local ticket = {
		id = ticketId,
		playerKey = key,
		networkId = networkId,
		sourceNodeId = sourceNodeId,
		targetKey = tostring(targetKey or ""),
		pacingId = tostring(pacingId or ""),
		rowKey = rowKey,
		revision = selection.revision,
		refs = selection.refs,
		count = selection.count,
		offset = 1,
		sequence = 1,
		pacing = {
			mode = pacing and pacing.mode or "SAFE",
			batchUnits = math.max(1, math.min(10,
				math.floor(tonumber(pacing and pacing.batchUnits) or 10))),
			batchDelayMs = math.max(0,
				math.floor(tonumber(pacing and pacing.batchDelayMs) or 400)),
		},
		createdMs = now,
		touchedMs = now,
	}
	records[ticketId] = ticket
	return ticket, nil
end

local function boundTicket(player, ticketId, networkId, targetKey, pacingId)
	local now = nowMs()
	sweepExpired(now)
	local ticket = type(ticketId) == "string" and records[ticketId] or nil
	if not ticket then return nil, "ticket_expired" end
	local key = playerKey(player)
	if ticket.playerKey ~= key then
		return nil, "ticket_mismatch"
	end
	if ticket.networkId ~= networkId
		or ticket.targetKey ~= tostring(targetKey or "")
		or ticket.pacingId ~= tostring(pacingId or "") then
		-- El mismo jugador cambió de red, destino u operación: el ticket ya no
		-- representa su contexto actual y debe destruirse, no quedar vivo hasta
		-- el TTL. Un jugador distinto nunca puede cancelar el ticket ajeno.
		records[ticketId] = nil
		return nil, "ticket_mismatch"
	end
	ticket.touchedMs = now
	return ticket, nil
end

---@return table|nil batch
---@return string|nil reason
function Tickets.take(player, ticketId, networkId, targetKey, pacingId, sequence, limit, sourceNodeId)
	local ticket, reason = boundTicket(player, ticketId, networkId, targetKey, pacingId)
	if not ticket then return nil, reason end
	if ticket.sourceNodeId ~= sourceNodeId then return nil, "ticket_mismatch" end
	if math.floor(tonumber(sequence) or -1) ~= ticket.sequence then
		return nil, "ticket_sequence"
	end
	local first = ticket.refs[ticket.offset]
	if not first then return nil, "ticket_complete" end
	limit = math.max(1, math.min(10, math.floor(tonumber(limit) or 10)))
	local ids = {}
	local index = ticket.offset
	while index <= #ticket.refs and #ids < limit do
		local ref = ticket.refs[index]
		if ref.fullType ~= first.fullType then break end
		ids[#ids + 1] = ref.itemId
		index = index + 1
	end
	return {
		ticket = ticket,
		fullType = first.fullType,
		itemIds = ids,
		requested = #ids,
		selectionCount = ticket.count,
		remainingBefore = #ticket.refs - ticket.offset + 1,
	}, nil
end

function Tickets.commit(ticketId, attempted)
	local ticket = records[ticketId]
	if not ticket then return 0, true end
	ticket.offset = math.min(#ticket.refs + 1,
		ticket.offset + math.max(0, math.floor(tonumber(attempted) or 0)))
	ticket.sequence = ticket.sequence + 1
	ticket.touchedMs = nowMs()
	local remaining = math.max(0, #ticket.refs - ticket.offset + 1)
	if remaining == 0 then records[ticketId] = nil end
	return remaining, remaining == 0
end

function Tickets.cancel(player, ticketId)
	local ticket = type(ticketId) == "string" and records[ticketId] or nil
	if not ticket or ticket.playerKey ~= playerKey(player) then return false end
	records[ticketId] = nil
	return true
end

function Tickets.cancelForPlayer(player)
	local key = playerKey(player)
	local ids = {}
	for ticketId, ticket in pairs(records) do
		if ticket.playerKey == key then ids[#ids + 1] = ticketId end
	end
	for i = 1, #ids do records[ids[i]] = nil end
	return #ids
end

return Tickets

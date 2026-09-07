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
		retryRefs = {},
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
	local fromRetry = #ticket.retryRefs > 0
	local source = fromRetry and ticket.retryRefs or ticket.refs
	local startIndex = fromRetry and 1 or ticket.offset
	local first = source[startIndex]
	if not first then return nil, "ticket_complete" end
	limit = math.max(1, math.min(10, math.floor(tonumber(limit) or 10)))
	local ids, refs = {}, {}
	local index = startIndex
	while index <= #source and #ids < limit do
		local ref = source[index]
		if ref.fullType ~= first.fullType then break end
		ids[#ids + 1] = ref.itemId
		refs[#refs + 1] = ref
		index = index + 1
	end
	local remainingBefore = #ticket.retryRefs + math.max(0, #ticket.refs - ticket.offset + 1)
	return {
		ticket = ticket,
		fullType = first.fullType,
		itemIds = ids,
		refs = refs,
		fromRetry = fromRetry,
		sequence = ticket.sequence,
		requested = #ids,
		selectionCount = ticket.count,
		remainingBefore = remainingBefore,
	}, nil
end

--- Consume únicamente identidades físicas confirmadas por la transferencia.
-- Las no movidas vuelven a una cola corta prioritaria; el resto del ticket no
-- se reconstruye en cada microlote, evitando coste cuadrático con selecciones
-- grandes. El batch es además la capacidad intransferible: debe ser exactamente
-- el obtenido por take(), con el mismo ticket y secuencia.
function Tickets.commit(batch, movedItemIds)
	local ticket = type(batch) == "table" and batch.ticket or nil
	if not ticket or records[ticket.id] ~= ticket or batch.sequence ~= ticket.sequence then
		return nil, nil, nil, "ticket_sequence"
	end
	local attempted, confirmed = {}, {}
	for i = 1, #(batch.refs or {}) do
		local ref = batch.refs[i]
		local itemId = ref and tonumber(ref.itemId) or nil
		if itemId then attempted[tostring(math.floor(itemId))] = true end
	end
	for i = 1, #(movedItemIds or {}) do
		local itemId = tonumber(movedItemIds[i])
		local key = itemId and tostring(math.floor(itemId)) or nil
		if key and attempted[key] then confirmed[key] = true end
	end
	local retry, consumed = {}, 0
	for i = 1, #(batch.refs or {}) do
		local ref = batch.refs[i]
		local itemId = ref and tonumber(ref.itemId) or nil
		local key = itemId and tostring(math.floor(itemId)) or nil
		if key and confirmed[key] then consumed = consumed + 1
		else retry[#retry + 1] = ref end
	end
	if batch.fromRetry then
		local kept = {}
		for i = #batch.refs + 1, #ticket.retryRefs do
			kept[#kept + 1] = ticket.retryRefs[i]
		end
		for i = 1, #kept do retry[#retry + 1] = kept[i] end
		ticket.retryRefs = retry
	else
		ticket.offset = ticket.offset + #batch.refs
		for i = 1, #retry do ticket.retryRefs[#ticket.retryRefs + 1] = retry[i] end
	end
	ticket.sequence = ticket.sequence + 1
	ticket.touchedMs = nowMs()
	local remaining = #ticket.retryRefs + math.max(0, #ticket.refs - ticket.offset + 1)
	if remaining == 0 then records[ticket.id] = nil end
	return remaining, remaining == 0, consumed, nil
end

function Tickets.cancel(player, ticketId)
	local ticket = type(ticketId) == "string" and records[ticketId] or nil
	if not ticket or ticket.playerKey ~= playerKey(player) then return nil end
	records[ticketId] = nil
	return ticket
end

function Tickets.cancelForPlayer(player)
	local key = playerKey(player)
	local ids = {}
	local cancelled = {}
	for ticketId, ticket in pairs(records) do
		if ticket.playerKey == key then ids[#ids + 1] = ticketId end
	end
	for i = 1, #ids do
		local ticket = records[ids[i]]
		if ticket then cancelled[#cancelled + 1] = ticket end
		records[ids[i]] = nil
	end
	return cancelled
end

return Tickets

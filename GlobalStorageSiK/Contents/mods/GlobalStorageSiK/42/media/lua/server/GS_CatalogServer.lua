-- One immutable transport snapshot per recipient. Called by the existing
-- server flush, never a new permanent event or an inventory/world scan.
local Codec = require "GS_CatalogCodec"
local Server = {}
GlobalStorageSiK.CatalogServer = Server
local sessions, jobs, order = {}, {}, {}
local serial, cursor, retainedBytes, lastPrune = 0, 0, 0, 0
local context
local SESSION_LIMIT = 256
local GLOBAL_BYTES = 64 * 1024 * 1024
local TIMEOUT_MS = 60000
local function now() return getTimestampMs and getTimestampMs() or 0 end
local function log(event, data)
	if GlobalStorageSiK.Log then GlobalStorageSiK.Log.debug("CatalogTransport", event, data) end
end
local function release(player)
	local job = jobs[player]
	if job then retainedBytes = retainedBytes - job.bytes; jobs[player] = nil end
end
function Server.configure(value) context = value end
function Server.isOpening(player) return sessions[player] and sessions[player].openUi == true end
function Server.hasJob(player) return jobs[player] ~= nil end
function Server.clear(player)
	release(player)
	sessions[player] = nil
	for i = #order, 1, -1 do if order[i] == player then table.remove(order, i) end end
	if cursor > #order then cursor = 0 end
end
local function send(player, command, payload)
	local size, reason = Codec.size(payload)
	-- Includes packet ID, module/command UTF strings and optional engine fields.
	if not size or size + 128 > Codec.FRAME_BYTES then return false, reason or "catalog_budget" end
	local ok = pcall(context.send, player, command, payload)
	return ok, ok and nil or "catalog_send"
end
local function failure(player, reason, batchId)
	local session = sessions[player]
	if not session then return end
	Server.clear(player)
	if context.abort then context.abort(player) end
	send(player, "terminalCatalogError", {playerNum=session.playerNum, openSeq=session.openSeq,
		networkId=session.networkId, batchId=batchId or serial, reason=reason})
	log("failed", "batch=" .. tostring(batchId) .. " reason=" .. tostring(reason))
end
function Server.begin(player, confirmation)
	if not context then return false end
	local live = {}
	context.visit(function(p) live[p] = true end)
	local retired = {}
	for p in pairs(sessions) do if not live[p] then retired[#retired + 1] = p end end
	for i = 1, #retired do
		Server.clear(retired[i])
		if context.abort then context.abort(retired[i]) end
	end
	Server.clear(player)
	if #order >= SESSION_LIMIT then
		if context.abort then context.abort(player) end
		send(player, "terminalCatalogError", {playerNum=confirmation.playerNum,
			openSeq=confirmation.openSeq, networkId=confirmation.networkId, reason="catalog_busy", batchId=serial})
		return false
	end
	confirmation.openUi = true
	sessions[player] = confirmation
	order[#order + 1] = player
	local ok = send(player, "terminalOpenAck", confirmation)
	if not ok then
		Server.clear(player)
		if context.abort then context.abort(player) end
	end
	return ok
end
function Server.queue(player, payload)
	local session = sessions[player]
	if not session or session.networkId ~= payload.networkId then return false end
	local valid, invalidReason = context.valid(player, session, payload)
	if not valid then
		if invalidReason then failure(player, invalidReason, serial) else Server.clear(player) end
		return false
	end
	-- Latest state supersedes an unfinished one; do not hold both snapshots.
	release(player)
	serial = serial + 1
	payload.playerNum, payload.openSeq = session.playerNum, session.openSeq
	payload.accessProbeId = nil -- The independent access ACK consumes the probe.
	if session.openUi then
		payload.openUi = true
		payload.accessMode, payload.terminalAnchor = session.accessMode, session.terminalAnchor
		payload.confirmedProximityRange = session.confirmedProximityRange
		payload.confirmedWirelessRange = session.confirmedWirelessRange
	end
	local envelope = {protocol=1, playerNum=session.playerNum, openSeq=session.openSeq,
		networkId=payload.networkId, inventoryRevision=payload.inventoryRevision,
		catalogScope=payload.catalogScope, batchId=serial, part=1, total=1,
		tokenCount=1, totalBytes=1, data={}}
	local overhead = Codec.size(envelope)
	if not overhead then failure(player, "catalog_budget", serial); return false end
	local encodeStarted = now()
	local encoded, reason = Codec.encode(payload, Codec.FRAME_BYTES - overhead - 128)
	if not encoded then failure(player, reason, serial); return false end
	if retainedBytes + encoded.totalBytes > GLOBAL_BYTES then
		failure(player, "catalog_busy", serial); return false
	end
	envelope.total, envelope.tokenCount, envelope.totalBytes = #encoded.chunks, encoded.tokenCount, encoded.totalBytes
	-- Account conservatively for transient token/table overhead as well as
	-- serialized bytes; this is an admission estimate, not a JVM heap claim.
	local reservation = encoded.totalBytes * 2 + encoded.tokenCount * 64 + #encoded.chunks * 128
	if retainedBytes + reservation > GLOBAL_BYTES then
		failure(player, "catalog_busy", serial); return false
	end
	jobs[player] = {envelope=envelope, chunks=encoded.chunks, bytes=reservation, wireBytes=encoded.totalBytes,
		nextPart=1, started=now(), rows=payload.itemTypeCount or 0}
	retainedBytes = retainedBytes + reservation
	log("queued", "batch=" .. tostring(serial) .. " rows=" .. tostring(payload.itemTypeCount or 0)
		.. " parts=" .. tostring(#encoded.chunks) .. " bytes=" .. tostring(encoded.totalBytes)
		.. " encodeMs=" .. tostring(now() - encodeStarted))
	return true
end

--- Sends one bounded catalog delta inside the already authorized terminal
--- session. Oversized deltas return false so the caller can use the normal
--- fragmented full-catalog transport without truncating any row.
function Server.delta(player, payload)
	local session = sessions[player]
	if not session or session.networkId ~= payload.networkId then return false, "catalog_session" end
	local valid, invalidReason = context.valid(player, session, payload)
	if not valid then return false, invalidReason or "catalog_access_changed" end
	payload.protocol = 1
	payload.playerNum, payload.openSeq = session.playerNum, session.openSeq
	local sent, reason = send(player, "terminalCatalogDelta", payload)
	log(sent and "delta_sent" or "delta_fallback", "base=" .. tostring(payload.baseRevision)
		.. " revision=" .. tostring(payload.inventoryRevision)
		.. " changed=" .. tostring(#(payload.changedRows or {}))
		.. " removed=" .. tostring(#(payload.removedRowKeys or {}))
		.. " reason=" .. tostring(reason))
	return sent, reason
end
function Server.receipt(player, payload)
	local session, job = sessions[player], jobs[player]
	if not session or not job or type(payload) ~= "table" then return end
	local meta = job.envelope
	if payload.openSeq ~= session.openSeq or payload.networkId ~= session.networkId
		or payload.batchId ~= meta.batchId or payload.inventoryRevision ~= meta.inventoryRevision
		or payload.catalogScope ~= meta.catalogScope then return end
	-- Receipt is only a transport acknowledgement, never permission or mutation.
	if job.nextPart <= meta.total then return end
	session.openUi = false
	log("completed", "batch=" .. tostring(meta.batchId) .. " rows=" .. tostring(job.rows)
		.. " bytes=" .. tostring(job.wireBytes))
	release(player)
end
function Server.update()
	if not context or #order == 0 then return end
	local timestamp, visited, sent = now(), 0, 0
	-- Only active sessions retain player references. The existing flush removes
	-- disconnected recipients even when no new opening arrives to prune them.
	if timestamp < lastPrune or timestamp - lastPrune >= 1000 then
		lastPrune = timestamp
		local live, retired = {}, {}
		context.visit(function(player) live[player] = true end)
		for player in pairs(sessions) do if not live[player] then retired[#retired + 1] = player end end
		for i = 1, #retired do
			Server.clear(retired[i])
			if context.abort then context.abort(retired[i]) end
		end
	end
	-- Four frames globally per tick, round robin; quiet sessions send nothing.
	-- Revisit busy recipients to use the existing budget even with one player.
	-- Bound idle traversal and re-check length: SP callbacks may remove sessions.
	local visitBudget = #order * 4
	while #order > 0 and visited < visitBudget and sent < 4 do
		cursor = cursor % #order + 1
		local player = order[cursor]
		local job, session = jobs[player], sessions[player]
		visited = visited + 1
		if job and session then
			local valid, invalidReason = context.valid(player, session, job.envelope)
			if timestamp < job.started then job.started = timestamp end
			if timestamp - job.started >= TIMEOUT_MS then
				failure(player, "catalog_timeout", job.envelope.batchId)
			elseif not valid then
				local networkId = session.networkId
				release(player)
				if invalidReason then
					failure(player, invalidReason, job.envelope.batchId)
				else context.stale(player, networkId) end
			elseif job.nextPart <= job.envelope.total then
				local frame = {}
				for key, value in pairs(job.envelope) do frame[key] = value end
				frame.part, frame.data = job.nextPart, job.chunks[job.nextPart]
				-- Advance before dispatch: SP may deliver a synchronous receipt.
				job.nextPart = job.nextPart + 1
				local ok, reason = send(player, "terminalCatalogChunk", frame)
				if ok then job.started = timestamp end
				sent = sent + 1
				if not ok then failure(player, reason, frame.batchId) end
			end
		end
	end
end
return Server

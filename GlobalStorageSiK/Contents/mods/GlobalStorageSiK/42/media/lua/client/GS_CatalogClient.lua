-- Private reassembly: no partial table reaches the inventory/UI consumers.
local Codec = require "GS_CatalogCodec"
local Client = {}
GlobalStorageSiK.CatalogClient = Client
local slots = {}
local context
local TIMEOUT_MS = 60000
local IDLE_MS = 10000
local function now() return getTimestampMs and getTimestampMs() or 0 end
function Client.configure(value) context = value end
function Client.clear(playerNum, sequence)
	if playerNum == nil then slots = {}
	elseif sequence == nil or (slots[playerNum] and slots[playerNum].sequence == sequence) then
		slots[playerNum] = nil
	end
end
function Client.start(playerNum, sequence)
	slots[playerNum] = {sequence=sequence, latest=0, started=now()}
end
local function slotFor(payload)
	if type(payload) ~= "table" or not Codec.integer(payload.playerNum, 0, 3) then return end
	local slot = slots[payload.playerNum]
	if not slot or slot.sequence ~= payload.openSeq or not context
		or not context.current(payload.playerNum, payload.openSeq) then return end
	return slot
end
local function fail(playerNum, reason)
	local slot = slots[playerNum]
	if not slot then return end
	slots[playerNum] = nil -- Fence before callbacks/close to avoid reentrancy.
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.debug("CatalogTransport", "failed", "player=" .. tostring(playerNum)
			.. " openSeq=" .. tostring(slot.sequence) .. " reason=" .. tostring(reason))
	end
	context.failure(playerNum, slot.sequence, reason, slot.confirmed ~= nil)
end
local function same(a, b)
	return a.batchId == b.batchId and a.networkId == b.networkId and a.openSeq == b.openSeq
		and a.playerNum == b.playerNum and a.inventoryRevision == b.inventoryRevision
		and a.catalogScope == b.catalogScope and a.total == b.total
		and a.tokenCount == b.tokenCount and a.totalBytes == b.totalBytes
end
local function applyReady(playerNum, slot)
	local batch = slot.batch
	if not slot.confirmed or not batch or batch.count ~= batch.meta.total then return end
	if slot.confirmed.networkId ~= batch.meta.networkId then fail(playerNum, "catalog_schema"); return end
	if batch.bytes ~= batch.meta.totalBytes or batch.tokens ~= batch.meta.tokenCount then
		fail(playerNum, "catalog_incomplete"); return
	end
	local decodeStarted = now()
	local value, reason = Codec.decode(batch.parts, batch.meta.tokenCount)
	if not value then fail(playerNum, reason); return end
	if value.networkId ~= batch.meta.networkId or value.openSeq ~= batch.meta.openSeq
		or value.playerNum ~= playerNum or value.inventoryRevision ~= batch.meta.inventoryRevision
		or value.catalogScope ~= batch.meta.catalogScope then fail(playerNum, "catalog_schema"); return end
	if value.notModified ~= true and (type(value.items) ~= "table"
		or value.itemTypeCount ~= #value.items) then fail(playerNum, "catalog_incomplete"); return end
	-- A queued refresh may replace the first snapshot before its receipt. Only
	-- the client's live opening intent decides whether completion opens a view.
	value.openUi = context.pending(playerNum) == true
	value.accessProbeId = nil
	if not context.allowed(slot.confirmed) then fail(playerNum, "catalog_access_changed"); return end
	if value.notModified == true and not context.hasCache(value) then
		fail(playerNum, "catalog_cache_miss"); return
	end
	slot.batch = nil
	slot.completedRevision = value.inventoryRevision
	local ok, accepted = pcall(context.apply, value)
	-- Consumer callbacks may close/reopen synchronously (including SP).
	-- Completion of the old request cannot fail or acknowledge its replacement.
	if slots[playerNum] ~= slot then return end
	if not ok or accepted == false then fail(playerNum, "catalog_apply"); return end
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.debug("CatalogTransport", "applied", "player=" .. tostring(playerNum)
			.. " openSeq=" .. tostring(slot.sequence) .. " batch=" .. tostring(batch.meta.batchId)
			.. " receiveMs=" .. tostring(decodeStarted - batch.started)
			.. " decodeApplyMs=" .. tostring(now() - decodeStarted))
	end
	context.receipt(batch.meta)
end
function Client.ack(payload)
	local slot = slotFor(payload)
	if not slot or slot.confirmed then return end
	if type(payload.networkId) ~= "string" or not context.allowed(payload) then
		fail(payload.playerNum, "catalog_access_changed"); return
	end
	if not context.confirm(payload) then return end
	slot.confirmed = payload
	slot.started = now()
	if context.progress then context.progress(payload, 0, nil) end
	if slots[payload.playerNum] ~= slot then return end
	applyReady(payload.playerNum, slot)
end
function Client.receive(payload)
	local slot = slotFor(payload)
	if not slot then return end
	if payload.protocol ~= 1 or not Codec.integer(payload.batchId, 1, 9007199254740991)
		or not Codec.integer(payload.total, 1, Codec.MAX_CHUNKS)
		or not Codec.integer(payload.part, 1, payload.total)
		or not Codec.integer(payload.tokenCount, 1, Codec.MAX_TOKENS)
		or not Codec.integer(payload.totalBytes, 1, Codec.MAX_BATCH_BYTES)
		or not Codec.integer(payload.inventoryRevision, 0, 9007199254740991)
		or type(payload.catalogScope) ~= "string" or type(payload.networkId) ~= "string"
		or type(payload.data) ~= "table" then fail(payload.playerNum, "catalog_schema"); return end
	if payload.batchId < slot.latest then return end
	if slot.confirmed and slot.confirmed.networkId ~= payload.networkId then return end
	if slot.completedRevision and payload.inventoryRevision < slot.completedRevision then return end
	local size = Codec.size(payload)
	if not size or size + 128 > Codec.FRAME_BYTES then fail(payload.playerNum, "catalog_budget"); return end
	if payload.batchId == slot.latest and not slot.batch then return end -- completed duplicate
	if payload.batchId > slot.latest then
		if slot.batch and payload.inventoryRevision < slot.batch.meta.inventoryRevision then return end
		slot.latest = payload.batchId
		slot.batch = {meta=payload, parts={}, count=0, bytes=0, tokens=0, started=now(), progress=now()}
	end
	local batch = slot.batch
	if not same(batch.meta, payload) then fail(payload.playerNum, "catalog_schema"); return end
	local count = 0
	for key, token in pairs(payload.data) do
		if not Codec.integer(key, 1, Codec.MAX_TOKENS) or (type(token) ~= "string"
			and type(token) ~= "number" and type(token) ~= "boolean") then
			fail(payload.playerNum, "catalog_schema"); return
		end
		count = count + 1
	end
	for i = 1, count do if payload.data[i] == nil then fail(payload.playerNum, "catalog_schema"); return end end
	local previous = batch.parts[payload.part]
	if previous then
		if #previous ~= count then fail(payload.playerNum, "catalog_duplicate"); return end
		for i = 1, count do
			if previous[i] ~= payload.data[i] then fail(payload.playerNum, "catalog_duplicate"); return end
		end
		return -- Exact duplicates do not extend the deadline.
	end
	batch.parts[payload.part] = payload.data
	batch.count, batch.tokens = batch.count + 1, batch.tokens + count
	batch.bytes = batch.bytes + (Codec.size(payload.data) or Codec.MAX_BATCH_BYTES + 1)
	batch.progress = now()
	slot.started = batch.progress
	if batch.tokens > batch.meta.tokenCount or batch.bytes > batch.meta.totalBytes then
		fail(payload.playerNum, "catalog_budget"); return
	end
	-- Only accepted, unique fragments advance presentation. A complete batch
	-- still remains non-operable until decoding and the consumer apply finish.
	if slot.confirmed and context.progress then context.progress(batch.meta, batch.count, batch.meta.total) end
	if slots[payload.playerNum] ~= slot then return end
	applyReady(payload.playerNum, slot)
end
function Client.error(payload)
	local slot = slotFor(payload)
	if not slot then return end
	if slot.confirmed and payload.networkId ~= slot.confirmed.networkId then return end
	if type(payload.batchId) == "number" and payload.batchId < slot.latest then return end
	fail(payload.playerNum, payload.reason or "catalog_send")
end
function Client.update(timestamp)
	local active = false
	for playerNum = 0, 3 do
		local slot = slots[playerNum]
		if slot then
			if not context.current(playerNum, slot.sequence) then slots[playerNum] = nil
			else
				local batch = slot.batch
				if batch or (slot.confirmed and context.pending(playerNum)) then
					active = true
					if timestamp < slot.started then slot.started = timestamp end
					if batch and timestamp < batch.progress then batch.progress = timestamp end
					if (context.pending(playerNum) and timestamp - slot.started >= TIMEOUT_MS)
						or (batch and timestamp - batch.progress >= IDLE_MS) then
						fail(playerNum, "catalog_timeout")
					elseif slot.confirmed and not context.allowed(slot.confirmed) then
						fail(playerNum, "catalog_access_changed")
					end
				end
			end
		end
	end
	return active
end
return Client

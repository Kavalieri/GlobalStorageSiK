-- Private reassembly: no partial table reaches the inventory/UI consumers.
local Codec = require "GS_CatalogCodec"
local AccessPolicy = require "GS_ManifestProtocol"
local Metrics=require "GS_InitialLoadMetrics"
local Profile=require "GS_InitialLoadProfile"
local Client = {}
GlobalStorageSiK.CatalogClient = Client
local slots = {}
local context
local TIMEOUT_MS = 60000
local IDLE_MS = 10000
local FRAGMENT_RETRY_MS = 1500
local APPLIED_WINDOW = 8
local PLAYER_BYTES, GLOBAL_BYTES = 32*1024*1024, 64*1024*1024
local function now() return getTimestampMs and getTimestampMs() or 0 end
local function diagnosticsEnabled()
    local sandbox=GlobalStorageSiK.Sandbox
    return GlobalStorageSiK.Log and sandbox and sandbox.debugMode()
        and sandbox.debugCategoryEnabled("CatalogTransport")
end
function Client.configure(value) context = value end
function Client.clear(playerNum, sequence)
	if playerNum == nil then
		for n=0,3 do Metrics.finish(slots[n] and slots[n].summary,"cancelled","session_closed") end
		if GlobalStorageSiK.NodeCatalogClient then for n=0,3 do GlobalStorageSiK.NodeCatalogClient.clear(n,false) end end
		slots = {}
	elseif sequence == nil or (slots[playerNum] and slots[playerNum].sequence == sequence) then
		Metrics.finish(slots[playerNum] and slots[playerNum].summary,"cancelled","session_closed")
		if GlobalStorageSiK.NodeCatalogClient then GlobalStorageSiK.NodeCatalogClient.clear(playerNum,false) end
		slots[playerNum] = nil
	end
end
function Client.replicaApplied(playerNum,revision)
	local slot=slots[playerNum]
	if slot then slot.completedRevision=revision;slot.applied=true;slot.recoveryUsed=nil;slot.started=now() end
end
function Client.start(playerNum, sequence)
	Metrics.finish(slots[playerNum] and slots[playerNum].summary,"cancelled","reopened")
	if GlobalStorageSiK.NodeCatalogClient then GlobalStorageSiK.NodeCatalogClient.clear(playerNum,false) end
	slots[playerNum] = {sequence=sequence, latest=0, started=now(),completedBatches={},completedOrder={},
		summary=Metrics.begin("client",{playerNum=playerNum,openSeq=sequence})}
end
function Client.metrics(playerNum) return slots[playerNum] and slots[playerNum].summary end
-- Accepted progress belongs to one negotiated opening. Presence of a batch,
-- repeated fragments and another split-screen player's work are not progress.
function Client.replicaProgress(ack)
	local slot=slots[ack.playerNum]
	local confirmed=slot and slot.confirmed
	if confirmed and slot.sequence==ack.openSeq and confirmed.networkId==ack.networkId
		and confirmed.replicaEpoch==ack.replicaEpoch and confirmed.catalogScope==ack.catalogScope
		and (confirmed.topologySequence or 0)==(ack.topologySequence or 0) then
		return slot.replicaProgressAt
	end
end
function Client.recordReplicaView(playerNum,rows,complete)
	local slot=slots[playerNum]
	if not slot then return end
	Metrics.view(slot.summary,rows,complete)
	if complete and slot.summary then slot.summary.completePending=true end
end
function Client.recordReplicaComplete(playerNum)
	Metrics.complete(Client.metrics(playerNum))
end
local function slotFor(payload)
	if type(payload) ~= "table" or not Codec.integer(payload.playerNum, 0, 3) then return end
	local slot = slots[payload.playerNum]
	if not slot or slot.sequence ~= payload.openSeq or not context
		or not context.current(payload.playerNum, payload.openSeq) then return end
	return slot
end
local function fail(playerNum, reason, serverError, consumerRejected)
	local slot = slots[playerNum]
	if not slot then return end
	if consumerRejected then slot.consumerRejected=true end
	local recoverable = slot.applied == true and not AccessPolicy.accessLoss(reason)
	local rejected = slot.batch and slot.batch.meta
	if slot.confirmed and slot.confirmed.replicaEpoch and not AccessPolicy.accessLoss(reason)
		and reason~="catalog_budget" and not slot.consumerRejected and context.nodeRecover then
		slot.batch=nil
		if rejected and not serverError and context.reject then context.reject(rejected,reason,false) end
		if context.nodeRecover(playerNum) then slot.started=now();return end
	end
	Metrics.finish(slot.summary,AccessPolicy.accessLoss(reason) and "cancelled"
		or reason=="catalog_timeout" and "timeout" or "failed",reason)
	if recoverable then slot.batch = nil else slots[playerNum] = nil end
	if rejected and not serverError and not AccessPolicy.accessLoss(reason) and context.reject
		and not slot.rejectionSent then context.reject(rejected,reason,slot.consumerRejected==true);slot.rejectionSent=true end
	if slot.consumerRejected and not rejected and context.replicaReject and slot.replicaFailure
		and not slot.rejectionSent then context.replicaReject(slot.replicaFailure,reason);slot.rejectionSent=true end
	if recoverable and slots[playerNum] ~= slot then return end
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.debug("CatalogTransport", "failed", "player=" .. tostring(playerNum)
			.. " openSeq=" .. tostring(slot.sequence) .. " reason=" .. tostring(reason))
	end
	context.failure(playerNum, slot.sequence, reason, slot.confirmed ~= nil, recoverable)
	if recoverable and not slot.consumerRejected and not rejected and not serverError
		and slots[playerNum] == slot and not slot.recoveryUsed then
		slot.recoveryUsed = true
		local recover = context.recover or context.stale
		if recover then recover(rejected or slot.confirmed, reason) end
	end
end
local function allowed(payload, playerNum)
	local started=now()
	local accepted, reason = context.allowed(payload)
	Metrics.work(Client.metrics(playerNum),"validate",now()-started)
	if not accepted then
		fail(playerNum, AccessPolicy.suspendsAccess(reason) and reason or "catalog_access_changed")
	end
	return accepted
end
function Client.abortReplica(playerNum,reason,meta)
	local slot=slots[playerNum]
	if slot then slot.replicaFailure=meta end
	fail(playerNum,reason or "catalog_apply",false,true)
end
local function consumerFailure(playerNum, slot, meta, ok, result, reason, stage)
	if slots[playerNum] ~= slot then return end
	local cause = ok and reason or result
	if type(cause) == "table" then ok = cause.rejected == true or ok; stage, cause = cause.stage or stage, cause.cause end
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.debug("CatalogTransport", "consumer_failed",
			"stage=" .. tostring(stage or "terminalState") .. " outcome=" .. (ok and "rejected" or "exception")
			.. " cause=" .. tostring(cause or "false"):gsub("[%c]", " "):sub(1,240)
			.. " batch=" .. tostring(meta.batchId) .. " openSeq=" .. tostring(slot.sequence)
			.. " revision=" .. tostring(meta.inventoryRevision) .. " scope=" .. tostring(meta.catalogScope):sub(1,120)
			.. " source=" .. tostring(meta.catalogSource))
	end
	fail(playerNum, AccessPolicy.accessLoss(cause) and cause or "catalog_apply",false,true)
end
local function same(a, b)
	return a.protocol == b.protocol and a.batchId == b.batchId and a.networkId == b.networkId and a.openSeq == b.openSeq
		and a.playerNum == b.playerNum and a.inventoryRevision == b.inventoryRevision
		and (a.topologySequence or 0)==(b.topologySequence or 0)
		and a.catalogScope == b.catalogScope and a.total == b.total
		and a.tokenCount == b.tokenCount and a.totalBytes == b.totalBytes
end
local function rememberApplied(slot,meta)
	local id=meta.batchId
	if not slot.completedBatches[id] then
		slot.completedOrder[#slot.completedOrder+1]=id
		if #slot.completedOrder>APPLIED_WINDOW then
			local retired=table.remove(slot.completedOrder,1);slot.completedBatches[retired]=nil
		end
	end
	local retained={}
	for _,key in ipairs({"protocol","batchId","networkId","openSeq","playerNum","inventoryRevision",
		"topologySequence","catalogScope","total","tokenCount","totalBytes","catalogSource"}) do
		retained[key]=meta[key]
	end
	slot.completedBatches[id]=retained
end
local function payloadReservation(batch,expanded)
	return batch.bytes*2+(batch.tokens+(expanded or batch.expandedKeys or 0))*64
end
local function reservationFor(batch,expanded)
	return payloadReservation(batch,expanded)+Codec.STRING_CACHE_BYTES+Codec.SCHEMA_CACHE_BYTES+Codec.TEXT_CACHE_BYTES
end
local function reserveBatch(slot,batch,expanded)
	local reservation=reservationFor(batch,expanded)+(slot.retainedBytes or 0)
	local global=reservation
	for n=0,3 do
		local other=slots[n]
		if other and other~=slot then global=global+(other.retainedBytes or 0)
			+(other.batch and reservationFor(other.batch) or 0) end
	end
	if reservation>PLAYER_BYTES or global>GLOBAL_BYTES then return false end
	batch.expandedKeys=expanded or batch.expandedKeys or 0
	Metrics.peak(slot.summary,reservation)
	return true
end
local function applyReady(playerNum, slot)
	local batch = slot.batch
	if not slot.confirmed or not batch or batch.count ~= batch.meta.total then return end
	if slot.confirmed.networkId ~= batch.meta.networkId
		or (slot.confirmed.topologySequence or 0)~=(batch.meta.topologySequence or 0)
		or slot.confirmed.catalogScope ~= batch.meta.catalogScope then fail(playerNum, "catalog_schema"); return end
	if batch.bytes ~= batch.meta.totalBytes or batch.tokens ~= batch.meta.tokenCount then
		fail(playerNum, "catalog_incomplete"); return
	end
	-- Receiving the last fragment only schedules decode. The existing update
	-- watcher performs bounded codec work; no callback decodes a whole catalog.
	if not batch.decoded then
		if not batch.decoder then
			local decoder, reason = Codec.beginDecode(batch.parts, batch.meta.tokenCount,slot.profile and slot.profile.frameBytes,
				slot.profile and slot.profile.optimizedCodec,slot.profile and slot.profile.compactTables,
				function(expanded) return slots[playerNum]==slot and slot.batch==batch and reserveBatch(slot,batch,expanded) end)
			if not decoder then fail(playerNum, reason); return end
			batch.decoder, batch.decodeStarted = decoder, now()
			if not batch.reassembled then
			batch.reassembled=true
			Metrics.count(slot.summary,"receiveWaitMs",now()-batch.started)
				if context.reassembled then context.reassembled(batch.meta) end
			end
		end
		return
	end
	local decodeStarted = batch.decodeStarted
	local value = batch.decoded
	if value.networkId ~= batch.meta.networkId or value.openSeq ~= batch.meta.openSeq
		or (value.topologySequence or 0)~=(batch.meta.topologySequence or 0)
		or value.playerNum ~= playerNum or value.inventoryRevision ~= batch.meta.inventoryRevision
		or value.catalogScope ~= batch.meta.catalogScope then fail(playerNum, "catalog_schema"); return end
	if value.catalogManifest ~= true and value.catalogNode ~= true
		and value.catalogDetail ~= true and value.catalogDelta ~= true and value.notModified ~= true and (type(value.items) ~= "table"
		or value.itemTypeCount ~= #value.items) then fail(playerNum, "catalog_incomplete"); return end
	-- A queued refresh may replace the first snapshot before its receipt. Only
	-- the client's live opening intent decides whether completion opens a view.
	value.openUi = value.catalogDetail ~= true and context.pending(playerNum) == true
	value.accessProbeId = nil
	if not allowed(slot.confirmed,playerNum) then return end
	if value.notModified == true and not context.hasCache(value) then
		fail(playerNum, "catalog_cache_miss"); return
	end
	local consumer = (value.catalogManifest == true or value.catalogNode == true) and context.applyNode
		or value.catalogDetail == true and context.applyDetail
		or value.catalogDelta == true and context.applyDelta or context.apply
	local applyStarted=now()
	Metrics.enter(slot.summary)
	local ok, accepted, applyReason, stage = pcall(consumer, value,payloadReservation(batch))
	Metrics.work(slot.summary,"dispatch",now()-applyStarted)
	Metrics.leave(slot.summary)
	-- Consumer callbacks may close/reopen synchronously (including SP).
	-- Completion of the old request cannot fail or acknowledge its replacement.
	if slots[playerNum] ~= slot then return end
	if not ok or accepted == false then
		consumerFailure(playerNum, slot, batch.meta, ok, accepted, applyReason, stage)
		return
	end
	slot.batch = nil
	rememberApplied(slot,batch.meta)
	if value.catalogDetail ~= true and not value.catalogManifest and not value.catalogNode then
		slot.completedRevision, slot.applied = value.inventoryRevision, true
		slot.recoveryUsed = nil
		if value.catalogDelta ~= true then slot.retainedBytes = payloadReservation(batch) end
	end
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.debug("CatalogTransport", "applied", "player=" .. tostring(playerNum)
			.. " openSeq=" .. tostring(slot.sequence) .. " batch=" .. tostring(batch.meta.batchId)
			.. " receiveMs=" .. tostring(decodeStarted - batch.started)
			.. " decodeMs=" .. tostring((batch.decodeFinished or applyStarted)-decodeStarted)
			.. " applyMs=" .. tostring(now()-applyStarted))
	end
	if batch.profile and GlobalStorageSiK.Log then
		local profile=batch.profile
		GlobalStorageSiK.Log.debug("CatalogTransport","profile_client",
			"player="..tostring(playerNum).." openSeq="..tostring(slot.sequence).." batch="..tostring(batch.meta.batchId)
			.." sizeMs="..tostring(profile.sizeMs).." sizeMaxMs="..tostring(profile.sizeMaxMs)
			.." decodeActiveMs="..tostring(profile.decodeMs).." decodeMaxMs="..tostring(profile.decodeMaxMs)
			.." decodeSteps="..tostring(profile.steps).." wallYields="..tostring(profile.wallYields)
			.." unitYields="..tostring(profile.unitYields).." applyMs="..tostring(now()-applyStarted))
	end
	context.receipt(batch.meta)
end
function Client.ack(payload)
	local slot = slotFor(payload)
	if not slot then return end
	if payload.topologyTransition then
		local previous=slot.confirmed
		local Protocol=GlobalStorageSiK.ManifestProtocol
		if previous then
			if previous.networkId~=payload.networkId or previous.replicaEpoch~=payload.replicaEpoch
				or not Protocol.transitionAccepts(payload,previous.catalogScope,previous.topologySequence) then return end
		elseif not Protocol.transitionAccepts(payload,payload.previousCatalogScope,0) then return end
		if payload.topologySequence and not Codec.integer(payload.catalogBatchFloor,0,9007199254740991) then return end
		-- Explicit server fence: old fragments cannot replace the new manifest.
		slot.batch=nil;slot.confirmed=nil
		if payload.catalogBatchFloor then slot.latest=math.max(slot.latest,payload.catalogBatchFloor) end
	elseif slot.confirmed then return end
	if type(payload.networkId) ~= "string" then
		fail(payload.playerNum, "catalog_access_changed"); return
	end
	if not allowed(payload,payload.playerNum) then return end
	local profile=Profile.snapshot(payload.initialLoadProfile or "control")
	if not profile or ((profile.id=="final4" or profile.compactTables or profile.optimizedCodec or payload.initialLoadProfileHash) and payload.initialLoadProfileHash~=profile.hash) then fail(payload.playerNum,"catalog_profile");return end
	local confirmed,accepted,reason=pcall(context.confirm,payload)
	if not confirmed then consumerFailure(payload.playerNum,slot,payload,false,accepted,nil,"catalogAccessConfirm"); return end
	if accepted == false then
		if GlobalStorageSiK.Log then GlobalStorageSiK.Log.debug("CatalogTransport","consumer_failed",
			"stage=catalogAccessConfirm outcome=rejected cause=" .. tostring(reason or "false")) end
		fail(payload.playerNum,"catalog_access_changed"); return
	end
	if slots[payload.playerNum] ~= slot then return end
	slot.confirmed = payload
	slot.profile=profile
	Metrics.bind(slot.summary,payload)
	slot.started = now()
	if (context.hasCache and context.hasCache(payload))
		or (context.hasPreview and context.hasPreview(payload)) then slot.applied = true end
	if context.progress then
		local ok, accepted, reason, stage = pcall(context.progress, payload, 0, nil)
		if not ok or accepted == false then consumerFailure(payload.playerNum, slot, payload, ok, accepted, reason, stage or "catalogPreview"); return end
	end
	if slots[payload.playerNum] ~= slot then return end
	applyReady(payload.playerNum, slot)
	if payload.replicaEpoch and context.negotiate then context.negotiate(payload) end
end
function Client.receive(payload)
	local slot = slotFor(payload)
	if not slot then return end
	if slot.consumerRejected then return end
	if slot.confirmed and (slot.confirmed.topologySequence or 0)~=(payload.topologySequence or 0) then return end
	if (payload.protocol ~= 1 and payload.protocol ~= 2) or not Codec.integer(payload.batchId, 1, 9007199254740991)
		or not Codec.integer(payload.total, 1, Codec.MAX_CHUNKS)
		or not Codec.integer(payload.part, 1, payload.total)
		or not Codec.integer(payload.tokenCount, 1, Codec.MAX_TOKENS)
		or not Codec.integer(payload.totalBytes, 1, Codec.MAX_BATCH_BYTES)
		or not Codec.integer(payload.inventoryRevision, 0, 9007199254740991)
		or type(payload.catalogScope) ~= "string" or type(payload.networkId) ~= "string"
		or type(payload.data) ~= "table" then fail(payload.playerNum, "catalog_schema"); return end
	if payload.batchId < slot.latest then return end
	if slot.confirmed and (slot.confirmed.networkId ~= payload.networkId
		or slot.confirmed.catalogScope ~= payload.catalogScope) then return end
	if slot.completedRevision and payload.inventoryRevision < slot.completedRevision then return end
	local sizeStarted=diagnosticsEnabled() and now()
	local size,_,chunkBytes = Codec.frameSize(payload)
	local sizingMs=sizeStarted and math.max(0,now()-sizeStarted) or nil
	if not size or size > (slot.profile and slot.profile.frameBytes or Codec.FRAME_BYTES) then fail(payload.playerNum, "catalog_budget"); return end
	local completed=slot.completedBatches and slot.completedBatches[payload.batchId]
	if completed then
		if not same(completed,payload) then fail(payload.playerNum,"catalog_schema");return end
		-- Reconfirm an applied immutable batch without a second decode or apply.
		context.receipt(completed)
		return
	end
	if payload.batchId == slot.latest and not slot.batch then return end
	if payload.batchId > slot.latest then
		-- A later producer job cannot evict an incomplete accepted batch. Only
		-- completion, failure or an explicit session fence may replace it.
		if slot.batch then return end
		slot.latest = payload.batchId
		slot.batch = {meta=payload, parts={}, count=0, bytes=0, tokens=0, started=now(), progress=now()}
		Metrics.count(slot.summary,"batches")
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
	batch.bytes = batch.bytes + chunkBytes
	Metrics.work(slot.summary,"size",sizingMs or 0)
	Metrics.count(slot.summary,"fragments");Metrics.count(slot.summary,"uniqueFrameBytes",size)
	if sizingMs then
		batch.profile=batch.profile or {sizeMs=0,sizeMaxMs=0,decodeMs=0,decodeMaxMs=0,steps=0,wallYields=0,unitYields=0}
		batch.profile.sizeMs=batch.profile.sizeMs+sizingMs
		batch.profile.sizeMaxMs=math.max(batch.profile.sizeMaxMs,sizingMs)
	end
	if not reserveBatch(slot,batch) then
		fail(payload.playerNum, "catalog_budget"); return
	end
	batch.progress = now()
	slot.started = batch.progress
	slot.replicaProgressAt = batch.progress
	if batch.tokens > batch.meta.tokenCount or batch.bytes > batch.meta.totalBytes then
		fail(payload.playerNum, "catalog_budget"); return
	end
	-- Only accepted, unique fragments advance presentation. A complete batch
	-- still remains non-operable until decoding and the consumer apply finish.
	if slot.confirmed and context.progress and not slot.confirmed.replicaEpoch then
		local ok, accepted, reason, stage = pcall(context.progress, batch.meta, batch.count, batch.meta.total)
		if not ok or accepted == false then consumerFailure(payload.playerNum, slot, batch.meta, ok, accepted, reason, stage or "catalogProgress"); return end
	end
	if slots[payload.playerNum] ~= slot then return end
	applyReady(payload.playerNum, slot)
end
function Client.error(payload)
	local slot = slotFor(payload)
	if not slot then return end
	if slot.confirmed and (slot.confirmed.topologySequence or 0)~=(payload.topologySequence or 0) then return end
	if slot.confirmed and payload.networkId ~= slot.confirmed.networkId then return end
	if not Codec.integer(payload.batchId, 1, 9007199254740991) then return end
	if AccessPolicy.accessLoss(payload.reason) and slot.confirmed then
		fail(payload.playerNum, payload.reason, true)
		return
	end
	if slot.batch then
		if payload.batchId ~= slot.batch.meta.batchId then return end
	elseif payload.batchId <= slot.latest then return
	else slot.latest = payload.batchId end
	fail(payload.playerNum, payload.reason or "catalog_send", true)
end

--- Applies a bounded live delta only over its exact catalog base. Missing or
--- out-of-order bases retain the visible image and request one coalesced full
--- recovery through the existing fragmented transport.
function Client.delta(payload)
	local slot = slotFor(payload)
	if not slot or type(payload) ~= "table" then return end
	if slot.confirmed and (slot.confirmed.topologySequence or 0)~=(payload.topologySequence or 0) then return end
	if (payload.protocol ~= 1 and payload.protocol ~= 2)
		or not Codec.integer(payload.baseRevision, 0, 9007199254740991)
		or not Codec.integer(payload.inventoryRevision, payload.baseRevision + 1, 9007199254740991)
		or type(payload.networkId) ~= "string" or type(payload.catalogScope) ~= "string"
		or type(payload.changedRows) ~= "table" or type(payload.removedRowKeys) ~= "table" then return end
	local size = Codec.size(payload)
	if not size or size + 128 > Codec.FRAME_BYTES then return end
	if slot.completedRevision and payload.inventoryRevision <= slot.completedRevision then return end
	if slot.confirmed and slot.confirmed.networkId ~= payload.networkId then return end
	if not slot.confirmed then
		fail(payload.playerNum, "catalog_access_changed"); return
	end
	if not allowed(slot.confirmed,payload.playerNum) then return end
	if slot.batch then return end -- Preserve an accepted fragmented B1.
	local ok, accepted, reason, stage = pcall(context.applyDelta, payload)
	if slots[payload.playerNum] ~= slot then return end
	if ok and accepted == true then
		slot.completedRevision = payload.inventoryRevision
		slot.recoveryUsed = nil
		if GlobalStorageSiK.Log then GlobalStorageSiK.Log.debug("CatalogTransport", "delta_applied",
			"base=" .. tostring(payload.baseRevision) .. " revision=" .. tostring(payload.inventoryRevision)
				.. " changed=" .. tostring(#payload.changedRows)
				.. " removed=" .. tostring(#payload.removedRowKeys)) end
		return
	end
	if reason == "catalog_revision" and context.recover and not slot.recoveryUsed then
		slot.recoveryUsed = true
		if GlobalStorageSiK.Log then GlobalStorageSiK.Log.debug("CatalogTransport", "delta_recovery",
			"base=" .. tostring(payload.baseRevision) .. " revision=" .. tostring(payload.inventoryRevision)) end
		context.recover(payload)
		return
	end
	if ok and reason == "catalog_revision" then return end
	consumerFailure(payload.playerNum,slot,payload,ok,accepted,reason,stage or "terminalCatalogDelta")
end
function Client.waiting(payload)
	local slot=slotFor(payload)
	if not slot or not slot.confirmed or not context.allowed(slot.confirmed)
		or payload.replicaEpoch~=slot.confirmed.replicaEpoch
		or (slot.confirmed.topologySequence or 0)~=(payload.topologySequence or 0)
		or payload.networkId~=slot.confirmed.networkId or payload.catalogScope~=slot.confirmed.catalogScope
		or not Codec.integer(payload.batchId,1,9007199254740991)
		or not Codec.integer(payload.work,0,9007199254740991)
		or payload.batchId<=slot.latest or (slot.batch and payload.batchId~=slot.batch.meta.batchId) then return end
	local previous=slot.waiting
	if previous and (payload.batchId<previous.batchId or (payload.batchId==previous.batchId and payload.work<=previous.work)) then return end
	slot.waiting={batchId=payload.batchId,work=payload.work}
	slot.started=now()
	slot.replicaProgressAt=slot.started
	if GlobalStorageSiK.Log then GlobalStorageSiK.Log.debug("CatalogTransport","request_timeout",
		"recoverable=true phase="..tostring(payload.phase).." work="..tostring(payload.work)) end
end
function Client.update(timestamp)
	local active = false
	if context and context.nodeUpdate then
		active=context.nodeUpdate()==true
		if active then
			for n=0,3 do if slots[n] and slots[n].confirmed and slots[n].confirmed.replicaEpoch then slots[n].started=timestamp end end
		end
	end
	local started, work = now(), 0
	for playerNum = 0, 3 do
		local slot = slots[playerNum]
		if slot then
			if not context.current(playerNum, slot.sequence) then
				Metrics.finish(slot.summary,"cancelled","intent_replaced");slots[playerNum] = nil
			else
				local batch = slot.batch
				if batch or (slot.confirmed and context.pending(playerNum)) then
					active = true
					if timestamp < slot.started then slot.started = timestamp end
					if batch and timestamp < batch.progress then batch.progress = timestamp end
					if (context.pending(playerNum) and timestamp - slot.started >= TIMEOUT_MS)
						or (batch and timestamp - batch.progress >= IDLE_MS) then
						fail(playerNum, "catalog_timeout")
					elseif batch and batch.count<batch.meta.total
						and timestamp-batch.progress>=FRAGMENT_RETRY_MS
						and timestamp-(batch.lastMissingAt or 0)>=FRAGMENT_RETRY_MS then
						local missing={}
						for part=1,batch.meta.total do if not batch.parts[part] then missing[#missing+1]=part end end
						batch.lastMissingAt=timestamp
						if #missing>0 and context.missing then context.missing(batch.meta,missing) end
					elseif slot.confirmed and not allowed(slot.confirmed,playerNum) then
						-- The authority-loss path already fenced and closed this slot.
					elseif batch and batch.decoder then
						-- Authorization may itself exceed the time slice. Give each
						-- accepted batch one bounded step, then enforce wall time.
						local stepped = false
						while slots[playerNum] == slot and slot.batch == batch and batch.decoder
							and work < 8192 and (not stepped or now() - started < 4) do
							local decodeStarted=batch.profile and now()
							local quantum=math.min(slot.profile and slot.profile.optimizedCodec and 128 or 1024,8192-work)
							local value, reason, done = Codec.stepDecode(batch.decoder, quantum,slot.profile and slot.profile.optimizedCodec and started+4 or nil)
							Metrics.work(slot.summary,"decode",decodeStarted and now()-decodeStarted or 0)
							Metrics.count(slot.summary,"decodeSteps")
							if decodeStarted then
								local elapsed=math.max(0,now()-decodeStarted)
								batch.profile.decodeMs=batch.profile.decodeMs+elapsed
								batch.profile.decodeMaxMs=math.max(batch.profile.decodeMaxMs,elapsed)
								batch.profile.steps=batch.profile.steps+1
							end
							stepped = true
							work = work + (slot.profile and slot.profile.optimizedCodec and batch.decoder and batch.decoder.workLastStep or quantum)
							if reason then fail(playerNum, reason); break end
							batch.progress = timestamp
							if (batch.decoder.workLastStep or 0)>0 or done then slot.replicaProgressAt=now() end
							if done then
								batch.decoded, batch.decoder, batch.decodeFinished = value, nil, now()
								if GlobalStorageSiK.Log then GlobalStorageSiK.Log.debug("CatalogTransport","decoded",
									"player="..tostring(playerNum).." batch="..tostring(batch.meta.batchId)
									.." decodeMs="..tostring(batch.decodeFinished-batch.decodeStarted)) end
								applyReady(playerNum, slot)
								break
							end
						end
						if slot.batch==batch and batch.decoder and batch.profile then
							local reason=work>=8192 and "unitYields" or "wallYields"
							batch.profile[reason]=batch.profile[reason]+1
							Metrics.count(slot.summary,reason)
						end
					end
				end
			end
		end
	end
	for n=0,3 do
		local slot=slots[n]
		if slot and slot.summary and slot.summary.completePending and not slot.batch then Metrics.finish(slot.summary,"complete","full_view_committed") end
	end
	return active
end
return Client

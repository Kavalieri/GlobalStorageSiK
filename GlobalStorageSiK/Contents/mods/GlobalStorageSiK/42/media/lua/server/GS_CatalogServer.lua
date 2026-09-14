-- One immutable, acknowledged catalog job per authorized recipient.
local Codec = require "GS_CatalogCodec"
local Server = {}
GlobalStorageSiK.CatalogServer = Server
local sessions, jobs, order = {}, {}, {}
local serial, cursor, retainedBytes, lastPrune = 0, 0, 0, 0
local context
local SESSION_LIMIT = 256
local GLOBAL_BYTES, PLAYER_BYTES = 64*1024*1024, 32*1024*1024
local TIMEOUT_MS = 60000
local RESPONSE_DEADLINE_MS = 10000
local counters = {full=0, delta=0, notModified=0, details=0, manifests=0, nodes=0, completed=0, discarded=0, rejected=0, coalesced=0}
local lastDiscardLog = 0
local lastProgressLog = 0
local function now() return getTimestampMs and getTimestampMs() or 0 end
local function log(event, data)
    if GlobalStorageSiK.Log then GlobalStorageSiK.Log.debug("CatalogTransport", event, data) end
end
local function description(meta)
    return "player=" .. tostring(meta.playerNum) .. " network=" .. tostring(meta.networkId)
        .. " openSeq=" .. tostring(meta.openSeq) .. " batch=" .. tostring(meta.batchId)
        .. " source=" .. tostring(meta.catalogSource) .. " base=" .. tostring(meta.baseRevision)
        .. " revision=" .. tostring(meta.inventoryRevision) .. " scope=" .. tostring(meta.catalogScope)
end
local function release(player, reason)
    local job = jobs[player]
    if job then
        if job.builder and job.builder.cancel then
            log("detached",description(job.envelope).." phase=preparation reason="..tostring(reason or "recipient_detached"))
            job.builder.cancel(reason or "recipient_detached")
        end
        retainedBytes = math.max(0, retainedBytes-job.bytes); jobs[player] = nil
    end
end
function Server.configure(value) context = value end
function Server.valid(player,session,payload) return context.valid(player,session,payload) end
function Server.replicaReady(player,revision,scope)
    local session=sessions[player]
    if not session or not session.replicaEpoch or jobs[player] then return false end
    if not context.valid(player,session,{catalogScope=scope}) then return false end
    session.openUi=false
    session.confirmed={revision=revision,scope=scope}
    session.forceFull=nil;session.recoveryUsed=nil
    session.topologyBaseScope=nil;session.topologyZones=nil;session.topologyBaseSequence=nil
    session.removedTopologyZones=nil;session.removedTopologyNodes=nil
    return true
end
function Server.isOpening(player) return sessions[player] and sessions[player].openUi == true end
function Server.hasJob(player) return jobs[player] ~= nil end
function Server.fenceConsumer(player,reason)
	local session=sessions[player]
	if not session then return false end
	release(player,reason or "catalog_consumer")
	session.consumerRejected=true;session.forceFull=true;session.recoveryUsed=true
	if context and context.rejectNode then context.rejectNode(player) end
	return true
end
function Server.base(player)
    local session = sessions[player]
    return session and not session.forceFull and session.confirmed or nil
end
function Server.restoreBase(player,entry,knownRevision,knownScope)
    local session=sessions[player]
    if not session or not entry or entry.networkId~=session.networkId
        or entry.scopeSignature~=session.catalogScope or knownScope~=session.catalogScope
        or entry.revision~=knownRevision or session.confirmed then return false end
    local valid=context.valid(player,session,{catalogScope=session.catalogScope})
    local bytes=entry.bytes or #(entry.rows or {})*1024
    if not valid or retainedBytes+bytes>GLOBAL_BYTES or bytes>PLAYER_BYTES then return false end
    session.confirmed={rows=entry.rows,revision=entry.revision,scope=entry.scopeSignature}
    session.baseBytes=bytes;retainedBytes=retainedBytes+bytes
    log("base_restored","network="..tostring(session.networkId).." revision="..tostring(entry.revision))
    return true
end
function Server.diagnostics()
    local result = {retainedBytes=retainedBytes, sessions=#order, jobs=0}
    for key, value in pairs(counters) do result[key] = value end
    for _ in pairs(jobs) do result.jobs = result.jobs+1 end
    return result
end
function Server.clear(player)
    release(player)
    local session = sessions[player]
    retainedBytes = math.max(0, retainedBytes-(session and session.baseBytes or 0))
    sessions[player] = nil
    if context and context.closed then context.closed(player) end
    for i=#order,1,-1 do if order[i]==player then table.remove(order,i) end end
    if cursor>#order then cursor=0 end
end
local function send(player, command, payload)
    local size,reason,chunkBytes,payloadBytes=Codec.frameSize(payload)
    if command=="terminalCatalogChunk" then
        log("frame",description(payload).." part="..tostring(payload.part).." total="..tostring(payload.total)
            .." frameBytes="..tostring(size).." frameBudget="..tostring(Codec.FRAME_BYTES)
            .." payloadBytes="..tostring(payloadBytes).." chunkBytes="..tostring(chunkBytes)
            .." overheadBytes="..tostring(size and chunkBytes and size-chunkBytes)
            .." accepted="..tostring(size~=nil and size<=Codec.FRAME_BYTES))
    end
    if not size or size>Codec.FRAME_BYTES then return false, reason or "catalog_budget" end
    local ok, accepted = pcall(context.send, player, command, payload)
    return ok and accepted ~= false, (not ok or accepted == false) and "catalog_send" or nil
end
local function recoverOnce(player, session, reason)
    if session.recoveryUsed then return end
    session.recoveryUsed=true
    if session.replicaEpoch and context.nodeRecover and context.nodeRecover(player,reason) then return end
    if context.recover then context.recover(player,session.networkId,reason)
    elseif context.stale then context.stale(player,session.networkId) end
end
local function failure(player, reason, batchId)
    local session = sessions[player]
    if not session then return end
    local active = jobs[player]
    if active and active.envelope then batchId=active.envelope.batchId
    else serial=serial+1; batchId=serial end
    local recoverable = (session.confirmed ~= nil or session.replicaEpoch ~= nil) and reason ~= "catalog_access_changed"
    if recoverable then release(player,reason); session.forceFull=true
    else
        release(player,reason)
        Server.clear(player)
        if context.abort then context.abort(player) end
    end
    send(player, "terminalCatalogError", {playerNum=session.playerNum, openSeq=session.openSeq,
		topologySequence=session.topologySequence,
        networkId=session.networkId, batchId=batchId, reason=reason, recoverable=recoverable})
    if recoverable and sessions[player]==session then recoverOnce(player,session,reason) end
    log("failed", "batch=" .. tostring(batchId) .. " reason=" .. tostring(reason)
        .. " recoverable=" .. tostring(recoverable))
end
function Server.fail(player,reason) failure(player,reason,serial) end

-- This ticket stays on the server stack across a synchronous authorized add.
-- No client command can create it or use it to forgive a revoked old zone.
function Server.prepareZoneAddition(networkId)
    local prepared={}
    for player,session in pairs(sessions) do
        if session.networkId==networkId and session.replicaEpoch and not session.consumerRejected
            and context.valid(player,session,session) then
            prepared[#prepared+1]={player=player,session=session,scope=session.catalogScope}
        end
    end
    return prepared
end
local function completeTopology(prepared,zoneId,zoneMetadata,removedNodes,removeZone)
    local Protocol=GlobalStorageSiK.ManifestProtocol
    for i=1,#prepared do
        local ticket=prepared[i]
        local player,session=ticket.player,ticket.session
        if sessions[player]==session and session.catalogScope==ticket.scope then
            local scope=context.scope(player,session.networkId)
            if scope~=ticket.scope or removedNodes then
                local expected=removedNodes and (removeZone and Protocol.scopeWithoutZone(ticket.scope,zoneId) or ticket.scope)
                    or Protocol.scopeWithZone(ticket.scope,zoneId)
                local confirmation={}
                for _,key in ipairs({"playerNum","openSeq","networkId","replicaEpoch","manifestSchema",
                    "accessMode","terminalAnchor","confirmedProximityRange","confirmedWirelessRange",
                    "inventoryRevision","protocol"}) do confirmation[key]=session[key] end
                confirmation.catalogScope=scope
                if expected~=scope or not context.valid(player,confirmation,confirmation) then
                    failure(player,"catalog_access_changed")
                else
                    -- Retire old frames/requests before exposing the new identity.
                    release(player,"topology_addition")
					-- A fresh authorization object owns this generation. openSeq
					-- still identifies the UI opening; topologySequence fences the
					-- newly validated catalog session and every node request/body.
					local renewed={}
					for key,value in pairs(session) do renewed[key]=value end
					session=renewed;sessions[player]=session
                    session.catalogScope=scope
                    session.topologyBaseScope=session.topologyBaseScope or ticket.scope
                    session.topologyBaseSequence=session.topologyBaseSequence or session.topologySequence or 0
                    session.topologySequence=(session.topologySequence or 0)+1
                    session.confirmed=nil
                    if context.opened then context.opened(player,session) end
                    confirmation.topologyTransition=true
                    confirmation.previousCatalogScope=session.topologyBaseScope
                    confirmation.topologySequence=session.topologySequence
                    confirmation.topologyBaseSequence=session.topologyBaseSequence
                    confirmation.catalogBatchFloor=serial
                    if removedNodes then
                        session.removedTopologyNodes=session.removedTopologyNodes or {}
                        -- A zone tombstone already covers all of its nodes. Keep
                        -- the access ACK independent of the number of containers.
                        if not removeZone then
                            for _,id in ipairs(removedNodes) do session.removedTopologyNodes[id]=true end
                        end
                        if removeZone then
                            session.removedTopologyZones=session.removedTopologyZones or {}
                            session.removedTopologyZones[zoneId]=true
                            if session.topologyZones then session.topologyZones[zoneId]=nil end
                        end
                    end
                    if zoneMetadata then
                        session.topologyZones=session.topologyZones or {}
                        session.topologyZones[zoneId]=zoneMetadata
                        if session.removedTopologyZones then session.removedTopologyZones[zoneId]=nil end
                    end
                    if session.topologyZones then
                        confirmation.topologyZones={}
                        for _,zone in pairs(session.topologyZones) do
                            confirmation.topologyZones[#confirmation.topologyZones+1]=zone
                        end
                    end
                    for _,field in ipairs({"removedTopologyZones","removedTopologyNodes"}) do
                        if session[field] then
                            confirmation[field]={}
                            for id in pairs(session[field]) do confirmation[field][#confirmation[field]+1]=id end
                        end
                    end
                    if not send(player,"terminalOpenAck",confirmation) then failure(player,"catalog_send") end
                    log("topology_transition","network="..tostring(session.networkId).." zone="..zoneId)
                end
            end
        end
    end
end
function Server.completeZoneAddition(prepared,zoneId,zoneMetadata)
    completeTopology(prepared,zoneId,zoneMetadata)
end
function Server.prepareTopologyRemoval(networkId)
    return Server.prepareZoneAddition(networkId)
end
function Server.completeTopologyRemoval(prepared,zoneId,nodeIds,removeZone)
    completeTopology(prepared,zoneId,nil,nodeIds,removeZone)
end
local function prune()
    local live, retired = {}, {}
    context.visit(function(player) live[player]=true end)
    for player in pairs(sessions) do if not live[player] then retired[#retired+1]=player end end
    for i=1,#retired do
        Server.clear(retired[i])
        if context.abort then context.abort(retired[i]) end
    end
end
function Server.begin(player, confirmation)
    if not context then return false end
    prune()
    local previous,active=sessions[player],jobs[player]
    local oldAnchor=previous and previous.terminalAnchor or {}
    local anchor=confirmation.terminalAnchor or {}
    local compatible=previous and previous.networkId==confirmation.networkId
        and previous.catalogScope==confirmation.catalogScope and previous.accessMode==confirmation.accessMode
        and oldAnchor.x==anchor.x and oldAnchor.y==anchor.y and oldAnchor.z==anchor.z
    -- Retarget only a not-yet-encoded full. Old fragments/ACKs remain fenced by
    -- openSeq. Deltas have a recipient base and cannot be rebound blindly.
    local resume=compatible and active and active.builder and active.kind=="full"
        and active.envelope.inventoryRevision==confirmation.inventoryRevision
        and (not active.builder.classificationStamp or active.builder.classificationStamp==GlobalStorageSiK.Index.getClassificationStamp())
    if resume then jobs[player]=nil end
    Server.clear(player)
    if #order>=SESSION_LIMIT then
        if context.abort then context.abort(player) end
        serial=serial+1
        send(player,"terminalCatalogError",{playerNum=confirmation.playerNum,
            openSeq=confirmation.openSeq,networkId=confirmation.networkId,reason="catalog_busy",batchId=serial})
        return false
    end
    confirmation.openUi=true
    sessions[player]=confirmation
    order[#order+1]=player
    if resume then
        active.envelope.openSeq=confirmation.openSeq
        active.payload.openSeq=confirmation.openSeq
        active.payload.openUi=true
        jobs[player]=active
        log("resumed",description(active.envelope).." phase=preparation reason=reopen")
    end
    if context.opened then context.opened(player,confirmation) end
    local ok=send(player,"terminalOpenAck",confirmation)
    if not ok then
        Server.clear(player)
        if context.abort then context.abort(player) end
    end
    return ok
end
-- Catalog rows are immutable Index outputs. Copy the small state envelope:
-- configuration and zone metadata can otherwise mutate while encoding yields.
local function copyMetadata(value, depth, active)
    if type(value)~="table" then return value end
    if depth>Codec.MAX_DEPTH or active[value] then error("catalog_schema",0) end
    active[value]=true
    local result={}
    for key, child in pairs(value) do
        if depth==0 and (key=="items" or key=="changedRows" or key=="nodeSnapshot") then result[key]=child
        else result[key]=copyMetadata(child,depth+1,active) end
    end
    active[value]=nil
    return result
end
local function queue(player, payload, rows, builder)
	local session=sessions[player]
	if not session or type(payload)~="table" or session.networkId~=payload.networkId then return false end
	if session.consumerRejected then return false,"catalog_session_fenced" end
    local valid, invalidReason=context.valid(player,session,payload)
    if not valid then
        if invalidReason then failure(player,invalidReason,serial) else Server.clear(player) end
        return false
    end
    if jobs[player] then
        if context.stale then context.stale(player,session.networkId) end
        counters.coalesced=counters.coalesced+1
        return false,"catalog_inflight"
    end
    local copied, immutable=pcall(copyMetadata,payload,0,{})
    if not copied then failure(player,"catalog_schema",serial); return false end
    payload=immutable
    serial=serial+1
    payload.playerNum,payload.openSeq,payload.protocol=session.playerNum,session.openSeq,2
    payload.accessProbeId=nil
    if session.openUi and payload.catalogDetail~=true then
        payload.openUi=true
        payload.accessMode,payload.terminalAnchor=session.accessMode,session.terminalAnchor
        payload.confirmedProximityRange=session.confirmedProximityRange
        payload.confirmedWirelessRange=session.confirmedWirelessRange
    end
	payload.topologySequence=session.topologySequence
    local envelope={protocol=2,playerNum=session.playerNum,openSeq=session.openSeq,topologySequence=session.topologySequence,
        networkId=payload.networkId,inventoryRevision=payload.inventoryRevision,
        catalogScope=payload.catalogScope,batchId=serial,part=1,total=1,
        tokenCount=1,totalBytes=1,data={},catalogSource=payload.catalogSource or "terminalState",
        baseRevision=payload.baseRevision}
    local overhead=Codec.frameSize(Codec.frame(envelope,{},1))
    if not overhead then failure(player,"catalog_budget",serial); return false end
    local encoder, reason
    if not builder then encoder,reason=Codec.beginEncode(payload,Codec.FRAME_BYTES-overhead+4) end
    if not builder and not encoder then failure(player,reason,serial); return false end
    if retainedBytes+4096>GLOBAL_BYTES then failure(player,"catalog_busy",serial); return false end
    jobs[player]={envelope=envelope,encoder=encoder,builder=builder,payload=payload,
        frameBudget=Codec.FRAME_BYTES-overhead+4,bytes=4096,nextPart=1,lastProgressAt=now(),startedAt=builder and builder.startedAt or now(),lastDiagnosticAt=now(),
        encodeStarted=now(),encodeMs=0,rows=payload.itemTypeCount or 0,
        detail=payload.catalogDetail==true, nodeTransfer=payload.catalogManifest==true or payload.catalogNode==true,
        confirmedRows=rows or payload.items or (session.confirmed and session.confirmed.rows)}
    retainedBytes=retainedBytes+4096
    local kind=payload.catalogNode and "nodes" or payload.catalogManifest and "manifests"
        or payload.catalogDetail and "details" or payload.catalogDelta and "delta"
        or payload.notModified and "notModified" or "full"
    jobs[player].kind=kind
    counters[kind]=counters[kind]+1
    log("queued",description(envelope) .. " kind=" .. kind .. " rows=" .. tostring(payload.itemTypeCount or 0))
    return true
end
function Server.queue(player,payload,rows) return queue(player,payload,rows) end
function Server.queueBuild(player,payload,builder)
    local accepted,reason=queue(player,payload,nil,builder)
    if not accepted and builder and builder.cancel then builder.cancel() end
    return accepted,reason
end
function Server.delta(player,payload,rows)
    payload.protocol=2
    payload.catalogDelta=true
    payload.catalogSource=payload.catalogSource or "inventory_delta"
    return Server.queue(player,payload,rows)
end
local function discard(reason)
    counters.discarded=counters.discarded+1
    local timestamp=now()
    if timestamp<lastDiscardLog or timestamp-lastDiscardLog>=1000 then
        lastDiscardLog=timestamp
        log("ack_discarded","reason=" .. reason .. " total=" .. tostring(counters.discarded))
    end
end
function Server.receipt(player,payload)
    local session,job=sessions[player],jobs[player]
    if not session or not job or type(payload)~="table" then discard("no_matching_job"); return end
    local meta=job.envelope
    if payload.openSeq~=session.openSeq or payload.networkId~=session.networkId
		or (payload.topologySequence or 0)~=(session.topologySequence or 0)
        or payload.batchId~=meta.batchId or payload.inventoryRevision~=meta.inventoryRevision
        or payload.catalogScope~=meta.catalogScope then discard("identity"); return end
    local valid,reason=context.valid(player,session,meta)
    if not valid then
        discard(reason or "session")
        if reason then failure(player,reason,meta.batchId) else Server.clear(player) end
        return
    end
	if payload.rejected==true then
		counters.rejected=counters.rejected+1
		local rejectReason=payload.consumerRejected==true and "catalog_consumer" or "catalog_transport"
		log("rejected",description(meta) .. " reason="..rejectReason)
		if payload.consumerRejected==true then Server.fenceConsumer(player,"catalog_consumer")
		else
			release(player,rejectReason);session.forceFull=true
			recoverOnce(player,session,rejectReason)
		end
		return
    end
    if job.builder or job.encoder or job.framer or job.nextPart<=meta.total then discard("premature"); return end
    if not job.detail and not job.nodeTransfer then
        retainedBytes=math.max(0,retainedBytes-(session.baseBytes or 0))
        session.baseBytes=job.baseEstimate or 0
        retainedBytes=retainedBytes+session.baseBytes
        session.openUi=false
        session.confirmed={rows=job.confirmedRows,revision=meta.inventoryRevision,scope=meta.catalogScope}
        session.forceFull=nil
        session.recoveryUsed=nil
    end
    counters.completed=counters.completed+1
    if job.nodeTransfer then session.recoveryUsed=nil end
    log("completed",description(meta) .. " kind=" .. tostring(job.kind) .. " rows=" .. tostring(job.rows)
        .. " bytes=" .. tostring(job.wireBytes) .. " encodeMs=" .. tostring(job.encodeMs)
        .. " elapsedMs=" .. tostring(now()-job.startedAt))
    release(player)
    if context.received then context.received(player,job.payload) end
end
local function encodeStep(player,job,session)
    local started=now()
    local encoded,reason,done=Codec.stepEncode(job.encoder,1024)
    job.encodeMs=job.encodeMs+math.max(0,now()-started)
    local state=job.encoder
    local bytes=state.totalBytes or (encoded and encoded.totalBytes) or 0
    local tokens=state.tokenCount or (encoded and encoded.tokenCount) or 0
    local chunks=state.chunks or (encoded and encoded.chunks) or {}
    local reservation=math.max(4096,bytes*2+tokens*64+#chunks*128+(state.memoBytes or 0))
    if reservation+(session.baseBytes or 0)>PLAYER_BYTES or retainedBytes-job.bytes+reservation>GLOBAL_BYTES then
        failure(player,"catalog_busy",job.envelope.batchId); return
    end
    retainedBytes=retainedBytes-job.bytes+reservation
    job.bytes=reservation
    if reason then failure(player,reason,job.envelope.batchId); return end
    job.lastProgressAt=now()
    if done then
        job.encoder=nil
        job.chunks=encoded.chunks
        job.wireBytes=encoded.totalBytes
        job.envelope.total=#encoded.chunks
        job.envelope.totalBytes=encoded.totalBytes
        job.envelope.tokenCount=encoded.tokenCount
        job.framer,reason=Codec.beginFraming(encoded,job.envelope)
        if not job.framer then failure(player,reason,job.envelope.batchId);return end
        job.framingBaseBytes=job.bytes
        job.baseEstimate=(job.detail or job.nodeTransfer) and 0 or math.min(reservation,encoded.totalBytes*2+job.rows*256)
        log("encoded",description(job.envelope) .. " bytes=" .. tostring(encoded.totalBytes)
            .. " parts=" .. tostring(#encoded.chunks) .. " encodeMs=" .. tostring(job.encodeMs)
            .. " elapsedMs=" .. tostring(now()-job.startedAt))
    end
end
local function framingStep(player,job,session)
    local framed,reason,done=Codec.stepFraming(job.framer,1024)
    if reason then failure(player,reason,job.envelope.batchId);return end
    -- Repartitioning temporarily retains both source and destination arrays.
    local extra=job.framer.chunks==job.chunks and 0 or #job.framer.chunks*128
    local reservation=job.framingBaseBytes+extra
    if reservation+(session.baseBytes or 0)>PLAYER_BYTES or retainedBytes-job.bytes+reservation>GLOBAL_BYTES then
        failure(player,"catalog_busy",job.envelope.batchId);return
    end
    retainedBytes=retainedBytes-job.bytes+reservation;job.bytes=reservation
    job.lastProgressAt=now()
    if done then
        job.chunks=framed.chunks
        job.envelope.total=#framed.chunks
        job.envelope.totalBytes=framed.totalBytes
        job.wireBytes=framed.totalBytes
        job.framer=nil
        log("framed",description(job.envelope).." bytes="..tostring(framed.totalBytes).." parts="..tostring(#framed.chunks))
    end
end
local function buildStep(player,job,session,budget,millis)
    local started=now()
    local ok,done,payload,rows,stats=pcall(job.builder.step,budget,millis)
    local diagnostic=job.builder.error and job.builder.error()
    stats=stats or {}
    local used=math.max(1,math.min(budget,stats.workLastStep or budget))
    if not ok or diagnostic then
        local cause=diagnostic or done
        log("build_failed",description(job.envelope) .. " stage="
            .. tostring(type(cause)=="table" and cause.stage or "catalog_build")
            .. " cause=" .. tostring(type(cause)=="table" and cause.cause or cause))
        failure(player,"catalog_build",job.envelope.batchId)
        return used
    end
    local reservation=math.max(4096,tonumber(stats.retainedBytes) or 4096)
    if reservation+(session.baseBytes or 0)>PLAYER_BYTES
        or retainedBytes-job.bytes+reservation>GLOBAL_BYTES then
        failure(player,"catalog_busy",job.envelope.batchId); return used
    end
    retainedBytes=retainedBytes-job.bytes+reservation
    job.bytes=reservation
    if done or (tonumber(stats.workLastStep) or 0)>0 then job.lastProgressAt=now() end
    job.buildMs=(job.buildMs or 0)+math.max(0,now()-started)
    job.buildUnits=stats.workTotal or job.buildUnits or 0
    if done then
        -- The builder mutates only the copied metadata envelope owned by this
        -- job. The captured content revision never changes during construction.
        for key,value in pairs(payload or {}) do job.payload[key]=value end
        job.builder.cancel()
        job.builder=nil
        job.confirmedRows=rows
        job.rows=#(rows or {})
        job.envelope.baseRevision=job.payload.baseRevision
        local kind=job.payload.catalogDetail and "details" or job.payload.notModified and "notModified"
            or job.payload.catalogDelta and "delta" or "full"
        if kind~=job.kind then counters[job.kind]=counters[job.kind]-1;counters[kind]=counters[kind]+1;job.kind=kind end
        local encoder,reason=Codec.beginEncode(job.payload,job.frameBudget)
        if not encoder then failure(player,reason,job.envelope.batchId); return used end
        job.encoder=encoder
        job.encodeStarted=now()
        log("catalog_rows_built",description(job.envelope) .. " buildMs=" .. tostring(job.buildMs)
            .. " rows=" .. tostring(job.rows) .. " nodesProcessed=" .. tostring(stats.nodesProcessed)
            .. " parentsProcessed=" .. tostring(stats.parentsProcessed)
            .. " work=" .. tostring(stats.workTotal or stats.work or stats.totalWork)
            .. " elapsedMs=" .. tostring(now()-job.startedAt))
    end
    return used
end
function Server.update()
    if not context or #order==0 then return end
    local timestamp,visited,sent,work=now(),0,0,0
    local buildWork,computeMs=0,0
    local validations={}
    if timestamp<lastPrune or timestamp-lastPrune>=1000 then lastPrune=timestamp; prune() end
    local visitBudget=math.max(#order*4,8)
    -- Always permit one useful visit: validation may itself cross 4 ms. Stop
    -- afterwards on wall time, so expensive observers cannot multiply the tick.
    while #order>0 and visited<visitBudget and sent<4 and computeMs<4
        and (visited==0 or now()-timestamp<4) do
        cursor=cursor%#order+1
        local player=order[cursor]
        local job,session=jobs[player],sessions[player]
        visited=visited+1
        if job and session then
            local validationStarted=now()
            local cached=validations[player]
            local valid,reason
            if cached and cached.job==job and cached.session==session and (job.builder or job.encoder or job.framer) then
                valid,reason=cached.valid,cached.reason
            else
                valid,reason=context.valid(player,session,job.envelope)
                validations[player]={job=job,session=session,valid=valid,reason=reason}
            end
            job.validationMs=(job.validationMs or 0)+math.max(0,now()-validationStarted)
            local workStarted=now()
            if timestamp<job.lastProgressAt then job.lastProgressAt=timestamp end
            if not valid then
                if reason then failure(player,reason,job.envelope.batchId) else Server.clear(player) end
            elseif timestamp-job.lastProgressAt>=TIMEOUT_MS then failure(player,"catalog_stalled",job.envelope.batchId)
            elseif job.builder then
                if buildWork<4096 then
                    local slice=math.max(1,math.min(4-computeMs,4-(now()-timestamp)))
                    buildWork=buildWork+buildStep(player,job,session,4096-buildWork,slice)
                end
            elseif job.framer then
                if work<8192 then framingStep(player,job,session);work=work+1024 end
            elseif job.encoder then
                if work<8192 then
                    local encodeSlice=math.max(1,math.min(4-computeMs,4-(now()-timestamp)))
                    repeat
                        encodeStep(player,job,session)
                        work=work+1024
                    until work>=8192 or jobs[player]~=job or not job.encoder or now()-workStarted>=encodeSlice
                end
            elseif job.nextPart<=job.envelope.total then
                local frame=Codec.frame(job.envelope,job.chunks[job.nextPart],job.nextPart)
                job.nextPart=job.nextPart+1 -- SP receipt can be synchronous.
                local ok,sendReason=send(player,"terminalCatalogChunk",frame)
                if ok then job.lastProgressAt=timestamp end
                sent=sent+1
                if not ok then failure(player,sendReason,frame.batchId) end
            end
            computeMs=computeMs+math.max(0,now()-workStarted)
            -- The response target is not a lifetime for shared catalog work.
            -- Report a recoverable wait while keeping this batch attached.
            if jobs[player]==job and now()-job.startedAt>=RESPONSE_DEADLINE_MS
                and now()-(job.pendingAt or 0)>=2000 then
                local progress=(job.buildUnits or 0)+(job.encoder and job.encoder.tokenCount or 0)
                    +(job.framer and job.envelope.tokenCount+job.framer.work or 0)
                if not job.pendingWork or progress>job.pendingWork then
                    local pending={}
                    for key,value in pairs(job.envelope) do pending[key]=value end
                    pending.reason,pending.recoverable,pending.work="request_timeout",true,progress
                    pending.phase=job.builder and "preparation" or (job.encoder and "encoding" or (job.framer and "framing" or "sending"))
                    local ok=send(player,"terminalCatalogPending",pending)
                    if not ok then failure(player,"catalog_send",job.envelope.batchId)
                    else job.pendingAt,job.pendingWork=now(),progress end
                    log("request_timeout",description(job.envelope).." recoverable=true phase="..pending.phase.." work="..tostring(progress))
                end
            end
            if now()<lastProgressLog then lastProgressLog=now() end
            if jobs[player]==job and now()-job.lastDiagnosticAt>=2000 and now()-lastProgressLog>=2000 then
                job.lastDiagnosticAt=now()
                lastProgressLog=now()
                local stats=job.builder and job.builder.diagnostics and job.builder.diagnostics() or {}
                log("progress",description(job.envelope).." phase="..tostring(stats.phase or (job.encoder and "encoding" or (job.framer and "framing" or "sending")))
                    .." node="..tostring(stats.nodeIndex).." nodes="..tostring(stats.totalNodes)
                    .." remaining="..tostring(stats.remaining).." work="..tostring(stats.work)
                    .." baseRetained="..tostring(session.confirmed~=nil).." validationMs="..tostring(job.validationMs))
            end
        end
    end
end
return Server

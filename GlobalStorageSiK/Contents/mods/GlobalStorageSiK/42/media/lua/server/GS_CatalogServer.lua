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
local BUILD_DEADLINE_MS = 10000
local counters = {full=0, delta=0, notModified=0, details=0, completed=0, discarded=0, rejected=0, coalesced=0}
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
function Server.isOpening(player) return sessions[player] and sessions[player].openUi == true end
function Server.hasJob(player) return jobs[player] ~= nil end
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
    for i=#order,1,-1 do if order[i]==player then table.remove(order,i) end end
    if cursor>#order then cursor=0 end
end
local function send(player, command, payload)
    local size, reason = Codec.size(payload)
    if not size or size+128>Codec.FRAME_BYTES then return false, reason or "catalog_budget" end
    local ok, accepted = pcall(context.send, player, command, payload)
    return ok and accepted ~= false, (not ok or accepted == false) and "catalog_send" or nil
end
local function recoverOnce(player, session, reason)
    if session.recoveryUsed then return end
    session.recoveryUsed=true
    if context.recover then context.recover(player,session.networkId,reason)
    elseif context.stale then context.stale(player,session.networkId) end
end
local function failure(player, reason, batchId)
    local session = sessions[player]
    if not session then return end
    local active = jobs[player]
    if active and active.envelope then batchId=active.envelope.batchId
    else serial=serial+1; batchId=serial end
    local recoverable = session.confirmed ~= nil and reason ~= "catalog_access_changed"
    if recoverable then release(player,reason); session.forceFull=true
    else
        release(player,reason)
        Server.clear(player)
        if context.abort then context.abort(player) end
    end
    send(player, "terminalCatalogError", {playerNum=session.playerNum, openSeq=session.openSeq,
        networkId=session.networkId, batchId=batchId, reason=reason, recoverable=recoverable})
    if recoverable and sessions[player]==session then recoverOnce(player,session,reason) end
    log("failed", "batch=" .. tostring(batchId) .. " reason=" .. tostring(reason)
        .. " recoverable=" .. tostring(recoverable))
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
        if depth==0 and (key=="items" or key=="changedRows") then result[key]=child
        else result[key]=copyMetadata(child,depth+1,active) end
    end
    active[value]=nil
    return result
end
local function queue(player, payload, rows, builder)
    local session=sessions[player]
    if not session or type(payload)~="table" or session.networkId~=payload.networkId then return false end
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
    local envelope={protocol=2,playerNum=session.playerNum,openSeq=session.openSeq,
        networkId=payload.networkId,inventoryRevision=payload.inventoryRevision,
        catalogScope=payload.catalogScope,batchId=serial,part=1,total=1,
        tokenCount=1,totalBytes=1,data={},catalogSource=payload.catalogSource or "terminalState",
        baseRevision=payload.baseRevision}
    local overhead=Codec.size(envelope)
    if not overhead then failure(player,"catalog_budget",serial); return false end
    local encoder, reason
    if not builder then encoder,reason=Codec.beginEncode(payload,Codec.FRAME_BYTES-overhead-128) end
    if not builder and not encoder then failure(player,reason,serial); return false end
    if retainedBytes+4096>GLOBAL_BYTES then failure(player,"catalog_busy",serial); return false end
    jobs[player]={envelope=envelope,encoder=encoder,builder=builder,payload=payload,
        frameBudget=Codec.FRAME_BYTES-overhead-128,bytes=4096,nextPart=1,lastProgressAt=now(),startedAt=builder and builder.startedAt or now(),lastDiagnosticAt=now(),
        encodeStarted=now(),encodeMs=0,rows=payload.itemTypeCount or 0,
        detail=payload.catalogDetail==true,
        confirmedRows=rows or payload.items or (session.confirmed and session.confirmed.rows)}
    retainedBytes=retainedBytes+4096
    local kind=payload.catalogDetail and "details" or payload.catalogDelta and "delta"
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
        log("rejected",description(meta) .. " reason=catalog_consumer")
        release(player)
        session.forceFull=true
        recoverOnce(player,session,"catalog_consumer")
        return
    end
    if job.builder or job.encoder or job.nextPart<=meta.total then discard("premature"); return end
    if not job.detail then
        retainedBytes=math.max(0,retainedBytes-(session.baseBytes or 0))
        session.baseBytes=job.baseEstimate or 0
        retainedBytes=retainedBytes+session.baseBytes
        session.openUi=false
        session.confirmed={rows=job.confirmedRows,revision=meta.inventoryRevision,scope=meta.catalogScope}
        session.forceFull=nil
        session.recoveryUsed=nil
    end
    counters.completed=counters.completed+1
    log("completed",description(meta) .. " kind=" .. tostring(job.kind) .. " rows=" .. tostring(job.rows)
        .. " bytes=" .. tostring(job.wireBytes) .. " encodeMs=" .. tostring(job.encodeMs)
        .. " elapsedMs=" .. tostring(now()-job.startedAt))
    release(player)
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
        job.baseEstimate=job.detail and 0 or math.min(reservation,encoded.totalBytes*2+job.rows*256)
        log("encoded",description(job.envelope) .. " bytes=" .. tostring(encoded.totalBytes)
            .. " parts=" .. tostring(#encoded.chunks) .. " encodeMs=" .. tostring(job.encodeMs)
            .. " elapsedMs=" .. tostring(now()-job.startedAt))
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
    if done then
        -- The builder mutates only the copied metadata envelope owned by this
        -- job. The captured content revision never changes during construction.
        for key,value in pairs(payload or {}) do job.payload[key]=value end
        job.builder.cancel()
        job.builder=nil
        job.confirmedRows=rows
        job.rows=#(rows or {})
        job.envelope.baseRevision=job.payload.baseRevision
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
            if cached and cached.job==job and cached.session==session and (job.builder or job.encoder) then
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
            elseif (job.builder or job.encoder) and timestamp-job.startedAt>=BUILD_DEADLINE_MS then
                log("deadline",description(job.envelope).." phase="..(job.builder and "preparation" or "encoding")
                    .." elapsedMs="..tostring(timestamp-job.startedAt).." validationMs="..tostring(job.validationMs))
                failure(player,"catalog_timeout",job.envelope.batchId)
            elseif timestamp-job.lastProgressAt>=TIMEOUT_MS then failure(player,"catalog_timeout",job.envelope.batchId)
            elseif job.builder then
                if buildWork<4096 then
                    local slice=math.max(1,math.min(4-computeMs,4-(now()-timestamp)))
                    buildWork=buildWork+buildStep(player,job,session,4096-buildWork,slice)
                end
            elseif job.encoder then
                if work<8192 then
                    local encodeSlice=math.max(1,math.min(4-computeMs,4-(now()-timestamp)))
                    repeat
                        encodeStep(player,job,session)
                        work=work+1024
                    until work>=8192 or jobs[player]~=job or not job.encoder or now()-workStarted>=encodeSlice
                end
            elseif job.nextPart<=job.envelope.total then
                local frame={}
                for key,value in pairs(job.envelope) do frame[key]=value end
                frame.part,frame.data=job.nextPart,job.chunks[job.nextPart]
                job.nextPart=job.nextPart+1 -- SP receipt can be synchronous.
                local ok,sendReason=send(player,"terminalCatalogChunk",frame)
                if ok then job.lastProgressAt=timestamp end
                sent=sent+1
                if not ok then failure(player,sendReason,frame.batchId) end
            end
            computeMs=computeMs+math.max(0,now()-workStarted)
            if now()<lastProgressLog then lastProgressLog=now() end
            if jobs[player]==job and now()-job.lastDiagnosticAt>=2000 and now()-lastProgressLog>=2000 then
                job.lastDiagnosticAt=now()
                lastProgressLog=now()
                local stats=job.builder and job.builder.diagnostics and job.builder.diagnostics() or {}
                log("progress",description(job.envelope).." phase="..tostring(stats.phase or (job.encoder and "encoding" or "sending"))
                    .." node="..tostring(stats.nodeIndex).." nodes="..tostring(stats.totalNodes)
                    .." remaining="..tostring(stats.remaining).." work="..tostring(stats.work)
                    .." baseRetained="..tostring(session.confirmed~=nil).." validationMs="..tostring(job.validationMs))
            end
        end
    end
end
return Server

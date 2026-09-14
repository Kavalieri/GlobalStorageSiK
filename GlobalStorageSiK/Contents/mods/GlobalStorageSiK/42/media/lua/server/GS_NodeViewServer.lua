-- Container editor read model. Only its node is captured/read; access still
-- belongs to an authenticated terminal session. Reuses bounded detail framing.
require "GS_Index"
require "GS_NodeSnapshots"
local V={}
GlobalStorageSiK.NodeViewServer=V
local context,pending=nil,{}
local function now()return getTimestampMs and getTimestampMs() or 0 end
local function integer(value, maximum)
    value=tonumber(value)
    if not value or value~=value or value<0 or value>maximum or value~=math.floor(value) then return nil end
    return value
end
function V.configure(value)context=value end
function V.request(player,args)
    if type(args)~="table" or type(args.nodeId)~="string" or #args.nodeId>240
        or type(args.networkId)~="string" or #args.networkId>160 then return false end
    if not context or not context.authorize(player,args.networkId,args.nodeId) then return false end
    if args.rowKey~=nil and (type(args.rowKey)~="string" or #args.rowKey>500) then return false end
    local descriptor={player=player,networkId=args.networkId,nodeId=args.nodeId,
        knownRevision=integer(args.knownNodeRevision,9007199254740991),
        knownClassification=type(args.knownClassification)=="string" and #args.knownClassification<=240 and args.knownClassification or nil,
        nodeViewId=type(args.nodeViewId)=="string" and args.nodeViewId:sub(1,96) or nil,
        nodeViewSeq=integer(args.nodeViewSeq,9007199254740991),nodeRevision=integer(args.nodeRevision,9007199254740991),
        rowKey=type(args.rowKey)=="string" and #args.rowKey<=500 and args.rowKey or nil,
        page=math.max(1,integer(args.page,100000) or 1),at=now()}
    for i=1,#pending do
        local p=pending[i]
        if p.player==player and p.nodeId==descriptor.nodeId and p.nodeViewId==descriptor.nodeViewId
            and p.rowKey==descriptor.rowKey then pending[i]=descriptor;return true end
    end
    if #pending>=512 then return false end
    local count=0
    for i=1,#pending do if pending[i].player==player then count=count+1 end end
    if count>=16 then return false end
    pending[#pending+1]=descriptor
    return true
end
local function prepare(request,node)
    local GS=GlobalStorageSiK
    local revision=GS.Index.getInventoryRevision(request.networkId)
    local confirmed=node.snapshotSchema==GS.NodeSnapshots.SCHEMA and type(node.itemSnapshot)=="table"
    local registry=GS.Zones.getRegistry()
    local zone=registry.zones and registry.zones[node.zoneId]
    local available=node.enabled~=false and node.membership~="excluded" and node.offline~=true
        and zone and zone.enabled~=false
    if not confirmed then GS.CatalogReconciler.markDirty(node.id,"replication_bootstrap") end
    local classification=GS.Index.getClassificationStamp()
    local payload={catalogDetail=true,nodeContents=true,catalogSource="container_node",
        networkId=request.networkId,catalogScope=context.scope(request.player,request.networkId),
        inventoryRevision=revision,nodeId=node.id,nodeRevision=node.contentRevision or 0,
        nodeViewId=request.nodeViewId,nodeViewSeq=request.nodeViewSeq,classificationStamp=classification,
        snapshotSignature=node.snapshotSignature,snapshotCertified=confirmed,
        snapshotRevision=confirmed and revision or 0,reconcilePending=not confirmed,
        snapshotAgeMs=math.max(0,now()-(node.snapshotConfirmedAt or now())),
        source=confirmed and "snapshot" or "empty",nodeRecord=GS.NodeSnapshots.record(node),
        capacity=context.capacity(node,request.player)}
    -- Configuration/availability can change without a content revision. Never
    -- answer notModified or expose legacy rows across either visibility fence.
    if not confirmed or not available then
        payload.catalogRows={};payload.nodeUnavailable=not available
        if request.rowKey then payload.detailPage={rowKey=request.rowKey,items={},reason="node_unavailable"} end
        return payload
    end
    if request.rowKey then
        payload.detailPage=request.nodeRevision and request.nodeRevision~=(node.contentRevision or 0)
            and {rowKey=request.rowKey,items={},reason="revision_mismatch"}
            or GS.Index.buildDetailPage(request.networkId,request.player,request.rowKey,request.page,25,node.id)
        return payload
    end
    if confirmed and request.knownRevision==node.contentRevision and request.knownClassification==classification then
        payload.nodeNotModified=true;return payload
    end
    local job=GS.Index.beginCatalogBuild(request.networkId,request.player,node.id,revision)
    local builder={startedAt=now()}
    local result,counts,cursor,best,bestCount=nil,{},1,nil,0
    function builder.error()return job.error end
    function builder.cancel()GS.Index.cancelCatalogBuild(job)end
    function builder.step(work,millis)
        if not result then
            local done,rows,stats=GS.Index.stepCatalogBuild(job,work,millis)
            if done and rows then result=rows end
            return false,nil,nil,stats
        end
        local used,started=0,now()
        while cursor<=#result and used<work do
            if used>0 and now()-started>=millis then break end
            local row=result[cursor]
            local path=context.suggest({row})
            if path then
                counts[path]=(counts[path] or 0)+(row.count or 1)
                if counts[path]>bestCount or counts[path]==bestCount and (not best or path<best) then
                    best,bestCount=path,counts[path]
                end
            end
            cursor=cursor+1;used=used+1
        end
        local stats=job.stats or {};stats.workLastStep=math.max(1,used)
        if cursor>#result then return true,{catalogRows=result,suggestedNativePath=best},nil,stats end
        return false,nil,nil,stats
    end
    return payload,builder
end
function V.update()
    for i=1,#pending do
        local request=pending[i]
        if now()-request.at>30000 then table.remove(pending,i);return end
        if not context.busy(request.player) then
            table.remove(pending,i)
            local node=context.authorize(request.player,request.networkId,request.nodeId)
            if not node then return end
            local payload,builder=prepare(request,node)
            if builder then context.queueBuild(request.player,payload,builder)
            else context.queue(request.player,payload) end
            return
        end
    end
end
return V

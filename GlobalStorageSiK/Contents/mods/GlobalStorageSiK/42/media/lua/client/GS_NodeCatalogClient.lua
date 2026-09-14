local Protocol=require "GS_ManifestProtocol"
local Replica=require "GS_NodeReplica"
local Rows=require "GS_CatalogRows"
require "GS_Index"
local Client={}
GlobalStorageSiK.NodeCatalogClient=Client
local context,slots=nil,{}
local cursor=0
local function diagnosticId(value)
	value=tostring(value or "")
	local hash=0
	for i=1,#value do hash=(hash*31+value:byte(i))%2147483629 end
	return tostring(#value)..":"..tostring(hash)
end
local function trace(event,meta,detail)
	local log=GlobalStorageSiK.NetTrace
	if log and log.isEnabled() then
		local epoch=meta.replicaEpoch or meta.epoch
		local scope=meta.catalogScope or meta.scope or ""
		log.write("Replica: "..event,"player="..tostring(meta.playerNum).." network="..tostring(meta.networkId)
			.." epoch="..diagnosticId(epoch).." scope="..diagnosticId(scope)
			.." key="..diagnosticId(Protocol.key(epoch,meta.playerNum,meta.networkId,scope))
			.." token="..tostring(meta.manifestToken or meta.token).." revision="..tostring(meta.inventoryRevision)
			.." "..(detail or ""))
	end
end
local cache=Replica.new({evicted=function(entry,reason)
	trace("clientCacheEvicted",entry,"reason="..tostring(reason).." bytes="..tostring(entry.bytes))
	if context and context.evicted then context.evicted(entry,reason) end
end})
local function now() return getTimestampMs and getTimestampMs() or 0 end
local function shallow(value) local out={};for k,v in pairs(value or {}) do out[k]=v end;return out end
local function intent(state)
	local ack=state.ack
	return {networkId=ack.networkId,openSeq=ack.openSeq,playerNum=ack.playerNum,
		catalogScope=ack.catalogScope,replicaEpoch=ack.replicaEpoch}
end
local function send(state,command,args)
	args=args or intent(state)
	return context.send(command,args,state.ack.playerNum)
end
function Client.configure(value) context=value end
function Client.clear(playerNum,revoke)
	local state=slots[playerNum]
	if state and state.build then GlobalStorageSiK.Index.cancelCatalogBuild(state.build) end
	-- Roll back before a reentrant confirm can observe the same cached store.
	if state and state.undo then state.undo();state.undo=nil end
	if state and state.cancelStage then state.cancelStage();state.cancelStage=nil end
	slots[playerNum]=nil
	if revoke then cache.clear(playerNum) end
end
function Client.confirm(ack)
	if ack.manifestSchema~=Protocol.SCHEMA or not Protocol.id(ack.replicaEpoch) then return false,"manifest_protocol" end
	Client.clear(ack.playerNum,false)
	local entry,reason=cache.confirm(ack)
	if reason then return false,reason end
	trace(entry and "clientCacheHit" or "clientCacheMiss",ack,entry and "reason=identity_confirmed" or "reason=no_confirmed_view")
	slots[ack.playerNum]={ack=ack,entry=entry,previous=entry and entry.rows,previousMetadata=entry and entry.metadata,
		store=entry and entry.rows and entry.rowStore,hasComplete=entry and entry.rows~=nil,
		hasPresented=entry and entry.rows~=nil,receivedBlocks=0,
		derivedGeneration=entry and entry.rows and entry.derivedGeneration,
		pendingNodeIds=shallow(entry and entry.changedNodeIds),
		viewSequence=0,started=now(),retries=0,buildMs=0,viewMs=0}
	return true
end
function Client.negotiate(ack)
	local state=slots[ack.playerNum]
	if not state or state.ack~=ack then return false end
	local args=intent(state)
	if state.entry and state.entry.confirmed then args.knownManifestToken=state.entry.confirmed.token end
	return send(state,"terminalManifestRequest",args)
end
local function missingNode(state)
	local missing=cache.missing(state.entry,1)
	if not missing[1] then
		for i=1,#state.entry.records do
			local record=state.entry.records[i]
			if record.enabled and not record.confirmed
				and record.availability~="unloaded_or_missing" and record.availability~="offline" then
				missing[1]=record;break
			end
		end
	end
	return missing[1]
end
local function nextNode(state,receivedBlock)
	local missing=missingNode(state)
	-- A warm refresh retains its complete image until all replacement blocks
	-- arrive. Bootstrap publishes each verified block before requesting more.
	local bootstrapWindow=not state.hasPresented and (state.receivedBlocks or 0)>=4
	if missing and not bootstrapWindow and (not state.request or state.request.nodeId~=missing.nodeId) then
		local args=intent(state);args.nodeId=missing.nodeId;args.manifestToken=state.entry.token
		trace("node requested",args,"node="..args.nodeId.." nodeRevision="..tostring(missing.revision))
		state.request=args;state.sentAt=now()
		if not send(state,"terminalNodeRequest",args) then return false,"node_send" end
	end
	if not missing then state.request=nil end
	if state.build or state.phase then return true end
	if missing and (not receivedBlock or state.hasComplete) then return true end
	state.partial=missing~=nil
	state.buildVersion=state.blockVersion
	local changedIds=state.pendingNodeIds or {}
	state.buildNodeIds=changedIds;state.pendingNodeIds={}
	local entry,partial=state.entry,state.partial
	local registry=cache.registry(entry,partial,changedIds)
	if not registry then return false,"replica_incomplete" end
	state.build=GlobalStorageSiK.Index.beginCatalogBuild(state.ack.networkId,nil,nil,state.manifest.inventoryRevision,
		{registry=registry,key=state.entry.key..Protocol.part(state.manifest.classificationEpoch),
			incremental=true,baseGeneration=state.derivedGeneration,changedNodeIds=changedIds,
			completeRegistry=function() return cache.registry(entry,partial) end})
	return state.build~=nil
end
function Client.consume(value,retainedBytes)
	local state=slots[value.playerNum]
	if not state or state.ack.openSeq~=value.openSeq or state.ack.networkId~=value.networkId
		or state.ack.replicaEpoch~=value.replicaEpoch
		or state.ack.catalogScope~=value.catalogScope then return false,"manifest_identity" end
	state.started=now()
	if value.catalogManifest then
		state.completed=false
		state.blockVersion=(state.blockVersion or 0)+1
		state.roundStarted=now();state.buildMs=0;state.viewMs=0
		if state.build then GlobalStorageSiK.Index.cancelCatalogBuild(state.build);state.build=nil end
		for id in pairs(state.buildNodeIds or {}) do state.pendingNodeIds[id]=true end
		state.buildNodeIds=nil
		state.buildRows=nil;state.phase=nil;state.view=nil;state.request=nil
		local entry=cache.get(value)
		state.previous=entry and entry.rows or state.previous
		state.previousMetadata=entry and entry.metadata or state.previousMetadata
		if value.manifestNotModified then
			if not entry or not entry.confirmed or entry.confirmed.token~=value.manifestToken
				or not entry.rows or not entry.metadata then
				return false,"manifest_cache_miss"
			end
			state.entry=entry;state.manifest=value;state.metadata=entry.metadata
			state.partial=false;state.stats=nil;state.store=entry.rowStore;state.hasComplete=true
			state.derivedGeneration=entry.derivedGeneration
			state.rows=entry.rows;state.phase="apply";state.notModified=true
			trace("notModified",value,"nodesRequested=0 buildWork=0")
			return true
		end
		if type(value.terminalMetadata)~="table" then return false,"manifest_metadata" end
		local reason
		entry,reason=cache.manifest(value)
		if not entry then return false,reason end
		for id in pairs(entry.changedNodeIds) do state.pendingNodeIds[id]=true end
		state.entry=entry;state.manifest=value;state.metadata=value.terminalMetadata;state.notModified=nil
		state.rows=nil;state.phase=nil;state.view=nil;state.buildRows=nil;state.request=nil
		return nextNode(state)
	elseif value.catalogNode then
		local accepted,reason=cache.block(value,retainedBytes)
		if not accepted then return false,reason end
		state.pendingNodeIds[value.nodeRecord.nodeId]=true
		state.blockVersion=(state.blockVersion or 0)+1
		state.retries=0
		state.receivedBlocks=(state.receivedBlocks or 0)+1
		return nextNode(state,true)
	end
	return false,"manifest_schema"
end
local function prepareView(state,rows,stats)
	state.stats=stats
	if stats.incremental then
		if not state.store then return false,"replica_view_base" end
		local undo,reason=Rows.patch(state.store,rows,stats.removedRowKeys or {},stats.rowCount)
		if not undo then return false,reason end
		state.undo=undo
		state.view={changed=rows,removed=stats.removedRowKeys or {}}
	else
		local store,reason=Rows.new(rows)
		if not store then return false,reason end
		state.store=store;state.view=nil
	end
	state.rows=state.store.rows
	local categories={}
	for key in pairs(state.store.categories) do
		if GlobalStorageSiK.CategoryResolution.isVanillaKey(key) then categories[#categories+1]=key end
	end
	state.metadata=shallow(state.metadata)
	state.metadata.categories=GlobalStorageSiK.Categories.buildCatalog(state.ack.networkId,{},categories)
	state.phase="apply"
	return true
end
local function apply(state)
	local applyStarted=now()
	if state.buildRows then
		local accepted,reason=prepareView(state,state.buildRows,state.stats)
		state.buildRows=nil
		if not accepted then return false,reason end
	end
	local payload=shallow(state.metadata)
	for k,v in pairs(intent(state)) do payload[k]=v end
	payload.inventoryRevision=state.manifest.inventoryRevision
	payload.manifestToken=state.manifest.manifestToken
	payload.snapshotRevision=state.manifest.snapshotRevision
	payload.snapshotCertified=not state.partial and state.manifest.snapshotCertified==true
	payload.reconcilePending=state.partial or state.manifest.reconcilePending
	payload.replicaPartial=state.partial==true
	payload.viewSequence=(state.viewSequence or 0)+1
	payload.itemTypeCount=#state.rows;payload.items=state.rows
	payload.openUi=context.pending(payload.playerNum)==true
	payload.accessMode=state.ack.accessMode;payload.terminalAnchor=state.ack.terminalAnchor
	payload.confirmedProximityRange=state.ack.confirmedProximityRange
	payload.confirmedWirelessRange=state.ack.confirmedWirelessRange
	local delta=false
	local current=context.currentState(payload.playerNum)
	if not payload.openUi and current and current.replicaEpoch==payload.replicaEpoch
		and current.catalogScope==payload.catalogScope and current.networkId==payload.networkId and state.view
		and tonumber(payload.inventoryRevision) and tonumber(current.inventoryRevision)
		and payload.inventoryRevision>=current.inventoryRevision then
		delta=true;payload.items=nil;payload.catalogDelta=true;payload.protocol=2
		payload.baseRevision=current.inventoryRevision
		payload.baseViewSequence=current.viewSequence or 0
		payload.changedRows=state.view.changed;payload.removedRowKeys=state.view.removed
	end
	local retained=math.max(4096,(state.stats and state.stats.retainedBytes) or #state.rows*1024)
	local generation=state.stats and state.stats.generation or state.derivedGeneration
	local commit,storeReason,cancel=cache.stageView(state.entry,state.rows,state.metadata,retained,
		not state.partial,state.store,generation,state.manifest.manifestToken)
	if not commit then return false,storeReason end
	state.cancelStage=cancel
	local accepted,reason=context.apply(payload,delta,state.rows)
	if accepted==false then return false,reason end
	if slots[payload.playerNum]~=state then return true end
	if not context.current(payload.playerNum,state.ack.openSeq) or not context.allowed(state.ack) then
		Client.clear(payload.playerNum,true);return true
	end
	if not commit() then return false,"manifest_changed" end
	state.cancelStage=nil
	state.undo=nil;state.viewSequence=payload.viewSequence;state.hasPresented=true
	state.derivedGeneration=generation;state.buildNodeIds=nil
	if GlobalStorageSiK.NetTrace and GlobalStorageSiK.NetTrace.isEnabled() then
		local stats=state.notModified and {} or state.stats or {}
		GlobalStorageSiK.NetTrace.write("Replica: vista aplicada",
			"network="..tostring(payload.networkId).." revision="..tostring(payload.inventoryRevision)
			.." notModified="..tostring(state.notModified==true).." nodes="..tostring(stats.nodesProcessed or 0)
			.." parents="..tostring(stats.parentsProcessed or 0).." bytes="..tostring(retained)
			.." buildMs="..tostring(state.buildMs or 0).." viewMs="..tostring(state.viewMs or 0)
			.." applyMs="..tostring(now()-applyStarted).." roundMs="..tostring(now()-(state.roundStarted or state.started)))
	end
	if slots[payload.playerNum]~=state then return true end
	state.phase=nil;state.previous=state.rows;state.view=nil;state.completed=true
	if not state.notModified and (state.partial or state.buildVersion~=state.blockVersion) then
		state.completed=false
		if state.buildVersion~=state.blockVersion then return nextNode(state,true) end
		return true
	end
	state.hasComplete=true
	local args=intent(state);args.manifestToken=state.manifest.manifestToken;args.inventoryRevision=payload.inventoryRevision
	return send(state,"terminalReplicaReady",args)
end
function Client.update()
	local active=false
	for offset=0,3 do
		local n=(cursor+offset)%4
		local state=slots[n]
		if state then
			if not context.current(n,state.ack.openSeq) then Client.clear(n,false)
			elseif not context.allowed(state.ack) then Client.clear(n,true)
			elseif not state.completed and not state.build and not state.phase and now()-state.started>10000 then
				active=true
				if not Client.recover(n) then Client.clear(n,false);context.failed(n,"catalog_timeout") end
			elseif state.build then
				active=true
				local phaseStarted=now()
				local done,rows,stats=GlobalStorageSiK.Index.stepCatalogBuild(state.build,256,2)
				state.buildMs=(state.buildMs or 0)+now()-phaseStarted
				if state.build.error then local reason=state.build.error;Client.clear(n,false);context.failed(n,reason)
				elseif done then
					state.build=nil
					state.buildRows=rows;state.stats=stats;state.phase="apply"
				end
			elseif state.phase=="apply" then
				active=true
				local ok,accepted,reason=pcall(apply,state)
				if not ok or accepted==false then
					if slots[n]==state then Client.clear(n,false);context.failed(n,ok and reason or accepted) end
				end
			end
		end
		if active then cursor=(n+1)%4;break end
	end
	return active
end
function Client.recover(playerNum)
	local state=slots[playerNum]
	if not state then return false end
	state.retries=state.retries+1
	trace("recovery",state.ack,"attempt="..state.retries.." reason=incomplete_transfer preserveConfirmed=true")
	if state.retries>2 then return false end
	state.started=now()
	-- Successfully installed blocks survive. Request a fresh manifest; matching
	-- revisions will be reused even if one fragment or derived view failed.
	local args=intent(state)
	return send(state,"terminalManifestRequest",args)
end
function Client.diagnostics() return cache.diagnostics() end
return Client

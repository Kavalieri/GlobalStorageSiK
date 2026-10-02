local Protocol=require "GS_ManifestProtocol"
local Replica=require "GS_NodeReplica"
local Rows=require "GS_CatalogRows"
local Profile=require "GS_InitialLoadProfile"
local Metrics=require "GS_InitialLoadMetrics"
require "GS_Index"
local Client={}
GlobalStorageSiK.NodeCatalogClient=Client
local context,slots=nil,{}
local owners={}
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
local function metric(state)
	local transport=GlobalStorageSiK.CatalogClient
	return transport and transport.metrics and transport.metrics(state.ack.playerNum)
end
local function shallow(value) local out={};for k,v in pairs(value or {}) do out[k]=v end;return out end
local function intent(state)
	local ack=state.ack
	return {networkId=ack.networkId,openSeq=ack.openSeq,playerNum=ack.playerNum,
		catalogScope=ack.catalogScope,replicaEpoch=ack.replicaEpoch,topologySequence=ack.topologySequence}
end
local function remainingBlocks(state)
	local remaining=0
	local entry=state.entry
	for i=1,#(entry and entry.records or {}) do
		local record=entry.records[i]
		local unavailable=record.availability=="unloaded_or_missing" or record.availability=="offline"
		if record.enabled and not entry.blocks[record.nodeId]
			and (record.confirmed or not unavailable) then remaining=remaining+1 end
	end
	return remaining
end
local function publishProgress(state,ready)
	if not context.progress then return true end
	local total=state.progressTotal
	local done=state.progressDone
	if total then
		done=math.max(done or 1,total-remainingBlocks(state)-1)
		if ready then done=total elseif done>=total then done=total-1 end
		if not state.progressDone or done>state.progressDone then state.progressDone=done end
	end
	local meta=intent(state)
	meta.manifestToken=state.manifest and state.manifest.manifestToken
	meta.inventoryRevision=state.manifest and state.manifest.inventoryRevision
	return context.progress(meta,state.progressDone,total,ready==true)
end
local function send(state,command,args)
	args=args or intent(state)
	if command=="terminalNodeRequest" then Metrics.count(metric(state),"requests") end
	return context.send(command,args,state.ack.playerNum)
end
local function failureIdentity(state)
	local result=intent(state)
	result.manifestToken=state.manifest and state.manifest.manifestToken
	result.inventoryRevision=state.manifest and state.manifest.inventoryRevision
	return result
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
local function currentOwner(playerNum)
	if not context.player then return true end
	local player=context.player(playerNum)
	if owners[playerNum] and owners[playerNum]~=player then Client.clear(playerNum,true) end
	owners[playerNum]=player
	return player~=nil
end
local function allowed(state)
	local accepted,reason=context.allowed(state.ack)
	if accepted then return true end
	reason=Protocol.suspendsAccess(reason) and reason or "catalog_access_changed"
	local n=state.ack.playerNum
	Client.clear(n,not Protocol.suspendsAccess(reason))
	trace("clientAccessSuspended",state.ack,"reason="..reason.." retained="..tostring(Protocol.suspendsAccess(reason)))
	if context.failed then context.failed(n,reason,failureIdentity(state)) end
	return false
end
function Client.confirm(ack)
	if ack.manifestSchema~=Protocol.SCHEMA or not Protocol.id(ack.replicaEpoch) then return false,"manifest_protocol" end
	local profile=Profile.snapshot(ack.initialLoadProfile or "control")
	if not profile then return false,"manifest_protocol" end
	if (profile.id=="final4" or profile.compactTables or profile.optimizedCodec or ack.initialLoadProfileHash~=nil) and ack.initialLoadProfileHash~=profile.hash then return false,"manifest_protocol" end
	if not currentOwner(ack.playerNum) then return false,"catalog_access_changed" end
	Client.clear(ack.playerNum,false)
	if ack.topologyTransition then
		local accepted,reason=cache.transition(ack)
		if not accepted then return false,reason end
	end
	local entry,reason=cache.confirm(ack)
	if reason then return false,reason end
	if entry then entry.topologySequence=ack.topologySequence or 0 end
	trace(entry and "clientCacheHit" or "clientCacheMiss",ack,entry and
		("reason=identity_confirmed cachedToken="..tostring(entry.token)) or "reason=no_confirmed_view")
	local current=ack.topologyTransition and context.currentState(ack.playerNum)
	slots[ack.playerNum]={ack=ack,profile=profile,entry=entry,previous=entry and entry.rows,previousMetadata=entry and entry.metadata,
		store=entry and entry.rows and entry.rowStore,hasComplete=entry and entry.rows~=nil,
		hasPresented=entry and entry.rows~=nil,receivedBlocks=0,
		derivedGeneration=entry and entry.rows and entry.derivedGeneration,
		pendingNodeIds=shallow(entry and entry.changedNodeIds),
		viewSequence=current and current.viewSequence or 0,started=now(),retries=0,buildMs=0,viewMs=0}
	return true
end
function Client.negotiate(ack)
	local state=slots[ack.playerNum]
	if not state or state.ack~=ack then return false end
	local args=intent(state)
	if state.entry and state.entry.confirmed then
		args.knownManifestToken=state.entry.confirmed.token
		args.knownMetadataToken=state.entry.confirmed.metadataToken
	end
	if state.entry and not state.entry.confirmed and state.entry.token then
		-- A draft token is only a resume hint. The server still captures and
		-- verifies the authoritative manifest before any cached block is reused.
		args.resumeManifestToken=state.entry.token
	end
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
		args.nodeBaseRevision=cache.baseRevision(state.entry,missing.nodeId)
		if state.hasPresented and not state.hasComplete and state.profile.groupCredits>1 and args.nodeBaseRevision==nil then
			local missingNodes=cache.missing(state.entry,state.profile.groupCredits)
			if #missingNodes>1 then
				args.nodeCount=#missingNodes
				for i=2,#missingNodes do args["nodeId"..i]=missingNodes[i].nodeId end
			end
		end
        local log=GlobalStorageSiK.NetTrace
        if log and log.isEnabled() then
        local units,rows,maximum=0,0,0
  for i=1,(args.nodeCount or 1) do
   local record=state.entry.byId and state.entry.byId[i==1 and args.nodeId or args["nodeId"..i]]
   if record then units=units+(record.units or 0);rows=rows+(record.rows or 0);maximum=math.max(maximum,record.units or 0) end
  end
  trace("node requested",args,"node="..args.nodeId.." nodeRevision="..tostring(missing.revision)
   .." nodes="..tostring(args.nodeCount or 1).." units="..tostring(units).." rows="..tostring(rows)
   .." maxNodeUnits="..tostring(maximum))
        end
		state.request=args;state.sentAt=now()
		if not send(state,"terminalNodeRequest",args) then return false,"node_send" end
	end
	if not missing then state.request=nil end
	if state.build or state.phase then return true end
	if missing and (not receivedBlock or state.hasComplete) then return true end
	-- Keep the first useful view and the final complete view unconditional.
	-- Intermediate bodies are already validated/ACKable; accumulate their node
	-- contributions without making the transport wait for every visual apply.
	if missing and state.hasPresented and not state.hasComplete
		and (state.receivedBlocks or 0)-(state.presentedBlocks or 0)<state.profile.viewBlocks then return true end
	state.partial=missing~=nil
	state.buildVersion=state.blockVersion
	state.buildPresentedBlocks=state.receivedBlocks or 0
	local changedIds=state.pendingNodeIds or {}
	state.buildNodeIds=changedIds;state.pendingNodeIds={}
	local entry,partial=state.entry,state.partial
	local registry=cache.registry(entry,partial,changedIds)
	if not registry then return false,"replica_incomplete" end
	state.build=GlobalStorageSiK.Index.beginCatalogBuild(state.ack.networkId,nil,nil,state.manifest.inventoryRevision,
		{registry=registry,key=(state.entry.derivedKey or state.entry.key)..Protocol.part(state.manifest.viewStamp or state.manifest.classificationEpoch),
			incremental=true,baseGeneration=state.derivedGeneration,changedNodeIds=changedIds,
			completeRegistry=function() return cache.registry(entry,partial) end})
	return state.build~=nil
end
function Client.consume(value,retainedBytes)
	local state=slots[value.playerNum]
	if not state or state.ack.openSeq~=value.openSeq or state.ack.networkId~=value.networkId
		or state.ack.replicaEpoch~=value.replicaEpoch
		or state.ack.catalogScope~=value.catalogScope
		or (state.ack.topologySequence or 0)~=(value.topologySequence or 0) then return false,"manifest_identity" end
	state.started=now()
	state.recovering=nil
	if value.catalogManifest then
		Metrics.bind(metric(state),value)
		trace("manifest received",value,"notModified="..tostring(value.manifestNotModified==true))
		state.completed=false
		state.blockVersion=(state.blockVersion or 0)+1
		state.roundStarted=now();state.buildMs=0;state.viewMs=0
		if state.build then GlobalStorageSiK.Index.cancelCatalogBuild(state.build);state.build=nil end
		for id in pairs(state.buildNodeIds or {}) do state.pendingNodeIds[id]=true end
		state.buildNodeIds=nil
		state.buildRows=nil;state.phase=nil;state.view=nil;state.request=nil
		local entry=cache.get(value)
		if value.metadataNotModified then
			local confirmed=entry and entry.confirmed
			if not value.manifestNotModified or value.terminalMetadata~=nil or not Protocol.id(value.metadataToken)
				or not confirmed or confirmed.token~=value.manifestToken
				or confirmed.metadataToken~=value.metadataToken or not confirmed.metadata then
				-- A missing confirmed control base requests the full envelope once,
				-- with no known tokens. It never borrows controls from a draft view.
				if Client.recover(value.playerNum) then return true end
				return false,"manifest_cache_miss"
			end
			-- Reconstruct a fresh envelope; retained control data is read-only.
			value.terminalMetadata=confirmed.metadata
		elseif state.profile.compactTables and not Protocol.id(value.metadataToken) then return false,"manifest_metadata" end
		state.previous=entry and entry.rows or state.previous
		state.previousMetadata=entry and entry.metadata or state.previousMetadata
		if value.manifestNotModified then
			if not entry or not entry.confirmed or entry.confirmed.token~=value.manifestToken
				or not entry.rows or not entry.metadata then
				return false,"manifest_cache_miss"
			end
			if type(value.terminalMetadata)~="table" then return false,"manifest_metadata" end
			state.entry=entry;state.manifest=value;state.metadata=value.terminalMetadata
			state.partial=false;state.stats=nil;state.store=entry.rowStore;state.hasComplete=true
			state.derivedGeneration=entry.derivedGeneration
			if context.topology then
				local accepted,reason=context.topology(value,value.terminalMetadata,false)
				if accepted==false then return false,reason end
			end
			Metrics.manifest(metric(state),entry.manifestStats)
			if entry.viewStamp~=value.viewStamp then
				state.derivedGeneration=nil;state.notModified=nil
				for _,record in ipairs(entry.records) do state.pendingNodeIds[record.nodeId]=true end
				state.progressDone,state.progressTotal=1,2
				return nextNode(state)
			end
			state.rows=entry.rows;state.phase="apply";state.notModified=true
			state.view={changed={},removed={}}
			state.progressDone,state.progressTotal=1,2
			publishProgress(state,false)
			trace("notModified",value,"nodesRequested=0 buildWork=0")
			return true
		end
		if type(value.terminalMetadata)~="table" then return false,"manifest_metadata" end
		local reason
		entry,reason=cache.manifest(value,state.ack)
		if not entry then return false,reason end
		if context.topology then
			local accepted,topologyReason=context.topology(value,value.terminalMetadata,false)
			if accepted==false then return false,topologyReason end
		end
		for id in pairs(entry.changedNodeIds) do state.pendingNodeIds[id]=true end
		state.entry=entry;state.manifest=value;state.metadata=value.terminalMetadata;state.notModified=nil
		Metrics.manifest(metric(state),entry.manifestStats)
		state.rows=nil;state.phase=nil;state.view=nil;state.buildRows=nil;state.request=nil
		state.progressDone=1
		state.progressTotal=remainingBlocks(state)+2
		publishProgress(state,false)
		return nextNode(state)
	elseif value.catalogNode then
		if value.nodeBlocks~=nil then
			local blocks=value.nodeBlocks
			if type(blocks)~="table" or getmetatable(blocks)~=nil or #blocks<1 or #blocks>state.profile.groupCredits
				or not Protocol.integer(retainedBytes,1,32*1024*1024) then return false,"node_group" end
			local seen,count={},0
			for key in pairs(blocks) do
				if not Protocol.integer(key,1,#blocks) then return false,"node_group" end
				count=count+1
			end
			if count~=#blocks then return false,"node_group" end
			for i=1,#blocks do
				local block=blocks[i]
				local record=type(block)=="table" and getmetatable(block)==nil and Protocol.record(block.nodeRecord)
				if not record or not record.confirmed or seen[record.nodeId] or not Protocol.sameBlock(record,state.entry.byId[record.nodeId])
					or type(block.nodeSnapshot)~="table" or getmetatable(block.nodeSnapshot)~=nil or block.nodeDelta~=nil then return false,"node_group" end
				seen[record.nodeId]=true
			end
			local changed=false
			for i=1,#blocks do
				local block=blocks[i];local meta=shallow(value)
				meta.nodeBlocks=nil;meta.nodeRecord=block.nodeRecord;meta.nodeSnapshot=block.nodeSnapshot
				local accepted,reason=cache.block(meta,math.ceil(retainedBytes/#blocks))
				if not accepted then return false,reason end
				if reason~="duplicate" then
					changed=true;state.pendingNodeIds[block.nodeRecord.nodeId]=true
					state.receivedBlocks=(state.receivedBlocks or 0)+1;Metrics.count(metric(state),"nodeBodies")
				end
			end
			if changed then state.blockVersion=(state.blockVersion or 0)+1;state.retries=0;publishProgress(state,false) end
			return nextNode(state,changed)
		end
		local accepted,reason=cache.block(value,retainedBytes)
		if not accepted then return false,reason end
		if reason=="duplicate" then
			trace("node duplicate",value,"node="..tostring(value.nodeRecord and value.nodeRecord.nodeId))
			return nextNode(state,false)
		end
		Metrics.count(metric(state),"nodeBodies")
		state.pendingNodeIds[value.nodeRecord.nodeId]=true
		state.blockVersion=(state.blockVersion or 0)+1
		state.retries=0
		state.receivedBlocks=(state.receivedBlocks or 0)+1
		publishProgress(state,false)
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
	elseif state.store then
		-- A classification change derives all rows locally, but still patches the
		-- mounted view transactionally instead of rebuilding its window/widgets.
		local present,removed={},{}
		for _,row in ipairs(rows) do present[row.rowKey]=true end
		for key in pairs(state.store.byKey) do if not present[key] then removed[#removed+1]=key end end
		local undo,reason=Rows.patch(state.store,rows,removed,#rows)
		if not undo then return false,reason end
		state.undo=undo;state.view={changed=rows,removed=removed}
	else
		local store,reason=Rows.new(rows)
		if not store then return false,reason end
		state.store=store;state.view=nil
	end
	state.rows=state.store.rows
	state.phase="apply"
	return true
end
local function apply(state)
	local applyStarted=now()
	local prepareMs,stageMs,consumerMs=0,0,0
	if state.buildRows then
		local accepted,reason=prepareView(state,state.buildRows,state.stats)
		state.buildRows=nil
		if not accepted then return false,reason end
	end
	-- Fresh control metadata also accompanies notModified. Preserve categories
	-- derived from the confirmed local rows without rebuilding those rows.
	if state.store then
		local categories={}
		for key in pairs(state.store.categories) do
			if GlobalStorageSiK.CategoryResolution.isVanillaKey(key) then categories[#categories+1]=key end
		end
		state.metadata=shallow(state.metadata)
		state.metadata.categories=GlobalStorageSiK.Categories.composeCatalog({state.metadata.categories,categories})
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
	payload._gsAwaitReplicaReady=true
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
	prepareMs=now()-applyStarted
	local stageStarted=now()
	local retained=math.max(4096,(state.stats and state.stats.retainedBytes) or #state.rows*1024)
	local generation=state.stats and state.stats.generation or state.derivedGeneration
	local commit,storeReason,cancel=cache.stageView(state.entry,state.rows,state.metadata,retained,
		not state.partial,state.store,generation,state.manifest.manifestToken,state.manifest.viewStamp)
	if not commit then return false,storeReason end
	state.cancelStage=cancel
	stageMs=now()-stageStarted
	local consumerStarted=now()
	local accepted,reason=context.apply(payload,delta,state.rows)
	consumerMs=now()-consumerStarted
	if accepted==false then return false,reason end
	if slots[payload.playerNum]~=state then return true end
	if not context.current(payload.playerNum,state.ack.openSeq) then Client.clear(payload.playerNum,false);return true end
	if not allowed(state) then return true end
	if not commit() then return false,"manifest_changed" end
	if not state.partial and state.entry.confirmed then state.entry.confirmed.metadataToken=state.manifest.metadataToken end
	state.cancelStage=nil
	state.undo=nil;state.viewSequence=payload.viewSequence;state.hasPresented=true
	state.presentedBlocks=state.buildPresentedBlocks or state.receivedBlocks or 0
	if GlobalStorageSiK.CatalogClient and GlobalStorageSiK.CatalogClient.recordReplicaView then
		GlobalStorageSiK.CatalogClient.recordReplicaView(payload.playerNum,#state.rows,false)
	end
	state.derivedGeneration=generation;state.buildNodeIds=nil
	if GlobalStorageSiK.NetTrace and GlobalStorageSiK.NetTrace.isEnabled() then
		local stats=state.notModified and {} or state.stats or {}
		GlobalStorageSiK.NetTrace.write("Replica: vista aplicada",
			"network="..tostring(payload.networkId).." revision="..tostring(payload.inventoryRevision)
			.." notModified="..tostring(state.notModified==true).." nodes="..tostring(stats.nodesProcessed or 0)
			.." parents="..tostring(stats.parentsProcessed or 0).." bytes="..tostring(retained)
			.." buildMs="..tostring(state.buildMs or 0).." viewMs="..tostring(state.viewMs or 0)
			.." prepareMs="..tostring(prepareMs).." stageMs="..tostring(stageMs)
			.." consumerMs="..tostring(consumerMs).." postConsumerMs="..tostring(now()-consumerStarted-consumerMs)
			.." applyMs="..tostring(now()-applyStarted).." roundMs="..tostring(now()-(state.roundStarted or state.started)))
	end
	if slots[payload.playerNum]~=state then return true end
	state.phase=nil;state.previous=state.rows;state.view=nil;state.completed=true
	if not state.notModified and (state.partial or state.buildVersion~=state.blockVersion) then
		state.completed=false
		-- Tras publicar la primera ventana parcial hay que pedir inmediatamente el
		-- siguiente nodo. Dejar el estado sin build, phase ni request lo aparcaba
		-- hasta el watchdog de 10 s y mantenia capacidad en «Cargando».
		return nextNode(state,false)
	end
	state.hasComplete=true
	local args=intent(state);args.manifestToken=state.manifest.manifestToken;args.inventoryRevision=payload.inventoryRevision
	local ready=send(state,"terminalReplicaReady",args)
	if ready and GlobalStorageSiK.CatalogClient and GlobalStorageSiK.CatalogClient.recordReplicaComplete then
		GlobalStorageSiK.CatalogClient.recordReplicaComplete(payload.playerNum)
	end
	payload._gsAwaitReplicaReady=nil
	if ready then publishProgress(state,true) end
	return ready
end
local function applyChecked(state,n)
	local summary,phaseStarted=metric(state),now()
	Metrics.enter(summary)
	local ok,accepted,reason=pcall(apply,state)
	Metrics.work(summary,"apply",now()-phaseStarted)
	if (not ok or accepted==false) and slots[n]==state then
		local identity=failureIdentity(state)
		Client.clear(n,false);context.failed(n,ok and reason or accepted,identity)
	end
	Metrics.leave(summary)
end
function Client.update()
	local active=false
	for offset=0,3 do
		local n=(cursor+offset)%4
		currentOwner(n)
		local state=slots[n]
		if state then
			if not context.current(n,state.ack.openSeq) then Client.clear(n,false)
			elseif not allowed(state) then -- Access loss already cancelled this round.
			else
			local timestamp=now()
			if timestamp<state.started then state.started=timestamp end
			local transport=GlobalStorageSiK.CatalogClient
			local progressed=transport and transport.replicaProgress and transport.replicaProgress(state.ack)
			if progressed and progressed<=timestamp and progressed>state.started then state.started=progressed end
			if not state.completed and not state.build and not state.phase and timestamp-state.started>10000 then
				active=true
				if not Client.recover(n) then Client.clear(n,false);context.failed(n,"catalog_timeout") end
			elseif state.build then
				active=true
				local phaseStarted=now()
				local done,rows,stats
				local work=0
				local build=state.build
				repeat
					local remaining=math.max(1,2-(now()-phaseStarted))
					done,rows,stats=GlobalStorageSiK.Index.stepCatalogBuild(build,256,remaining)
					work=work+256
				until done or build.error or build.cancelled or slots[n]~=state or state.build~=build
					or work>=state.profile.buildWork or now()-phaseStarted>=2
				Metrics.work(metric(state),"build",now()-phaseStarted)
				state.buildMs=(state.buildMs or 0)+now()-phaseStarted
				if slots[n]~=state or state.build~=build then -- Reentrant replacement owns its own work.
				elseif build.error then
					local reason,identity=build.error,failureIdentity(state)
					Client.clear(n,false);context.failed(n,reason,identity)
				elseif done then
					state.build=nil
					state.buildRows=rows;state.stats=stats;state.phase="apply"
					-- Apply remains indivisible; start it in its own next update.
				end
			elseif state.phase=="apply" then
				active=true
				applyChecked(state,n)
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
	-- Multiple failure paths may observe the same in-flight recovery. Retain one
	-- intent until a verified payload arrives; the watchdog can retry a real stall.
	if state.recovering and now()-state.started<=10000 then return true end
	state.retries=state.retries+1
	trace("recovery",state.ack,"attempt="..state.retries.." reason=incomplete_transfer preserveConfirmed=true")
	if state.retries>2 then return false end
	state.started=now()
	-- Successfully installed blocks survive. Request a fresh manifest; matching
	-- revisions will be reused even if one fragment or derived view failed.
	local args=intent(state)
	args.replicaRecovery=true
	local accepted=send(state,"terminalManifestRequest",args)
	if accepted then state.recovering=true;Metrics.count(metric(state),"recoveries") end
	return accepted
end
function Client.diagnostics() return cache.diagnostics() end

-- Diagnostic references only; exported after the timed complete boundary.
function Client.oracleStatus(playerNum)
	local state=slots[playerNum]
	if not state then return {playerNum=playerNum,completed=false,hasComplete=false} end
	local status=shallow(state.ack)
	for _,key in ipairs({"manifestToken","inventoryRevision","snapshotRevision","snapshotCertified","reconcilePending"}) do
		status[key]=state.manifest and state.manifest[key]
	end
	status.completed=state.completed==true;status.hasComplete=state.hasComplete==true;status.partial=state.partial==true
	status.contextCurrent=context.current(playerNum,state.ack.openSeq)==true
	status.accessAllowed=context.allowed(state.ack)==true
	status.cacheAccepted=state.entry~=nil and cache.acceptView(state.entry)==true
	status.confirmedToken=state.entry and state.entry.confirmed and state.entry.confirmed.token or nil
	return status
end
function Client.oracleImage(playerNum)
	local state=slots[playerNum]
	if not state or not state.completed or not state.hasComplete or state.partial
		or not context.current(playerNum,state.ack.openSeq) or not context.allowed(state.ack)
		or not cache.acceptView(state.entry) then return nil,"oracle_incomplete" end
	local entry=state.entry
	if not entry.confirmed or entry.confirmed.token~=state.manifest.manifestToken then return nil,"oracle_token" end
	local meta=shallow(state.ack)
	meta.manifestToken=state.manifest.manifestToken;meta.inventoryRevision=state.manifest.inventoryRevision
	meta.snapshotCertified=state.manifest.snapshotCertified;meta.reconcilePending=state.manifest.reconcilePending
	local nodes={}
	for _,record in ipairs(entry.records) do
		if record.enabled then
			local block=entry.blocks[record.nodeId]
			if not record.confirmed or not block then return nil,"oracle_unconfirmed" end
			nodes[#nodes+1]={record=record,snapshot=block.snapshot}
		end
	end
	return {meta=meta,nodes=nodes},nil,function()
		return slots[playerNum]==state and state.completed and state.hasComplete and not state.partial
			and state.manifest and state.manifest.snapshotCertified==true and state.manifest.reconcilePending~=true
			and state.manifest.inventoryRevision==meta.inventoryRevision and state.manifest.manifestToken==meta.manifestToken
			and context.current(playerNum,meta.openSeq) and context.allowed(state.ack)
			and cache.acceptView(entry) and entry.confirmed and entry.confirmed.token==meta.manifestToken
	end
end
return Client

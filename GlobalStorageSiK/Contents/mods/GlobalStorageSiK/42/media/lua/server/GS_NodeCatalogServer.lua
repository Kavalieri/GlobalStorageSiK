-- Post-access negotiation and bounded one-block-at-a-time requests.
local Protocol=require "GS_ManifestProtocol"
local Manifest=require "GS_NodeManifest"
local Server={}
GlobalStorageSiK.NodeCatalogServer=Server
local context,states=nil,{}
local metadataFields=Protocol.METADATA_FIELDS
local function now() return getTimestampMs and getTimestampMs() or 0 end
function Server.configure(value) context=value end
function Server.clear(player) states[player]=nil end
function Server.opened(player,session)
	if session.replicaEpoch then states[player]={session=session,started=now()} end
end
function Server.active(player) return states[player]~=nil end
function Server.negotiated(player) return states[player] and states[player].negotiated==true end
function Server.received(player)
	local state=states[player]
	if state then state.lastPayload=nil end
end
function Server.reject(player)
	local state=states[player]
	if not state then return false end
	state.rejected=true;state.request=nil;state.retry=nil;state.ready=nil;state.lastPayload=nil
	return true
end
local function valid(player,args)
	local state=states[player]
	if not state or type(args)~="table" or args.openSeq~=state.session.openSeq
		or args.networkId~=state.session.networkId or args.replicaEpoch~=state.session.replicaEpoch
		or args.catalogScope~=state.session.catalogScope
		or (args.topologySequence or 0)~=(state.session.topologySequence or 0) then return nil end
	if not context.valid(player,state.session,args) then return nil end
	return state
end
local function refresh(player,state)
	-- A recovery cannot replace an unacknowledged frame. Keep one intent and
	-- retry after its receipt; ordinary refreshes remain coalesced until ready.
	if context.hasJob(player) then state.retry=true;return end
	state.request=nil;state.retry=nil;state.ready=nil
	state.roundActive=nil;state.refreshPending=nil
	context.refresh(player,state.session.networkId)
end
function Server.queueState(player,payload)
	local state=states[player]
	if not state or not state.negotiated then return false,"manifest_negotiation" end
	if state.rejected then return true,"catalog_session_fenced" end
	local metadata={}
	for i=1,#metadataFields do local key=metadataFields[i];metadata[key]=payload[key] end
	local signature=Protocol.metadataSignature(metadata)
	if not signature then return false,"manifest_metadata_budget" end
	if context.hasJob(player) or state.roundActive then
		-- Do not discard an accepted node request in the ACK-to-node handoff.
		-- Rebuild current metadata once the complete replica is acknowledged.
		local current=state.manifest
		if not current or current.inventoryRevision~=payload.inventoryRevision or state.controlStamp~=signature
			or current.snapshotRevision~=payload.snapshotRevision or current.snapshotCertified~=payload.snapshotCertified
			or current.reconcilePending~=payload.reconcilePending then state.refreshPending=true end
		return true,"manifest_coalesced"
	end
	local manifest,reason=Manifest.capture(player,state.session,state.knownToken)
	if not manifest then return false,reason end
	state.manifest=manifest
	state.request=nil
	-- Control metadata is fresh even when the complete set of blocks is stable.
	manifest.terminalMetadata=metadata
	manifest.viewStamp=Protocol.metadataSignature({classification=manifest.classificationEpoch,
		routing=manifest.routingRevision,categories=metadata.categories,configEpoch=metadata.configEpoch})
	if not manifest.viewStamp then return false,"manifest_metadata_budget" end
	manifest.catalogSource=manifest.manifestNotModified and "manifest_not_modified" or "node_manifest"
	manifest.snapshotRevision=payload.snapshotRevision
	manifest.snapshotCertified=payload.snapshotCertified
	manifest.reconcilePending=payload.reconcilePending
	for _,record in ipairs(manifest.nodeManifest or {}) do
		if record.enabled and not record.confirmed then manifest.snapshotCertified=false;manifest.reconcilePending=true end
	end
	state.lastPayload=manifest
	local trace=GlobalStorageSiK.NetTrace
	if trace and trace.isEnabled() then
		trace.write("Manifest: decision","network="..tostring(manifest.networkId)
			.." token="..tostring(manifest.manifestToken).." revision="..tostring(manifest.inventoryRevision)
			.." notModified="..tostring(manifest.manifestNotModified==true)
			.." reason="..(manifest.manifestNotModified and "confirmed_token" or state.knownToken and "manifest_changed" or "bootstrap_or_recovery")
			.." records="..tostring(#(manifest.nodeManifest or {})))
	end
	local accepted,queueReason=context.queue(player,manifest)
	if accepted then state.roundActive=true;state.controlStamp=signature end
	if trace and trace.isEnabled() then
		trace.write("Manifest: queue","network="..tostring(manifest.networkId).." token="..tostring(manifest.manifestToken)
			.." accepted="..tostring(accepted==true).." reason="..tostring(queueReason or "queued"))
	end
	return accepted,queueReason
end
function Server.dispatch(command,player,args)
	if command~="terminalManifestRequest" and command~="terminalNodeRequest"
		and command~="terminalReplicaReady" and command~="terminalReplicaReject" then return false end
	local state=valid(player,args)
	if not state then return true end
	if command=="terminalReplicaReject" then
		if state.manifest and args.manifestToken==state.manifest.manifestToken
			and args.inventoryRevision==state.manifest.inventoryRevision then
			Server.reject(player)
			if context.fence then context.fence(player,"catalog_consumer") end
		end
		return true
	end
	if state.rejected then return true end
	if command=="terminalManifestRequest" then
		if args.knownManifestToken~=nil and not Protocol.id(args.knownManifestToken) then return true end
		state.negotiated=true;state.knownToken=args.knownManifestToken
		refresh(player,state)
	elseif command=="terminalNodeRequest" then
		if not state.negotiated or not Protocol.id(args.nodeId) or not Protocol.id(args.manifestToken) then return true end
		if not state.roundActive or not state.manifest or args.manifestToken~=state.manifest.manifestToken then return true end
		-- Reliable unordered commands may precede the manifest receipt. Retain one
		-- descriptor and serve it only after the previous frame job is released.
		if not state.request then state.request={nodeId=args.nodeId,token=args.manifestToken} end
	elseif state.roundActive and state.manifest and args.manifestToken==state.manifest.manifestToken
		and args.inventoryRevision==state.manifest.inventoryRevision then
		state.ready={token=args.manifestToken,revision=args.inventoryRevision}
	end
	return true
end
function Server.recover(player)
	local state=states[player]
	if not state or not state.negotiated or state.rejected then return false end
	state.retries=(state.retries or 0)+1
	if state.retries>2 then return false end
	state.retry=true
	return true
end
function Server.update()
	local retired={}
	for player,state in pairs(states) do
		local pending=state.ready or state.retry or state.request or (state.refreshPending and not state.roundActive)
		local check=pending or now()-(state.checkedAt or 0)>=1000
		local accepted,reason=true,nil
		if check then state.checkedAt=now();accepted,reason=context.valid(player,state.session,state.session) end
		if not accepted then retired[#retired+1]={player=player,reason=reason or "catalog_access_changed"}
		elseif pending and not context.hasJob(player) then
			if state.ready then
				local accepted=context.completed(player,state.ready.revision,state.session.catalogScope)
				if accepted~=false and states[player]==state then
					state.knownToken=state.ready.token;state.ready=nil;state.retries=0
					state.roundActive=nil;state.request=nil
					if state.refreshPending then refresh(player,state) end
				end
			elseif state.retry then
				state.retry=nil
				state.knownToken=nil;refresh(player,state)
			elseif state.refreshPending and not state.roundActive then refresh(player,state)
			elseif state.request and now()>=(state.request.due or 0) then
				local request=state.request;state.request=nil
				local payload,reason=Manifest.block(player,state.session,request.nodeId,request.token)
				if payload then
					payload.catalogSource="node_block";state.lastPayload=payload
					context.queue(player,payload)
				elseif reason=="node_revision" or reason=="manifest_changed" then refresh(player,state)
				elseif reason=="node_unconfirmed" then
					local registry=GlobalStorageSiK.Zones.getRegistry()
					local node=registry.nodes and registry.nodes[request.nodeId]
					if node and node.snapshotAvailability=="unloaded_or_missing" then refresh(player,state)
					else request.due=now()+250;state.request=request end
				else context.failed(player,reason or "node_unconfirmed") end
			end
		end
	end
	for i=1,#retired do
		-- Revocation must reach the client even when no catalog job is in flight.
		context.failed(retired[i].player,retired[i].reason)
		Server.clear(retired[i].player)
	end
end
return Server

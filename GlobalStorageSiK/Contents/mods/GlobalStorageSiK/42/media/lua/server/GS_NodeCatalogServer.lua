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
local function valid(player,args)
	local state=states[player]
	if not state or type(args)~="table" or args.openSeq~=state.session.openSeq
		or args.networkId~=state.session.networkId or args.replicaEpoch~=state.session.replicaEpoch
		or args.catalogScope~=state.session.catalogScope then return nil end
	if not context.valid(player,state.session,args) then return nil end
	return state
end
local function refresh(player,state)
	state.request=nil;state.retry=nil
	context.refresh(player,state.session.networkId)
end
function Server.queueState(player,payload)
	local state=states[player]
	if not state or not state.negotiated then return false,"manifest_negotiation" end
	if context.hasJob(player) then return false,"catalog_inflight" end
	local metadata={}
	for i=1,#metadataFields do local key=metadataFields[i];metadata[key]=payload[key] end
	local signature=Protocol.metadataSignature(metadata)
	if not signature then return false,"manifest_metadata_budget" end
	state.session.controlStamp=signature
	local manifest,reason=Manifest.capture(player,state.session,state.knownToken)
	state.session.controlStamp=nil
	if not manifest then return false,reason end
	state.manifest=manifest
	state.request=nil
	if not manifest.manifestNotModified then manifest.terminalMetadata=metadata end
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
	return context.queue(player,manifest)
end
function Server.dispatch(command,player,args)
	if command~="terminalManifestRequest" and command~="terminalNodeRequest" and command~="terminalReplicaReady" then return false end
	local state=valid(player,args)
	if not state then return true end
	if command=="terminalManifestRequest" then
		if args.knownManifestToken~=nil and not Protocol.id(args.knownManifestToken) then return true end
		state.negotiated=true;state.knownToken=args.knownManifestToken
		refresh(player,state)
	elseif command=="terminalNodeRequest" then
		if not state.negotiated or not Protocol.id(args.nodeId) or not Protocol.id(args.manifestToken) then return true end
		-- Reliable unordered commands may precede the manifest receipt. Retain one
		-- descriptor and serve it only after the previous frame job is released.
		if not state.request then state.request={nodeId=args.nodeId,token=args.manifestToken} end
	elseif state.manifest and args.manifestToken==state.manifest.manifestToken
		and args.inventoryRevision==state.manifest.inventoryRevision then
		state.ready={token=args.manifestToken,revision=args.inventoryRevision}
	end
	return true
end
function Server.recover(player)
	local state=states[player]
	if not state or not state.negotiated then return false end
	state.retries=(state.retries or 0)+1
	if state.retries>2 then return false end
	state.retry=true
	return true
end
function Server.update()
	local retired={}
	for player,state in pairs(states) do
		local pending=state.ready or state.retry or state.request
		local check=pending or now()-(state.checkedAt or 0)>=1000
		local accepted=true
		if check then state.checkedAt=now();accepted=context.valid(player,state.session,state.session) end
		if not accepted then retired[#retired+1]=player
		elseif pending and not context.hasJob(player) then
			if state.ready then
				context.completed(player,state.ready.revision,state.session.catalogScope)
				state.knownToken=state.ready.token;state.ready=nil;state.retries=0
			elseif state.retry then
				state.retry=nil
				state.knownToken=nil;refresh(player,state)
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
	for i=1,#retired do Server.clear(retired[i]) end
end
return Server

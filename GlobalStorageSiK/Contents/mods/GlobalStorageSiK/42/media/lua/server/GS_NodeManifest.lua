-- Manifests inspect confirmed metadata only. No ItemContainer or item traversal.
local Protocol = require "GS_ManifestProtocol"
local Snapshots = require "GS_NodeSnapshots"
local Metrics = require "GS_InitialLoadMetrics"
local Manifest = {}
GlobalStorageSiK.NodeManifest = Manifest
local context, sessions, serial = nil, {}, 0
local topologies, topologyCount, topologyBytes, retainedBytes, clock = {}, 0, 0, 0, 0

function Manifest.configure(value) context=value end
function Manifest.clear(player)
	local state=sessions[player]
	retainedBytes=math.max(0,retainedBytes-(state and state.bytes or 0));sessions[player]=nil
end

local function append(parts, value) parts[#parts+1]=Protocol.part(value) end

local function authorized(player, meta)
	if not context or type(meta)~="table" or not Protocol.id(meta.networkId)
		or not Protocol.id(meta.replicaEpoch) then return false,"manifest_identity" end
	return context.valid(player,meta)
end

function Manifest.capture(player, meta, knownToken)
	local valid, reason=authorized(player,meta)
	if not valid then Manifest.clear(player);return nil,reason or "catalog_access_changed" end
	local registry=context.registry()
	local network=registry.networks and registry.networks[meta.networkId]
	if not network then return nil,"manifest_network" end
	-- Bounded by the retained 128 topology entries, never by inventory rows.
	local retiredNetworks={}
	for id in pairs(topologies) do
		if not registry.networks[id] then retiredNetworks[#retiredNetworks+1]=id end
	end
	for i=1,#retiredNetworks do
		local id=retiredNetworks[i]
		topologyBytes=math.max(0,topologyBytes-#topologies[id])
		topologyCount=topologyCount-1;topologies[id]=nil
	end
	local records,topology,parts={}, {}, {}
	local visited=0
	for nodeId,node in pairs(registry.nodes or {}) do
		visited=visited+1
		if visited>Protocol.MAX_NODES then return nil,"manifest_nodes_limit" end
		local zone=registry.zones and registry.zones[node.zoneId]
		if zone and zone.networkId==meta.networkId then
			topology[#topology+1]=Protocol.part(nodeId)..Protocol.part(node.zoneId)
				..Protocol.part(node.membership)..Protocol.part(node.enabled)..Protocol.part(zone.enabled)
			if context.zoneAllowed(player,meta.networkId,node.zoneId) then
				local record=Snapshots.record(node)
				-- Unknown legacy snapshots require a directed schema upgrade first.
				if record.schema~=Protocol.SCHEMA then
					record.confirmed=false
					if GlobalStorageSiK.CatalogReconciler and GlobalStorageSiK.CatalogReconciler.markDirty then
						GlobalStorageSiK.CatalogReconciler.markDirty(nodeId,"replication_bootstrap")
					end
				end
				record.enabled=record.enabled and zone.enabled~=false
				record=Protocol.record(record)
				if not record then return nil,"manifest_record" end
				records[#records+1]=record
			end
		end
	end
	for zoneId,zone in pairs(registry.zones or {}) do
		visited=visited+1
		if visited>Protocol.MAX_NODES*2 then return nil,"manifest_zones_limit" end
		if zone.networkId==meta.networkId then topology[#topology+1]=Protocol.part(zoneId)..Protocol.part(zone.enabled) end
	end
	table.sort(topology)
	local topologyText=table.concat(topology)
	local topologyDelta=#topologyText-(topologies[meta.networkId] and #topologies[meta.networkId] or 0)
	if topologyBytes+topologyDelta>8*1024*1024 then return nil,"manifest_topology_budget" end
	if not topologies[meta.networkId] then
		if topologyCount>=128 then return nil,"manifest_network_limit" end
		topologyCount=topologyCount+1
	end
	if topologies[meta.networkId]~=topologyText then
		network.topologyRevision=(tonumber(network.topologyRevision) or 0)+1
		topologies[meta.networkId]=topologyText
		topologyBytes=topologyBytes+topologyDelta
	end
	table.sort(records,function(a,b) return a.nodeId<b.nodeId end)
	append(parts,meta.replicaEpoch);append(parts,meta.catalogScope)
	append(parts,network.topologyRevision)
	-- The token describes reusable blocks, not scan/control or presentation.
	-- Access is still validated above and before every individual block.
	local manifestStats=Metrics.manifestAccumulator()
	for i=1,#records do
		local record=records[i]
		Metrics.manifestRecord(manifestStats,record)
		append(parts,record.nodeId);append(parts,record.zoneId);append(parts,record.revision)
		append(parts,record.signature);append(parts,record.schema);append(parts,record.enabled)
		append(parts,record.confirmed);append(parts,record.availability)
	end
	local signature=table.concat(parts)
	local previous=sessions[player]
	local same=previous and previous.networkId==meta.networkId and previous.epoch==meta.replicaEpoch
		and previous.signature==signature
	if not same then
		local live,count,retired={},0,{}
		context.visit(function(p) live[p]=true end)
		for p in pairs(sessions) do
			if not live[p] then retired[#retired+1]=p else count=count+1 end
		end
		for i=1,#retired do Manifest.clear(retired[i]) end
		if not previous and count>=128 then return nil,"manifest_busy" end
		local carry=previous and previous.networkId==meta.networkId and previous.epoch==meta.replicaEpoch
			and previous.scope==meta.catalogScope and previous or nil
		local reservation=#signature*2+#records*1024+4096+(carry and carry.stampBytes or 0)
		if reservation>8*1024*1024 then return nil,"manifest_budget" end
		if retainedBytes-(previous and previous.bytes or 0)+reservation>32*1024*1024 then
			return nil,"manifest_busy"
		end
		serial=serial+1
		previous={networkId=meta.networkId,epoch=meta.replicaEpoch,scope=meta.catalogScope,signature=signature,
			token=meta.replicaEpoch..":"..tostring(serial),records=records,byId={},bytes=reservation,
			revision=context.inventoryRevision(meta.networkId),stampBytes=carry and carry.stampBytes,
			controlSignature=carry and carry.controlSignature,viewSignature=carry and carry.viewSignature,
			metadataToken=carry and carry.metadataToken,viewToken=carry and carry.viewToken}
		for i=1,#records do previous.byId[records[i].nodeId]=records[i] end
		Manifest.clear(player);retainedBytes=retainedBytes+reservation
		sessions[player]=previous
	end
	clock=clock+1;previous.usedAt=clock
	previous.revision=context.inventoryRevision(meta.networkId)
	local result={manifestSchema=Protocol.SCHEMA,replicaEpoch=meta.replicaEpoch,
		manifestToken=previous.token,networkId=meta.networkId,catalogScope=meta.catalogScope,topologySequence=meta.topologySequence,
		topologyRevision=network.topologyRevision,routingRevision=network.routingRevision or 0,
		classificationEpoch=context.classificationStamp(),contentWatermark=network.contentWatermark or 0,
		inventoryRevision=context.inventoryRevision(meta.networkId),catalogManifest=true}
	if knownToken==previous.token then result.manifestNotModified=true
	else result.nodeManifest=previous.records end
	if manifestStats then manifestStats.seenZones=nil end
	return result,nil,manifestStats
end

function Manifest.diagnostics() return {retainedBytes=retainedBytes,topologyBytes=topologyBytes,networks=topologyCount} end

-- Short identities are assigned after exact canonical comparison, not a weak
-- digest. They live in the same authorized, bounded session as the block token.
function Manifest.stamps(player,control,view)
	local state=sessions[player]
	if not state or type(control)~="string" or type(view)~="string" then return nil,"manifest_metadata" end
	local bytes=(#control+#view)*4+512
	local delta=bytes-(state.stampBytes or 0)
	if state.bytes+delta>8*1024*1024 or retainedBytes+delta>32*1024*1024 then return nil,"manifest_budget" end
	local priorToken=state.metadataToken
 local changedAt
 local trace=GlobalStorageSiK.NetTrace
 if trace and trace.isEnabled() and state.controlSignature and state.controlSignature~=control then
  local before=state.controlSignature
  local at,limit=1,math.min(#before,#control,2048)
  -- Diagnostics must not scan a 4 MiB canonical signature on the update path.
  -- Compare a bounded prefix in chunks, then at most one chunk byte by byte.
  while at<=limit do
   local last=math.min(limit,at+63)
   if string.sub(before,at,last)~=string.sub(control,at,last) then
    while at<=last and string.byte(before,at)==string.byte(control,at) do at=at+1 end
    break
   end
   at=last+1
  end
  changedAt=at<=limit and at or limit<2048 and at or "prefix_scan_truncated"
 end
 if state.controlSignature~=control then
		serial=serial+1;state.metadataToken=state.epoch..":m:"..tostring(serial);state.controlSignature=control
	end
	if state.viewSignature~=view then
		serial=serial+1;state.viewToken=state.epoch..":v:"..tostring(serial);state.viewSignature=view
	end
	state.bytes=state.bytes+delta;retainedBytes=retainedBytes+delta;state.stampBytes=bytes
	return state.metadataToken,state.viewToken,priorToken,changedAt
end

local function prepareBlock(player,meta,nodeId,token,baseRevision,state)
	if not state or state.epoch~=meta.replicaEpoch or state.networkId~=meta.networkId
		or state.token~=token or not Protocol.id(nodeId) then return nil,"manifest_changed" end
	local record=state.byId[nodeId]
	if not record or not context.zoneAllowed(player,meta.networkId,record.zoneId) then return nil,"catalog_access_changed" end
	local registry=context.registry()
	local node=registry.nodes and registry.nodes[nodeId]
	local zone=node and registry.zones and registry.zones[node.zoneId]
	if not zone or zone.networkId~=meta.networkId or not Protocol.sameBlock(record,Snapshots.record(node)) then
		return nil,"node_revision"
	end
	if not record.confirmed then return nil,"node_unconfirmed" end
	-- Published snapshots are replaced, never mutated. The transport holds this
	-- one reference until ACK; newer commits cannot alter the encoded block.
	local delta = Snapshots.delta(node, baseRevision)
	local payload = {catalogNode=true,manifestSchema=Protocol.SCHEMA,replicaEpoch=meta.replicaEpoch,
		manifestToken=token,networkId=meta.networkId,catalogScope=meta.catalogScope,topologySequence=meta.topologySequence,
		inventoryRevision=state.revision,nodeRecord=record}
	if delta then
		payload.nodeDelta={baseRevision=delta.baseRevision,revision=delta.revision,
			changedRows=delta.changedRows,removedRowKeys=delta.removedRowKeys}
	else payload.nodeSnapshot=node.itemSnapshot end
	return payload
end

function Manifest.block(player,meta,nodeId,token,baseRevision)
	local valid,reason=authorized(player,meta)
	if not valid then Manifest.clear(player);return nil,reason or "catalog_access_changed" end
	return prepareBlock(player,meta,nodeId,token,baseRevision,sessions[player])
end
-- One synchronous authorization observation; every zone and node stays fenced.
function Manifest.blocks(player,meta,nodeIds,token)
	if type(nodeIds)~="table" or getmetatable(nodeIds)~=nil or #nodeIds<1 or #nodeIds>4 then return nil,"node_request" end
	local count,seen=0,{}
	for key,nodeId in pairs(nodeIds) do
		if type(key)~="number" or key%1~=0 or key<1 or key>#nodeIds or not Protocol.id(nodeId) or seen[nodeId] then return nil,"node_request" end
		count=count+1;seen[nodeId]=true
	end
	if count~=#nodeIds then return nil,"node_request" end
	local valid,reason=authorized(player,meta)
	if not valid then Manifest.clear(player);return nil,reason or "catalog_access_changed" end
	local payload,blocks=nil,{}
	for i=1,#nodeIds do
		local block,why=prepareBlock(player,meta,nodeIds[i],token,nil,sessions[player])
		if not block then return nil,why end
		payload=payload or block
		blocks[i]={nodeRecord=block.nodeRecord,nodeSnapshot=block.nodeSnapshot}
	end
	payload.nodeRecord=nil;payload.nodeSnapshot=nil;payload.nodeDelta=nil;payload.nodeBlocks=blocks
	return payload
end


function Manifest.oracleCurrent(player,meta,token)
	local accepted=authorized(player,meta)
	local state=sessions[player]
	return accepted and state and state.token==token and state.revision==meta.inventoryRevision
		and context.inventoryRevision(meta.networkId)==meta.inventoryRevision
end

function Manifest.oracleImage(player,meta,token)
	local state=sessions[player]
	if not state or state.token~=token or state.revision~=meta.inventoryRevision then return nil,"oracle_token" end
	local nodes={}
	for _,record in ipairs(state.records) do
		if record.enabled then
			local block,reason=Manifest.block(player,meta,record.nodeId,token)
			if not block then return nil,reason end
			nodes[#nodes+1]={record=record,snapshot=block.nodeSnapshot}
		end
	end
	return {meta=meta,nodes=nodes}
end
return Manifest

-- Manifests inspect confirmed metadata only. No ItemContainer or item traversal.
local Protocol = require "GS_ManifestProtocol"
local Snapshots = require "GS_NodeSnapshots"
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
	append(parts,network.topologyRevision);append(parts,network.routingRevision or 0)
	append(parts,context.inventoryRevision(meta.networkId))
	append(parts,context.classificationStamp());append(parts,meta.controlStamp or "")
	for i=1,#records do
		local record=records[i]
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
		local reservation=#signature*2+#records*1024+4096
		if reservation>8*1024*1024 then return nil,"manifest_budget" end
		if retainedBytes-(previous and previous.bytes or 0)+reservation>32*1024*1024 then
			return nil,"manifest_busy"
		end
		serial=serial+1
		previous={networkId=meta.networkId,epoch=meta.replicaEpoch,signature=signature,
			token=meta.replicaEpoch..":"..tostring(serial),records=records,byId={},bytes=reservation,
			revision=context.inventoryRevision(meta.networkId)}
		for i=1,#records do previous.byId[records[i].nodeId]=records[i] end
		Manifest.clear(player);retainedBytes=retainedBytes+reservation
		sessions[player]=previous
	end
	clock=clock+1;previous.usedAt=clock
	local result={manifestSchema=Protocol.SCHEMA,replicaEpoch=meta.replicaEpoch,
		manifestToken=previous.token,networkId=meta.networkId,catalogScope=meta.catalogScope,
		topologyRevision=network.topologyRevision,routingRevision=network.routingRevision or 0,
		classificationEpoch=context.classificationStamp(),contentWatermark=network.contentWatermark or 0,
		inventoryRevision=context.inventoryRevision(meta.networkId),catalogManifest=true}
	if knownToken==previous.token then result.manifestNotModified=true
	else result.nodeManifest=previous.records end
	return result
end

function Manifest.diagnostics() return {retainedBytes=retainedBytes,topologyBytes=topologyBytes,networks=topologyCount} end

function Manifest.block(player, meta, nodeId, token)
	local valid,reason=authorized(player,meta)
	if not valid then Manifest.clear(player);return nil,reason or "catalog_access_changed" end
	local state=sessions[player]
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
	return {catalogNode=true,manifestSchema=Protocol.SCHEMA,replicaEpoch=meta.replicaEpoch,
		manifestToken=token,networkId=meta.networkId,catalogScope=meta.catalogScope,
		inventoryRevision=state.revision,nodeRecord=record,nodeSnapshot=node.itemSnapshot}
end

return Manifest

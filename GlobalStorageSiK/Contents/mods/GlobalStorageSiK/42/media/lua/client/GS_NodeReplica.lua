-- Session cache with byte LRU. No age expiry and no revision-indexed copies.
local Protocol = require "GS_ManifestProtocol"
local Replica = {}
GlobalStorageSiK.NodeReplica = Replica

function Replica.new(options)
	options = options or {}
	local entries, bytes, clock = {}, 0, 0
	local maxBytes, maxEntries = options.maxBytes or 32*1024*1024, options.maxEntries or 16
	local api = {}
	local function touch(entry) clock=clock+1; entry.usedAt=clock end
	local function remove(key, reason)
		local entry=entries[key]
		if not entry then return end
		entries[key]=nil; bytes=math.max(0,bytes-entry.bytes)
		if options.evicted then options.evicted(entry,reason) end
	end
	local function reserve(amount, protected)
		if amount > maxBytes then return false end
		while true do
			local count, oldestKey, oldest = 0, nil, nil
			for key, entry in pairs(entries) do
				count=count+1
				if key~=protected and (not oldest or entry.usedAt<oldest) then oldestKey,oldest=key,entry.usedAt end
			end
			if bytes+amount<=maxBytes and count+(entries[protected] and 0 or 1)<=maxEntries then return true end
			if not oldestKey then return false end
			remove(oldestKey,"byte_lru")
		end
	end
	function api.identity(meta)
		if type(meta)~="table" or not Protocol.id(meta.replicaEpoch)
			or not Protocol.id(meta.networkId) or type(meta.catalogScope)~="string" or #meta.catalogScope>65536
			or not Protocol.integer(meta.playerNum,0,3) then return nil end
		return Protocol.key(meta.replicaEpoch,meta.playerNum,meta.networkId,meta.catalogScope)
	end
	function api.confirm(meta)
		local key=api.identity(meta)
		if not key then return nil,"manifest_identity" end
		local retired={}
		for cachedKey,entry in pairs(entries) do
			if entry.playerNum==meta.playerNum and (entry.epoch~=meta.replicaEpoch
				or (entry.networkId==meta.networkId and entry.scope~=meta.catalogScope)) then retired[#retired+1]=cachedKey end
		end
		for i=1,#retired do remove(retired[i],"scope_or_epoch_changed") end
		local entry=entries[key]
		if entry then touch(entry) end
		return entry,nil,key
	end
	function api.transition(meta)
		local key=api.identity(meta)
		if not key or not Protocol.scopeContains(meta.catalogScope,meta.previousCatalogScope) then return false,"manifest_identity" end
		local source
		for cachedKey,entry in pairs(entries) do
			if entry.playerNum==meta.playerNum and entry.networkId==meta.networkId and entry.epoch==meta.replicaEpoch
				and Protocol.scopeContains(entry.scope,meta.previousCatalogScope)
				and Protocol.scopeContains(meta.catalogScope,entry.scope) then source=cachedKey;break end
		end
		if source and source~=key then
			local entry=entries[source]
			if entries[key] then return false,"manifest_identity" end
			entries[source]=nil
			entry.derivedKey=entry.derivedKey or source
			entry.key,entry.scope=key,meta.catalogScope
			entries[key]=entry;touch(entry)
		end
		return true
	end
	function api.manifest(meta)
		local key=api.identity(meta)
		if not key or not Protocol.id(meta.manifestToken) or meta.manifestSchema~=Protocol.SCHEMA then
			return nil,"manifest_schema"
		end
		local records,byId=Protocol.records(meta.nodeManifest)
		if not records then return nil,"manifest_records" end
		local old,reason=api.confirm(meta)
		if reason then return nil,reason end
		local entry={key=key,epoch=meta.replicaEpoch,playerNum=meta.playerNum,networkId=meta.networkId,
			scope=meta.catalogScope,token=meta.manifestToken,records=records,byId=byId,blocks={},
			changedNodeIds={},bytes=4096+#records*1024}
		-- A draft never replaces the token or rows of the last accepted image.
		if old then
			entry.derivedKey=old.derivedKey
			for id in pairs(old.changedNodeIds or {}) do entry.changedNodeIds[id]=true end
			entry.confirmed=old.confirmed
			if entry.confirmed then
				local c=entry.confirmed
				entry.rows,entry.metadata,entry.rowStore=c.rows,c.metadata,c.rowStore
				entry.derivedGeneration,entry.viewBytes=c.derivedGeneration,c.viewBytes
				entry.viewCharge=c.viewBytes;entry.bytes=entry.bytes+c.viewBytes
			end
			for id in pairs(old.byId) do if not byId[id] then entry.changedNodeIds[id]=true end end
		end
		for i=1,#records do
			local record=records[i]
			local previous=old and old.byId[record.nodeId]
			if not Protocol.sameBlock(previous,record) or previous.enabled~=record.enabled then
				entry.changedNodeIds[record.nodeId]=true
			end
			local block=old and old.blocks[record.nodeId]
			if block and Protocol.sameBlock(block.record,record) then
				entry.blocks[record.nodeId]=block; entry.bytes=entry.bytes+block.bytes
			end
		end
		-- Reservations may evict unrelated networks, never the previous same-key image.
		if not reserve(entry.bytes-(old and old.bytes or 0),key) then return nil,"replica_budget" end
		bytes=bytes-(old and old.bytes or 0)+entry.bytes
		entries[key]=entry;touch(entry)
		return entry
	end
	function api.block(meta, retainedBytes)
		local key=api.identity(meta)
		local entry=key and entries[key]
		if not entry or entry.token~=meta.manifestToken then return false,"manifest_changed" end
		local record=Protocol.record(meta.nodeRecord)
		if not record or not record.confirmed or not Protocol.sameBlock(record,entry.byId[record.nodeId])
			or type(meta.nodeSnapshot)~="table" or getmetatable(meta.nodeSnapshot)~=nil then return false,"node_revision" end
		-- Caller supplies the verified codec reservation, not a field from the packet.
		if not Protocol.integer(retainedBytes,1,maxBytes) then return false,"replica_budget" end
		local old=entry.blocks[record.nodeId]
		if old and Protocol.sameBlock(old.record,record) then touch(entry);return true,"duplicate" end
		local delta=retainedBytes-(old and old.bytes or 0)
		if not reserve(delta,key) then return false,"replica_budget" end
		entry.blocks[record.nodeId]={record=record,snapshot=meta.nodeSnapshot,bytes=retainedBytes}
		entry.changedNodeIds[record.nodeId]=true
		entry.bytes=entry.bytes+delta;bytes=bytes+delta;touch(entry)
		return true
	end
	function api.missing(entry, limit)
		local missing={}
		if not entry or entries[entry.key]~=entry then return missing end
		limit=math.max(1,math.min(Protocol.MAX_REQUEST_NODES,tonumber(limit) or Protocol.MAX_REQUEST_NODES))
		for i=1,#entry.records do
			local record=entry.records[i]
			if record.enabled and record.confirmed and not entry.blocks[record.nodeId] then
				missing[#missing+1]=record
				if #missing>=limit then break end
			end
		end
		return missing
	end
	function api.registry(entry,partial,changedIds)
		if not entry or entries[entry.key]~=entry or not partial and #api.missing(entry,1)>0 then return nil end
		local registry={nodes={},zones={}}
		local function add(record)
			if not record then return end
			local block=entry.blocks[record.nodeId]
			registry.zones[record.zoneId]={id=record.zoneId,networkId=entry.networkId}
			if block then registry.nodes[record.nodeId]={id=record.nodeId,zoneId=record.zoneId,
				enabled=record.enabled,itemSnapshot=block.snapshot} end
		end
		if changedIds then
			for id in pairs(changedIds) do add(entry.byId[id]) end
		else for i=1,#entry.records do add(entry.records[i]) end end
		return registry
	end
	function api.stageView(entry,rows,metadata,retainedBytes,complete,rowStore,generation,viewToken)
		if not entry or entries[entry.key]~=entry or type(rows)~="table"
			or not Protocol.integer(retainedBytes,1,maxBytes) or entry.staged then return nil,"replica_budget" end
		local c=entry.confirmed
		local charge=retainedBytes
		if c then charge=c.rows==rows and math.max(c.viewBytes,retainedBytes) or c.viewBytes+retainedBytes end
		local extra=math.max(0,charge-(entry.viewCharge or 0))
		if not reserve(extra,entry.key) then return nil,"replica_budget" end
		local stage={token=entry.token,extra=extra}
		entry.staged=stage;entry.bytes=entry.bytes+extra;bytes=bytes+extra
		local function cancel()
			if entries[entry.key]~=entry or entry.staged~=stage then return false end
			entry.staged=nil;entry.bytes=entry.bytes-extra;bytes=bytes-extra;return true
		end
		local function commit()
			if entries[entry.key]~=entry or entry.staged~=stage or entry.token~=stage.token then return false end
			local finalCharge=retainedBytes+(complete==false and c and c.viewBytes or 0)
			local released=(entry.viewCharge or 0)+extra-finalCharge
			entry.bytes=entry.bytes-released;bytes=bytes-released
			entry.viewCharge=finalCharge;entry.staged=nil
			if complete~=false then
				entry.confirmed={token=viewToken or stage.token,rows=rows,metadata=metadata,rowStore=rowStore,
					derivedGeneration=generation,viewBytes=retainedBytes}
				entry.rows,entry.metadata,entry.rowStore=rows,metadata,rowStore
				entry.derivedGeneration,entry.viewBytes=generation,retainedBytes
				if not viewToken or viewToken==entry.token then entry.changedNodeIds={} end
			end
			touch(entry);return true
		end
		return commit,nil,cancel
	end
	function api.view(entry,rows,metadata,retainedBytes,complete)
		local commit,reason=api.stageView(entry,rows,metadata,retainedBytes,complete)
		return commit and commit() or false,reason
	end
	function api.get(meta)
		local key=api.identity(meta)
		local entry=key and entries[key]
		if entry then touch(entry) end
		return entry
	end
	function api.acceptView(entry)
		return entry~=nil and entries[entry.key]==entry
	end
	function api.clear(playerNum)
		local retired={}
		for key,entry in pairs(entries) do if playerNum==nil or entry.playerNum==playerNum then retired[#retired+1]=key end end
		for i=1,#retired do remove(retired[i],"revoked") end
	end
	function api.diagnostics()
		local count=0
		for _ in pairs(entries) do count=count+1 end
		return {bytes=bytes,entries=count,maxBytes=maxBytes,maxEntries=maxEntries}
	end
	return api
end

return Replica

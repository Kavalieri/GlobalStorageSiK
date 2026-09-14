-- Reconcile only dirty containers. Observation never schedules physical work.

require "GS_Network"
require "GS_Zones"
require "GS_Utils"
require "GS_ItemSnapshot"
require "GS_Index"
require "GS_NodeProbe"
require "GS_NodeSnapshots"

GlobalStorageSiK.CatalogReconciler = GlobalStorageSiK.CatalogReconciler or {}
local Reconciler = GlobalStorageSiK.CatalogReconciler

local MAX_TICK_UNITS = 32
local MAX_TICK_MS = 4
local MAX_NODES = 8192
local MAX_UNITS = 32768

local context = nil
local job = nil
local dirty, dirtyOrder = {}, {}

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function report(networkId, phase, stats)
	if context and context.status then context.status(networkId, phase, stats) end
end

local function eligible(registry, networkId, nodeId, expected)
	if not registry or not registry.networks or not registry.networks[networkId] then return nil end
	local node = registry.nodes and registry.nodes[nodeId] or nil
	if not node or (expected and node ~= expected) then return nil end
	local zone = registry.zones and registry.zones[node.zoneId] or nil
	if not zone or zone.networkId ~= networkId or zone.enabled == false then return nil end
	if node.enabled == false or node.membership == "excluded" then return nil end
	return node
end

local function resolveContainer(node)
	local object = GlobalStorageSiK.Network.findWorldObject(node)
	if not object then return nil end
	local container = GlobalStorageSiK.Utils.getObjectContainer(object, node.containerIndex)
	if not container or not GlobalStorageSiK.Utils.isNetworkStorageContainer(object, node.containerIndex) then
		return nil
	end
	local items = container.getItems and container:getItems() or nil
	if not items or not items.size or not items.get then return nil end
	return object, container, items
end

local function newComparison(a, b)
	return { stack = { { a = a, b = b, phase = 0 } }, seenA = {}, seenB = {}, equal = true }
end

local function compareOne(state)
	local frame = state.stack[#state.stack]
	if not frame then return true end
	if frame.phase == 0 then
		if frame.a==frame.b then state.stack[#state.stack]=nil;return true end
		local kind = type(frame.a)
		if kind ~= type(frame.b) then state.equal = false return true end
		if kind ~= "table" then
			if frame.a ~= frame.b then state.equal = false end
			state.stack[#state.stack] = nil
			return true
		end
		local mappedB, mappedA = state.seenA[frame.a], state.seenB[frame.b]
		if mappedB or mappedA then
			if mappedB ~= frame.b or mappedA ~= frame.a then state.equal = false end
			state.stack[#state.stack] = nil
			return true
		end
		state.seenA[frame.a], state.seenB[frame.b] = frame.b, frame.a
		frame.iter, frame.iterState, frame.key = pairs(frame.a)
		frame.phase = 1
		return true
	end
	if frame.phase == 1 then
		local key, value = frame.iter(frame.iterState, frame.key)
		frame.key = key
		if key ~= nil then
			local other = rawget(frame.b, key)
			if other == nil then state.equal = false return true end
			state.stack[#state.stack + 1] = { a = value, b = other, phase = 0 }
			return true
		end
		frame.iter, frame.iterState, frame.key = pairs(frame.b)
		frame.phase = 2
		return true
	end
	local key = frame.iter(frame.iterState, frame.key)
	frame.key = key
	if key ~= nil then
		if rawget(frame.a, key) == nil then state.equal = false end
		return true
	end
	state.stack[#state.stack] = nil
	return true
end

local function discardCapture(reason)
	local capture = job and job.capture or nil
	if capture then
		job.stats.discarded = job.stats.discarded + 1
		Reconciler.markDirty(capture.nodeId, reason)
		report(capture.networkId, reason, job.stats)
	end
	if job then job.capture = nil job.nodeIndex = job.nodeIndex + 1 end
end

local function beginCapture(candidate)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local node = eligible(registry, candidate.networkId, candidate.nodeId, candidate.node)
	if not node then return false end
	local object, container, items = resolveContainer(node)
	if not items then
		-- Preserve the existing persisted snapshot across a replication-schema
		-- upgrade. This is not a new physical confirmation of an unloaded node.
		if node.snapshotSchema~=GlobalStorageSiK.NodeSnapshots.SCHEMA and type(node.itemSnapshot)=="table" then
			GlobalStorageSiK.NodeSnapshots.commit(node,node.itemSnapshot,"legacy_replication_upgrade")
			node.snapshotAvailability="unloaded_or_missing"
			if context and context.changed then context.changed(candidate.networkId,candidate.nodeId) end
		else node.snapshotAvailability="unloaded_or_missing" end
		return false
	end
	local count = items:size()
	if count < 0 or count > MAX_UNITS then
		report(candidate.networkId, "failure_units_limit", { nodeId = candidate.nodeId, units = count, limit = MAX_UNITS })
		return false
	end
	job.capture = {
		networkId = candidate.networkId, nodeId = candidate.nodeId, node = node,
		oldSnapshot = node.itemSnapshot, revision = node.contentRevision,
		object = object, container = container, items = items, count = count,
		refs = {}, probes = {}, snapshot = {}, index = 0, phase = "capture",
	}
	return true
end

local function captureOne(capture)
	-- The Java list is live across ticks: withdrawal may shrink it meanwhile.
	if capture.items:size() ~= capture.count then
		discardCapture("capture_interference") return
	end
	if capture.index >= capture.count then
		capture.comparison = newComparison(capture.oldSnapshot or {}, capture.snapshot)
		capture.phase = "compare"
		return
	end
	local item = capture.items:get(capture.index)
	capture.refs[capture.index + 1] = item
	capture.probes[capture.index + 1] = GlobalStorageSiK.ItemSnapshot.probeItem(item)
	capture.index = capture.index + 1
	if item and item.getFullType then
		GlobalStorageSiK.ItemSnapshot.addItem(capture.snapshot, item, item:getFullType())
	end
	job.stats.units = job.stats.units + 1
end

local function compareStep(capture)
	-- Comparison fields are much cheaper than capturing an InventoryItem. Do
	-- not charge one whole item slot per primitive/table cursor transition.
	-- The same 4 ms wall budget still bounds the entire update.
	for i=1,128 do
		if not capture.comparison.equal or #capture.comparison.stack==0 then break end
		if nowMs()-job.tickStarted>=MAX_TICK_MS then break end
		compareOne(capture.comparison)
		job.stats.compared = job.stats.compared + 1
	end
	if not capture.comparison.equal then
		capture.equal = false
		capture.digest=GlobalStorageSiK.Index.beginSnapshotDigest(capture.snapshot)
		capture.phase, capture.index = "digest", 0
		return
	end
	if #capture.comparison.stack == 0 then
		capture.equal = true
		capture.phase, capture.index = "verify", 0
		if capture.node.snapshotSchema~=GlobalStorageSiK.NodeSnapshots.SCHEMA then
			capture.digest=GlobalStorageSiK.Index.beginSnapshotDigest(capture.snapshot);capture.phase="digest"
		end
	end
end

local function verifyOne(capture)
	if capture.index == 0 then
		local object, container, items = resolveContainer(capture.node)
		if object ~= capture.object or container ~= capture.container or not items or items:size() ~= capture.count then
			discardCapture("capture_interference") return
		end
		capture.items = items
	end
	if capture.items:size() ~= capture.count then
		discardCapture("capture_interference") return false
	end
	if capture.index < capture.count then
		if capture.items:get(capture.index) ~= capture.refs[capture.index + 1]
			or GlobalStorageSiK.ItemSnapshot.probeItem(capture.items:get(capture.index)) ~= capture.probes[capture.index + 1] then
			discardCapture("capture_interference") return false
		end
		capture.index = capture.index + 1
		job.stats.verified = job.stats.verified + 1
		return capture.index >= capture.count
	end
	return true
end

local function publish(capture)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local node = eligible(registry, capture.networkId, capture.nodeId, capture.node)
	if not node or node.itemSnapshot ~= capture.oldSnapshot
		or node.contentRevision ~= capture.revision then
		discardCapture("publish_interference") return
	end
	if not capture.equal or node.snapshotSchema ~= GlobalStorageSiK.NodeSnapshots.SCHEMA then
		GlobalStorageSiK.NodeSnapshots.commit(node, capture.snapshot, "dirty_reconcile", nil, capture.digest)
		job.stats.changed = job.stats.changed + 1
		if context and context.changed then context.changed(capture.networkId, capture.nodeId) end
	end
	job.stats.nodes = job.stats.nodes + 1
	job.capture = nil
	job.nodeIndex = job.nodeIndex + 1
end

function Reconciler.markDirty(nodeId, reason)
	if not nodeId or dirty[nodeId] then return end
	if #dirtyOrder >= MAX_NODES then report(nil, "dirty_queue_limit", { limit=MAX_NODES }); return end
	dirty[nodeId] = reason or "external_signal"
	dirtyOrder[#dirtyOrder + 1] = nodeId
end

function Reconciler.confirmed(nodeId, revision)
	-- Precise mutations replace only this node; a probe in progress notices its
	-- snapshot reference change. It cannot publish across this commit.
	local registry = GlobalStorageSiK.Network.getRegistry()
	local node = registry.nodes and registry.nodes[nodeId]
	if node then node.snapshotAvailability = "loaded" end
end

function Reconciler.configure(value)
	context = value; job = nil; dirty = {}; dirtyOrder = {}
	GlobalStorageSiK.NodeProbe.configure({ resolve=resolveContainer, dirty=Reconciler.markDirty,
		availability=function(node)
			local registry=GlobalStorageSiK.Network.getRegistry()
			local zone=registry.zones and registry.zones[node.zoneId]
			if zone and GlobalStorageSiK.notifyRegistryChanged then GlobalStorageSiK.notifyRegistryChanged(zone.networkId) end
		end })
end

local function takeDirty()
	local id = table.remove(dirtyOrder, 1)
	if not id then return end
	local reason = dirty[id]; dirty[id] = nil
	local registry = GlobalStorageSiK.Network.getRegistry()
	local node = registry.nodes and registry.nodes[id]
	local zone = node and registry.zones and registry.zones[node.zoneId]
	if not node or not zone then return end
	job = { nodeIndex=1, tickStarted=nowMs(), networkId=zone.networkId,
		stats={networks=1,nodeId=id,nodes=0,units=0,compared=0,verified=0,changed=0,discarded=0,reason=reason} }
	if not beginCapture({networkId=zone.networkId,nodeId=id,node=node}) then job=nil end
end

function Reconciler.update()
	GlobalStorageSiK.NodeProbe.update()
	local started = nowMs()
	for i = 1, MAX_TICK_UNITS do
		if nowMs()-started >= MAX_TICK_MS then break end
		if not job then takeDirty() end
		if not job then break end
		job.tickStarted=started
		local capture=job.capture
		if not capture then
			report(job.networkId, "node_complete", job.stats); job=nil
		elseif capture.phase == "capture" then captureOne(capture)
		elseif capture.phase == "compare" then compareStep(capture)
		elseif capture.phase == "digest" then
			if GlobalStorageSiK.Index.stepSnapshotDigest(capture.digest) then capture.phase,capture.index="verify",0 end
		elseif capture.phase == "verify" then
			if verifyOne(capture) and job and job.capture == capture then publish(capture) end
		end
	end
end

function Reconciler.diagnostics()
	return { active=job~=nil, phase=job and job.capture and job.capture.phase or "idle",
		dirtyNodes=#dirtyOrder, stats=job and job.stats,
		limits={nodes=MAX_NODES,units=MAX_UNITS,tickUnits=MAX_TICK_UNITS,tickMs=MAX_TICK_MS} }
end

return Reconciler

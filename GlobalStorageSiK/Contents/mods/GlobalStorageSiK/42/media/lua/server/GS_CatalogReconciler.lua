-- Background reconciliation for catalog snapshots while terminals observe a network.
-- The server wires watcher enumeration and change publication through configure().

require "GS_Network"
require "GS_Zones"
require "GS_Utils"
require "GS_ItemSnapshot"
require "GS_Index"

GlobalStorageSiK.CatalogReconciler = GlobalStorageSiK.CatalogReconciler or {}
local Reconciler = GlobalStorageSiK.CatalogReconciler

local CADENCE_MS = 1000
local MAX_TICK_UNITS = 32
local MAX_TICK_MS = 4
local MAX_NETWORKS = 256
local MAX_NODES = 8192
local MAX_UNITS = 32768

local context = nil
local job = nil
local nextCycleAt = 0

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function report(networkId, phase, stats)
	if context and context.status then context.status(networkId, phase, stats) end
end

local function activeNetworks()
	local list, set, overflow = {}, {}, false
	if not context or type(context.visitNetworks) ~= "function" then return list, set, overflow end
	context.visitNetworks(function(networkId)
		if networkId ~= nil and not set[networkId] then
			if #list >= MAX_NETWORKS then overflow = true return false end
			set[networkId] = true
			list[#list + 1] = networkId
		end
		return true
	end)
	return list, set, overflow
end

local function networkBusy(networkId)
	return (GlobalStorageSiK.ZoneScanJob and GlobalStorageSiK.ZoneScanJob.isActive
		and GlobalStorageSiK.ZoneScanJob.isActive(networkId))
		or (GlobalStorageSiK.RedistributeJob and GlobalStorageSiK.RedistributeJob.isActive
		and GlobalStorageSiK.RedistributeJob.isActive(networkId))
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

local function inventoryRevision(networkId)
	if GlobalStorageSiK.Index and GlobalStorageSiK.Index.getInventoryRevision then
		return GlobalStorageSiK.Index.getInventoryRevision(networkId)
	end
	return nil
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
		report(capture.networkId, reason, job.stats)
	end
	if job then job.capture = nil job.nodeIndex = job.nodeIndex + 1 end
end

local function beginCapture(candidate)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local node = eligible(registry, candidate.networkId, candidate.nodeId, candidate.node)
	if not node or networkBusy(candidate.networkId) then return false end
	local object, container, items = resolveContainer(node)
	if not items then return false end
	local count = items:size()
	if count < 0 or count > MAX_UNITS then
		report(candidate.networkId, "failure_units_limit", { nodeId = candidate.nodeId, units = count, limit = MAX_UNITS })
		return false
	end
	job.capture = {
		networkId = candidate.networkId, nodeId = candidate.nodeId, node = node,
		oldSnapshot = node.itemSnapshot, revision = inventoryRevision(candidate.networkId),
		object = object, container = container, items = items, count = count,
		refs = {}, snapshot = {}, index = 0, phase = "capture",
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
		capture.phase, capture.index = "verify", 0
		return
	end
	if #capture.comparison.stack == 0 then
		capture.equal = true
		capture.phase, capture.index = "verify", 0
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
		if capture.items:get(capture.index) ~= capture.refs[capture.index + 1] then
			discardCapture("capture_interference") return false
		end
		capture.index = capture.index + 1
		job.stats.verified = job.stats.verified + 1
		return capture.index >= capture.count
	end
	return true
end

local function publish(capture, activeSet)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local node = eligible(registry, capture.networkId, capture.nodeId, capture.node)
	if not activeSet[capture.networkId] or not node or networkBusy(capture.networkId)
		or node.itemSnapshot ~= capture.oldSnapshot
		or inventoryRevision(capture.networkId) ~= capture.revision then
		discardCapture("publish_interference") return
	end
	if not capture.equal then
		node.itemSnapshot = capture.snapshot
		job.stats.changed = job.stats.changed + 1
		if context and context.changed then context.changed(capture.networkId, capture.nodeId) end
	end
	job.stats.nodes = job.stats.nodes + 1
	job.capture = nil
	job.nodeIndex = job.nodeIndex + 1
end

local function collectOne()
	local key, node = job.nodeIter(job.nodeState, job.nodeKey)
	job.nodeKey = key
	if key == nil then job.phase = "nodes" return end
	local zone = job.registry.zones and node and job.registry.zones[node.zoneId] or nil
	local networkId = zone and zone.networkId or nil
	if networkId and job.networkSet[networkId] and eligible(job.registry, networkId, key, node) then
		if #job.nodes >= MAX_NODES then
			job.overflow = true
			job.phase = "abort"
			report(networkId, "failure_nodes_limit", { limit = MAX_NODES })
			return
		end
		job.nodes[#job.nodes + 1] = { networkId = networkId, nodeId = key, node = node }
	end
end

local function startCycle(networkList, networkSet)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local iter, iterState, iterKey = pairs(registry.nodes or {})
	job = {
		phase = "collect", registry = registry, networkList = networkList, networkSet = networkSet,
		nodeIter = iter, nodeState = iterState, nodeKey = iterKey, nodes = {}, nodeIndex = 1,
		lastProgress=nowMs(),
		stats = { networks = #networkList, nodes = 0, units = 0, compared = 0,
			verified = 0, changed = 0, discarded = 0 },
	}
end

local function finishCycle()
	local phase=job.overflow and "cycle_aborted" or "cycle_complete"
	for i = 1, #job.networkList do report(job.networkList[i], phase, job.stats) end
	job = nil
	nextCycleAt = nowMs() + CADENCE_MS
end

function Reconciler.configure(value)
	context = value
	job = nil
	nextCycleAt = 0
end

function Reconciler.update()
	local networkList, networkSet, overflow = activeNetworks()
	if #networkList == 0 then job = nil return end
	if overflow then
		job = nil
		nextCycleAt = nowMs() + CADENCE_MS
		report(nil, "failure_networks_limit", { limit = MAX_NETWORKS })
		return
	end
	if not job then
		if nowMs() < nextCycleAt then return end
		startCycle(networkList, networkSet)
		for i=1,#networkList do report(networkList[i],"cycle_start",job.stats) end
	else
		job.networkSet = networkSet
	end
	local started, work = nowMs(), 0
	job.tickStarted=started
	while job and work < MAX_TICK_UNITS do
		if nowMs() - started >= MAX_TICK_MS then break end
		if job.phase == "abort" then
			finishCycle()
		elseif job.phase == "collect" then
			collectOne()
		elseif job.nodeIndex > #job.nodes then
			finishCycle()
		elseif not job.capture then
			local candidate = job.nodes[job.nodeIndex]
			if not networkSet[candidate.networkId] or not beginCapture(candidate) then
				job.nodeIndex = job.nodeIndex + 1
			end
		else
			local capture = job.capture
			if not networkSet[capture.networkId] then discardCapture("watchers_closed")
			elseif capture.phase == "capture" then captureOne(capture)
			elseif capture.phase == "compare" then compareStep(capture)
			elseif capture.phase == "verify" then
				if verifyOne(capture) and job and job.capture == capture then publish(capture, networkSet) end
			else publish(capture, networkSet) end
		end
		work = work + 1
	end
	if job and nowMs()-job.lastProgress>=2000 then
		job.lastProgress=nowMs()
		job.stats.totalNodes=job.phase~="collect" and #job.nodes or nil
		job.stats.nodeIndex=job.nodeIndex
		job.stats.phase=job.capture and job.capture.phase or job.phase
		job.stats.remaining=job.phase~="collect" and math.max(0,#job.nodes-job.nodeIndex+1) or nil
		for i=1,#job.networkList do report(job.networkList[i],"cycle_progress",job.stats) end
	end
end

function Reconciler.diagnostics()
	return {
		active = job ~= nil,
		phase = job and (job.capture and job.capture.phase or job.phase) or "idle",
		nodeIndex = job and job.nodeIndex or 0,
		stats = job and job.stats or nil,
		limits = { networks = MAX_NETWORKS, nodes = MAX_NODES, units = MAX_UNITS,
			tickUnits = MAX_TICK_UNITS, tickMs = MAX_TICK_MS, cadenceMs = CADENCE_MS },
	}
end

return Reconciler

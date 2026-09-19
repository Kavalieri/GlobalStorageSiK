-- The confirmed container is the authoritative unit of inventory replication.
-- itemSnapshot remains the compatibility field consumed by public Core APIs.
require "GS_Config"
local Codec = require "GS_CatalogCodec"
GlobalStorageSiK.NodeSnapshots = {}
local Snapshots = GlobalStorageSiK.NodeSnapshots
Snapshots.SCHEMA = 1
local MAX_DELTAS_PER_NODE = 8
local MAX_DELTA_ROWS = 4096
local MAX_DELTA_BYTES = 1024 * 1024
local MAX_HISTORY_BYTES = 16 * 1024 * 1024
local MAX_HISTORY_ENTRIES = 1024
local histories, historyOrder, historyBytes = {}, {}, 0

local function removeDelta(history, delta)
	for i = 1, #history.deltas do
		if history.deltas[i] == delta then
			table.remove(history.deltas, i)
			history.bytes = math.max(0, history.bytes - delta.estimatedBytes)
			historyBytes = math.max(0, historyBytes - delta.estimatedBytes)
			return
		end
	end
end

local function trimHistory()
	while #historyOrder > MAX_HISTORY_ENTRIES or historyBytes > MAX_HISTORY_BYTES do
		local retired = table.remove(historyOrder, 1)
		if retired and retired.history then removeDelta(retired.history, retired.delta) end
	end
end

local function clearHistory(id)
	local history = histories[id]
	if not history then return end
	while #history.deltas > 0 do removeDelta(history, history.deltas[1]) end
	for i = #historyOrder, 1, -1 do
		if historyOrder[i].history == history then table.remove(historyOrder, i) end
	end
	histories[id] = nil
end

local function recordDelta(entry, previous, snapshot, baseRevision, revision, fullBytes)
	if not entry.id or type(snapshot) ~= "table" then return end
	if type(previous) ~= "table" then clearHistory(tostring(entry.id)); return end
	local changed, removed, changedCount, estimated = {}, {}, 0, 0
	for key, row in pairs(snapshot) do
		local old = previous[key]
		local signature = GlobalStorageSiK.Index.rowSignature(row)
		if not old or GlobalStorageSiK.Index.rowSignature(old) ~= signature then
			changed[key] = row
			changedCount = changedCount + 1
			estimated = estimated + #tostring(key) + #(signature or "") + 16
		end
	end
	for key in pairs(previous) do
		if snapshot[key] == nil then
			removed[#removed + 1] = key
			estimated = estimated + #tostring(key) + 8
		end
	end
	local rowCount = changedCount + #removed
	local id = tostring(entry.id)
	if rowCount == 0 or rowCount > MAX_DELTA_ROWS or estimated > MAX_DELTA_BYTES
		or estimated >= fullBytes then
		clearHistory(id)
		return
	end
	local fullWireBytes = Codec and Codec.size and Codec.size(snapshot) or fullBytes
	if type(fullWireBytes) ~= "number" then clearHistory(id); return end
	local history = histories[id]
	if not history or history.entry ~= entry then
		if history then clearHistory(id) end
		history = { entry = entry, deltas = {}, bytes = 0,
			fullBytes = fullBytes, fullWireBytes = fullWireBytes }
		histories[id] = history
	end
	local delta = { baseRevision = baseRevision, revision = revision,
		changedRows = changed, removedRowKeys = removed, estimatedBytes = estimated }
	history.deltas[#history.deltas + 1] = delta
	history.bytes = history.bytes + estimated
	history.fullBytes = fullBytes
	history.fullWireBytes = fullWireBytes
	historyBytes = historyBytes + estimated
	historyOrder[#historyOrder + 1] = { history = history, delta = delta }
	while #history.deltas > MAX_DELTAS_PER_NODE do removeDelta(history, history.deltas[1]) end
	trimHistory()
end

local function networkFor(entry)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local zone = registry.zones and registry.zones[entry.zoneId]
	return zone and registry.networks and registry.networks[zone.networkId], zone and zone.networkId
end

local function compactSignature(text)
	-- A summary/checksum, never a physical item selector or an access credential.
	local a, b = 1, 7
	for i = 1, #text do
		local byte = string.byte(text, i)
		a = (a * 31 + byte) % 2147483629
		b = (b * 33 + byte) % 2147483587
	end
	return tostring(#text) .. ":" .. tostring(a) .. ":" .. tostring(b)
end

function Snapshots.commit(entry, snapshot, reason, canonical, prepared)
	if not GlobalStorageSiK.isAuthoritative() or type(entry) ~= "table" or type(snapshot) ~= "table" then return false end
	if snapshot == entry.itemSnapshot and entry.snapshotSchema == Snapshots.SCHEMA then return true, false end
	if not prepared then canonical = canonical or GlobalStorageSiK.Index.snapshotSignature(snapshot) end
	local signature=prepared and prepared.signature or compactSignature(canonical)
	if entry.snapshotSchema==Snapshots.SCHEMA and signature==entry.snapshotSignature
		and type(entry.itemSnapshot)=="table" then
		-- Checksums are only a fast filter. Equality of canonical content prevents
		-- a collision from hiding an actual unit/ID/dynamic-state change.
		canonical=canonical or GlobalStorageSiK.Index.snapshotSignature(snapshot)
		if canonical==GlobalStorageSiK.Index.snapshotSignature(entry.itemSnapshot) then return true,false end
	end
	local units, weight, rows = 0, 0, 0
	if prepared then units,weight,rows=prepared.units,prepared.weight,prepared.rows
	else
		for _, row in pairs(snapshot) do
			units = units + (tonumber(row.count) or 0)
			weight = weight + (tonumber(row.totalWeight) or 0)
			rows = rows + 1
		end
	end
	local previous = entry.itemSnapshot
	local baseRevision = tonumber(entry.contentRevision) or 0
	entry.itemSnapshot = snapshot
	entry.contentRevision = baseRevision + 1
	entry.snapshotSchema = Snapshots.SCHEMA
	entry.snapshotSignature = signature
	entry.snapshotUnits, entry.snapshotRows, entry.snapshotWeight = units, rows, weight
	entry.snapshotConfirmedAt = getTimestampMs and getTimestampMs() or 0
	entry.snapshotReason = reason or "capture"
	recordDelta(entry, previous, snapshot, baseRevision, entry.contentRevision,
		math.max(1, #(canonical or "")))
	local network, networkId = networkFor(entry)
	if network then network.contentWatermark = (tonumber(network.contentWatermark) or 0) + 1 end
	if GlobalStorageSiK.CatalogReconciler and GlobalStorageSiK.CatalogReconciler.confirmed then
		GlobalStorageSiK.CatalogReconciler.confirmed(entry.id, entry.contentRevision)
	end
	return true, true, networkId
end

-- Compose a bounded contiguous history. Callers send the full immutable
-- snapshot whenever the client base is absent, retired or no longer cheaper.
function Snapshots.delta(entry, baseRevision)
	if type(entry) ~= "table" or not entry.id or type(baseRevision) ~= "number"
		or baseRevision ~= math.floor(baseRevision) then return nil end
	local history = histories[tostring(entry.id)]
	if not history or history.entry ~= entry or baseRevision >= (entry.contentRevision or 0) then return nil end
	local current, changed, removed, estimated = baseRevision, {}, {}, 0
	for i = 1, #history.deltas do
		local delta = history.deltas[i]
		if delta.baseRevision == current then
			for key, row in pairs(delta.changedRows) do changed[key], removed[key] = row, nil end
			for j = 1, #delta.removedRowKeys do
				local key = delta.removedRowKeys[j]
				changed[key], removed[key] = nil, true
			end
			current = delta.revision
			estimated = estimated + delta.estimatedBytes
			if current == entry.contentRevision then break end
		end
	end
	if current ~= entry.contentRevision or estimated >= (history.fullBytes or 0) then return nil end
	local removedKeys = {}
	for key in pairs(removed) do removedKeys[#removedKeys + 1] = key end
	table.sort(removedKeys, function(a, b) return tostring(a) < tostring(b) end)
	local wireBytes = Codec and Codec.size and Codec.size({
		changedRows = changed, removedRowKeys = removedKeys }) or estimated
	if type(wireBytes) ~= "number" or wireBytes >= (history.fullWireBytes or 0) then return nil end
	return { baseRevision = baseRevision, revision = current,
		changedRows = changed, removedRowKeys = removedKeys,
		estimatedBytes = estimated, wireBytes = wireBytes,
		fullWireBytes = history.fullWireBytes }
end

function Snapshots.deltaDiagnostics()
	return { retainedBytes = historyBytes, entries = #historyOrder,
		maxBytes = MAX_HISTORY_BYTES, maxEntries = MAX_HISTORY_ENTRIES }
end

-- The caller has already performed the physical mutation and captured its
-- exact node. Notify legacy revision consumers and observers without ModData
-- broadcasting or certifying unrelated stale snapshots.
function Snapshots.notifyMutation(player, networkId, updated, nodeId)
	if not GlobalStorageSiK.isAuthoritative() then return false end
	local server=GlobalStorageSiK.Server
	if server and server.markInventoryDirty then
		server.markInventoryDirty(networkId,player,{scheduleSnapshot=false,
			snapshotsUpdated=updated==true,touchedNodeIds=nodeId and {tostring(nodeId)} or {}})
		if server.notifyNodeMutation then server.notifyNodeMutation(player,networkId) end
	else
		GlobalStorageSiK.Index.bumpInventoryRevision(networkId,false)
		if updated~=true and nodeId and GlobalStorageSiK.CatalogReconciler then
			GlobalStorageSiK.CatalogReconciler.markDirty(nodeId,"directed_capture_failed")
		end
	end
	return true
end

function Snapshots.record(entry)
	return { nodeId = entry.id, zoneId = entry.zoneId,
		revision = tonumber(entry.contentRevision) or 0, signature = entry.snapshotSignature,
		schema = entry.snapshotSchema or 0, units = entry.snapshotUnits or 0,
		rows = entry.snapshotRows or 0, weight = entry.snapshotWeight or 0,
		availability = entry.snapshotAvailability or (entry.offline and "offline" or "unknown"),
		enabled = entry.enabled ~= false and entry.membership ~= "excluded",
		confirmed = type(entry.itemSnapshot) == "table" }
end

return Snapshots

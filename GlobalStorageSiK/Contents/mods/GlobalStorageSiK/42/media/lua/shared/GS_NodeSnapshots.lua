-- The confirmed container is the authoritative unit of inventory replication.
-- itemSnapshot remains the compatibility field consumed by public Core APIs.
require "GS_Config"
GlobalStorageSiK.NodeSnapshots = {}
local Snapshots = GlobalStorageSiK.NodeSnapshots
Snapshots.SCHEMA = 1

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
	local units, weight, rows = 0, 0, 0
	if prepared then units,weight,rows=prepared.units,prepared.weight,prepared.rows
	else
		for _, row in pairs(snapshot) do
			units = units + (tonumber(row.count) or 0)
			weight = weight + (tonumber(row.totalWeight) or 0)
			rows = rows + 1
		end
	end
	entry.itemSnapshot = snapshot
	entry.contentRevision = (tonumber(entry.contentRevision) or 0) + 1
	entry.snapshotSchema = Snapshots.SCHEMA
	entry.snapshotSignature = prepared and prepared.signature or compactSignature(canonical)
	entry.snapshotUnits, entry.snapshotRows, entry.snapshotWeight = units, rows, weight
	entry.snapshotConfirmedAt = getTimestampMs and getTimestampMs() or 0
	entry.snapshotReason = reason or "capture"
	local network, networkId = networkFor(entry)
	if network then network.contentWatermark = (tonumber(network.contentWatermark) or 0) + 1 end
	if GlobalStorageSiK.CatalogReconciler and GlobalStorageSiK.CatalogReconciler.confirmed then
		GlobalStorageSiK.CatalogReconciler.confirmed(entry.id, entry.contentRevision)
	end
	return true, true, networkId
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

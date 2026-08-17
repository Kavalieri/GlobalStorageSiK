--[[
	GlobalStorageSiK - Gestión de redes (listado, sesión activa, resumen MP)
	Autor: SiK
	Fecha: 2026-06-28
	Descripción: API servidor/cliente para menú de redes; sin escaneo de chunks.
]]

require "GS_Network"
require "GS_Permissions"
require "GS_Sandbox"
require "GS_TerminalRecord"
require "GS_Zones"

GlobalStorageSiK.NetworkManager = GlobalStorageSiK.NetworkManager or {}

local PLAYER_SESSION_KEY = "gsActiveNetworkId"

---@param networkId string
---@param net table|nil
---@return number
local function countZones(networkId)
	local n = 0
	if GlobalStorageSiK.Zones and GlobalStorageSiK.Zones.getRegistry then
		local reg = GlobalStorageSiK.Zones.getRegistry()
		for _, zone in pairs(reg.zones or {}) do
			if zone and zone.networkId == networkId then
				n = n + 1
			end
		end
	end
	return n
end

---@param networkId string
---@param net table|nil
---@return number
local function countNodes(networkId, net)
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local zoneIds = {}
	for zoneId, zone in pairs(registry.zones or {}) do
		if zone and zone.networkId == networkId then zoneIds[zoneId] = true end
	end
	local seen = {}
	local n = 0
	for nodeId, node in pairs(registry.nodes or {}) do
		if node and zoneIds[node.zoneId] then
			seen[nodeId] = true
			n = n + 1
		end
	end
	for i = 1, #(net and net.containers or {}) do
		local entry = net.containers[i]
		if entry and entry.id and not seen[entry.id] then
			seen[entry.id] = true
			n = n + 1
		end
	end
	return n
end

--- Resumen ligero de una red (payload MP).
---@param player IsoPlayer|nil
---@param networkId string
---@param net table|nil
---@return table|nil
function GlobalStorageSiK.NetworkManager.buildSummary(player, networkId, net)
	if not networkId or not net then
		return nil
	end
	if not GlobalStorageSiK.TerminalRegistry then
		require "GS_TerminalRegistry"
	end
	local anchor = GlobalStorageSiK.TerminalRecord.getPrimaryAnchor(net)
	local activeCount = GlobalStorageSiK.TerminalRecord.countActive(net)
	local suspendedCount = 0
	if net.terminals then
		for i = 1, #net.terminals do
			if net.terminals[i]
				and net.terminals[i].status == GlobalStorageSiK.TerminalRecord.STATUS_SUSPENDED then
				suspendedCount = suspendedCount + 1
			end
		end
	end
	local reloc = net.relocation
	local last = GlobalStorageSiK.TerminalRecord.getLastKnownLocation(net)
	return {
		networkId = networkId,
		name = net.name or "",
		owner = net.owner or "",
		isOwner = GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId),
		activeTerminals = activeCount,
		suspendedTerminals = suspendedCount,
		maxTerminals = GlobalStorageSiK.Sandbox.getMaxTerminalsPerNetwork(),
		zoneCount = countZones(networkId),
		nodeCount = countNodes(networkId, net),
		anchor = anchor and {
			x = anchor.x,
			y = anchor.y,
			z = anchor.z or 0,
		} or nil,
		relocationStatus = reloc and reloc.status or nil,
		hasActiveTerminal = activeCount > 0,
		status = activeCount > 0 and "active" or "suspended",
		lastLocation = last and { x = last.x, y = last.y, z = last.z or 0 } or nil,
		createdMs = net.createdMs or 0,
	}
end

--- Lista redes accesibles para el jugador (servidor).
---@param player IsoPlayer|nil
---@return table[]
function GlobalStorageSiK.NetworkManager.listForPlayer(player)
	if not player or not GlobalStorageSiK.Network then
		return {}
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local out = {}
	for networkId, net in pairs(registry.networks or {}) do
		local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(player, networkId))
		if allowed and net then
			local summary = GlobalStorageSiK.NetworkManager.buildSummary(player, networkId, net)
			if summary then
				local suffix = string.sub(networkId, -8)
				summary.label = (net.name and net.name ~= "" and (net.name .. " (" .. suffix .. ")"))
					or networkId
				out[#out + 1] = summary
			end
		end
	end
	table.sort(out, function(a, b)
		return (a.label or a.networkId) < (b.label or b.networkId)
	end)
	return out
end

---@param player IsoPlayer|nil
---@return string|nil
function GlobalStorageSiK.NetworkManager.getPlayerSessionNetwork(player)
	if not player or not player.getModData then
		return nil
	end
	local md = player:getModData()
	if md and md[PLAYER_SESSION_KEY] and md[PLAYER_SESSION_KEY] ~= "" then
		local resolved = GlobalStorageSiK.Network.resolveNetworkId(md[PLAYER_SESSION_KEY])
		if resolved then return resolved end
		-- Una red eliminada puede seguir en ModData de un personaje offline.
		-- Limpiarla al primer acceso evita sesiones fantasma permanentes.
		md[PLAYER_SESSION_KEY] = nil
	end
	return nil
end

--- Fija red activa del jugador (menú / apertura explícita).
---@param player IsoPlayer|nil
---@param networkId string|nil
---@return boolean ok
---@return string|nil reason
function GlobalStorageSiK.NetworkManager.setPlayerSessionNetwork(player, networkId)
	if not player or not player.getModData then
		return false, "no_player"
	end
	if networkId and networkId ~= "" then
		local resolved = GlobalStorageSiK.Network.resolveNetworkId(networkId)
		if not resolved then
			return false, "network_not_found"
		end
		local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(player, resolved))
		if not allowed then
			return false, "denied"
		end
		networkId = resolved
	end
	local md = player:getModData()
	md[PLAYER_SESSION_KEY] = networkId or nil
	if GlobalStorageSiK.Client then
		GlobalStorageSiK.Client.activeNetworkId = networkId
	end
	return true, nil
end

--- Crea red nueva (servidor) y opcionalmente la activa en sesión.
---@param player IsoPlayer|nil
---@param name string|nil
---@return string|nil networkId
---@return string|nil errorReason
function GlobalStorageSiK.NetworkManager.createNetworkForPlayer(player, name)
	local nid = GlobalStorageSiK.Network.createNetwork(player)
	if not nid then
		return nil, "create_failed"
	end
	if name and name ~= "" then
		local registry = GlobalStorageSiK.Network.getRegistry()
		local net = registry.networks[nid]
		if net then
			net.name = name
		end
	end
	GlobalStorageSiK.NetworkManager.setPlayerSessionNetwork(player, nid)
	return nid, nil
end

--- Elimina exclusivamente metadata de una red totalmente suspendida. No
--- busca objetos del mundo ni toca ItemContainer: los cofres y sus objetos
--- fisicos permanecen exactamente donde estaban.
---@param player IsoPlayer|nil
---@param networkId string
---@return boolean ok
---@return string reason
---@return table|nil summary
function GlobalStorageSiK.NetworkManager.deleteSuspendedNetwork(player, networkId)
	if not GlobalStorageSiK.isAuthoritative() then return false, "not_authoritative", nil end
	local resolved = GlobalStorageSiK.Network.resolveNetworkId(networkId)
	if not resolved then return false, "network_not_found", nil end
	if not GlobalStorageSiK.Permissions.isOwnerPlayer(player, resolved) then
		return false, "owner_only", nil
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local net = registry.networks[resolved]
	if not net then return false, "network_not_found", nil end
	if GlobalStorageSiK.TerminalRecord.countActive(net) > 0 then
		return false, "active_terminals", nil
	end
	if GlobalStorageSiK.RedistributeJob and GlobalStorageSiK.RedistributeJob.isActive(resolved) then
		return false, "network_busy", nil
	end
	if GlobalStorageSiK.ZoneScanJob and GlobalStorageSiK.ZoneScanJob.isActive(resolved) then
		return false, "network_busy", nil
	end
	local totalNodeCount = countNodes(resolved, net)

	local zoneIds = {}
	local zoneCount = 0
	for zoneId, zone in pairs(registry.zones or {}) do
		if zone and zone.networkId == resolved then
			zoneIds[#zoneIds + 1] = zoneId
			zoneCount = zoneCount + 1
		end
	end
	local zoneSet = {}
	for i = 1, #zoneIds do zoneSet[zoneIds[i]] = true end
	local nodeIds = {}
	for nodeId, node in pairs(registry.nodes or {}) do
		if node and zoneSet[node.zoneId] then nodeIds[#nodeIds + 1] = nodeId end
	end
	for i = 1, #nodeIds do registry.nodes[nodeIds[i]] = nil end
	for i = 1, #zoneIds do registry.zones[zoneIds[i]] = nil end

	local suspendedTerminals = #(net.terminals or {})
	registry.networks[resolved] = nil
	if registry.defaultNetworkId == resolved then registry.defaultNetworkId = nil end
	if registry._inventoryRevision then registry._inventoryRevision[resolved] = nil end
	if registry._snapshotRevision then registry._snapshotRevision[resolved] = nil end
	local aliasKeys = {}
	for alias, target in pairs(registry._legacyNetworkAliases or {}) do
		if target == resolved then aliasKeys[#aliasKeys + 1] = alias end
	end
	for i = 1, #aliasKeys do registry._legacyNetworkAliases[aliasKeys[i]] = nil end
	if not registry.defaultNetworkId then
		for remainingId in pairs(registry.networks or {}) do
			registry.defaultNetworkId = remainingId
			break
		end
	end
	if GlobalStorageSiK.RegistryStore and GlobalStorageSiK.RegistryStore.notifyChanged then
		GlobalStorageSiK.RegistryStore.notifyChanged()
	end
	return true, "deleted", {
		networkId = resolved,
		name = net.name or resolved,
		zones = zoneCount,
		nodes = totalNodeCount,
		suspendedTerminals = suspendedTerminals,
	}
end

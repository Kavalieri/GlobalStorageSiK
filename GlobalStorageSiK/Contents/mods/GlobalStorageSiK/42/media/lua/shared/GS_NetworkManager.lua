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
local function countZones(networkId, net)
	local n = 0
	if GlobalStorageSiK.Zones and GlobalStorageSiK.Zones.getRegistry then
		local reg = GlobalStorageSiK.Zones.getRegistry()
		for _, zone in pairs(reg.zones or {}) do
			if zone and zone.networkId == networkId then
				n = n + 1
			end
		end
	end
	if net and net.containers then
		n = n + #net.containers
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
	return {
		networkId = networkId,
		name = net.name or "",
		owner = net.owner or "",
		isOwner = GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId),
		activeTerminals = activeCount,
		suspendedTerminals = suspendedCount,
		maxTerminals = GlobalStorageSiK.Sandbox.getMaxTerminalsPerNetwork(),
		zoneCount = countZones(networkId, net),
		anchor = anchor and {
			x = anchor.x,
			y = anchor.y,
			z = anchor.z or 0,
		} or nil,
		relocationStatus = reloc and reloc.status or nil,
		hasActiveTerminal = activeCount > 0,
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
		return md[PLAYER_SESSION_KEY]
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

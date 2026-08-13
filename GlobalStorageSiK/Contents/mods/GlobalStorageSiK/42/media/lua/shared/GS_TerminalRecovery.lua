--[[
	GlobalStorageSiK - Redes accesibles y preparación de colocación
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Lista redes para el diálogo de colocación; intención new/link en servidor.
]]

require "GS_Network"
require "GS_Permissions"
require "GS_Sandbox"
require "GS_TerminalPlacementIntent"

GlobalStorageSiK.TerminalRecovery = {}

--- Etiqueta de red para UI.
---@param net table|nil
---@param networkId string
---@return string
local function networkLabel(net, networkId)
	if net and net.name and net.name ~= "" then
		return net.name .. " (" .. string.sub(networkId, -8) .. ")"
	end
	return networkId
end

--- Serializa redes a las que el jugador tiene acceso (servidor).
---@param player IsoPlayer|nil
---@return table[]
function GlobalStorageSiK.TerminalRecovery.buildNetworksForPlayer(player)
	if not player or not GlobalStorageSiK.Network then
		return {}
	end
	if not GlobalStorageSiK.TerminalRegistry then
		require "GS_TerminalRegistry"
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ() or 0)
	local out = {}
	for networkId, net in pairs(registry.networks or {}) do
		local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(player, networkId))
		if allowed and net then
			local anchor = GlobalStorageSiK.TerminalRegistry.getActiveAnchor(net)
			-- No tiene sentido poder vincularse a una red cuya cobertura no
			-- llega hasta donde estamos (ver GS_Sandbox.isWithinNetworkRange) -
			-- se filtra aqui para no ofrecer en el dialogo una red que el
			-- servidor va a rechazar de todos modos al instalar de verdad
			-- (ver handleInstallTerminalReader en GS_Server.lua, chequeo autoritativo).
			if not anchor or GlobalStorageSiK.Sandbox.isWithinNetworkRange(anchor, px, py, pz) then
				out[#out + 1] = {
					networkId = networkId,
					name = net.name or "",
					label = networkLabel(net, networkId),
					owner = net.owner or "",
					isOwner = GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId),
					terminalCount = GlobalStorageSiK.TerminalRegistry.countTerminals(net),
					maxTerminals = GlobalStorageSiK.Sandbox.getMaxTerminalsPerNetwork(),
					anchor = anchor and {
						x = anchor.x,
						y = anchor.y,
						z = anchor.z or 0,
					} or nil,
				}
			end
		end
	end
	table.sort(out, function(a, b)
		return (a.label or a.networkId) < (b.label or b.networkId)
	end)
	return out
end

--- Fusiona lista del servidor con manifiesto local (cliente).
---@param serverList table[]|nil
---@param manifest table|nil
---@return table[]
function GlobalStorageSiK.TerminalRecovery.mergeClientNetworkList(serverList, manifest)
	local byId = {}
	for i = 1, #(serverList or {}) do
		local row = serverList[i]
		if row and row.networkId then
			byId[row.networkId] = row
		end
	end
	for _, term in ipairs(manifest and manifest.terminals or {}) do
		if term.networkId and not byId[term.networkId] then
			byId[term.networkId] = {
				networkId = term.networkId,
				name = "",
				label = term.networkId,
				anchor = { x = term.x, y = term.y, z = term.z or 0 },
			}
		elseif term.networkId and byId[term.networkId] and not byId[term.networkId].anchor then
			byId[term.networkId].anchor = { x = term.x, y = term.y, z = term.z or 0 }
		end
	end
	local out = {}
	for _, row in pairs(byId) do
		out[#out + 1] = row
	end
	table.sort(out, function(a, b)
		return (a.label or a.networkId) < (b.label or b.networkId)
	end)
	return out
end

--- Resuelve networkId al colocar terminal (intención servidor o ModData del ítem).
---@param player IsoPlayer|nil
---@param itemNetworkId string|nil
---@return string|nil bindId nil = crear red nueva
---@return string mode new|link
function GlobalStorageSiK.TerminalRecovery.resolveNetworkIdForPlacement(player, itemNetworkId)
	if GlobalStorageSiK.TerminalPlacementIntent then
		local mode, nid = GlobalStorageSiK.TerminalPlacementIntent.resolveForRegister(player, itemNetworkId)
		if mode == GlobalStorageSiK.TerminalPlacementIntent.MODE_NEW then
			return nil, mode
		end
		if mode == GlobalStorageSiK.TerminalPlacementIntent.MODE_LINK and nid and nid ~= "" then
			local registry = GlobalStorageSiK.Network.getRegistry()
			if registry and registry.networks and registry.networks[nid] then
				return nid, mode
			end
		end
	end
	if itemNetworkId and itemNetworkId ~= "" then
		local registry = GlobalStorageSiK.Network.getRegistry()
		if registry and registry.networks and registry.networks[itemNetworkId] then
			return itemNetworkId, GlobalStorageSiK.TerminalPlacementIntent.MODE_LINK
		end
	end
	return nil, GlobalStorageSiK.TerminalPlacementIntent.MODE_NEW
end

--- Prepara colocación vinculada a red existente.
---@param player IsoPlayer|nil
---@param networkId string
---@return boolean ok
---@return string message
function GlobalStorageSiK.TerminalRecovery.prepareLinkPlacement(player, networkId)
	if not player or not networkId or networkId == "" then
		return false, "missing_network"
	end
	if not GlobalStorageSiK.TerminalRegistry then
		require "GS_TerminalRegistry"
	end
	local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(player, networkId))
	if not allowed then
		return false, "denied"
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local net = registry.networks[networkId]
	if not net then
		return false, "network_not_found"
	end
	local okCap, capReason = GlobalStorageSiK.TerminalRegistry.validateTerminalCapacity(net)
	if not okCap then
		return false, capReason or "terminal_limit"
	end
	if GlobalStorageSiK.TerminalPlacementIntent then
		GlobalStorageSiK.TerminalPlacementIntent.setIntent(player, {
			mode = GlobalStorageSiK.TerminalPlacementIntent.MODE_LINK,
			networkId = networkId,
			preparedAt = (getTimestampMs and getTimestampMs()) or 0,
		})
	end
	return true, "prepared"
end

--- Prepara colocación de terminal en red nueva.
---@param player IsoPlayer|nil
---@return boolean ok
---@return string message
function GlobalStorageSiK.TerminalRecovery.prepareNewNetworkPlacement(player)
	if not player then
		return false, "no_player"
	end
	if GlobalStorageSiK.TerminalPlacementIntent then
		GlobalStorageSiK.TerminalPlacementIntent.setIntent(player, {
			mode = GlobalStorageSiK.TerminalPlacementIntent.MODE_NEW,
			networkId = nil,
			preparedAt = (getTimestampMs and getTimestampMs()) or 0,
		})
	end
	return true, "prepared"
end

--- Prepara colocación según modo (servidor): solo new o link.
---@param player IsoPlayer|nil
---@param mode string new|link
---@param networkId string|nil
---@return boolean ok
---@return string message
function GlobalStorageSiK.TerminalRecovery.preparePlacement(player, mode, networkId)
	if mode == GlobalStorageSiK.TerminalPlacementIntent.MODE_NEW then
		return GlobalStorageSiK.TerminalRecovery.prepareNewNetworkPlacement(player)
	end
	if mode == GlobalStorageSiK.TerminalPlacementIntent.MODE_LINK then
		if not networkId or networkId == "" then
			return false, "missing_network"
		end
		return GlobalStorageSiK.TerminalRecovery.prepareLinkPlacement(player, networkId)
	end
	return false, "invalid_mode"
end

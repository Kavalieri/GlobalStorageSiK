--[[
	GlobalStorageSiK - Resolución de red para comandos MP (sin sesión pegajosa)
	Autor: SiK
	Fecha: 2026-06-28
	Descripción: openTerminal y registro priorizan terminal físico e intención explícita.
]]

require "GS_Network"
require "GS_Sandbox"
require "GS_TerminalRecord"

GlobalStorageSiK.NetworkResolve = GlobalStorageSiK.NetworkResolve or {}

--- Comandos que NO deben heredar networkId de la sesión/UI automáticamente.
GlobalStorageSiK.NetworkResolve.SESSION_EXEMPT = {
	openTerminal = true,
	prepareTerminalPlacement = true,
	registerTerminal = true,
	getNetworkList = true,
	getRecoveryNetworks = true,
	createNetwork = true,
	setActiveNetwork = true,
}

---@param command string|nil
---@return boolean
function GlobalStorageSiK.NetworkResolve.isSessionExempt(command)
	return command ~= nil and GlobalStorageSiK.NetworkResolve.SESSION_EXEMPT[command] == true
end

--- Resuelve networkId genérico para comandos de UI (post-apertura).
---@param player IsoPlayer|nil
---@param args table|nil
---@return string|nil
function GlobalStorageSiK.NetworkResolve.resolveCommandNetworkId(player, args)
	args = args or {}
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)

	if args.networkId and args._gsExplicitNetwork == true then
		return GlobalStorageSiK.Network.resolveNetworkId(args.networkId)
	end
	if args.networkId then
		local resolved = GlobalStorageSiK.Network.resolveNetworkId(args.networkId)
		if resolved then
			return resolved
		end
	end

	local hint = args.terminalHint
	if hint and hint.networkId and hint.networkId ~= "" then
		local resolved = GlobalStorageSiK.Network.resolveNetworkId(hint.networkId)
		if resolved then
			return resolved
		end
	end

	if GlobalStorageSiK.NetworkManager then
		local session = GlobalStorageSiK.NetworkManager.getPlayerSessionNetwork(player)
		if session and registry.networks[session] then
			return session
		end
	end

	if GlobalStorageSiK.TerminalAccess then
		local sessionNet = GlobalStorageSiK.TerminalAccess.getSessionNetworkId
			and GlobalStorageSiK.TerminalAccess.getSessionNetworkId(player)
		if sessionNet and registry.networks[sessionNet] then
			return sessionNet
		end
	end

	return GlobalStorageSiK.Network.getDefaultNetworkId()
end

--- Resuelve red al abrir terminal: físico > hint objeto > sesión explícita.
---@param player IsoPlayer|nil
---@param args table|nil
---@return string|nil networkId
---@return table|nil nearbyProbe
---@return string|nil blockReason
function GlobalStorageSiK.NetworkResolve.resolveOpenTerminal(player, args)
	args = args or {}
	if not player then
		return nil, nil, "no_player"
	end

	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local proxRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange()

	local hint = args.terminalHint
	if hint and hint.networkId and hint.networkId ~= "" then
		local resolved = GlobalStorageSiK.Network.resolveNetworkId(hint.networkId)
		if resolved then
			return resolved, hint, nil
		end
	end

	if hint and hint.x and hint.y and not hint.networkId then
		local at = GlobalStorageSiK.Network.findNetworkIdAtTerminal(hint.x, hint.y, hint.z or 0, {
			activeOnly = true,
		})
		if at then
			return at, hint, nil
		end
		return nil, hint, "terminal_unlinked"
	end

	if GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.probeNearbyTerminal then
		local nearby = GlobalStorageSiK.TerminalAccess.probeNearbyTerminal(player, proxRange, nil)
		if nearby and nearby.x then
			local nid = nearby.networkId
			if nid and nid ~= "" then
				local resolved = GlobalStorageSiK.Network.resolveNetworkId(nid)
				if resolved then
					return resolved, nearby, nil
				end
			end
			local at = GlobalStorageSiK.Network.findNetworkIdAtTerminal(nearby.x, nearby.y, nearby.z or 0, {
				activeOnly = true,
			})
			if at then
				return at, nearby, nil
			end
			return nil, nearby, "terminal_unlinked"
		end
	end

	if args.networkId and args._gsExplicitNetwork == true then
		local resolved = GlobalStorageSiK.Network.resolveNetworkId(args.networkId)
		if resolved then
			return resolved, nil, nil
		end
	end

	if GlobalStorageSiK.NetworkManager then
		local session = GlobalStorageSiK.NetworkManager.getPlayerSessionNetwork(player)
		if session and registry.networks[session] then
			local anchor = GlobalStorageSiK.TerminalRecord.getPrimaryAnchor(registry.networks[session])
			if anchor then
				return session, anchor, nil
			end
		end
	end

	local defaultId = GlobalStorageSiK.Network.getDefaultNetworkId()
	if defaultId and registry.networks[defaultId] then
		local anchor = GlobalStorageSiK.TerminalRecord.getPrimaryAnchor(registry.networks[defaultId])
		if anchor then
			return defaultId, anchor, nil
		end
	end

	return nil, nil, "no_terminal"
end

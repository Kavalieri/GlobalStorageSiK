--[[
	GlobalStorageSiK - Comandos cliente → servidor
	Autor: SiK
	Fecha: 2025-06-24
]]

require "GS_Config"
require "GS_Debug"
require "GS_NetTrace"
require "GS_NetworkResolve"
require "GS_FloorTargets"

GlobalStorageSiK.NetClient = GlobalStorageSiK.NetClient or {}
local floorSequences = {}

--- Obtiene el jugador local en cliente MP/SP.
---@return IsoPlayer|nil
function GlobalStorageSiK.NetClient.getPlayer(playerArg)
	if playerArg and type(playerArg) ~= "number" and playerArg.getUsername then
		return playerArg
	end
	if getSpecificPlayer then
		local player = getSpecificPlayer(tonumber(playerArg) or 0)
		if player then
			return player
		end
	end
	if getPlayer then
		return getPlayer()
	end
	return nil
end

--- Envía un comando al módulo servidor del mod (B42: requiere IsoPlayer).
---@param command string
---@param args table|nil
---@param playerArg IsoPlayer|number|nil
---@return boolean
function GlobalStorageSiK.NetClient.sendCommand(command, args, playerArg)
	if not command then
		return false
	end
	-- BUG CRITICO corregido: "not isClient()" abortaba TODO comando en
	-- singleplayer real, donde isClient() da false (ver
	-- GlobalStorageSiK.isAuthoritative en GS_Config.lua) - ningun comando
	-- llegaba nunca a sendClientCommand en SP, por eso "Instalar aqui",
	-- crear zonas, enviar items a la red, etc. no hacian nada en partidas de
	-- un jugador. sendClientCommand SI funciona en SP real (cliente y
	-- "servidor" comparten el mismo proceso) - lo unico que de verdad hay
	-- que evitar es un servidor DEDICADO puro (sin cliente local) enviandose
	-- un comando de cliente a si mismo, cosa que no tiene sentido ahi.
	if type(isServer) == "function" and isServer() and type(isClient) == "function" and not isClient() then
		return false
	end
	local player = GlobalStorageSiK.NetClient.getPlayer(playerArg)
	if not player then
		return false
	end
	args = args or {}
	if command == "closeTerminal" and args.closeSeq == nil then
		local client = GlobalStorageSiK.Client
		local sequences = client and client.terminalOpenSeqByPlayer
		args.closeSeq = sequences and sequences[player:getPlayerNum()] or nil
	end
	local accessGuard = GlobalStorageSiK.TerminalAccessGuard
	if accessGuard and accessGuard.isTransitioning and accessGuard.isTransitioning(player) then
		-- A provisional revocation blocks new network work, never cleanup of
		-- an already accepted operation or the request needed to confirm access.
		local cleanup = command == "closeTerminal" or command == "pingTerminalAccess"
			or command == "cancelWithdrawSelection"
			or (command == "depositItems" and (args.origin == "operation_abort_return"
				or args.origin == "operation_complete_return" or args.origin == "operation_result_deposit"))
		local independent = GlobalStorageSiK.NetworkResolve
			and GlobalStorageSiK.NetworkResolve.isSessionExempt(command)
		if not cleanup and not independent and string.sub(command, 1, 3) ~= "get" then
			if GlobalStorageSiK.UIFeedback and GlobalStorageSiK.I18n then
				GlobalStorageSiK.UIFeedback.halo(player,
					GlobalStorageSiK.I18n.text("IGUI_GS_AccessUnconfirmed"), nil, nil, nil, nil,
					{tone="warning", channel="terminal-access", dedupeKey="access-unconfirmed"})
			end
			return false
		end
	end
	if GlobalStorageSiK.NetTrace and GlobalStorageSiK.NetTrace.logClientSend then
		GlobalStorageSiK.NetTrace.logClientSend(command, args)
	end
	local exempt = GlobalStorageSiK.NetworkResolve
		and GlobalStorageSiK.NetworkResolve.isSessionExempt(command)
	if not exempt and not args.networkId then
		local playerNum = player.getPlayerNum and player:getPlayerNum() or 0
		local ui = nil
		if GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.getInstanceForPlayer then
			ui = GlobalStorageSiK.TerminalUI.getInstanceForPlayer(playerNum)
		elseif GlobalStorageSiK.TerminalUI then
			ui = GlobalStorageSiK.TerminalUI.instance
		end
		if ui and ui.terminalState and ui.terminalState.networkId then
			args.networkId = ui.terminalState.networkId
		elseif GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkIdByPlayer
			and GlobalStorageSiK.Client.activeNetworkIdByPlayer[playerNum] then
			args.networkId = GlobalStorageSiK.Client.activeNetworkIdByPlayer[playerNum]
		elseif playerNum == 0 and GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId then
			args.networkId = GlobalStorageSiK.Client.activeNetworkId
		end
	end
	if (command == "withdrawItem" and GlobalStorageSiK.FloorTargets.isKey(args.targetKey))
		or (command == "depositItems" and GlobalStorageSiK.FloorTargets.isKey(args.sourceKey)) then
		-- Shared by every local queue; assign only when actually sending. A
		-- failed/uncertain send consumes its number and must not be replayed.
		local playerNum = player:getPlayerNum()
		floorSequences[playerNum] = (floorSequences[playerNum] or 0) % 2147483647 + 1
		args.floorSeq = floorSequences[playerNum]
	end
	local ok, err = pcall(sendClientCommand, player, GlobalStorageSiK.MOD_ID, command, args)
	if not ok then
		GlobalStorageSiK.Log.error("NetClient", "sendClientCommand failed", err)
		return false
	end
	return true
end

--- Envía comando con networkId explícito (menú de redes).
---@param command string
---@param networkId string|nil
---@param args table|nil
---@param playerArg IsoPlayer|number|nil
---@return boolean
function GlobalStorageSiK.NetClient.sendNetworkCommand(command, networkId, args, playerArg)
	args = args or {}
	args.networkId = networkId
	args._gsExplicitNetwork = true
	return GlobalStorageSiK.NetClient.sendCommand(command, args, playerArg)
end

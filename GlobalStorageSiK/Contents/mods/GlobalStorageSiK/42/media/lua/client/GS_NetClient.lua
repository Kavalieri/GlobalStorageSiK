--[[
	GlobalStorageSiK - Comandos cliente → servidor
	Autor: SiK
	Fecha: 2025-06-24
]]

require "GS_Config"
require "GS_Debug"
require "GS_NetTrace"
require "GS_NetworkResolve"

GlobalStorageSiK.NetClient = GlobalStorageSiK.NetClient or {}

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

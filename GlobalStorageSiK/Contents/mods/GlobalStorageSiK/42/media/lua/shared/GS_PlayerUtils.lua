--[[
	GlobalStorageSiK - Utilidades de jugador (cliente / menús)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Resuelve IsoPlayer desde índice B42 y comprueba estado.
]]

GlobalStorageSiK.PlayerUtils = {}

--- Convierte índice de jugador o referencia en IsoPlayer.
---@param playerArg number|IsoPlayer|nil
---@return IsoPlayer|nil
function GlobalStorageSiK.PlayerUtils.resolve(playerArg)
	if playerArg == nil then
		if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer then
			return GlobalStorageSiK.NetClient.getPlayer()
		end
		if getPlayer then
			return getPlayer()
		end
		return nil
	end
	if type(playerArg) == "number" and getSpecificPlayer then
		return getSpecificPlayer(playerArg)
	end
	return playerArg
end

--- Busca un IsoPlayer online por nombre de cuenta, iterando jugadores
--- conectados (servidor dedicado o anfitrión) en vez de depender de
--- getPlayerFromUsername, que en pruebas devolvia nil de forma poco fiable
--- incluso con el jugador claramente conectado (ver GS_RedistributeJob.lua).
---@param username string|nil
---@return IsoPlayer|nil
function GlobalStorageSiK.PlayerUtils.resolveByUsername(username)
	if not username or username == "" then
		return nil
	end
	if getOnlinePlayers then
		local ok, list = pcall(getOnlinePlayers)
		if ok and list and list.size then
			for i = 0, list:size() - 1 do
				local p = list:get(i)
				if p and p.getUsername and p:getUsername() == username then
					return p
				end
			end
		end
	end
	if getNumActivePlayers and getSpecificPlayer then
		local ok, n = pcall(getNumActivePlayers)
		if ok and n then
			for i = 0, n - 1 do
				local p = getSpecificPlayer(i)
				if p and p.getUsername and p:getUsername() == username then
					return p
				end
			end
		end
	end
	if getPlayerFromUsername then
		local ok, player = pcall(getPlayerFromUsername, username)
		if ok and player then
			return player
		end
	end
	return nil
end

--- Indica si el jugador no está disponible para interacción.
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.PlayerUtils.isUnavailable(player)
	if not player then
		return true
	end
	if player.isDead and player:isDead() then
		return true
	end
	return false
end

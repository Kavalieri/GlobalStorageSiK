--[[
	GlobalStorageSiK - Intención de colocación de terminal (fuente única)
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Modo new/link autorizado por servidor antes de colocar terminal.
]]

require "GS_Config"
require "GS_Permissions"

GlobalStorageSiK.TerminalPlacementIntent = GlobalStorageSiK.TerminalPlacementIntent or {}

GlobalStorageSiK.TerminalPlacementIntent.MODE_NEW = "new"
GlobalStorageSiK.TerminalPlacementIntent.MODE_LINK = "link"
GlobalStorageSiK.TerminalPlacementIntent.MODDATA_KEY = "gsPlacementIntent"
GlobalStorageSiK.TerminalPlacementIntent.TTL_MS = 600000

GlobalStorageSiK.TerminalPlacementIntent._serverIntents = GlobalStorageSiK.TerminalPlacementIntent._serverIntents or {}

--- Clave estable del jugador.
---@param player IsoPlayer|nil
---@return string|nil
function GlobalStorageSiK.TerminalPlacementIntent.playerKey(player)
	if not player then
		return nil
	end
	if player.getUsername then
		return player:getUsername()
	end
	return tostring(player)
end

--- True si la intención persistida sigue vigente.
---@param intent table|nil
---@return boolean
function GlobalStorageSiK.TerminalPlacementIntent.isIntentValid(intent)
	if not intent or not intent.mode then
		return false
	end
	local preparedAt = tonumber(intent.preparedAt) or 0
	if preparedAt <= 0 then
		return true
	end
	local now = (getTimestampMs and getTimestampMs()) or 0
	return (now - preparedAt) <= GlobalStorageSiK.TerminalPlacementIntent.TTL_MS
end

--- Lee intención del ModData del jugador (servidor).
---@param player IsoPlayer|nil
---@return table|nil
function GlobalStorageSiK.TerminalPlacementIntent.readPlayerIntent(player)
	if not player or not player.getModData then
		return nil
	end
	local md = player:getModData()
	local intent = md and md[GlobalStorageSiK.TerminalPlacementIntent.MODDATA_KEY]
	if GlobalStorageSiK.TerminalPlacementIntent.isIntentValid(intent) then
		return intent
	end
	if md and md[GlobalStorageSiK.TerminalPlacementIntent.MODDATA_KEY] then
		md[GlobalStorageSiK.TerminalPlacementIntent.MODDATA_KEY] = nil
		if player.transmitModData then
			player:transmitModData()
		end
	end
	return nil
end

--- Persiste intención en RAM + ModData del jugador (servidor).
---@param player IsoPlayer|nil
---@param intent table|nil
function GlobalStorageSiK.TerminalPlacementIntent.writePlayerIntent(player, intent)
	if not player or not player.getModData then
		return
	end
	local md = player:getModData()
	if not md then
		return
	end
	md[GlobalStorageSiK.TerminalPlacementIntent.MODDATA_KEY] = intent
	if player.transmitModData then
		player:transmitModData()
	end
end

--- Lee intención activa (servidor o cliente local).
---@param player IsoPlayer|nil
---@return table|nil { mode, networkId, preparedAt }
function GlobalStorageSiK.TerminalPlacementIntent.getIntent(player)
	local key = GlobalStorageSiK.TerminalPlacementIntent.playerKey(player)
	if not key then
		return nil
	end
	-- isAuthoritative(), no isServer() a pelo: en SP real isServer() da false
	-- y esta rama nunca corria, perdiendo la intencion "red nueva/existente"
	-- elegida antes de colocar el terminal (ver GS_Config.isAuthoritative).
	if GlobalStorageSiK.isAuthoritative() then
		local ram = GlobalStorageSiK.TerminalPlacementIntent._serverIntents[key]
		if GlobalStorageSiK.TerminalPlacementIntent.isIntentValid(ram) then
			return ram
		end
		return GlobalStorageSiK.TerminalPlacementIntent.readPlayerIntent(player)
	end
	if GlobalStorageSiK.Client and GlobalStorageSiK.Client.placementIntent then
		local intent = GlobalStorageSiK.Client.placementIntent
		if GlobalStorageSiK.TerminalPlacementIntent.isIntentValid(intent) then
			return intent
		end
	end
	return nil
end

--- Persiste intención en servidor y espejo cliente.
---@param player IsoPlayer|nil
---@param intent table|nil
function GlobalStorageSiK.TerminalPlacementIntent.setIntent(player, intent)
	local key = GlobalStorageSiK.TerminalPlacementIntent.playerKey(player)
	if not key then
		return
	end
	if intent and not intent.preparedAt then
		intent.preparedAt = (getTimestampMs and getTimestampMs()) or 0
	end
	-- isAuthoritative(), no isServer() a pelo: en SP real isServer() da false
	-- y esta rama nunca corria, perdiendo la intencion "red nueva/existente"
	-- elegida antes de colocar el terminal (ver GS_Config.isAuthoritative).
	if GlobalStorageSiK.isAuthoritative() then
		if intent then
			GlobalStorageSiK.TerminalPlacementIntent._serverIntents[key] = intent
			GlobalStorageSiK.TerminalPlacementIntent.writePlayerIntent(player, intent)
		else
			GlobalStorageSiK.TerminalPlacementIntent._serverIntents[key] = nil
			GlobalStorageSiK.TerminalPlacementIntent.writePlayerIntent(player, nil)
		end
	end
	if isClient and isClient() then
		if not GlobalStorageSiK.Client then
			GlobalStorageSiK.Client = {}
		end
		GlobalStorageSiK.Client.placementIntent = intent
	end
end

--- Limpia intención tras colocar o cancelar.
---@param player IsoPlayer|nil
---@return table|nil intent consumida
function GlobalStorageSiK.TerminalPlacementIntent.consumeIntent(player)
	local intent = GlobalStorageSiK.TerminalPlacementIntent.getIntent(player)
	GlobalStorageSiK.TerminalPlacementIntent.setIntent(player, nil)
	return intent
end

--- Resuelve modo efectivo para registerTerminal.
---@param player IsoPlayer|nil
---@param networkId string|nil
---@return string mode new|link
---@return string|nil networkId
function GlobalStorageSiK.TerminalPlacementIntent.resolveForRegister(player, networkId)
	local intent = GlobalStorageSiK.TerminalPlacementIntent.getIntent(player)
	if intent and intent.mode == GlobalStorageSiK.TerminalPlacementIntent.MODE_NEW then
		return GlobalStorageSiK.TerminalPlacementIntent.MODE_NEW, nil
	end
	if intent and intent.mode == GlobalStorageSiK.TerminalPlacementIntent.MODE_LINK then
		return GlobalStorageSiK.TerminalPlacementIntent.MODE_LINK, intent.networkId or networkId
	end
	if networkId and networkId ~= "" then
		return GlobalStorageSiK.TerminalPlacementIntent.MODE_LINK, networkId
	end
	return GlobalStorageSiK.TerminalPlacementIntent.MODE_NEW, nil
end

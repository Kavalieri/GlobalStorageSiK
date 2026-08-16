--[[
	GlobalStorageSiK - Bloqueo de transferencias por red (servidor MP)
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Serializa depósitos/retiros en la misma red para evitar condiciones de carrera.
]]

GlobalStorageSiK.TransferLock = {}

local LOCK_TIMEOUT_MS = 8000
local _locks = {}

---@param networkId string|nil
---@return string
local function lockKey(networkId)
	if not networkId or networkId == "" then
		return "_default"
	end
	return networkId
end

---@param player IsoPlayer|nil
---@return string|nil
local function playerKey(player)
	if not player or not player.getUsername then
		return nil
	end
	return player:getUsername()
end

--- Intenta adquirir el bloqueo de transferencia de una red.
---@param networkId string|nil
---@param player IsoPlayer|nil
---@param op string|nil
---@return boolean acquired
---@return string|nil reason
function GlobalStorageSiK.TransferLock.acquire(networkId, player, op)
	if not isServer or not isServer() then
		return true, nil
	end
	local user = playerKey(player)
	if not user then
		return false, "no_player"
	end
	local key = lockKey(networkId)
	local now = getTimestampMs and getTimestampMs() or 0
	local lock = _locks[key]
	if lock then
		if lock.owner == user then
			lock.since = now
			lock.op = op or lock.op
			return true, nil
		end
		if now - (lock.since or 0) > LOCK_TIMEOUT_MS then
			_locks[key] = nil
		else
			return false, "network_busy"
		end
	end
	_locks[key] = {
		owner = user,
		since = now,
		op = op or "transfer",
	}
	return true, nil
end

--- Libera el bloqueo de transferencia si pertenece al jugador.
---@param networkId string|nil
---@param player IsoPlayer|nil
function GlobalStorageSiK.TransferLock.release(networkId, player)
	if not isServer or not isServer() then
		return
	end
	local user = playerKey(player)
	if not user then
		return
	end
	local key = lockKey(networkId)
	local lock = _locks[key]
	if lock and lock.owner == user then
		_locks[key] = nil
	end
end

--- Ejecuta una operación con bloqueo de red (solo servidor).
---@param networkId string|nil
---@param player IsoPlayer|nil
---@param op string|nil
---@param fn function
---@return boolean ok
---@return any ...
function GlobalStorageSiK.TransferLock.withNetworkLock(networkId, player, op, fn)
	if not fn then
		return false, "invalid"
	end
	local acquired, reason = GlobalStorageSiK.TransferLock.acquire(networkId, player, op)
	if not acquired then
		return false, reason
	end
	local results = { pcall(fn) }
	local callOk = results[1]
	GlobalStorageSiK.TransferLock.release(networkId, player)
	if not callOk then
		error(results[2])
	end
	return unpack(results, 2)
end

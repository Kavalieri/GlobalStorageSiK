--[[
	GlobalStorageSiK - Identificadores únicos de red
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: Genera IDs estables (gsn_*) que nunca se reutilizan ni renombran.
]]

require "GS_Network"

GlobalStorageSiK.NetworkId = {}

--- Genera un ID único de red (no colisiona con legacy "main").
---@param registry table|nil
---@return string
function GlobalStorageSiK.NetworkId.generate(registry)
	registry = registry or GlobalStorageSiK.Network.getRegistry()
	registry._nextNetworkSeq = (registry._nextNetworkSeq or 0) + 1
	local seq = registry._nextNetworkSeq
	local t = (getTimestampMs and getTimestampMs()) or (os.time() * 1000) or 0
	local rnd = (ZombRand and ZombRand(0, 65535)) or math.random(0, 65535)
	return string.format("gsn_%x_%04x_%04x", t % 0xFFFFFF, seq % 0xFFFF, rnd % 0xFFFF)
end

--- Comprueba si un string es un ID de red válido del mod.
---@param id string|nil
---@return boolean
function GlobalStorageSiK.NetworkId.isValid(id)
	if not id or id == "" then
		return false
	end
	if id == "main" then
		return true
	end
	return id:match("^gsn_[0-9a-f]+_[0-9a-f]+_[0-9a-f]+$") ~= nil
end

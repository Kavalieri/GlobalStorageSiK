--[[
	GlobalStorageSiK - Registro debug (sandbox)
	Autor: SiK
	Fecha: 2025-06-24
]]

require "GS_Sandbox"
require "GS_Log"

GlobalStorageSiK.Debug = GlobalStorageSiK.Debug or {}

--- Indica si el modo debug está activo.
---@return boolean
function GlobalStorageSiK.Debug.isEnabled()
	return GlobalStorageSiK.Sandbox.debugMode()
end

--- Escribe en consola si DebugMode está activo.
---@param area string
---@param message string
---@param detail any|nil
function GlobalStorageSiK.Debug.log(area, message, detail)
	if not GlobalStorageSiK.Debug.isEnabled() then
		return
	end
	if GlobalStorageSiK.Log and GlobalStorageSiK.Log.debug then
		GlobalStorageSiK.Log.debug(area, message, detail)
	end
end

--- Halo azul de diagnóstico en cliente (solo debug).
---@param player IsoPlayer|nil
---@param message string
function GlobalStorageSiK.Debug.halo(player, message)
	if not GlobalStorageSiK.Debug.isEnabled() or not player or not message then
		return
	end
	player:setHaloNote("[GS DBG] " .. tostring(message), 120, 200, 255, 350)
end

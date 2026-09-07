--[[
	GSSiK Addon Tablet - Registro visible (consola)
	Autor: SiK
	Descripcion: Mismo patron que GS_Log.lua/SCLG_Log.lua/MM_Log.lua: punto
	unico de log, gateado por SandboxVars.GSSiK_Addon_Tablet.DebugMode (ver
	GSSiK_Addon_Tablet_Sandbox.lua). Sin esto, DebugMode era una opcion sin
	ningun efecto real (ningun sitio del addon la consultaba).
]]

require "GSSiK_Addon_Tablet_Sandbox"
local API = require "GSSiK_API"

GSSiK_Addon_Tablet.Log = GSSiK_Addon_Tablet.Log or {}

local function requestRelay()
	if isClient and isClient() and not (isServer and isServer())
		and GSSiK_Addon_Tablet.Sandbox.isDebugMode() then
		API.Diagnostics.subscribe("Tablet")
	end
end

--- Segundos transcurridos (con decimas) desde que arranco el proceso actual -
--- la fecha no importa para depurar, pero medir cuanto tarda algo entre dos
--- lineas de log si (pedido 2026-08-16).
---@return string
local function elapsedTag()
	if not getTimestampMs then
		return "?"
	end
	return string.format("%.1fs", getTimestampMs() / 1000)
end

---@param message string
function GSSiK_Addon_Tablet.Log.debug(message)
	if not GSSiK_Addon_Tablet.Sandbox.isDebugMode() then
		return
	end
	requestRelay()
	local _, _, origin = API.Diagnostics.processTag()
	local line = "[" .. elapsedTag() .. "][" .. origin .. "] [GSSiK_Addon_Tablet:DEBUG] " .. tostring(message)
	print(line)
	API.Diagnostics.emit(line)
end

if Events and Events.OnCreatePlayer then
	Events.OnCreatePlayer.Add(requestRelay)
end

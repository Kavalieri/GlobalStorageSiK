--[[
	GSSiK Addon Craft - Registro visible (consola)
	Descripcion: Mismo patron que GSSiK_Addon_Tablet_Log.lua/GS_Log.lua -
	punto unico de log, gateado por SandboxVars.GSSiK_Addon_Craft.DebugMode
	(ver GSSiK_Addon_Craft_Sandbox.lua), INDEPENDIENTE del DebugMode de Core.
	Sin esto, DebugMode era una opcion sin ningun efecto real (ningun sitio
	del addon la consultaba) - igual bug ya corregido antes en Tablet.
]]

require "GSSiK_Addon_Craft_Sandbox"

GSSiK_Addon_Craft = GSSiK_Addon_Craft or {}
GSSiK_Addon_Craft.Log = GSSiK_Addon_Craft.Log or {}

local PREFIX = "[GSSiK_Addon_Craft:DEBUG] "

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
function GSSiK_Addon_Craft.Log.debug(message)
	if not GSSiK_Addon_Craft.Sandbox.isDebugMode() then
		return
	end
	print("[" .. elapsedTag() .. "] " .. PREFIX .. tostring(message))
end

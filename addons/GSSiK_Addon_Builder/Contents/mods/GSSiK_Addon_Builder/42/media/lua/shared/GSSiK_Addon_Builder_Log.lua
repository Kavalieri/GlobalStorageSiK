--[[
	GSSiK Addon Builder - Registro visible (consola)
	Descripcion: Mismo patron que GSSiK_Addon_Tablet_Log.lua/GS_Log.lua -
	punto unico de log, gateado por SandboxVars.GSSiK_Addon_Builder.DebugMode
	(ver GSSiK_Addon_Builder_Sandbox.lua), INDEPENDIENTE del DebugMode de
	Core. Sin esto, DebugMode era una opcion sin ningun efecto real (ningun
	sitio del addon la consultaba) - igual bug ya corregido antes en Tablet.
]]

require "GSSiK_Addon_Builder_Sandbox"

GSSiK_Addon_Builder = GSSiK_Addon_Builder or {}
GSSiK_Addon_Builder.Log = GSSiK_Addon_Builder.Log or {}

local PREFIX = "[GSSiK_Addon_Builder:DEBUG]"

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

---@param category string "Operations"|"Lifecycle"
---@param message string|nil
function GSSiK_Addon_Builder.Log.debug(category, message)
	if message == nil then
		message = category
		category = "Lifecycle"
	end
	if not GSSiK_Addon_Builder.Sandbox.isDebugCategoryEnabled(category) then
		return
	end
	print("[" .. elapsedTag() .. "] " .. PREFIX .. "[" .. tostring(category) .. "] " .. tostring(message))
end

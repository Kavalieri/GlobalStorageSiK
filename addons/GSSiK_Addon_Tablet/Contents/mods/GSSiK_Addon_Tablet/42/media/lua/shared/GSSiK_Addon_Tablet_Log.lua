--[[
	GSSiK Addon Tablet - Registro visible (consola)
	Autor: SiK
	Descripcion: Mismo patron que GS_Log.lua/SCLG_Log.lua/MM_Log.lua: punto
	unico de log, gateado por SandboxVars.GSSiK_Addon_Tablet.DebugMode (ver
	GSSiK_Addon_Tablet_Sandbox.lua). Sin esto, DebugMode era una opcion sin
	ningun efecto real (ningun sitio del addon la consultaba).
]]

require "GSSiK_Addon_Tablet_Sandbox"

GSSiK_Addon_Tablet.Log = GSSiK_Addon_Tablet.Log or {}

local PREFIX = "[GSSiK_Addon_Tablet:DEBUG] "

---@param message string
function GSSiK_Addon_Tablet.Log.debug(message)
	if not GSSiK_Addon_Tablet.Sandbox.isDebugMode() then
		return
	end
	print(PREFIX .. tostring(message))
end

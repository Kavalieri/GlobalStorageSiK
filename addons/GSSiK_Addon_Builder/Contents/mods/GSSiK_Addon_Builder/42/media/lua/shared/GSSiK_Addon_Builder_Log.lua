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

local PREFIX = "[GSSiK_Addon_Builder:DEBUG] "

---@param message string
function GSSiK_Addon_Builder.Log.debug(message)
	if not GSSiK_Addon_Builder.Sandbox.isDebugMode() then
		return
	end
	print(PREFIX .. tostring(message))
end

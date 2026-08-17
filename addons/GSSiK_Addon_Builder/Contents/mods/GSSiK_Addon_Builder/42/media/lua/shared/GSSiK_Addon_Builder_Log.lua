--[[
	GSSiK Addon Builder - Registro visible (consola)
	Descripcion: Mismo patron que GSSiK_Addon_Tablet_Log.lua/GS_Log.lua -
	punto unico de log, gateado por SandboxVars.GSSiK_Addon_Builder.DebugMode
	(ver GSSiK_Addon_Builder_Sandbox.lua), INDEPENDIENTE del DebugMode de
	Core. Sin esto, DebugMode era una opcion sin ningun efecto real (ningun
	sitio del addon la consultaba) - igual bug ya corregido antes en Tablet.
]]

require "GSSiK_Addon_Builder_Sandbox"
pcall(require, "GS_DebugRelay")

GSSiK_Addon_Builder = GSSiK_Addon_Builder or {}
GSSiK_Addon_Builder.Log = GSSiK_Addon_Builder.Log or {}

local detailNoticeShown = false

local function relay()
	return GlobalStorageSiK and GlobalStorageSiK.DebugRelay or nil
end

local function requestRelay()
	local r = relay()
	if r and isClient and isClient() and not (isServer and isServer())
		and GSSiK_Addon_Builder.Sandbox.isDebugMode() then
		r.requestClientSubscription("Builder")
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
	requestRelay()
	local r = relay()
	local origin = r and r.processTag() or "?"
	local level = category == "Operations" and "DETAIL" or "DEBUG"
	if level == "DETAIL" and not detailNoticeShown then
		detailNoticeShown = true
		local notice = "[" .. elapsedTag() .. "][" .. origin .. "] [GSSiK_Addon_Builder:SYSTEM][Operations] DETAIL sublog enabled; high-volume output may fill console.txt; use only for targeted diagnostics"
		print(notice)
		if r then r.emit(notice) end
	end
	local line = "[" .. elapsedTag() .. "][" .. origin .. "] [GSSiK_Addon_Builder:" .. level .. "][" .. tostring(category) .. "] " .. tostring(message)
	print(line)
	if r then r.emit(line) end
end

if Events and Events.OnCreatePlayer then
	Events.OnCreatePlayer.Add(requestRelay)
end

--[[
	GSSiK Addon Craft - Registro visible (consola)
	Descripcion: Mismo patron que GSSiK_Addon_Tablet_Log.lua/GS_Log.lua -
	punto unico de log, gateado por SandboxVars.GSSiK_Addon_Craft.DebugMode
	(ver GSSiK_Addon_Craft_Sandbox.lua), INDEPENDIENTE del DebugMode de Core.
	Sin esto, DebugMode era una opcion sin ningun efecto real (ningun sitio
	del addon la consultaba) - igual bug ya corregido antes en Tablet.
]]

require "GSSiK_Addon_Craft_Sandbox"
local API = require "GSSiK_API"
local Diagnostics = API.Diagnostics

GSSiK_Addon_Craft = GSSiK_Addon_Craft or {}
GSSiK_Addon_Craft.Log = GSSiK_Addon_Craft.Log or {}

local budget = {}

local function requestRelay()
	if isClient and isClient() and not (isServer and isServer())
		and GSSiK_Addon_Craft.Sandbox.isDebugMode() then
		Diagnostics.subscribe("Craft")
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
function GSSiK_Addon_Craft.Log.debug(category, message)
	if message == nil then
		message = category
		category = "Lifecycle"
	end
	if not GSSiK_Addon_Craft.Sandbox.isDebugCategoryEnabled(category) then
		return
	end
	local now = getTimestampMs and tonumber(getTimestampMs()) or 0
	local bucket = budget[category]
	if not bucket or now < bucket.startedAt or now - bucket.startedAt >= 1000 then
		bucket = { startedAt = now, lines = 0 }
		budget[category] = bucket
	end
	if bucket.lines >= 20 then return end
	bucket.lines = bucket.lines + 1
	message = tostring(message)
	if #message > 1024 then message = "oversized diagnostic omitted bytes=" .. tostring(#message) end
	requestRelay()
	local _, _, origin = Diagnostics.processTag()
	origin = origin or "?"
	local level = "DEBUG"
	local line = "[" .. elapsedTag() .. "][" .. origin .. "] [GSSiK_Addon_Craft:" .. level .. "][" .. tostring(category) .. "] " .. tostring(message)
	print(line)
	Diagnostics.emit(line)
end

if Events and Events.OnCreatePlayer then
	Events.OnCreatePlayer.Add(requestRelay)
end

--[[
	GlobalStorageSiK - Registro visible (Error Magnifier / consola)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Errores siempre a consola; info detallada con DebugMode.
]]

require "GS_Sandbox"

GlobalStorageSiK.Log = GlobalStorageSiK.Log or {}

--- Hook opcional: cuando está establecido, cada línea de log se reenvía (servidor → cliente).
---@type function|nil
GlobalStorageSiK.Log._echoHook = nil

local PREFIX = "[GlobalStorageSiK"

--- Segundos transcurridos (con decimas) desde que arrancó el proceso actual -
--- la fecha no importa para depurar, pero medir cuánto tarda algo entre dos
--- líneas de log sí (pedido 2026-08-16, tras varias rondas de logs reales
--- donde localizar "cuanto paso entre X e Y" a mano era tedioso).
--- getTimestampMs existe tanto en cliente como en servidor.
---@return string
local function elapsedTag()
	if not getTimestampMs then
		return "?"
	end
	return string.format("%.1fs", getTimestampMs() / 1000)
end

--- Mapa area de log (primer argumento de cada llamada Log.debug/Debug.log en
--- todo el mod) -> categoria de sandbox (ver GS_Sandbox.debugCategoryEnabled).
--- Un area sin entrada aqui NO se filtra por categoria (solo por DebugMode
--- maestro) - ver el comentario de debugCategoryEnabled() sobre por que.
local AREA_CATEGORY = {
	NetTrace = "Network",
	Client = "Network",
	-- BUG REAL encontrado (reportado: "el log tiene mucho ruido"): el area
	-- "Network" (getLiveContainers SOURCES, la traza mas frecuente de todas)
	-- no tenia entrada aqui, asi que caia en la regla "area sin mapear = no
	-- se filtra por categoria" y salia SIEMPRE con DebugMode activo, sin que
	-- apagar DebugCatNetwork tuviera ningun efecto sobre ella.
	Network = "Network",
	TerminalAccess = "TerminalAccess",
	Access = "TerminalAccess",
	TerminalManifest = "TerminalAccess",
	TerminalRegistry = "TerminalAccess",
	CraftUtils = "Craft",
	RecipeTuning = "Craft",
	ItemNetworkTooltip = "Tooltip",
	Server = "Inventory",
	Deposit = "Inventory",
	RedistributeJob = "Inventory",
	ItemTaxonomy = "Inventory",
	Subcategories = "Inventory",
	Router = "Router",
	NodeNaming = "UI",
	TerminalUI = "UI",
}

--- Escribe línea en consola del juego.
---@param level string
---@param area string
---@param message string
---@param detail any|nil
local function write(level, area, message, detail)
	local line = "[" .. elapsedTag() .. "] " .. PREFIX .. ":" .. tostring(level) .. ":" .. tostring(area) .. "] " .. tostring(message)
	if detail ~= nil then
		line = line .. " | " .. tostring(detail)
	end
	print(line)
	if GlobalStorageSiK.Log._echoHook then
		pcall(GlobalStorageSiK.Log._echoHook, line)
	end
end

--- Error siempre visible (compatible con Error Magnifier).
---@param area string
---@param message string
---@param detail any|nil
function GlobalStorageSiK.Log.error(area, message, detail)
	write("ERROR", area, message, detail)
	if debug and debug.traceback then
		print(debug.traceback("", 2))
	end
end

--- Aviso siempre visible.
---@param area string
---@param message string
---@param detail any|nil
function GlobalStorageSiK.Log.warn(area, message, detail)
	write("WARN", area, message, detail)
end

--- Info de flujo (acceso terminal, etc.). Solo con DebugMode sandbox activo
--- (igual que .debug()) - no es un error ni un aviso, es traza de operacion
--- normal y no debe aparecer en consola si el jugador no activo el debug.
---@param area string
---@param message string
---@param detail any|nil
function GlobalStorageSiK.Log.info(area, message, detail)
	if not GlobalStorageSiK.Sandbox.debugMode() then
		return
	end
	local category = AREA_CATEGORY[area]
	if category and not GlobalStorageSiK.Sandbox.debugCategoryEnabled(category) then
		return
	end
	write("INFO", area, message, detail)
end

--- Traza solo con DebugMode sandbox.
---@param area string
---@param message string
---@param detail any|nil
function GlobalStorageSiK.Log.debug(area, message, detail)
	if not GlobalStorageSiK.Sandbox.debugMode() then
		return
	end
	local category = AREA_CATEGORY[area]
	if category and not GlobalStorageSiK.Sandbox.debugCategoryEnabled(category) then
		return
	end
	write("DEBUG", area, message, detail)
end

--- Ejecuta función con captura de error reportada.
---@param area string
---@param fn function
---@param ... any
---@return boolean ok
---@return any result
function GlobalStorageSiK.Log.pcall(area, fn, ...)
	local results = { pcall(fn, ...) }
	local ok = results[1]
	if not ok then
		GlobalStorageSiK.Log.error(area, results[2])
	end
	return ok, table.unpack(results, 2)
end

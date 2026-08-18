--[[
	GlobalStorageSiK - Registro visible (Error Magnifier / consola)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Errores siempre a consola; info detallada con DebugMode.
]]

require "GS_Sandbox"
require "GS_DebugRelay"

GlobalStorageSiK.Log = GlobalStorageSiK.Log or {}
GlobalStorageSiK.Log._detailNoticeShown = GlobalStorageSiK.Log._detailNoticeShown or {}

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
	Permissions = "TerminalAccess",
	CraftUtils = "Craft",
	RecipeTuning = "Craft",
	Acquire = "Craft",
	-- El estado/fallo del hook pertenece al bloque Tooltip. El render por
	-- frame usa un area separada y queda bajo el sublog masivo de inventario,
	-- de modo que activar solo Tooltip no llena console.txt.
	ItemNetworkTooltip = "Tooltip",
	ItemNetworkTooltipDetail = "Inventory",
	Server = "Inventory",
	Deposit = "Inventory",
	DepositClient = "Inventory",
	TransferQueue = "Inventory",
	NetworkReadAction = "Inventory",
	CraftSession = "Craft",
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
	local origin = GlobalStorageSiK.DebugRelay.processTag()
	local line = "[" .. elapsedTag() .. "][" .. origin .. "] " .. PREFIX .. ":" .. tostring(level) .. ":" .. tostring(area) .. "] " .. tostring(message)
	if detail ~= nil then
		line = line .. " | " .. tostring(detail)
	end
	print(line)
	GlobalStorageSiK.DebugRelay.emit(line)
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

--- Traza de alto volumen dentro de la categoria del area. Se usa para
--- payloads completos y lineas por objeto/nodo; nunca se activa solo por
--- encender el bloque padre.
---@param area string
---@param message string
---@param detail any|nil
function GlobalStorageSiK.Log.detail(area, message, detail)
	local category = AREA_CATEGORY[area]
	if not category or not GlobalStorageSiK.Sandbox.debugDetailEnabled(category) then
		return
	end
	if not GlobalStorageSiK.Log._detailNoticeShown[category] then
		GlobalStorageSiK.Log._detailNoticeShown[category] = true
		write("SYSTEM", area, "DETAIL sublog enabled category=" .. tostring(category)
			.. "; high-volume output may fill console.txt; use only for targeted diagnostics")
	end
	write("DETAIL", area, message, detail)
end

--- Ejecuta función con captura de error reportada.
---@param area string
---@param fn function
---@param ... any
---@return boolean ok
---@return any result
function GlobalStorageSiK.Log.pcall(area, fn, ...)
	-- Conservar posiciones aunque un retorno intermedio sea nil. Guardarlo en
	-- una tabla y usar unpack sin limite puede truncar los valores posteriores.
	local ok, r1, r2, r3, r4, r5, r6, r7, r8 = pcall(fn, ...)
	if not ok then
		GlobalStorageSiK.Log.error(area, r1)
	end
	return ok, r1, r2, r3, r4, r5, r6, r7, r8
end

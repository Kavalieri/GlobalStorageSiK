--[[
	GlobalStorageSiK - Registro visible (Error Magnifier / consola)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Errores siempre a consola; info detallada con DebugMode.
]]

require "GS_Sandbox"
require "GS_DebugRelay"
require "GS_DiagnosticsSession"

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
	Permissions = "Permissions",
	Identity = "Permissions",
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
	-- dev36: categoria "UI" (antes cubria NodeNaming + TerminalUI a la vez,
	-- sin poder separarlos) retirada y sustituida por un arbol propio "SiK UI"
	-- con sub-categorias, pedido explicito del usuario para poder depurar
	-- el framework/interfaz por partes tras la migracion completa de
	-- NeatUI_Framework a SiK_UI (dev28-dev35). NodeNaming es logica de
	-- nombrado de terminal (servidor de nombres), no forma parte del
	-- framework visual - se separa en su propia categoria para no perderla.
	NodeNaming = "NodeNaming",
	-- General/framework: apertura de ventana, refresco de pestaña, fallos de
	-- TerminalUI - antes "UI" (compartida con NodeNaming), ahora bajo el
	-- arbol SiK UI. Tambien gobierna GS_UIDebug.lua (arbol de widgets, clicks,
	-- solapes) - ver GlobalStorageSiK.Sandbox.debugCategoryEnabled("SiKUI"),
	-- sustituye al antiguo interruptor independiente DebugModeUI.
	TerminalUI = "SiKUI",
	-- Geometria de columnas de SiK_UI.Table (GS_SiK_UI_Table.lua) - ancho
	-- resuelto por columna, solo se traza cuando el ancho disponible cambia
	-- de verdad (resize), nunca por fotograma.
	SiKUITable = "SiKUITable",
	-- Motor de scroll/lista virtual (GS_TerminalUI_Scroll.lua) - crecimiento
	-- de pool y cambios de dataset (Almacen y cualquier lista virtualizada).
	SiKUIScroll = "SiKUIScroll",
	-- Pestañas laterales + contrato de extensiones (GS_TerminalUI_TabRail.lua/
	-- GS_TerminalUI_Extensions.lua) - registro/reutilizacion de panel,
	-- visibilidad y activacion/cancelacion de clic.
	SiKUITabs = "SiKUITabs",
	-- Caja de busqueda de SiK UI (antes "SearchDiag", pedido explicito
	-- 2026-08-18: sin esta entrada dependia solo del interruptor maestro).
	-- Renombrada en dev36 para agrupar bajo el mismo arbol SiK UI en vez de
	-- quedar suelta.
	SiKUISearch = "SiKUISearch",
	-- Categoria propia (pedido explicito 2026-08-21, fase dev Better Sorting):
	-- traza de normalizacion de categorias por item, alto volumen (Log.detail),
	-- debe poder apagarse sin tocar el resto de diagnosticos activos.
	CompatCategories = "CompatCategories",
	-- Categoria propia (pedido explicito 2026-08-21, prueba de bonus de
	-- capacidad por rasgo tipo Organizado): confirma si/cuanto bonus personal
	-- se detecto por contenedor durante la prueba, sin depender del
	-- interruptor maestro ni mezclarse con otro diagnostico activo.
	CapacityBonus = "CapacityBonus",
	-- Categoria propia (pedido explicito 2026-08-21, diagnostico del tick de
	-- "ya leido" en manuales GS): confirma con datos reales si la sonda de
	-- receta (instanceItem + getLearnedRecipes) tiene exito o falla, en vez
	-- de seguir adivinando a ciegas por que un manual con receta fija de
	-- script nunca marcaba el tick pese a estar ya aprendida.
	LiteratureRead = "LiteratureRead",
	-- Categoria propia (pedido explicito 2026-08-23, tras un reporte real de
	-- un jugador con 8 zonas contando para el limite de sandbox pero solo 2
	-- realmente pobladas, sin ninguna traza que explicara que estaba pasando
	-- ni por que): la creacion de zonas (los 5 caminos "Crear zona desde...")
	-- no tenia NINGUN log, ni siquiera sin categoria propia - imposible
	-- diagnosticar a distancia sin pedirle al jugador capturas manuales de
	-- cada zona. Cubre nombre/origen/bounds de cada intento, si coincide con
	-- una zona ya existente (guarda de duplicados, ver GS_Zones.
	-- findDuplicateZone) y el recuento contra el limite configurado.
	Zones = "Zones",
	-- Categoria propia (pedido explicito 2026-08-23, diagnostico del menu
	-- contextual "Global Storage" tras un reporte real de que la opcion
	-- Transferir no aparecia ni por proximidad fisica ni con el Almacen
	-- abierto): confirma si el evento OnPreFillInventoryObjectContextMenu
	-- llega a dispararse de verdad para el click probado, en vez de seguir
	-- adivinando a ciegas si el fallo esta en el registro del evento o en la
	-- condicion de canTransfer.
	ItemActions = "ItemActions",
	-- Categoria propia (pedido explicito 2026-08-23, tras reporte real: "no
	-- me ha entregado la impresora" al desinstalar y "no consumio la
	-- impresora" al instalar, con todos los addons probados): confirma con
	-- datos reales el fullType exacto buscado/eliminado al instalar y si
	-- giveModuleItem() genero de verdad el item al desinstalar - antes este
	-- subsistema no tenia NINGUNA traza, ni siquiera sin categoria propia.
	Addons = "Addons",
}

--- Ficheros de depuración por categoría, uno por bloque individual del
--- sandbox. Cada proceso crea una sesión bajo
--- Lua/SiKDiagnostics/GlobalStorageSiK/<sessionId>/; Permissions usa su
--- suite y run propios, y el resto queda bajo debug/. Las rutas únicas
--- evitan que una ejecución sobrescriba otra y session.json conserva el
--- inventario de evidencias de la sesión.
--- API real getFileWriter(nombre, relativeToModData, append), misma que
--- usa SCLG_FileLog.lua (confirmada en scripts vanilla, ej. forageSystem.lua).
--- La primera línea de una categoría en cada arranque de proceso es un
--- separador "=== INICIO <categoria> <fecha/hora> proceso=<CLI/SRV/HOST/SP>
--- ===". No hay marca de "FIN" fiable (no existe un evento de apagado
--- limpio garantizado en un servidor dedicado que se pueda capturar desde
--- Lua). Una categoría desactivada o sin trazas no crea una evidencia vacía.
local FILE_LOG_PREFIX = "GlobalStorageSiK_Debug_"
local categoryFileStartedThisRun = {}
local categoryFilePath = {}

---@return string
local function fileTimestamp()
	local ok, s = pcall(function() return os.date("%Y-%m-%d %H:%M:%S") end)
	return (ok and s) and s or "?"
end

---@param category string
---@param line string
local function writeCategoryFile(category, line)
	if not GlobalStorageSiK.Sandbox.debugCategoryEnabled(category) then
		return
	end
	local fileName = categoryFilePath[category]
	if not fileName and GlobalStorageSiK.DiagnosticsSession then
		local suite = category == "Permissions" and "permissions" or "debug"
		local kind = category == "Permissions" and "permissions" or string.lower(tostring(category))
		local run = GlobalStorageSiK.DiagnosticsSession.beginRun(suite, { kind })
		fileName = run.paths[kind]
		categoryFilePath[category] = fileName
	end
	fileName = fileName or (FILE_LOG_PREFIX .. category .. ".log")
	if not categoryFileStartedThisRun[category] then
		categoryFileStartedThisRun[category] = true
		local okStart, startWriter = pcall(getFileWriter, fileName, true, true)
		if okStart and startWriter then
			pcall(function()
				startWriter:write("=== INICIO " .. category .. " " .. fileTimestamp()
					.. " proceso=" .. tostring(GlobalStorageSiK.DebugRelay.processTag()) .. " ===\r\n")
			end)
			pcall(function() startWriter:close() end)
		end
	end
	local ok, writer = pcall(getFileWriter, fileName, true, true)
	if not ok or not writer then
		return
	end
	pcall(function()
		writer:write("[" .. fileTimestamp() .. "] " .. line .. "\r\n")
	end)
	pcall(function() writer:close() end)
	categoryFileStartedThisRun[category] = true
end

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
	local category = AREA_CATEGORY[area]
	if category then
		writeCategoryFile(category, line)
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

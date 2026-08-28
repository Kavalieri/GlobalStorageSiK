--[[
	GlobalStorageSiK - Pestaña "Taxonomía" del panel de staff QA/Diagnóstico
	Autor: SiK
	Fecha: 2026-08-27

	dev22 (pedido explicito de sistemas, reorganizacion de GS_AdminDashboard.lua
	en pestañas "Soporte de redes"/"Taxonomia"): extraccion de TODO lo
	relacionado con la auditoria del catalogo nativo - antes era un unico
	boton (nativeAuditBtn) mezclado con las herramientas de red en
	buildStaticFrame(). Mismo motivo que la extraccion de runNativeAudit a
	GS_NativeAuditServer.lua en dev14: mantener GS_AdminDashboard.lua sin
	crecer mas de lo necesario.

	dev23 (rechazo visual de sistemas sobre dev22: "catalogEpoch+fingerprint
	y la linea de ficheros atraviesan el borde derecho - 4 ISLabel fijas de
	una linea, refreshSummary() solo llama a setName()"): sustituidas las 4
	labels fijas por un bloque dinamico dentro de un TerminalScroll (mismo
	motor de scroll ya usado en el resto del mod, ver GS_TerminalUI_Scroll.lua)
	que envuelve TODO texto variable con SiK_UI.wrapTextLines() y recalcula
	su propio alto de contenido en cada refreshSummary() - nunca solo
	setName() sobre una altura fija. version/estado tambien pasan por el
	mismo wrap (linea corta en la practica, pero nunca se asume).

	Redimensionado: NO hay un onResize propio en este fichero - GS_AdminDashboard.
	lua:rebuildAfterResize() ya hace clearChildren()+buildStaticFrame() enteros
	en cada resize (mecanismo preexistente, no tocado), lo que reconstruye
	esta pestaña completa con el ancho nuevo. Cumple el requisito de sistemas
	("al redimensionar, el resumen debe envolverse de nuevo") sin necesitar
	un segundo camino de reflow incremental.

	Alcance (solo lectura/diagnostico): boton "Auditar catalogo" (unico
	hogar, ya no vive en Soporte de redes), estado de ejecucion inactivo/
	ejecutando/completado/error, resumen persistente de la ultima auditoria,
	nombres de fichero server-side, agregado del probe tier/variant,
	representacion compacta del fingerprint (digest + nº de mods + build,
	nunca la cadena completa - eso se queda en GlobalStorageSiK_NativeAudit.log).
	NUNCA envia el informe completo por red - eso sigue siendo
	responsabilidad exclusiva de GS_NativeAuditServer.lua/GS_NativeAudit.lua.
]]

require "ISUI/ISLabel"
require "GS_I18n"
require "GS_SiK_UI_Core"
require "GS_TerminalUI_Scroll"
require "GS_Config"

GlobalStorageSiK.AdminDashboardAudit = GlobalStorageSiK.AdminDashboardAudit or {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local LINE_GAP = 4
local BTN_H = FONT_HGT_SMALL + 8
local MIN_SUMMARY_SCROLL_H = FONT_HGT_SMALL * 4

-- dev24: renderWrappedLines() promovida a GlobalStorageSiK.SiK_UI.
-- renderWrappedLinePool() (GS_SiK_UI_Core.lua) para reutilizarla tambien en
-- GS_AdminDashboard_Corpus.lua - alias local para no tocar el resto de este
-- fichero.
local renderWrappedLines = GlobalStorageSiK.SiK_UI.renderWrappedLinePool

--- Construye la pestaña Taxonomia completa - todos los widgets creados aqui
--- se añaden como hijos de `ui` (la ventana) y se registran en
--- `ui._taxonomyTabWidgets` para que GS_AdminDashboardUI:selectStaffTab()
--- pueda mostrarlos/ocultarlos sin reconstruir nada.
---@param ui table GS_AdminDashboardUI instance
---@param pad number
---@param y number posicion Y inicial (debajo de la barra de pestañas)
---@param textW number ancho util del contenido
---@param bottomLimitY number limite inferior REAL de esta seccion - dev24:
---  ya no se asume "hasta el final de la ventana", la pestaña Taxonomia
---  reparte el alto disponible entre esta suite y GS_AdminDashboardCorpus.lua.
function GlobalStorageSiK.AdminDashboardAudit.build(ui, pad, y, textW, bottomLimitY)
	local function track(widget)
		ui._taxonomyTabWidgets[#ui._taxonomyTabWidgets + 1] = widget
	end
	local function trackAddChild(host, widget)
		host:addChild(widget)
		track(widget)
	end

	ui._auditPad = pad
	ui._auditContentW = textW
	ui._auditVersionPool = {}
	ui._auditStatePool = {}

	y = renderWrappedLines(ui, ui._auditVersionPool,
		T("IGUI_GS_TaxonomyVersionLine", tostring(GlobalStorageSiK.Config and GlobalStorageSiK.Config.MOD_VERSION or "?")),
		pad, y, textW, trackAddChild)
	y = y + LINE_GAP + 4

	ui.nativeAuditBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad, y, textW, BTN_H, T("IGUI_GS_NativeAuditBtn"), ui, function()
			GlobalStorageSiK.AdminDashboardAudit.runNativeAudit(ui)
		end)
	trackAddChild(ui, ui.nativeAuditBtn)
	y = y + BTN_H + LINE_GAP + 4

	ui._auditStateY = y

	-- dev23: el limite inferior REAL de la pestaña (alto de la ventana menos
	-- el padding) se guarda aparte de `y` - refreshSummary() reposiciona y
	-- redimensiona el scroll de resumen en cada llamada usando este limite,
	-- para que un estado que crezca a 2 lineas (ventana muy estrecha) no
	-- deje el scroll superpuesto con la ultima linea de estado (requisito
	-- de sistemas: "la posicion Y de cada bloque debe calcularse con el
	-- numero real de lineas producido", no solo en la construccion inicial).
	ui._auditBottomLimit = bottomLimitY

	-- El propio scroll se crea aqui (una vez), pero su Y/alto reales los fija
	-- refreshSummary() a partir de ui._auditStateY - evita crear el
	-- widget 2 veces.
	ui.nativeAuditSummaryScroll = GlobalStorageSiK.TerminalScroll.create(ui, pad, y, textW, MIN_SUMMARY_SCROLL_H)
	track(ui.nativeAuditSummaryScroll)

	GlobalStorageSiK.AdminDashboardAudit.refreshSummary(ui)
end

--- Repinta estado + resumen a partir de `ui._nativeAuditLastReport`/
--- `ui._nativeAuditRunning`/`ui._nativeAuditLastFailed` - SIEMPRE recalcula
--- el layout con el ancho actual (`ui._auditContentW`, actualizado en
--- cada reconstruccion de ventana por resize), nunca un simple :setName()
--- sobre posiciones fijas (dev23, rechazo de sistemas sobre dev22).
---@param ui table
function GlobalStorageSiK.AdminDashboardAudit.refreshSummary(ui)
	if not ui._auditStatePool then return end
	local pad = ui._auditPad
	local textW = ui._auditContentW

	-- Estado: 1 de 4 textos mutuamente excluyentes, diferenciados tambien
	-- por color (requisito explicito de sistemas: distinguir visualmente
	-- ejecutando/completado/error/ocupado). "Ocupado" comparte texto con
	-- "error" (ambos son un actionResult fallido, ver onActionResult) -
	-- distinguir esos dos casos exigiria que el servidor marcara la causa
	-- del fallo en el payload, fuera de alcance de esta ronda.
	local stateText, stateColor
	if ui._nativeAuditRunning then
		stateText, stateColor = T("IGUI_GS_TaxonomyStateRunning"), { r = 0.85, g = 0.75, b = 0.35 }
	elseif ui._nativeAuditLastFailed then
		stateText, stateColor = T("IGUI_GS_TaxonomyStateError"), { r = 0.85, g = 0.4, b = 0.35 }
	elseif ui._nativeAuditLastReport then
		local finishedText = GlobalStorageSiK.SiK_UI.relativeAge(ui._nativeAuditFinishedAtMs)
		ui._nativeAuditFinishedAtText = finishedText
		stateText, stateColor = T("IGUI_GS_TaxonomyStateDone", finishedText), { r = 0.55, g = 0.8, b = 0.5 }
	else
		stateText, stateColor = T("IGUI_GS_TaxonomyStateIdle"), { r = 0.72, g = 0.75, b = 0.8 }
	end
	local function addStateLabel(host, widget)
		host:addChild(widget)
		ui._taxonomyTabWidgets[#ui._taxonomyTabWidgets + 1] = widget
	end
	local afterStateY = renderWrappedLines(ui, ui._auditStatePool, stateText, pad, ui._auditStateY, textW, addStateLabel)
	for i = 1, #ui._auditStatePool do
		local lbl = ui._auditStatePool[i]
		if lbl then lbl:setColor(stateColor.r, stateColor.g, stateColor.b) end
	end

	if ui.nativeAuditBtn then
		local locked = ui._nativeAuditRunning == true
		ui.nativeAuditBtn._sikUiLocked = locked
		ui.nativeAuditBtn:setEnable(not locked)
	end

	-- dev23: el scroll se reposiciona/redimensiona aqui con el Y REAL tras
	-- el estado (nunca asumido en la construccion inicial) - cubre el caso
	-- de que el estado crezca a 2 lineas en una ventana estrecha sin dejar
	-- el scroll superpuesto con la ultima linea de estado.
	local scroll = ui.nativeAuditSummaryScroll
	if not scroll then return end
	local scrollY = afterStateY + LINE_GAP + 6
	local scrollH = math.max(MIN_SUMMARY_SCROLL_H, (ui._auditBottomLimit or scrollY) - scrollY)
	scroll:setY(scrollY)
	GlobalStorageSiK.TerminalScroll.resize(scroll, textW, scrollH)

	-- Resumen: reconstruido por completo dentro del scroll en cada llamada
	-- (mismo patron ya usado por refreshMemberPanel en GS_AdminDashboard.lua
	-- para listas de tamaño variable) - clear() ya garantiza que ninguna
	-- linea sobrante de una ejecucion anterior queda visible.
	GlobalStorageSiK.TerminalScroll.clear(scroll)
	local contentW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local sy = 2

	local report = ui._nativeAuditLastReport
	if not report then
		sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomyNoRunYet"), 4, sy, contentW - 8,
			GlobalStorageSiK.TerminalScroll.addChild)
		GlobalStorageSiK.TerminalScroll.finish(scroll, sy)
		return
	end

	sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomySummaryLine",
		tostring(report.totalTypes), tostring(report.pending), tostring(report.unclassified),
		tostring(report.excludedInternal or 0), tostring(report.invalidPath),
		tostring(report.classifierErrors), tostring(report.timeMs)),
		4, sy, contentW - 8, GlobalStorageSiK.TerminalScroll.addChild)

	-- dev23 (rechazo de sistemas: "el fingerprint completo es demasiado
	-- largo para una interfaz, incluso envuelto - mostrar una
	-- representacion compacta, el completo solo en el log server-side"):
	-- digest corto + nº de mods + build, NUNCA una subcadena truncada del
	-- fingerprint completo (que podria confundirse con el valor real).
	sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomyEpochLine",
		tostring(report.catalogEpoch), tostring(report.gameBuildVersion),
		tostring(report.activeModCount), tostring(report.catalogFingerprintDigest)),
		4, sy, contentW - 8, GlobalStorageSiK.TerminalScroll.addChild)

	sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomyTierVariantLine",
		tostring(report.tierVariantMatched), tostring(report.tierVariantTotal)),
		4, sy, contentW - 8, GlobalStorageSiK.TerminalScroll.addChild)

	sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomyRunLine",
		tostring(report.sessionId or "?"), tostring(report.runId or "?")),
		4, sy, contentW - 8, GlobalStorageSiK.TerminalScroll.addChild)

	-- dev23 (pedido explicito: "lineas independientes, sin asumir
	-- exactamente 2 ficheros"): recorre una lista en vez de 2 campos fijos -
	-- soporta ampliarse en el futuro sin tocar este bloque.
	local files = {
		{ labelKey = "IGUI_GS_TaxonomyFileReport", name = report.fileName },
		{ labelKey = "IGUI_GS_TaxonomyFileUnclassified", name = report.unclassifiedFileName },
		{ labelKey = "IGUI_GS_TaxonomyFileExcludedInternal", name = report.excludedInternalFileName },
	}
	for i = 1, #files do
		if files[i].name then
			sy = renderWrappedLines(scroll, {}, T(files[i].labelKey, tostring(files[i].name)),
				4, sy, contentW - 8, GlobalStorageSiK.TerminalScroll.addChild)
		end
	end

	GlobalStorageSiK.TerminalScroll.finish(scroll, sy)
end

--- Envia el comando runNativeAudit - guarda de un solo vuelo en CLIENTE
--- (ademas de la guarda de concurrencia ya existente en servidor,
--- GS_NativeAuditServer.lua): una segunda pulsacion mientras ya hay una
--- auditoria en curso simplemente no hace nada, el boton ya aparece
--- bloqueado (ver refreshSummary).
--
--- dev23 (pedido explicito de sistemas: "el boton solo debe desbloquearse
--- por la respuesta correspondiente a su propia ejecucion"): genera un
--- `requestId` local incremental y lo manda en el comando - el servidor
--- (GS_NativeAuditServer.lua) lo reenvia tal cual en su respuesta, exito o
--- fallo, y onSummary()/onActionResult() ignoran cualquier respuesta cuyo
--- requestId no coincida con el de la ultima peticion enviada.
--
--- Expuesta como funcion del modulo (NO como metodo de GS_AdminDashboardUI)
--- a proposito: esta funcion se define al cargar GS_AdminDashboard_Audit.lua,
--- requerido ANTES de que GS_AdminDashboard.lua defina la clase
--- GS_AdminDashboardUI (linea ~482) - "function GS_AdminDashboardUI:x()"
--- aqui fallaria contra una tabla global todavia inexistente.
---@param ui table GS_AdminDashboardUI instance
function GlobalStorageSiK.AdminDashboardAudit.runNativeAudit(ui)
	if ui._nativeAuditRunning then return end
	ui._nativeAuditRequestId = (ui._nativeAuditRequestId or 0) + 1
	ui._nativeAuditRunning = true
	ui._nativeAuditLastFailed = false
	GlobalStorageSiK.AdminDashboardAudit.refreshSummary(ui)
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("runNativeAudit", { requestId = ui._nativeAuditRequestId })
	end
end

--- Llamado desde GlobalStorageSiK.AdminDashboard.onNativeAuditSummary()
--- cuando llega "nativeAuditSummary" del servidor.
---@param ui table
---@param report table
function GlobalStorageSiK.AdminDashboardAudit.onSummary(ui, report)
	if report and report.requestId ~= nil and report.requestId ~= ui._nativeAuditRequestId then
		-- Respuesta de una peticion anterior (o de otra pestaña/sesion) -
		-- nunca actualiza el estado de la peticion EN CURSO.
		return
	end
	ui._nativeAuditRunning = false
	ui._nativeAuditLastFailed = false
	ui._nativeAuditLastReport = report
	ui._nativeAuditFinishedAtMs = report and tonumber(report.finishedAtMs) or nil
	ui._nativeAuditFinishedAtText = GlobalStorageSiK.SiK_UI.relativeAge(ui._nativeAuditFinishedAtMs)
	GlobalStorageSiK.AdminDashboardAudit.refreshSummary(ui)
end

--- Llamado desde GlobalStorageSiK.AdminDashboard.onActionResult() para
--- CUALQUIER actionResult recibido - si habia una auditoria en curso, el
--- resultado es un fallo (ocupado/error/abortada, ver
--- GS_NativeAuditServer.lua) Y el `requestId`/`action` corresponden a ESTA
--- ejecucion, libera el boton en vez de dejarlo bloqueado para siempre.
--
--- dev23 (cierra el limite aceptado de dev22 - "una accion administrativa
--- fallida no debe desbloquear ni cambiar el estado de la auditoria"): el
--- actionResult generico ahora lleva `action="runNativeAudit"` +
--- `requestId` (ver GS_NativeAuditServer.lua) - un fallo de OTRA accion
--- (p.ej. borrar una red) ya NO coincide y este handler lo ignora.
---@param ui table
---@param args table|nil
function GlobalStorageSiK.AdminDashboardAudit.onActionResult(ui, args)
	if not ui._nativeAuditRunning then return end
	if not args or args.ok ~= false then return end
	if args.action ~= "runNativeAudit" then return end
	if args.requestId ~= nil and args.requestId ~= ui._nativeAuditRequestId then return end
	ui._nativeAuditRunning = false
	ui._nativeAuditLastFailed = true
	GlobalStorageSiK.AdminDashboardAudit.refreshSummary(ui)
end

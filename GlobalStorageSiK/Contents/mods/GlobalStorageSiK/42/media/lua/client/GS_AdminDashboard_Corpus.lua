--[[
	GlobalStorageSiK - Suite "Validar corpus" de la pestaña Taxonomía
	Autor: SiK
	Fecha: 2026-08-27

	dev24 (pedido explicito de sistemas, DEV24 - "infraestructura de corpus
	ground-truth"): suite DIFERENCIADA de "Auditar catálogo"
	(GS_AdminDashboard_Audit.lua) - estado, `requestId`, última ejecución y
	resumen PROPIOS, nunca compartidos - una respuesta de esta suite no
	desbloquea ni sobrescribe la otra, y viceversa (mismo aislamiento que ya
	tienen las guardas de concurrencia server-side, ver
	GS_NativeCorpusServer.lua). Reutiliza el layout envuelto+scroll de dev23
	(GlobalStorageSiK.SiK_UI.renderWrappedLinePool, GS_TerminalUI_Scroll)
	sin duplicarlo.

	NUNCA envía la lista detallada de divergencias por red - eso vive
	exclusivamente en GlobalStorageSiK_NativeCorpus.log, escrito en servidor
	por GS_NativeCorpus.lua. Solo lectura/diagnóstico, sin mutar catálogo,
	cachés, redes ni permisos.
]]

require "ISUI/ISLabel"
require "GS_I18n"
require "GS_SiK_UI_Core"
require "GS_TerminalUI_Scroll"

GlobalStorageSiK.AdminDashboardCorpus = GlobalStorageSiK.AdminDashboardCorpus or {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local LINE_GAP = 4
local BTN_H = FONT_HGT_SMALL + 8
local MIN_SUMMARY_SCROLL_H = FONT_HGT_SMALL * 4

local renderWrappedLines = GlobalStorageSiK.SiK_UI.renderWrappedLinePool

--- Construye la seccion "Validar corpus" dentro de la pestaña Taxonomia -
--- todos los widgets creados aqui se añaden como hijos de `ui` y se
--- registran en `ui._taxonomyTabWidgets` (mismo mecanismo de
--- mostrar/ocultar de GS_AdminDashboardUI:selectStaffTab()).
---@param ui table GS_AdminDashboardUI instance
---@param pad number
---@param y number posicion Y inicial (debajo de la seccion de auditoria)
---@param textW number ancho util del contenido
---@param bottomLimitY number limite inferior REAL de esta seccion
function GlobalStorageSiK.AdminDashboardCorpus.build(ui, pad, y, textW, bottomLimitY)
	local function track(widget)
		ui._taxonomyTabWidgets[#ui._taxonomyTabWidgets + 1] = widget
	end
	local function trackAddChild(host, widget)
		host:addChild(widget)
		track(widget)
	end

	ui._corpusPad = pad
	ui._corpusContentW = textW
	ui._corpusStatePool = {}

	local title = GlobalStorageSiK.SiK_UI.createSectionLabel(pad, y, T("IGUI_GS_TaxonomyCorpusTitle"))
	trackAddChild(ui, title)
	y = y + FONT_HGT_SMALL + LINE_GAP + 2

	ui.nativeCorpusBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad, y, textW, BTN_H, T("IGUI_GS_NativeCorpusBtn"), ui, function()
			GlobalStorageSiK.AdminDashboardCorpus.runNativeCorpus(ui)
		end)
	trackAddChild(ui, ui.nativeCorpusBtn)
	y = y + BTN_H + LINE_GAP + 4

	ui._corpusStateY = y
	ui._corpusBottomLimit = bottomLimitY

	ui.nativeCorpusSummaryScroll = GlobalStorageSiK.TerminalScroll.create(ui, pad, y, textW, MIN_SUMMARY_SCROLL_H)
	track(ui.nativeCorpusSummaryScroll)

	GlobalStorageSiK.AdminDashboardCorpus.refreshSummary(ui)
end

--- Repinta estado + resumen a partir de `ui._nativeCorpusLastReport`/
--- `ui._nativeCorpusRunning`/`ui._nativeCorpusLastFailed` - mismo patron
--- exacto que GS_AdminDashboardAudit.refreshSummary (layout dinamico,
--- scroll reposicionado con el Y real).
---@param ui table
function GlobalStorageSiK.AdminDashboardCorpus.refreshSummary(ui)
	if not ui._corpusStatePool then return end
	local pad = ui._corpusPad
	local textW = ui._corpusContentW

	local stateText, stateColor
	if ui._nativeCorpusRunning then
		stateText, stateColor = T("IGUI_GS_TaxonomyStateRunning"), { r = 0.85, g = 0.75, b = 0.35 }
	elseif ui._nativeCorpusLastFailed then
		stateText, stateColor = T("IGUI_GS_TaxonomyStateError"), { r = 0.85, g = 0.4, b = 0.35 }
	elseif ui._nativeCorpusLastReport then
		local finishedText = GlobalStorageSiK.SiK_UI.relativeAge(ui._nativeCorpusFinishedAtMs)
		ui._nativeCorpusFinishedAtText = finishedText
		stateText, stateColor = T("IGUI_GS_TaxonomyStateDone", finishedText), { r = 0.55, g = 0.8, b = 0.5 }
	else
		stateText, stateColor = T("IGUI_GS_TaxonomyStateIdle"), { r = 0.72, g = 0.75, b = 0.8 }
	end
	local function addStateLabel(host, widget)
		host:addChild(widget)
		ui._taxonomyTabWidgets[#ui._taxonomyTabWidgets + 1] = widget
	end
	local afterStateY = renderWrappedLines(ui, ui._corpusStatePool, stateText, pad, ui._corpusStateY, textW, addStateLabel)
	for i = 1, #ui._corpusStatePool do
		local lbl = ui._corpusStatePool[i]
		if lbl then lbl:setColor(stateColor.r, stateColor.g, stateColor.b) end
	end

	if ui.nativeCorpusBtn then
		local locked = ui._nativeCorpusRunning == true
		ui.nativeCorpusBtn._sikUiLocked = locked
		ui.nativeCorpusBtn:setEnable(not locked)
	end

	local scroll = ui.nativeCorpusSummaryScroll
	if not scroll then return end
	local scrollY = afterStateY + LINE_GAP + 6
	local scrollH = math.max(MIN_SUMMARY_SCROLL_H, (ui._corpusBottomLimit or scrollY) - scrollY)
	scroll:setY(scrollY)
	GlobalStorageSiK.TerminalScroll.resize(scroll, textW, scrollH)

	GlobalStorageSiK.TerminalScroll.clear(scroll)
	local contentW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local sy = 2

	local report = ui._nativeCorpusLastReport
	if not report then
		sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomyNoRunYet"), 4, sy, contentW - 8,
			GlobalStorageSiK.TerminalScroll.addChild)
		GlobalStorageSiK.TerminalScroll.finish(scroll, sy)
		return
	end

	sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomyCorpusVersionLine", tostring(report.corpusVersion)),
		4, sy, contentW - 8, GlobalStorageSiK.TerminalScroll.addChild)

	sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomyCorpusCountsLine",
		tostring(report.totalCases), tostring(report.applicableCases), tostring(report.absentCases),
		tostring(report.skippedCases), tostring(report.passedCases), tostring(report.failedCases)),
		4, sy, contentW - 8, GlobalStorageSiK.TerminalScroll.addChild)

	-- "Exactitud" simple (aciertos/aplicables), nunca llamada precision/
	-- recall (pedido explicito de sistemas - esos terminos exigirian una
	-- formula distinta que este corpus piloto no calcula).
	sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomyCorpusAccuracyLine",
		tostring(report.l1CorrectCount), tostring(report.l1Total),
		tostring(report.l2CorrectCount), tostring(report.l2Total),
		tostring(report.l3CorrectCount), tostring(report.l3Total)),
		4, sy, contentW - 8, GlobalStorageSiK.TerminalScroll.addChild)

	sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomyCorpusFailureKindsLine",
		tostring(report.classificationFailures), tostring(report.evidenceFailures),
		tostring(report.facetAttributeFailures), tostring(report.requiredMissingFailures)),
		4, sy, contentW - 8, GlobalStorageSiK.TerminalScroll.addChild)

	sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomyRunLine",
		tostring(report.sessionId or "?"), tostring(report.runId or "?")),
		4, sy, contentW - 8, GlobalStorageSiK.TerminalScroll.addChild)

	-- dev25/dev26 (pedido explicito de sistemas §4: "mostrar en su resumen
	-- el estado del bloque propio y sus razones mediante el layout envuelto
	-- existente") - status + razones ya vienen COMPACTOS del servidor
	-- (GS_NativeCorpusServer.lua), este bloque solo los envuelve/pinta.
	-- dev26: generalizado a una lista de bloques en vez de un solo caso
	-- fijo - "globalstoragesik" (dev25) y "tools" (dev26) comparten el
	-- mismo par de lineas, nunca una rama if/else por bloque.
	local BLOCK_STATUS_FIELDS = {
		{ blockName = "globalstoragesik", statusKey = "ownBlockStatus", reasonsKey = "ownBlockReasons" },
		{ blockName = "tools", statusKey = "toolsBlockStatus", reasonsKey = "toolsBlockReasons" },
		-- dev27: 3 bloques nuevos, mismo patron generico (nunca una rama
		-- if/else por bloque) - "combat"/"clothing_protection"/"containers".
		{ blockName = "combat", statusKey = "combatBlockStatus", reasonsKey = "combatBlockReasons" },
		{ blockName = "clothing_protection", statusKey = "clothingBlockStatus", reasonsKey = "clothingBlockReasons" },
		{ blockName = "containers", statusKey = "containersBlockStatus", reasonsKey = "containersBlockReasons" },
	}
	for i = 1, #BLOCK_STATUS_FIELDS do
		local status = report[BLOCK_STATUS_FIELDS[i].statusKey]
		if status then
			sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomyCorpusBlockStatusLine",
				BLOCK_STATUS_FIELDS[i].blockName, tostring(status)),
				4, sy, contentW - 8, GlobalStorageSiK.TerminalScroll.addChild)
			local reasons = report[BLOCK_STATUS_FIELDS[i].reasonsKey]
			if reasons and reasons ~= "" then
				sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomyCorpusBlockReasonsLine", tostring(reasons)),
					4, sy, contentW - 8, GlobalStorageSiK.TerminalScroll.addChild)
			end
		end
	end

	if report.fileName then
		sy = renderWrappedLines(scroll, {}, T("IGUI_GS_TaxonomyFileCorpus", tostring(report.fileName)),
			4, sy, contentW - 8, GlobalStorageSiK.TerminalScroll.addChild)
	end

	GlobalStorageSiK.TerminalScroll.finish(scroll, sy)
end

--- Envia el comando runNativeCorpus - guarda de un solo vuelo en CLIENTE
--- (ademas de la guarda de concurrencia propia en servidor, ver
--- GS_NativeCorpusServer.lua), con el mismo patron de correlacion
--- `requestId` ya cerrado en dev23 para la auditoria - completamente
--- independiente del `requestId` de GS_AdminDashboardAudit (contadores
--- separados en `ui`).
---@param ui table GS_AdminDashboardUI instance
function GlobalStorageSiK.AdminDashboardCorpus.runNativeCorpus(ui)
	if ui._nativeCorpusRunning then return end
	ui._nativeCorpusRequestId = (ui._nativeCorpusRequestId or 0) + 1
	ui._nativeCorpusRunning = true
	ui._nativeCorpusLastFailed = false
	GlobalStorageSiK.AdminDashboardCorpus.refreshSummary(ui)
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("runNativeCorpus", { requestId = ui._nativeCorpusRequestId })
	end
end

--- Llamado desde GlobalStorageSiK.AdminDashboard.onNativeCorpusSummary()
--- cuando llega "nativeCorpusSummary" del servidor.
---@param ui table
---@param report table
function GlobalStorageSiK.AdminDashboardCorpus.onSummary(ui, report)
	if report and report.requestId ~= nil and report.requestId ~= ui._nativeCorpusRequestId then
		return
	end
	ui._nativeCorpusRunning = false
	ui._nativeCorpusLastFailed = false
	ui._nativeCorpusLastReport = report
	ui._nativeCorpusFinishedAtMs = report and tonumber(report.finishedAtMs) or nil
	ui._nativeCorpusFinishedAtText = GlobalStorageSiK.SiK_UI.relativeAge(ui._nativeCorpusFinishedAtMs)
	GlobalStorageSiK.AdminDashboardCorpus.refreshSummary(ui)
end

--- Llamado desde GlobalStorageSiK.AdminDashboard.onActionResult() para
--- CUALQUIER actionResult recibido - solo actua si `action="runNativeCorpus"`
--- Y el `requestId` corresponde a la ejecucion en curso de ESTA suite (un
--- fallo de "runNativeAudit" u otra accion de red nunca la afecta).
---@param ui table
---@param args table|nil
function GlobalStorageSiK.AdminDashboardCorpus.onActionResult(ui, args)
	if not ui._nativeCorpusRunning then return end
	if not args or args.ok ~= false then return end
	if args.action ~= "runNativeCorpus" then return end
	if args.requestId ~= nil and args.requestId ~= ui._nativeCorpusRequestId then return end
	ui._nativeCorpusRunning = false
	ui._nativeCorpusLastFailed = true
	GlobalStorageSiK.AdminDashboardCorpus.refreshSummary(ui)
end

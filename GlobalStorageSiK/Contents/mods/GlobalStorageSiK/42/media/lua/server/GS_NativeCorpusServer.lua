--[[
	GlobalStorageSiK - Handler server del boton "Validar corpus"
	Autor: SiK
	Fecha: 2026-08-27

	dev24 (pedido explicito de sistemas): suite DIFERENCIADA de
	GS_NativeAuditServer.lua - guarda de concurrencia PROPIA
	(`nativeCorpusRunning`, independiente de `nativeAuditRunning`), comando
	propio (`runNativeCorpus`), respuesta propia (`nativeCorpusSummary`) -
	una respuesta nunca desbloquea ni sobrescribe el estado de la otra suite.
	Mismo patron de correlacion `requestId`/`action` ya cerrado en dev23
	para la auditoria de catalogo (ver GS_NativeAuditServer.lua).
]]

require "GS_NativeCorpus"

GlobalStorageSiK.NativeCorpusServer = GlobalStorageSiK.NativeCorpusServer or {}

local nativeCorpusRunning = false

---@param player table
---@param args table|nil
---@param requireServerModFn fun(player:table, action:string, networkId:any): boolean
---@param sendCommandFn fun(player:table, command:string, payload:table)
function GlobalStorageSiK.NativeCorpusServer.handle(player, args, requireServerModFn, sendCommandFn)
	if not requireServerModFn(player, "runNativeCorpus", nil) then return end
	local requestId = args and args.requestId

	if nativeCorpusRunning then
		sendCommandFn(player, "actionResult",
			{ ok = false, action = "runNativeCorpus", requestId = requestId,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_NativeCorpusBusyMsg") })
		return
	end

	nativeCorpusRunning = true
	local ok, report = pcall(GlobalStorageSiK.NativeCorpus.run)
	nativeCorpusRunning = false

	if not ok or not report then
		sendCommandFn(player, "actionResult",
			{ ok = false, action = "runNativeCorpus", requestId = requestId,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_NativeCorpusFailedMsg") })
		return
	end
	if report.aborted then
		sendCommandFn(player, "actionResult",
			{ ok = false, action = "runNativeCorpus", requestId = requestId,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_NativeAuditAbortedMsg", tostring(report.abortReason)) })
		return
	end

	GlobalStorageSiK.NativeCorpus.writeReportToFile(report)

	-- dev25/dev26 (pedido explicito de sistemas §4: "mostrar en su resumen
	-- el estado del bloque propio y sus razones... conservar en red
	-- unicamente el resumen acotado"): solo status + razones YA COMPACTAS
	-- viajan al cliente, uno por bloque con umbral formal - los contadores
	-- completos por bloque, el inventario y el detalle de divergencias
	-- siguen exclusivamente en GlobalStorageSiK_NativeCorpus.log. Nombres
	-- de campo explicitos (own.../tools...) en vez de una lista generica -
	-- el CALCULO server-side (GS_NativeCorpus.BLOCK_ACCEPTANCE_CONFIG) es
	-- el que es declarativo/generico, este payload solo expone los 2
	-- bloques que la matriz QA de sistemas comprueba por separado.
	local function blockSummary(blockName)
		local block = report.blockAcceptance and report.blockAcceptance[blockName]
		return (block and block.status) or "?", block and table.concat(block.reasons or {}, " | ") or ""
	end
	local ownBlockStatus, ownBlockReasons = blockSummary("globalstoragesik")
	local toolsBlockStatus, toolsBlockReasons = blockSummary("tools")
	-- dev27: 3 bloques nuevos, mismo patron explicito (nunca una lista
	-- generica en el payload de red - la matriz QA de sistemas comprueba
	-- cada bloque por su nombre de campo propio).
	local combatBlockStatus, combatBlockReasons = blockSummary("combat")
	local clothingBlockStatus, clothingBlockReasons = blockSummary("clothing_protection")
	local containersBlockStatus, containersBlockReasons = blockSummary("containers")

	-- Al cliente SOLO el resumen agregado - la lista detallada de
	-- divergencias se queda en GlobalStorageSiK_NativeCorpus.log (pedido
	-- explicito: "no enviarlos completos por red").
	sendCommandFn(player, "nativeCorpusSummary", {
		requestId = requestId,
		finishedAtMs = (getTimestampMs and getTimestampMs()) or 0,
		corpusVersion = report.corpusVersion,
		catalogEpoch = report.catalogEpoch,
		totalCases = report.totalCases,
		applicableCases = report.applicableCases,
		absentCases = report.absentCases,
		skippedCases = report.skippedCases,
		passedCases = report.passedCases,
		failedCases = report.failedCases,
		l1CorrectCount = report.l1CorrectCount, l1Total = report.l1Total,
		l2CorrectCount = report.l2CorrectCount, l2Total = report.l2Total,
		l3CorrectCount = report.l3CorrectCount, l3Total = report.l3Total,
		classificationFailures = report.classificationFailures,
		evidenceFailures = report.evidenceFailures,
		facetAttributeFailures = report.facetAttributeFailures,
		requiredMissingFailures = report.requiredMissingFailures,
		ownBlockStatus = ownBlockStatus,
		ownBlockReasons = ownBlockReasons,
		toolsBlockStatus = toolsBlockStatus,
		toolsBlockReasons = toolsBlockReasons,
		combatBlockStatus = combatBlockStatus,
		combatBlockReasons = combatBlockReasons,
		clothingBlockStatus = clothingBlockStatus,
		clothingBlockReasons = clothingBlockReasons,
		containersBlockStatus = containersBlockStatus,
		containersBlockReasons = containersBlockReasons,
		timeMs = report.timeMs,
		fileName = "GlobalStorageSiK_NativeCorpus.log",
	})
end

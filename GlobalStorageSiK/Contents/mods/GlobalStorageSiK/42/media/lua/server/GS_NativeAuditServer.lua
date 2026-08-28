--[[
	GlobalStorageSiK - Handler server del boton "Auditar catalogo"
	Autor: SiK
	Fecha: 2026-08-27

	dev14 (pedido explicito de sistemas: "GS_Server.lua en 146/150 locales -
	no conviene añadir mas locales al gran dispatcher... extraer
	runNativeAudit a un pequeño handler server dedicado"). Extraccion
	PURAMENTE ESTRUCTURAL - mismo protocolo, mismos permisos, misma
	respuesta al cliente, mismo comportamiento. `requireServerMod` y
	`gsSendServerCommand` siguen siendo funciones locales de GS_Server.lua
	(nunca expuestas globalmente sin necesidad real) - se pasan como
	parametros desde el unico punto de llamada, sin cambiar su visibilidad
	ni su implementacion.
]]

require "GS_NativeAudit"
require "GS_DiagnosticsSession"

GlobalStorageSiK.NativeAuditServer = GlobalStorageSiK.NativeAuditServer or {}

-- Guarda de concurrencia - vivia como local de modulo en GS_Server.lua,
-- ahora vive aqui junto al resto del estado de esta herramienta.
local nativeAuditRunning = false

-- dev23 (pedido explicito de sistemas: "el boton solo debe desbloquearse
-- por la respuesta correspondiente a su propia ejecucion" - cierra el
-- limite aceptado de dev22, un actionResult de OTRA accion podia liberar el
-- boton antes de tiempo). Correlacion SIN protocolo grande: el cliente manda
-- un requestId propio en `args.requestId` (entero incremental local, ver
-- GS_AdminDashboard_Audit.lua) y este handler lo reenvia TAL CUAL en las 4
-- rutas de respuesta (ocupado/fallo/abortado/exito) - el cliente ignora
-- cualquier respuesta cuyo requestId no coincida con la ultima que envio.
---@param player table
---@param args table|nil
---@param requireServerModFn fun(player:table, action:string, networkId:any): boolean
---@param sendCommandFn fun(player:table, command:string, payload:table)
function GlobalStorageSiK.NativeAuditServer.handle(player, args, requireServerModFn, sendCommandFn)
	if not requireServerModFn(player, "runNativeAudit", nil) then return end
	local requestId = args and args.requestId

	if nativeAuditRunning then
		sendCommandFn(player, "actionResult",
			{ ok = false, action = "runNativeAudit", requestId = requestId,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_NativeAuditBusyMsg") })
		return
	end

	nativeAuditRunning = true
	local ok, report = pcall(GlobalStorageSiK.NativeAudit.run)
	nativeAuditRunning = false

	if not ok or not report then
		sendCommandFn(player, "actionResult",
			{ ok = false, action = "runNativeAudit", requestId = requestId,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_NativeAuditFailedMsg") })
		return
	end
	if report.aborted then
		sendCommandFn(player, "actionResult",
			{ ok = false, action = "runNativeAudit", requestId = requestId,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_NativeAuditAbortedMsg", tostring(report.abortReason)) })
		return
	end

	-- dev13→dev14 (hallazgo de sistemas): el inventario debe intentarse
	-- ANTES del log principal, para que este pueda informar
	-- GENERADO/NO GENERADO con la causa real en vez de anunciar el
	-- fichero a ciegas.
	local diagnosticRun = GlobalStorageSiK.DiagnosticsSession.beginRun(
		"taxonomy", { "audit", "unclassified" })
	report.diagnosticSessionId = diagnosticRun.sessionId
	report.diagnosticRunId = diagnosticRun.runId
	report.diagnosticReportFile = diagnosticRun.paths.audit
	report.diagnosticUnclassifiedFile = diagnosticRun.paths.unclassified
	local tsvOk, tsvErr = GlobalStorageSiK.NativeAudit.writeUnclassifiedTsv(report)
	report.unclassifiedTsvOk = tsvOk
	report.unclassifiedTsvError = tsvErr
	if not tsvOk and GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.warn("NativeAudit", "writeUnclassifiedTsv fallo: " .. tostring(tsvErr))
	end
	GlobalStorageSiK.NativeAudit.writeReportToFile(report)

	-- dev22 (pedido explicito de sistemas, pestaña Taxonomia del panel de
	-- staff: "resultado agregado del probe tier/variant si puede incluirse
	-- en el resumen sin enviar el informe completo") - cuenta match=true
	-- sobre el texto ya generado de cada linea del probe (mismo formato que
	-- GS_NativeAudit.lua escribe a fichero), sin reconstruir ningun dato
	-- nuevo ni enviar las lineas en si.
	local tierVariantTotal = #(report.samples and report.samples.tierVariantProbe or {})
	local tierVariantMatched = 0
	for i = 1, tierVariantTotal do
		if tostring(report.samples.tierVariantProbe[i]):find("match=true", 1, true) then
			tierVariantMatched = tierVariantMatched + 1
		end
	end

	-- Al cliente SOLO el resumen (pedido explicito) - el informe completo,
	-- con muestras, se queda en el fichero de diagnostico del servidor.
	-- dev23: `finishedAtMs` va aqui (hora real de finalizacion en el
	-- servidor) para que el cliente la registre UNA vez al recibir la
	-- respuesta - pedido explicito de sistemas ("no recalcularla cada vez
	-- que se repinta el resumen", ver refreshSummary en
	-- GS_AdminDashboard_Audit.lua). `catalogFingerprintDigest`/
	-- `activeModCount`/`gameBuildVersion` son la representacion compacta
	-- para UI (ver GS_CatalogManager.lua) - `catalogFingerprint` completo se
	-- mantiene en el payload por compatibilidad/depuracion, pero la pestaña
	-- Taxonomia ya no lo usa para pintar.
	sendCommandFn(player, "nativeAuditSummary", {
		requestId = requestId,
		sessionId = diagnosticRun.sessionId,
		runId = diagnosticRun.runId,
		finishedAtMs = (getTimestampMs and getTimestampMs()) or 0,
		totalTypes = report.totalTypes,
		pending = report.pending,
		unclassified = report.unclassified,
		invalidPath = report.invalidPath,
		classifierErrors = report.classifierErrors,
		timeMs = report.timeMs,
		catalogEpoch = report.catalogEpoch,
		catalogFingerprint = report.catalogFingerprint,
		catalogFingerprintDigest = report.catalogFingerprintDigest,
		activeModCount = report.activeModCount,
		gameBuildVersion = report.gameBuildVersion,
		tierVariantMatched = tierVariantMatched,
		tierVariantTotal = tierVariantTotal,
		fileName = diagnosticRun.paths.audit,
		unclassifiedFileName = diagnosticRun.paths.unclassified,
	})
end

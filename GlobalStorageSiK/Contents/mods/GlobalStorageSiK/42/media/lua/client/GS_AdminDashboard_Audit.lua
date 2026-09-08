-- Global Storage SiK - independent audit request state for Staff.
-- TaxonomyView owns compact Blocks and wrapping. Full fingerprints remain in
-- server logs; readable details are available on the summary tooltip.
-- The former fixed-label layout overflowed with long fingerprints (dev23).
-- Keep complete text wrapped and measure it whenever width or data changes.
require "GS_I18n"
local View = require "GS_AdminDashboard_TaxonomyView"
GlobalStorageSiK.AdminDashboardAudit = GlobalStorageSiK.AdminDashboardAudit or {}

local function relativeAge(value)
 local dashboard = GlobalStorageSiK.AdminDashboard
 return dashboard and dashboard.relativeAge and dashboard.relativeAge(value) or "?"
end

function GlobalStorageSiK.AdminDashboardAudit.build(ui)
 View.build(ui, "audit")
end

function GlobalStorageSiK.AdminDashboardAudit.refreshSummary(ui)
 View.refresh(ui, "audit")
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
	ui._nativeAuditFinishedAtText = relativeAge(ui._nativeAuditFinishedAtMs)
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

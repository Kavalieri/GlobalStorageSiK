-- Global Storage SiK - independent corpus request state for Staff.
-- TaxonomyView owns compact Blocks and wrapping. Full fingerprints remain in
-- server logs; readable details are available on the summary tooltip.
-- The former fixed-label layout overflowed with long fingerprints (dev23).
-- Keep complete text wrapped and measure it whenever width or data changes.
require "GS_I18n"
local View = require "GS_AdminDashboard_TaxonomyView"
GlobalStorageSiK.AdminDashboardCorpus = GlobalStorageSiK.AdminDashboardCorpus or {}

local function relativeAge(value)
 local dashboard = GlobalStorageSiK.AdminDashboard
 return dashboard and dashboard.relativeAge and dashboard.relativeAge(value) or "?"
end

function GlobalStorageSiK.AdminDashboardCorpus.build(ui)
 View.build(ui, "corpus")
end

function GlobalStorageSiK.AdminDashboardCorpus.refreshSummary(ui)
 View.refresh(ui, "corpus")
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
	ui._nativeCorpusFinishedAtText = relativeAge(ui._nativeCorpusFinishedAtMs)
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

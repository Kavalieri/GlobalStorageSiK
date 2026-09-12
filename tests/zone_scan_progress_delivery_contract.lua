-- Regression contract for the complete server -> client -> header progress path.
-- This prevents a scan from remaining visually at 0/N while the incremental
-- server job is still advancing.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("zone_scan_progress_delivery_contract")

local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/"
local function read(path)
	local file = assert(io.open(root .. path, "rb"), path)
	local source = file:read("*a")
	file:close()
	return source
end

local job = read("server/GS_ZoneScanJob.lua")
local server = read("server/GS_Server.lua")
local client = read("client/GS_Client.lua")
local terminal = read("client/GS_TerminalUI.lua")

Support.check(suite, "scan job publishes bounded fractional progress", function()
	assert(job:find("local function progressStatus%(job%)"), "missing progress status builder")
	assert(job:find("progressDone = math%.min%(total %* 0%.99, completed %+ fraction%)"),
		"scan progress must include the current zone fraction and stay below completion until commit")
	assert(job:find("now %- %(job%.lastUiProgressMs or 0%) >= 250"),
		"progress publication is not throttled")
	assert(job:find("onNetworkScanProgress%(job%.networkId"),
		"scan job does not publish progress to the server bridge")
	return true
end)

Support.check(suite, "server sends only the lightweight progress event", function()
	assert(server:find("function GlobalStorageSiK%.Server%.onNetworkScanProgress"),
		"missing server progress bridge")
	assert(server:find('gsSendServerCommand%(player, "scanProgress", status%)'),
		"server does not send scanProgress")
	return true
end)

Support.check(suite, "client updates the active matching terminal without rebuilding rows", function()
	assert(client:find('if command == "scanProgress" then', 1, true),
		"client does not consume scanProgress")
	assert(client:find("ui.terminalState.networkId == args.networkId", 1, true),
		"progress is not scoped to the matching terminal network")
	assert(client:find("ui:syncHeaderChrome()", 1, true),
		"progress does not refresh header chrome")
	local start = assert(client:find('if command == "scanProgress" then', 1, true))
	local finish = assert(client:find('elseif command == "actionResult" then', start, true))
	local branch = client:sub(start, finish)
	assert(not branch:find("refreshItemsTab", 1, true),
		"progress event rebuilds the warehouse table")
	return true
end)

Support.check(suite, "header consumes real progress and a short scan label", function()
	assert(terminal:find("local done = scan.progressDone or scan.zonesDone", 1, true),
		"header ignores fractional progress")
	assert(terminal:find('statusLabel, statusTone = T("IGUI_GS_ScanRunningShort")', 1, true),
		"header no longer uses the approved short scan label")
	assert(not terminal:find('operationLabel("IGUI_GS_ScanRunningShort"', 1, true),
		"scan progress duplicated the header label in the progress bar")
	return true
end)

Support.finish(suite)

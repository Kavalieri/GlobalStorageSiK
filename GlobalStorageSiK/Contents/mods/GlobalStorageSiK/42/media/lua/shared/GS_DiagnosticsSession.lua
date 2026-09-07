--[[
	GlobalStorageSiK - aislamiento temporal de evidencias QA por sesion/run
	Core 1.4.3-dev28.2

	Todo nombre devuelto es relativo a <Zomboid>/Lua/. El modulo no transmite
	contenido ni conoce UI; solo reserva rutas, evita sobrescrituras y mantiene
	un session.json pequeño y sin datos del mundo.
]]

require "GS_Config"

GlobalStorageSiK.DiagnosticsSession = GlobalStorageSiK.DiagnosticsSession or {}
local D = GlobalStorageSiK.DiagnosticsSession

local state = D._state

local function nowMs()
	return (getTimestampMs and getTimestampMs()) or 0
end

local function jsonEscape(value)
	local text = tostring(value or "")
	text = text:gsub("\\", "\\\\")
	text = text:gsub('"', '\\"')
	text = text:gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
	return text
end

local function ensureState()
	if state then return state end
	local startedMs = nowMs()
	local utc = "?"
	if os and os.date then
		local ok, value = pcall(os.date, "!%Y-%m-%dT%H:%M:%SZ", math.floor(startedMs / 1000))
		if ok and value then utc = tostring(value) end
	end
	state = {
		sessionId = "gs-" .. tostring(math.max(0, math.floor(startedMs))),
		startedAtUtc = utc,
		nextRunId = 0,
		suites = {},
		files = {},
	}
	D._state = state
	return state
end

local function sortedKeys(set)
	local list = {}
	for key, enabled in pairs(set or {}) do
		if enabled then list[#list + 1] = key end
	end
	table.sort(list)
	return list
end

local function writeManifest()
	if not getFileWriter then return false end
	local s = ensureState()
	local path = "SiKDiagnostics/GlobalStorageSiK/" .. s.sessionId .. "/session.json"
	s.files[path] = true
	local ok, writer = pcall(getFileWriter, path, true, false)
	if not ok or not writer then return false end
	local suites = sortedKeys(s.suites)
	local files = sortedKeys(s.files)
	local modVersion = GlobalStorageSiK.Config and GlobalStorageSiK.Config.MOD_VERSION
	if modVersion == nil or tostring(modVersion) == "" then modVersion = "?" end
	local okWrite = pcall(function()
		writer:write("{\r\n")
		writer:write('  "schemaVersion": "1.0",\r\n')
		writer:write('  "modId": "GlobalStorageSiK",\r\n')
		writer:write('  "modVersion": "' .. jsonEscape(modVersion) .. '",\r\n')
		writer:write('  "sessionId": "' .. jsonEscape(s.sessionId) .. '",\r\n')
		writer:write('  "startedAtUtc": "' .. jsonEscape(s.startedAtUtc) .. '",\r\n')
		writer:write('  "suites": [')
		for i = 1, #suites do
			if i > 1 then writer:write(", ") end
			writer:write('"' .. jsonEscape(suites[i]) .. '"')
		end
		writer:write("],\r\n  \"files\": [")
		for i = 1, #files do
			if i > 1 then writer:write(", ") end
			writer:write('"' .. jsonEscape(files[i]) .. '"')
		end
		writer:write("]\r\n}\r\n")
	end)
	pcall(function() writer:close() end)
	return okWrite == true
end

---@param suite string taxonomy|permissions|debug
---@param kinds string[] nombres de fichero sin extension
---@return table
function D.beginRun(suite, kinds)
	local s = ensureState()
	s.nextRunId = s.nextRunId + 1
	local runId = string.format("%06d", s.nextRunId)
	local paths = {}
	local suiteName = tostring(suite or "debug")
	for i = 1, #(kinds or {}) do
		local kind = tostring(kinds[i])
		local path = "SiKDiagnostics/GlobalStorageSiK/" .. s.sessionId .. "/"
			.. suiteName .. "/" .. kind .. "-" .. runId .. ".log"
		paths[kind] = path
		s.files[path] = true
	end
	s.suites[suiteName] = true
	writeManifest()
	return { sessionId = s.sessionId, runId = runId, paths = paths }
end

function D.getSessionId()
	return ensureState().sessionId
end

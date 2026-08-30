-- Focal executable contract for GS_Server.onNetworkScanComplete.
-- Only the handler body is evaluated with deterministic dependencies; loading
-- the full server or Project Zomboid runtime would hide the caller contract.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("network_scan_complete_staging_contract")

local SERVER = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_Server.lua"

local function read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a")
	file:close()
	return text
end

local function section(text, first, last)
	local from = assert(text:find(first, 1, true), "missing " .. first)
	local to = assert(text:find(last, from + #first, true), "missing " .. last)
	return text:sub(from, to - 1)
end

local serverSource = read(SERVER)
local handlerSource = section(serverSource,
	"function GlobalStorageSiK.Server.onNetworkScanComplete",
	"function GlobalStorageSiK.Server.onNetworkScanFailed")

local factorySource = [[
return function(deps)
	local GlobalStorageSiK = deps.GlobalStorageSiK
	local forEachOnlinePlayer = deps.forEachOnlinePlayer
	local isTerminalWatcher = deps.isTerminalWatcher
	local scheduleSnapshotSync = deps.scheduleSnapshotSync
	local gsSendServerCommand = deps.gsSendServerCommand
	local scanResult = deps.scanResult
	local pushTerminalState = deps.pushTerminalState
	local pendingSnapshotSync = deps.pendingSnapshotSync
]] .. handlerSource .. [[
	return GlobalStorageSiK.Server.onNetworkScanComplete
end
]]

local factory = assert(loadstring(factorySource, "@network_scan_complete_handler"))()

local function newHarness(currentRevision)
	local evidence = {
		retries = {}, commands = {}, snapshots = 0, bumps = 0,
		setSnapshots = {}, overrides = {}, warnings = {},
	}
	local player = { getUsername = function() return "Kava" end }
	local GS = {
		Server = {},
		Index = {
			getInventoryRevision = function() return currentRevision end,
			bumpInventoryRevision = function()
				evidence.bumps = evidence.bumps + 1
				currentRevision = currentRevision + 1
				return currentRevision
			end,
			setSnapshotRevision = function(networkId, revision)
				evidence.setSnapshots[#evidence.setSnapshots + 1] = {
					networkId = networkId, revision = revision,
				}
			end,
		},
		PlayerUtils = {
			resolveByUsername = function(username)
				return username == "Kava" and player or nil
			end,
		},
		ZoneScanJob = {
			overrideTerminalState = function(networkId, state, reason)
				evidence.overrides[#evidence.overrides + 1] = {
					networkId = networkId, state = state, reason = reason,
				}
			end,
		},
		Permissions = {
			canAccess = function() return true end,
		},
		I18n = {
			remote = function(key) return key end,
		},
		Log = {
			warn = function(...)
				evidence.warnings[#evidence.warnings + 1] = { ... }
			end,
		},
	}
	local deps = {
		GlobalStorageSiK = GS,
		pendingSnapshotSync = {},
		forEachOnlinePlayer = function(callback) callback(player) end,
		isTerminalWatcher = function(candidate, networkId)
			return candidate == player and networkId == "network-A"
		end,
		scheduleSnapshotSync = function(networkId, retryPlayer, revision)
			evidence.retries[#evidence.retries + 1] = {
				networkId = networkId, player = retryPlayer, revision = revision,
			}
		end,
		gsSendServerCommand = function(target, command, payload)
			evidence.commands[#evidence.commands + 1] = {
				target = target, command = command, payload = payload,
			}
		end,
		scanResult = function(networkId, state, key, reason, summary)
			return {
				networkId = networkId, state = state, key = key,
				reason = reason, summary = summary,
			}
		end,
		pushTerminalState = function()
			evidence.snapshots = evidence.snapshots + 1
		end,
	}
	return factory(deps), evidence, player
end

Support.check(suite, "discarded FAILED revision retries without publishing snapshot", function()
	local handler, evidence, player = newHarness(11)
	local summary = {
		_terminalState = "FAILED", _stagedDiscarded = true,
		_startRevision = 10, zones = 2,
	}
	handler("network-A", summary, { Kava = "potato" })
	assert(#evidence.retries == 1, "stale staging did not schedule exactly one retry")
	assert(evidence.retries[1].player == player and evidence.retries[1].revision == 11,
		"retry lost watcher or current revision")
	assert(evidence.snapshots == 0, "stale staging published terminal snapshot")
	assert(evidence.bumps == 0 and #evidence.setSnapshots == 0,
		"stale staging certified a new snapshot revision")
	assert(#evidence.overrides == 1
		and evidence.overrides[1].state == "FAILED"
		and evidence.overrides[1].reason == "snapshot_stale",
		"stale staging did not preserve explicit snapshot_stale state")
	assert(#evidence.commands == 1
		and evidence.commands[1].command == "actionResult"
		and evidence.commands[1].payload.state == "FAILED"
		and evidence.commands[1].payload.reason == "snapshot_stale",
		"watcher did not receive the non-publishing stale result")
	return true
end)

Support.check(suite, "genuine FAILED scan remains zone failure without retry", function()
	local handler, evidence = newHarness(20)
	local summary = {
		_terminalState = "FAILED", _startRevision = 20,
		failedZones = 1,
	}
	handler("network-A", summary, { Kava = "query" })
	assert(#evidence.retries == 0, "genuine zone failure was converted into retry")
	assert(evidence.snapshots == 1, "genuine failure did not publish failure state")
	assert(evidence.bumps == 0 and #evidence.setSnapshots == 0,
		"genuine failure certified a successful snapshot")
	assert(#evidence.overrides == 0, "genuine failure was overwritten as stale")
	assert(#evidence.commands == 1
		and evidence.commands[1].payload.state == "FAILED"
		and evidence.commands[1].payload.reason == "zone_error",
		"genuine failure lost zone_error semantics")
	return true
end)

Support.check(suite, "stable COMPLETED scan still publishes and certifies once", function()
	local handler, evidence = newHarness(30)
	local summary = {
		_terminalState = "COMPLETED", _startRevision = 30,
		_freshSnapshotScope = "network", _background = false,
		durationMs = 5, nodesScanned = 2, itemInstances = 4,
		distinctTypes = 3, snapshotRows = 4,
	}
	handler("network-A", summary, { Kava = "query" })
	assert(#evidence.retries == 0, "stable scan scheduled retry")
	assert(evidence.bumps == 1 and #evidence.setSnapshots == 1,
		"stable scan did not certify exactly once")
	assert(evidence.setSnapshots[1].revision == 31,
		"stable snapshot stored the wrong revision")
	assert(evidence.snapshots == 1, "stable scan did not publish exactly once")
	assert(#evidence.commands == 1
		and evidence.commands[1].payload.state == "COMPLETED"
		and evidence.commands[1].payload.reason == "complete",
		"stable scan lost COMPLETED semantics")
	return true
end)

Support.finish(suite)

-- Author-side contract for bounded operation pacing.
-- It executes the pure resolver and binds its immutable snapshot to every
-- transfer/auto-sort consumer without simulating Project Zomboid runtime.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("operation_pacing_contract")

local ROOT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/"
local SHARED = ROOT .. "shared/"
local CLIENT = ROOT .. "client/"
local SERVER = ROOT .. "server/"
local PACING_PATH = SHARED .. "GS_OperationPacing.lua"

local function read(path)
	local file = io.open(path, "rb")
	if not file then return nil end
	local text = file:read("*a")
	file:close()
	return text
end

local function contains(text, needle, label)
	assert(text and text:find(needle, 1, true), label or ("missing " .. needle))
end

local function excludes(text, needle, label)
	assert(text and not text:find(needle, 1, true), label or ("unexpected " .. needle))
end

local function countPlain(text, needle)
	local count, at = 0, 1
	while text do
		local found = text:find(needle, at, true)
		if not found then return count end
		count = count + 1
		at = found + #needle
	end
	return count
end

local pacingSource = read(PACING_PATH)
local sources = {
	transferQueue = read(CLIENT .. "GS_TransferQueue.lua"),
	withdrawClient = read(CLIENT .. "GS_WithdrawClient.lua"),
	deposit = read(SHARED .. "GS_Deposit.lua"),
	withdraw = read(SHARED .. "GS_Transfer.lua"),
	server = read(SERVER .. "GS_Server.lua"),
	redistributeJob = read(SERVER .. "GS_RedistributeJob.lua"),
	redistribute = read(SHARED .. "GS_Redistribute.lua"),
}

local sandboxValues = {}
GlobalStorageSiK = GlobalStorageSiK or {}
GlobalStorageSiK.Sandbox = {
	getLocalPerformanceProfile = function() return sandboxValues.mode end,
	getLocalBatchUnits = function() return sandboxValues.batchUnits end,
	getLocalBatchDelayMs = function() return sandboxValues.batchDelayMs end,
	getLocalAutoSortMovesPerStep = function() return sandboxValues.maxMovesPerStep end,
	getLocalAutoSortMoveDelayMs = function() return sandboxValues.moveDelayMs end,
	getLocalInspectedPerStep = function() return sandboxValues.inspectedPerStep end,
	getLocalCpuBudgetMs = function() return sandboxValues.cpuBudgetMs end,
}
local runtime = { multiplayerActive = false, activePlayers = 1, onlinePlayers = 1 }
GlobalStorageSiK.isMultiplayerActive = function() return runtime.multiplayerActive end
getNumActivePlayers = function() return runtime.activePlayers end
getOnlinePlayers = function()
	return { size = function() return runtime.onlinePlayers end }
end

package.loaded["GS_Config"] = true
package.loaded["GS_Sandbox"] = true
if pacingSource then
	local loaded, detail = pcall(dofile, PACING_PATH)
	if not loaded then
		Support.fail(suite, "OperationPacing module loads in Lua 5.1", detail)
	end
else
	Support.blocked(suite, "OperationPacing module exists",
		"missing shared/GS_OperationPacing.lua")
end

local function context(operationType)
	return { operationType = operationType }
end

local function assertProfile(actual, mode, effectiveProfile, expected)
	assert(type(actual) == "table", "resolve must return a profile table")
	assert(actual.mode == mode, "mode=" .. tostring(actual.mode) .. " expected=" .. mode)
	assert(actual.effectiveProfile == effectiveProfile,
		"effectiveProfile=" .. tostring(actual.effectiveProfile)
			.. " expected=" .. effectiveProfile)
	for key, value in pairs(expected) do
		assert(actual[key] == value,
			key .. "=" .. tostring(actual[key]) .. " expected=" .. tostring(value))
	end
end

local SAFE = {
	batchUnits = 10, batchDelayMs = 400, maxMovesPerStep = 2,
	moveDelayMs = 1000, inspectedPerStep = 25, cpuBudgetMs = 5,
}
local FAST = {
	batchUnits = 25, batchDelayMs = 75, maxMovesPerStep = 5,
	moveDelayMs = 150, inspectedPerStep = 100, cpuBudgetMs = 5,
}

local resolve = GlobalStorageSiK.OperationPacing
	and GlobalStorageSiK.OperationPacing.resolve
if type(resolve) ~= "function" then
	Support.blocked(suite, "OperationPacing.resolve is public",
		"missing GlobalStorageSiK.OperationPacing.resolve(context)")
else
	Support.check(suite, "SAFE and FAST expose the exact canonical limits", function()
		runtime = { multiplayerActive = false, activePlayers = 1, onlinePlayers = 1 }
		sandboxValues.mode = 1
		assertProfile(resolve(context("deposit")), "local_single_player", "safe", SAFE)
		sandboxValues.mode = 2
		assertProfile(resolve(context("withdraw")), "local_single_player", "fast", FAST)
		return true
	end)

	Support.check(suite, "CUSTOM clamps every sandbox value at both boundaries", function()
		sandboxValues = {
			mode = 3, batchUnits = -20, batchDelayMs = -1,
			maxMovesPerStep = 0, moveDelayMs = -4, inspectedPerStep = 0,
			cpuBudgetMs = 0,
		}
		runtime = { multiplayerActive = false, activePlayers = 1, onlinePlayers = 1 }
		assertProfile(resolve(context("auto_sort")), "local_single_player", "custom", {
			batchUnits = 1, batchDelayMs = 0, maxMovesPerStep = 1,
			moveDelayMs = 0, inspectedPerStep = 10, cpuBudgetMs = 1,
		})
		sandboxValues = {
			mode = 3, batchUnits = 1000, batchDelayMs = 1001,
			maxMovesPerStep = 200, moveDelayMs = 9999, inspectedPerStep = 9999,
			cpuBudgetMs = 99,
		}
		assertProfile(resolve(context("auto_sort")), "local_single_player", "custom", {
			batchUnits = 100, batchDelayMs = 1000, maxMovesPerStep = 20,
			moveDelayMs = 2000, inspectedPerStep = 500, cpuBudgetMs = 15,
		})
		return true
	end)

	Support.check(suite, "host alone keeps requested profile; remote MP and split-screen force safe", function()
		sandboxValues.mode = 2
		local cases = {
			{ name = "host one human", runtime = {
				multiplayerActive = false, activePlayers = 1, onlinePlayers = 1,
			}, mode = "local_single_player", profile = "fast", values = FAST },
			{ name = "dedicated process/client", runtime = {
				multiplayerActive = true, activePlayers = 1, onlinePlayers = 1,
			}, mode = "multiplayer_safe", profile = "safe", values = SAFE },
			{ name = "host with remote human", runtime = {
				multiplayerActive = false, activePlayers = 1, onlinePlayers = 2,
			}, mode = "multiplayer_safe", profile = "safe", values = SAFE },
			{ name = "SP split-screen", runtime = {
				multiplayerActive = false, activePlayers = 2, onlinePlayers = 1,
			}, mode = "multiplayer_safe", profile = "safe", values = SAFE },
		}
		for i = 1, #cases do
			runtime = cases[i].runtime
			local profile = resolve(context("withdraw"))
			assertProfile(profile, cases[i].mode, cases[i].profile, cases[i].values)
		end
		return true
	end)

	Support.check(suite, "resolve returns an isolated immutable operation snapshot", function()
		runtime = { multiplayerActive = false, activePlayers = 1, onlinePlayers = 1 }
		sandboxValues.mode = 1
		local first = resolve(context("deposit"))
		local second = resolve(context("deposit"))
		assert(first ~= second, "profiles are a shared mutable table")
		first.batchUnits = 99
		assert(second.batchUnits == SAFE.batchUnits,
			"mutating one operation changes another operation")
		sandboxValues.batchUnits = 77
		assert(second.batchUnits == SAFE.batchUnits,
			"operation snapshot changes when sandbox changes")
		if type(GlobalStorageSiK.OperationPacing.forOperation) == "function" then
			sandboxValues.mode = 1
			local cached = GlobalStorageSiK.OperationPacing.forOperation("op-immutable", context("deposit"))
			sandboxValues.mode = 2
			assert(GlobalStorageSiK.OperationPacing.forOperation("op-immutable", context("deposit")) == cached,
				"active operation re-resolves after sandbox changes")
			GlobalStorageSiK.OperationPacing.release("op-immutable")
			assert(GlobalStorageSiK.OperationPacing.forOperation("op-immutable", context("deposit")) ~= cached,
				"released operation retains its old pacing snapshot")
			GlobalStorageSiK.OperationPacing.release("op-immutable")
		end
		return true
	end)
end

Support.check(suite, "client queues resolve once and keep pacing on the operation", function()
	for _, key in ipairs({ "transferQueue", "withdrawClient" }) do
		local source = sources[key]
		contains(source, 'require "GS_OperationPacing"', key .. " does not load pacing")
		contains(source, "OperationPacing.resolve", key .. " never resolves pacing")
		contains(source, ".pacing", key .. " does not snapshot pacing on its job/operation")
		contains(source, "batchDelayMs", key .. " ignores the client-side delay")
		assert(countPlain(source, "OperationPacing.resolve") == 1,
			key .. " re-resolves mutable pacing during one operation")
	end
	return true
end)

Support.check(suite, "authoritative deposit and withdrawal resolve their own limits", function()
	contains(sources.server, 'require "GS_OperationPacing"',
		"authoritative server does not load pacing")
	contains(sources.server, "OperationPacing.forOperation",
		"server does not preserve one profile across micro-batches")
	contains(sources.server, "OperationPacing.release",
		"server does not clean completed/cancelled pacing snapshots")
	contains(sources.server, "maxItemsPerTick", "server does not cap authoritative deposit")
	contains(sources.server, "Transfer.withdrawType",
		"server does not invoke the capped authoritative withdrawal helper")
	contains(sources.server, "pacing.batchUnits",
		"server does not pass its own batch limit to deposit/withdraw")
	excludes(sources.server, "args.batchUnits", "server trusts a client batch size")
	excludes(sources.server, "args.pacing.", "server trusts a client profile")
	for _, key in ipairs({ "deposit", "withdraw" }) do
		excludes(sources[key], "OperationPacing.resolve",
			key .. " re-resolves the server snapshot inside a shared helper")
	end
	contains(sources.deposit, "maxItemsPerTick", "Deposit does not consume the server limit")
	contains(sources.withdraw, "maxUnits", "Transfer does not consume the server limit")
	return true
end)

Support.check(suite, "Auto-Sort snapshots once in its job and passes limits to Redistribute", function()
	contains(sources.redistributeJob, 'require "GS_OperationPacing"',
		"RedistributeJob does not load pacing")
	contains(sources.redistributeJob, "OperationPacing.resolve",
		"RedistributeJob does not snapshot pacing at start")
	contains(sources.redistributeJob, ".pacing",
		"RedistributeJob does not retain the immutable snapshot")
	assert(countPlain(sources.redistributeJob, "OperationPacing.resolve") == 1,
		"RedistributeJob re-resolves pacing while active")
	contains(sources.redistributeJob, "job.session, job.pacing",
		"RedistributeJob does not pass its original snapshot to Redistribute")
	contains(sources.redistribute, "session.pacing = pacing or GlobalStorageSiK.OperationPacing.resolve",
		"direct Redistribute fallback is not saved on its new session")
	contains(sources.redistribute, "local effectivePacing = session.pacing",
		"Redistribute does not prefer the immutable session snapshot")
	for _, field in ipairs({ "maxMovesPerStep", "inspectedPerStep", "cpuBudgetMs" }) do
		contains(sources.redistribute, field, "Redistribute ignores pacing." .. field)
	end
	contains(sources.redistributeJob, "moveDelayMs",
		"RedistributeJob ignores pacing.moveDelayMs between steps")
	return true
end)

Support.check(suite, "all three operation families declare their pacing context", function()
	local clientCombined = sources.transferQueue .. sources.withdrawClient
	local serverCombined = sources.deposit .. sources.withdraw
	local sortCombined = sources.redistributeJob .. sources.redistribute
	contains(clientCombined .. serverCombined, "deposit", "deposit context is not declared")
	contains(clientCombined .. serverCombined, "withdraw", "withdraw context is not declared")
	assert(sortCombined:find("auto_sort", 1, true) or sortCombined:find("autosort", 1, true),
		"Auto-Sort context is not declared")
	return true
end)

Support.check(suite, "pacing never blocks a thread or introduces an unlimited loop", function()
	local combined = (pacingSource or "")
	for _, source in pairs(sources) do combined = combined .. source end
	for _, forbidden in ipairs({ "while true do", "socket.sleep", "os.execute", "Thread.sleep", "sleep(" }) do
		excludes(combined, forbidden, "blocking/unbounded route: " .. forbidden)
	end
	return true
end)

Support.check(suite, "each family emits one complete aggregate and cleans its state", function()
	local families = {
		deposit = sources.transferQueue,
		withdraw = sources.withdrawClient,
		autosort = sources.redistributeJob,
	}
	local missing = {}
	for name, source in pairs(families) do
		if not source:find("Log.", 1, true) then missing[#missing + 1] = name .. ".log" end
		if not source:find("OperationPacing.describe", 1, true) then
			missing[#missing + 1] = name .. ".mode/profile/limits"
		end
		for _, field in ipairs({
			"inspected", "moved", "skipped", "batches", "budgetExhaustions",
			"error", "cancel", "timeout",
		}) do
			if not source:find(field, 1, true) then
				missing[#missing + 1] = name .. "." .. field
			end
		end
		if not (source:find("durationMs", 1, true) or source:find("elapsedMs", 1, true)) then
			missing[#missing + 1] = name .. ".duration"
		end
		if not source:find("= nil", 1, true) then missing[#missing + 1] = name .. ".cleanup" end
	end
	assert(#missing == 0, "aggregate fields missing: " .. table.concat(missing, ", "))
	contains(sources.server, "OperationPacing.release",
		"authoritative pacing snapshots are never released")
	return true
end)

Support.finish(suite)

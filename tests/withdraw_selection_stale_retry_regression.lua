-- A semantic exact_group gesture survives one authoritative refresh after a
-- stale revision.  Visual expansion and pagination never alter that gesture:
-- rowKey, destination and pacingId remain stable, while the selection revision
-- is replaced only by the fresh terminalState supplied by the server.

for _, name in ipairs({
	"GS_NetClient", "GS_I18n", "GS_Log", "GS_PlayerUtils", "GS_Sandbox", "GS_OperationPacing",
}) do
	package.loaded[name] = true
end

local now, tick, commands = 0, nil, {}
getTimestampMs = function() return now end
Events = { OnTick = {
	Add = function(callback) tick = callback end,
	Remove = function(callback) if tick == callback then tick = nil end end,
} }

GlobalStorageSiK = {
	NetClient = {
		getPlayer = function() return nil end,
		sendCommand = function(command, args)
			commands[#commands + 1] = { command = command, args = args }
			return true
		end,
	},
	I18n = { text = function(key) return key end, remote = function(key) return key end },
	Log = {
		debug = function() end, info = function() end,
		error = function() end, warn = function() end,
	},
	Sandbox = { operationHaloFeedbackEnabled = function() return false end },
	OperationPacing = {
		resolve = function() return { batchUnits = 10, batchDelayMs = 400 } end,
		describe = function() return "test" end,
	},
	TerminalSync = {
		beginManagedTransfer = function() return true end,
		finishManagedTransfer = function() end,
	},
	Client = { activeNetworkId = "network-a" },
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_WithdrawClient.lua")

local function countCommand(name)
	local count = 0
	for i = 1, #commands do
		if commands[i].command == name then count = count + 1 end
	end
	return count
end

local function lastCommand(name)
	for i = #commands, 1, -1 do
		if commands[i].command == name then return commands[i].args end
	end
	return nil
end

local function staleResult(request)
	return GlobalStorageSiK.WithdrawClient.onActionResult({
		ok = false,
		withdrawId = request.withdrawId,
		transfer = {
			op = "withdraw", moved = 0, reason = "selection_stale",
			selectionMode = "exact_group", networkId = "network-a",
		},
	})
end

local function exerciseVisualState(label, visualFields, initialRevision)
	local row = {
		rowKey = "group:Base.VHS:214",
		fullType = "Base.VHS",
		count = 23,
		selectionMode = "exact_group",
		selectionRevision = initialRevision,
	}
	for key, value in pairs(visualFields or {}) do row[key] = value end

	local commandBase = #commands
	assert(GlobalStorageSiK.WithdrawClient.sendWithdraw(
		row, 0, "container:trunk", "woodcraft", { networkId = "network-a" }),
		label .. ": gesture was not queued")
	assert(tick, label .. ": bounded operation tick was not installed")
	tick()
	local first = lastCommand("withdrawItem")
	assert(first and first.rowKey == row.rowKey, label .. ": initial semantic request missing")
	assert(first.selectionRevision == initialRevision, label .. ": initial revision changed")
	assert(first.targetKey == "container:trunk", label .. ": destination changed")
	local pacingId = first.pacingId

	assert(staleResult(first) == true, label .. ": first stale did not enter refresh wait")
	assert(#commands == commandBase + 2, label .. ": stale must emit exactly one refresh request")
	local refresh = commands[#commands]
	assert(refresh.command == "requestItemIndex", label .. ": stale did not request terminalState refresh")
	assert(refresh.args.networkId == "network-a" and refresh.args.searchQuery == "woodcraft",
		label .. ": refresh lost network/search context")

	-- The installed tick only owns a bounded timeout while waiting.  It must not
	-- resend the gesture or poll another snapshot before a newer terminalState.
	now = now + 100
	tick()
	assert(#commands == commandBase + 2, label .. ": request resent before fresh snapshot")
	assert(GlobalStorageSiK.WithdrawClient.onTerminalState({
		networkId = "network-a", inventoryRevision = initialRevision,
		items = { row },
	}) == false, label .. ": equal revision was incorrectly accepted as fresh")
	assert(#commands == commandBase + 2, label .. ": equal revision triggered retry")

	local freshRevision = initialRevision + 1
	local freshRow = {
		rowKey = row.rowKey, fullType = row.fullType, count = 21,
		selectionMode = "exact_group", selectionRevision = freshRevision,
	}
	assert(GlobalStorageSiK.WithdrawClient.onTerminalState({
		networkId = "network-a", inventoryRevision = freshRevision,
		items = { freshRow },
	}) == true, label .. ": fresh authoritative snapshot was not consumed")
	assert(#commands == commandBase + 2, label .. ": retry was sent inside snapshot callback")
	tick()
	local retry = lastCommand("withdrawItem")
	assert(#commands == commandBase + 3, label .. ": fresh snapshot did not cause one retry")
	assert(retry.rowKey == first.rowKey, label .. ": retry changed semantic rowKey")
	assert(retry.targetKey == first.targetKey, label .. ": retry changed destination")
	assert(retry.pacingId == pacingId, label .. ": retry changed logical pacing operation")
	assert(retry.selectionRevision == freshRevision, label .. ": retry did not use fresh revision")
	assert(retry.selectionTicket == nil and retry.selectionSequence == 1,
		label .. ": retry reused stale ticket state")

	assert(staleResult(retry) == false, label .. ": second stale must terminate the gesture")
	assert(not GlobalStorageSiK.WithdrawClient.isPending(), label .. ": second stale left pending work")
	assert(tick == nil, label .. ": second stale left OnTick installed")
	assert(countCommand("requestItemIndex") == (initialRevision == 10 and 1
		or initialRevision == 20 and 2 or 3),
		label .. ": second stale requested another refresh")
end

exerciseVisualState("collapsed", { _gsExpanded = false }, 10)
exerciseVisualState("expanded", { _gsExpanded = true }, 20)
exerciseVisualState("paginated", { _gsExpanded = true, detailPage = 3, detailHasNext = true }, 30)

-- Closing/cancelling while waiting invalidates the deferred gesture.  A late
-- authoritative snapshot must not resurrect it.
local cleanupRow = {
	rowKey = "group:Base.PetrolCan:fuel", fullType = "Base.PetrolCan", count = 2,
	selectionMode = "exact_group", selectionRevision = 40,
}
assert(GlobalStorageSiK.WithdrawClient.sendWithdraw(
	cleanupRow, 0, "player:main", "fuel", { networkId = "network-a" }))
tick()
local cleanupRequest = lastCommand("withdrawItem")
assert(staleResult(cleanupRequest) == true, "cleanup fixture did not enter stale wait")
local beforeCleanup = #commands
GlobalStorageSiK.WithdrawClient.cancelAll("terminal_closed")
assert(not GlobalStorageSiK.WithdrawClient.isPending() and tick == nil,
	"cleanup left stale wait active")
assert(GlobalStorageSiK.WithdrawClient.onTerminalState({
	networkId = "network-a", inventoryRevision = 41,
	items = { {
		rowKey = cleanupRow.rowKey, fullType = cleanupRow.fullType, count = 2,
		selectionMode = "exact_group", selectionRevision = 41,
	} },
}) == false, "late snapshot resurrected cancelled gesture")
assert(#commands == beforeCleanup, "cleanup or late snapshot emitted another request")

-- Integration source contract: requestItemIndex returns terminalState, and the
-- client dispatches that authoritative state to WithdrawClient.  itemIndex is
-- diagnostics-only and must not be the retry trigger.
local function readAll(path)
	local file = assert(io.open(path, "r"))
	local source = file:read("*a")
	file:close()
	return source
end

local clientSource = readAll(
	"GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_Client.lua")
local terminalBranch = assert(clientSource:find('command == "terminalState"', 1, true),
	"GS_Client terminalState branch missing")
local retryCallback = assert(clientSource:find("WithdrawClient.onTerminalState(args)", terminalBranch, true),
	"terminalState is not forwarded to WithdrawClient")
local itemIndexBranch = assert(clientSource:find('command == "itemIndex"', terminalBranch, true),
	"GS_Client itemIndex branch missing")
assert(retryCallback < itemIndexBranch,
	"retry callback is not owned by authoritative terminalState branch")

local serverSource = readAll(
	"GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_Server.lua")
local refreshBranch = assert(serverSource:find('command == "requestItemIndex"', 1, true),
	"GS_Server requestItemIndex branch missing")
local nextBranch = assert(serverSource:find("elseif command ==", refreshBranch + 1, true),
	"cannot bound requestItemIndex branch")
local refreshBody = serverSource:sub(refreshBranch, nextBranch - 1)
assert(refreshBody:find("pushTerminalState(player, networkId", 1, true),
	"requestItemIndex does not return an authoritative terminalState")

local withdrawSource = readAll(
	"GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_WithdrawClient.lua")
local tickStart = assert(withdrawSource:find("function GlobalStorageSiK.WithdrawClient.onTick", 1, true))
local tickEnd = assert(withdrawSource:find("function GlobalStorageSiK.WithdrawClient.cancelAll", tickStart, true))
assert(not withdrawSource:sub(tickStart, tickEnd - 1):find("requestItemIndex", 1, true),
	"OnTick must not poll authoritative snapshots")

print("withdraw_selection_stale_retry_regression: OK")

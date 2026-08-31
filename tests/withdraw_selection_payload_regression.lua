-- Client intents preserve semantic selection. exact_group never serializes a
-- visual page as IDs; exact_ids is bounded to the same physical micro-batch.

for _, name in ipairs({
	"GS_NetClient", "GS_I18n", "GS_Log", "GS_PlayerUtils", "GS_Sandbox",
	"GS_OperationPacing",
}) do package.loaded[name] = true end

local clock = 5000
getTimestampMs = function() return clock end
Events = {
	OnTick = { Add = function() end, Remove = function() end },
}

local commands = {}
GlobalStorageSiK = {
	I18n = {
		text = function(key) return key end,
		remote = function(key) return key end,
	},
	Log = {
		debug = function() end, info = function() end,
		warn = function() end, error = function() end,
	},
	Sandbox = { operationHaloFeedbackEnabled = function() return false end },
	OperationPacing = {
		resolve = function()
			return { mode = "SAFE", batchUnits = 10, batchDelayMs = 0 }
		end,
		describe = function() return "mode=SAFE batchUnits=10" end,
	},
	NetClient = {
		getPlayer = function() return nil end,
		sendCommand = function(command, args)
			commands[#commands + 1] = { command = command, args = args }
			return true
		end,
	},
	TerminalUI = { instance = { terminalState = { networkId = "net" } } },
}

local path = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_WithdrawClient.lua"
dofile(path)

local group = {
	rowKey = "Base.VHS_Retail\31sprite:\31media:214",
	fullType = "Base.VHS_Retail", count = 34,
	selectionMode = "exact_group", selectionRevision = 9,
}
assert(GlobalStorageSiK.WithdrawClient.sendWithdrawBatch({ group }),
	"semantic group was rejected locally")
GlobalStorageSiK.WithdrawClient.onTick()
local first = commands[#commands]
assert(first and first.command == "withdrawItem", "exact_group intent was not dispatched")
assert(first.args.selectionMode == "exact_group", "semantic mode was lost")
assert(first.args.rowKey == group.rowKey and first.args.selectionRevision == 9,
	"first exact_group batch must carry its captured identity and revision")
assert(#first.args.itemIds == 0 and first.args.amount == 10,
	"exact_group must send no client IDs and must stay within ten units")

assert(GlobalStorageSiK.WithdrawClient.onActionResult({
	ok = true, withdrawId = first.args.withdrawId,
	transfer = {
		op = "withdraw", moved = 10, selectionMode = "exact_group",
		selectionTicket = "ticket-1", selectionSequence = 2,
		selectionCount = 34, ticketRemaining = 24,
	},
}), "exact_group continuation was not scheduled")
GlobalStorageSiK.WithdrawClient.onTick()
local second = commands[#commands]
assert(second.command == "withdrawItem" and second.args.amount == 10,
	"continued semantic selection did not preserve the micro-batch bound")
assert(second.args.selectionTicket == "ticket-1" and second.args.selectionSequence == 2,
	"continued semantic selection lost ticket or sequence")
assert(second.args.rowKey == nil and second.args.selectionRevision == nil
	and #second.args.itemIds == 0,
	"ticket continuation must not resend mutable selector fields or client IDs")
GlobalStorageSiK.WithdrawClient.cancelAll("fixture_reset")

commands = {}
local exact = { fullType = "Base.Nails", count = 15, selectionMode = "exact_ids", itemIds = {} }
for i = 1, 15 do exact.itemIds[i] = 100 + i end
assert(GlobalStorageSiK.WithdrawClient.sendWithdrawBatch({ exact }, 0),
	"exact ID selection was rejected locally")
GlobalStorageSiK.WithdrawClient.onTick()
local exactFirst = commands[#commands]
assert(exactFirst.command == "withdrawItem" and exactFirst.args.selectionMode == "exact_ids",
	"exact_ids intent was not dispatched explicitly")
assert(exactFirst.args.amount == 10 and #exactFirst.args.itemIds == 10,
	"exact_ids must be sliced into at most ten physical IDs")
for i = 1, 10 do
	assert(exactFirst.args.itemIds[i] == 100 + i, "first exact_ids slice changed order")
end

assert(GlobalStorageSiK.WithdrawClient.onActionResult({
	ok = true, withdrawId = exactFirst.args.withdrawId,
	transfer = { op = "withdraw", moved = 10, selectionMode = "exact_ids" },
}), "exact_ids continuation was not scheduled")
GlobalStorageSiK.WithdrawClient.onTick()
local exactSecond = commands[#commands]
assert(exactSecond.command == "withdrawItem" and exactSecond.args.amount == 5
	and #exactSecond.args.itemIds == 5,
	"remaining exact IDs must form the final bounded micro-batch")
for i = 1, 5 do
	assert(exactSecond.args.itemIds[i] == 110 + i, "second exact_ids slice changed order")
end
GlobalStorageSiK.WithdrawClient.cancelAll("fixture_done")

print("withdraw_selection_payload_regression: OK")

-- A manual exact selection may contain different RecordedMedia titles. Once
-- their itemIds are known the client packs them into the configured physical
-- micro-batch; this is deliberately not a semantic VHS group.

for _, name in ipairs({
	"GS_NetClient", "GS_I18n", "GS_Log", "GS_PlayerUtils", "GS_Sandbox", "GS_OperationPacing",
}) do
	package.loaded[name] = true
end

local now, tick, sent = 0, nil, {}
getTimestampMs = function() return now end
Events = { OnTick = {
	Add = function(callback) tick = callback end,
	Remove = function(callback) if tick == callback then tick = nil end end,
} }

GlobalStorageSiK = {
	NetClient = {
		getPlayer = function() return nil end,
		sendCommand = function(command, args)
			assert(command == "withdrawItem", "unexpected command")
			sent[#sent + 1] = args
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
	Client = { activeNetworkId = "network" },
}

dofile("tests/helpers/gs_ui_feedback_stub.lua").install()
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_WithdrawClient.lua")

local rows = {}
for i = 1, 28 do
	rows[#rows + 1] = {
		fullType = "Base.VHS",
		mediaTitle = "Titulo " .. tostring(i),
		mediaIndex = i,
		count = 1,
		itemIds = { i },
	}
end

assert(GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(rows, 0, "player:main", "vhs"),
	"exact VHS batch was not queued")
assert(tick, "withdraw tick was not installed")

local function respond(moved)
	local request = sent[#sent]
	assert(request, "no request in flight")
	GlobalStorageSiK.WithdrawClient.onActionResult({
		ok = true,
		withdrawId = request.withdrawId,
		transfer = { op = "withdraw", moved = moved, itemIds = {}, networkId = "network" },
	})
end

tick()
assert(#sent == 1 and #sent[1].itemIds == 10, "first micro-batch must contain ten exact VHS")
assert(sent[1].mediaTitle == nil and sent[1].mediaIndex == nil,
	"merged exact VHS must not retain the first title selector")
respond(10)

now = 400
tick()
assert(#sent == 2 and #sent[2].itemIds == 10, "second micro-batch must contain ten exact VHS")
respond(10)

now = 800
tick()
assert(#sent == 3 and #sent[3].itemIds == 8, "last micro-batch must include all remaining VHS")
respond(8)

assert(tick == nil, "completed exact batch left an OnTick handler installed")

-- The same batcher receives one exact VHS group header. Its visible pages are
-- deliberately absent: all 34 units share title and media identity, so the
-- semantic selection must become 10/10/10/4 without item-by-item requests.
local parent = {
	rowKey = "Base.VHS_Retail\31sprite:\31media:214",
	fullType = "Base.VHS_Retail", count = 34,
	name = "VHS: Woodcraft Ep. 3", displayName = "VHS: Woodcraft Ep. 3",
	mediaTitle = "VHS: Woodcraft Ep. 3", mediaIndex = 214,
	selectionMode = "exact_group", selectionRevision = 9,
}
assert(GlobalStorageSiK.WithdrawClient.sendWithdrawBatch({ parent }, 0, "player:main", "vhs"),
	"semantic group header was not queued")
tick()
assert(#sent == 4 and sent[4].amount == 10 and #sent[4].itemIds == 0,
	"first header micro-batch must request ten semantic units")
local function respondGroup(moved, remaining, sequence)
	local request = sent[#sent]
	assert(request, "no semantic request in flight")
	GlobalStorageSiK.WithdrawClient.onActionResult({
		ok = true,
		withdrawId = request.withdrawId,
		transfer = {
			op = "withdraw", moved = moved, selectionMode = "exact_group",
			selectionTicket = "ticket-media-214", selectionSequence = sequence,
			selectionCount = 34, ticketRemaining = remaining,
		},
	})
end
respondGroup(10, 24, 2)
now = 1200
tick()
assert(#sent == 5 and sent[5].amount == 10, "second header micro-batch must request ten units")
respondGroup(10, 14, 3)
now = 1600
tick()
assert(#sent == 6 and sent[6].amount == 10, "third header micro-batch must request ten units")
respondGroup(10, 4, 4)
now = 2000
tick()
assert(#sent == 7 and sent[7].amount == 4, "final header micro-batch must request four units")
respondGroup(4, 0, 5)
assert(tick == nil, "semantic group completion left an OnTick handler installed")

local source = assert(io.open("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_WithdrawClient.lua", "r")):read("*a")
local halo = assert(source:match("local function showProgress%(force%)(.-)\nend"), "progress function missing")
assert(not halo:find("rowsDone", 1, true) and not halo:find("rowsTotal", 1, true),
	"world halo must expose physical units only, never queue rows")
print("withdraw_exact_batch_regression: OK")

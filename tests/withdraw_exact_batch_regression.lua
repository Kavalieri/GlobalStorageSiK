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

local rows, batchCompletion = {}, nil
for i = 1, 28 do
	rows[#rows + 1] = {
		fullType = "Base.VHS",
		mediaTitle = "Titulo " .. tostring(i),
		mediaIndex = i,
		dynamicSignature = "snapshot-" .. tostring(i),
		count = 1,
		itemIds = { i },
		-- Expanded rows may originate in different containers. Exact item IDs are
		-- authoritative; batching must not fragment or pin them to a stale node.
		sourceNodeId = "node-" .. tostring((i % 3) + 1),
	}
end

-- El arrastre nace sobre una fila y aporta amount=1 aunque la seleccion visual
-- contenga muchas filas hijas. El lote debe conservar todos los IDs elegidos.
assert(GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(rows, 1, "player:main", "vhs", {
	onComplete = function(ok, result) batchCompletion = { ok = ok, result = result } end,
}),
	"exact VHS batch was not queued")
assert(tick, "withdraw tick was not installed")

local function respond(moved)
	local request = sent[#sent]
	assert(request, "no request in flight")
	GlobalStorageSiK.WithdrawClient.onActionResult({
		ok = true,
		withdrawId = request.withdrawId,
		transfer = { op = "withdraw", moved = moved, itemIds = {}, networkId = "network",
			inventoryRevision = 100 + #sent },
	})
end

tick()
assert(#sent == 1 and #sent[1].itemIds == 10, "first micro-batch must contain ten exact VHS")
assert(sent[1].sourceNodeId == nil,
	"exact item IDs must be resolved across the accessible network, not pinned to one node")
assert(sent[1].mediaTitle == nil and sent[1].mediaIndex == nil
	and sent[1].dynamicSignature == nil,
	"merged exact VHS must not retain stale derived selectors")
respond(10)

now = 400
tick()
assert(#sent == 2 and #sent[2].itemIds == 10, "second micro-batch must contain ten exact VHS")
assert(sent[2].sourceNodeId == nil, "second exact micro-batch leaked a source node")
respond(10)

now = 800
tick()
assert(#sent == 3 and #sent[3].itemIds == 8, "last micro-batch must include all remaining VHS")
assert(sent[3].sourceNodeId == nil, "last exact micro-batch leaked a source node")
respond(8)

assert(tick == nil, "completed exact batch left an OnTick handler installed")
assert(batchCompletion and batchCompletion.ok == true and batchCompletion.result.moved == 28,
	"coalesced exact batch did not emit one successful completion")
assert(batchCompletion.result.inventoryRevision == 103,
	"coalesced completion did not preserve the newest inventory revision")

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

-- Defensa en profundidad: incluso un cliente anterior que conserve metadatos
-- de snapshot debe entrar en la rama exacta sin filtrar por ellos.
local serverSource = assert(io.open(
	"GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_Server.lua", "r")):read("*a")
local exactStart = assert(serverSource:find('elseif selectionMode == "exact_ids" then', 1, true),
	"server exact_ids branch missing")
local exactEnd = assert(serverSource:find("\n\t\telse", exactStart + 1, true),
	"server exact_ids branch end missing")
local exactBranch = serverSource:sub(exactStart, exactEnd - 1)
assert(exactBranch:find("mediaTitle = nil", 1, true)
	and exactBranch:find("mediaIndex = nil", 1, true)
	and exactBranch:find("dynamicSignature = nil", 1, true),
	"server exact_ids must discard stale derived selectors")
print("withdraw_exact_batch_regression: OK")

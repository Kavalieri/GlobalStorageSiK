require "GS_NetClient"
require "GS_ContainerTargets"
require "GS_I18n"
require "GS_Log"
require "GS_UI_Feedback"
local createOperation = require "GS_WithdrawOperation"

-- Each gesture captures its destination once. Rows and ACKs never borrow the
-- current UI selection or another local player's queue state.
local Client = {}
GlobalStorageSiK.WithdrawClient = Client
local queues = {}
local serial = 0
local pumpInstalled = false
local MAX_GESTURES = 64
local MAX_ROWS = 4096

local function numberOf(playerNum)
	playerNum = playerNum == nil and 0 or tonumber(playerNum)
	if not playerNum or playerNum ~= math.floor(playerNum) or playerNum < 0 or playerNum > 3 then return nil end
	return playerNum
end

local function completeRejected(options, reason)
	if not options or not options.onComplete then return end
	local ok, err = pcall(options.onComplete, false, { reason = reason, moved = 0, itemIds = {} })
	if not ok then GlobalStorageSiK.Log.error("WithdrawClient", "rejected callback failed", tostring(err)) end
end

local function reject(player, options, reason)
	GlobalStorageSiK.Log.warn("WithdrawClient", "gesture rejected", tostring(reason))
	if player then
		GlobalStorageSiK.UIFeedback.halo(player,
			GlobalStorageSiK.I18n.text((reason == "target_unavailable" or reason == "invalid_target")
				and "IGUI_GS_WithdrawTargetUnavailable" or "IGUI_GS_InternalTransferError"),
			255, 120, 120, 1800, { tone = "danger", channel = "withdraw" })
	end
	completeRejected(options, reason)
	return false
end

local fields = { "fullType", "count", "selectionMode", "rowKey", "selectionRevision",
	"sourceNodeId", "mediaTitle", "mediaIndex", "dynamicSignature", "aggregateAllowed" }
local function captureRow(row)
	if type(row) ~= "table" or type(row.fullType) ~= "string" or row.fullType == "" then return nil end
	local result = {}
	for i = 1, #fields do
		local value = row[fields[i]]
		local kind = type(value)
		if kind ~= "nil" and kind ~= "string" and kind ~= "number" and kind ~= "boolean" then return nil end
		if kind == "number" and (value ~= value or value == math.huge or value == -math.huge) then return nil end
		result[fields[i]] = value
	end
	for _, key in ipairs({ "itemIds", "fullTypes" }) do
		if row[key] ~= nil then
			if type(row[key]) ~= "table" or #row[key] > MAX_ROWS then return nil end
			result[key] = {}
			for i = 1, #row[key] do result[key][i] = row[key][i] end
		end
	end
	return result
end

local function ensurePump()
	if pumpInstalled or not Events or not Events.OnTick then return end
	pumpInstalled = true
	Events.OnTick.Add(Client.onTick)
end

local function afterDispatch(entry, worker)
	local state = queues[entry.playerNum]
	if not state or state.entries[1] ~= entry or entry.worker ~= worker or worker.isPending() then return end
	table.remove(state.entries, 1)
	state.rows = state.rows - #entry.rows
	if #state.entries == 0 then queues[entry.playerNum] = nil else ensurePump() end
	if not Client.isPending() and pumpInstalled and Events and Events.OnTick then
		Events.OnTick.Remove(Client.onTick)
		pumpInstalled = false
	end
end

local function start(entry)
	if entry.worker then return end
	local context = {
		playerNum = entry.playerNum, player = entry.player, operationId = entry.operationId,
		networkId = entry.networkId, targetKey = entry.targetKey, requestPump = ensurePump,
		afterDispatch = function(worker) afterDispatch(entry, worker) end,
	}
	local worker = createOperation(context)
	entry.worker = worker
	local options = { networkId = entry.networkId, returnItemIds = entry.returnItemIds,
		onComplete = entry.onComplete, readLoanId = entry.readLoanId }
	local accepted
	if entry.batch then
		accepted = worker.sendWithdrawBatch(entry.rows, entry.amount, entry.targetKey, entry.searchQuery, options)
	else
		accepted = worker.sendWithdraw(entry.rows[1], entry.amount, entry.targetKey, entry.searchQuery, options)
	end
	afterDispatch(entry, worker)
	return accepted
end

local function enqueue(rows, batch, amount, targetKey, searchQuery, options)
	options = options or {}
	local playerNum = numberOf(options.playerNum)
	local player = playerNum ~= nil and GlobalStorageSiK.NetClient.getPlayer(playerNum) or nil
	if not player then return reject(nil, options, "player_unavailable") end
	if player.getPlayerNum and player:getPlayerNum() ~= playerNum then return reject(nil, options, "player_mismatch") end
	if type(rows) ~= "table" or #rows == 0 or #rows > MAX_ROWS then return reject(player, options, "invalid_rows") end
	local numericAmount = amount ~= nil and tonumber(amount) or nil
	if amount ~= nil and (not numericAmount or numericAmount ~= numericAmount
		or numericAmount == math.huge or numericAmount == -math.huge) then
		return reject(player, options, "invalid_amount")
	end
	if targetKey == nil then
		local reason
		targetKey, reason = GlobalStorageSiK.ContainerTargets.resolveWithdrawTarget(player)
		if not targetKey then return reject(player, options, reason or "target_unavailable") end
	end
	if type(targetKey) ~= "string" or targetKey == "" or #targetKey > 192 then
		return reject(player, options, "invalid_target")
	end
	local state = queues[playerNum]
	if state and (#state.entries >= MAX_GESTURES or state.rows + #rows > MAX_ROWS) then
		return reject(player, options, "queue_limit")
	end
	local captured = {}
	for i = 1, #rows do
		captured[i] = captureRow(rows[i])
		if not captured[i] then return reject(player, options, "invalid_row") end
	end
	local terminal = GlobalStorageSiK.TerminalUI
	local ui = terminal and terminal.getInstanceForPlayer and terminal.getInstanceForPlayer(playerNum)
	local client = GlobalStorageSiK.Client
	local networkId = options.networkId or (ui and ui.terminalState and ui.terminalState.networkId)
		or (client and client.activeNetworkIdByPlayer and client.activeNetworkIdByPlayer[playerNum])
		or (playerNum == 0 and client and client.activeNetworkId)
	if type(networkId) ~= "string" or networkId == "" then return reject(player, options, "network_unavailable") end
	serial = serial + 1
	local entry = {
		playerNum = playerNum, player = player, networkId = networkId, rows = captured,
		batch = batch, amount = numericAmount, targetKey = targetKey, searchQuery = searchQuery or "",
		returnItemIds = options.returnItemIds == true, onComplete = options.onComplete,
		readLoanId = options.readLoanId,
		operationId = "withdraw:" .. tostring(playerNum) .. ":"
			.. tostring(getTimestampMs and getTimestampMs() or 0) .. ":" .. tostring(serial),
	}
	if not state then state = { entries = {}, rows = 0 }; queues[playerNum] = state end
	state.entries[#state.entries + 1] = entry
	state.rows = state.rows + #captured
	if #state.entries == 1 then return start(entry) end
	ensurePump()
	return true
end

function Client.sendWithdraw(row, amount, targetKey, searchQuery, options)
	return enqueue({ row }, false, amount, targetKey, searchQuery, options)
end
function Client.sendWithdrawBatch(rows, amount, targetKey, searchQuery, options)
	return enqueue(rows, true, amount, targetKey, searchQuery, options)
end
function Client.onTick()
	for i = 0, 3 do
		local state = queues[i]
		local entry = state and state.entries[1]
		if entry then
			if not entry.worker then start(entry) end
			if queues[i] == state and state.entries[1] == entry and entry.worker then
				entry.worker.onTick()
			end
		end
	end
end
function Client.isResponseExpected(args)
	for i = 0, 3 do
		local state = queues[i]
		local entry = state and state.entries[1]
		if entry and entry.worker and entry.worker.matchesResponse(args)
			and (args.playerNum == nil or tonumber(args.playerNum) == i) then return true end
	end
	return false
end
function Client.onActionResult(args)
	for i = 0, 3 do
		local state = queues[i]
		local entry = state and state.entries[1]
		local worker = entry and entry.worker
		if worker and worker.matchesResponse(args) then
			if args.playerNum ~= nil and tonumber(args.playerNum) ~= i then return false end
			args.playerNum = i
			local continuing = worker.onActionResult(args)
			afterDispatch(entry, worker)
			return continuing
		end
	end
	return false
end
function Client.onTerminalState(state)
	local playerNum = state and numberOf(state.playerNum)
	local queue = playerNum ~= nil and queues[playerNum]
	local entry = queue and queue.entries[1]
	if not entry or not entry.worker then return false end
	local consumed = entry.worker.onTerminalState(state)
	afterDispatch(entry, entry.worker)
	return consumed
end
function Client.isPending(playerNum)
	if playerNum ~= nil then
		local number = numberOf(playerNum)
		return number ~= nil and queues[number] ~= nil
	end
	for i = 0, 3 do if queues[i] then return true end end
	return false
end
function Client.cancelAll(reason, playerNum)
	local cancelled = {}
	local number = playerNum ~= nil and numberOf(playerNum) or nil
	if playerNum ~= nil and number == nil then return end
	for i = 0, 3 do
		if (number == nil or number == i) and queues[i] then
			cancelled[#cancelled + 1] = queues[i]
			queues[i] = nil
		end
	end
	-- Detach before callbacks; a callback may enqueue a new, independent gesture.
	for i = 1, #cancelled do
		for j = 1, #cancelled[i].entries do
			local entry = cancelled[i].entries[j]
			if entry.worker then entry.worker.cancelAll(reason)
			else completeRejected(entry, reason or "cancelled") end
		end
	end
	if not Client.isPending() and pumpInstalled and Events and Events.OnTick then
		Events.OnTick.Remove(Client.onTick)
		pumpInstalled = false
	end
end
function Client.clearPending(playerNum) Client.cancelAll("cancelled", playerNum) end
return Client

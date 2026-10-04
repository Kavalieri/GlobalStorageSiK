--[[
	GlobalStorageSiK - Tareas autoritativas acotadas de deposito por identidad
	Descripcion: sella una seleccion una vez y la avanza en slices justos sin
	depender de un RTT cliente por slice.
]]

require "GS_PlayerUtils"
require "GS_TransferLock"
require "GS_InventorySync"
require "GS_Deposit"

GlobalStorageSiK.DepositTasks = GlobalStorageSiK.DepositTasks or {}

local Tasks = GlobalStorageSiK.DepositTasks
local MAX_IDS = 4096
local MAX_TASKS_PER_PLAYER = 4
local MAX_TASKS_GLOBAL = 128
local MAX_SLICES_PER_TICK = 2
local CPU_BUDGET_MS = 5
local RECEIPT_TTL_MS = 30000
local MAX_RECEIPTS = 256
local tasks, order, byKey, receipts, receiptOrder = {}, {}, {}, {}, {}
local cursor = 0
local callbacks = {}

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function playerKey(player)
	if not player or not player.getUsername then return nil end
	local username = player:getUsername()
	local playerNum = player.getPlayerNum and player:getPlayerNum() or -1
	if not username or username == "" then return nil end
	return tostring(username) .. "\31" .. tostring(playerNum)
end

local function operationKey(key, networkId, depositId, queueId)
	local id = type(depositId) == "string" and depositId ~= "" and depositId or queueId
	if not key or type(id) ~= "string" or id == "" then return nil end
	return key .. "\31" .. tostring(networkId) .. "\31" .. string.sub(id, 1, 96)
end

local function removeOrder(taskId)
	for i = #order, 1, -1 do
		if order[i] == taskId then
			table.remove(order, i)
			if cursor >= i then cursor = cursor - 1 end
		end
	end
	if cursor < 0 then cursor = 0 end
end

local function copySummary(summary)
	local copy = {}
	for key, value in pairs(summary or {}) do
		if type(value) == "table" then
			local list = {}
			for i = 1, #value do list[i] = value[i] end
			copy[key] = list
		else
			copy[key] = value
		end
	end
	return copy
end

local function sweepReceipts(now)
	local kept = {}
	local live = {}
	for i = 1, #receiptOrder do
		local key = receiptOrder[i]
		local receipt = receipts[key]
		if receipt and (now <= 0 or now - (receipt.createdMs or 0) <= RECEIPT_TTL_MS) then
			kept[#kept + 1], live[key] = key, true
		else receipts[key] = nil end
	end
	for key, receipt in pairs(receipts) do
		if not live[key] and now > 0 and now - (receipt.createdMs or 0) > RECEIPT_TTL_MS then receipts[key] = nil end
	end
	receiptOrder = kept
	while #receiptOrder >= MAX_RECEIPTS do receipts[table.remove(receiptOrder, 1)] = nil end
end

local function countForPlayer(key)
	local count = 0
	for _, task in pairs(tasks) do
		if task.playerKey == key then count = count + 1 end
	end
	return count
end

local function mergeTouched(task, ids)
	for i = 1, #(ids or {}) do
		local id = tostring(ids[i])
		if not task.touchedSet[id] then
			task.touchedSet[id] = true
			task.summary.touchedNodeIds[#task.summary.touchedNodeIds + 1] = id
		end
	end
end

local function finish(task, reason, cancelled, silent)
	if not task or tasks[task.id] ~= task then return end
	tasks[task.id], byKey[task.key] = nil, nil
	removeOrder(task.id)
	local summary = task.summary
	local checkpointOk, checkpointNodes =
		GlobalStorageSiK.Transfer.flushDepositSessionSnapshots(task.routingSession)
	if checkpointOk ~= true then summary.snapshotsUpdated = false end
	mergeTouched(task, checkpointNodes)
	if reason and not summary.reason then summary.reason = reason end
	if cancelled and task.offset <= #task.itemIds then
		summary.cancelled = #task.itemIds - task.offset + 1
	end
	summary.inventoryRevision = GlobalStorageSiK.Index.getInventoryRevision(task.networkId)
	local plan = task.routingSession and task.routingSession.routingPlan
	if plan and GlobalStorageSiK.Log and GlobalStorageSiK.Log.debug then
		local stats = plan.stats
		GlobalStorageSiK.Log.debug("Router", "depositComplete | networkId=" .. tostring(task.networkId)
			.. " moved=" .. tostring(summary.moved or 0) .. " skipped=" .. tostring(summary.skipped or 0)
			.. " failed=" .. tostring(summary.failed or 0) .. " planBuilds=" .. tostring(stats.builds)
			.. " planHits=" .. tostring(stats.hits) .. " candidateVisits=" .. tostring(stats.visits)
			.. " matching=" .. tostring(stats.matches) .. " affinityReads=" .. tostring(stats.affinityReads)
			.. " physicalValidations=" .. tostring(stats.validations))
	end
	receipts[task.key] = { createdMs = nowMs(), summary = copySummary(summary), meta = task.meta }
	receiptOrder[#receiptOrder + 1] = task.key
	if not silent and callbacks.complete then callbacks.complete(task.player, task.networkId, task.meta, summary) end
end

local function processTask(task)
	local player = GlobalStorageSiK.PlayerUtils.resolveByUsername(task.username)
	if not player or (player.getPlayerNum and player:getPlayerNum() or -1) ~= task.playerNum then
		finish(task, "player_unavailable", true, true)
		return
	end
	task.player = player
	if callbacks.validate then
		local allowed, reason = callbacks.validate(player, task.networkId, task.meta)
		if not allowed then finish(task, reason or "terminal_access_changed", true); return end
	end
	local last = math.min(#task.itemIds, task.offset + task.batchUnits - 1)
	local slice = {}
	for i = task.offset, last do slice[#slice + 1] = task.itemIds[i] end
	local worked, lockReason = GlobalStorageSiK.TransferLock.withAuthorityLock(
		task.networkId, task.id, "depositTask", function()
			return GlobalStorageSiK.InventorySync.withBatch(function()
				return GlobalStorageSiK.Deposit.depositByIds(player, task.networkId, slice, {
					preferredNodeId = task.meta.preferredNodeId,
					maxItemsPerTick = #slice,
					searchSnapshot = task.searchSnapshot,
					routingSession = task.routingSession,
					deferSnapshotFlush = true,
				})
			end)
		end)
	if worked == false and type(lockReason) == "string" then
		if lockReason ~= "network_busy" then finish(task, lockReason, true) end
		return
	end
	local summary = worked
	if type(summary) ~= "table" then finish(task, "transfer_failed", true); return end
	task.offset = last + 1
	for _, key in ipairs({ "processed", "moved", "skipped", "failed", "missing" }) do
		task.summary[key] = (task.summary[key] or 0) + (summary[key] or 0)
	end
	if summary.snapshotsUpdated ~= true then task.summary.snapshotsUpdated = false end
	mergeTouched(task, summary.touchedNodeIds)
	if summary.failureReason and not task.summary.failureReason then
		task.summary.failureReason = summary.failureReason
	end
	if summary.reason and summary.reason ~= "limit" and not task.summary.reason then
		task.summary.reason = summary.reason
	end
	if task.offset > #task.itemIds then finish(task) end
	if tasks[task.id] == task and callbacks.progress then
		local now = nowMs()
		if now - (task.lastProgressMs or 0) >= 1000 then
			task.lastProgressMs = now
			callbacks.progress(player, task.networkId, task.meta, task.summary, #task.itemIds)
		end
	end
end

function Tasks.configure(options)
	callbacks = options or {}
end

function Tasks.start(player, networkId, itemIds, options)
	options = options or {}
	local pkey = playerKey(player)
	local key = operationKey(pkey, networkId, options.depositId, options.queueId)
	if not key or type(networkId) ~= "string" or networkId == ""
		or type(itemIds) ~= "table" or #itemIds < 1 or #itemIds > MAX_IDS then
		return false, "invalid_request"
	end
	sweepReceipts(nowMs())
	local receipt = receipts[key]
	if receipt then
		local replay = copySummary(receipt.summary)
		replay.replay = true
		local meta = {}
		for name, value in pairs(receipt.meta or {}) do meta[name] = value end
		meta.queueId = options.queueId or meta.queueId
		if callbacks.complete then callbacks.complete(player, networkId, meta, replay) end
		return true, "replayed"
	end
	if byKey[key] then return true, "active" end
	if #order >= MAX_TASKS_GLOBAL or countForPlayer(pkey) >= MAX_TASKS_PER_PLAYER then
		return false, "task_limit"
	end
	local sealed, seen = {}, {}
	for i = 1, #itemIds do
		local id = itemIds[i]
		if type(id) ~= "number" or id ~= id or id == math.huge or id == -math.huge
			or id ~= math.floor(id) then return false, "invalid_request" end
		if not seen[id] then sealed[#sealed + 1], seen[id] = id, true end
	end
	if #sealed == 0 then return false, "invalid_request" end
	local task = {
		id = "deposit-task:" .. key,
		key = key, playerKey = pkey, username = player:getUsername(),
		playerNum = player.getPlayerNum and player:getPlayerNum() or -1, player = player,
		networkId = networkId, itemIds = sealed, offset = 1,
		batchUnits = math.max(1, math.min(100, math.floor(tonumber(options.batchUnits) or 10))),
		meta = options.meta or {}, touchedSet = {},
		searchSnapshot = GlobalStorageSiK.Deposit.createSearchSnapshot(player, sealed),
		routingSession = GlobalStorageSiK.Transfer.createDepositSession(player, networkId),
		summary = { processed = 0, moved = 0, skipped = 0, failed = 0, missing = 0,
			snapshotsUpdated = true, touchedNodeIds = {} },
	}
	tasks[task.id], byKey[key] = task, task.id
	order[#order + 1] = task.id
	return true, "started"
end

function Tasks.cancelForPlayer(player, reason)
	local key, ids = playerKey(player), {}
	for id, task in pairs(tasks) do
		if task.playerKey == key then ids[#ids + 1] = id end
	end
	for i = 1, #ids do finish(tasks[ids[i]], reason or "cancelled", true) end
	return #ids
end

function Tasks.update(maxSlices, deadlineMs)
	if not GlobalStorageSiK.isAuthoritative() then return end
	local started, serviced = nowMs(), 0
	local sharedDeadline = tonumber(deadlineMs)
	local sliceLimit = math.max(0, math.min(MAX_SLICES_PER_TICK,
		math.floor(tonumber(maxSlices) or MAX_SLICES_PER_TICK)))
	local deadline = sharedDeadline or (started + CPU_BUDGET_MS)
	sweepReceipts(started)
	while #order > 0 and serviced < sliceLimit do
		-- An external deadline is shared with the other transfer queue and may
		-- already be exhausted before this queue receives its turn.
		if (serviced > 0 or sharedDeadline ~= nil) and nowMs() >= deadline then break end
		cursor = cursor % #order + 1
		local task = tasks[order[cursor]]
		if task then processTask(task) else table.remove(order, cursor); cursor = cursor - 1 end
		serviced = serviced + 1
	end
	return serviced
end

function Tasks.pendingCount()
	return #order
end

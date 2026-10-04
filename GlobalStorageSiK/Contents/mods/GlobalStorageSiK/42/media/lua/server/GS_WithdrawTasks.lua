--[[
	GlobalStorageSiK - Tareas autoritativas de retirada exact_group
	Descripcion: conserva el ticket sellado y ejecuta microlotes justos sin
	depender de un RTT cliente entre slices.
]]

require "GS_PlayerUtils"
require "GS_TransferLock"
require "GS_InventorySync"
require "GS_WithdrawSelectionTickets"
require "GS_DepositSources"
require "GS_FloorTargets"
require "GS_Zones"
require "GS_Permissions"
require "GS_Transfer"

GlobalStorageSiK.WithdrawTasks = GlobalStorageSiK.WithdrawTasks or {}

local Tasks = GlobalStorageSiK.WithdrawTasks
local MAX_TASKS_PER_PLAYER = 4
local MAX_TASKS_GLOBAL = 128
local MAX_SLICES_PER_TICK = 2
local CPU_BUDGET_MS = 5
local tasks, order, cursor, callbacks = {}, {}, 0, {}

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

local function removeOrder(taskId)
	for i = #order, 1, -1 do
		if order[i] == taskId then
			table.remove(order, i)
			if cursor >= i then cursor = cursor - 1 end
		end
	end
	if cursor < 0 then cursor = 0 end
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

local function cancelTicket(task)
	if not task.ticketId then return end
	GlobalStorageSiK.WithdrawSelectionTickets.cancel(task.player, task.ticketId)
	task.ticketId = nil
end

local function finish(task, reason, cancelled, silent)
	if not task or tasks[task.id] ~= task then return end
	tasks[task.id] = nil
	removeOrder(task.id)
	if reason and not task.summary.reason then task.summary.reason = reason end
	local checkpointOk, checkpointNodes =
		GlobalStorageSiK.Transfer.flushDepositSessionSnapshots(task.snapshotSession)
	if checkpointOk ~= true then task.summary.snapshotsUpdated = false end
	mergeTouched(task, checkpointNodes)
	if cancelled then task.summary.cancelled = math.max(0,
		(task.limit or task.selectionCount) - (task.summary.moved or 0)) end
	cancelTicket(task)
	task.summary.inventoryRevision = GlobalStorageSiK.Index.getInventoryRevision(task.networkId)
	if callbacks.complete then
		callbacks.complete(task.player, task.networkId, task.meta, task.summary, silent == true)
	end
end

local function validateSource(player, task)
	if task.sourceNodeId == nil then return true end
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local node = registry.nodes and registry.nodes[task.sourceNodeId]
	local zone = node and registry.zones and registry.zones[node.zoneId]
	if not node or node.enabled == false or node.membership == "excluded"
		or not zone or zone.networkId ~= task.networkId or zone.enabled == false
		or not GlobalStorageSiK.Permissions.canAccessZone(
			player, task.networkId, node.zoneId) then
		return false, "source_unavailable"
	end
	return true
end

local function runSlice(task)
	local player = task.player
	local dest, targetReason, targetStage = GlobalStorageSiK.DepositSources.resolveExternalTarget(
		player, task.targetKey)
	if not dest then
		local trace = GlobalStorageSiK.NetTrace
		if trace and trace.isEnabled() then
			trace.write("Withdraw: destination rejected",
				"withdrawId=" .. tostring(task.meta.withdrawId)
				.. " targetKey=" .. tostring(task.targetKey):gsub("[%c]", " "):sub(1,192)
				.. " targetStage=" .. tostring(targetStage or "resolver")
				.. " reason=" .. tostring(targetReason)
				.. " selectionRevision=" .. tostring(task.meta.selectionRevision)
				.. " currentRevision=" .. tostring(GlobalStorageSiK.Index.getInventoryRevision(task.networkId)))
		end
		return nil, targetReason or "target_unavailable"
	end
	local remainingLimit = math.max(0, task.limit - task.summary.moved)
	if remainingLimit == 0 then return { complete = true } end
	local batch, reason = GlobalStorageSiK.WithdrawSelectionTickets.take(
		player, task.ticketId, task.networkId, task.targetKey, task.pacingId,
		task.sequence, math.min(task.batchUnits, remainingLimit), task.sourceNodeId)
	if not batch then return nil, reason end
	local ok, transferReason, moved, movedIds, nodeIds, snapshotsUpdated =
		GlobalStorageSiK.TransferLock.withAuthorityLock(task.networkId, task.id,
			"withdrawTask", function()
				return GlobalStorageSiK.InventorySync.withBatch(function()
					return GlobalStorageSiK.Transfer.withdrawType(
						player, batch.fullType, task.networkId, batch.requested, dest,
						nil, nil, batch.itemIds, nil, nil, task.batchUnits, task.sourceNodeId,
						{ snapshotSession = task.snapshotSession })
				end)
			end)
	if ok == false and transferReason == "network_busy" then return false, transferReason end
	local remaining, complete, consumed, commitReason =
		GlobalStorageSiK.WithdrawSelectionTickets.commit(batch, movedIds)
	if commitReason or consumed ~= (tonumber(moved) or 0) then
		return nil, commitReason or "ticket_identity_mismatch"
	end
	return {
		ok = ok, reason = transferReason, moved = tonumber(moved) or 0,
		fullType = batch.fullType, remaining = remaining or 0,
		complete = complete == true, nodeIds = nodeIds,
		snapshotsUpdated = snapshotsUpdated == true,
	}
end

local function reportProgress(task)
	if not callbacks.progress then return end
	local now = nowMs()
	if now - (task.lastProgressMs or 0) < 1000 then return end
	task.lastProgressMs = now
	callbacks.progress(task.player, task.networkId, task.meta, task.summary, task.limit)
end

local function advanceTask(task)
	local player = GlobalStorageSiK.PlayerUtils.resolveByUsername(task.username)
	if not player or (player.getPlayerNum and player:getPlayerNum() or -1) ~= task.playerNum then
		finish(task, "player_unavailable", true, true); return
	end
	task.player = player
	if callbacks.validate then
		local allowed, reason = callbacks.validate(player, task.networkId, task.meta)
		if not allowed then finish(task, reason or "terminal_access_changed", true); return end
	end
	local sourceOk, sourceReason = validateSource(player, task)
	if not sourceOk then finish(task, sourceReason, true); return end
	local result, reason = runSlice(task)
	if result == false and reason == "network_busy" then reportProgress(task); return end
	if not result then finish(task, reason or "transfer_failed", true); return end
	if result.complete and result.moved == nil then finish(task); return end
	task.sequence = task.sequence + 1
	task.summary.slices = task.summary.slices + 1
	task.summary.moved = task.summary.moved + result.moved
	task.summary.fullType = result.fullType or task.summary.fullType
	if result.snapshotsUpdated ~= true then task.summary.snapshotsUpdated = false end
	mergeTouched(task, result.nodeIds)
	local limitReached = task.summary.moved >= task.limit
	if result.complete or limitReached or result.moved == 0 then
		if result.moved == 0 and result.reason and not task.summary.reason then
			task.summary.reason = string.gsub(tostring(result.reason), "^partial:", "")
		end
		finish(task)
		return
	end
	reportProgress(task)
end

function Tasks.configure(options)
	callbacks = options or {}
end

-- Returns applicable, started, reason. Older clients omit taskAmount and keep
-- the receipt-backed per-slice protocol unchanged.
function Tasks.start(player, args, networkId)
	if type(args) ~= "table" or args.selectionMode ~= "exact_group"
		or args.selectionTicket ~= nil or args.taskAmount == nil
		or args.readLoanId ~= nil then return false, false end
	local targetKey = args.targetKey
	if type(targetKey) ~= "string" or targetKey == "" or #targetKey > 192
		or GlobalStorageSiK.FloorTargets.isKey(targetKey) then
		return false, false
	end
	local pkey = playerKey(player)
	if not pkey or #order >= MAX_TASKS_GLOBAL
		or countForPlayer(pkey) >= MAX_TASKS_PER_PLAYER then
		return true, false, "task_limit"
	end
	local pacingId = type(args.pacingId) == "string"
		and string.sub(args.pacingId, 1, 96) or tostring(args.withdrawId or "")
	local pacingKey = GlobalStorageSiK.Server.operationPacingKey(
		player, "withdraw", pacingId, networkId)
	local pacing = GlobalStorageSiK.OperationPacing.forOperation(
		pacingKey, { operationType = "withdraw" })
	pacing.batchUnits = math.min(10, math.max(1,
		math.floor(tonumber(pacing.batchUnits) or 10)))
	local rowKey = type(args.rowKey) == "string" and string.sub(args.rowKey, 1, 500) or nil
	local ticket, reason = GlobalStorageSiK.WithdrawSelectionTickets.start(
		player, networkId, targetKey, pacingId, rowKey, args.selectionRevision,
		pacing, args.sourceNodeId)
	if not ticket then GlobalStorageSiK.OperationPacing.release(pacingKey); return true, false, reason end
	local requested = tonumber(args.taskAmount)
	if not requested or requested ~= requested or requested == math.huge
		or requested == -math.huge then
		GlobalStorageSiK.WithdrawSelectionTickets.cancel(player, ticket.id)
		GlobalStorageSiK.OperationPacing.release(pacingKey)
		return true, false, "invalid_request"
	end
	requested = math.floor(requested)
	local limit = requested <= 0 and ticket.count or math.min(requested, ticket.count)
	if limit <= 0 then
		GlobalStorageSiK.WithdrawSelectionTickets.cancel(player, ticket.id)
		GlobalStorageSiK.OperationPacing.release(pacingKey)
		return true, false, "not_found"
	end
	local id = "withdraw-task:" .. pkey .. "\31" .. tostring(networkId)
		.. "\31" .. tostring(args.withdrawId)
	local task = {
		id = id, playerKey = pkey, username = player:getUsername(),
		playerNum = player.getPlayerNum and player:getPlayerNum() or -1,
		player = player, networkId = networkId, targetKey = targetKey,
		sourceNodeId = args.sourceNodeId, ticketId = ticket.id,
		pacingId = pacingId, pacingKey = pacingKey, sequence = 1,
		batchUnits = ticket.pacing.batchUnits, selectionCount = ticket.count,
		limit = limit, touchedSet = {},
		snapshotSession = GlobalStorageSiK.Transfer.createSnapshotSession(networkId),
		meta = {
			selectionRevision = args.selectionRevision,
			withdrawId = args.withdrawId, pacingKey = pacingKey,
			searchQuery = type(args.searchQuery) == "string" and args.searchQuery or "",
			selectionCount = ticket.count, requested = limit,
		},
		summary = { moved = 0, slices = 0, snapshotsUpdated = true,
			touchedNodeIds = {} },
	}
	tasks[id] = task
	order[#order + 1] = id
	return true, true, nil
end

function Tasks.cancelForPlayer(player, reason, silent)
	local key, ids = playerKey(player), {}
	for id, task in pairs(tasks) do if task.playerKey == key then ids[#ids + 1] = id end end
	for i = 1, #ids do finish(tasks[ids[i]], reason or "cancelled", true, silent) end
	return #ids
end

function Tasks.cancel(player, withdrawId, reason)
	local key = playerKey(player)
	if type(withdrawId) ~= "string" or withdrawId == "" then return false end
	for _, task in pairs(tasks) do
		if task.playerKey == key and task.meta.withdrawId == withdrawId then
			finish(task, reason or "cancelled", true)
			return true
		end
	end
	return false
end

function Tasks.update(maxSlices, deadlineMs)
	if not GlobalStorageSiK.isAuthoritative() then return end
	local started, serviced = nowMs(), 0
	local sharedDeadline = tonumber(deadlineMs)
	local sliceLimit = math.max(0, math.min(MAX_SLICES_PER_TICK,
		math.floor(tonumber(maxSlices) or MAX_SLICES_PER_TICK)))
	local deadline = sharedDeadline or (started + CPU_BUDGET_MS)
	while #order > 0 and serviced < sliceLimit do
		if (serviced > 0 or sharedDeadline ~= nil) and nowMs() >= deadline then break end
		cursor = cursor % #order + 1
		local task = tasks[order[cursor]]
		if task then advanceTask(task) else table.remove(order, cursor); cursor = cursor - 1 end
		serviced = serviced + 1
	end
	return serviced
end

function Tasks.pendingCount()
	return #order
end

return Tasks

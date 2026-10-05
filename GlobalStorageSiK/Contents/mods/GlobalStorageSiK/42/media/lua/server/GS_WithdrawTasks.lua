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
	if task.slotId then GlobalStorageSiK.WithdrawSelectionTickets.releaseTask(task.player,task.slotId);task.slotId=nil end
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
	if task.admission then
		if task.summary.reason then task.summary.reason=string.sub(tostring(task.summary.reason),1,48) end
		local ended=nowMs()
		local active=(task.activeWorkMs or 0)+(task.turnStartedMs and math.max(0,ended-task.turnStartedMs) or 0)
		task.turnStartedMs=nil
		task.summary.elapsedMs=math.max(0,ended-task.startedMs)
		task.summary.activeWorkMs=active
		task.summary.waitMs=math.max(0,task.summary.elapsedMs-active)
		task.summary.admissionElapsedMs=task.admissionMs or task.summary.elapsedMs
		task.summary.selectors={}
		for i=1,#task.admission.selectors do
			local s=task.admission.selectors[i]
			task.summary.selectors[i]={index=i,selected=s.selected or 0,moved=s.moved or 0,
				applied=s.applied or 0,overlap=s.overlap or 0,
				reason=s.reason and string.sub(tostring(s.reason),1,48) or nil}
			if (s.selected or 0)==0 or (s.moved or 0)<(s.selected or 0) then
				task.summary.unfulfilledSelectors=(task.summary.unfulfilledSelectors or 0)+1
			end
		end
		if not task.summary.reason and task.summary.unfulfilledSelectors then task.summary.reason="partial:not_found" end
		task.summary.admissionStats=task.admission.stats
		GlobalStorageSiK.Index.releaseExactBatch(task.admission)
	end
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

local function advanceBatch(task,deadline)
	if nowMs()-(task.lastActivityMs or task.startedMs)>30000 then finish(task,"selection_expired",true);return end
	if callbacks.validateBatch then
		local valid,reason=callbacks.validateBatch(task.player,task.networkId,task.binding,task.admitting)
		if not valid then finish(task,reason or "terminal_access_changed",true);return end
	end
	if task.admitting then
		local ready,reason=GlobalStorageSiK.Index.stepExactBatch(task.admission,deadline)
		if ready==nil then finish(task,reason,true);return end
		if not ready then reportProgress(task);return end
		if callbacks.validateBatch then
			local valid,sealReason=callbacks.validateBatch(task.player,task.networkId,task.binding,false)
			if not valid then finish(task,sealReason or "selection_stale",true);return end
		end
		task.admitting=false;task.selectionCount=#task.admission.refs;task.limit=task.selectionCount
		task.meta.selectionCount=task.selectionCount;task.meta.requested=task.limit
		task.admissionMs=nowMs()-task.startedMs
		if task.limit==0 then finish(task,"not_found");return end
		-- Mutations receive a later scheduler turn, after the complete seal.
		return
	end
	if task.revision~=GlobalStorageSiK.Index.getInventoryRevision(task.networkId)
		or task.admission.routingRevision~=GlobalStorageSiK.RoutingProtocol.revision(task.networkId) then
		finish(task,"selection_changed",true);return
	end
	local refs=task.admission.refs
	local first=refs[task.offset]
	if not first then finish(task);return end
	local dest,reason=GlobalStorageSiK.DepositSources.resolveExternalTarget(task.player,task.targetKey)
	if not dest then finish(task,reason or "target_unavailable",true);return end
	if dest~=task.binding.destination then finish(task,"target_unavailable",true);return end
	local ids,batch={},{}
	while task.offset+#ids<=#refs and #ids<task.batchUnits do
		local ref=refs[task.offset+#ids]
		if ref.fullType~=first.fullType or ref.sourceNodeId~=first.sourceNodeId then break end
		ids[#ids+1]=ref.itemId;batch[#batch+1]=ref
	end
	local valid,sealReason=GlobalStorageSiK.Index.validateExactBatchRefs(task.admission,batch)
	if not valid then finish(task,sealReason,true);return end
	local ok,transferReason,moved,movedIds,nodeIds,snapshotsUpdated=
		GlobalStorageSiK.TransferLock.withAuthorityLock(task.networkId,task.id,"withdrawBatch",function()
			return GlobalStorageSiK.InventorySync.withBatch(function()
				return GlobalStorageSiK.Transfer.withdrawType(task.player,first.fullType,task.networkId,#ids,dest,
					nil,nil,ids,nil,nil,task.batchUnits,first.sourceNodeId,{snapshotSession=task.snapshotSession})
			end)
		end)
	if ok==false and transferReason=="network_busy" then reportProgress(task);return end
	-- Physical confirmation is evidence even if a later identity check rejects
	-- the task. Never report zero for units already moved by Transfer.
	task.summary.moved=task.summary.moved+(tonumber(moved) or 0)
	task.summary.slices=task.summary.slices+1
	if snapshotsUpdated~=true then task.summary.snapshotsUpdated=false end
	mergeTouched(task,nodeIds)
	task.lastActivityMs=nowMs()
	local confirmed={}
	for i=1,#(movedIds or {}) do
		local id=tonumber(movedIds[i]);if not id or confirmed[id] then finish(task,"ticket_identity_mismatch",true);return end
		confirmed[id]=true
	end
	local consumed=0
	for i=1,#batch do
		local ref=batch[i]
		if confirmed[ref.itemId] then
			local owner=task.admission.selectors[ref.selectors[1]]
			owner.applied=(owner.applied or 0)+1
		end
		for j=1,#ref.selectors do
			local s=task.admission.selectors[ref.selectors[j]]
			if confirmed[ref.itemId] then s.moved=s.moved+1
			else s.reason=transferReason or "not_found" end
		end
		if confirmed[ref.itemId] then consumed=consumed+1 end
	end
	if consumed~=(tonumber(moved) or 0) then finish(task,"ticket_identity_mismatch",true);return end
	task.offset=task.offset+#batch
	local cleanReason=transferReason and string.gsub(transferReason,"^partial:","")
	if cleanReason and cleanReason~="not_found" then finish(task,cleanReason,true);return end
	if task.offset>#refs then finish(task);return end
	if nowMs()-(task.lastCheckpointMs or task.startedMs)>=1000 then
		local updated,nodes=GlobalStorageSiK.Transfer.flushDepositSessionSnapshots(task.snapshotSession)
		if updated~=true then task.summary.snapshotsUpdated=false end
		mergeTouched(task,nodes)
		GlobalStorageSiK.Index.checkpointExactBatch(task.admission,nodes)
		if callbacks.checkpoint then callbacks.checkpoint(task.player,task.networkId,task.meta,{snapshotsUpdated=updated,touchedNodeIds=nodes}) end
		task.revision=GlobalStorageSiK.Index.getInventoryRevision(task.networkId)
		task.lastCheckpointMs=nowMs();task.summary.checkpoints=(task.summary.checkpoints or 0)+1
	end
	reportProgress(task)
end

local function advanceTask(task,deadline)
	local player = GlobalStorageSiK.PlayerUtils.resolveByUsername(task.username)
	if player ~= task.player or (player and player.getPlayerNum and player:getPlayerNum() or -1) ~= task.playerNum then
		finish(task, "player_unavailable", true, true); return
	end
	task.player = player
	if callbacks.validate then
		local allowed, reason = callbacks.validate(player, task.networkId, task.meta)
		if not allowed then finish(task, reason or "terminal_access_changed", true); return end
	end
	if task.admission then advanceBatch(task,deadline);return end
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

local function startBatch(player,args,networkId)
	if args.batchVersion~=1 or args.readLoanId~=nil or args.returnItemIds==true
		or type(args.targetKey)~="string" or #args.targetKey<1 or #args.targetKey>192
		or GlobalStorageSiK.FloorTargets.isKey(args.targetKey) then return true,false,"invalid_request" end
	local pkey=playerKey(player)
	if not pkey or #order>=MAX_TASKS_GLOBAL or countForPlayer(pkey)>=MAX_TASKS_PER_PLAYER then return true,false,"task_limit" end
	local binding,reason
	if callbacks.captureBatch then binding,reason=callbacks.captureBatch(player,networkId,args) end
	if not binding then return true,false,reason or "invalid_request" end
	local admission,admissionReason=GlobalStorageSiK.Index.beginExactBatch(networkId,player,args.selectors,args.selectionRevision)
	if not admission then return true,false,admissionReason end
	local pacingId=tostring(args.withdrawId)
	local id="withdraw-task:"..pkey.."\31"..tostring(networkId).."\31"..pacingId
	local reserved,reserveReason=GlobalStorageSiK.WithdrawSelectionTickets.reserveTask(player,id)
	if not reserved then GlobalStorageSiK.Index.releaseExactBatch(admission);return true,false,reserveReason end
	local pacingKey=GlobalStorageSiK.Server.operationPacingKey(player,"withdraw",pacingId,networkId)
	local pacing=GlobalStorageSiK.OperationPacing.forOperation(pacingKey,{operationType="withdraw"})
	local task={id=id,playerKey=pkey,username=player:getUsername(),player=player,
		playerNum=player.getPlayerNum and player:getPlayerNum() or -1,networkId=networkId,
		targetKey=args.targetKey,binding=binding,admission=admission,admitting=true,offset=1,slotId=id,
		startedMs=nowMs(),revision=GlobalStorageSiK.Index.getInventoryRevision(networkId),
		batchUnits=math.min(10,math.max(1,math.floor(tonumber(pacing.batchUnits) or 10))),
		selectionCount=0,limit=0,touchedSet={},snapshotSession=GlobalStorageSiK.Transfer.createSnapshotSession(networkId),
		meta={selectionMode="exact_batch",withdrawId=args.withdrawId,pacingKey=pacingKey,
			selectionRevision=args.selectionRevision,searchQuery=args.searchQuery or ""},
		summary={moved=0,slices=0,snapshotsUpdated=true,touchedNodeIds={}}}
	tasks[id]=task;order[#order+1]=id
	return true,true
end

-- Returns applicable, started, reason. Older clients omit taskAmount and keep
-- the receipt-backed per-slice protocol unchanged.
function Tasks.start(player, args, networkId)
	if type(args)=="table" and args.selectionMode=="exact_batch" then return startBatch(player,args,networkId) end
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
		if task then
			task.turnStartedMs=nowMs();advanceTask(task,deadline)
			if task.turnStartedMs then task.activeWorkMs=(task.activeWorkMs or 0)+math.max(0,nowMs()-task.turnStartedMs);task.turnStartedMs=nil end
		else table.remove(order, cursor); cursor = cursor - 1 end
		serviced = serviced + 1
	end
	return serviced
end

function Tasks.pendingCount()
	return #order
end

return Tasks

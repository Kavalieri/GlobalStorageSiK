--[[
	GlobalStorageSiK - Leer literatura prestada desde la red
	Autor: SiK
	Descripcion: retira una instancia exacta, usa ISReadABook vanilla y
	devuelve el mismo itemId a su red original al completar o cancelar.
]]

require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISReadABook"
require "TimedActions/ISTimedActionQueue"
require "GS_DepositClient"
require "GS_I18n"
require "GS_UI_Feedback"
require "GS_Log"
require "GS_WithdrawClient"
local Sequence = require "GS_NetworkReadSequence"

GlobalStorageSiK.NetworkReadAction = GlobalStorageSiK.NetworkReadAction or {}

local START_WAIT_MS = 10000
local RETURN_WAIT_MS = 30000
local RETRY_MS = 1000

local serial = 0
local pendingStarts = {}
local pendingReturns = {}
local tickInstalled = false
local sessions = {}
local activeLoans = {}
local recoveryJobs = {}

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function playerFor(loan)
	if loan.session ~= (sessions[loan.playerNum or 0] or 0) then return nil end
	local current = getSpecificPlayer and getSpecificPlayer(loan.playerNum or 0) or nil
	if current ~= loan.player then return nil end
	return current
end

local function position(player)
	if not player or not player.getX or not player.getY or not player.getZ then return nil end
	return { x = player:getX(), y = player:getY(), z = player:getZ() }
end

local function moved(player, origin)
	if not origin then return false end
	return not player or math.abs(player:getX() - origin.x) > 0.001
		or math.abs(player:getY() - origin.y) > 0.001 or player:getZ() ~= origin.z
end

local function showError(player, key)
	if not player then return end
	pcall(function()
		GlobalStorageSiK.UIFeedback.halo(player, GlobalStorageSiK.I18n.text(key),
			255, 120, 120, 300, { tone = "danger" })
	end)
end

local function inventoryItemById(player, itemId)
	local inventory = player and player.getInventory and player:getInventory() or nil
	if not inventory or not itemId then return nil end
	if inventory.getItemWithID then
		local ok, item = pcall(function() return inventory:getItemWithID(itemId) end)
		if ok and item then return item end
	end
	if inventory.getItemById then
		local ok, item = pcall(function() return inventory:getItemById(itemId) end)
		if ok and item then return item end
	end
	local items = inventory.getItems and inventory:getItems() or nil
	if items then
		for i = 0, items:size() - 1 do
			local item = items:get(i)
			if item and item.getID and item:getID() == itemId then return item end
		end
	end
	return nil
end

local function countPending()
	local count = Sequence.hasPending() and 1 or 0
	for _ in pairs(pendingStarts) do count = count + 1 end
	for _, loan in pairs(pendingReturns) do
		if not loan.returnInFlight then count = count + 1 end
	end
	for _, job in pairs(recoveryJobs) do if not job.waiting then count = count + 1 end end
	return count
end

local function ensureTick()
	if tickInstalled or not Events or not Events.OnTick then return end
	tickInstalled = true
	Events.OnTick.Add(GlobalStorageSiK.NetworkReadAction.onTick)
end

local function uninstallTickIfIdle()
	if countPending() > 0 then return end
	if tickInstalled and Events and Events.OnTick then
		Events.OnTick.Remove(GlobalStorageSiK.NetworkReadAction.onTick)
	end
	tickInstalled = false
end

local function settleLoan(loan, ok)
	if loan.settled then return end
	loan.settled = true
	loan.player = nil
	if activeLoans[loan.loanId] == loan then activeLoans[loan.loanId] = nil end
	if loan.onSettled then loan.onSettled(ok) end
	if Sequence.hasPending() then ensureTick() end
end

local function scheduleReturn(loan, source)
	if not loan or loan.returnScheduled then return end
	if loan.session ~= (sessions[loan.playerNum] or 0) then settleLoan(loan, false); return end
	loan.returnScheduled = true
	loan.returnSource = source or "unknown"
	loan.nextAttemptMs = nowMs()
	loan.returnDeadlineMs = loan.nextAttemptMs + RETURN_WAIT_MS
	pendingReturns[loan.loanId] = loan
	GlobalStorageSiK.Log.info("NetworkReadAction", "return scheduled",
		"loanId=" .. tostring(loan.loanId) .. " itemId=" .. tostring(loan.itemId)
			.. " source=" .. tostring(loan.returnSource))
	ensureTick()
end

local function startVanillaRead(loan, player, item)
	if (loan.isCancelled and loan.isCancelled())
		or (player and player.isDead and player:isDead()) or moved(player, loan.position) then
		scheduleReturn(loan, "cancelled")
		return
	end
	if not player or not item or not ISReadABook or not ISTimedActionQueue then
		showError(player, "IGUI_GS_ReadStartFailed")
		scheduleReturn(loan, "start_unavailable")
		return
	end
	local data = item.getModData and item:getModData() or nil
	if loan.validateIdentity and tostring(data and data.literatureTitle or "")
		~= tostring(loan.literatureTitle or "") then
		showError(player, "IGUI_GS_ReadStartFailed")
		scheduleReturn(loan, "title_mismatch")
		return
	end
	if not item.getFullType or item:getFullType() ~= loan.fullType then
		showError(player, "IGUI_GS_ReadStartFailed")
		scheduleReturn(loan, "type_mismatch")
		return
	end

	local created, action = pcall(function() return ISReadABook:new(player, item) end)
	if not created or not action or type(action.perform) ~= "function"
		or type(action.stop) ~= "function" then
		showError(player, "IGUI_GS_ReadStartFailed")
		GlobalStorageSiK.Log.error("NetworkReadAction", "vanilla read action unavailable",
			"loanId=" .. tostring(loan.loanId) .. " error=" .. tostring(action))
		scheduleReturn(loan, "action_unavailable")
		return
	end
	local originalPerform = action.perform
	local originalStop = action.stop
	action.perform = function(self)
		local ok, result = pcall(originalPerform, self)
		scheduleReturn(loan, ok and "complete" or "perform_failed")
		if not ok then
			GlobalStorageSiK.Log.error("NetworkReadAction", "vanilla read perform failed",
				"loanId=" .. tostring(loan.loanId) .. " error=" .. tostring(result))
			return nil
		end
		return result
	end
	action.stop = function(self)
		local ok, result = pcall(originalStop, self)
		scheduleReturn(loan, "cancelled")
		if not ok then
			GlobalStorageSiK.Log.error("NetworkReadAction", "vanilla read stop failed",
				"loanId=" .. tostring(loan.loanId) .. " error=" .. tostring(result))
			return nil
		end
		return result
	end
	local queued, queueError = pcall(ISTimedActionQueue.add, action)
	if not queued then
		showError(player, "IGUI_GS_ReadStartFailed")
		GlobalStorageSiK.Log.error("NetworkReadAction", "vanilla read queue failed",
			"loanId=" .. tostring(loan.loanId) .. " error=" .. tostring(queueError))
		scheduleReturn(loan, "queue_failed")
		return
	end
	GlobalStorageSiK.Log.info("NetworkReadAction", "read queued",
		"loanId=" .. tostring(loan.loanId) .. " itemId=" .. tostring(loan.itemId)
			.. " fullType=" .. tostring(loan.fullType))
end

local function getVanillaText(key, fallback)
	if getText then
		local ok, value = pcall(getText, key)
		if ok and value and value ~= key then return value end
	end
	return fallback
end

---@param rowData table|nil
---@param player IsoPlayer|nil
---@return table|nil { probe, label, available, tooltip }
function GlobalStorageSiK.NetworkReadAction.describe(rowData, player)
	if not rowData or not rowData.fullType or not instanceItem then return nil end
	local ok, probe = pcall(instanceItem, rowData.fullType)
	if not ok or not probe or not probe.getCategory or probe:getCategory() ~= "Literature" then
		return nil
	end
	if probe.canBeWrite and probe:canBeWrite() then return nil end

	local modData = probe.getModData and probe:getModData() or nil
	-- Context eligibility uses the captured title, never the random title of
	-- a newly created probe. The borrowed object is checked again before reading.
	local literatureTitle = rowData.literatureTitle or (modData and modData.literatureTitle)
	local isPrintMedia = modData and modData.printMedia ~= nil
	local picture = probe.hasTag and ItemTag and probe:hasTag(ItemTag.PICTURE)
	local pictureBook = probe.hasTag and ItemTag and probe:hasTag(ItemTag.PICTUREBOOK)
	local illiterate = player and player.hasTrait and CharacterTrait
		and player:hasTrait(CharacterTrait.ILLITERATE)
	local recentlyRead = literatureTitle and player
		and player.isLiteratureRead and player:isLiteratureRead(literatureTitle)

	local baseLabel = getVanillaText("ContextMenu_Read", "Read")
	if isPrintMedia then
		baseLabel = getVanillaText("ContextMenu_Inspect", "Inspect")
	elseif illiterate and pictureBook and recentlyRead then
		baseLabel = getVanillaText("ContextMenu_ReLook_at_pictures", baseLabel)
	elseif illiterate and pictureBook then
		baseLabel = getVanillaText("ContextMenu_Look_at_pictures", baseLabel)
	elseif picture and recentlyRead then
		baseLabel = getVanillaText("ContextMenu_ReLook_at_picture", baseLabel)
	elseif picture then
		baseLabel = getVanillaText("ContextMenu_Look_at_picture", baseLabel)
	elseif recentlyRead then
		baseLabel = getVanillaText("ContextMenu_ReRead", baseLabel)
	end

	local available = true
	local tooltip = nil
	if player and player.tooDarkToRead and player:tooDarkToRead() then
		available = false
		local darkKey = "ContextMenu_TooDark"
		if isPrintMedia then
			darkKey = "ContextMenu_TooDarkToInspect"
		elseif picture or (illiterate and pictureBook) then
			darkKey = "ContextMenu_TooDarkToSee"
		end
		tooltip = getVanillaText(darkKey, "Too dark")
	elseif isPrintMedia and player and player.isAsleep and player:isAsleep() then
		available = false
		tooltip = getVanillaText("ContextMenu_NoOptionSleeping", "Unavailable while sleeping")
	elseif illiterate and not pictureBook and not picture then
		available = false
		tooltip = getVanillaText("ContextMenu_Illiterate", "Cannot read")
	elseif probe.hasTag and ItemTag and probe:hasTag(ItemTag.UNINTERESTING) then
		available = false
		tooltip = getVanillaText("ContextMenu_EmptyNotebook", "Nothing to read")
	else
		local skill = probe.getSkillTrained and probe:getSkillTrained() or nil
		local skillBook = skill and SkillBook and SkillBook[skill] or nil
		local perk = skillBook and skillBook.perk or nil
		local level = perk and player and player.getPerkLevel and player:getPerkLevel(perk) or nil
		local minLevel = probe.getLvlSkillTrained and probe:getLvlSkillTrained() or -1
		local maxLevel = probe.getMaxLevelTrained and probe:getMaxLevelTrained() or -1
		if level and minLevel ~= -1 and minLevel > level + 1 then
			available = false
			tooltip = getVanillaText("ContextMenu_TooComplicated", "Too complicated")
		elseif level and maxLevel ~= -1 and maxLevel <= level then
			available = false
			tooltip = getVanillaText("ContextMenu_TooSimple", "Too simple")
		end
	end

	return {
		probe = probe,
		label = GlobalStorageSiK.I18n.text("IGUI_GS_ReadAndReturn", baseLabel),
		available = available,
		tooltip = tooltip,
	}
end

---@param rowData table
---@param player IsoPlayer
---@param networkId string
---@param searchQuery string|nil
---@return boolean
function GlobalStorageSiK.NetworkReadAction.request(rowData, player, networkId, searchQuery, options)
	local spec = GlobalStorageSiK.NetworkReadAction.describe(rowData, player)
	if not spec or not spec.available or not player or not networkId then return false end
	serial = serial + 1
	local loan = {
		loanId = "Read-" .. tostring(nowMs()) .. "-" .. tostring(serial),
		playerNum = player.getPlayerNum and player:getPlayerNum() or 0,
		networkId = networkId,
		fullType = rowData.fullType,
		literatureTitle = rowData.literatureTitle,
		validateIdentity = rowData._gsReadIdentity == true,
		onSettled = options and options.onSettled,
		isCancelled = options and options.isCancelled,
		position = position(player),
		player = player,
	}
	loan.session = sessions[loan.playerNum] or 0
	sessions[loan.playerNum] = loan.session
	activeLoans[loan.loanId] = loan
	local sent = GlobalStorageSiK.WithdrawClient.sendWithdraw(
		rowData, 1, "player:main", searchQuery, {
			networkId = networkId, playerNum = loan.playerNum,
			returnItemIds = true,
			readLoanId = loan.loanId,
			onComplete = function(ok, result)
				-- A completed borrow belongs to this loan for its entire lifecycle.
				-- A repeated callback must never enqueue a second vanilla action,
				-- including after the exact item has already been returned.
				if loan.borrowResolved then return end
				loan.borrowResolved = true
				if loan.session ~= (sessions[loan.playerNum] or 0) then
					settleLoan(loan, false)
					return
				end
				local ids = result and result.itemIds or {}
				if #ids ~= 1 then
					showError(playerFor(loan), "IGUI_GS_ReadBorrowFailed")
					settleLoan(loan, false)
					return
				end
				loan.itemId = ids[1]
				loan.preferredNodeId = result and result.sourceNodeId or nil
				if not ok then
					showError(playerFor(loan), "IGUI_GS_ReadBorrowFailed")
					scheduleReturn(loan, "borrow_incomplete")
					return
				end
				loan.startDeadlineMs = nowMs() + START_WAIT_MS
				pendingStarts[loan.loanId] = loan
				ensureTick()
			end,
		})
	if not sent then settleLoan(loan, false) end
	return sent
end

function GlobalStorageSiK.NetworkReadAction.requestSelection(rows, player, networkId, searchQuery)
	if not player then return false end
	local plan = Sequence.plan(rows, GlobalStorageSiK.NetworkReadAction.describe, player)
	if not plan then return false end
	local origin = position(player)
	return Sequence.start(player:getPlayerNum(), plan, function(row, onSettled, isCancelled)
		if moved(player, origin) or (player.isDead and player:isDead()) then return false end
		return GlobalStorageSiK.NetworkReadAction.request(row, player, networkId, searchQuery,
			{ onSettled = onSettled, isCancelled = isCancelled })
	end)
end

---@param context ISContextMenu
---@param player IsoPlayer|nil
---@param rowData table
---@param terminal GS_TerminalUI
function GlobalStorageSiK.NetworkReadAction.addToContext(context, player, rowData, terminal, selectedRows)
	local spec = GlobalStorageSiK.NetworkReadAction.describe(rowData, player)
	if not spec then return end
	local rows = selectedRows or { rowData }
	local plan = Sequence.plan(rows, GlobalStorageSiK.NetworkReadAction.describe, player)
	if not plan then
		if #rows ~= 1 or spec.available then return end
		plan = {} -- Preserve the vanilla disabled option and its explanation.
	end
	local option = context:addOption(spec.label, plan, function(captured)
		local networkId = terminal and terminal.terminalState and terminal.terminalState.networkId
		local searchQuery = terminal and terminal.itemSearchQuery or nil
		GlobalStorageSiK.NetworkReadAction.requestSelection(captured, player, networkId, searchQuery)
	end)
	option.itemForTexture = spec.probe
	if not spec.available then
		option.notAvailable = true
		if ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.addToolTip then
			option.toolTip = ISInventoryPaneContextMenu.addToolTip()
			option.toolTip.description = spec.tooltip or ""
		end
	end
end

function GlobalStorageSiK.NetworkReadAction.onTick()
	GlobalStorageSiK.NetworkReadAction.updateRecovery()
	Sequence.update()
	local now = nowMs()
	local startIds = {}
	for loanId in pairs(pendingStarts) do startIds[#startIds + 1] = loanId end
	for i = 1, #startIds do
		local loan = pendingStarts[startIds[i]]
		if loan then
			local player = playerFor(loan)
			local item = inventoryItemById(player, loan.itemId)
			if item then
				pendingStarts[loan.loanId] = nil
				startVanillaRead(loan, player, item)
			elseif now >= (loan.startDeadlineMs or 0) then
				pendingStarts[loan.loanId] = nil
				showError(player, "IGUI_GS_ReadStartFailed")
				scheduleReturn(loan, "sync_timeout")
			end
		end
	end

	local returnIds = {}
	for loanId in pairs(pendingReturns) do returnIds[#returnIds + 1] = loanId end
	for i = 1, #returnIds do
		local loan = pendingReturns[returnIds[i]]
		if loan and not loan.returnInFlight and now >= (loan.nextAttemptMs or 0) then
			local player = playerFor(loan)
			local sent = false
			if player then
				-- Queue acceptance is not a completed transfer. Keep this exact loan
				-- until its logical job receives the final authoritative ACK.
				loan.returnInFlight = true
				sent = GlobalStorageSiK.DepositClient.sendDepositItems(
					{ loan.itemId }, player, {
						networkId = loan.networkId,
						origin = "network_read_return",
						operationId = loan.loanId,
						preferredNodeId = loan.preferredNodeId,
						onComplete = function(ok, result)
							if pendingReturns[loan.loanId] ~= loan then return end
							loan.returnInFlight = false
							if ok and result and result.moved == 1 then
								pendingReturns[loan.loanId] = nil
								settleLoan(loan, loan.returnSource == "complete" or loan.recovery == true)
							elseif nowMs() >= loan.returnDeadlineMs then
								pendingReturns[loan.loanId] = nil
								showError(playerFor(loan), "IGUI_GS_ReadReturnFailed")
								settleLoan(loan, false)
							else
								loan.nextAttemptMs = nowMs() + RETRY_MS
							end
							ensureTick()
						end,
					})
			end
			if sent then
				GlobalStorageSiK.Log.info("NetworkReadAction", "return queued",
					"loanId=" .. tostring(loan.loanId) .. " itemId=" .. tostring(loan.itemId)
						.. " preferredNodeId=" .. tostring(loan.preferredNodeId))
			elseif now >= (loan.returnDeadlineMs or 0) then
				pendingReturns[loan.loanId] = nil
				showError(player, "IGUI_GS_ReadReturnFailed")
				settleLoan(loan, false)
				GlobalStorageSiK.Log.error("NetworkReadAction", "return queue timeout",
					"loanId=" .. tostring(loan.loanId) .. " itemId=" .. tostring(loan.itemId))
			else
				loan.returnInFlight = false
				loan.nextAttemptMs = now + RETRY_MS
			end
		end
	end
	uninstallTickIfIdle()
end

-- Opening an authorized terminal supplies a fresh private journal projection.
-- No login polling, inventory sweep, automatic learning or new transfer path.
function GlobalStorageSiK.NetworkReadAction.onTerminalOpen(args)
	if type(args) ~= "table" or type(args.readLoans) ~= "table" or #args.readLoans == 0 then return end
	local playerNum = tonumber(args.playerNum) or 0
	local player = getSpecificPlayer and getSpecificPlayer(playerNum)
	if not player or recoveryJobs[playerNum] then return end
	local records = {}
	for i = 1, math.min(#args.readLoans, 64) do
		local row = args.readLoans[i]
		if type(row) == "table" then
			records[#records + 1] = {
				loanId = row.loanId, itemId = row.itemId, networkId = row.networkId,
				fullType = row.fullType, preferredNodeId = row.preferredNodeId,
			}
		end
	end
	recoveryJobs[playerNum] = {
		player = player, networkId = args.networkId, rows = records, index = 1,
	}
	ensureTick()
end

function GlobalStorageSiK.NetworkReadAction.updateRecovery()
	local slots = {}
	for playerNum in pairs(recoveryJobs) do slots[#slots + 1] = playerNum end
	for i = 1, #slots do
		local playerNum = slots[i]
		local job = recoveryJobs[playerNum]
		local player = getSpecificPlayer and getSpecificPlayer(playerNum)
		if not player or player ~= job.player or (player.isDead and player:isDead()) then
			recoveryJobs[playerNum] = nil
		elseif not job.waiting then
			while job.index <= math.min(#job.rows, 64) do
				local record = job.rows[job.index]
				job.index = job.index + 1
				if type(record) == "table" and type(record.loanId) == "string"
					and record.networkId == job.networkId and not activeLoans[record.loanId] then
					local item = inventoryItemById(player, record.itemId)
					if item and item:getFullType() == record.fullType then
						local loan = {
							loanId = record.loanId, itemId = record.itemId, fullType = record.fullType,
							playerNum = playerNum, player = player, networkId = job.networkId,
							preferredNodeId = record.preferredNodeId, recovery = true,
							session = sessions[playerNum] or 0,
							onSettled = function(ok)
								if recoveryJobs[playerNum] ~= job then return end
								if ok then job.waiting = false else recoveryJobs[playerNum] = nil end
								ensureTick()
							end,
						}
						sessions[playerNum] = loan.session
						activeLoans[loan.loanId] = loan
						job.waiting = true
						scheduleReturn(loan, "recovery")
						break
					end
				end
			end
			if not job.waiting then recoveryJobs[playerNum] = nil end
		end
	end
end

function GlobalStorageSiK.NetworkReadAction.cancelPlayer(player)
	local playerNum = player and player.getPlayerNum and player:getPlayerNum()
	if playerNum == nil or (getSpecificPlayer and getSpecificPlayer(playerNum) ~= player) then return end
	Sequence.cancel(playerNum)
end

local function onDisconnect()
	Sequence.cancelAll()
	-- No callback from the previous connection may address a new character
	-- merely because it reused the same split-screen slot.
	local slots = {}
	for playerNum in pairs(sessions) do slots[#slots + 1] = playerNum end
	for i = 1, #slots do sessions[slots[i]] = sessions[slots[i]] + 1 end
	pendingStarts, pendingReturns = {}, {}
	activeLoans, recoveryJobs = {}, {}
	uninstallTickIfIdle()
end

if Events and Events.OnPlayerDeath then
	Events.OnPlayerDeath.Add(GlobalStorageSiK.NetworkReadAction.cancelPlayer)
end
if Events and Events.OnDisconnect then Events.OnDisconnect.Add(onDisconnect) end

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
require "GS_Log"
require "GS_WithdrawClient"

GlobalStorageSiK.NetworkReadAction = GlobalStorageSiK.NetworkReadAction or {}

local START_WAIT_MS = 10000
local RETURN_WAIT_MS = 30000
local RETRY_MS = 1000

local serial = 0
local pendingStarts = {}
local pendingReturns = {}
local tickInstalled = false

local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function playerFor(loan)
	return getSpecificPlayer and getSpecificPlayer(loan.playerNum or 0) or nil
end

local function showError(player, key)
	if not player or not player.setHaloNote then return end
	pcall(function()
		player:setHaloNote(GlobalStorageSiK.I18n.text(key), 255, 120, 120, 300)
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
	local count = 0
	for _ in pairs(pendingStarts) do count = count + 1 end
	for _ in pairs(pendingReturns) do count = count + 1 end
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

local function scheduleReturn(loan, source)
	if not loan or loan.returnScheduled then return end
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
	if not player or not item or not ISReadABook or not ISTimedActionQueue then
		showError(player, "IGUI_GS_ReadStartFailed")
		scheduleReturn(loan, "start_unavailable")
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
		scheduleReturn(loan, "complete")
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
	local isPrintMedia = modData and modData.printMedia ~= nil
	local picture = probe.hasTag and ItemTag and probe:hasTag(ItemTag.PICTURE)
	local pictureBook = probe.hasTag and ItemTag and probe:hasTag(ItemTag.PICTUREBOOK)
	local illiterate = player and player.hasTrait and CharacterTrait
		and player:hasTrait(CharacterTrait.ILLITERATE)
	local recentlyRead = modData and modData.literatureTitle and player
		and player.isLiteratureRead and player:isLiteratureRead(modData.literatureTitle)

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
function GlobalStorageSiK.NetworkReadAction.request(rowData, player, networkId, searchQuery)
	local spec = GlobalStorageSiK.NetworkReadAction.describe(rowData, player)
	if not spec or not spec.available or not player or not networkId then return false end
	serial = serial + 1
	local loan = {
		loanId = "Read-" .. tostring(nowMs()) .. "-" .. tostring(serial),
		playerNum = player.getPlayerNum and player:getPlayerNum() or 0,
		networkId = networkId,
		fullType = rowData.fullType,
	}
	return GlobalStorageSiK.WithdrawClient.sendWithdraw(
		rowData, 1, "player:main", searchQuery, {
			networkId = networkId,
			returnItemIds = true,
			onComplete = function(ok, result)
				local ids = result and result.itemIds or {}
				if not ok or #ids ~= 1 then
					showError(playerFor(loan) or player, "IGUI_GS_ReadBorrowFailed")
					return
				end
				loan.itemId = ids[1]
				loan.startDeadlineMs = nowMs() + START_WAIT_MS
				pendingStarts[loan.loanId] = loan
				ensureTick()
			end,
		})
end

---@param context ISContextMenu
---@param player IsoPlayer|nil
---@param rowData table
---@param terminal GS_TerminalUI
function GlobalStorageSiK.NetworkReadAction.addToContext(context, player, rowData, terminal)
	local spec = GlobalStorageSiK.NetworkReadAction.describe(rowData, player)
	if not spec then return end
	local option = context:addOption(spec.label, rowData, function(data)
		local networkId = terminal and terminal.terminalState and terminal.terminalState.networkId
		local searchQuery = terminal and terminal.itemSearchQuery or nil
		GlobalStorageSiK.NetworkReadAction.request(data, player, networkId, searchQuery)
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
		if loan and now >= (loan.nextAttemptMs or 0) then
			local player = playerFor(loan)
			local sent = false
			if player then
				sent = GlobalStorageSiK.DepositClient.sendDepositItems(
					{ loan.itemId }, player, {
						networkId = loan.networkId,
						origin = "network_read_return",
						operationId = loan.loanId,
					})
			end
			if sent then
				pendingReturns[loan.loanId] = nil
				GlobalStorageSiK.Log.info("NetworkReadAction", "return queued",
					"loanId=" .. tostring(loan.loanId) .. " itemId=" .. tostring(loan.itemId))
			elseif now >= (loan.returnDeadlineMs or 0) then
				pendingReturns[loan.loanId] = nil
				showError(player, "IGUI_GS_ReadReturnFailed")
				GlobalStorageSiK.Log.error("NetworkReadAction", "return queue timeout",
					"loanId=" .. tostring(loan.loanId) .. " itemId=" .. tostring(loan.itemId))
			else
				loan.nextAttemptMs = now + RETRY_MS
			end
		end
	end
	uninstallTickIfIdle()
end

require "GS_UI_Framework"

GlobalStorageSiK = GlobalStorageSiK or {}

local UI = SiK.UI
local Feedback = GlobalStorageSiK.UIFeedback or {}
GlobalStorageSiK.UIFeedback = Feedback

local cleanupInstalled = false
local statuses = {}
local operations = {}
local statusTickInstalled = false
local nextStatusCheck = 0

local function clockMs() return getTimestampMs and tonumber(getTimestampMs()) or 0 end

local function expireStatuses()
	local now = clockMs()
	if now < nextStatusCheck then return end
	nextStatusCheck = now + 100
	local expired, remaining = {}, 0
	for playerNum, entry in pairs(statuses) do
		if now >= entry.expiresMs or not entry.ui.terminalState
			or entry.ui.terminalState.headerTransient ~= entry.value then
			expired[#expired + 1] = playerNum
		else remaining = remaining + 1 end
	end
	for i = 1, #expired do
		local entry = statuses[expired[i]]
		statuses[expired[i]] = nil
		if entry.ui.terminalState and entry.ui.terminalState.headerTransient == entry.value then
			entry.ui.terminalState.headerTransient = nil
			if entry.ui.syncHeaderChrome then entry.ui:syncHeaderChrome() end
		end
	end
	if remaining == 0 and statusTickInstalled then
		Events.OnTick.Remove(expireStatuses)
		statusTickInstalled = false
	end
end

local function playerNumber(player, explicit)
	local value = tonumber(explicit)
	if value == nil and player and player.getPlayerNum then value = tonumber(player:getPlayerNum()) end
	if value == nil or value ~= math.floor(value) or value < 0 or value > 3 then return nil end
	return value
end

function Feedback.installCleanup()
	if cleanupInstalled then return true end
	local client = GlobalStorageSiK.Client
	if not client or type(client.registerTransientCleanup) ~= "function" then return false end
	cleanupInstalled = client.registerTransientCleanup("sik-ui-feedback", function(playerNum)
		Feedback.clear(playerNum)
	end) == true
	return cleanupInstalled
end

-- Reuse the existing transient status slot, never a second window or halo.
-- At most one entry per local player; the tick exists only until expiry.
function Feedback.status(player, text, options)
	options = options or {}
	Feedback.installCleanup()
	local playerNum = playerNumber(player, options.playerNum)
	if playerNum == nil or playerNum > 3 then return nil, "invalid_player_num" end
	if player and player.getPlayerNum and player:getPlayerNum() ~= playerNum then
		return nil, "player_mismatch"
	end
	local terminal = GlobalStorageSiK.TerminalUI
	local ui = terminal and terminal.getInstanceForPlayer and terminal.getInstanceForPlayer(playerNum)
	if not ui or not ui.terminalState or not ui.syncHeaderChrome then return nil, "no_status_surface" end
	local expiry = clockMs() + math.min(5000, math.max(1200, tonumber(options.durationMs) or 1800))
	local value = { text = tostring(text or ""), tone = "text", expiresMs = expiry }
	ui.terminalState.headerTransient = value
	statuses[playerNum] = { ui = ui, value = value, expiresMs = expiry, channel = options.channel or "global-storage" }
	ui:syncHeaderChrome()
	if not statusTickInstalled and Events and Events.OnTick then
		Events.OnTick.Add(expireStatuses)
		statusTickInstalled = true
	end
	return "status"
end

function Feedback.halo(player, text, r, g, b, duration, options)
	options = options or {}
	Feedback.installCleanup()
	if (options.tone ~= "danger" and options.tone ~= "warning")
		or options.channel == "timed-action" then
		local statusOptions = {}
		for key, value in pairs(options) do statusOptions[key] = value end
		statusOptions.durationMs = statusOptions.durationMs or duration
		return Feedback.status(player, text, statusOptions)
	end
	local playerNum = playerNumber(player, options.playerNum)
	if playerNum == nil then return nil, "missing_player_num" end
	return UI.Feedback.halo({
		player = player,
		playerNum = playerNum,
		text = text,
		tone = options.tone or "info",
		color = { r = r, g = g, b = b },
		durationMs = duration,
		channel = options.channel or "global-storage",
		dedupeKey = options.dedupeKey,
		policy = options.policy or "dedupe",
		throttleMs = options.throttleMs or 600,
		maxQueue = options.maxQueue,
		presentation = "note",
	})
end

-- A running transfer is lifecycle-owned, not a transient message with a TTL.
-- Its ID prevents a late finish from clearing a newer gesture's presentation.
local function refreshOperationHeader(playerNum)
	local terminal = GlobalStorageSiK.TerminalUI
	local ui = terminal and terminal.getInstanceForPlayer and terminal.getInstanceForPlayer(playerNum)
	if ui and ui.syncHeaderChrome then ui:syncHeaderChrome() end
end

function Feedback.beginOperation(player, operationId, networkId, channel)
	local playerNum = playerNumber(player)
	if playerNum == nil or playerNum > 3 or type(operationId) ~= "string" then return false end
	local previous = operations[playerNum]
	if previous then return previous.id == operationId and previous.networkId == networkId end
	Feedback.installCleanup()
	operations[playerNum] = { id = operationId, networkId = networkId, channel = channel,
		label = "", mode = "indeterminate", tone = "warning", status = "warning", showProgress = true }
	return true
end

function Feedback.updateOperation(playerNum, operationId, label, done, total)
	local entry = operations[playerNum]
	if not entry or entry.id ~= operationId then return false end
	done, total = tonumber(done) or 0, tonumber(total) or 0
	if done ~= done or total ~= total or done == math.huge or total == math.huge
		or done == -math.huge or total == -math.huge then return false end
	entry.label = tostring(label or "")
	entry.mode = total > 0 and "determinate" or "indeterminate"
	entry.value = total > 0 and math.max(0, math.min(1, done / total)) or nil
	refreshOperationHeader(playerNum)
	return true
end

function Feedback.operationFor(playerNum, networkId)
	local entry = operations[playerNum]
	if entry and entry.networkId == networkId then return entry end
	return nil
end

function Feedback.finishOperation(playerNum, operationId)
	local entry = operations[playerNum]
	if not entry or entry.id ~= operationId then return false end
	operations[playerNum] = nil
	refreshOperationHeader(playerNum)
	return true
end

function Feedback.clear(playerNum, channel)
	local keys = {}
	for key in pairs(statuses) do
		if (playerNum == nil or key == playerNum) and (channel == nil or statuses[key].channel == channel) then
			keys[#keys + 1] = key
		end
	end
	for i = 1, #keys do statuses[keys[i]].expiresMs = 0 end
	nextStatusCheck = 0
	expireStatuses()
	local operationKeys = {}
	for key, entry in pairs(operations) do
		if (playerNum == nil or key == playerNum) and (channel == nil or entry.channel == channel) then
			operationKeys[#operationKeys + 1] = key
		end
	end
	for i = 1, #operationKeys do
		local key = operationKeys[i]
		Feedback.finishOperation(key, operations[key].id)
	end
	return UI.Feedback.clear(playerNum, channel)
end

return Feedback

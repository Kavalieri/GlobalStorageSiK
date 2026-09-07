require "GS_UI_Framework"

GlobalStorageSiK = GlobalStorageSiK or {}

local UI = SiK.UI
local Feedback = GlobalStorageSiK.UIFeedback or {}
GlobalStorageSiK.UIFeedback = Feedback

local cleanupInstalled = false
local statuses = {}
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
	if value == nil then return nil end
	return math.max(0, math.floor(value))
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
	statuses[playerNum] = { ui = ui, value = value, expiresMs = expiry }
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
		return Feedback.status(player, text, options)
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

function Feedback.clear(playerNum, channel)
	local keys = {}
	for key in pairs(statuses) do
		if playerNum == nil or key == playerNum then keys[#keys + 1] = key end
	end
	for i = 1, #keys do statuses[keys[i]].expiresMs = 0 end
	nextStatusCheck = 0
	expireStatuses()
	return UI.Feedback.clear(playerNum, channel)
end

return Feedback

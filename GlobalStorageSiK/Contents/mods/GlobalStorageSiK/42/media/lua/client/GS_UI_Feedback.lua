require "GS_UI_Framework"

GlobalStorageSiK = GlobalStorageSiK or {}

local UI = SiK.UI
local Feedback = GlobalStorageSiK.UIFeedback or {}
GlobalStorageSiK.UIFeedback = Feedback

local cleanupInstalled = false

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
		UI.Feedback.clear(playerNum)
	end) == true
	return cleanupInstalled
end

function Feedback.halo(player, text, r, g, b, duration, options)
	options = options or {}
	Feedback.installCleanup()
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
		-- Direct product calls historically displayed every invocation. Keep that
		-- semantic unless a caller deliberately opts into queue/dedupe; progress
		-- channels still throttle through their explicit throttleMs contract.
		policy = options.policy or "replace",
		throttleMs = options.throttleMs,
		maxQueue = options.maxQueue,
		presentation = "note",
	})
end

function Feedback.clear(playerNum, channel)
	return UI.Feedback.clear(playerNum, channel)
end

return Feedback

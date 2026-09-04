-- Shared author-test double for the public GS -> SiK.UI feedback adapter.
-- Product modules must require GS_UI_Feedback explicitly; isolated harnesses
-- install this double instead of weakening that runtime dependency.

local Stub = {}

function Stub.install()
	GlobalStorageSiK = GlobalStorageSiK or {}

	local calls = {}
	local feedback = {
		calls = calls,
		cleanupInstalled = false,
	}

	function feedback.halo(player, text, r, g, b, duration, options)
		calls[#calls + 1] = {
			kind = "halo",
			player = player,
			text = text,
			r = r,
			g = g,
			b = b,
			duration = duration,
			options = options,
		}
		return true
	end

	function feedback.clear(playerNum, channel)
		calls[#calls + 1] = {
			kind = "clear",
			playerNum = playerNum,
			channel = channel,
		}
		return true
	end

	function feedback.installCleanup()
		feedback.cleanupInstalled = true
		return true
	end

	GlobalStorageSiK.UIFeedback = feedback
	package.loaded["GS_UI_Feedback"] = feedback
	return feedback
end

return Stub

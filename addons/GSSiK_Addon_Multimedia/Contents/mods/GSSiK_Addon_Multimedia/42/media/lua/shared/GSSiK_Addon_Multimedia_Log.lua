local Sandbox = require "GSSiK_Addon_Multimedia_Sandbox"
local API = require "GSSiK_API"
local Log = {}
GSSiK_Addon_Multimedia.Log = Log
local budgets = {}
local function emit(level, category, message)
	if not Sandbox.debug(category) then return end
	local now = getTimestampMs and getTimestampMs() or 0
	local bucket = budgets[category]
	if not bucket or now < bucket.time or now - bucket.time >= 1000 then
		bucket = { time = now, count = 0 }; budgets[category] = bucket
	end
	if bucket.count >= 10 then return end
	bucket.count = bucket.count + 1
	message = tostring(message)
	if #message > 1024 then message = "diagnostic_too_long" end
	local _, _, origin = API.Diagnostics.processTag()
	local line = "[" .. tostring(origin or "?") .. "][GSSiK_Addon_Multimedia:"
		.. level .. "][" .. category .. "] " .. message
	-- Single owned console sink; all call sites use this gated logger.
	print(line)
	API.Diagnostics.emit(line)
end
function Log.debug(category, message) emit("DEBUG", category, message) end
function Log.error(category, message) emit("ERROR", category, message) end
return Log

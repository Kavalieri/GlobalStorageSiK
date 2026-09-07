-- Dynamic policy contract for transient UI feedback and transfer errors.

for _, name in ipairs({ "GS_UI_Framework", "GS_I18n", "GS_UI_Feedback", "GS_TransferFeedback" }) do
	package.loaded[name] = nil
end
local now = 0
local tick, removedTick, statusSyncs = nil, 0, { [0] = 0, [1] = 0 }
local haloCalls = {}
local cleanup
local players = {}
local surfaces = {}
for i = 0, 1 do
	players[i] = { getPlayerNum = function() return i end }
	surfaces[i] = { terminalState = {}, syncHeaderChrome = function() statusSyncs[i] = statusSyncs[i] + 1 end }
end

SiK = { UI = { Feedback = {
	halo = function(options) haloCalls[#haloCalls + 1] = options; return "halo" end,
	clear = function(playerNum) return playerNum end,
} } }
GlobalStorageSiK = {
	I18n = { text = function(key) return "text:" .. key end },
	Client = { registerTransientCleanup = function(_, callback) cleanup = callback; return true end },
	TerminalUI = { getInstanceForPlayer = function(playerNum) return surfaces[playerNum] end },
	NetClient = { getPlayer = function(playerNum) return players[playerNum] end },
}
getTimestampMs = function() return now end
getSpecificPlayer = function(playerNum) return players[playerNum] end
Events = { OnTick = {
	Add = function(callback) tick = callback end,
	Remove = function(callback) if tick == callback then tick = nil; removedTick = removedTick + 1 end end,
} }
package.preload["GS_UI_Framework"] = function() return true end
package.preload["GS_I18n"] = function() return true end

local Feedback = dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_UI_Feedback.lua")
package.preload["GS_UI_Feedback"] = function() return Feedback end
local TransferFeedback = dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TransferFeedback.lua")

local function status(playerNum, text, options)
	return Feedback.status(players[playerNum], text, options)
end

assert(Feedback.halo(players[0], "bad", 1, 2, 3, 1200,
	{ tone = "danger", channel = "transfer-error", dedupeKey = "n:op:full" }) == "halo")
assert(#haloCalls == 1 and haloCalls[1].durationMs == 1200
	and haloCalls[1].playerNum == 0 and haloCalls[1].dedupeKey == "n:op:full",
	"danger halo did not preserve brief dedupe policy")
Feedback.halo(players[0], "bad", 1, 2, 3, 1200,
	{ tone = "danger", channel = "transfer-error", dedupeKey = "n:op:full" })
assert(#haloCalls == 2 and haloCalls[2].policy == "dedupe", "duplicate error did not use dedupe adapter policy")

assert(Feedback.halo(players[0], "info", 1, 2, 3, 1200, { tone = "info" }) == "status")
assert(Feedback.halo(players[0], "ok", 1, 2, 3, 1200, { tone = "success" }) == "status")
assert(Feedback.halo(players[0], "working", 1, 2, 3, 1200,
	{ tone = "danger", channel = "timed-action" }) == "status")
assert(#haloCalls == 2, "info/success/timed-action incorrectly emitted halos")
assert(status(0, "one", { durationMs = 1800 }) == "status")
assert(status(0, "two", { durationMs = 1800 }) == "status")
assert(surfaces[0].terminalState.headerTransient.text == "two", "status slot was not reused per player")
assert(status(1, "other", { durationMs = 1800 }) == "status")
assert(statusSyncs[0] >= 1 and statusSyncs[1] == 1, "status did not target player-local surfaces")

assert(Feedback.status(players[0], "wrong", { playerNum = 1 }) == nil, "player mismatch was accepted")
assert(cleanup and tick, "feedback cleanup/listener was not installed")
cleanup(0)
assert(surfaces[0].terminalState.headerTransient == nil
	and surfaces[1].terminalState.headerTransient ~= nil, "clearing one player affected another")
now = 2000
tick()
assert(surfaces[1].terminalState.headerTransient == nil and tick == nil and removedTick == 1,
	"TTL did not remove the last status listener")

local reasons = { "carry_weight", "destination_full", "no_room", "no_space", "partial:destination_full" }
for i = 1, #reasons do
	local reason = reasons[i]
	assert(TransferFeedback.showResult({ playerNum = 0, networkId = "net", transfer = {
		 reason = reason, op = "deposit", pacingId = "p1" } }) == true,
		"transfer reason was not presented: " .. reason)
end
assert(#haloCalls == 2 + #reasons, "transfer errors created a modal or bypassed the common adapter")
for i = 3, #haloCalls do
	assert(haloCalls[i].channel == "transfer-error" and haloCalls[i].policy == "dedupe",
		"transfer error did not use the shared dedupe halo policy")
	assert(haloCalls[i].dedupeKey:find(":", 1, true), "transfer error lost its reason/dedupe identity")
end
print("PASS UI feedback policy contract")

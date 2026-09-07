require "GS_UI_Feedback"
require "GS_I18n"
GlobalStorageSiK.TransferFeedback = {}
local Feedback = GlobalStorageSiK.TransferFeedback
local function text(key) return GlobalStorageSiK.I18n.text(key) end
local reasonKeys = {
	carry_weight = "IGUI_GS_TransferCarryWeight",
	destination_full = "IGUI_GS_TransferDestinationFull",
	no_room = "IGUI_GS_TransferDestinationFull",
	no_space = "IGUI_GS_TransferDestinationFull",
	no_compatible_destination = "IGUI_GS_TransferNoCompatible",
	source_unavailable = "IGUI_GS_TransferSourceUnavailable",
	no_permission = "IGUI_GS_RequireAdminRole",
}

function Feedback.showResult(args)
	local transfer = args and args.transfer
	local reason = transfer and tostring(transfer.reason or "") or ""
	if string.sub(reason, 1, 8) == "partial:" then reason = string.sub(reason, 9) end
	local key = reasonKeys[reason]
	if not key then return false end
	if transfer.op == "redistribute" and reason == "destination_full" then key = "IGUI_GS_TransferCompatibleFull" end
	local playerNum = tonumber(args.playerNum) or 0
	local message = text(key)
	local player = getSpecificPlayer and getSpecificPlayer(playerNum)
	if not player and GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer then
		player = GlobalStorageSiK.NetClient.getPlayer(playerNum)
	end
	if not player then return false end
	-- Feedback never mutates a queue or acknowledges a transfer. The result
	-- handlers alone account for confirmed IDs and decide whether to continue.
	GlobalStorageSiK.UIFeedback.halo(player, message, 235, 90, 90, 1200, {
		playerNum = playerNum, tone = "danger", channel = "transfer-error",
		policy = "dedupe", throttleMs = 600,
		dedupeKey = tostring(args.networkId or "") .. ":"
			.. tostring(transfer.pacingId or transfer.operationId or transfer.queueId
				or transfer.withdrawId or args.operationId or "") .. ":" .. reason,
	})
	return true
end

return Feedback

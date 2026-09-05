local UI = require "GS_UI_Framework"
require "GS_I18n"
GlobalStorageSiK.TransferFeedback = {}
local Feedback = GlobalStorageSiK.TransferFeedback
local active = {}
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
	local titleKey = reason == "carry_weight" and "IGUI_GS_TransferWeightTitle"
		or (reason == "no_compatible_destination" or transfer.op == "redistribute")
			and "IGUI_GS_TransferDestinationsTitle" or "IGUI_GS_TransferSpaceTitle"
	if reason == "source_unavailable" or reason == "no_permission" then
		titleKey = "IGUI_GS_TransferWarning"
	end
	if active[playerNum] then
		active[playerNum].message:setText(message)
		active[playerNum].block.header:setText(text(titleKey))
		UI.Controls.setTooltip(active[playerNum].block.header.info, message,
			{ playerNum = playerNum, profile = "informational", channel = "informational-help" })
		active[playerNum].panel:reflow()
		return true
	end
	local modal, copy, remaining, block, actions, acknowledge
	modal = UI.Modal.create({ kind = "compact", playerNum = playerNum,
		title = text("IGUI_GS_TransferWarning"), contentHeight = 180, contentMode = "dock",
		onClose = function() active[playerNum] = nil end,
		buildContent = function(host, rect)
			block = UI.Block.create({ parent = host, w = rect.w,
				title = text(titleKey), tooltip = message, playerNum = playerNum })
			copy = UI.Controls.copyText(block.childParent, { w = rect.w,
				text = message, tone = "text", playerNum = playerNum })
			remaining = UI.Controls.copyText(block.childParent, { w = rect.w,
				text = text("IGUI_GS_TransferRemaining"), tone = "textMuted", playerNum = playerNum })
			actions = UI.Block.create({ parent = host, w = rect.w,
				title = text("IGUI_GS_PermColActions"), tooltip = text("IGUI_GS_Acknowledge"), playerNum = playerNum })
			acknowledge = UI.Controls.button(actions.childParent, {
				text = text("IGUI_GS_Acknowledge"), leadingIcon = "sik.check.18", success = true,
				onClick = function() UI.Modal.close(modal, "acknowledge") end })
		end })
	if not modal then return false end
	local originalReflow = modal.reflow
	modal.reflow = function(self)
		if self._feedbackLayoutBusy then return self end
		self._feedbackLayoutBusy = true
		originalReflow(self)
		local width = self.contentHost.width
		block:setBounds(0, 0, width, block.h)
		local column = block:beginColumn()
		copy:reflow(column.width); remaining:reflow(column.width)
		column:block(copy, copy.height); column:block(remaining, remaining.height)
		local height = column:finish()
		actions:setBounds(0, height + 8, width, actions.h)
		local buttons = actions:beginColumn()
		buttons:block(acknowledge, UI.Controls.metrics("editor").buttonHeight)
		UI.Modal.fitContent(self, height + 8 + buttons:finish(), { center = true })
		-- fitContent changes the window bounds while the layout guard is active.
		-- Apply the final content rectangle without recursively fitting again.
		originalReflow(self)
		self._feedbackLayoutBusy = false
		return self
	end
	active[playerNum] = { panel = modal, message = copy, block = block }
	modal:reflow()
	UI.Modal.show(modal)
	return true
end

return Feedback

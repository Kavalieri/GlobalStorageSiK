-- Global Storage SiK - product adapter for the neutral SiK.UI confirmation modal.
--
-- This module owns only product wiring.  Layout, Escape/close rejection,
-- focus, buttons and icon rendering remain in SiK.UI.Modal.confirm.

local UI = require "GS_UI_Framework"
require "GS_I18n"

GlobalStorageSiK = GlobalStorageSiK or {}
GlobalStorageSiK.Confirmation = GlobalStorageSiK.Confirmation or {}

local Confirmation = GlobalStorageSiK.Confirmation

local ASSET_ALERT_DANGER = "sik.alert.danger.24"
local ASSET_CLOSE = "sik.close.18"
local ASSET_CHECK = "sik.check.18"

--- Shows a destructive-or-confirming product action through the neutral modal.
--- `question` and `consequences` are product-owned, already localized copy.
--- @param options table {playerNum,title,question,consequences,onAccept,onReject}
--- @return table|nil panel
function Confirmation.show(options)
	options = options or {}
	if type(options.question) ~= "string" or options.question == "" then
		return nil, "missing_confirmation_question"
	end
	return UI.Modal.confirm({
		playerNum = options.playerNum,
		title = options.title,
		question = options.question,
		consequences = options.consequences,
		actionsTitle = GlobalStorageSiK.I18n.text("IGUI_GS_PermColActions"),
		alert = {
			icon = options.alertIcon or ASSET_ALERT_DANGER,
			severity = options.severity or "danger",
			glow = options.glow ~= false,
			tooltip = options.alertTooltip or options.question,
		},
		reject = { text = GlobalStorageSiK.I18n.text("IGUI_GS_No"), icon = ASSET_CLOSE, danger = true },
		accept = { text = GlobalStorageSiK.I18n.text("IGUI_GS_Yes"), icon = ASSET_CHECK, success = true },
		onAccept = options.onAccept,
		onReject = options.onReject,
	})
end

return Confirmation

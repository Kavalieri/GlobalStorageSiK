-- Product copy and lifecycle for the approved transport notice. Geometry,
-- wrapping, scrolling, focus and Escape belong to the existing SiK.UI APIs.
local UI = require "GS_UI_Framework"
require "GS_I18n"
local Feedback = {}
local instances = {}
local T = GlobalStorageSiK.I18n.text
local reasonKeys = {
	catalog_timeout="Timeout", catalog_incomplete="Incomplete", catalog_schema="Incomplete",
	catalog_duplicate="Incomplete", catalog_encoding="Encoding", catalog_string_size="Encoding",
	catalog_budget="Budget", catalog_busy="Busy", catalog_access_changed="AccessChanged",
	catalog_cache_miss="CacheMiss", catalog_apply="Apply", catalog_send="Send",
}

function Feedback.clear(playerNum)
	if playerNum == nil then
		for n = 0, 3 do Feedback.clear(n) end
		return
	end
	local panel = instances[playerNum]
	if panel then UI.Modal.close(panel, "superseded") end
end

function Feedback.show(playerNum, reason, confirmed)
	Feedback.clear(playerNum)
	local prefix = confirmed and "IGUI_GS_CatalogFailure" or "IGUI_GS_AccessTimeout"
	local hint = T(prefix .. "Hint")
	if reasonKeys[reason] then hint = hint .. " " .. T("IGUI_GS_Catalog" .. reasonKeys[reason]) end
	local panel, dock, body, actions, message, recovery, button
	local metrics = UI.Controls.metrics("compact")
	local buttonHeight = math.max(metrics.buttonHeight, UI.Metrics.profile(0, "editor").controls.buttonHeight)
	-- Keep the approved 720px width when fitContent resolves bounds again.
	-- This existing profile is limited by the player's safe viewport.
	panel = UI.Modal.create({kind="compact", profile="terminal-config", playerNum=playerNum,
		title=T(prefix .. "Title"), width=UI.Modal.STANDARD_MODAL_W,
		height=300, contentMode="dock", resizable=false, closeOnEscape=true,
		onClose=function()
			if instances[playerNum] == panel then instances[playerNum] = nil end
		end,
		buildContent=function(host, rect)
			dock = UI.ScrollDock.create({parent=host, x=0, y=0, w=rect.w,
				h=rect.h, padding=0, playerNum=playerNum})
			body = UI.Block.create({parent=dock.contentHost, w=rect.w, h=160,
				title=T(prefix .. "Block"), tooltip=hint, headerHeight=26, playerNum=playerNum})
			message = UI.Controls.copyText(body.childParent, {w=rect.w,
				text=T(prefix .. "Body"), tone="text", playerNum=playerNum})
			recovery = UI.Controls.copyText(body.childParent, {w=rect.w,
				text=T("IGUI_GS_CatalogRecovery"), tone="textMuted", playerNum=playerNum})
			actions = UI.Block.create({parent=dock.fixedBottomHost, w=rect.w, h=70,
				title=T("IGUI_GS_PermColActions"), tooltip=T("IGUI_GS_CatalogCloseHint"), headerHeight=26, playerNum=playerNum})
			button = UI.Controls.button(actions.childParent, {text=T("IGUI_GS_Close"),
				leadingIcon="sik.check.18", iconSize=18, success=true, playerNum=playerNum,
				onClick=function() UI.Modal.close(panel, "close") end})
		end})
	if not panel then return end
	local baseReflow, baseDispose = panel.reflow, panel.dispose
	panel.reflow = function(self)
		baseReflow(self)
		if self._gsNoticeLayout or not dock then return self end
		self._gsNoticeLayout = true
		local rect = self:contentRect()
		dock:reflow(0, 0, rect.w, rect.h)
		for pass = 1, 3 do
			local width = UI.Scroll.contentWidth(dock.scroll)
			body:setBounds(0, 0, width, body.h)
			local column = body:beginColumn()
			message:reflow(column.width); column:block(message, message.height, UI.Metrics.spacing.md)
			recovery:reflow(column.width); column:block(recovery, recovery.height)
			local height = column:finish()
			actions:setBounds(0, 0, rect.w, actions.h)
			local buttons = actions:beginColumn()
			buttons:row(buttonHeight, {{widget=button}})
			local actionHeight = buttons:finish()
			dock:setFixedBottomHeight(actionHeight); dock:setContentHeight(height)
			self._gsNoticeHeight = height + dock.gap + actionHeight
			if width == UI.Scroll.contentWidth(dock.scroll) then break end
		end
		self._gsNoticeLayout = nil
		return self
	end
	panel.dispose = function(self)
		if dock then body:dispose(); actions:dispose(); dock:dispose(); dock=nil end
		return baseDispose(self)
	end
	instances[playerNum] = panel
	panel:reflow()
	UI.Modal.fitContent(panel, panel._gsNoticeHeight, {center=true})
	UI.Modal.show(panel, button)
	return panel
end

return Feedback

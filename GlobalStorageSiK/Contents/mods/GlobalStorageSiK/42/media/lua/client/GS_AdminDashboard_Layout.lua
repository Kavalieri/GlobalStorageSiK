-- Staff product composition. Block owns padding; Table owns its row viewport.
require "GS_I18n"
local UI = require "GS_UI_Framework"
local Layout = {}
local T = GlobalStorageSiK.I18n.text
local GAP = 8
local metrics = UI.Controls.metrics("staff")

local function place(widget, x, y, w, h)
	UI.Layout.apply(widget, { x = x, y = y, w = w, h = h })
end

local function block(parent, title, help)
	local result, reason = UI.Block.create({ parent = parent, x = 0, y = 0, w = 400, h = 100,
		title = T(title), tooltip = T(help) })
	if not result then error("Staff Block: " .. tostring(reason)) end
	return result
end

local function naturalHeight(frame, bodyHeight)
	return UI.Block.intrinsicHeight(bodyHeight, {
		headerHeight = frame.headerHeight, headerGap = GAP,
	})
end

local function button(parent, text, callback, danger)
	return UI.Controls.button(parent, { x = 0, y = 0, w = 200, h = metrics.buttonHeight,
		text = T(text), onClick = callback, danger = danger == true, fullWidth = true })
end

function Layout.build(ui)
	ui.supportScroll = UI.Scroll.create(ui.networkTabRoot, 0, 0,
		ui.networkTabRoot.width, ui.networkTabRoot.height)
	local parent = UI.Scroll.childHost(ui.supportScroll)
	ui.selectedNetworkBlock = block(parent, "IGUI_GS_AdminSelectedNetworkTitle", "IGUI_GS_AdminSelectedNetworkHelp")
	ui.internalTestsBlock = block(parent, "IGUI_GS_AdminInternalTests", "IGUI_GS_AdminInternalTestsHelp")
	ui.membersBlock = block(parent, "IGUI_GS_AdminMembersTitle", "IGUI_GS_AdminMembersHelp")
	ui.networkActionsBlock = block(parent, "IGUI_GS_AdminNetworkActionsTitle", "IGUI_GS_AdminNetworkActionsHelp")
	local selected = ui.selectedNetworkBlock.childParent
	ui.networkCombo = UI.Controls.combo(selected, { x = 0, y = 0, w = 200, h = metrics.inputHeight,
		onChange = function() ui:onComboChanged() end })
	ui.infoLbls, ui.infoRightLabels = {}, {}
	ui.reloadBtn = button(selected, "IGUI_GS_AdminReload", function()
		ui:requestNetworkList()
		if ui._selectedNetworkId then ui:requestMembers(ui._selectedNetworkId) end
	end)
	ui.historyBtn = button(selected, "IGUI_GS_AdminHistoryButton", function() ui:requestHistory() end)
	ui.staffActionButtons = {}
	local actions = GlobalStorageSiK.TerminalExtensions.getStaffActions()
	for index = 1, #actions do
		local action = actions[index]
		ui.staffActionButtons[index] = button(ui.internalTestsBlock.childParent, action.labelKey,
			function() action.invoke(ui) end)
	end
	ui.addMemberCombo = UI.Controls.combo(ui.membersBlock.childParent,
		{ x = 0, y = 0, w = 200, h = metrics.inputHeight })
	ui.addMemberBtn = button(ui.membersBlock.childParent, "IGUI_GS_AdminAddMember", function() ui:onAddMember() end)
	ui.releaseBtn = button(ui.networkActionsBlock.childParent, "IGUI_GS_AdminReleaseOwnership",
		function() ui:onReleaseOwnership() end)
	ui.deleteBtn = button(ui.networkActionsBlock.childParent, "IGUI_GS_AdminDeleteNetwork",
		function() ui:onDeleteNetworkConfirm() end, true)
	UI.Scroll.setOnContentRectChanged(ui.supportScroll, function() Layout.reflow(ui) end)
	Layout.reflow(ui)
end

local function equalButtons(buttons, rect, top, columns)
	local width = math.max(1, (rect.w - GAP * (columns - 1)) / columns)
	for index = 1, #buttons do
		local row, column = math.floor((index - 1) / columns), (index - 1) % columns
		place(buttons[index], rect.x + column * (width + GAP), top + row * (metrics.buttonHeight + GAP),
			width, metrics.buttonHeight)
	end
	return math.ceil(#buttons / columns) * (metrics.buttonHeight + GAP) - (#buttons > 0 and GAP or 0)
end

local function selectedInfo(ui, width)
	local frame = ui.selectedNetworkBlock
	frame:setBounds(0, 0, width, 300)
	local rect = frame:getContentRect()
	place(ui.networkCombo, rect.x, rect.y, rect.w, metrics.inputHeight)
	local top = rect.y + metrics.inputHeight + GAP
	local half = math.max(1, (rect.w - GAP) / 2)
	local net = ui._selectedNetwork
	local left, right = "", ""
	if net then
		left = (net.vacant and T("IGUI_GS_AdminInfoVacant") or T("IGUI_GS_AdminInfoOwner", net.owner or "?"))
			.. "\n" .. T("IGUI_GS_AdminInfoAccount", net.ownerAccountLogin or "?")
		local active = net.activeMemberCount or net.memberCount or 0
		right = T("IGUI_GS_AdminNetworkCounts", active,
			math.max(0, (net.memberCount or 0) - active), net.terminalCount or 0)
	end
	local afterLeft = UI.Controls.renderWrappedLinePool(frame.childParent, ui.infoLbls,
		{ text = left, x = rect.x, y = top, w = half, lineGap = 2 })
	local afterRight = UI.Controls.renderWrappedLinePool(frame.childParent, ui.infoRightLabels,
		{ text = right, x = rect.x + half + GAP, y = top, w = half, lineGap = 2 })
	local actionY = math.max(afterLeft, afterRight) + GAP
	equalButtons({ ui.reloadBtn, ui.historyBtn }, rect, actionY, 2)
	local height = naturalHeight(frame, actionY - rect.y + metrics.buttonHeight)
	frame:setBounds(0, 0, width, height)
	return height
end

function Layout.reflow(ui)
	if not ui.supportScroll or ui._supportLayoutActive then return end
	ui._supportLayoutActive = true
	UI.Scroll.resize(ui.supportScroll, ui.networkTabRoot.width, ui.networkTabRoot.height)
	-- At most two passes: setting content height can add/remove the outer bar.
	for pass = 1, 2 do
		local width = UI.Scroll.contentWidth(ui.supportScroll)
		local top = selectedInfo(ui, width) + GAP
		local count = #ui.staffActionButtons
		local tools = ui.internalTestsBlock
		tools.panel:setVisible(count > 0)
		if count > 0 then
			local cols = math.min(2, count)
			local height = naturalHeight(tools, math.ceil(count / cols) * (metrics.buttonHeight + GAP) - GAP)
			tools:setBounds(0, top, width, height)
			local rect = tools:getContentRect()
			equalButtons(ui.staffActionButtons, rect, rect.y, cols)
			top = top + height + GAP
		end
		local actions = ui.networkActionsBlock
		local actionsHeight = naturalHeight(actions, metrics.buttonHeight)
		local members = ui.membersBlock
		local memberHeight = math.max(230, ui.networkTabRoot.height - top - GAP - actionsHeight)
		members:setBounds(0, top, width, memberHeight)
		local rect = members:getContentRect()
		UI.Controls.fitButtonToContent(ui.addMemberBtn)
		local buttonWidth = math.min(rect.w, ui.addMemberBtn:getWidth())
		place(ui.addMemberCombo, rect.x, rect.y, math.max(1, rect.w - buttonWidth - GAP), metrics.inputHeight)
		place(ui.addMemberBtn, rect.x + rect.w - buttonWidth, rect.y, buttonWidth, metrics.inputHeight)
		ui._memberTableRect = { x = rect.x, y = rect.y + metrics.inputHeight + GAP,
			w = rect.w, h = math.max(1, rect.h - metrics.inputHeight - GAP) }
		if ui.memberTableBlock then ui.memberTableBlock:layout(ui._memberTableRect) end
		top = top + memberHeight + GAP
		actions:setBounds(0, top, width, actionsHeight)
		rect = actions:getContentRect()
		equalButtons({ ui.releaseBtn, ui.deleteBtn }, rect, rect.y, 2)
		UI.Scroll.setContentHeight(ui.supportScroll, top + actionsHeight)
		if UI.Scroll.contentWidth(ui.supportScroll) == width then break end
	end
	ui._supportLayoutActive = nil
end

function Layout.dispose(ui)
	for _, key in ipairs({ "selectedNetworkBlock", "internalTestsBlock", "membersBlock", "networkActionsBlock" }) do
		if ui[key] then ui[key]:dispose(); ui[key] = nil end
	end
end

return Layout

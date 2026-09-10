-- Product editor for the third Staff Block approved by Kava (2026-09-08).
local UI = require "GS_UI_Framework"
local Model = require "GS_NativeWorldEditorModel"
local Sync = require "GS_NativeWorldSync"
local View = {}
local T = GlobalStorageSiK.I18n.text
local GAP, HEIGHT = 8, UI.Controls.metrics().inputHeight
local function text(key, ...) return T("IGUI_GS_WorldTax_" .. key, ...) end
local function value(combo)
	local item = combo:getSelectedItem()
	return item and item.value or nil
end
function View.lookup(view)
	view.model:setFullType(view.fullType:getText())
	view.model:lookup()
	View.refresh(view, true)
end

local function submit(view, operation)
	view.model:setFullType(view.fullType:getText())
	view.model:setReason(view.reason:getText())
	view.model:submit(operation)
	View.refresh(view, true)
end

function View.build(ui, parent, reflow)
	local frame, reason = UI.Block.create({ parent = parent, x = 0, y = 0, w = 400, h = 300,
		title = text("Title"), tooltip = text("Help") })
	if not frame then error("Staff world taxonomy: " .. tostring(reason)) end
	local view = { frame = frame, playerNum = ui.playerNum or 0, reflow = reflow, combos = {} }
	view.model = Model.create(view.playerNum)
	local host = frame.childParent
	local function status(key, framed)
		return UI.Controls.status(host, { text = text(key), w = 200, wrap = true, framed = framed, tone = "text" })
	end
	local function button(key, fn)
		return UI.Controls.button(host, { text = text(key), w = 200, h = HEIGHT, fullWidth = true, onClick = fn })
	end
	view.typeLabel, view.choiceLabel, view.reasonLabel = status("Type"), status("Choice"), status("Reason")
	view.fullType = UI.Controls.field(host, { w = 200, maxLength = 160,
		onChange = function() view.model:setFullType(view.fullType:getText()); View.refresh(view, true) end })
	view.lookup = button("Consult", function() View.lookup(view) end)
	view.current = status("ConsultFirst", true)
	for i = 1, 3 do
		local level = i
		view.combos[i] = UI.Controls.combo(host, { w = 150, playerNum = view.playerNum,
			onChange = function()
				view.model:select(level, value(view.combos[level])); View.refresh(view, true)
			end })
	end
	view.reason = UI.Controls.field(host, { w = 200, maxLength = 512,
		onChange = function() view.model:setReason(view.reason:getText()); View.refresh(view, true) end })
	view.apply = button("Apply", function() submit(view, "apply") end)
	view.restore = button("Restore", function() submit(view, "restore") end)
	view.feedback = status("Idle")
	ui.worldTaxonomyView = view
	Sync.request(false, view.playerNum)
	View.refresh(view, true)
	return view
end

function View.refresh(view, force)
	if not view then return end
	local state = view.model:snapshot()
	local stamp = tostring(state.busy) .. ":" .. tostring(state.canApply) .. ":" .. tostring(state.canRestore)
		.. ":" .. state.current.text .. ":" .. state.feedback.text
	if not force and view.stamp == stamp then return end
	view.stamp = stamp
	view.current:setStatus(state.current.text, state.current.tone)
	view.feedback:setStatus(state.feedback.text, state.feedback.tone)
	view.apply:setEnable(state.canApply); view.restore:setEnable(state.canRestore)
	view.lookup:setEnable(not state.busy)
	view.fullType:setEnabled(not state.busy); view.reason:setEnabled(not state.busy)
	for i = 1, 3 do
		local selected = state.selected["l" .. tostring(i)]
		view.combos[i]:setItems(state.choices[i], selected)
		view.combos[i]:setEnabled(not state.busy and selected ~= nil)
	end
	view.reflow()
end

function View.layout(view, width, top)
	view.frame:setBounds(0, top, width, 300)
	local rect = view.frame:getContentRect()
	local y = rect.y
	local function place(widget, x, w, h)
		UI.Layout.apply(widget, { x = x, y = y, w = w, h = h })
	end
	local function line(widget)
		widget:reflow(rect.w); place(widget, rect.x, rect.w, widget.height)
		y = y + widget.height + GAP
	end
	line(view.typeLabel)
	local consultW = math.min(math.floor(rect.w / 2), getTextManager():MeasureStringX(UIFont.Small, text("Consult")) + 24)
	place(view.fullType, rect.x, rect.w - consultW - GAP, HEIGHT)
	place(view.lookup, rect.x + rect.w - consultW, consultW, HEIGHT); y = y + HEIGHT + GAP
	line(view.current); line(view.choiceLabel)
	local third = math.floor((rect.w - GAP * 2) / 3)
	for i = 1, 3 do place(view.combos[i], rect.x + (third + GAP) * (i - 1),
		i == 3 and rect.w - (third + GAP) * 2 or third, HEIGHT) end
	y = y + HEIGHT + GAP
	line(view.reasonLabel); place(view.reason, rect.x, rect.w, HEIGHT); y = y + HEIGHT + GAP
	local half = math.floor((rect.w - GAP) / 2)
	place(view.apply, rect.x, half, HEIGHT); place(view.restore, rect.x + half + GAP, rect.w - half - GAP, HEIGHT)
	y = y + HEIGHT + GAP; line(view.feedback)
	local height = UI.Block.intrinsicHeight(y - GAP - rect.y, { headerHeight = view.frame.headerHeight, headerGap = GAP })
	view.frame:setBounds(0, top, width, height)
	return height
end

return View

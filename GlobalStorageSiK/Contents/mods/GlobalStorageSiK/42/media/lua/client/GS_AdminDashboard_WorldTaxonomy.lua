-- Product editor for the third Staff Block approved by Kava (2026-09-08).
local UI = require "GS_UI_Framework"
local Editor = require "GS_NativeWorldEditor"
local Sync = require "GS_NativeWorldSync"
local View = {}
local T = GlobalStorageSiK.I18n.text
local World = GlobalStorageSiK.NativeWorldOverrides
local GAP, HEIGHT = 8, UI.Controls.metrics().inputHeight
local function text(key, ...) return T("IGUI_GS_WorldTax_" .. key, ...) end
local function value(combo)
	local item = combo:getSelectedItem()
	return item and item.value or nil
end
local function label(key) return T("IGUI_GS_NativeTax_" .. key) end
local function choices(source, array)
	local items = {}
	for key, entry in pairs(source or {}) do
		local id = array and entry or key
		items[#items + 1] = { value = id, text = label(id) }
	end
	table.sort(items, function(a, b) return a.text == b.text and a.value < b.value or a.text < b.text end)
	return items
end
local function cascade(view, level, path)
	local tree = GlobalStorageSiK.NativeTaxonomyRegistry.getTree()
	if level == 1 then view.combos[1]:setItems(choices(tree), path and path.l1) end
	local l1 = value(view.combos[1])
	if level <= 2 then view.combos[2]:setItems(choices(tree[l1]), path and path.l2) end
	local l2 = value(view.combos[2])
	view.combos[3]:setItems(choices(tree[l1] and tree[l1][l2], true), path and path.l3)
	view.combos[3]:setEnabled(value(view.combos[3]) ~= nil)
end
local function feedback(view, key, reason, tone)
	view.feedback:setStatus(text(key, reason or ""), tone or "info")
	view.reflow()
end

function View.lookup(view)
	view.captured = nil
	local fullType = view.fullType:getText()
	if not World.validFullType(fullType) or not GlobalStorageSiK.I18n.getScriptItem(fullType) then
		feedback(view, "InvalidType", nil, "warning"); return
	end
	local revision = World.getRevision()
	if revision == nil then Sync.request(true, view.playerNum); feedback(view, "Sync"); return end
	local result = GlobalStorageSiK.NativeClassifier.classify(fullType)
	if not result or result.pending or not result.primaryPath then feedback(view, "Sync"); return end
	local path = result.primaryPath
	view.captured = { fullType = fullType, revision = revision,
		classifierSchema = GlobalStorageSiK.CatalogManager.getClassifierSchema(),
		catalogFingerprint = GlobalStorageSiK.CatalogManager.getCatalogFingerprintDigest(),
		worldOverride = result.classificationScope == "world" }
	local names = {}
	for _, id in ipairs({ path.l1, path.l2, path.l3 }) do names[#names + 1] = label(id) end
	view.current:setStatus(text("Current", table.concat(names, " > "),
		text(view.captured.worldOverride and "World" or "Automatic")))
	cascade(view, 1, path)
	feedback(view, "Idle")
	View.refresh(view, true)
end

local function submit(view, operation)
	if not view.captured or view.fullType:getText() ~= view.captured.fullType then
		feedback(view, "ConsultFirst", nil, "warning"); return
	end
	local parts = {}
	for i = 1, 3 do local id = value(view.combos[i]); if id then parts[#parts + 1] = id end end
	local ok, reason = Editor.submit(view.playerNum, view.captured, operation,
		"native:" .. table.concat(parts, "/"), view.reason:getText())
	if not ok then feedback(view, "Failed", reason, "warning") end
	View.refresh(view, true)
end

function View.build(ui, parent, reflow)
	local frame, reason = UI.Block.create({ parent = parent, x = 0, y = 0, w = 400, h = 300,
		title = text("Title"), tooltip = text("Help") })
	if not frame then error("Staff world taxonomy: " .. tostring(reason)) end
	local view = { frame = frame, playerNum = ui.playerNum or 0, reflow = reflow, combos = {} }
	local host = frame.childParent
	local function status(key, framed)
		return UI.Controls.status(host, { text = text(key), w = 200, wrap = true, framed = framed, tone = "text" })
	end
	local function button(key, fn)
		return UI.Controls.button(host, { text = text(key), w = 200, h = HEIGHT, fullWidth = true, onClick = fn })
	end
	view.typeLabel, view.choiceLabel, view.reasonLabel = status("Type"), status("Choice"), status("Reason")
	view.fullType = UI.Controls.field(host, { w = 200, maxLength = 160,
		onChange = function() view.captured = nil; View.refresh(view, true) end })
	view.lookup = button("Consult", function() View.lookup(view) end)
	view.current = status("ConsultFirst", true)
	for i = 1, 3 do
		local level = i
		view.combos[i] = UI.Controls.combo(host, { w = 150, playerNum = view.playerNum,
			onChange = function() if level < 3 then cascade(view, level + 1) end end })
	end
	view.reason = UI.Controls.field(host, { w = 200, maxLength = 512,
		onChange = function() View.refresh(view, true) end })
	view.apply = button("Apply", function() submit(view, "apply") end)
	view.restore = button("Restore", function() submit(view, "restore") end)
	view.feedback = status("Idle")
	ui.worldTaxonomyView = view
	cascade(view, 1)
	Sync.request(false, view.playerNum)
	View.refresh(view, true)
	return view
end

function View.refresh(view, force)
	if not view then return end
	local state = Editor.state(view.playerNum)
	if not state then return end
	local revision = World.getRevision()
	local stamp = tostring(state.status) .. ":" .. tostring(state.requestId) .. ":" .. tostring(revision)
	if not force and view.stamp == stamp then return end
	view.stamp = stamp
	local busy = state.status == "pending" or state.status == "uncertain"
	local captured = view.captured
	local valid = captured and captured.revision == revision and captured.fullType == view.fullType:getText()
	local reason = view.reason:getText()
	valid = valid and type(reason) == "string" and #reason <= 512 and reason:find("%S") ~= nil and not reason:find("%c")
	view.apply:setEnable(not busy and valid == true)
	view.restore:setEnable(not busy and valid == true and captured.worldOverride == true)
	view.fullType:setEnabled(not busy); view.reason:setEnabled(not busy)
	for i = 1, 3 do view.combos[i]:setEnabled(not busy and value(view.combos[i]) ~= nil) end
	if state.status == "pending" then feedback(view, "Pending")
	elseif state.status == "uncertain" then feedback(view, "Uncertain", nil, "warning")
	elseif state.status == "success" then
		feedback(view, (state.syncPending or (state.revision and revision and revision < state.revision)) and "Sync" or "Success", nil, "success")
	elseif state.status == "failed" then feedback(view, "Failed", state.reason, "warning") end
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

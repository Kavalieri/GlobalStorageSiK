--[[
	GlobalStorageSiK - Neutral SiK UI control factory.
	Consumers provide text and callbacks; this module owns only shared chrome.
]]

require "GS_SiK_UI_Core"

local SiK_UI = GlobalStorageSiK.SiK_UI
SiK_UI.Controls = SiK_UI.Controls or {}

local Controls = SiK_UI.Controls

local function fontHeight(font)
	if getTextManager and UIFont then
		return getTextManager():getFontHeight(font or UIFont.Small)
	end
	return 14
end

local function addToParent(parent, widget)
	if parent and widget and parent.addChild then parent:addChild(widget) end
	return widget
end

local function optionNumber(options, key, fallback)
	local value = options and tonumber(options[key]) or nil
	if value == nil then return fallback end
	return math.floor(value)
end

--- Canonical control dimensions. Profile changes density, never alignment.
function Controls.metrics(profile)
	local height = fontHeight(UIFont and UIFont.Small or nil) + 10
	local profileMetrics = SiK_UI.Metrics and SiK_UI.Metrics.profile
		and SiK_UI.Metrics.profile(profile or "standard") or nil
	local density = profileMetrics and profileMetrics.controls or nil
	return {
		buttonHeight = height,
		inputHeight = height,
		sectionHeight = height,
		statusHeight = height,
		rowGap = density and density.rowGap or 8,
		controlGap = density and density.controlGap or 8,
		windowPadding = 14,
		blockPadding = 8,
		resizeHandle = SiK_UI.Metrics.tokens().resizeHandle,
	}
end

function Controls.sectionTitle(parent, options)
	options = options or {}
	local label = SiK_UI.createSectionLabel(
		optionNumber(options, "x", 0), optionNumber(options, "y", 0),
		tostring(options.text or ""))
	label._sikUiControl = "sectionTitle"
	return addToParent(parent, label)
end

-- Cabecera canónica de bloque: Info -> Title -> Action. El consumidor aporta
-- contenido y callbacks; la fábrica conserva orden, separación y anclaje.
---@param parent ISUIElement
---@param options table {x,y,w,text,tooltip,target,action?}
---@return table header {info,title,action,height}
function Controls.blockHeader(parent, options)
	options = options or {}
	local metrics = Controls.metrics(options.profile)
	local x = optionNumber(options, "x", 0)
	local y = optionNumber(options, "y", 0)
	local w = optionNumber(options, "w", parent and parent.width or 360)
	local gap = optionNumber(options, "gap", metrics.controlGap)
	local cursorX = x
	local result = { height = metrics.sectionHeight }
	if options.tooltip and options.tooltip ~= "" then
		local size = fontHeight(UIFont and UIFont.Small or nil)
		result.info = SiK_UI.createInfoHintButton(cursorX,
			y + math.floor((metrics.sectionHeight - size) / 2), size,
			options.target or parent, options.tooltip)
		result.info._sikUiControl = "blockHeaderInfo"
		addToParent(parent, result.info)
		cursorX = cursorX + size + gap
	end
	result.title = SiK_UI.createSectionLabel(cursorX, y, tostring(options.text or ""))
	result.title._sikUiControl = "blockHeaderTitle"
	addToParent(parent, result.title)
	if type(options.action) == "table" then
		local action = options.action
		local actionW = optionNumber(action, "w", 120)
		result.action = Controls.button(parent, {
			x = x + math.max(0, w - actionW), y = y,
			w = actionW, h = metrics.buttonHeight,
			text = action.text, target = action.target or options.target or parent,
			onClick = action.onClick, tooltip = action.tooltip,
			danger = action.danger, activeColor = action.activeColor,
			locked = action.locked,
		})
		result.action._sikUiControl = "blockHeaderAction"
	end
	return result
end

function Controls.button(parent, options)
	options = options or {}
	local metrics = Controls.metrics(options.profile)
	local button = SiK_UI.createButton(
		optionNumber(options, "x", 0), optionNumber(options, "y", 0),
		optionNumber(options, "w", 360),
		optionNumber(options, "h", metrics.buttonHeight),
		tostring(options.text or ""), options.target or parent, options.onClick,
		options.activeColor, options.fullWidth == true, options.locked == true)
	if options.tooltip and button.setTooltip then button:setTooltip(options.tooltip) end
	if options.danger then SiK_UI.applyDangerButton(button) end
	button._sikUiControl = "button"
	return addToParent(parent, button)
end

function Controls.icon(parent, options)
	options = options or {}
	local metrics = Controls.metrics(options.profile)
	local size = optionNumber(options, "size", metrics.buttonHeight)
	local texture = options.texture
	if not texture and options.icon then texture = SiK_UI.getIconTexture(options.icon) end
	local button = SiK_UI.createIconButton(
		optionNumber(options, "x", 0), optionNumber(options, "y", 0), size,
		texture, options.target or parent, options.onClick)
	if button and options.tooltip and button.setTooltip then button:setTooltip(options.tooltip) end
	if button and options.active and button.setActive then button:setActive(true) end
	if button then button._sikUiControl = "icon" end
	return addToParent(parent, button)
end
Controls.iconButton = Controls.icon

function Controls.field(parent, options)
	options = options or {}
	local metrics = Controls.metrics(options.profile)
	local field = ISTextEntryBox:new(
		tostring(options.text or ""),
		optionNumber(options, "x", 0), optionNumber(options, "y", 0),
		optionNumber(options, "w", 160),
		optionNumber(options, "h", metrics.inputHeight))
	field:initialise()
	field.font = options.font or UIFont.Small
	SiK_UI.styleTextEntry(field)
	if field.instantiate then field:instantiate() end
	if options.onTextChange then field.onTextChange = options.onTextChange end
	if options.tooltip and field.setTooltip then field:setTooltip(options.tooltip) end
	if options.numeric and field.setOnlyNumbers then field:setOnlyNumbers(true) end
	field._sikUiControl = "field"
	return addToParent(parent, field)
end

function Controls.combo(parent, options)
	options = options or {}
	local metrics = Controls.metrics(options.profile)
	local combo = ISComboBox:new(
		optionNumber(options, "x", 0), optionNumber(options, "y", 0),
		optionNumber(options, "w", 160),
		optionNumber(options, "h", metrics.inputHeight),
		options.target or parent, options.onChange)
	combo:initialise()
	SiK_UI.styleComboBox(combo)
	local items = options.items or {}
	for i = 1, #items do
		local item = items[i]
		if type(item) == "table" and combo.addOptionWithData then
			combo:addOptionWithData(tostring(item.text or item.label or ""), item.data)
		elseif combo.addOption then
			combo:addOption(tostring(item))
		end
	end
	if options.tooltip and combo.setTooltip then combo:setTooltip(options.tooltip) end
	combo._sikUiControl = "combo"
	return addToParent(parent, combo)
end

function Controls.search(parent, options)
	options = options or {}
	local metrics = Controls.metrics(options.profile)
	local box, entry = SiK_UI.createSearchBox(
		optionNumber(options, "x", 0), optionNumber(options, "y", 0),
		optionNumber(options, "w", 240),
		optionNumber(options, "h", metrics.inputHeight),
		parent, options.onTextChange)
	if options.text and entry.setText then entry:setText(options.text) end
	if options.tooltip and entry.setTooltip then entry:setTooltip(options.tooltip) end
	box._sikUiControl = "search"
	addToParent(parent, box)
	return box, entry
end

function Controls.toggle(parent, options)
	options = options or {}
	local metrics = Controls.metrics(options.profile)
	local size = optionNumber(options, "size", metrics.inputHeight)
	local toggle = SiK_UI.createToggle(
		optionNumber(options, "x", 0), optionNumber(options, "y", 0), size,
		options.checked == true, options.target or parent, options.onToggle)
	if toggle and options.tooltip and toggle.setTooltip then toggle:setTooltip(options.tooltip) end
	if toggle then toggle._sikUiControl = "toggle" end
	return addToParent(parent, toggle)
end

function Controls.status(parent, options)
	options = options or {}
	local metrics = Controls.metrics(options.profile)
	local row = SiK_UI.createStatusIndicatorRow(
		optionNumber(options, "x", 0), optionNumber(options, "y", 0),
		optionNumber(options, "w", 200),
		optionNumber(options, "h", metrics.statusHeight))
	SiK_UI.setStatusIndicatorRow(row, tostring(options.text or ""),
		options.status or "ok", options.maxW)
	row._sikUiControl = "status"
	return addToParent(parent, row)
end

local function feedbackColor(kind)
	local palette = SiK_UI.PALETTE
	if kind == "error" or kind == "danger" then return palette.statusDanger end
	if kind == "warning" or kind == "warn" then return palette.statusWarn end
	if kind == "ok" or kind == "success" then return palette.statusOk end
	return palette.statusInfo
end

function Controls.feedback(parent, options)
	options = options or {}
	local metrics = Controls.metrics(options.profile)
	local panel = ISPanel:new(
		optionNumber(options, "x", 0), optionNumber(options, "y", 0),
		optionNumber(options, "w", 240),
		optionNumber(options, "h", metrics.statusHeight + 8))
	panel:initialise()
	panel.drawBackground = false
	panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	panel._sikUiFeedbackText = tostring(options.text or "")
	panel._sikUiFeedbackKind = options.kind or "info"
	panel.prerender = function(self)
		ISPanel.prerender(self)
		local color = feedbackColor(self._sikUiFeedbackKind)
		local bg = SiK_UI.PALETTE.bgCard
		self:drawRect(0, 0, self.width, self.height, 0.94, bg[1], bg[2], bg[3])
		self:drawRect(0, 0, 3, self.height, 1, color[1], color[2], color[3])
		self:drawRectBorder(0, 0, self.width, self.height, 0.55,
			color[1], color[2], color[3])
		local text = SiK_UI.truncateText(self._sikUiFeedbackText,
			math.max(0, self.width - 20), UIFont.Small)
		local textY = math.floor((self.height - fontHeight(UIFont.Small)) / 2)
		self:drawText(text, 12, textY, SiK_UI.PALETTE.textPrimary[1],
			SiK_UI.PALETTE.textPrimary[2], SiK_UI.PALETTE.textPrimary[3],
			1, UIFont.Small)
	end
	panel.setFeedback = function(self, text, kind)
		self._sikUiFeedbackText = tostring(text or "")
		self._sikUiFeedbackKind = kind or "info"
	end
	panel._sikUiControl = "feedback"
	return addToParent(parent, panel)
end

return Controls

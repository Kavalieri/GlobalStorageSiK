--[[
	GlobalStorageSiK - Lista reutilizable SiK UI
	Estado neutral y pool virtual; no conoce columnas ni reserva scrollbar.
]]

require "GS_SiK_UI_Core"

if not GlobalStorageSiK.SiK_UI.Controls then require "GS_SiK_UI_Controls" end

GlobalStorageSiK.SiK_UI.List = GlobalStorageSiK.SiK_UI.List or {}

local List = GlobalStorageSiK.SiK_UI.List
local SiK_UI = GlobalStorageSiK.SiK_UI

local OPTION_PADDING = 8
local OPTION_GAP = 8

local ListOption = List.ListOption
if not ListOption then
	if ISPanel and ISPanel.derive then
		ListOption = ISPanel:derive("SiK_UI_ListOption")
	else
		-- Author-side geometry harnesses load this module without PZ widgets.
		-- Runtime construction still requires ISPanel and fails explicitly.
		ListOption = {}
		ListOption.__index = ListOption
	end
	List.ListOption = ListOption
end

local function fontHeight(font)
	if getTextManager then
		return getTextManager():getFontHeight(font or (UIFont and UIFont.Small))
	end
	return 12
end

local function optionText(data, formatter, option)
	if formatter then
		return tostring(formatter(data, option) or "")
	end
	if type(data) == "table" then
		return tostring(data.text or data.label or "")
	end
	return tostring(data or "")
end

local function wrapLines(text, width, font)
	width = math.max(1, math.floor(tonumber(width) or 1))
	if SiK_UI.wrapTextLines then
		local lines = SiK_UI.wrapTextLines(text, width, font)
		if type(lines) == "table" and #lines > 0 then return lines end
	end
	return { tostring(text or "") }
end

--- Canonical geometry shared by every selectable list option.
---@param profile string|nil
---@return table
function List.optionMetrics(profile)
	local controls = SiK_UI.Controls.metrics(profile or "standard")
	local lineH = fontHeight(UIFont and UIFont.Small) + 3
	return {
		padding = OPTION_PADDING,
		gap = OPTION_GAP,
		minHeight = controls.buttonHeight,
		lineHeight = lineH,
	}
end

--- Pure measurement used by runtime rows and author harnesses.
---@param text string
---@param width number
---@param options table|nil {profile,font,leadingWidth}
---@return table {height,lines,textX,textWidth,padding,gap,minHeight,lineHeight}
function List.measureOption(text, width, options)
	options = options or {}
	local metrics = List.optionMetrics(options.profile)
	local leadingW = math.max(0, math.floor(tonumber(options.leadingWidth) or 0))
	local leadingGap = leadingW > 0 and metrics.gap or 0
	local textX = metrics.padding + leadingW + leadingGap
	local textW = math.max(1, math.floor(tonumber(width) or 0) - textX - metrics.padding)
	local lines = wrapLines(tostring(text or ""), textW,
		options.font or (UIFont and UIFont.Small))
	local contentH = #lines * metrics.lineHeight
	return {
		height = math.max(metrics.minHeight, contentH + metrics.padding * 2),
		lines = lines,
		textX = textX,
		textWidth = textW,
		padding = metrics.padding,
		gap = metrics.gap,
		minHeight = metrics.minHeight,
		lineHeight = metrics.lineHeight,
	}
end

local function paletteColor(name, fallback)
	local palette = SiK_UI.PALETTE or {}
	return palette[name] or fallback
end

function ListOption:new(x, y, width, options)
	assert(ISPanel and ISPanel.new, "ListOption requires ISPanel")
	options = options or {}
	local initialData = options.data
	if initialData == nil then initialData = options.text or "" end
	local text = optionText(initialData, options.formatter, nil)
	local measured = List.measureOption(text, width, options)
	local option = ISPanel:new(x or 0, y or 0, math.max(0, width or 0), measured.height)
	setmetatable(option, self)
	self.__index = self
	option.drawBackground = false
	option.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	option.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	option._sikUiControl = "listOption"
	option._sikHitboxFull = true
	option.profile = options.profile or "standard"
	option.font = options.font or (UIFont and UIFont.Small)
	option.leadingWidth = math.max(0, math.floor(tonumber(options.leadingWidth) or 0))
	option.renderLeading = options.renderLeading
	option.formatter = options.formatter
	option.callback = options.callback or options.onActivate or options.onClick
	option.callbackTarget = options.target or option
	option.selectOnActivate = options.selectOnActivate ~= false
	option.data = initialData
	option.text = text
	local dataSelected = type(initialData) == "table" and initialData.selected or nil
	local dataEnabled = type(initialData) == "table" and initialData.enabled or nil
	local dataLoading = type(initialData) == "table" and initialData.loading or nil
	option._sikSelected = options.selected == true
		or (options.selected == nil and dataSelected == true)
	option._sikEnabled = options.enabled ~= false
		and (options.enabled ~= nil or dataEnabled ~= false)
	option._sikLoading = options.loading == true
		or (options.loading == nil and dataLoading == true)
	option._sikPressed = false
	option._sikHover = false
	option._sikMeasure = measured
	return option
end

function ListOption:refreshLayout()
	self.text = optionText(self.data, self.formatter, self)
	self._sikMeasure = List.measureOption(self.text, self.width or 0, {
		profile = self.profile,
		font = self.font,
		leadingWidth = self.leadingWidth,
	})
	if self.setHeight then self:setHeight(self._sikMeasure.height)
	else self.height = self._sikMeasure.height end
	return self._sikMeasure.height
end

function ListOption:setOptionWidth(width)
	width = math.max(0, math.floor(tonumber(width) or 0))
	if self.setWidth then self:setWidth(width) else self.width = width end
	return self:refreshLayout()
end

function ListOption:setData(data)
	self.data = data
	if type(data) == "table" then
		if data.selected ~= nil then self:setSelected(data.selected) end
		if data.enabled ~= nil then self:setEnabled(data.enabled) end
		if data.loading ~= nil then self:setLoading(data.loading) end
	end
	self:refreshLayout()
	return self
end

function ListOption:getData()
	return self.data
end

function ListOption:setSelected(selected)
	self._sikSelected = selected == true
	return self
end

function ListOption:isSelected()
	return self._sikSelected == true
end

function ListOption:setEnabled(enabled)
	self._sikEnabled = enabled ~= false
	if not self._sikEnabled then self._sikPressed = false end
	return self
end

function ListOption:isEnabled()
	return self._sikEnabled ~= false and self._sikLoading ~= true
end

function ListOption:setLoading(loading)
	self._sikLoading = loading == true
	if self._sikLoading then self._sikPressed = false end
	return self
end

function ListOption:isLoading()
	return self._sikLoading == true
end

function ListOption:setCallback(callback, target)
	self.callback = callback
	self.callbackTarget = target or self
	return self
end

function ListOption:hitTest(x, y)
	local width = self.width or (self.getWidth and self:getWidth()) or 0
	local height = self.height or (self.getHeight and self:getHeight()) or 0
	return type(x) == "number" and type(y) == "number"
		and x >= 0 and y >= 0 and x < width and y < height
end

function ListOption:activate()
	if not self:isEnabled() then return false end
	if self.selectOnActivate then self:setSelected(true) end
	if self.callback then
		self.callback(self.callbackTarget or self, self, self.data)
	end
	return true
end

function ListOption:onMouseDown(x, y)
	if not self:isEnabled() or not self:hitTest(x, y) then return false end
	self._sikPressed = true
	if self.setCapture then self:setCapture(true) end
	return true
end

function ListOption:onMouseUp(x, y)
	local activate = self._sikPressed and self:hitTest(x, y)
	self._sikPressed = false
	if self.setCapture then self:setCapture(false) end
	if activate then return self:activate() end
	return false
end

function ListOption:onMouseUpOutside()
	self._sikPressed = false
	if self.setCapture then self:setCapture(false) end
	return false
end

function ListOption:onMouseMove()
	self._sikHover = true
	return true
end

function ListOption:onMouseMoveOutside()
	self._sikHover = false
	return false
end

function ListOption:prerender()
	if ISPanel and ISPanel.prerender then ISPanel.prerender(self) end
	local width = self.width or 0
	local height = self.height or 0
	local enabled = self:isEnabled()
	local selected = self:isSelected()
	local fill = paletteColor("btnDefault", { 0.2, 0.2, 0.2 })
	if selected then fill = paletteColor("btnPressed", { 0.1, 0.1, 0.1 })
	elseif enabled and (self._sikPressed or self._sikHover) then
		fill = paletteColor("btnHover", { 0.3, 0.3, 0.3 })
	end
	local alpha = enabled and 0.85 or (self:isLoading() and 0.55 or 0.42)
	self:drawRect(0, 0, width, height, alpha, fill[1], fill[2], fill[3])
	local border = selected and paletteColor("btnActive", { 0.95, 0.5, 0.1 })
		or paletteColor("border", { 0.4, 0.4, 0.4 })
	self:drawRectBorder(0, 0, width, height, enabled and 0.95 or 0.5,
		border[1], border[2], border[3])

	local measure = self._sikMeasure or self:refreshLayout()
	local textColor = enabled and paletteColor("textPrimary", { 0.92, 0.94, 0.96 })
		or paletteColor("textMuted", { 0.58, 0.62, 0.66 })
	local linesHeight = #measure.lines * measure.lineHeight
	local textY = math.max(measure.padding, math.floor((height - linesHeight) / 2))
	if self.renderLeading and self.leadingWidth > 0 then
		self.renderLeading(self, measure.padding, measure.padding,
			self.leadingWidth, height - measure.padding * 2, self.data)
	end
	for i = 1, #measure.lines do
		self:drawText(measure.lines[i], measure.textX,
			textY + (i - 1) * measure.lineHeight,
			textColor[1], textColor[2], textColor[3], enabled and 1 or 0.7,
			self.font)
	end
end

local terminalScroll
local installStateApi

--- Factory for a typed full-hitbox selectable row.
---@param parent ISUIElement|nil
---@param options table {x,y,w,data,text,profile,font,selected,enabled,loading,target,callback,onActivate,onClick,selectOnActivate,leadingWidth,renderLeading}
---@return SiK_UI_ListOption
function List.createOption(parent, options)
	options = options or {}
	local option = ListOption:new(options.x or 0, options.y or 0,
		options.w or options.width or 0, options)
	if option.initialise then option:initialise() end
	if parent and parent.addChild then parent:addChild(option) end
	return option
end

--- Creates a typed scrollable list whose viewport/gutter is owned by Block.
--- Consumers add variable-height ListOption rows through addScrollableOption.
function List.createScrollable(parent, x, y, w, h)
	local list = terminalScroll().createInteractive(parent, x, y, w, h)
	installStateApi(list)
	list._sikUiControl = "scrollableList"
	return list
end

--- Adds one variable-height option to a scrollable list at content coordinates.
function List.addScrollableOption(list, options)
	options = options or {}
	local host = terminalScroll().childHost(list)
	local option = List.createOption(nil, options)
	terminalScroll().addChild(list, option)
	if option.setX then option:setX(options.x or 0) end
	if option.setY then option:setY(options.y or 0) end
	return option, host
end

function List.clearScrollable(list, preserveOffset)
	terminalScroll().clear(list, preserveOffset == true)
end

function List.finishScrollable(list, contentHeight)
	terminalScroll().finish(list, contentHeight)
	return terminalScroll().contentRect(list)
end

local function copyRect(rect)
	return {
		x = tonumber(rect and rect.x) or 0,
		y = tonumber(rect and rect.y) or 0,
		w = math.max(0, tonumber(rect and (rect.w or rect.contentW)) or 0),
		h = math.max(0, tonumber(rect and rect.h) or 0),
		scrollGutter = math.max(0, tonumber(rect and rect.scrollGutter) or 0),
	}
end

--- List consume exactamente el contentRect de Block, tanto corta como larga.
--- rowCount solo afecta overflow/pool; nunca modifica geometria horizontal.
function List.resolveContentRect(contentRect, options)
	local rect = copyRect(contentRect)
	options = options or {}
	rect.rowCount = math.max(0, math.floor(tonumber(options.rowCount) or 0))
	return rect
end

terminalScroll = function()
	if not GlobalStorageSiK.TerminalScroll then
		require "GS_TerminalUI_Scroll"
	end
	return GlobalStorageSiK.TerminalScroll
end

installStateApi = function(list)
	list._sikSelectedKey = list._sikSelectedKey or nil
	list._sikFocusedKey = list._sikFocusedKey or nil
	list._sikEmptyText = list._sikEmptyText or ""

	function list:setSelectedKey(key)
		self._sikSelectedKey = key
	end

	function list:getSelectedKey()
		return self._sikSelectedKey
	end

	function list:setFocusedKey(key)
		self._sikFocusedKey = key
	end

	function list:getFocusedKey()
		return self._sikFocusedKey
	end

	function list:setEmptyText(text)
		self._sikEmptyText = tostring(text or "")
	end

	function list:captureListState()
		return {
			selectedKey = self._sikSelectedKey,
			focusedKey = self._sikFocusedKey,
			scrollY = terminalScroll().getScrollOffset(self),
		}
	end

	function list:restoreListState(state)
		state = type(state) == "table" and state or {}
		self._sikSelectedKey = state.selectedKey
		self._sikFocusedKey = state.focusedKey
		terminalScroll().setScrollOffset(self, tonumber(state.scrollY) or 0)
	end
end

--- Crea un pool virtual sobre el Block exterior. TerminalScroll adapta el
--- gutter de Block una sola vez; List y Table consumen despues contentW.
function List.createVirtual(parent, x, y, w, h, rowHeight, padding, onCreateRow, onUpdateRow)
	local list = terminalScroll().createVirtual(parent, x, y, w, h, rowHeight, padding)
	installStateApi(list)
	if onCreateRow then list:setOnCreateItem(onCreateRow) end
	if onUpdateRow then list:setOnUpdateItem(onUpdateRow) end
	return list
end

return List

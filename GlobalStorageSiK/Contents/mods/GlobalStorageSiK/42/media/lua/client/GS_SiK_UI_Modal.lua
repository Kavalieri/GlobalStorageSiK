--[[
	GlobalStorageSiK - Modal specializations built on SiK UI Window + Block.
	No product decision or text is owned here.
]]

require "GS_SiK_UI_Core"

if not GlobalStorageSiK.SiK_UI.Metrics then require "GS_SiK_UI_Metrics" end
if not GlobalStorageSiK.SiK_UI.Viewport then pcall(require, "GS_SiK_UI_Viewport") end
if not GlobalStorageSiK.SiK_UI.Block then require "GS_SiK_UI_Block" end
if not GlobalStorageSiK.SiK_UI.Controls then pcall(require, "GS_SiK_UI_Controls") end
if not GlobalStorageSiK.SiK_UI.Window then require "GS_SiK_UI_Window" end

local SiK_UI = GlobalStorageSiK.SiK_UI
SiK_UI.Modal = SiK_UI.Modal or {}

local Modal = SiK_UI.Modal
local Window = SiK_UI.Window
local Block = SiK_UI.Block
local Controls = SiK_UI.Controls
local modalStack = {}

local MODAL_PROFILES = {
	compact = { preferredW = 460, minW = 360, maxW = 560,
		widthCap = 0.70, heightCap = 0.70 },
	standard = { preferredW = 460, minW = 360, maxW = 560,
		widthCap = 0.70, heightCap = 0.70 },
	confirm = { preferredW = 460, minW = 360, maxW = 560,
		widthCap = 0.70, heightCap = 0.70 },
	input = { preferredW = 460, minW = 360, maxW = 560,
		widthCap = 0.70, heightCap = 0.70 },
	task = { preferredW = 640, minW = 420, maxW = 760,
		widthCap = 0.80, heightCap = 0.80 },
}

local function clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

local function profileFor(kind)
	return MODAL_PROFILES[kind] or MODAL_PROFILES.compact
end

local function safeViewport(viewport, playerNum)
	if type(viewport) == "table" then return viewport end
	if SiK_UI.Viewport and SiK_UI.Viewport.resolve then
		return SiK_UI.Viewport.resolve(playerNum or 0)
	end
	local width = getCore and getCore():getScreenWidth() or 1280
	local height = getCore and getCore():getScreenHeight() or 720
	return { x = 0, y = 0, w = width, h = height, playerNum = playerNum or 0 }
end

--- Pure modal geometry used by HTML/Lua parity harnesses.
function Modal.resolve(kind, contentSize, viewport, options)
	options = options or {}
	contentSize = contentSize or {}
	viewport = safeViewport(viewport, options.playerNum)
	local spec = profileFor(kind)
	local capW = math.floor(viewport.w * spec.widthCap)
	local capH = math.floor(viewport.h * spec.heightCap)
	local maxW = math.min(spec.maxW, capW, viewport.w)
	local maxH = math.min(tonumber(options.maxHeight) or capH, capH, viewport.h)
	local minW = math.min(tonumber(options.minWidth) or spec.minW, maxW)
	local minH = math.min(tonumber(options.minHeight) or 120, maxH)
	local wantedW = math.max(tonumber(contentSize.w) or 0,
		tonumber(options.width) or spec.preferredW)
	local wantedH = math.max(tonumber(contentSize.h) or 0,
		tonumber(options.height) or minH)
	local width = clamp(math.floor(wantedW), minW, maxW)
	local height = clamp(math.floor(wantedH), minH, maxH)
	local left = math.floor(tonumber(viewport.x) or 0)
	local top = math.floor(tonumber(viewport.y) or 0)
	return {
		x = left + math.floor((viewport.w - width) / 2),
		y = top + math.floor((viewport.h - height) / 2),
		w = width, h = height, kind = kind or "compact",
		playerNum = viewport.playerNum or options.playerNum or 0,
		overflow = wantedH > height,
	}
end

local function removeFromStack(panel)
	for i = #modalStack, 1, -1 do
		if modalStack[i] == panel then
			table.remove(modalStack, i)
			return
		end
	end
end

function Modal.top()
	return modalStack[#modalStack]
end

function Modal.close(panel)
	if not panel then return end
	removeFromStack(panel)
	if panel.destroy then panel:destroy()
	elseif panel.removeFromUIManager then panel:removeFromUIManager()
	elseif panel.setVisible then panel:setVisible(false) end
	local top = Modal.top()
	if top and top.bringToTop then top:bringToTop() end
end

function Modal.show(panel, focusControl)
	if not panel then return panel end
	removeFromStack(panel)
	modalStack[#modalStack + 1] = panel
	if panel.addToUIManager then panel:addToUIManager() end
	SiK_UI.finalizeModalShow(panel)
	local focus = focusControl or panel._sikInitialFocus
	if focus then
		if focus.focus then focus:focus()
		elseif focus.javaObject and focus.javaObject.focus then focus.javaObject:focus() end
	end
	return panel
end

--- Applies modal behavior to an existing panel without adding another dialog.
function Modal.apply(panel, onClose, options)
	if not panel then return panel end
	options = options or {}
	local close = function(target)
		if onClose then onClose(target) else Modal.close(target) end
	end
	options.profile = options.profile or options.kind or "compact"
	if options.resizable == nil then options.resizable = options.kind == "task" end
	local spec = profileFor(options.kind or "compact")
	if options.minWidth == nil then options.minWidth = spec.minW end
	if options.maxWidth == nil then options.maxWidth = spec.maxW end
	if options.minHeight == nil then options.minHeight = 120 end
	Window.apply(panel, close, options.geometryKey, options)
	panel._sikModalKind = options.kind or "compact"
	return panel
end

function Modal.fitContent(panel, contentBottomY, options)
	if not panel then return panel end
	options = options or {}
	local padding = tonumber(options.bottomPadding) or panel.padding or 14
	local viewport = safeViewport(options.viewport, options.playerNum or panel.playerNum)
	local rect = Modal.resolve(options.kind or panel._sikModalKind or "compact", {
		w = panel:getWidth(), h = (tonumber(contentBottomY) or 0) + padding,
	}, viewport, options)
	panel:setWidth(rect.w)
	panel:setHeight(rect.h)
	panel:setX(rect.x)
	panel:setY(rect.y)
	Window.layoutHeader(panel, options)
	return panel
end

local function createBody(panel, rect, contentHeight, scrollable)
	local body = ISPanel:new(rect.x, rect.y, rect.w, rect.h)
	body:initialise()
	body.drawBackground = false
	body.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	panel:addChild(body)
	if body.setScrollChildren then body:setScrollChildren(scrollable == true) end
	if scrollable and body.setScrollHeight then
		body:setScrollHeight(math.max(rect.h, contentHeight or rect.h))
	end
	if scrollable and Block and Block.bindScrollable then
		Block.bindScrollable(body, { contentHeight = contentHeight or rect.h })
	end
	return body
end

--- Generic compact/task modal. buildContent receives the body content rect.
function Modal.create(options)
	options = options or {}
	local kind = options.kind or "compact"
	local viewport = safeViewport(options.viewport, options.playerNum)
	local contentSize = options.contentSize or {
		w = options.contentWidth or 0, h = options.contentHeight or 0,
	}
	local rect = Modal.resolve(kind, contentSize, viewport, options)
	local panel = ISPanel:new(rect.x, rect.y, rect.w, rect.h)
	panel:initialise()
	panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.headerHeight = tonumber(options.headerHeight) or 42
	panel.prerender = function(self)
		ISPanel.prerender(self)
		SiK_UI.drawCardBackground(self, self.headerHeight)
	end
	local close = function(target)
		if options.onClose then options.onClose(target) else Modal.close(target) end
	end
	Modal.apply(panel, close, {
		kind = kind, profile = kind, resizable = options.resizable,
		playerNum = rect.playerNum, minWidth = profileFor(kind).minW,
		maxWidth = profileFor(kind).maxW,
	})
	if options.title and options.title ~= "" then
		local title = SiK_UI.createWindowTitleLabel(14, 10, tostring(options.title))
		panel:addChild(title)
		panel.titleLabel = title
	end
	local padding = 14
	local bodyY = panel.headerHeight + padding
	local bodyH = math.max(0, panel.height - bodyY - padding)
	local bounds = { x = padding, y = bodyY, w = panel.width - padding * 2, h = bodyH }
	local contentRect = bounds
	if Block and Block.resolveContentRect then
		contentRect = Block.resolveContentRect(bounds, {
			scrollable = rect.overflow, contentHeight = contentSize.h,
		})
	end
	if options.buildContent then
		local body = createBody(panel, bounds, contentSize.h, rect.overflow)
		panel.contentBlock = body
		options.buildContent(body, {
			x = contentRect.x - bounds.x, y = contentRect.y - bounds.y,
			w = contentRect.w, h = contentRect.h,
			scrollGutter = contentRect.scrollGutter,
		}, panel)
	end
	return panel, rect
end

local function addMessageLines(parent, text, x, y, width)
	local font = UIFont.Small
	local lineHeight = getTextManager():getFontHeight(font) + 3
	local lines = SiK_UI.wrapTextLines(tostring(text or ""), width, font)
	local palette = SiK_UI.PALETTE.textPrimary
	for i = 1, #lines do
		local label = ISLabel:new(x, y, lineHeight, lines[i], palette[1],
			palette[2], palette[3], 1, font, true)
		label:initialise()
		parent:addChild(label)
		y = y + lineHeight
	end
	return y
end

local function translatedOr(key, fallback)
	if getText then
		local value = getText(key)
		if value and value ~= key then return value end
	end
	return fallback
end

--- Confirmation built from SiK UI primitives; no nested ISModalDialog.
function Modal.confirm(message, onYes, options)
	options = options or {}
	local metrics = Controls.metrics(options.profile)
	local viewport = safeViewport(options.viewport, options.playerNum)
	local preferredW = tonumber(options.width) or 460
	local textWidth = math.max(200, preferredW - 56)
	local lineHeight = getTextManager():getFontHeight(UIFont.Small) + 3
	local lineCount = #SiK_UI.wrapTextLines(tostring(message or ""), textWidth, UIFont.Small)
	local contentHeight = lineCount * lineHeight + metrics.buttonHeight + 34
	local modal
	modal = Modal.create({
		kind = "confirm", title = options.title,
		contentWidth = preferredW - 28, contentHeight = contentHeight + 70,
		viewport = viewport, playerNum = options.playerNum,
		resizable = false,
		onClose = function(target)
			Modal.close(target)
			if options.onNo then options.onNo() end
		end,
		buildContent = function(body, content)
			local y = addMessageLines(body, message, content.x, content.y, content.w)
			y = y + 16
			local gap = metrics.controlGap
			local buttonW = math.floor((content.w - gap) / 2)
			Controls.button(body, { x = content.x, y = y, w = buttonW,
				h = metrics.buttonHeight,
				text = options.noText or translatedOr("UI_No", "No"),
				fullWidth = true, onClick = function()
					Modal.close(modal)
					if options.onNo then options.onNo() end
				end })
			Controls.button(body, { x = content.x + buttonW + gap, y = y,
				w = buttonW, h = metrics.buttonHeight,
				text = options.yesText or translatedOr("UI_Yes", "Yes"),
				fullWidth = true, onClick = function()
					Modal.close(modal)
					if onYes then onYes() end
				end })
		end,
	})
	Modal.show(modal)
	return modal
end

function Modal.input(options)
	options = options or {}
	local field
	local modal
	modal = Modal.create({
		kind = "input", title = options.title,
		contentWidth = options.contentWidth or 432,
		contentHeight = options.contentHeight or 110,
		viewport = options.viewport, playerNum = options.playerNum,
		resizable = false, onClose = options.onClose,
		buildContent = function(body, content)
			local metrics = Controls.metrics(options.profile)
			field = Controls.field(body, { x = content.x, y = content.y,
				w = content.w, text = options.text, onTextChange = options.onTextChange })
			local y = content.y + metrics.inputHeight + metrics.rowGap
			Controls.button(body, { x = content.x, y = y, w = content.w,
				fullWidth = true,
				text = options.acceptText or translatedOr("UI_Ok", "OK"),
				onClick = function()
					local value = field and field:getText() or ""
					if options.onAccept then options.onAccept(value, modal) end
				end })
		end,
	})
	modal._sikInitialFocus = field
	Modal.show(modal, field)
	return modal, field
end

function Modal.compact(options)
	options = options or {}
	options.kind = "compact"
	return Modal.create(options)
end

function Modal.task(options)
	options = options or {}
	options.kind = "task"
	return Modal.create(options)
end

return Modal

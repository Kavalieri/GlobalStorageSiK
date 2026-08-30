--[[
	GlobalStorageSiK - Block SiK UI
	Unico propietario de padding, viewport, clipping y gutter de scrollbar.
]]

if not GlobalStorageSiK or not GlobalStorageSiK.SiK_UI
		or not GlobalStorageSiK.SiK_UI.Metrics then
	require "GS_SiK_UI_Metrics"
end

GlobalStorageSiK.SiK_UI.Block = GlobalStorageSiK.SiK_UI.Block or {}

local Block = GlobalStorageSiK.SiK_UI.Block
local Metrics = GlobalStorageSiK.SiK_UI.Metrics

local function numberOr(value, fallback)
	value = tonumber(value)
	if value and value == value then
		return value
	end
	return fallback
end

local function copyRect(rect)
	return {
		x = numberOr(rect and rect.x, 0),
		y = numberOr(rect and rect.y, 0),
		w = math.max(0, numberOr(rect and rect.w, 0)),
		h = math.max(0, numberOr(rect and rect.h, 0)),
	}
end

function Block.resolveContentRect(bounds, options)
	bounds = copyRect(bounds)
	options = options or {}
	local tokens = Metrics.tokens()
	local padX = math.max(0, numberOr(options.paddingX, tokens.blockPaddingX))
	local padY = math.max(0, numberOr(options.paddingY, tokens.blockPaddingY))
	local scrollable = options.scrollable == true
	local height = math.max(0, bounds.h - padY * 2)
	local contentHeight = math.max(0, numberOr(options.contentHeight, 0))
	local overflow = scrollable and contentHeight > height
	local gutter = overflow and tokens.scrollGutter or 0
	local width = math.max(0, bounds.w - padX * 2 - gutter)
	return {
		x = bounds.x + padX,
		y = bounds.y + padY,
		w = width,
		h = height,
		contentW = width,
		contentH = contentHeight,
		paddingX = padX,
		paddingY = padY,
		scrollable = scrollable,
		scrollGutter = gutter,
		overflow = overflow,
		kind = options.kind or "block",
	}
end

function Block.resolveScrollBarRect(bounds, options)
	bounds = copyRect(bounds)
	options = options or {}
	local tokens = Metrics.tokens()
	local padX = math.max(0, numberOr(options.paddingX, tokens.blockPaddingX))
	local content = Block.resolveContentRect(bounds, options)
	return {
		x = bounds.x + math.max(0, bounds.w - padX - tokens.scrollBarWidth),
		y = bounds.y + math.max(0, numberOr(options.paddingY, tokens.blockPaddingY)),
		w = tokens.scrollBarWidth,
		h = math.max(0, bounds.h - math.max(0, numberOr(options.paddingY,
			tokens.blockPaddingY)) * 2),
		gap = tokens.scrollBarGap,
		visible = content.overflow,
		overflow = content.overflow,
	}
end

function Block.resolveLayout(bounds, options)
	bounds = copyRect(bounds)
	options = options or {}
	local tokens = Metrics.tokens()
	local headerHeight = math.max(0, numberOr(options.headerHeight, 0))
	local footerHeight = math.max(0, numberOr(options.footerHeight, 0))
	local headerGap = headerHeight > 0 and math.max(0,
		numberOr(options.headerGap, tokens.space8)) or 0
	local footerGap = footerHeight > 0 and math.max(0,
		numberOr(options.footerGap, tokens.space8)) or 0
	local availableHeight = math.max(0, bounds.h - headerHeight - headerGap
		- footerHeight - footerGap)
	local regionHeight = availableHeight
	if options.fill ~= true and tonumber(options.contentHeight) then
		local desired = math.max(0, tonumber(options.contentHeight))
			+ tokens.blockPaddingY * 2
		regionHeight = math.min(availableHeight,
			math.max(math.max(0, numberOr(options.minContentHeight, 0)), desired))
	end
	local bodyBounds = {
		x = bounds.x,
		y = bounds.y + headerHeight + headerGap,
		w = bounds.w,
		h = regionHeight,
	}
	local contentRect = Block.resolveContentRect(bodyBounds, options)
	local layout = {
		bounds = bounds,
		headerRect = { x = bounds.x, y = bounds.y, w = bounds.w, h = headerHeight },
		bodyRect = bodyBounds,
		contentRect = contentRect,
		fill = options.fill == true,
		availableHeight = availableHeight,
	}
	local footerY = bounds.y + bounds.h - footerHeight
	layout.footerRect = { x = bounds.x, y = footerY, w = bounds.w, h = footerHeight }
	return layout
end

function Block.bindScrollable(widget, options)
	if not widget then
		return nil
	end
	options = options or {}
	local resolvedOptions = {
		scrollable = true,
		contentHeight = options.contentHeight,
		paddingX = options.paddingX,
		paddingY = options.paddingY,
		kind = options.kind,
	}
	local rect = Block.resolveContentRect({
		x = 0, y = 0, w = widget.width or 0, h = widget.height or 0,
	}, resolvedOptions)
	local previous = widget._sikBlockContentRect
	widget._sikBlockContentRect = rect
	widget._sikBlockScrollable = true
	local changed = not previous or previous.x ~= rect.x or previous.y ~= rect.y
		or previous.w ~= rect.w or previous.h ~= rect.h
		or previous.overflow ~= rect.overflow
	return rect, changed
end

--[[
	GlobalStorageSiK - Metricas canonicas SiK UI
	Tokens y perfiles puros compartidos por HTML, layout y widgets runtime.
]]

require "GS_SiK_UI_Core"

GlobalStorageSiK.SiK_UI.Metrics = GlobalStorageSiK.SiK_UI.Metrics or {}

local Metrics = GlobalStorageSiK.SiK_UI.Metrics

local TOKENS = {
	space4 = 4,
	space6 = 6,
	space8 = 8,
	space12 = 12,
	space16 = 16,
	spacing = { 4, 6, 8, 12, 16 },
	safeMargin = 16,
	windowPadding = 14,
	blockPaddingX = 8,
	blockPaddingY = 8,
	scrollBarWidth = 14,
	scrollBarGap = 10,
	scrollGutter = 24,
	blockBaseReservation = 16,
	blockHorizontalReservation = 40,
	resizeHandle = 14,
	controlVerticalPadding = 10,
	tableHeaderVerticalPadding = 10,
	tableColumnGap = 8,
	tableCellPadding = 6,
}

local PROFILES = {
	compact = {
		name = "compact", minWidth = 0, minHeight = 0,
		window = {
			preferredWidth = 900, preferredHeight = 600,
			minWidth = 720, minHeight = 480,
			maxWidth = 900, maxHeight = 700,
			railWidth = 70, railItemHeight = 50, railPadding = 6, railGap = 4,
			headerHeight = 40, footerHeight = 24,
		},
		controls = { buttonHeight = 30, inputHeight = 30, rowGap = 6, controlGap = 6 },
	},
	standard = {
		name = "standard", minWidth = 900, minHeight = 700,
		window = {
			preferredWidth = 1100, preferredHeight = 700,
			minWidth = 720, minHeight = 480,
			maxWidth = 1200, maxHeight = 800,
			railWidth = 88, railItemHeight = 58, railPadding = 8, railGap = 4,
			headerHeight = 40, footerHeight = 24,
		},
		controls = { buttonHeight = 30, inputHeight = 30, rowGap = 6, controlGap = 6 },
	},
	wide = {
		name = "wide", minWidth = 1400, minHeight = 800,
		window = {
			preferredWidth = 1280, preferredHeight = 800,
			minWidth = 720, minHeight = 480,
			maxWidth = 1320, maxHeight = 840,
			railWidth = 96, railItemHeight = 58, railPadding = 8, railGap = 4,
			headerHeight = 40, footerHeight = 24,
		},
		controls = { buttonHeight = 30, inputHeight = 30, rowGap = 8, controlGap = 6 },
	},
	editor = {
		name = "editor", minWidth = 600, minHeight = 460,
		window = {
			preferredWidth = 860, preferredHeight = 640,
			minWidth = 600, minHeight = 460,
			maxWidth = 1000, maxHeight = 800,
			railWidth = 0, headerHeight = 40, footerHeight = 24,
		},
		controls = { buttonHeight = 30, inputHeight = 30, rowGap = 6, controlGap = 6 },
	},
	staff = {
		name = "staff", minWidth = 720, minHeight = 520,
		window = {
			preferredWidth = 1000, preferredHeight = 720,
			minWidth = 720, minHeight = 520,
			maxWidth = 1200, maxHeight = 860,
			railWidth = 0, headerHeight = 40, footerHeight = 24,
		},
		controls = { buttonHeight = 30, inputHeight = 30, rowGap = 6, controlGap = 6 },
	},
}

local function copyArray(source)
	local result = {}
	for i = 1, #(source or {}) do
		result[i] = source[i]
	end
	return result
end

local function copyMap(source)
	local result = {}
	for key, value in pairs(source or {}) do
		if type(value) == "table" then
			result[key] = copyMap(value)
		else
			result[key] = value
		end
	end
	return result
end

function Metrics.tokens()
	local result = copyMap(TOKENS)
	result.spacing = copyArray(TOKENS.spacing)
	return result
end

function Metrics.profile(name)
	local selected = PROFILES[tostring(name or "standard")] or PROFILES.standard
	return copyMap(selected)
end

function Metrics.profileFor(usableW, usableH)
	usableW = math.max(0, tonumber(usableW) or 0)
	usableH = math.max(0, tonumber(usableH) or 0)
	if usableW >= PROFILES.wide.minWidth and usableH >= PROFILES.wide.minHeight then
		return "wide"
	end
	if usableW < PROFILES.standard.minWidth or usableH < PROFILES.standard.minHeight then
		return "compact"
	end
	return "standard"
end

function Metrics.spacing(index)
	local value = tonumber(index)
	if value == 4 or value == 6 or value == 8 or value == 12 or value == 16 then
		return value
	end
	return TOKENS.space8
end

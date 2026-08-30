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
	resizeHandle = 24,
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
			railWidth = 76, railItemHeight = 60, railIconSize = 44,
			railPadding = 6, railGap = 4,
			headerHeight = 48, footerHeight = 48,
			headerCloseSize = 28, headerGap = 12,
		},
		controls = { buttonHeight = 30, inputHeight = 30, rowGap = 6, controlGap = 6 },
	},
	standard = {
		name = "standard", minWidth = 900, minHeight = 700,
		window = {
			preferredWidth = 1100, preferredHeight = 700,
			minWidth = 720, minHeight = 480,
			maxWidth = 1200, maxHeight = 800,
			railWidth = 96, railItemHeight = 68, railIconSize = 52,
			railPadding = 8, railGap = 4,
			headerHeight = 48, footerHeight = 48,
			headerCloseSize = 28, headerGap = 12,
		},
		controls = { buttonHeight = 30, inputHeight = 30, rowGap = 6, controlGap = 6 },
	},
	wide = {
		name = "wide", minWidth = 1400, minHeight = 800,
		window = {
			preferredWidth = 1280, preferredHeight = 800,
			minWidth = 720, minHeight = 480,
			maxWidth = 1320, maxHeight = 840,
			railWidth = 104, railItemHeight = 68, railIconSize = 52,
			railPadding = 8, railGap = 4,
			headerHeight = 48, footerHeight = 48,
			headerCloseSize = 28, headerGap = 12,
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

--- Fuente unica de rectangulos del shell. Los consumidores reciben estas
--- cajas resueltas y no vuelven a restar cabecera, rail ni pie localmente.
function Metrics.shellRects(profileName, width, height, blocked)
	local profile = Metrics.profile(profileName)
	local window = profile.window
	local w = math.max(0, math.floor(tonumber(width) or 0))
	local h = math.max(0, math.floor(tonumber(height) or 0))
	local headerH = math.min(h, window.headerHeight or 0)
	local footerH = math.min(math.max(0, h - headerH), window.footerHeight or 0)
	local railW = blocked and 0 or math.min(w, window.railWidth or 0)
	local bodyH = math.max(0, h - headerH - footerH)
	return {
		shell = { x = 0, y = 0, w = w, h = h },
		header = { x = 0, y = 0, w = w, h = headerH },
		rail = { x = 0, y = headerH, w = railW, h = math.max(0, h - headerH) },
		content = { x = railW, y = headerH, w = math.max(0, w - railW), h = bodyH },
		footer = { x = railW, y = math.max(headerH, h - footerH),
			w = math.max(0, w - railW), h = footerH },
	}
end

--- Dos areas independientes de cabecera: titulo y cierre. La X conserva
--- tamano y margenes; el titulo nunca consume su separacion izquierda.
function Metrics.headerRects(profileName, width, padding)
	local profile = Metrics.profile(profileName)
	local window = profile.window
	local w = math.max(0, math.floor(tonumber(width) or 0))
	local pad = math.max(0, math.floor(tonumber(padding) or TOKENS.windowPadding))
	local gap = math.max(0, math.floor(window.headerGap or TOKENS.space12))
	local closeW = math.min(window.headerCloseSize or 28, math.max(0, w - pad * 2))
	local closeX = math.max(pad, w - pad - closeW)
	return {
		title = { x = pad, y = 0, w = math.max(0, closeX - gap - pad),
			h = window.headerHeight },
		close = { x = closeX, y = math.floor((window.headerHeight - closeW) / 2),
			w = closeW, h = closeW },
		gap = gap,
	}
end

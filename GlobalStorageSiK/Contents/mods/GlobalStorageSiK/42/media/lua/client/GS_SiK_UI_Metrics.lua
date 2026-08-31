--[[
	GlobalStorageSiK - Metricas canonicas SiK UI
	Tokens y perfiles puros compartidos por HTML, layout y widgets runtime.
]]

require "GS_SiK_UI_Core"

GlobalStorageSiK.SiK_UI.Metrics = GlobalStorageSiK.SiK_UI.Metrics or {}

local Metrics = GlobalStorageSiK.SiK_UI.Metrics
local CHROME = GlobalStorageSiK.SiK_UI.windowChrome()

local TOKENS = {
	space4 = 4,
	space6 = 6,
	space8 = 8,
	space12 = 12,
	space16 = 16,
	spacing = { 4, 6, 8, 12, 16 },
	safeMargin = 16,
	windowPadding = CHROME.horizontalPadding,
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
	-- El terminal tiene una sola geometria. El viewport solo lo centra y limita;
	-- no elige una segunda interfaz ni cambia rail, iconos, margenes o controles.
	terminal = {
		name = "terminal",
		window = {
			preferredWidth = 1600, preferredHeight = 900,
			minWidth = 720, minHeight = 480,
			railWidth = 104, railItemHeight = 76, railIconSize = 68,
			railPadding = 0, railGap = 0, railSlotInset = 0,
			headerHeight = CHROME.headerHeight,
			-- El pie del terminal solo muestra la línea de versiones. Su altura se
			-- calcula desde la fuente y el padding del perfil; no hay reserva fija.
			footerMinimumHeight = 0, footerLines = 1, footerPaddingY = 12, footerLineGap = 0,
		},
		controls = { buttonHeight = 30, inputHeight = 30, rowGap = 8, controlGap = 6 },
	},
	editor = {
		name = "editor", minWidth = 600, minHeight = 460,
		window = {
			preferredWidth = 860, preferredHeight = 640,
			minWidth = 600, minHeight = 460,
			maxWidth = 1000, maxHeight = 800,
			railWidth = 0, headerHeight = CHROME.headerHeight, footerHeight = 24,
		},
		controls = { buttonHeight = 30, inputHeight = 30, rowGap = 6, controlGap = 6 },
	},
	staff = {
		name = "staff", minWidth = 720, minHeight = 520,
		window = {
			preferredWidth = 1000, preferredHeight = 720,
			minWidth = 720, minHeight = 520,
			maxWidth = 1200, maxHeight = 860,
			railWidth = 0, headerHeight = CHROME.headerHeight, footerHeight = 24,
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
	local requested = tostring(name or "terminal")
	if requested == "compact" or requested == "standard" or requested == "wide" then
		requested = "terminal"
	end
	local selected = PROFILES[requested] or PROFILES.terminal
	return copyMap(selected)
end

function Metrics.profileFor(_usableW, _usableH)
	return "terminal"
end

function Metrics.spacing(index)
	local value = tonumber(index)
	if value == 4 or value == 6 or value == 8 or value == 12 or value == 16 then
		return value
	end
	return TOKENS.space8
end

-- El pie del terminal contiene una única línea de versiones. Su reserva nace
-- de la métrica de fuente disponible y del padding del perfil, sin un alto
-- visual fijo que deje espacio vacío al cambiar escala UI.
function Metrics.footerLayout(profileName, reservedHeight)
	local window = Metrics.profile(profileName).window or {}
	local lines = math.max(1, math.floor(tonumber(window.footerLines) or 1))
	local fontH = 14
	if getTextManager then
		local manager = getTextManager()
		if manager and manager.getFontHeight then
			fontH = math.max(fontH, tonumber(manager:getFontHeight(UIFont.Small)) or fontH)
		end
	end
	local paddingY = math.max(0, tonumber(window.footerPaddingY) or 0)
	local lineGap = math.max(0, tonumber(window.footerLineGap) or 0)
	local measured = lines * fontH + math.max(0, lines - 1) * lineGap + paddingY * 2
	local height = math.max(tonumber(window.footerMinimumHeight) or 0, math.ceil(measured))
	if reservedHeight then height = math.max(height, tonumber(reservedHeight) or 0) end
	return { height = height, lineHeight = fontH, lineGap = lineGap, paddingY = paddingY }
end

function Metrics.footerHeight(profileName)
	return Metrics.footerLayout(profileName).height
end

--- Fuente unica de rectangulos del shell. Los consumidores reciben estas
--- cajas resueltas y no vuelven a restar cabecera, rail ni pie localmente.
function Metrics.shellRects(profileName, width, height, blocked)
	local profile = Metrics.profile(profileName)
	local window = profile.window
	local w = math.max(0, math.floor(tonumber(width) or 0))
	local h = math.max(0, math.floor(tonumber(height) or 0))
	local headerH = math.min(h, window.headerHeight or 0)
	local footerH = math.min(math.max(0, h - headerH), Metrics.footerHeight(profileName))
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
	local chrome = GlobalStorageSiK.SiK_UI.windowChrome()
	local gap = math.max(0, math.floor(chrome.titleCloseGap or TOKENS.space12))
	local closeW = math.min(chrome.closeButtonSize, math.max(0, w - pad * 2))
	local closeX = math.max(pad, w - pad - closeW)
	return {
		title = { x = pad, y = 0, w = math.max(0, closeX - gap - pad),
			h = window.headerHeight },
		close = { x = closeX, y = math.floor((window.headerHeight - closeW) / 2),
			w = closeW, h = closeW },
		gap = gap,
	}
end

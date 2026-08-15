--[[
	GlobalStorageSiK - Cabecera y chrome del terminal (NeatUI)
	Autor: SiK
	Fecha: 2025-06-24
]]

require "GS_I18n"

require "ISUI/ISButton"
require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_Libs"
require "GS_UIDebug"
require "GS_CraftUtils"

GlobalStorageSiK.TerminalChrome = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

--- Paleta alineada con Neat Crafting / Neat Building (NI_SquareButton).
GlobalStorageSiK.TerminalChrome.PALETTE = {
	bgHeader = { 0.06, 0.06, 0.06 },
	bgBody = { 0.12, 0.12, 0.12 },
	bgCard = { 0.10, 0.10, 0.10, 0.85 },
	btnDefault = { 0.2, 0.2, 0.2 },
	btnHover = { 0.3, 0.3, 0.3 },
	btnPressed = { 0.1, 0.1, 0.1 },
	btnActive = { 0.95, 0.5, 0.1 },
	border = { 0.4, 0.4, 0.4 },
	textPrimary = { 0.92, 0.94, 0.96 },
	textSecondary = { 0.75, 0.78, 0.82 },
	textMuted = { 0.58, 0.62, 0.66 },
	accentLine = { 0.28, 0.28, 0.28 },
	tableStripeA = { 0.10, 0.10, 0.10, 0.50 },
	tableStripeB = { 0.08, 0.08, 0.08, 0.30 },
	tableHover = { 0.15, 0.15, 0.15, 0.40 },
	tableSelected = { 0.22, 0.32, 0.45, 0.35 },
	zoneHeader = { 0.14, 0.16, 0.20, 0.80 },
	zoneHeaderHover = { 0.22, 0.28, 0.35, 0.45 },
	statusOk     = { 0.4,  0.85, 0.45 },
	statusWarn   = { 0.9,  0.75, 0.35 },
	statusDanger = { 0.95, 0.38, 0.35 },
	dangerBorder = { 0.55, 0.28, 0.28 },
	dangerBg     = { 0.18, 0.08, 0.08 },
	dangerHover  = { 0.28, 0.12, 0.12 },
	-- Aliases usados en Network y Permissions
	accent    = { 0.95, 0.5,  0.1  },
	cardBg    = { 0.06, 0.06, 0.08 },
	divider   = { 0.18, 0.18, 0.22 },
}

---@param text string
---@param maxWidth number
---@param font UIFont|nil
---@return string
function GlobalStorageSiK.TerminalChrome.truncateText(text, maxWidth, font)
	return GlobalStorageSiK.Libs.truncateText(text, maxWidth, font, "..")
end

--- Nine-patch de botón NeatUI (esquinas fijas, sin estirar como píldora).
---@return userdata|nil
function GlobalStorageSiK.TerminalChrome.getButtonNinePatch()
	if GlobalStorageSiK.TerminalChrome._btnPatch ~= nil then
		local cached = GlobalStorageSiK.TerminalChrome._btnPatch
		return cached ~= false and cached or nil
	end
	local patch = nil
	if NinePatchTexture and NinePatchTexture.getSharedTexture then
		local ok, loaded = pcall(function()
			return NinePatchTexture.getSharedTexture("media/ui/NeatUI/Button/Background.png")
		end)
		if ok and loaded then
			patch = loaded
		end
	end
	GlobalStorageSiK.TerminalChrome._btnPatch = patch or false
	return patch
end

--- Ancho de barra vertical NeatUI (misma fórmula que NC_Config / NIScrollBar).
---@return number
function GlobalStorageSiK.TerminalChrome.scrollBarWidth()
	return math.floor(FONT_HGT_SMALL * 0.6)
end

--- Ancho recomendado para botón NeatUI según texto (sin estirar a todo el panel).
---@param title string
---@param font UIFont|nil
---@param padH number|nil
---@param minW number|nil
---@param maxW number|nil
---@return number
function GlobalStorageSiK.TerminalChrome.measureNeatButtonWidth(title, font, padH, minW, maxW)
	font = font or UIFont.Small
	padH = padH or 20
	minW = minW or 52
	maxW = maxW or 280
	local tw = getTextManager():MeasureStringX(font, title or "")
	return math.min(maxW, math.max(minW, tw + padH))
end

--- Ancho real del botón según etiqueta (el parámetro w actúa como tope máximo).
---@param title string
---@param w number|nil
---@param font UIFont|nil
---@param padH number|nil
---@param minW number|nil
---@return number width, number maxW
function GlobalStorageSiK.TerminalChrome.resolveNeatButtonWidth(title, w, font, padH, minW)
	font = font or UIFont.Small
	padH = padH or 20
	minW = minW or 52
	local maxW = (w and w > 0) and w or 360
	return GlobalStorageSiK.TerminalChrome.measureNeatButtonWidth(title, font, padH, minW, maxW), maxW
end

--- Ajusta ancho del botón al texto actual (sin estirar la textura).
---@param btn ISButton|nil
function GlobalStorageSiK.TerminalChrome.fitNeatButtonToLabel(btn)
	if not btn then
		return
	end
	local label = btn._gsNeatLabel or btn.title or ""
	local font = btn.font or UIFont.Small
	local nw = GlobalStorageSiK.TerminalChrome.measureNeatButtonWidth(
		label, font, btn._gsNeatPadH or 20, btn._gsNeatMinW or 52, btn._gsNeatMaxW or 360
	)
	if nw ~= btn.width then
		btn:setWidth(nw)
	end
end

--- Dibuja superficie de botón estilo NeatUI (3-patch horizontal; sin estirar textura).
---@param panel ISUIElement
---@param w number
---@param h number
---@param tex table|nil
---@param opts table|nil pressed, hover, active
---@param ox number|nil
---@param oy number|nil
function GlobalStorageSiK.TerminalChrome.drawButtonSurface(panel, w, h, tex, opts, ox, oy)
	opts = opts or {}
	ox = ox or 0
	oy = oy or 0
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	local r, g, b = pal.btnDefault[1], pal.btnDefault[2], pal.btnDefault[3]
	if opts.active then
		local ac = pal.btnActive
		if opts.pressed then
			r, g, b = ac[1] * 0.8, ac[2] * 0.8, ac[3] * 0.8
		elseif opts.hover then
			r, g, b = math.min(ac[1] * 1.2, 1), math.min(ac[2] * 1.2, 1), math.min(ac[3] * 1.2, 1)
		else
			r, g, b = ac[1], ac[2], ac[3]
		end
	elseif opts.pressed then
		r, g, b = pal.btnPressed[1], pal.btnPressed[2], pal.btnPressed[3]
	elseif opts.hover then
		r, g, b = pal.btnHover[1], pal.btnHover[2], pal.btnHover[3]
	end
	local tp = GlobalStorageSiK.TerminalChrome.getNeatThreePatch()
	local inputTex = GlobalStorageSiK.TerminalChrome.getNeatInputTextures()
	if tp and inputTex.left and inputTex.middle and inputTex.right then
		tp.drawHorizontal(panel, ox, oy, w, h, inputTex.left, inputTex.middle, inputTex.right, 1, r, g, b)
		return
	end
	panel:drawRect(ox, oy, w, h, 0.94, r * 0.22, g * 0.22, b * 0.22)
	local br = pal.border
	panel:drawRectBorder(ox, oy, w, h, 0.9, br[1], br[2], br[3])
end

--- Fondo de fila de tabla (rayas + hover).
---@param panel ISPanel
---@param rowIndex number|nil
---@param hovered boolean|nil
---@param selected boolean|nil
function GlobalStorageSiK.TerminalChrome.drawTableRowBackground(panel, rowIndex, hovered, selected)
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	local stripe = pal.tableStripeA
	if rowIndex and rowIndex % 2 == 1 then
		stripe = pal.tableStripeB
	end
	panel:drawRect(0, 0, panel.width, panel.height, stripe[4], stripe[1], stripe[2], stripe[3])
	if selected then
		local s = pal.tableSelected
		panel:drawRect(0, 0, panel.width, panel.height, s[4], s[1], s[2], s[3])
	end
	if hovered then
		local hov = pal.tableHover
		panel:drawRect(0, 0, panel.width, panel.height, hov[4], hov[1], hov[2], hov[3])
	end
end

--- Separador inferior de cabecera de tabla.
---@param panel ISPanel
function GlobalStorageSiK.TerminalChrome.drawTableHeaderLine(panel)
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	panel:drawRect(0, panel.height - 1, panel.width, 1, 0.65, pal.accentLine[1], pal.accentLine[2], pal.accentLine[3])
end

--- Cabecera de zona colapsable (bloque contenedores).
---@param panel ISPanel
---@param hovered boolean|nil
function GlobalStorageSiK.TerminalChrome.drawZoneHeaderBackground(panel, hovered)
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	local z = hovered and pal.zoneHeaderHover or pal.zoneHeader
	panel:drawRect(0, 0, panel.width, panel.height, z[4], z[1], z[2], z[3])
end

--- Crea etiqueta de sección con estilo Neat.
---@param x number
---@param y number
---@param text string
---@return ISLabel
function GlobalStorageSiK.TerminalChrome.createSectionLabel(x, y, text)
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	local lbl = ISLabel:new(x, y, FONT_HGT_SMALL, text, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small, true)
	lbl:initialise()
	return lbl
end

--- Crea etiqueta de hint secundario.
---@param x number
---@param y number
---@param text string
---@param lineH number|nil
---@return ISLabel
function GlobalStorageSiK.TerminalChrome.createHintLabel(x, y, text, lineH)
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	local h = lineH or FONT_HGT_SMALL
	local lbl = ISLabel:new(x, y, h, text, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small, true)
	lbl:initialise()
	return lbl
end

--- Texturas de botón NeatUI.
---@return table
function GlobalStorageSiK.TerminalChrome.neatButtonTextures()
	return {
		bg = getTexture("media/ui/NeatUI/Button/Background.png"),
		border = getTexture("media/ui/NeatUI/Button/Boarder.png"),
	}
end

--- ThreePatch de NeatUI_Framework (campos, barras).
---@return table|nil
function GlobalStorageSiK.TerminalChrome.getNeatThreePatch()
	local tool = GlobalStorageSiK.Libs.getNeatTool()
	if tool and tool.ThreePatch then
		return tool.ThreePatch
	end
	return nil
end

--- Texturas 3-patch para campos de texto/combo (Button_FULL, estilo NC_SearchBox).
---@return table
function GlobalStorageSiK.TerminalChrome.getNeatInputTextures()
	if GlobalStorageSiK.TerminalChrome._inputTex then
		return GlobalStorageSiK.TerminalChrome._inputTex
	end
	GlobalStorageSiK.TerminalChrome._inputTex = {
		left = getTexture("media/ui/NeatUI/Button/Button_FULL_L.png"),
		middle = getTexture("media/ui/NeatUI/Button/Button_FULL_M.png"),
		right = getTexture("media/ui/NeatUI/Button/Button_FULL_R.png"),
	}
	return GlobalStorageSiK.TerminalChrome._inputTex
end

--- Resuelve textura 3-patch con rutas de fallback (NeatUI → Neat_Crafting).
---@param basePaths string[]
---@param kind string "Background"|"Progress"
---@return table|nil
function GlobalStorageSiK.TerminalChrome._loadThreePatchSet(basePaths, kind)
	kind = kind or "Background"
	local function firstTex(suffix)
		for i = 1, #basePaths do
			local tex = getTexture(basePaths[i] .. kind .. suffix)
			if tex then
				return tex
			end
		end
		return nil
	end
	local left = firstTex("_L.png")
	local middle = firstTex("_M.png")
	local right = firstTex("_R.png")
	if left and middle and right then
		return { left = left, middle = middle, right = right }
	end
	return nil
end

--- Texturas de barra de progreso (Neat_Crafting / NeatUI).
---@return table
function GlobalStorageSiK.TerminalChrome.getNeatProgressTextures()
	if GlobalStorageSiK.TerminalChrome._progressTex then
		return GlobalStorageSiK.TerminalChrome._progressTex
	end
	local bases = {
		"media/ui/NeatUI/Progress/",
		"media/ui/Neat_Crafting/Progress/",
	}
	GlobalStorageSiK.TerminalChrome._progressTex = {
		bg = GlobalStorageSiK.TerminalChrome._loadThreePatchSet(bases, "Background"),
		fill = GlobalStorageSiK.TerminalChrome._loadThreePatchSet(bases, "Progress"),
	}
	return GlobalStorageSiK.TerminalChrome._progressTex
end

--- Color de barra según porcentaje (patrón NR_DrawBar).
---@param pct number 0.0–1.0
---@return number r, number g, number b
function GlobalStorageSiK.TerminalChrome.getBarColor(pct)
	if pct > 0.5 then
		return 0.2, 0.8, 0.3
	elseif pct > 0.25 then
		return 0.9, 0.5, 0.1
	end
	return 0.85, 0.2, 0.2
end

--- Dibuja barra de progreso NeatUI con stencil (patrón NC_CraftActionPanel / NR_DrawBar).
---@param panel ISPanel
---@param x number
---@param y number
---@param w number
---@param h number
---@param pct number 0.0–1.0
---@param fr number|nil
---@param fg number|nil
---@param fb number|nil
---@param label string|nil
function GlobalStorageSiK.TerminalChrome.drawProgressBar(panel, x, y, w, h, pct, fr, fg, fb, label)
	if not panel then
		return
	end
	pct = math.max(0, math.min(1, tonumber(pct) or 0))
	local tp = GlobalStorageSiK.TerminalChrome.getNeatThreePatch()
	local tex = GlobalStorageSiK.TerminalChrome.getNeatProgressTextures()
	if tp and tex.bg then
		tp.drawHorizontal(panel, x, y, w, h, tex.bg.left, tex.bg.middle, tex.bg.right, 0.8, 0.4, 0.4, 0.4)
		local fillW = math.floor(w * pct)
		if fillW > 0 and tex.fill then
			if not fr then
				fr, fg, fb = GlobalStorageSiK.TerminalChrome.getBarColor(pct)
			end
			panel:setStencilRect(x, y, fillW, h)
			tp.drawHorizontal(panel, x, y, w, h, tex.fill.left, tex.fill.middle, tex.fill.right, 1.0, fr, fg, fb)
			panel:clearStencilRect()
		end
	elseif tp then
		tp.drawHorizontal(panel, x, y, w, h,
			GlobalStorageSiK.TerminalChrome.getNeatInputTextures().left,
			GlobalStorageSiK.TerminalChrome.getNeatInputTextures().middle,
			GlobalStorageSiK.TerminalChrome.getNeatInputTextures().right,
			0.8, 0.15, 0.15, 0.15)
		if pct > 0 then
			if not fr then
				fr, fg, fb = GlobalStorageSiK.TerminalChrome.getBarColor(pct)
			end
			panel:drawRect(x, y, math.floor(w * pct), h, 1, fr, fg, fb)
		end
	else
		panel:drawRect(x, y, w, h, 1, 0.1, 0.12, 0.16)
		if pct > 0 then
			if not fr then
				fr, fg, fb = GlobalStorageSiK.TerminalChrome.getBarColor(pct)
			end
			panel:drawRect(x, y, math.floor(w * pct), h, 1, fr, fg, fb)
		end
		panel:drawRectBorder(x, y, w, h, 0.85, 0.3, 0.4, 0.5)
	end
	if label and label ~= "" then
		local ty = y + math.floor((h - FONT_HGT_SMALL) / 2)
		panel:drawTextCentre(label, x + math.floor(w / 2), ty, 1, 1, 1, 1, UIFont.Small)
	end
end

--- Separador horizontal 1px (patrón NR_DrawUtils).
---@param panel ISPanel
---@param y number
---@param pad number|nil
function GlobalStorageSiK.TerminalChrome.drawSeparator(panel, y, pad)
	if not panel then
		return
	end
	pad = pad or (panel.padding or 8)
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE.accentLine
	panel:drawRect(pad, y, panel.width - pad * 2, 1, 0.65, pal[1], pal[2], pal[3])
end

--- Etiqueta derecha + valor izquierdo en la misma línea (patrón NR_DrawUtils).
---@param panel ISPanel
---@param label string
---@param value string
---@param xPivot number
---@param valX number
---@param y number
---@param la number|nil
---@param vr number|nil
---@param vg number|nil
---@param vb number|nil
function GlobalStorageSiK.TerminalChrome.drawLabelValue(panel, label, value, xPivot, valX, y, la, vr, vg, vb)
	panel:drawTextRight(label, xPivot, y, 1, 1, 1, la or 0.7, UIFont.Small)
	panel:drawText(value, valX, y, vr or 1, vg or 1, vb or 1, 1, UIFont.Small)
end

--- Aplica fondo 3-patch a un campo editable (ISTextEntryBox / ISComboBox).
---@param field ISUIElement
---@param padAdjust number|nil
local function applyNeatInputChrome(field, padAdjust)
	if not field or field._gsNeatInputStyled then
		return
	end
	field._gsNeatInputStyled = true
	if field.addOption or field.Type == "ISComboBox" then
		-- Para combos: fondo sólido en estado cerrado + dropdown completamente opaco
		field.backgroundColor = { r = 0.08, g = 0.09, b = 0.12, a = 0.96 }
		field.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 1 }
		field.tableColor = { r = 0.07, g = 0.08, b = 0.11, a = 1.0 }
		if field.setTableColor then
			field:setTableColor(0.07, 0.08, 0.11, 1.0)
		end
	else
		field.backgroundColor = { r = 0.1, g = 0.1, b = 0.1, a = 0 }
		field.borderColor = { r = 0.28, g = 0.28, b = 0.28, a = 0 }
	end
	local tex = GlobalStorageSiK.TerminalChrome.getNeatInputTextures()
	local pad = padAdjust or 0
	local origPrerender = field.prerender
	field.prerender = function(self)
		if origPrerender then
			origPrerender(self)
		end
		local tp = GlobalStorageSiK.TerminalChrome.getNeatThreePatch()
		if tp and tex.left and tex.middle and tex.right then
			tp.drawHorizontal(self, -pad, 0, self.width + pad * 2, self.height,
				tex.left, tex.middle, tex.right, 1, 0.4, 0.4, 0.4)
		else
			self:drawRect(0, 0, self.width, self.height, 0.95, 0.1, 0.1, 0.1)
			self:drawRectBorder(0, 0, self.width, self.height, 0.85, 0.28, 0.28, 0.28)
		end
	end
end

--- Caché de nine-patch NeatUI (Framework + fallback Neat Crafting).
---@return table
function GlobalStorageSiK.TerminalChrome.getNeatPanelPatches()
	if GlobalStorageSiK.TerminalChrome._neatPatches then
		return GlobalStorageSiK.TerminalChrome._neatPatches
	end
	local function loadPatch(path)
		if not NinePatchTexture or not NinePatchTexture.getSharedTexture then
			return nil
		end
		local ok, patch = pcall(function()
			return NinePatchTexture.getSharedTexture(path)
		end)
		if ok and patch then
			return patch
		end
		return nil
	end
	local function firstOf(paths)
		for i = 1, #paths do
			local patch = loadPatch(paths[i])
			if patch then
				return patch
			end
		end
		return nil
	end
	GlobalStorageSiK.TerminalChrome._neatPatches = {
		mainBody = firstOf({
			"media/ui/NeatUI/DefaultPanel/MainPanelBG_FlatTop.png",
			"media/ui/Neat_Crafting/Panel/MainPanelBG_FlatTop.png",
		}),
		mainTitle = firstOf({
			"media/ui/NeatUI/DefaultPanel/MainTitle_BG.png",
		}),
		content = firstOf({
			"media/ui/NeatUI/DefaultPanel/ContentPanel_BG.png",
			"media/ui/Neat_Crafting/Panel/ContentPanel_BG.png",
		}),
		innerTitle = firstOf({
			"media/ui/NeatUI/DefaultPanel/InnerTitle_BG.png",
			"media/ui/Neat_Crafting/Panel/InnerTitle_BG.png",
		}),
	}
	return GlobalStorageSiK.TerminalChrome._neatPatches
end

--- Dibuja nine-patch en coordenadas absolutas de pantalla.
---@param panel ISPanel
---@param patch userdata|nil
---@param relX number
---@param relY number
---@param w number
---@param h number
---@param r number|nil
---@param g number|nil
---@param b number|nil
---@param a number|nil
---@return boolean
function GlobalStorageSiK.TerminalChrome.renderNinePatch(panel, patch, relX, relY, w, h, r, g, b, a)
	if not patch or not panel or not panel.getAbsoluteX then
		return false
	end
	patch:render(
		panel:getAbsoluteX() + relX,
		panel:getAbsoluteY() + relY,
		w,
		h,
		r or 0.15,
		g or 0.15,
		b or 0.15,
		a or 1
	)
	return true
end

--- Fondo de tarjeta (recetas, bloques) estilo Neat Crafting / Project Cook.
---@param panel ISPanel
---@param titleHeight number|nil
function GlobalStorageSiK.TerminalChrome.drawCardBackground(panel, titleHeight)
	titleHeight = titleHeight or 0
	local patches = GlobalStorageSiK.TerminalChrome.getNeatPanelPatches()
	local bodyH = math.max(0, panel.height - titleHeight)
	if patches.content and GlobalStorageSiK.TerminalChrome.renderNinePatch(panel, patches.content, 0, titleHeight, panel.width, bodyH, 0.1, 0.1, 0.1, 0.94) then
		-- ok
	elseif titleHeight > 0 then
		panel:drawRect(0, titleHeight, panel.width, bodyH, 0.94, 0.09, 0.09, 0.09)
	else
		panel:drawRect(0, 0, panel.width, panel.height, 0.94, 0.09, 0.09, 0.09)
	end
	if titleHeight > 0 then
		if not GlobalStorageSiK.TerminalChrome.renderNinePatch(panel, patches.innerTitle, 0, 0, panel.width, titleHeight, 0.12, 0.12, 0.12, 0.96) then
			panel:drawRect(0, 0, panel.width, titleHeight, 0.96, 0.12, 0.12, 0.12)
		end
	end
	local br = GlobalStorageSiK.TerminalChrome.PALETTE.border
	panel:drawRectBorder(0, 0, panel.width, panel.height, 0.35, br[1] * 0.45, br[2] * 0.45, br[3] * 0.45)
end

--- Estilo Neat para ISTextEntryBox (3-patch Button_FULL, patrón NC_SearchBox).
---@param entry ISTextEntryBox
---@param padAdjust number|nil
function GlobalStorageSiK.TerminalChrome.styleTextEntry(entry, padAdjust)
	if not entry then
		return
	end
	applyNeatInputChrome(entry, padAdjust)
end

--- Estilo Neat para ISComboBox (mismo 3-patch que campos de texto).
---@param combo ISComboBox
---@param padAdjust number|nil
function GlobalStorageSiK.TerminalChrome.styleComboBox(combo, padAdjust)
	if not combo then
		return
	end
	applyNeatInputChrome(combo, padAdjust)
end

--- Crea botón de pestaña con subrayado activo (estilo Neat Crafting).
---@param x number
---@param y number
---@param w number
---@param h number
---@param title string
---@param terminal GS_TerminalUI
---@param tabKey string
---@return ISButton
function GlobalStorageSiK.TerminalChrome.createTabButton(x, y, w, h, title, terminal, tabKey)
	local btn = ISButton:new(x, y, w, h, title, terminal, function()
		terminal:activateTab(tabKey)
	end)
	btn:initialise()
	btn.tabKey = tabKey
	btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.drawBackground = false
	local tex = GlobalStorageSiK.TerminalChrome.neatButtonTextures()
	btn.prerender = function(self)
		local sel = terminal.activeTabKey == self.tabKey
		GlobalStorageSiK.TerminalChrome.drawButtonSurface(self, self.width, self.height, tex, {
			pressed = self.pressed,
			hover = self:isMouseOver(),
			active = sel,
		})
		if sel then
			self:drawRect(0, self.height - 2, self.width, 2, 1, 0.95, 0.55, 0.15)
		end
	end
	btn.render = function(self)
		local font = self.font or UIFont.Small
		local th = getTextManager():getFontHeight(font)
		self:drawTextCentre(self.title, self.width / 2, (self.height - th) / 2, 0.92, 0.94, 0.96, 1, font)
	end
	return btn
end

--- Pestaña lateral (columna izquierda estilo Neat Crafting).
---@param x number
---@param y number
---@param w number
---@param h number
---@param title string
---@param terminal GS_TerminalUI
---@param tabKey string
---@return ISButton
function GlobalStorageSiK.TerminalChrome.createSideTabButton(x, y, w, h, title, terminal, tabKey)
	local btn = ISButton:new(x, y, w, h, title, terminal, function()
		terminal:activateTab(tabKey)
	end)
	btn:initialise()
	btn.tabKey = tabKey
	btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.drawBackground = false
	local tex = GlobalStorageSiK.TerminalChrome.neatButtonTextures()
	btn.prerender = function(self)
		local sel = terminal.activeTabKey == self.tabKey
		GlobalStorageSiK.TerminalChrome.drawButtonSurface(self, self.width, self.height, tex, {
			pressed = self.pressed,
			hover = self:isMouseOver(),
			active = sel,
		})
		if sel then
			self:drawRect(0, 0, 3, self.height, 1, 0.95, 0.55, 0.15)
		end
	end
	btn.render = function(self)
		local font = self.font or UIFont.Small
		local th = getTextManager():getFontHeight(font)
		self:drawTextCentre(self.title, self.width / 2, (self.height - th) / 2, 0.92, 0.94, 0.96, 1, font)
	end
	return btn
end

--- Logo Workshop (icon.png) para cabecera del terminal.
---@param pixelSize number|nil tamaño objetivo en px
---@return Texture|nil
function GlobalStorageSiK.TerminalChrome.getLogoTexture(pixelSize)
	pixelSize = pixelSize or 32
	local candidates = {
		"media/ui/GS/GS_Logo_" .. tostring(pixelSize) .. ".png",
		"media/ui/GS/GS_Logo.png",
		"media/ui/GS/GS_WorkshopIcon.png",
	}
	for i = 1, #candidates do
		local tex = getTexture(candidates[i])
		if tex then
			return tex
		end
	end
	return nil
end

--- Dibuja logo en cabecera conservando proporción del PNG Workshop.
---@param panel ISPanel
---@param maxHeight number
---@return number textX
function GlobalStorageSiK.TerminalChrome.drawHeaderLogo(panel, maxHeight)
	local pad = panel.padding or 8
	local tex = GlobalStorageSiK.TerminalChrome.getLogoTexture(maxHeight)
	if not tex or not tex.getWidth then
		return pad + 2
	end
	local tw = tex:getWidth()
	local th = tex:getHeight()
	if tw <= 0 or th <= 0 then
		return pad + 2
	end
	local maxW = math.floor(maxHeight * 1.35)
	local scale = math.min(maxHeight / th, maxW / tw)
	local dw = math.floor(tw * scale)
	local dh = math.floor(th * scale)
	local iconY = math.floor((panel.headerHeight - dh) / 2)
	panel:drawTextureScaled(tex, pad, iconY, dw, dh, 1, 1, 1, 1)
	return pad + dw + 8
end

--- Crea botón de texto estilo NeatUI (3-patch horizontal + etiqueta centrada).
--- El parámetro w es tope máximo de ancho; el ancho real se calcula por el texto.
--- NI_SquareButton es solo para iconos (x,y,size,texture); no usarlo con texto.
---@param x number
---@param y number
---@param w number|nil tope máximo de ancho (nil = 360)
---@param h number|nil
---@param title string
---@param target any
---@param onClick function
---@return ISButton
function GlobalStorageSiK.TerminalChrome.createNeatButton(x, y, w, h, title, target, onClick)
	title = title or ""
	if GlobalStorageSiK.UIDebug then
		onClick = GlobalStorageSiK.UIDebug.wrapClick("btn:" .. tostring(title), onClick)
	end
	h = h or (FONT_HGT_SMALL + 8)
	local font = UIFont.Small
	local maxW
	w, maxW = GlobalStorageSiK.TerminalChrome.resolveNeatButtonWidth(title, w, font)

	local btn = ISButton:new(x, y, w, h, "", target, onClick)
	btn:initialise()
	btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.drawBackground = false
	btn._gsNeatLabel = title
	btn._gsNeatMaxW = maxW
	btn._gsNeatMinW = 52
	btn._gsNeatPadH = 20
	btn:setTitle("")
	btn.font = font
	btn.prerender = function(self)
		local label = self._gsNeatLabel or self.title or ""
		if label ~= self._gsNeatLabel then
			self._gsNeatLabel = label
		end
		GlobalStorageSiK.TerminalChrome.fitNeatButtonToLabel(self)
		GlobalStorageSiK.TerminalChrome.drawButtonSurface(self, self.width, self.height, nil, {
			pressed = self.pressed,
			hover = self:isMouseOver(),
			active = self._gsNeatActive == true,
		})
	end
	btn.render = function(self)
		local font = self.font or UIFont.Small
		local th = getTextManager():getFontHeight(font)
		local r, g, b = 0.92, 0.94, 0.96
		if self.textColor then
			r, g, b = self.textColor.r or r, self.textColor.g or g, self.textColor.b or b
		end
		local label = self._gsNeatLabel or self.title or ""
		if label ~= "" then
			local pad = 6
			if getTextManager():MeasureStringX(font, label) > self.width - pad * 2 then
				label = GlobalStorageSiK.TerminalChrome.truncateText(label, self.width - pad * 2, font)
			end
			self:drawTextCentre(label, self.width / 2, (self.height - th) / 2, r, g, b, 1, font)
		end
	end
	return btn
end

--- Crea caja de búsqueda estilo NC_SearchBox (icono + campo 3-patch + limpiar).
---@param x number
---@param y number
---@param w number
---@param h number
---@param parentPanel any
---@param onTextChange function|nil
---@return ISPanel searchBox, ISTextEntryBox entry
function GlobalStorageSiK.TerminalChrome.createNeatSearchBox(x, y, w, h, parentPanel, onTextChange)
	local box = ISPanel:new(x, y, w, h)
	box:initialise()
	box.drawBackground = false
	box.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	box.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	box.padding = 4
	local btnSize = h
	local searchIcon = getTexture("media/ui/Neat_Crafting/ICON/Icon_SearchItem.png")
		or getTexture("media/ui/NeatUI/numbers_outline/Query.png")
	local searchBtn = GlobalStorageSiK.TerminalChrome.createNeatIconButton(0, 0, btnSize, searchIcon, box, function() end)
	if searchBtn then
		searchBtn:setActive(false)
		box:addChild(searchBtn)
	end
	local entryX = searchBtn and (btnSize + box.padding) or 0
	local entryW = w - entryX
	local entry = ISTextEntryBox:new("", entryX, 0, entryW, h)
	entry:initialise()
	entry.font = UIFont.Small
	GlobalStorageSiK.TerminalChrome.styleTextEntry(entry, box.padding / 2)
	entry:instantiate()
	if onTextChange then
		entry.onTextChange = onTextChange
	end
	box:addChild(entry)
	local clearSize = math.floor(h * 0.6)
	local clearIcon = getTexture("media/ui/Neat_Crafting/ICON/Icon_Close.png")
		or getTexture("media/ui/NeatUI/Icon/Icon_False.png")
	local clearBtn = GlobalStorageSiK.TerminalChrome.createNeatIconButton(
		entryX + entryW - clearSize - 2,
		math.floor((h - clearSize) / 2),
		clearSize,
		clearIcon,
		box,
		function()
			entry:setText("")
			if onTextChange then
				onTextChange()
			end
		end
	)
	if clearBtn then
		clearBtn:setVisible(false)
		clearBtn:setActive(false)
		box.clearBtn = clearBtn
		box:addChild(clearBtn)
		local origChange = entry.onTextChange
		entry.onTextChange = function()
			local hasText = (entry:getText() or "") ~= ""
			clearBtn:setVisible(hasText)
			if origChange then
				origChange()
			end
		end
	end
	box.searchEntry = entry
	return box, entry
end

--- Reposiciona hijos internos del cuadro de búsqueda NeatUI tras resize.
---@param box ISPanel|nil
---@param w number
---@param h number
function GlobalStorageSiK.TerminalChrome.layoutNeatSearchBox(box, w, h)
	if not box then
		return
	end
	box:setWidth(w)
	box:setHeight(h)
	local pad = box.padding or 4
	local btnSize = h
	local entry = box.searchEntry
	local entryX = pad + btnSize
	local clearSize = math.floor(h * 0.6)
	local entryW = math.max(48, w - entryX - clearSize - 6)
	if entry then
		entry:setX(entryX)
		entry:setY(0)
		entry:setWidth(entryW)
		entry:setHeight(h)
	end
	if box.clearBtn then
		box.clearBtn:setX(entryX + entryW - clearSize - 2)
		box.clearBtn:setY(math.floor((h - clearSize) / 2))
		box.clearBtn:setWidth(clearSize)
		box.clearBtn:setHeight(clearSize)
	end
end

--- Crea botón cuadrado con icono (API real de NI_SquareButton).
---@param x number
---@param y number
---@param size number
---@param iconTexture userdata|nil
---@param target any
---@param onClick function
---@return ISButton|nil
function GlobalStorageSiK.TerminalChrome.createNeatIconButton(x, y, size, iconTexture, target, onClick)
	local NISq = GlobalStorageSiK.Libs.getNISquareButton()
	if not NISq then
		return nil
	end
	local ok, btn = pcall(function()
		local b = NISq:new(x, y, size, iconTexture, target, onClick)
		b:initialise()
		return b
	end)
	if ok and btn then
		return btn
	end
	return nil
end

--- Crea interruptor NeatUI (NI_SquareButton + Icon_True, patrón cabecera NR_Header).
---@param x number
---@param y number
---@param size number
---@param checked boolean
---@param target any
---@param onToggle function|nil callback(checked)
---@return ISButton|nil
function GlobalStorageSiK.TerminalChrome.createNeatToggle(x, y, size, checked, target, onToggle)
	local iconOn = getTexture("media/ui/NeatUI/Icon/Icon_True.png")
	local btn
	btn = GlobalStorageSiK.TerminalChrome.createNeatIconButton(
		x, y, size,
		(checked == true) and iconOn or nil,
		target,
		function()
			btn._gsChecked = not (btn._gsChecked == true)
			if btn.setIcon then
				btn:setIcon(btn._gsChecked and iconOn or nil)
			end
			if onToggle then
				onToggle(btn._gsChecked == true)
			end
		end
	)
	if not btn then
		return nil
	end
	btn._gsChecked = checked == true
	btn.setChecked = function(self, value)
		self._gsChecked = value == true
		if self.setIcon then
			self:setIcon(self._gsChecked and iconOn or nil)
		end
	end
	btn.getChecked = function(self)
		return self._gsChecked == true
	end
	btn:setActive(true)
	btn:setActiveColor(0.95, 0.5, 0.1)
	return btn
end

--- Crea botón cerrar con NI_SquareButton + Icon_False (patrón NR_Header).
---@param parent ISUIElement
---@param target any
---@param onClose function
---@param size number|nil
---@return ISButton
function GlobalStorageSiK.TerminalChrome.createCloseButton(parent, target, onClose, size)
	if GlobalStorageSiK.UIDebug then
		onClose = GlobalStorageSiK.UIDebug.wrapClick("btn:close", onClose)
	end
	if parent.closeBtn then
		parent:removeChild(parent.closeBtn)
		if parent.closeBtn.removeFromUIManager then
			parent.closeBtn:removeFromUIManager()
		end
		parent.closeBtn = nil
	end
	local closeSize = size or math.max(getTextManager():getFontHeight(UIFont.Medium), 24)
	local closeIcon = getTexture("media/ui/NeatUI/Icon/Icon_False.png")
	local btn = GlobalStorageSiK.TerminalChrome.createNeatIconButton(-1000, -1000, closeSize, closeIcon, target, onClose)
	if btn then
		btn:setActive(true)
		btn:setActiveColor(0.8, 0.2, 0.2)
		parent:addChild(btn)
		parent.closeBtn = btn
		return btn
	end
	btn = ISButton:new(-1000, -1000, closeSize, closeSize, "X", target, onClose)
	btn:initialise()
	btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.drawBackground = false
	btn:setTitle("X")
	local tex = GlobalStorageSiK.TerminalChrome.neatButtonTextures()
	btn.prerender = function(self)
		GlobalStorageSiK.TerminalChrome.drawButtonSurface(self, self.width, self.height, tex, {
			pressed = self.pressed,
			hover = self:isMouseOver(),
			active = true,
		}, 0, 0)
	end
	parent:addChild(btn)
	parent.closeBtn = btn
	return btn
end

--- Crea panel de barra de peso/capacidad con render NeatUI.
---@param x number
---@param y number
---@param w number
---@param h number|nil
---@return ISPanel
function GlobalStorageSiK.TerminalChrome.createWeightBarPanel(x, y, w, h)
	h = h or math.max(10, math.floor(FONT_HGT_SMALL * 0.85))
	local bar = ISPanel:new(x, y, w, h)
	bar:initialise()
	bar.capacityPercent = 0
	bar.capacityStatus = "ok"
	bar.prerender = function(b)
		ISPanel.prerender(b)
		local fill = math.max(0, math.min(1, (b.capacityPercent or 0) / 100))
		local fr, fg, fb
		if b.capacityStatus == "warning" then
			fr, fg, fb = 0.95, 0.7, 0.2
		elseif b.capacityStatus == "critical" or b.capacityStatus == "full" then
			fr, fg, fb = 0.9, 0.3, 0.25
		else
			fr, fg, fb = GlobalStorageSiK.TerminalChrome.getBarColor(fill)
		end
		GlobalStorageSiK.TerminalChrome.drawProgressBar(b, 0, 0, b.width, b.height, fill, fr, fg, fb)
	end
	return bar
end

--- Dibuja fondo NeatUI del panel principal.
---@param panel ISPanel
function GlobalStorageSiK.TerminalChrome.renderMainBackground(panel)
	GlobalStorageSiK.TerminalChrome.renderPanelBackground(panel)
end

--- Fondo oscuro NeatUI (cabecera + cuerpo) con nine-patch Project Cook / Neat.
---@param panel ISPanel
function GlobalStorageSiK.TerminalChrome.renderPanelBackground(panel)
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	local headerH = panel.headerHeight or 0
	local bodyH = math.max(0, panel.height - headerH)
	local patches = GlobalStorageSiK.TerminalChrome.getNeatPanelPatches()
	local usedPatch = false
	if patches.mainTitle and headerH > 0 then
		usedPatch = GlobalStorageSiK.TerminalChrome.renderNinePatch(panel, patches.mainTitle, 0, 0, panel.width, headerH, 0.08, 0.08, 0.08, 1)
	end
	if patches.mainBody and bodyH > 0 then
		usedPatch = GlobalStorageSiK.TerminalChrome.renderNinePatch(panel, patches.mainBody, 0, headerH, panel.width, bodyH, 0.15, 0.15, 0.15, 0.96) or usedPatch
	end
	if not usedPatch then
		panel:drawRect(0, headerH, panel.width, bodyH, 0.96, pal.bgBody[1], pal.bgBody[2], pal.bgBody[3])
		panel:drawRect(0, 0, panel.width, headerH, 0.98, pal.bgHeader[1], pal.bgHeader[2], pal.bgHeader[3])
	end
	panel:drawRect(0, headerH - 1, panel.width, 1, 1, 0, 0, 0)
	panel:drawRect(0, headerH, panel.width, 1, 0.45, pal.accentLine[1], pal.accentLine[2], pal.accentLine[3])
end

--- Cabecera de la ventana bloqueada (texto blanco, icono GS opcional).
---@param panel ISPanel
function GlobalStorageSiK.TerminalChrome.renderBlockedHeader(panel)
	local iconSize = math.max(20, math.min(28, panel.headerHeight - 10))
	local textX = GlobalStorageSiK.TerminalChrome.drawHeaderLogo(panel, iconSize)
	local titleY = math.floor((panel.headerHeight - getTextManager():getFontHeight(UIFont.Medium)) / 2)
	panel:drawText(T("IGUI_GS_BlockedTitle"), textX, titleY, 1, 1, 1, 1, UIFont.Medium)
end

--- Dibuja cabecera con icono GS y título legible (blanco sobre banda NeatUI).
---@param panel GS_TerminalUI
function GlobalStorageSiK.TerminalChrome.renderHeader(panel)
	local pad = panel.padding or 8
	local textX = pad + 2
	local title = T("IGUI_GS_TerminalTitle")
	local state = panel.terminalState or {}
	local netName = state.networkName
	if not netName or netName == "" then
		netName = T("IGUI_GS_NetworkDefaultName")
	end
	local font = UIFont.Medium
	local tm = getTextManager()
	local titleY = math.floor((panel.headerHeight - tm:getFontHeight(font)) / 2)
	panel:drawText(title, textX + 1, titleY + 1, 0, 0, 0, 0.55, font)
	panel:drawText(title, textX, titleY, 1, 1, 1, 1, font)
	local titleW = tm:MeasureStringX(font, title)
	local sep = " - "
	local sepX = textX + titleW
	panel:drawText(sep, sepX, titleY, 0.5, 0.55, 0.6, 1, font)
	panel:drawText(netName, sepX + tm:MeasureStringX(font, sep), titleY, 0.72, 0.82, 0.92, 1, font)

	-- Version del Core, discreta, junto al boton cerrar - casi inapreciable
	-- a proposito (pedido explicito: no debe destacar, ocultar nada ni
	-- desplazar el resto de la cabecera). Una sola fuente de verdad
	-- (GS_Config.MOD_VERSION, ya sincronizada a mano con mod.info en cada
	-- release, ver CLAUDE.md), no un numero duplicado aparte.
	local verText = "v" .. tostring(GlobalStorageSiK.Config and GlobalStorageSiK.Config.MOD_VERSION or "?")
	local verFont = UIFont.Small
	local verW = tm:MeasureStringX(verFont, verText)
	local closeW = (panel.closeBtn and panel.closeBtn.width) or 24
	local verX = panel.width - pad - closeW - 10 - verW
	local verY = math.floor((panel.headerHeight - tm:getFontHeight(verFont)) / 2)
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	panel:drawText(verText, verX, verY, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 0.55, verFont)
end

--- Dibuja barra de estado inferior en pestaña Red.
---@param panel GS_TerminalUI
---@param state table|nil
function GlobalStorageSiK.TerminalChrome.renderStatusFooter(panel, state)
	if not panel.statusFooterHeight or panel.statusFooterHeight <= 0 then
		return
	end
	local y = panel.height - panel.statusFooterHeight
	panel:drawRect(0, y, panel.width, panel.statusFooterHeight, 0.85, 0.08, 0.08, 0.08)
	panel:drawRect(0, y, panel.width, 1, 0.7, 0.28, 0.28, 0.28)
	local networkId = state and state.networkId or "—"
	local netName = state and state.networkName or ""
	local text
	if netName ~= "" and networkId ~= "—" then
		text = T("IGUI_GS_NetworkDisplay", netName, networkId)
	else
		text = T("IGUI_GS_NetworkIdInternal", networkId)
	end
	panel:drawText(text, panel.padding + 4, y + 5, 0.55, 0.6, 0.65, 1, UIFont.Small)
end

--- Configura arrastre solo desde la cabecera.
---@param panel GS_TerminalUI
function GlobalStorageSiK.TerminalChrome.setupHeaderDrag(panel)
	panel.moveWithMouse = false
	panel.moving = false

	panel.onMouseDown = function(self, x, y)
		if y >= 0 and y < self.headerHeight and x < self.width - (self.closeBtn and self.closeBtn.width or 40) then
			self.moving = true
			self:setCapture(true)
			return true
		end
		return ISPanel.onMouseDown(self, x, y)
	end

	panel.onMouseUp = function(self, x, y)
		if self.moving then
			self.moving = false
			self:setCapture(false)
			return true
		end
		return ISPanel.onMouseUp(self, x, y)
	end

	panel.onMouseUpOutside = function(self, x, y)
		if self.moving then
			self.moving = false
			self:setCapture(false)
			return true
		end
		return ISPanel.onMouseUpOutside(self, x, y)
	end

	panel.onMouseMove = function(self, dx, dy)
		if self.moving then
			self:setX(self.x + dx)
			self:setY(self.y + dy)
			return true
		end
		return ISPanel.onMouseMove(self, dx, dy)
	end

	panel.onMouseMoveOutside = function(self, dx, dy)
		if self.moving then
			self:setX(self.x + dx)
			self:setY(self.y + dy)
			return true
		end
		return ISPanel.onMouseMoveOutside(self, dx, dy)
	end
end

--- Enlaza Enter y búsqueda en tiempo real en el buscador de ítems.
---@param panel GS_TerminalUI
---@param searchEntry ISTextEntryBox
function GlobalStorageSiK.TerminalChrome.bindSearchEntry(panel, searchEntry)
	if not searchEntry then
		return
	end
	if searchEntry.setPlaceholderText then
		searchEntry:setPlaceholderText(T("IGUI_GS_SearchPlaceholder"))
	end

	local SEARCH_MIN_CHARS = 3
	local DEBOUNCE_MS = 180
	local pendingTick = nil

	local function cancelPending()
		if pendingTick and Events and Events.OnTick and Events.OnTick.Remove then
			Events.OnTick.Remove(pendingTick)
			pendingTick = nil
		end
	end

	local function runSearch(force)
		if panel.onSearch then
			if force == true then
				panel:onSearch(true)
			else
				panel:onSearch(false)
			end
		end
	end

	searchEntry.onPressEnter = function()
		cancelPending()
		runSearch(true)
	end

	searchEntry.onTextChange = function()
		local text = searchEntry:getText() or ""
		cancelPending()
		if text == "" or #text < SEARCH_MIN_CHARS then
			runSearch(false)
			return
		end
		local deadline = (getTimestampMs and getTimestampMs() or 0) + DEBOUNCE_MS
		pendingTick = function()
			if getTimestampMs and getTimestampMs() < deadline then
				return
			end
			cancelPending()
			runSearch(false)
		end
		if Events and Events.OnTick then
			Events.OnTick.Add(pendingTick)
		end
	end
end

--- Trocea un string UTF-8 en su lista de caracteres reales (1-4 bytes cada
--- uno), sin partir nunca un caracter multibyte por la mitad. Manual, byte
--- a byte segun el prefijo UTF-8 - NO se puede usar la libreria "utf8" de
--- Lua 5.3+, Kahlua (el interprete que usa PZ) no la expone (mismo tipo de
--- suposicion equivocada que ya causo el bug real de next() en
--- GS_Addons.lua: nunca dar por hecho que existe una funcion de stdlib sin
--- comprobarlo primero).
---@param str string
---@return string[]
local function utf8Chars(str)
	local chars = {}
	local i = 1
	local len = #str
	while i <= len do
		local b = string.byte(str, i)
		local charLen = 1
		if b >= 0xF0 then
			charLen = 4
		elseif b >= 0xE0 then
			charLen = 3
		elseif b >= 0xC0 then
			charLen = 2
		end
		table.insert(chars, string.sub(str, i, i + charLen - 1))
		i = i + charLen
	end
	return chars
end

--- Trocea una "palabra" que por si sola ya excede maxWidth, caracter a
--- caracter, en trozos que si caben.
---@param token string
---@param tm TextManager
---@param font UIFont
---@param maxWidth number
---@return string[]
local function splitLongToken(token, tm, font, maxWidth)
	local chunks = {}
	local current = ""
	local chars = utf8Chars(token)
	for i = 1, #chars do
		local ch = chars[i]
		local candidate = current .. ch
		if tm:MeasureStringX(font, candidate) > maxWidth and current ~= "" then
			table.insert(chunks, current)
			current = ch
		else
			current = candidate
		end
	end
	if current ~= "" then
		table.insert(chunks, current)
	end
	return chunks
end

--- Parte texto en líneas según ancho máximo (px).
--- BUG REAL confirmado (reportado por un jugador: "no soporta chino", pese
--- a que la traduccion SI existe completa - ver Translate/CH/*.json): el
--- chino/japones/coreano se escribe SIN espacios entre palabras, asi que
--- "%S+" capturaba la frase ENTERA como una unica "palabra" - y esa unica
--- palabra nunca se partia (el chequeo de ancho exige line~="" para
--- disparar el salto, pero en la primera vuelta line siempre es ""),
--- desbordando el panel por completo con una sola linea gigante. Ahora,
--- cualquier "palabra" que por si sola ya exceda maxWidth (CJK sin
--- espacios, o una URL larga en cualquier idioma) se trocea caracter a
--- caracter en vez de desbordar sin control.
---@param text string
---@param maxWidth number
---@param font UIFont|nil
---@return string[]
function GlobalStorageSiK.TerminalChrome.wrapTextLines(text, maxWidth, font)
	local lines = {}
	local tm = getTextManager()
	font = font or UIFont.Small
	maxWidth = math.max(40, maxWidth or 200)
	for paragraph in string.gmatch(tostring(text or "") .. "\n", "(.-)\n") do
		local line = ""
		for word in string.gmatch(paragraph, "%S+") do
			if tm:MeasureStringX(font, word) > maxWidth then
				if line ~= "" then
					table.insert(lines, line)
					line = ""
				end
				local chunks = splitLongToken(word, tm, font, maxWidth)
				for i = 1, #chunks - 1 do
					table.insert(lines, chunks[i])
				end
				line = chunks[#chunks] or ""
			else
				local candidate = line == "" and word or (line .. " " .. word)
				if tm:MeasureStringX(font, candidate) > maxWidth and line ~= "" then
					table.insert(lines, line)
					line = word
				else
					line = candidate
				end
			end
		end
		if line ~= "" then
			table.insert(lines, line)
		end
	end
	if #lines == 0 then
		table.insert(lines, "")
	end
	return lines
end

--- Altura en px de un bloque de texto envuelto.
---@param text string
---@param maxWidth number
---@param font UIFont|nil
---@param lineGap number|nil
---@return number lineCount
function GlobalStorageSiK.TerminalChrome.countWrappedLines(text, maxWidth, font, lineGap)
	local fontH = getTextManager():getFontHeight(font or UIFont.Small)
	local gap = lineGap or 3
	local n = #GlobalStorageSiK.TerminalChrome.wrapTextLines(text, maxWidth, font)
	return n * (fontH + gap)
end

--- Añade una fila de "requisito" (icono del item + texto envuelto, coloreado
--- segun se cumpla o no) a un panel/scroll - usado en la pantalla de bloqueo
--- y en las ventanas "Conseguir PC"/"Fabricar lector" para que cada linea de
--- requisito muestre el icono real del item en vez de solo texto.
---@param parent ISPanel  panel/scroll al que añadir los hijos (necesita :addChild)
---@param x number
---@param y number
---@param w number  ancho total disponible (icono + texto)
---@param iconFullType string|Texture|nil  fullType del item cuyo icono mostrar, o una Texture ya resuelta (p.ej. icono de perk) - nil = sin icono, solo texto
---@param text string
---@param ok boolean
---@return number nextY
function GlobalStorageSiK.TerminalChrome.addRequirementLine(parent, x, y, w, iconFullType, text, ok)
	if not parent then return y end
	local ICON = 32
	local gap = 8
	local iconTex = nil
	if type(iconFullType) == "string" then
		iconTex = GlobalStorageSiK.CraftUtils and GlobalStorageSiK.CraftUtils.getItemIconTexture
			and GlobalStorageSiK.CraftUtils.getItemIconTexture(iconFullType) or nil
	elseif iconFullType then
		iconTex = iconFullType
	end
	local textX = iconTex and (x + ICON + gap) or x
	local textW = math.max(40, w - (textX - x))
	local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
	local r, g, b = (ok and 0.5 or 0.82), (ok and 0.78 or 0.32), (ok and 0.5 or 0.32)
	local startY = y
	for _, line in ipairs(GlobalStorageSiK.TerminalChrome.wrapTextLines(text, textW, UIFont.Small)) do
		local lbl = ISLabel:new(textX, y, FONT_HGT_SMALL, line, r, g, b, 1, UIFont.Small, true)
		lbl:initialise()
		parent:addChild(lbl)
		y = y + FONT_HGT_SMALL + 2
	end
	if iconTex then
		local rowH = math.max(ICON, y - startY)
		local iconPanel = ISPanel:new(x, startY, ICON, rowH)
		iconPanel:initialise()
		iconPanel.drawBackground = false
		iconPanel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
		iconPanel._gsIconTex = iconTex
		iconPanel.prerender = function(self)
			ISPanel.prerender(self)
			if self._gsIconTex then
				local iy = math.max(0, math.floor((self.height - ICON) / 2))
				self:drawTextureScaledAspect(self._gsIconTex, 0, iy, ICON, ICON, 1, 1, 1, 1)
			end
		end
		parent:addChild(iconPanel)
	end
	return y
end

--- Marca un widget como decorativo (no intercepta clics).
---@param widget ISUIElement|nil
function GlobalStorageSiK.TerminalChrome.makeMousePassthrough(widget)
	if not widget then
		return
	end
	if widget.setMouseTransparent then
		widget:setMouseTransparent(true)
	end
	widget.onMouseDown = function()
		return false
	end
	widget.onMouseUp = function()
		return false
	end
end

--- Marca paneles decorativos como transparentes al ratón.
---@param widgets ISUIElement[]
function GlobalStorageSiK.TerminalChrome.setMouseTransparentAll(widgets)
	if not widgets then
		return
	end
	for i = 1, #widgets do
		GlobalStorageSiK.TerminalChrome.makeMousePassthrough(widgets[i])
	end
end

--- Eleva solo controles interactivos (sin tocar el panel raíz ni UIManager).
---@param widgets ISUIElement[]
function GlobalStorageSiK.TerminalChrome.raiseModalControls(widgets)
	if not widgets then
		return
	end
	for i = 1, #widgets do
		local w = widgets[i]
		if w and w.bringToTop then
			w:bringToTop()
		end
	end
end

--- Posiciona botón cerrar en la cabecera del modal.
---@param panel ISPanel|nil
---@param pad number|nil
function GlobalStorageSiK.TerminalChrome.layoutModalChrome(panel, pad)
	if not panel then
		return
	end
	pad = pad or panel.padding or 8
	if panel.closeBtn then
		local sz = panel.closeBtn.width or 24
		panel.closeBtn:setX(panel.width - pad - sz)
		panel.closeBtn:setY(math.max(2, math.floor(((panel.headerHeight or sz) - sz) / 2)))
		panel.closeBtn:bringToTop()
	end
end

--- Cabecera arrastrable + botón cerrar para diálogos pequeños.
---@param panel ISPanel
---@param onClose function
---@param pad number|nil
function GlobalStorageSiK.TerminalChrome.setupModalPanel(panel, onClose, pad)
	pad = pad or 14
	panel.padding = pad
	panel.moveWithMouse = false
	GlobalStorageSiK.TerminalChrome.setupHeaderDrag(panel)
	GlobalStorageSiK.TerminalChrome.createCloseButton(panel, panel, onClose)
	GlobalStorageSiK.TerminalChrome.layoutModalChrome(panel, pad)
end

--- Ancho estandar para modales de edicion/confirmacion pequeños (fila de
--- miembro, nodo, renombrar, etc.) - apaisado (mas ancho que alto), en vez
--- de que cada ventana invente su propio ancho fijo distinto. La ALTURA
--- nunca es un numero fijo adivinado: se calcula siempre desde el contenido
--- real (wrapTextLines + suma de alturas reales de cada fila) y luego se
--- centra con centerModal. Ver GS_TerminalUI_MemberEditor.lua como
--- referencia de uso; migrar el resto de modales pequeños a este mismo
--- estandar es trabajo pendiente, no se ha tocado en este cambio.
GlobalStorageSiK.TerminalChrome.STANDARD_MODAL_W = 460

--- Centra un panel modal ya dimensionado (llamar DESPUES de fijar su alto
--- real por contenido, nunca antes) en el centro de la pantalla actual.
---@param panel ISPanel|nil
function GlobalStorageSiK.TerminalChrome.centerModal(panel)
	if not panel then
		return
	end
	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	panel:setX(math.floor((sw - panel.width) / 2))
	panel:setY(math.floor((sh - panel.height) / 2))
end

--- Muestra modal encima del resto de UI (una sola vez al abrir).
---@param panel ISPanel|nil
function GlobalStorageSiK.TerminalChrome.finalizeModalShow(panel)
	if not panel then
		return
	end
	GlobalStorageSiK.TerminalChrome.layoutModalChrome(panel, panel.padding)
	if panel.setVisible then
		panel:setVisible(true)
	end
	if panel.setAlwaysOnTop then
		panel:setAlwaysOnTop(true)
	end
	if panel.bringToTop then
		panel:bringToTop()
	end
	if UIManager and UIManager.pushToTop then
		pcall(function()
			UIManager:pushToTop(panel)
		end)
	end
end

---@deprecated Usar raiseModalControls + finalizeModalShow.
---@param panel ISPanel|nil
---@param widgets ISUIElement[]
function GlobalStorageSiK.TerminalChrome.bringModalControlsToFront(panel, widgets)
	GlobalStorageSiK.TerminalChrome.raiseModalControls(widgets)
end

--- Crea panel de fondo tipo "tarjeta" para un bloque de sección.
--- Debe añadirse al scroll ANTES que los demás hijos del bloque (se renderiza debajo).
---@param x number
---@param y number
---@param w number
---@param h number
---@return ISPanel
function GlobalStorageSiK.TerminalChrome.createSectionCard(x, y, w, h)
	local card = ISPanel:new(x, y, w, math.max(24, h))
	card:initialise()
	card.drawBackground = false
	card.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	card.prerender = function(self)
		ISPanel.prerender(self)
		local p = GlobalStorageSiK.TerminalChrome.PALETTE
		self:drawRect(0, 0, self.width, self.height,
			0.46, p.bgBody[1] * 0.72, p.bgBody[2] * 0.72, p.bgBody[3] * 0.78)
		self:drawRect(0, 0, 2, self.height,
			0.50, p.btnActive[1], p.btnActive[2], p.btnActive[3])
		self:drawRectBorder(0, 0, self.width, self.height,
			0.20, p.accentLine[1], p.accentLine[2], p.accentLine[3])
	end
	return card
end

--- Actualiza dimensiones de una tarjeta de sección tras construir su contenido.
---@param card ISPanel|nil
---@param x number
---@param y number
---@param w number
---@param h number
function GlobalStorageSiK.TerminalChrome.resizeSectionCard(card, x, y, w, h)
	if not card then return end
	card:setX(x)
	card:setY(y)
	card:setWidth(math.max(40, w))
	card:setHeight(math.max(24, h))
end

--- Crea fila de indicador de estado: punto de color + texto, actualizable por prerender.
---@param x number
---@param y number
---@param w number
---@param h number|nil
---@return ISPanel
function GlobalStorageSiK.TerminalChrome.createStatusIndicatorRow(x, y, w, h)
	h = h or (FONT_HGT_SMALL + 4)
	local row = ISPanel:new(x, y, w, h)
	row:initialise()
	row.drawBackground = false
	row.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	row._gsStatus = "ok"
	row._gsText   = ""
	row.prerender = function(self)
		ISPanel.prerender(self)
		local p = GlobalStorageSiK.TerminalChrome.PALETTE
		local dotSz = 6
		local dotY  = math.floor((self.height - dotSz) / 2)
		local cr, cg, cb = 0.4, 0.85, 0.4
		if     self._gsStatus == "warn"  then cr, cg, cb = 0.9, 0.75, 0.35
		elseif self._gsStatus == "error" then cr, cg, cb = 0.9, 0.38, 0.35
		elseif self._gsStatus == "info"  then cr, cg, cb = 0.55, 0.72, 0.92
		elseif self._gsStatus == "muted" then cr, cg, cb = p.textMuted[1], p.textMuted[2], p.textMuted[3]
		end
		self:drawRect(2, dotY, dotSz, dotSz, 1, cr, cg, cb)
		local ty = math.floor((self.height - FONT_HGT_SMALL) / 2)
		self:drawText(self._gsText, dotSz + 8, ty,
			p.textPrimary[1], p.textPrimary[2], p.textPrimary[3], 1, UIFont.Small)
	end
	return row
end

--- Actualiza el texto y estado de una fila indicadora sin reconstruir.
---@param row ISPanel|nil
---@param text string
---@param status string  "ok"|"warn"|"error"|"info"|"muted"
---@param maxW number|nil
function GlobalStorageSiK.TerminalChrome.setStatusIndicatorRow(row, text, status, maxW)
	if not row then return end
	if maxW and maxW > 20 then
		text = GlobalStorageSiK.TerminalChrome.truncateText(text or "", maxW - 16, UIFont.Small)
	end
	row._gsText   = text   or ""
	row._gsStatus = status or "ok"
end

--- Aplica estilo de botón peligroso (rojo oscuro) usando PALETTE.
---@param btn ISButton|nil
function GlobalStorageSiK.TerminalChrome.applyDangerButton(btn)
	if not btn then return end
	local p = GlobalStorageSiK.TerminalChrome.PALETTE
	btn.borderColor      = { r = p.dangerBorder[1], g = p.dangerBorder[2], b = p.dangerBorder[3], a = 0.9 }
	btn.backgroundColor  = { r = p.dangerBg[1],     g = p.dangerBg[2],     b = p.dangerBg[3],     a = 0.92 }
	btn.backgroundColorHL = { r = p.dangerHover[1],  g = p.dangerHover[2],  b = p.dangerHover[3],  a = 1 }
end

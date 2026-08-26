--[[
	GlobalStorageSiK - Nucleo visual compartido SiK UI
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

GlobalStorageSiK.SiK_UI = GlobalStorageSiK.SiK_UI or {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

--- Paleta propia y compartida de SiK UI.
GlobalStorageSiK.SiK_UI.PALETTE = {
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
	statusInfo   = { 0.55, 0.72, 0.92 },
	dangerBorder = { 0.55, 0.28, 0.28 },
	dangerBg     = { 0.18, 0.08, 0.08 },
	dangerHover  = { 0.28, 0.12, 0.12 },
	-- Motor de reglas AND/OR/NOT (dev26): un color por operador, reutilizado
	-- en las tarjetas de regla, los puntos de composicion de la lista de
	-- contenedores y el borde del modal "Anadir regla" - mismo trio en los
	-- 3 sitios, nunca inventado aparte.
	ruleOr  = { 0.55, 0.72, 0.92 },
	ruleAnd = { 0.9,  0.75, 0.35 },
	ruleNot = { 0.95, 0.38, 0.35 },
	-- Aliases usados en Network y Permissions
	accent    = { 0.95, 0.5,  0.1  },
	cardBg    = { 0.06, 0.06, 0.08 },
	divider   = { 0.18, 0.18, 0.22 },
}

-- Recursos propios del framework SiK_UI. Los PNG runtime son copias 64x64
-- optimizadas; los maestros de 1254x1254 permanecen fuera del paquete en
-- Resources/source. Un unico resolver evita rutas repetidas y permite que
-- Core y addons compartan exactamente el mismo arte.
local SIK_ICON_PATHS = {
	check = "media/ui/SiKUI/SiK_Icon_Check.png",
	close = "media/ui/SiKUI/SiK_Icon_Close.png",
	info = "media/ui/SiKUI/SiK_Icon_Info.png",
	search = "media/ui/SiKUI/SiK_Icon_Search.png",
}

---@param key string
---@return Texture|nil
function GlobalStorageSiK.SiK_UI.getIconTexture(key)
	GlobalStorageSiK.SiK_UI._sikIcons = GlobalStorageSiK.SiK_UI._sikIcons or {}
	local cache = GlobalStorageSiK.SiK_UI._sikIcons
	if cache[key] == nil then
		cache[key] = getTexture(SIK_ICON_PATHS[key] or "") or false
	end
	return cache[key] or nil
end

---@param text string
---@param maxWidth number
---@param font UIFont|nil
---@return string
function GlobalStorageSiK.SiK_UI.truncateText(text, maxWidth, font)
	return GlobalStorageSiK.Libs.truncateText(text, maxWidth, font, "..")
end

--- Antiguedad relativa legible ("hace 3h") de una marca de tiempo ms.
--- Compartido entre el panel de staff (GS_AdminDashboard.lua) y la pestaña
--- normal de permisos (GS_TerminalUI_Permissions.lua) para mostrar
--- "ultima conexion" sin duplicar la misma logica en dos ficheros.
---@param tsMs number|nil
---@return string
function GlobalStorageSiK.SiK_UI.relativeAge(tsMs)
	tsMs = tonumber(tsMs) or 0
	if tsMs <= 0 then return "?" end
	local T = GlobalStorageSiK.I18n.text
	local nowTs = (getTimestampMs and getTimestampMs()) or tsMs
	local deltaS = math.max(0, math.floor((nowTs - tsMs) / 1000))
	if deltaS < 60 then return T("IGUI_GS_AdminAgeSeconds", deltaS) end
	if deltaS < 3600 then return T("IGUI_GS_AdminAgeMinutes", math.floor(deltaS / 60)) end
	if deltaS < 86400 then return T("IGUI_GS_AdminAgeHours", math.floor(deltaS / 3600)) end
	return T("IGUI_GS_AdminAgeDays", math.floor(deltaS / 86400))
end

--- Ancho comun de la barra de desplazamiento vertical.
---@return number
function GlobalStorageSiK.SiK_UI.scrollBarWidth()
	return math.floor(FONT_HGT_SMALL * 0.6)
end

--- Ancho recomendado para boton SiK UI segun texto.
---@param title string
---@param font UIFont|nil
---@param padH number|nil
---@param minW number|nil
---@param maxW number|nil
---@return number
function GlobalStorageSiK.SiK_UI.measureButtonWidth(title, font, padH, minW, maxW)
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
function GlobalStorageSiK.SiK_UI.resolveButtonWidth(title, w, font, padH, minW)
	font = font or UIFont.Small
	padH = padH or 20
	minW = minW or 52
	local maxW = (w and w > 0) and w or 360
	return GlobalStorageSiK.SiK_UI.measureButtonWidth(title, font, padH, minW, maxW), maxW
end

--- Ajusta ancho del botón al texto actual (sin estirar la textura) - salvo
--- que el boton se creara con fullWidth=true (ver createButton), en cuyo
--- caso SIEMPRE ocupa el ancho asignado en vez de encogerse al contenido -
--- pedido explicito del usuario ("de ancho dinamico... la diferencia es
--- clara" comparando con el mockup, donde los botones de accion llenan
--- siempre su fila/tarjeta entera).
---@param btn ISButton|nil
function GlobalStorageSiK.SiK_UI.fitButtonToLabel(btn)
	if not btn then
		return
	end
	if btn._sikUiFullWidth then
		if btn._sikUiMaxW and btn._sikUiMaxW ~= btn.width then
			btn:setWidth(btn._sikUiMaxW)
		end
		return
	end
	local label = btn._sikUiLabel or btn.title or ""
	local font = btn.font or UIFont.Small
	local nw = GlobalStorageSiK.SiK_UI.measureButtonWidth(
		label, font, btn._sikUiPadH or 20, btn._sikUiMinW or 52, btn._sikUiMaxW or 360
	)
	if nw ~= btn.width then
		btn:setWidth(nw)
	end
end

--- Dibuja superficie de botón (rectángulo plano, esquinas cuadradas).
---@param panel ISUIElement
---@param w number
---@param h number
---@param opts table|nil pressed, hover, active, locked
---@param ox number|nil
---@param oy number|nil
function GlobalStorageSiK.SiK_UI.drawButtonSurface(panel, w, h, opts, ox, oy)
	opts = opts or {}
	ox = ox or 0
	oy = oy or 0
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local r, g, b = pal.btnDefault[1], pal.btnDefault[2], pal.btnDefault[3]
	if opts.locked then
		-- Boton "bloqueado", visible pero inerte (pedido 2026-08-26: reservar
		-- el hueco en vez de ocultar/mostrar el boton segun se cumplan
		-- requisitos, para no mover el resto de la UI). Ignora hover/pressed/
		-- active a proposito - un boton bloqueado no reacciona al raton.
		local m = pal.textMuted
		panel:drawRect(ox, oy, w, h, 0.5, m[1] * 0.3, m[2] * 0.3, m[3] * 0.3)
		panel:drawRectBorder(ox, oy, w, h, 0.4, m[1], m[2], m[3])
		return
	end
	if opts.active then
		local ac = opts.activeColor or pal.btnActive
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
	-- Esquinas cuadradas SIEMPRE: superficie plana propia, no un fallback.
	-- El mismo aspecto se pinta con independencia de librerias externas.
	panel:drawRect(ox, oy, w, h, 0.94, r * 0.22, g * 0.22, b * 0.22)
	local br = pal.border
	panel:drawRectBorder(ox, oy, w, h, 0.9, br[1], br[2], br[3])
end

--- Fondo de fila de tabla (rayas + hover).
---@param panel ISPanel
---@param rowIndex number|nil
---@param hovered boolean|nil
---@param selected boolean|nil
function GlobalStorageSiK.SiK_UI.drawTableRowBackground(panel, rowIndex, hovered, selected)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
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
function GlobalStorageSiK.SiK_UI.drawTableHeaderLine(panel)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	panel:drawRect(0, panel.height - 1, panel.width, 1, 0.65, pal.accentLine[1], pal.accentLine[2], pal.accentLine[3])
end

--- Cabecera de zona colapsable (bloque contenedores).
---@param panel ISPanel
---@param hovered boolean|nil
function GlobalStorageSiK.SiK_UI.drawZoneHeaderBackground(panel, hovered)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local z = hovered and pal.zoneHeaderHover or pal.zoneHeader
	panel:drawRect(0, 0, panel.width, panel.height, z[4], z[1], z[2], z[3])
end

--- Crea etiqueta de seccion con estilo SiK UI.
---@param x number
---@param y number
---@param text string
---@return ISLabel
function GlobalStorageSiK.SiK_UI.createSectionLabel(x, y, text)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local lbl = ISLabel:new(x, y, FONT_HGT_SMALL, text, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small, true)
	lbl:initialise()
	return lbl
end

--- Crea el titulo de una ventana modal (fuente Medium, blanco-ish) - antes
--- repetido a mano de forma IDENTICA en 5 ficheros distintos
--- (GS_AdminDashboard.lua x3, GS_TerminalUI_MemberEditor.lua,
--- GS_TerminalUI_TerminalEditor.lua, GS_TerminalInstallReaderChoice.lua):
--- ISLabel:new(pad, y, FONT_HGT_MEDIUM, texto, 0.95, 0.95, 0.95, 1,
--- UIFont.Medium, true). Distinto de createSectionLabel (fuente Small, para
--- sub-secciones DENTRO de una ventana) - este es para el titulo de la
--- ventana/modal en si. Cero cambio visual: mismo tamaño/color de siempre,
--- solo deja de repetirse el literal.
---@param x number
---@param y number
---@param text string
---@return ISLabel
function GlobalStorageSiK.SiK_UI.createWindowTitleLabel(x, y, text)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local fontHgtMedium = getTextManager():getFontHeight(UIFont.Medium)
	local lbl = ISLabel:new(x, y, fontHgtMedium, text, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Medium, true)
	lbl:initialise()
	return lbl
end

--- Crea etiqueta de hint secundario.
---@param x number
---@param y number
---@param text string
---@param lineH number|nil
---@return ISLabel
function GlobalStorageSiK.SiK_UI.createHintLabel(x, y, text, lineH)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local h = lineH or FONT_HGT_SMALL
	local lbl = ISLabel:new(x, y, h, text, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small, true)
	lbl:initialise()
	return lbl
end

--- Boton cuadrado "?" sin accion propia (no-op deliberado), solo para
--- alojar un tooltip largo junto al titulo de un bloque - dev26 ronda 4,
--- pedido explicito del usuario para sacar los parrafos explicativos
--- siempre visibles (prioridad, protocolo...) de la vista y dejarlos "a
--- disposicion" solo al pasar el raton, sin ocupar espacio permanente.
--- ISButton vanilla puro (mismo camino que createButton).
---@param x number
---@param y number
---@param size number
---@param target any
---@param tooltip string
---@return ISButton
function GlobalStorageSiK.SiK_UI.createInfoHintButton(x, y, size, target, tooltip)
	local icon = GlobalStorageSiK.SiK_UI.getIconTexture("info")
	local btn = GlobalStorageSiK.SiK_UI.createIconButton(x, y, size, icon, target, function() end)
	-- ISButton NO define setToolTipMap (eso es exclusivo de ISComboBox, otro
	-- mecanismo) - el tooltip real de ISButton/ISTextEntryBox es
	-- self.tooltip via :setTooltip(text) (ver ISUI/ISButton.lua:445). El
	-- guard "if X.setToolTipMap then" de toda esta ronda pasaba siempre
	-- silenciosamente en false: NINGUN tooltip de esta ronda llegaba a
	-- pintarse en juego (bug real reportado por el usuario, "los ? no
	-- muestran ningun tooltip").
	btn:setTooltip(tooltip)
	return btn
end

--- Coloca un botón "?" (createInfoHintButton) justo después de un título o
--- etiqueta ya dibujado, para sacar un párrafo explicativo largo de la vista
--- permanente y dejarlo solo en el tooltip - patrón ya usado en
--- GS_TerminalUI_NodeEditor.lua/GS_TerminalUI_ZoneEditor.lua (cada uno con su
--- propia copia local); centralizado aquí en dev39 para que Craft/Builder y
--- cualquier ventana futura lo reutilicen sin duplicar la misma función de
--- 6 líneas otra vez (pedido explícito del usuario: extender la norma a
--- "cualquier otra ventana, build, crafteos, craft, etc.").
---@param scroll table
---@param x number
---@param y number
---@param titleText string  -- texto YA renderizado justo antes (para medir dónde acaba)
---@param tooltip string
---@param target any
---@return ISButton
function GlobalStorageSiK.SiK_UI.addBlockInfoBtn(scroll, x, y, titleText, tooltip, target)
	local size = getTextManager():getFontHeight(UIFont.Small)
	local titleW = getTextManager():MeasureStringX(UIFont.Small, titleText or "")
	local btn = GlobalStorageSiK.SiK_UI.createInfoHintButton(x + titleW + 6, y, size, target, tooltip)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, btn)
	return btn
end

--- Color de barra según porcentaje (patrón NR_DrawBar).
---@param pct number 0.0–1.0
---@return number r, number g, number b
function GlobalStorageSiK.SiK_UI.getBarColor(pct)
	if pct > 0.5 then
		return 0.2, 0.8, 0.3
	elseif pct > 0.25 then
		return 0.9, 0.5, 0.1
	end
	return 0.85, 0.2, 0.2
end

--- Dibuja la barra de progreso plana de SiK UI.
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
function GlobalStorageSiK.SiK_UI.drawProgressBar(panel, x, y, w, h, pct, fr, fg, fb, label)
	if not panel then
		return
	end
	pct = math.max(0, math.min(1, tonumber(pct) or 0))
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	panel:drawRect(x, y, w, h, 1, 0.06, 0.06, 0.06)
	local fillW = math.floor(math.max(0, w - 2) * pct)
	if fillW > 0 then
		if not fr then
			fr, fg, fb = GlobalStorageSiK.SiK_UI.getBarColor(pct)
		end
		panel:drawRect(x + 1, y + 1, fillW, math.max(0, h - 2), 1, fr, fg, fb)
	end
	panel:drawRectBorder(x, y, w, h, 0.9, pal.border[1], pal.border[2], pal.border[3])
	if label and label ~= "" then
		local ty = y + math.floor((h - FONT_HGT_SMALL) / 2)
		panel:drawTextCentre(label, x + math.floor(w / 2), ty, 1, 1, 1, 1, UIFont.Small)
	end
end

--- Separador horizontal 1px (patrón NR_DrawUtils).
---@param panel ISPanel
---@param y number
---@param pad number|nil
function GlobalStorageSiK.SiK_UI.drawSeparator(panel, y, pad)
	if not panel then
		return
	end
	pad = pad or (panel.padding or 8)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE.accentLine
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
function GlobalStorageSiK.SiK_UI.drawLabelValue(panel, label, value, xPivot, valX, y, la, vr, vg, vb)
	panel:drawTextRight(label, xPivot, y, 1, 1, 1, la or 0.7, UIFont.Small)
	panel:drawText(value, valX, y, vr or 1, vg or 1, vb or 1, 1, UIFont.Small)
end

-- Parche de clase global para el listado desplegable compartido (2026-08-25,
-- rediseño desplegables/campos, mismo motivo que los botones): ISComboBox
-- usa UN SOLO popup para TODO el juego (ISComboBox.SharedPopup) - el borde
-- blanco fijo de ISComboBoxPopup:render (drawRectBorderStatic(...,1,1,1),
-- confirmado leyendo el fichero real del motor) no se puede recolorear por
-- instancia ni via ningun campo de color del combo, solo sobrescribiendo el
-- metodo de clase una vez. Se dibuja NUESTRO borde encima del blanco de
-- vanilla (no se reimplementa el metodo entero) para no arriesgar divergir
-- de la logica real de scroll/filtro/tooWide que sigue intacta. El resto
-- del popup (fondo de fila, fila resaltada) ya sale correcto solo con
-- backgroundColorMouseOver puesto en styleComboBox, sin tocar nada aqui.
local function ensureComboPopupStyled()
	if GlobalStorageSiK.SiK_UI._comboPopupStyled then
		return
	end
	GlobalStorageSiK.SiK_UI._comboPopupStyled = true
	if not ISComboBoxPopup then
		return
	end
	local origRender = ISComboBoxPopup.render
	ISComboBoxPopup.render = function(self)
		origRender(self)
		local br = GlobalStorageSiK.SiK_UI.PALETTE.border
		self:drawRectBorderStatic(-1, -1, self:getWidth() + 2, self:getHeight() + 2, 0.95, br[1], br[2], br[3])
	end
end

--- Fondo plano de tarjeta (recetas, bloques), sin textura externa.
---@param panel ISPanel
---@param titleHeight number|nil
function GlobalStorageSiK.SiK_UI.drawCardBackground(panel, titleHeight)
	titleHeight = titleHeight or 0
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local bodyH = math.max(0, panel.height - titleHeight)
	panel:drawRect(0, titleHeight, panel.width, bodyH, 0.94, pal.bgCard[1], pal.bgCard[2], pal.bgCard[3])
	if titleHeight > 0 then
		panel:drawRect(0, 0, panel.width, titleHeight, 0.98, pal.bgHeader[1], pal.bgHeader[2], pal.bgHeader[3])
	end
	local br = pal.border
	panel:drawRectBorder(0, 0, panel.width, panel.height, 0.35, br[1] * 0.45, br[2] * 0.45, br[3] * 0.45)
end

--- Estilo cuadrado/PALETTE para ISTextEntryBox (2026-08-25, sustituye la
--- texturas externas redondeadas, por el mismo motivo que
--- ya se aplico a los botones - ver drawButtonSurface). Vanilla YA dibuja un
--- rectangulo plano sin redondear por su cuenta (confirmado leyendo
--- ISUI/ISTextEntryBox.lua real del motor) - la unica razon del aspecto
--- redondeado/azulado de antes era la textura que se pintaba encima. Aqui
--- basta con poner los colores correctos; el prerender vanilla (ya cuadrado)
--- hace el resto solo. Foco: vanilla solo sube la opacidad del borde
--- (self.fade) al pasar el raton o enfocar - se añade un borde de acento
--- real (PALETTE.btnActive, el mismo naranja de los botones activos) para
--- que se note de verdad, sin depender de ningun recurso grafico ni
--- caracter de fuente (evita cualquier riesgo de "?" en idiomas sin ese
--- glifo - el propio usuario lo pidio explicitamente).
---@param entry ISTextEntryBox
---@param padAdjust number|nil sin uso (compatibilidad de firma, ver createSearchBox)
function GlobalStorageSiK.SiK_UI.styleTextEntry(entry, padAdjust)
	if not entry or entry._sikUiInputStyled then
		return
	end
	entry._sikUiInputStyled = true
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local bg = pal.btnDefault
	entry.backgroundColor = { r = bg[1] * 0.22, g = bg[2] * 0.22, b = bg[3] * 0.22, a = 0.94 }
	entry.borderColor = { r = pal.border[1], g = pal.border[2], b = pal.border[3], a = 0.9 }
	local origPrerender = entry.prerender
	entry.prerender = function(self)
		if origPrerender then
			origPrerender(self)
		end
		local focused = self:isMouseOver()
			or (self.javaObject and self.javaObject.isFocused and self.javaObject:isFocused())
		if focused then
			local ac = pal.btnActive
			self:drawRectBorder(0, 0, self.width, self.height, 1, ac[1], ac[2], ac[3])
		end
	end
end

--- Estilo cuadrado/PALETTE para ISComboBox (mismo motivo/fecha que
--- styleTextEntry). Igual que el campo de texto, vanilla YA dibuja la caja
--- cerrada como un rectangulo plano sin redondear (confirmado leyendo
--- ISUI/ISComboBox.lua real del motor) - no hace falta redibujar nada,
--- solo poner los colores. backgroundColorMouseOver pasa a ser un color
--- real (PALETTE.tableSelected, el mismo azulado ya usado para filas
--- seleccionadas en el resto del mod) en vez del azul semitransparente por
--- defecto heredado - vanilla reutiliza EXACTAMENTE ese mismo campo tanto
--- para el resaltado de la caja cerrada al pasar el raton como para la fila
--- resaltada del listado desplegado (ISComboBoxPopup:doDrawItem), asi que
--- un solo color queda coherente en los dos sitios sin tocar nada mas. La
--- flecha (self.image, PNG vanilla) se deja intacta a proposito: es un
--- recurso grafico, no un caracter de fuente, cero riesgo de no renderizar
--- en ningun idioma.
---@param combo ISComboBox
---@param padAdjust number|nil sin uso (compatibilidad de firma)
function GlobalStorageSiK.SiK_UI.styleComboBox(combo, padAdjust)
	if not combo or combo._sikUiInputStyled then
		return
	end
	combo._sikUiInputStyled = true
	ensureComboPopupStyled()
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local bg = pal.btnDefault
	combo.backgroundColor = { r = bg[1] * 0.22, g = bg[2] * 0.22, b = bg[3] * 0.22, a = 0.94 }
	combo.borderColor = { r = pal.border[1], g = pal.border[2], b = pal.border[3], a = 0.9 }
	local sel = pal.tableSelected
	combo.backgroundColorMouseOver = { r = sel[1], g = sel[2], b = sel[3], a = sel[4] or 0.35 }
end

--- Crea boton de pestana con subrayado activo SiK UI.
---@param x number
---@param y number
---@param w number
---@param h number
---@param title string
---@param terminal GS_TerminalUI
---@param tabKey string
---@return ISButton
function GlobalStorageSiK.SiK_UI.createTabButton(x, y, w, h, title, terminal, tabKey)
	local btn = ISButton:new(x, y, w, h, title, terminal, function()
		terminal:activateTab(tabKey)
	end)
	btn:initialise()
	btn.tabKey = tabKey
	btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.drawBackground = false
	btn.prerender = function(self)
		local sel = terminal.activeTabKey == self.tabKey
		GlobalStorageSiK.SiK_UI.drawButtonSurface(self, self.width, self.height, {
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

--- Pestana lateral de la columna SiK UI.
---@param x number
---@param y number
---@param w number
---@param h number
---@param title string
---@param terminal GS_TerminalUI
---@param tabKey string
---@return ISButton
function GlobalStorageSiK.SiK_UI.createSideTabButton(x, y, w, h, title, terminal, tabKey)
	local btn = ISButton:new(x, y, w, h, title, terminal, function()
		terminal:activateTab(tabKey)
	end)
	btn:initialise()
	btn.tabKey = tabKey
	btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.drawBackground = false
	btn.prerender = function(self)
		local sel = terminal.activeTabKey == self.tabKey
		GlobalStorageSiK.SiK_UI.drawButtonSurface(self, self.width, self.height, {
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
function GlobalStorageSiK.SiK_UI.getLogoTexture(pixelSize)
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
function GlobalStorageSiK.SiK_UI.drawHeaderLogo(panel, maxHeight)
	local pad = panel.padding or 8
	local tex = GlobalStorageSiK.SiK_UI.getLogoTexture(maxHeight)
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

--- Crea boton de texto SiK UI con superficie plana y etiqueta centrada.
--- El parámetro w es tope máximo de ancho; el ancho real se calcula por el texto.
---@param x number
---@param y number
---@param w number|nil tope máximo de ancho (nil = 360)
---@param h number|nil
---@param title string
---@param target any
---@param onClick function
---@return ISButton
---@param x number
---@param y number
---@param w number
---@param h number
---@param title string
---@param target any
---@param onClick function
---@param activeColor table|nil {r,g,b} 0-1 - color activo alternativo al naranja de PALETTE.btnActive
---@param fullWidth boolean|nil si true, el boton SIEMPRE ocupa el w pasado
---  en vez de encogerse al ancho del texto (botones de accion a fila/tarjeta
---  completa, ver GS_SiK_UI_Core.fitButtonToLabel).
---@param locked boolean|nil si true, el boton se pinta bloqueado (atenuado,
---  sin reaccionar a hover/click) en vez de ocultarse - pedido 2026-08-26:
---  reservar siempre el mismo hueco en vez de mostrar/ocultar el boton segun
---  se cumplan requisitos (evita saltos de layout al cumplirse la condicion).
---  El llamador sigue siendo responsable de poner un :setTooltip() explicando
---  que falta.
function GlobalStorageSiK.SiK_UI.createButton(x, y, w, h, title, target, onClick, activeColor, fullWidth, locked)
	title = title or ""
	locked = locked == true
	if locked then
		onClick = nil
	end
	if GlobalStorageSiK.UIDebug then
		onClick = GlobalStorageSiK.UIDebug.wrapClick("btn:" .. tostring(title), onClick)
	end
	h = h or (FONT_HGT_SMALL + 8)
	local font = UIFont.Small
	local maxW
	if fullWidth and w and w > 0 then
		maxW = w
	else
		w, maxW = GlobalStorageSiK.SiK_UI.resolveButtonWidth(title, w, font)
	end

	local btn = ISButton:new(x, y, w, h, "", target, onClick)
	btn:initialise()
	btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.drawBackground = false
	btn._sikUiLabel = title
	btn._sikUiMaxW = maxW
	btn._sikUiMinW = 52
	btn._sikUiPadH = 20
	btn._sikUiFullWidth = fullWidth == true
	btn._sikUiActiveColor = activeColor
	btn._sikUiLocked = locked
	btn:setTitle("")
	btn.font = font
	btn.prerender = function(self)
		local label = self._sikUiLabel or self.title or ""
		if label ~= self._sikUiLabel then
			self._sikUiLabel = label
		end
		GlobalStorageSiK.SiK_UI.fitButtonToLabel(self)
		GlobalStorageSiK.SiK_UI.drawButtonSurface(self, self.width, self.height, {
			pressed = self.pressed,
			hover = self:isMouseOver(),
			active = (self._sikUiActive == true) or (self._sikUiActiveColor ~= nil),
			activeColor = self._sikUiActiveColor,
			locked = self._sikUiLocked,
		})
		-- ISButton:updateTooltip() (el disparador REAL del tooltip, ver
		-- ISUI/ISButton.lua:316) solo se llama desde el prerender VANILLA -
		-- al sustituir prerender entero aqui, ese aviso nunca llegaba a
		-- correr y ningun :setTooltip() de ningun boton creado con
		-- createButton se mostraba nunca en juego, aunque el campo
		-- self.tooltip estuviera bien puesto (bug real reportado por el
		-- usuario, "los ? no muestran ningun tooltip" - la causa real tenia
		-- DOS partes, no solo el metodo equivocado usado para fijar el texto).
		self:updateTooltip()
	end
	btn.render = function(self)
		local font = self.font or UIFont.Small
		local th = getTextManager():getFontHeight(font)
		local r, g, b = 0.92, 0.94, 0.96
		if self._sikUiLocked then
			local m = GlobalStorageSiK.SiK_UI.PALETTE.textMuted
			r, g, b = m[1], m[2], m[3]
		elseif self.textColor then
			r, g, b = self.textColor.r or r, self.textColor.g or g, self.textColor.b or b
		end
		local label = self._sikUiLabel or self.title or ""
		if label ~= "" then
			local pad = 6
			if getTextManager():MeasureStringX(font, label) > self.width - pad * 2 then
				label = GlobalStorageSiK.SiK_UI.truncateText(label, self.width - pad * 2, font)
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
function GlobalStorageSiK.SiK_UI.createSearchBox(x, y, w, h, parentPanel, onTextChange)
	local box = ISPanel:new(x, y, w, h)
	box:initialise()
	box.drawBackground = false
	box.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	box.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	box.padding = 4
	-- La lupa funcional vive fuera del campo, en GS_TerminalUI.lua. Sustituye al
	-- antiguo boton textual Buscar y conserva GS_TerminalUI:onSearch. Este campo
	-- no dibuja una segunda lupa decorativa para evitar dos controles visualmente
	-- identicos con comportamientos distintos.
	local entryX = 0
	local entryW = w
	local entry = ISTextEntryBox:new("", entryX, 0, entryW, h)
	entry:initialise()
	entry.font = UIFont.Small
	GlobalStorageSiK.SiK_UI.styleTextEntry(entry, box.padding / 2)
	entry:instantiate()
	if onTextChange then
		entry.onTextChange = onTextChange
	end
	box:addChild(entry)
	local clearSize = math.floor(h * 0.6)
	local clearIcon = GlobalStorageSiK.SiK_UI.getIconTexture("close")
	local clearBtn = GlobalStorageSiK.SiK_UI.createIconButton(
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

--- Reposiciona los hijos del cuadro de busqueda SiK UI tras resize.
---@param box ISPanel|nil
---@param w number
---@param h number
function GlobalStorageSiK.SiK_UI.layoutSearchBox(box, w, h)
	if not box then
		return
	end
	box:setWidth(w)
	box:setHeight(h)
	local entry = box.searchEntry
	local entryX = 0
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

-- Reserva propia para botones cuadrados con icono. ISButton conserva el
-- contrato probado de onMouseDown/onMouseUp, captura, cancelacion al soltar
-- fuera y callback target+funcion; aqui solo sustituimos su dibujo y
-- exponemos el contrato comun de icono, tooltip y estado.
local function createFallbackIconButton(x, y, size, iconTexture, target, onClick)
	local btn = ISButton:new(x, y, size, size, "", target, onClick)
	btn:initialise()
	btn:setTitle("")
	btn.drawBackground = false
	btn.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	btn.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	btn._gsIcon = iconTexture
	btn._gsActive = false
	btn._gsActiveColor = nil
	btn.setIcon = function(self, texture)
		self._gsIcon = texture
	end
	btn.setActive = function(self, active)
		self._gsActive = active == true
	end
	btn.setActiveColor = function(self, r, g, b)
		self._gsActiveColor = { r, g, b }
	end
	btn.prerender = function(self)
		GlobalStorageSiK.SiK_UI.drawButtonSurface(self, self.width, self.height, {
			pressed = self.pressed,
			hover = self:isMouseOver(),
			active = self._gsActive,
			activeColor = self._gsActiveColor,
		})
		self:updateTooltip()
	end
	btn.render = function(self)
		local icon = self._gsIcon
		if not icon then
			return
		end
		local inset = math.max(2, math.floor(math.min(self.width, self.height) * 0.16))
		local iconW = math.max(1, self.width - inset * 2)
		local iconH = math.max(1, self.height - inset * 2)
		self:drawTextureScaledAspect(icon, inset, inset, iconW, iconH, 1, 1, 1, 1)
	end
	return btn
end

--- Crea boton cuadrado con icono mediante el proveedor propio SiK_UI.
--- La implementacion y la interaccion pertenecen por completo a SiK UI.
---@param x number
---@param y number
---@param size number
---@param iconTexture userdata|nil
---@param target any
---@param onClick function
---@return ISButton|nil
function GlobalStorageSiK.SiK_UI.createIconButton(x, y, size, iconTexture, target, onClick)
	return createFallbackIconButton(x, y, size, iconTexture, target, onClick)
end

--- Crea interruptor compartido con el check propio de SiK_UI.
---@param x number
---@param y number
---@param size number
---@param checked boolean
---@param target any
---@param onToggle function|nil callback(checked)
---@return ISButton|nil
function GlobalStorageSiK.SiK_UI.createToggle(x, y, size, checked, target, onToggle)
	local iconOn = GlobalStorageSiK.SiK_UI.getIconTexture("check")
	local btn
	btn = GlobalStorageSiK.SiK_UI.createIconButton(
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

--- Crea boton cerrar con el icono propio SiK_UI.
---@param parent ISUIElement
---@param target any
---@param onClose function
---@param size number|nil
---@return ISButton
function GlobalStorageSiK.SiK_UI.createCloseButton(parent, target, onClose, size)
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
	local closeIcon = GlobalStorageSiK.SiK_UI.getIconTexture("close")
	local btn = GlobalStorageSiK.SiK_UI.createIconButton(-1000, -1000, closeSize, closeIcon, target, onClose)
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
	btn.prerender = function(self)
		GlobalStorageSiK.SiK_UI.drawButtonSurface(self, self.width, self.height, {
			pressed = self.pressed,
			hover = self:isMouseOver(),
			active = true,
		}, 0, 0)
	end
	parent:addChild(btn)
	parent.closeBtn = btn
	return btn
end

--- Crea el panel de peso/capacidad SiK UI.
---@param x number
---@param y number
---@param w number
---@param h number|nil
---@return ISPanel
function GlobalStorageSiK.SiK_UI.createWeightBarPanel(x, y, w, h)
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
			fr, fg, fb = GlobalStorageSiK.SiK_UI.getBarColor(fill)
		end
		GlobalStorageSiK.SiK_UI.drawProgressBar(b, 0, 0, b.width, b.height, fill, fr, fg, fb)
	end
	return bar
end

--- Dibuja el fondo SiK UI del panel principal.
---@param panel ISPanel
function GlobalStorageSiK.SiK_UI.renderMainBackground(panel)
	GlobalStorageSiK.SiK_UI.renderPanelBackground(panel)
end

--- Fondo oscuro plano del panel principal, sin nine-patch externo.
---@param panel ISPanel
function GlobalStorageSiK.SiK_UI.renderPanelBackground(panel)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local headerH = panel.headerHeight or 0
	local bodyH = math.max(0, panel.height - headerH)
	panel:drawRect(0, headerH, panel.width, bodyH, 0.96, pal.bgBody[1], pal.bgBody[2], pal.bgBody[3])
	panel:drawRect(0, 0, panel.width, headerH, 0.98, pal.bgHeader[1], pal.bgHeader[2], pal.bgHeader[3])
	panel:drawRect(0, headerH - 1, panel.width, 1, 1, 0, 0, 0)
	panel:drawRect(0, headerH, panel.width, 1, 0.45, pal.accentLine[1], pal.accentLine[2], pal.accentLine[3])
end

--- Cabecera de la ventana bloqueada (texto blanco, icono GS opcional).
---@param panel ISPanel
function GlobalStorageSiK.SiK_UI.renderBlockedHeader(panel)
	local iconSize = math.max(20, math.min(28, panel.headerHeight - 10))
	local textX = GlobalStorageSiK.SiK_UI.drawHeaderLogo(panel, iconSize)
	local titleY = math.floor((panel.headerHeight - getTextManager():getFontHeight(UIFont.Medium)) / 2)
	panel:drawText(T("IGUI_GS_BlockedTitle"), textX, titleY, 1, 1, 1, 1, UIFont.Medium)
end

--- Dibuja la cabecera SiK UI con icono GS y titulo legible.
---@param panel GS_TerminalUI
function GlobalStorageSiK.SiK_UI.renderHeader(panel)
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
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	panel:drawText(verText, verX, verY, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 0.55, verFont)
end

--- Dibuja barra de estado inferior en pestaña Red.
---@param panel GS_TerminalUI
---@param state table|nil
function GlobalStorageSiK.SiK_UI.renderStatusFooter(panel, state)
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
function GlobalStorageSiK.SiK_UI.setupHeaderDrag(panel)
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
--- Cuenta caracteres UTF-8 reales (no bytes) de un string - cada caracter
--- chino/CJK ocupa 3 bytes en UTF-8, asi que usar #text (longitud en BYTES)
--- como si fueran caracteres es incorrecto para cualquier idioma no-ASCII.
--- BUG REAL DE ARQUITECTURA cerrado (2026-08-26, revision tecnica de
--- Desarrollo tras el banco CJK de DEV15): esta funcion trataba `#str`/
--- `string.byte` como bytes UTF-8 - en Kahlua/PZ las cadenas son unidades
--- UTF-16 (java.lang.String), asi que para el BMP (chino/japones/coreano
--- comun) cada unidad ya es un caracter completo (contaba bien por
--- coincidencia), pero un caracter fuera del BMP (par subrogado, 2 unidades)
--- se contaba como 2 caracteres en vez de 1. Delega ahora en
--- GlobalStorageSiK.Libs.unicodeLength (cuenta caracteres Unicode reales,
--- combinando pares subrogados). "wide" (algun caracter que necesita mas
--- ancho visual - acentos latinos SIEMPRE quedan por debajo de U+0800,
--- chino/japones/coreano y cualquier caracter fuera del BMP SIEMPRE por
--- encima) distingue CJK de "occidental con acentos" sin necesitar detectar
--- el idioma de la UI ni mantener una lista de idiomas - el umbral U+0800
--- conserva la misma frontera semantica que ya tenia el chequeo de bytes
--- anterior, aplicada ahora al punto de codigo real en vez de al byte.
---@param str string
---@return number length
---@return boolean wide
local function unicodeCharLengthAndWidth(str)
	local wide = false
	for i = 1, #str do
		if string.byte(str, i) >= 0x0800 then
			wide = true
			break
		end
	end
	return GlobalStorageSiK.Libs.unicodeLength(str), wide
end

function GlobalStorageSiK.SiK_UI.bindSearchEntry(panel, searchEntry)
	if not searchEntry then
		return
	end
	if searchEntry.setPlaceholderText then
		searchEntry:setPlaceholderText(T("IGUI_GS_SearchPlaceholder"))
	end

	-- Se mantiene en 3, pero medido en CARACTERES UNICODE REALES (unicodeCharLengthAndWidth),
	-- no en bytes como antes - ese es el bug real que se corrige aqui, no el
	-- numero en si. Con el bug (#text = bytes), un solo caracter chino (3
	-- bytes) ya colaba el umbral de "3" por accidente; con el fix, "3" es
	-- ahora 3 caracteres de verdad en CUALQUIER alfabeto (chino incluido),
	-- igual de estricto para todos los idiomas en vez de una coincidencia.
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
		local charCount, wide = unicodeCharLengthAndWidth(text)
		-- FASE DEV busqueda en idiomas no-ASCII (2026-08-17, feedback comunidad
		-- china: "buscar en chino no da ninguna reaccion"): traza gateada por
		-- Modo Debug (sandbox) del texto recibido crudo en bytes y en
		-- caracteres UTF-8 reales - unica forma de saber, sin poder probar
		-- nosotros mismos con IME chino, si el cuadro de texto SIQUIERA recibe
		-- los caracteres compuestos por el IME antes de sospechar del resto de
		-- la cadena de busqueda (filtro/lower/etc, ya revisados y blindados).
		if GlobalStorageSiK.Log then
			GlobalStorageSiK.Log.debug("SiKUISearch", "onTextChange bytes=" .. tostring(#text)
				.. " chars=" .. tostring(charCount) .. " wide=" .. tostring(wide) .. " text=" .. tostring(text))
		end
		-- CJK (chino/japones/coreano, pedido explicito): palabras de 1-2
		-- caracteres son la norma, un umbral de 3 caracteres reales sigue
		-- siendo demasiado exigente pese al fix de bytes->caracteres de
		-- arriba. "wide" (algun caracter de 3+ bytes UTF-8) distingue CJK de
		-- acentos latinos (siempre 2 bytes) sin depender del idioma de la UI.
		local minChars = wide and 2 or SEARCH_MIN_CHARS
		-- Compensacion empirica de un desfase de una pulsacion (reportado
		-- 2026-08-18: "empieza a buscar en el 4º caracter, no en el 3º" -
		-- osea, con minChars=3 la busqueda no arrancaba hasta charCount=4).
		-- Sin poder probarlo en vivo no se puede confirmar la causa exacta
		-- dentro del motor (sospecha: onTextChange se dispara con el texto
		-- DE ANTES de aplicar la pulsacion que lo disparo, no con el ya
		-- actualizado), pero el efecto observado es reproducible y
		-- consistente - se compensa aqui restando 1 al umbral efectivo en
		-- vez de dejar el gate a ciegas del texto que reporte el motor.
		if text == "" or charCount < minChars - 1 then
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

--- Trocea un string en su lista de caracteres Unicode reales, sin partir
--- nunca un par subrogado por la mitad. BUG REAL DE ARQUITECTURA cerrado
--- (2026-08-26, revision tecnica de Desarrollo tras el banco CJK de DEV15):
--- la version anterior trataba las unidades UTF-16 subyacentes (ver
--- GS_Libs.unicodeCodepoints para el analisis completo) como bytes lider
--- UTF-8, agrupando 3-4 unidades CJK reales en un solo "caracter" falso -
--- NO se puede usar la libreria "utf8" de Lua 5.3+, Kahlua (el interprete
--- que usa PZ) no la expone (mismo tipo de suposicion equivocada que ya
--- causo el bug real de next() en GS_Addons.lua: nunca dar por hecho que
--- existe una funcion de stdlib sin comprobarlo primero) - manual, unidad a
--- unidad, agrupando solo pares subrogados reales via isLowSurrogateAt.
---@param str string
---@return string[]
local function unicodeChars(str)
	local chars = {}
	local i = 1
	local len = #str
	while i <= len do
		local charLen = 1
		if GlobalStorageSiK.Libs.isLowSurrogateAt(str, i + 1) then
			local unit = string.byte(str, i)
			if unit >= 0xD800 and unit <= 0xDBFF then
				charLen = 2
			end
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
	local chars = unicodeChars(token)
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
function GlobalStorageSiK.SiK_UI.wrapTextLines(text, maxWidth, font)
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
function GlobalStorageSiK.SiK_UI.countWrappedLines(text, maxWidth, font, lineGap)
	local fontH = getTextManager():getFontHeight(font or UIFont.Small)
	local gap = lineGap or 3
	local n = #GlobalStorageSiK.SiK_UI.wrapTextLines(text, maxWidth, font)
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
function GlobalStorageSiK.SiK_UI.addRequirementLine(parent, x, y, w, iconFullType, text, ok)
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
	for _, line in ipairs(GlobalStorageSiK.SiK_UI.wrapTextLines(text, textW, UIFont.Small)) do
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
function GlobalStorageSiK.SiK_UI.makeMousePassthrough(widget)
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
function GlobalStorageSiK.SiK_UI.setMouseTransparentAll(widgets)
	if not widgets then
		return
	end
	for i = 1, #widgets do
		GlobalStorageSiK.SiK_UI.makeMousePassthrough(widgets[i])
	end
end

--- Eleva solo controles interactivos (sin tocar el panel raíz ni UIManager).
---@param widgets ISUIElement[]
function GlobalStorageSiK.SiK_UI.raiseModalControls(widgets)
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
function GlobalStorageSiK.SiK_UI.layoutModalFrame(panel, pad)
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
function GlobalStorageSiK.SiK_UI.setupModalPanel(panel, onClose, pad)
	pad = pad or 14
	panel.padding = pad
	panel.moveWithMouse = false
	GlobalStorageSiK.SiK_UI.setupHeaderDrag(panel)
	GlobalStorageSiK.SiK_UI.createCloseButton(panel, panel, onClose)
	GlobalStorageSiK.SiK_UI.layoutModalFrame(panel, pad)
	-- Contrato común: Escape cierra cualquier modal SiK UI sin que cada
	-- ventana tenga que registrar su propia variante. Se conserva un handler
	-- previo para no interferir con controles especializados.
	if not panel._sikEscapeInstalled then
		panel._sikEscapeInstalled = true
		local previous = panel.onKeyRelease
		panel.onKeyRelease = function(self, key)
			local escapeKey = Keyboard and Keyboard.KEY_ESCAPE or 1
			if key == escapeKey then
				if onClose then onClose() end
				return true
			end
			if previous then return previous(self, key) end
			return false
		end
	end
end

--- Ancho estandar para modales de edicion/confirmacion pequeños (fila de
--- miembro, nodo, renombrar, etc.) - apaisado (mas ancho que alto), en vez
--- de que cada ventana invente su propio ancho fijo distinto. La ALTURA
--- nunca es un numero fijo adivinado: se calcula siempre desde el contenido
--- real (wrapTextLines + suma de alturas reales de cada fila) y luego se
--- centra con centerModal. Ver GS_TerminalUI_MemberEditor.lua como
--- referencia de uso; migrar el resto de modales pequeños a este mismo
--- estandar es trabajo pendiente, no se ha tocado en este cambio.
GlobalStorageSiK.SiK_UI.STANDARD_MODAL_W = 460

--- Centra un panel modal ya dimensionado (llamar DESPUES de fijar su alto
--- real por contenido, nunca antes) en el centro de la pantalla actual.
---@param panel ISPanel|nil
function GlobalStorageSiK.SiK_UI.centerModal(panel)
	if not panel then
		return
	end
	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	panel:setX(math.floor((sw - panel.width) / 2))
	panel:setY(math.floor((sh - panel.height) / 2))
end

--- Minimos compartidos por las ventanas de editor GRANDES y redimensionables
--- del terminal (contenedor, zona) - dev26 ronda 4: antes cada una tenia su
--- propio criterio de tamano/redimensionado (NodeEditor con formula propia y
--- resizable=true, ZoneEditor con ancho fijo STANDARD_MODAL_W y alto
--- calculado del contenido, sin redimensionar) y el usuario pidio
--- coherencia real entre ambas para poder seguir trabajando encima. Un unico
--- criterio compartido aqui evita que vuelvan a divergir en el futuro.
GlobalStorageSiK.SiK_UI.EDITOR_MIN_W = 560
GlobalStorageSiK.SiK_UI.EDITOR_MIN_H = 480

--- Tamano inicial recomendado para una ventana de editor grande, en
--- proporcion a la pantalla actual (el jugador puede redimensionarla despues
--- con el asa de la esquina).
---@return number w, number h
function GlobalStorageSiK.SiK_UI.resolveEditorWindowSize()
	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	local w = math.min(760, math.max(GlobalStorageSiK.SiK_UI.EDITOR_MIN_W, sw * 0.5))
	local h = math.min(820, math.max(GlobalStorageSiK.SiK_UI.EDITOR_MIN_H, sh * 0.72))
	return w, h
end

--- Posicion inicial de una ventana de editor grande: superpuesta sobre el
--- terminal si esta disponible (para no tapar personaje/inventario con la
--- pantalla completa), centrada en pantalla si no - siempre recortada a los
--- bordes visibles.
---@param terminal table|nil
---@param w number
---@param h number
---@return number x, number y
function GlobalStorageSiK.SiK_UI.resolveEditorWindowPos(terminal, w, h)
	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	local x, y
	if terminal and terminal.getX and terminal.getY and terminal.getWidth and terminal.getHeight then
		x = terminal:getX() + (terminal:getWidth() - w) / 2
		y = terminal:getY() + (terminal:getHeight() - h) / 2
	else
		x = (sw - w) / 2
		y = (sh - h) / 2
	end
	x = math.floor(math.max(0, math.min(x, sw - w)))
	y = math.floor(math.max(0, math.min(y, sh - h)))
	return x, y
end

--- Muestra modal encima del resto de UI (una sola vez al abrir).
---@param panel ISPanel|nil
function GlobalStorageSiK.SiK_UI.finalizeModalShow(panel)
	if not panel then
		return
	end
	GlobalStorageSiK.SiK_UI.layoutModalFrame(panel, panel.padding)
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
function GlobalStorageSiK.SiK_UI.bringModalControlsToFront(panel, widgets)
	GlobalStorageSiK.SiK_UI.raiseModalControls(widgets)
end

--- Crea panel de fondo tipo "tarjeta" para un bloque de sección.
--- Debe añadirse al scroll ANTES que los demás hijos del bloque (se renderiza debajo).
---@param x number
---@param y number
---@param w number
---@param h number
---@return ISPanel
---@param x number
---@param y number
---@param w number
---@param h number
---@param accentColor table|nil {r,g,b} 0-1 - franja izquierda; por defecto PALETTE.btnActive (naranja, comportamiento previo sin cambios)
---@return ISPanel
function GlobalStorageSiK.SiK_UI.createSectionCard(x, y, w, h, accentColor)
	local card = ISPanel:new(x, y, w, math.max(24, h))
	card:initialise()
	card.drawBackground = false
	card.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	card._gsAccent = accentColor
	card.prerender = function(self)
		ISPanel.prerender(self)
		local p = GlobalStorageSiK.SiK_UI.PALETTE
		local ac = self._gsAccent or p.btnActive
		self:drawRect(0, 0, self.width, self.height,
			0.46, p.bgBody[1] * 0.72, p.bgBody[2] * 0.72, p.bgBody[3] * 0.78)
		self:drawRect(0, 0, 3, self.height,
			0.75, ac[1], ac[2], ac[3])
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
function GlobalStorageSiK.SiK_UI.resizeSectionCard(card, x, y, w, h)
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
function GlobalStorageSiK.SiK_UI.createStatusIndicatorRow(x, y, w, h)
	h = h or (FONT_HGT_SMALL + 4)
	local row = ISPanel:new(x, y, w, h)
	row:initialise()
	row.drawBackground = false
	row.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	row._gsStatus = "ok"
	row._gsText   = ""
	row.prerender = function(self)
		ISPanel.prerender(self)
		local p = GlobalStorageSiK.SiK_UI.PALETTE
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
function GlobalStorageSiK.SiK_UI.setStatusIndicatorRow(row, text, status, maxW)
	if not row then return end
	if maxW and maxW > 20 then
		text = GlobalStorageSiK.SiK_UI.truncateText(text or "", maxW - 16, UIFont.Small)
	end
	row._gsText   = text   or ""
	row._gsStatus = status or "ok"
end

--- Aplica estilo de botón peligroso (rojo oscuro) usando PALETTE.
---@param btn ISButton|nil
function GlobalStorageSiK.SiK_UI.applyDangerButton(btn)
	if not btn then return end
	local p = GlobalStorageSiK.SiK_UI.PALETTE
	btn.borderColor      = { r = p.dangerBorder[1], g = p.dangerBorder[2], b = p.dangerBorder[3], a = 0.9 }
	btn.backgroundColor  = { r = p.dangerBg[1],     g = p.dangerBg[2],     b = p.dangerBg[3],     a = 0.92 }
	btn.backgroundColorHL = { r = p.dangerHover[1],  g = p.dangerHover[2],  b = p.dangerHover[3],  a = 1 }
end

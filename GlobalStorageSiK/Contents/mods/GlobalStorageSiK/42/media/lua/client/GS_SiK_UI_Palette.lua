--[[
	GlobalStorageSiK - Paletas locales SiK UI
	Solo cambia colores neutrales. Estados y operadores conservan significado.
]]

require "GS_SiK_UI_Core"
require "ISUI/ISComboBox"
require "ISUI/ISPanel"

GlobalStorageSiK.SiK_UI.Palette = GlobalStorageSiK.SiK_UI.Palette or {}

local Palette = GlobalStorageSiK.SiK_UI.Palette
local PREF_KEY = "GSSiK_UIPalette"
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

Palette.DEFINITIONS = {
	{ key = "graphite", titleKey = "IGUI_GS_UIPaletteGraphite", tint = { 1.00, 1.00, 1.00 } },
	{ key = "blue", titleKey = "IGUI_GS_UIPaletteBlue", tint = { 0.82, 0.94, 1.08 } },
	{ key = "purple", titleKey = "IGUI_GS_UIPalettePurple", tint = { 0.98, 0.86, 1.08 } },
	{ key = "green", titleKey = "IGUI_GS_UIPaletteGreen", tint = { 0.84, 1.04, 0.94 } },
	{ key = "wine", titleKey = "IGUI_GS_UIPaletteWine", tint = { 1.08, 0.86, 0.86 } },
	{ key = "amber", titleKey = "IGUI_GS_UIPaletteAmber", tint = { 1.06, 1.00, 0.82 } },
}

local BASE_NEUTRAL = {
	bgHeader = { 0.06, 0.06, 0.06 }, bgBody = { 0.12, 0.12, 0.12 },
	bgCard = { 0.10, 0.10, 0.10, 0.85 }, btnDefault = { 0.2, 0.2, 0.2 },
	btnHover = { 0.3, 0.3, 0.3 }, btnPressed = { 0.1, 0.1, 0.1 },
	border = { 0.4, 0.4, 0.4 }, textPrimary = { 0.92, 0.94, 0.96 },
	textSecondary = { 0.75, 0.78, 0.82 }, textMuted = { 0.58, 0.62, 0.66 },
	accentLine = { 0.28, 0.28, 0.28 }, tableStripeA = { 0.10, 0.10, 0.10, 0.50 },
	tableStripeB = { 0.08, 0.08, 0.08, 0.30 }, tableHover = { 0.15, 0.15, 0.15, 0.40 },
	tableSelected = { 0.22, 0.32, 0.45, 0.35 }, zoneHeader = { 0.14, 0.16, 0.20, 0.80 },
	zoneHeaderHover = { 0.22, 0.28, 0.35, 0.45 }, cardBg = { 0.06, 0.06, 0.08 },
	divider = { 0.18, 0.18, 0.22 },
}

local function definitionByKey(key)
	for i = 1, #Palette.DEFINITIONS do
		if Palette.DEFINITIONS[i].key == key then return Palette.DEFINITIONS[i], i end
	end
	return Palette.DEFINITIONS[1], 1
end

local function tinted(source, tint)
	local out = {}
	for i = 1, #source do
		if i <= 3 then
			out[i] = math.max(0, math.min(1, source[i] * tint[i]))
		else
			out[i] = source[i]
		end
	end
	return out
end

local function copyColor(target, source)
	for i = 1, #source do target[i] = source[i] end
	for i = #source + 1, #target do target[i] = nil end
end

function Palette.getActiveKey()
	return Palette._activeKey or "graphite"
end

--- Actualiza en sitio para que closures/widgets que guardaron PALETTE sigan
--- leyendo el mismo objeto. No se tocan status*, rule*, danger* ni btnActive.
function Palette.apply(key)
	local def = definitionByKey(key)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	for name, base in pairs(BASE_NEUTRAL) do
		pal[name] = pal[name] or {}
		copyColor(pal[name], tinted(base, def.tint))
	end
	Palette._activeKey = def.key
	return def.key
end

function Palette.load(player)
	local key = "graphite"
	if player and player.getModData then
		local md = player:getModData()
		key = type(md[PREF_KEY]) == "string" and md[PREF_KEY] or key
	end
	return Palette.apply(key)
end

function Palette.save(player, key)
	key = Palette.apply(key)
	if player and player.getModData then
		-- Preferencia visual local: deliberadamente no transmitModData().
		player:getModData()[PREF_KEY] = key
	end
	return key
end

--- Reaplica colores almacenados por widgets vanilla y deja los paneles
--- transparentes intactos. Las superficies SiK UI leen PALETTE al dibujar.
function Palette.refreshTree(root)
	if not root then return end
	local children = root.childrenInOrder
	if root._sikUiInputStyled then
		root._sikUiInputStyled = nil
		if root.options then
			GlobalStorageSiK.SiK_UI.styleComboBox(root)
		elseif root.getText then
			GlobalStorageSiK.SiK_UI.styleTextEntry(root)
		end
	end
	if type(children) == "table" then
		for i = 1, #children do Palette.refreshTree(children[i]) end
	end
end

-- dev40 (pedido explicito del usuario, captura real: "es feisimo... no esta
-- bien construido ni es consistente con los tamaños y estilo que hemos
-- estado trabajando"): quitadas las 5 tiras de muestra de color junto al
-- combo - no hay ningun otro sitio del mod con ese patron ("etiqueta + campo
-- + tiras de color"), asi que desentonaba. Simplificado a exactamente el
-- mismo patron "etiqueta arriba + campo ancho completo debajo" que ya usan
-- los demas selectores del terminal (createSectionLabel + combo).
local LABEL_GAP = 4

--- Selector simple: etiqueta arriba, combo de ancho completo debajo.
function Palette.createSelector(x, y, w, player, onChanged)
	w = math.max(200, tonumber(w) or 260)
	local labelH = FONT_HGT_SMALL
	local comboH = 26
	local panel = ISPanel:new(x, y, w, labelH + LABEL_GAP + comboH)
	panel:initialise()
	panel.drawBackground = false
	panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	panel._sikPaletteSelector = true
	panel.player = player
	panel.label = GlobalStorageSiK.SiK_UI.createSectionLabel(0, 0, GlobalStorageSiK.I18n.text("IGUI_GS_UIPaletteLabel"))
	panel:addChild(panel.label)
	panel.combo = ISComboBox:new(0, labelH + LABEL_GAP, w, comboH, panel, function(target)
		if target._rebuilding then return end
		local def = Palette.DEFINITIONS[target.combo.selected or 1]
		Palette.save(target.player, def and def.key or "graphite")
		Palette.refreshTree(GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance)
		if onChanged then onChanged(def and def.key or "graphite") end
	end)
	panel.combo:initialise()
	GlobalStorageSiK.SiK_UI.styleComboBox(panel.combo)
	panel:addChild(panel.combo)
	panel._rebuilding = true
	local _, selected = definitionByKey(Palette.getActiveKey())
	for i = 1, #Palette.DEFINITIONS do
		panel.combo:addOption(GlobalStorageSiK.I18n.text(Palette.DEFINITIONS[i].titleKey))
	end
	panel.combo.selected = selected
	panel._rebuilding = nil
	return panel
end

function Palette.layoutSelector(panel, width)
	if not panel or not panel._sikPaletteSelector then return end
	local w = math.max(200, tonumber(width) or panel.width or 260)
	panel:setWidth(w)
	if panel.combo then panel.combo:setWidth(w) end
end

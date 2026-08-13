--[[

	GlobalStorageSiK - Bahía de slots de addons (terminal)

	Autor: SiK

	Fecha: 2025-06-27

	Descripción: Ranuras con borde rojo/verde; ancho dinámico según etiqueta.

]]



require "ISUI/ISPanel"

require "GS_I18n"

require "GS_AddonRegistry"

require "GS_TerminalUI_Scroll"

require "GS_AddonManageUI"



GlobalStorageSiK.TerminalAddonBay = GlobalStorageSiK.TerminalAddonBay or {}

--- Disquete vacío: se muestra mientras el addon no está instalado.
local FLOPPY_ICON_PATH = "media/textures/Item_GS_FloppyDisk_Blank.png"



local T = GlobalStorageSiK.I18n.text

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

local SLOT_GAP = 16

local SLOT_MIN = 72

local SLOT_FIXED = 88

local ICON_PAD = 10

local LABEL_H = FONT_HGT_SMALL + 6



---@param def table

---@param ctx table

---@return number r,g,b,a

local function slotBorderColor(def, ctx)

	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	if not GlobalStorageSiK.AddonRegistry.isModActive(def.id) then

		return pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 0.7

	end

	if ctx.installed and ctx.installed[def.id] then

		return pal.statusOk[1], pal.statusOk[2], pal.statusOk[3], 1

	end

	return pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 0.5

end



--- Calcula ancho de ranura según etiquetas y espacio disponible.

---@param defs table[]

---@param availW number

---@return number slotW, number rowW

local function measureBayLayout(defs, availW)

	local count = #defs

	if count <= 0 then

		return SLOT_MIN, 0

	end

	local tm = getTextManager()

	local maxLabelW = 0

	for i = 1, count do

		local label = T(defs[i].titleKey or "IGUI_GS_AddonUnknown")

		maxLabelW = math.max(maxLabelW, tm:MeasureStringX(UIFont.Small, label))

	end

	local minSlotW = math.max(SLOT_MIN, maxLabelW + 14)

	local slotW = minSlotW > SLOT_FIXED and minSlotW or SLOT_FIXED

	local rowW = count * slotW + (count - 1) * SLOT_GAP

	return slotW, rowW

end



---@param scroll ISPanel

---@param x number

---@param y number

---@param innerW number

---@param defs table[]

---@param ctx table

---@return number

function GlobalStorageSiK.TerminalAddonBay.addBay(scroll, x, y, innerW, defs, ctx)

	local count = #defs

	if count <= 0 then

		return y

	end

	local availW = math.max(SLOT_MIN, innerW - x * 2)

	local slotW, rowW = measureBayLayout(defs, availW)

	local slotH = slotW

	local rowH = slotH + LABEL_H + 4

	local host = ISPanel:new(x, y, rowW, rowH)

	host:initialise()

	host.drawBackground = false

	host.defs = defs

	host.ctx = ctx

	host.slotW = slotW

	host.slotH = slotH

	host.prerender = function(panel)

		ISPanel.prerender(panel)

		local defsLocal = panel.defs or {}

		local ctxLocal = panel.ctx or {}

		local sw = panel.slotW or SLOT_MIN

		local sh = panel.slotH or sw

		local slotX = 0

		for i = 1, #defsLocal do

			local def = defsLocal[i]

			local br, bg, bb, ba = slotBorderColor(def, ctxLocal)

			panel:drawRect(slotX, 0, sw, sh, 0.96, 0.05, 0.05, 0.05)

			panel:drawRectBorder(slotX, 0, sw, sh, ba, br, bg, bb)

			local isInstalled = ctxLocal.installed and ctxLocal.installed[def.id] ~= nil

			local pad = ICON_PAD

			if isInstalled then

				-- Icono REAL del periferico (ver iconPath en el registro de
				-- cada addon, p.ej. Item_GS_WifiAntenna.png) - antes un mapa
				-- aparte aqui lo sobrescribia con el icono de pestaña
				-- estilizado, por eso nunca se veia el periferico real.
				local iconPath = def.iconPath

				local tex = iconPath and getTexture(iconPath) or nil

				if tex then

					panel:drawTextureScaledAspect(tex, slotX + pad, pad, sw - pad * 2, sh - pad * 2, 1, 1, 1, 1)

				else

					local _fp = GlobalStorageSiK.TerminalChrome.PALETTE
					panel:drawText("?", slotX + sw / 2 - 4, sh / 2 - 8, _fp.textMuted[1], _fp.textMuted[2], _fp.textMuted[3], 1, UIFont.Small)

				end

			else

				local floppyTex = getTexture(FLOPPY_ICON_PATH)

				if floppyTex then

					panel:drawTextureScaledAspect(floppyTex, slotX + pad, pad, sw - pad * 2, sh - pad * 2, 0.5, 0.6, 0.6, 0.6)

				end

			end

			local label = T(def.titleKey or "IGUI_GS_AddonUnknown")

			local tw = getTextManager():MeasureStringX(UIFont.Small, label)

			local _lp = GlobalStorageSiK.TerminalChrome.PALETTE
			panel:drawText(label, slotX + math.floor((sw - tw) / 2), sh + 2, _lp.textSecondary[1], _lp.textSecondary[2], _lp.textSecondary[3], 1, UIFont.Small)

			slotX = slotX + sw + SLOT_GAP

		end

	end

	-- Clic en una ranura abre la ventana de gestion de ese addon (ver
	-- GS_AddonManageUI.lua) - antes la bahia era puramente visual, sin
	-- ninguna interaccion (reportado: los botones instalar/retirar solo
	-- vivian en el bloque apilado de abajo, ahora retirado).
	host.onMouseDown = function(panel, mx, my)
		local defsLocal = panel.defs or {}
		local ctxLocal = panel.ctx or {}
		local sw = panel.slotW or SLOT_MIN
		local slotX = 0
		for i = 1, #defsLocal do
			if mx >= slotX and mx < slotX + sw and my >= 0 and my < (panel.slotH or sw) then
				local def = defsLocal[i]
				if def and GlobalStorageSiK.AddonRegistry.isModActive(def.id) then
					GlobalStorageSiK.AddonManageUI.show(def.id, ctxLocal.networkId, ctxLocal.anchor, ctxLocal.terminal, ctxLocal.installed)
				end
				return true
			end
			slotX = slotX + sw + SLOT_GAP
		end
		return false
	end

	GlobalStorageSiK.TerminalScroll.addChild(scroll, host)

	return y + rowH + 8

end



---@param defCount number

---@return number

function GlobalStorageSiK.TerminalAddonBay.measureHeight(defCount)

	if defCount <= 0 then

		return 0

	end

	return SLOT_MIN + LABEL_H + 18

end


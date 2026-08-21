--[[
	GlobalStorageSiK - Pestaña Programación del terminal
	Autor: SiK
	Fecha: 2026-08-12
	Descripción: Graba disquetes (red, desinstalación, instalación de
	disquetera, y los que registren otros addons) desde el terminal, sin
	necesidad de cargar la disquetera encima. Solo visible si el periférico
	Reader está instalado en esta red - si no lo está, la vía existente sigue
	intacta: clic derecho en el disquete en blanco + disquetera encima + rango
	de un terminal (ver GS_ItemActions.lua / GS_ProgramDiskAction.lua), NO
	tocada por este fichero.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Chrome"
require "GS_DiskProgramming"
require "GS_CraftUtils"
require "GS_NetClient"

GlobalStorageSiK.TerminalProgramming = GlobalStorageSiK.TerminalProgramming or {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local CONTENT_PAD = 8
local BLOCK_GAP = 8
local BTN_H = FONT_HGT_SMALL + 10

-- Orden estable de programas conocidos por el Core; cualquier otro que un
-- addon registre via DiskProgramming.registerProgram() se añade detrás, en
-- el orden en que aparezca al iterar (no crítico, son pocos).
local KNOWN_PROGRAM_ORDER = { "network", "uninstall", "driveinstall" }

---@return table[] ids en orden estable
local function orderedProgramIds()
	local out = {}
	local seen = {}
	for i = 1, #KNOWN_PROGRAM_ORDER do
		local id = KNOWN_PROGRAM_ORDER[i]
		if GlobalStorageSiK.DiskProgramming.PROGRAMS[id] then
			out[#out + 1] = id
			seen[id] = true
		end
	end
	for id in pairs(GlobalStorageSiK.DiskProgramming.PROGRAMS) do
		if not seen[id] then
			out[#out + 1] = id
			seen[id] = true
		end
	end
	return out
end

local function addWrappedLabel(scroll, x, y, text, maxW, r, g, b)
	local lines = GlobalStorageSiK.TerminalChrome.wrapTextLines(text, maxW, UIFont.Small)
	for i = 1, #lines do
		local lbl = ISLabel:new(x, y, FONT_HGT_SMALL, lines[i], r, g, b, 1, UIFont.Small, true)
		lbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
		y = y + FONT_HGT_SMALL + 2
	end
	return y
end

-- Icono grande de la tarjeta de cada programa (pedido explicito 2026-08-21:
-- "tarjetas" visuales con el icono de su disquete correspondiente). Panel
-- propio con prerender, mismo patron que GS_TerminalUI_AddonBay.lua para el
-- icono del periferico - drawTextureScaledAspect conserva proporcion, nunca
-- deforma un icono cuadrado en un hueco no cuadrado.
local ICON_SIZE = 40
local function addProgramIcon(scroll, x, y, iconPath)
	local icon = ISPanel:new(x, y, ICON_SIZE, ICON_SIZE)
	icon:initialise()
	icon.drawBackground = false
	icon.prerender = function(panel)
		ISPanel.prerender(panel)
		local tex = iconPath and getTexture(iconPath) or nil
		if tex then
			panel:drawTextureScaledAspect(tex, 0, 0, panel.width, panel.height, 1, 1, 1, 1)
		end
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, icon)
end

local function addSectionTitle(scroll, x, y, titleKey, innerW)
	local title = T(titleKey)
	local titleH = FONT_HGT_SMALL + 8
	local hdrW = math.max(120, innerW - x * 2)
	local hdr = ISPanel:new(x, y, hdrW, titleH)
	hdr:initialise()
	hdr.drawBackground = false
	hdr.prerender = function(panel)
		ISPanel.prerender(panel)
		local patches = GlobalStorageSiK.TerminalChrome.getNeatPanelPatches()
		if not GlobalStorageSiK.TerminalChrome.renderNinePatch(panel, patches.innerTitle, 0, 0, panel.width, panel.height, 0.2, 0.2, 0.2, 0.88) then
			panel:drawRect(0, 0, panel.width, panel.height, 0.85, 0.12, 0.12, 0.12)
		end
		panel:drawText(title, 8, 2, 0.88, 0.9, 0.94, 1, UIFont.Small)
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, hdr)
	return y + titleH + 6
end

---@param panel ISPanel
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalProgramming.buildPanel(panel, terminal)
	if panel.programmingBuilt then
		return
	end
	panel.programmingBuilt = true
	panel.drawBackground = false
	panel.terminalRef = terminal
	panel.programmingScroll = GlobalStorageSiK.TerminalScroll.create(panel, terminal.padding or 8, 0, 280, 120)
end

---@param panel ISPanel
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalProgramming.layout(panel, innerW, innerH)
	if not panel or not panel.programmingScroll then
		return
	end
	local pad = panel.padding or 8
	local y = pad
	local bottomPad = GlobalStorageSiK.TerminalScroll.listBottomGap()
	local scrollH = math.max(120, innerH - y - pad - bottomPad)
	panel.programmingScroll:setX(pad)
	panel.programmingScroll:setY(y)
	GlobalStorageSiK.TerminalScroll.resize(panel.programmingScroll, innerW - pad * 2, scrollH)
end

---@param player IsoPlayer|nil
---@param id string
---@return boolean known
---@return boolean hasDisk
local function programReadiness(player, id)
	local known = GlobalStorageSiK.DiskProgramming.knowsProgram(player, id)
	local hasDisk = player ~= nil and GlobalStorageSiK.CraftUtils.findItemTypeNearby(player, GlobalStorageSiK.DiskProgramming.BLANK_DISK) ~= nil
	return known, hasDisk
end

---@param panel ISPanel
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalProgramming.refresh(panel, terminal)
	if not panel or not panel.programmingScroll then
		return
	end
	local scroll = panel.programmingScroll
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	GlobalStorageSiK.TerminalScroll.clear(scroll, true)

	local pad = CONTENT_PAD
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local cardW = math.max(260, innerW - pad * 2)
	local y = pad

	y = addSectionTitle(scroll, pad, y, "IGUI_GS_SectionProgramming", innerW)
	y = addWrappedLabel(scroll, pad, y, T("IGUI_GS_ProgrammingHint"), cardW, 0.62, 0.68, 0.72)
	y = y + BLOCK_GAP

	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or nil
	local btnW = math.min(280, cardW)
	local textX = pad + ICON_SIZE + 8
	local textW = math.max(80, cardW - ICON_SIZE - 8)
	local ids = orderedProgramIds()
	for i = 1, #ids do
		local id = ids[i]
		local def = GlobalStorageSiK.DiskProgramming.PROGRAMS[id]
		local blockTop = y

		addProgramIcon(scroll, pad, y, def.iconPath)

		local textY = y
		local title = T(def.menuTextKey or id)
		textY = addWrappedLabel(scroll, textX, textY, title, textW, 0.88, 0.9, 0.94)
		if def.descKey then
			textY = addWrappedLabel(scroll, textX, textY, T(def.descKey), textW, 0.62, 0.68, 0.72)
		end

		-- La tarjeta baja hasta lo mas alto entre el bloque de texto y el
		-- icono (un texto largo puede superar los 40px del icono; un icono
		-- sin descripcion nunca debe dejar la tarjeta mas corta que el).
		y = math.max(textY, blockTop + ICON_SIZE) + 4

		local known, hasDisk = programReadiness(player, id)
		local statusKey, sr, sg, sb
		if not known then
			statusKey, sr, sg, sb = "IGUI_GS_ProgrammingNeedsBook", 0.85, 0.4, 0.35
		elseif not hasDisk then
			statusKey, sr, sg, sb = "IGUI_GS_ProgrammingNeedsBlankDisk", 0.85, 0.7, 0.3
		else
			statusKey, sr, sg, sb = "IGUI_GS_ProgrammingReady", 0.5, 0.72, 0.55
		end
		y = addWrappedLabel(scroll, pad, y, T(statusKey), cardW, sr, sg, sb)
		y = y + 4

		local btn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad, y, btnW, BTN_H, T("IGUI_GS_ProgrammingButton"), scroll, function()
			GlobalStorageSiK.NetClient.sendCommand("programDisk", { programId = id })
		end)
		GlobalStorageSiK.TerminalScroll.addChild(scroll, btn)
		y = y + BTN_H + BLOCK_GAP
	end

	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, y + pad)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
	GlobalStorageSiK.TerminalScroll.applyPanelOffset(scroll)
end

--- Asegura panel de Programación en el terminal.
---@param terminal GS_TerminalUI
local function ensureProgrammingPanel(terminal)
	if not terminal or terminal.programmingPanel then
		return
	end
	local panel = ISPanel:new(0, 0, 10, 10)
	panel:initialise()
	panel.drawBackground = false
	panel.clipChildren = true
	panel:setScrollWithParent(false)
	if panel.setScrollChildren then
		panel:setScrollChildren(false)
	end
	terminal.programmingPanel = panel
	GlobalStorageSiK.TerminalProgramming.buildPanel(panel, terminal)
	GlobalStorageSiK.TerminalExtensions.registerTab(terminal, "programming", {
		panel = panel,
		module = GlobalStorageSiK.TerminalProgramming,
		titleKey = "IGUI_GS_TabProgramming",
		iconPath = "media/ui/GS/GS_TabProgramming.png",
	})
end

--- Muestra/oculta la pestaña Programación según si el periférico Reader
--- está instalado en esta red - sin él, la vía de siempre (disquetera
--- encima + rango de terminal, por menú contextual) sigue funcionando igual.
--- CRITICO: esto vivía como "function GS_TerminalUI:syncProgrammingTabVisibility()"
--- directamente en este fichero, que se requiere (GS_TerminalUI.lua) ANTES
--- de que la clase GS_TerminalUI exista (se define mucho más abajo en ese
--- mismo fichero) - crasheaba "attempted index of non-table" para TODO
--- jugador al conectar (reportado por Mad Man). Ningún otro fichero
--- GS_TerminalUI_*.lua hace esto: todos exponen su lógica en su propio
--- namespace (GlobalStorageSiK.TerminalXxx.*) y es GS_TerminalUI.lua quien,
--- YA con la clase definida, añade el método fino que delega aquí - mismo
--- patrón que Addons/Extensions/Network, ahora replicado.
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalProgramming.syncTabVisibility(terminal)
	local state = terminal.terminalState or {}
	local show = GlobalStorageSiK.Addons and GlobalStorageSiK.Addons.isInstalled(
		state.networkId, state.terminalAnchor, "Reader"
	)
	if show then
		ensureProgrammingPanel(terminal)
	end
	if GlobalStorageSiK.TerminalExtensions then
		GlobalStorageSiK.TerminalExtensions.setTabVisible(terminal, "programming", show == true)
	end
	if show and terminal.activeTabKey == "programming" and terminal.programmingPanel then
		GlobalStorageSiK.TerminalProgramming.refresh(terminal.programmingPanel, terminal)
	end
end

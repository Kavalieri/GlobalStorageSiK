--[[
	GSSiK Addon Builder - Pestaña Build del terminal
	Autor: SiK
	Fecha: 2026-08-04
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_Libs"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Chrome"
require "GS_NetworkCraftSession"
require "GSSiK_Addon_Builder_Sandbox"

GlobalStorageSiK.TerminalBuilder = GlobalStorageSiK.TerminalBuilder or {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local CONTENT_PAD = 8
local BLOCK_GAP = 8
local BTN_H = FONT_HGT_SMALL + 10

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
function GlobalStorageSiK.TerminalBuilder.buildPanel(panel, terminal)
	if panel.builderBuilt then
		return
	end
	panel.builderBuilt = true
	panel.drawBackground = false
	panel.terminalRef = terminal
	panel.builderScroll = GlobalStorageSiK.TerminalScroll.create(panel, terminal.padding or 8, 0, 280, 120)

	-- Version del addon, esquina inferior derecha - fuera del scroll (nunca
	-- se mueve con el contenido), discreta a propósito.
	local verText = "v" .. tostring(GSSiK_Addon_Builder.VERSION or "?")
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	panel.versionLbl = ISLabel:new(0, 0, FONT_HGT_SMALL, verText, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 0.5, UIFont.Small, true)
	panel.versionLbl:initialise()
	panel:addChild(panel.versionLbl)
end

---@param panel ISPanel
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalBuilder.layout(panel, innerW, innerH)
	if not panel or not panel.builderScroll then
		return
	end
	local pad = panel.padding or 8
	local y = pad
	local bottomPad = GlobalStorageSiK.TerminalScroll.listBottomGap()
	local scrollH = math.max(120, innerH - y - pad - bottomPad)
	panel.builderScroll:setX(pad)
	panel.builderScroll:setY(y)
	GlobalStorageSiK.TerminalScroll.resize(panel.builderScroll, innerW - pad * 2, scrollH)

	if panel.versionLbl then
		local tw = getTextManager():MeasureStringX(UIFont.Small, panel.versionLbl.name or "")
		panel.versionLbl:setX(math.max(pad, innerW - pad - tw))
		panel.versionLbl:setY(innerH - FONT_HGT_SMALL - 2)
		panel.versionLbl:bringToTop()
	end
end

---@param panel ISPanel
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalBuilder.refresh(panel, terminal)
	if not panel or not panel.builderScroll then
		return
	end
	local scroll = panel.builderScroll
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	GlobalStorageSiK.TerminalScroll.clear(scroll, true)

	local pad = CONTENT_PAD
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local cardW = math.max(260, innerW - pad * 2)
	local y = pad

	y = addSectionTitle(scroll, pad, y, "IGUI_GS_SectionBuildRemote", innerW)
	y = addWrappedLabel(scroll, pad, y, T("IGUI_GS_BuildRemoteHint"), cardW, 0.62, 0.68, 0.72)
	y = y + BLOCK_GAP

	local sessionStatus = GlobalStorageSiK.CraftSession.getStatus("Builder")
	local statusText, statusR, statusG, statusB = nil, 0.5, 0.72, 0.55
	local openError = GlobalStorageSiK.CraftSession.getLastOpenError and GlobalStorageSiK.CraftSession.getLastOpenError()
	if openError then
		statusR, statusG, statusB = 0.9, 0.4, 0.35
		if openError == "addon_unavailable" then
			statusText = T("IGUI_GS_CraftOpenErrorAddon")
		elseif openError == "no_player" then
			statusText = T("IGUI_GS_CraftOpenErrorNoPlayer")
		elseif openError == "out_of_range" then
			statusText = T("IGUI_GS_CraftOpenErrorRange")
		else
			statusText = T("IGUI_GS_CraftOpenErrorOpener")
		end
	elseif sessionStatus.active then
		statusText = T("IGUI_GS_CraftSessionActive", tostring(sessionStatus.networkContainers or 0))
	elseif sessionStatus.lastEndReason == "access_lost" then
		statusText = T("IGUI_GS_CraftSessionAccessLost")
	else
		statusText = T("IGUI_GS_CraftSessionInactive")
	end
	y = addWrappedLabel(scroll, pad, y, statusText, cardW, statusR, statusG, statusB)
	y = y + BLOCK_GAP

	-- Aviso suave (no es un error): ver comentario equivalente en
	-- GSSiK_Addon_Craft_TerminalUI.lua.
	if sessionStatus.active and (sessionStatus.unavailableContainers or 0) > 0 then
		y = addWrappedLabel(scroll, pad, y, T("IGUI_GS_CraftContainersUnavailable", tostring(sessionStatus.unavailableContainers)), cardW, 0.85, 0.7, 0.3)
		y = y + BLOCK_GAP
	end

	local btnW = math.min(280, cardW)
	local buildVanillaBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad, y, btnW, BTN_H, T("IGUI_GS_CraftOpenBuildVanilla"), scroll, function()
		if terminal and terminal.onOpenVanillaBuild then
			terminal:onOpenVanillaBuild()
		end
	end)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, buildVanillaBtn)
	y = y + BTN_H + 6

	if GlobalStorageSiK.Libs.hasNeatBuilding() then
		local buildNeatBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad, y, btnW, BTN_H, T("IGUI_GS_CraftOpenBuildNeat"), scroll, function()
			if terminal and terminal.onOpenNeatBuild then
				terminal:onOpenNeatBuild()
			end
		end)
		GlobalStorageSiK.TerminalScroll.addChild(scroll, buildNeatBtn)
		y = y + BTN_H + 6
	end

	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, y + pad)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
	GlobalStorageSiK.TerminalScroll.applyPanelOffset(scroll)
end

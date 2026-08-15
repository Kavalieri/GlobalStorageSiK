--[[
	GSSiK Addon Craft - Pestaña Craft del terminal
	Autor: SiK
	Fecha: 2025-06-27
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_Libs"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Chrome"
require "GS_NetworkCraftSession"
require "GSSiK_Addon_Craft_Sandbox"

GlobalStorageSiK.TerminalCraft = GlobalStorageSiK.TerminalCraft or {}

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
function GlobalStorageSiK.TerminalCraft.buildPanel(panel, terminal)
	if panel.craftBuilt then
		return
	end
	panel.craftBuilt = true
	panel.drawBackground = false
	panel.terminalRef = terminal
	panel.craftScroll = GlobalStorageSiK.TerminalScroll.create(panel, terminal.padding or 8, 0, 280, 120)

	-- Version del addon, esquina inferior derecha de la pestaña - fuera del
	-- scroll (nunca se mueve con el contenido, nunca desplaza nada), muy
	-- discreta a propósito (pedido explicito: casi inapreciable).
	local verText = "v" .. tostring(GSSiK_Addon_Craft.VERSION or "?")
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
	panel.versionLbl = ISLabel:new(0, 0, FONT_HGT_SMALL, verText, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 0.5, UIFont.Small, true)
	panel.versionLbl:initialise()
	panel:addChild(panel.versionLbl)
end

---@param panel ISPanel
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalCraft.layout(panel, innerW, innerH)
	if not panel or not panel.craftScroll then
		return
	end
	local pad = panel.padding or 8
	local y = pad
	local bottomPad = GlobalStorageSiK.TerminalScroll.listBottomGap()
	local scrollH = math.max(120, innerH - y - pad - bottomPad)
	panel.craftScroll:setX(pad)
	panel.craftScroll:setY(y)
	GlobalStorageSiK.TerminalScroll.resize(panel.craftScroll, innerW - pad * 2, scrollH)

	if panel.versionLbl then
		local tw = getTextManager():MeasureStringX(UIFont.Small, panel.versionLbl.name or "")
		panel.versionLbl:setX(math.max(pad, innerW - pad - tw))
		panel.versionLbl:setY(innerH - FONT_HGT_SMALL - 2)
		panel.versionLbl:bringToTop()
	end
end

---@param panel ISPanel
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalCraft.refresh(panel, terminal)
	if not panel or not panel.craftScroll then
		return
	end
	local scroll = panel.craftScroll
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	GlobalStorageSiK.TerminalScroll.clear(scroll, true)

	local pad = CONTENT_PAD
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local cardW = math.max(260, innerW - pad * 2)
	local y = pad

	y = addSectionTitle(scroll, pad, y, "IGUI_GS_SectionCraftRemote", innerW)
	y = addWrappedLabel(scroll, pad, y, T("IGUI_GS_CraftRemoteHint"), cardW, 0.62, 0.68, 0.72)
	y = y + BLOCK_GAP

	local sessionStatus = GlobalStorageSiK.CraftSession.getStatus("Craft")
	local statusText, statusR, statusG, statusB = nil, 0.5, 0.72, 0.55
	local openError = GlobalStorageSiK.CraftSession.getLastOpenError and GlobalStorageSiK.CraftSession.getLastOpenError()
	if openError then
		-- Antes, si el clic en "Open game crafting" fallaba, no pasaba nada
		-- visible - ahora el motivo exacto se muestra aqui, en rojo.
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

	-- Aviso suave (no es un error): contenedores registrados en la red que
	-- ahora mismo no se pueden usar en crafteo/construccion porque su zona
	-- no esta cargada para este cliente (ver getContainerAvailability en
	-- GS_CraftingBridge.lua) - antes esto no se veia en ningun sitio, un
	-- contenedor lejano simplemente "faltaba" sin explicacion.
	if sessionStatus.active and (sessionStatus.unavailableContainers or 0) > 0 then
		y = addWrappedLabel(scroll, pad, y, T("IGUI_GS_CraftContainersUnavailable", tostring(sessionStatus.unavailableContainers)), cardW, 0.85, 0.7, 0.3)
		y = y + BLOCK_GAP
	end

	local btnW = math.min(280, cardW)
	local vanillaBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad, y, btnW, BTN_H, T("IGUI_GS_CraftOpenVanilla"), scroll, function()
		if terminal and terminal.onOpenVanillaCraft then
			terminal:onOpenVanillaCraft()
		end
	end)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, vanillaBtn)
	y = y + BTN_H + 6

	if GlobalStorageSiK.Libs.hasNeatCrafting() then
		local neatBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad, y, btnW, BTN_H, T("IGUI_GS_CraftOpenNeat"), scroll, function()
			if terminal and terminal.onOpenNeatCraft then
				terminal:onOpenNeatCraft()
			end
		end)
		GlobalStorageSiK.TerminalScroll.addChild(scroll, neatBtn)
		y = y + BTN_H + 6
	end

	-- Solo visible con Project_Cook instalado - sin el mod no hay nada que
	-- abrir, y un boton "no hace nada" es peor que no mostrarlo.
	if GlobalStorageSiK.Libs.hasProjectCook() then
		local cookBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad, y, btnW, BTN_H, T("IGUI_GS_CraftOpenCook"), scroll, function()
			if terminal and terminal.onOpenCook then
				terminal:onOpenCook()
			end
		end)
		GlobalStorageSiK.TerminalScroll.addChild(scroll, cookBtn)
		y = y + BTN_H + 6
	end

	y = y + BLOCK_GAP

	-- Toggle "enviar resultado al almacen" (pedido explicito, 2026-08-17):
	-- las herramientas/materiales sobrantes YA vuelven solos a la red
	-- (sweepPendingReturns, mecanismo existente, sin tocar) - esto es SOLO
	-- para el resultado nuevo del crafteo, que hoy se queda siempre en el
	-- inventario. Preferencia solo de cliente, no persiste entre sesiones
	-- (vuelve a "no" cada vez que se reabre el terminal) - a proposito,
	-- mas simple y sin sorpresas de "se me olvido que lo tenia activado".
	local sendActive = GlobalStorageSiK.CraftSession.sendResultToNetwork == true
	local sendLabel = sendActive and T("IGUI_GS_CraftSendResultOn") or T("IGUI_GS_CraftSendResultOff")
	local sendBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad, y, btnW, BTN_H, sendLabel, scroll, function()
		local nowActive = not (GlobalStorageSiK.CraftSession.sendResultToNetwork == true)
		GlobalStorageSiK.CraftSession.sendResultToNetwork = nowActive
		sendBtn._gsNeatLabel = nowActive and T("IGUI_GS_CraftSendResultOn") or T("IGUI_GS_CraftSendResultOff")
		sendBtn._gsNeatActive = nowActive
	end)
	sendBtn._gsNeatActive = sendActive
	GlobalStorageSiK.TerminalScroll.addChild(scroll, sendBtn)
	y = y + BTN_H + 6
	y = addWrappedLabel(scroll, pad, y, T("IGUI_GS_CraftSendResultHint"), cardW, 0.55, 0.58, 0.62)

	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, y + pad)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
	GlobalStorageSiK.TerminalScroll.applyPanelOffset(scroll)
end

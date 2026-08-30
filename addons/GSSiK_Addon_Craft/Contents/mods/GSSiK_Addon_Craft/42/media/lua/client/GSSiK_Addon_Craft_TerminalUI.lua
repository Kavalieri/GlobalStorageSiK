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
require "GS_SiK_UI_Core"
require "GS_SiK_UI_Controls"
require "GS_NetworkCraftSession"
require "GSSiK_Addon_Craft_Sandbox"

GlobalStorageSiK.TerminalCraft = GlobalStorageSiK.TerminalCraft or {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local CONTROLS = GlobalStorageSiK.SiK_UI.Controls
local CONTROL_METRICS = CONTROLS.metrics("standard")
local BLOCK_GAP = CONTROL_METRICS.rowGap
local BTN_H = CONTROL_METRICS.buttonHeight

local function addWrappedLabel(scroll, x, y, text, maxW, r, g, b)
	local lines = GlobalStorageSiK.SiK_UI.wrapTextLines(text, maxW, UIFont.Small)
	for i = 1, #lines do
		local lbl = ISLabel:new(x, y, FONT_HGT_SMALL, lines[i], r, g, b, 1, UIFont.Small, true)
		lbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
		y = y + FONT_HGT_SMALL + 2
	end
	return y
end

local function addBlockHeader(scroll, x, y, width, titleKey, tooltipKey)
	local host = GlobalStorageSiK.TerminalScroll.childHost(scroll)
	local header = CONTROLS.blockHeader(host, {
		x = x, y = y, w = width, text = T(titleKey),
		tooltip = T(tooltipKey), target = scroll,
	})
	return y + header.height + BLOCK_GAP
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
	panel.craftScroll = GlobalStorageSiK.TerminalScroll.create(panel, 0, 0, 280, 120)
	GlobalStorageSiK.TerminalScroll.setOnContentRectChanged(panel.craftScroll,
		function()
			if not panel._craftRefreshing then
				GlobalStorageSiK.TerminalCraft.refresh(panel, panel.terminalRef)
			end
		end)
end

---@param panel ISPanel
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalCraft.layout(panel, innerW, innerH)
	if not panel or not panel.craftScroll then
		return
	end
	panel.craftScroll:setX(0)
	panel.craftScroll:setY(0)
	GlobalStorageSiK.TerminalScroll.resize(panel.craftScroll,
		math.max(120, innerW), math.max(120, innerH))
end

---@param panel ISPanel
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalCraft.refresh(panel, terminal)
	if not panel or not panel.craftScroll or panel._craftRefreshing then
		return
	end
	panel._craftRefreshing = true
	local scroll = panel.craftScroll
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	GlobalStorageSiK.TerminalScroll.clear(scroll, true)

	local beforeRect = GlobalStorageSiK.TerminalScroll.contentRect(scroll)
	local contentW = math.max(80, beforeRect.w)
	local y = 0
	y = addBlockHeader(scroll, 0, y, contentW,
		"IGUI_GS_SectionCraftRemote", "IGUI_GS_CraftRemoteHint")

	local sessionStatus = GlobalStorageSiK.CraftSession.getStatus("Craft")
	local statusText, statusKind = nil, "info"
	local openError = GlobalStorageSiK.CraftSession.getLastOpenError and GlobalStorageSiK.CraftSession.getLastOpenError()
	if openError then
		statusKind = "error"
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
		statusKind = "success"
		statusText = T("IGUI_GS_CraftSessionActive", tostring(sessionStatus.networkContainers or 0))
	elseif sessionStatus.lastEndReason == "access_lost" then
		statusKind = "warning"
		statusText = T("IGUI_GS_CraftSessionAccessLost")
	else
		statusText = T("IGUI_GS_CraftSessionInactive")
	end
	local feedback = CONTROLS.feedback(nil, {
		x = 0, y = y, w = contentW, text = statusText, kind = statusKind,
	})
	GlobalStorageSiK.TerminalScroll.addChild(scroll, feedback)
	y = y + feedback.height + BLOCK_GAP

	if sessionStatus.active and (sessionStatus.unavailableContainers or 0) > 0 then
		local unavailable = CONTROLS.feedback(nil, {
			x = 0, y = y, w = contentW,
			text = T("IGUI_GS_CraftContainersUnavailable",
				tostring(sessionStatus.unavailableContainers)), kind = "warning",
		})
		GlobalStorageSiK.TerminalScroll.addChild(scroll, unavailable)
		y = y + unavailable.height + BLOCK_GAP
	end

	local hasNeatCrafting = GlobalStorageSiK.Libs.hasNeatCrafting()
	local hasProjectCook = GlobalStorageSiK.Libs.hasProjectCook()
	local interfaceText = hasNeatCrafting and T("IGUI_GS_CraftInterfaceNeat")
		or T("IGUI_GS_CraftInterfaceVanilla")
	local cookText = hasProjectCook and T("IGUI_GS_CraftCookAvailable")
		or T("IGUI_GS_CraftCookUnavailable")
	local gap = CONTROL_METRICS.controlGap
	local gridMinW = getTextManager():MeasureStringX(UIFont.Small, interfaceText)
		+ getTextManager():MeasureStringX(UIFont.Small, cookText) + gap
	if contentW >= gridMinW then
		local colW = math.floor((contentW - gap) / 2)
		local leftY = addWrappedLabel(scroll, 0, y, interfaceText, colW,
			0.72, 0.78, 0.84)
		local rightY = addWrappedLabel(scroll, colW + gap, y, cookText,
			contentW - colW - gap, 0.72, 0.78, 0.84)
		y = math.max(leftY, rightY) + BLOCK_GAP
	else
		y = addWrappedLabel(scroll, 0, y, interfaceText, contentW,
			0.72, 0.78, 0.84)
		y = addWrappedLabel(scroll, 0, y, cookText, contentW,
			0.72, 0.78, 0.84) + BLOCK_GAP
	end

	local craftLabelKey = hasNeatCrafting and "IGUI_GS_CraftOpenNeat" or "IGUI_GS_CraftOpenVanilla"
	local craftBtn = CONTROLS.button(nil, {
		x = 0, y = y, w = contentW, h = BTN_H, text = T(craftLabelKey),
		target = scroll, fullWidth = true, onClick = function()
			if hasNeatCrafting then
				if terminal and terminal.onOpenNeatCraft then terminal:onOpenNeatCraft() end
			elseif terminal and terminal.onOpenVanillaCraft then
				terminal:onOpenVanillaCraft()
			end
		end,
	})
	GlobalStorageSiK.TerminalScroll.addChild(scroll, craftBtn)
	y = y + BTN_H + CONTROL_METRICS.rowGap

	if hasProjectCook then
		local cookBtn = CONTROLS.button(nil, {
			x = 0, y = y, w = contentW, h = BTN_H,
			text = T("IGUI_GS_CraftOpenCook"), target = scroll,
			fullWidth = true, onClick = function()
				if terminal and terminal.onOpenCook then terminal:onOpenCook() end
			end,
		})
		GlobalStorageSiK.TerminalScroll.addChild(scroll, cookBtn)
		y = y + BTN_H + CONTROL_METRICS.rowGap
	end

	local sendActive = GlobalStorageSiK.CraftSession.sendResultToNetwork == true
	local sendLabel = sendActive and T("IGUI_GS_CraftSendResultOn") or T("IGUI_GS_CraftSendResultOff")
	local sendBtn
	sendBtn = CONTROLS.button(nil, {
		x = 0, y = y, w = contentW, h = BTN_H, text = sendLabel,
		target = scroll, fullWidth = true,
		tooltip = T("IGUI_GS_CraftSendResultHint"), onClick = function()
			local nowActive = not (GlobalStorageSiK.CraftSession.sendResultToNetwork == true)
			GlobalStorageSiK.CraftSession.sendResultToNetwork = nowActive
			sendBtn._sikUiLabel = nowActive and T("IGUI_GS_CraftSendResultOn")
				or T("IGUI_GS_CraftSendResultOff")
			sendBtn._sikUiActive = nowActive
		end,
	})
	sendBtn._sikUiActive = sendActive
	GlobalStorageSiK.TerminalScroll.addChild(scroll, sendBtn)
	y = y + BTN_H

	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, y)
	local afterRect = GlobalStorageSiK.TerminalScroll.contentRect(scroll)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
	GlobalStorageSiK.TerminalScroll.applyPanelOffset(scroll)
	panel._craftRefreshing = false
	if afterRect.w ~= beforeRect.w then
		GlobalStorageSiK.TerminalCraft.refresh(panel, terminal)
	end
end

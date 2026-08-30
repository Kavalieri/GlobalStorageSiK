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
require "GS_SiK_UI_Controls"
require "GS_NetworkCraftSession"
require "GSSiK_Addon_Builder_Sandbox"

GlobalStorageSiK.TerminalBuilder = GlobalStorageSiK.TerminalBuilder or {}

local T = GlobalStorageSiK.I18n.text
local SiK_UI = GlobalStorageSiK.SiK_UI
local Controls = SiK_UI.Controls

local function contentHost(scroll)
	return GlobalStorageSiK.TerminalScroll.childHost(scroll) or scroll
end

local function sessionPresentation()
	local sessionStatus = GlobalStorageSiK.CraftSession.getStatus("Builder")
	local openError = GlobalStorageSiK.CraftSession.getLastOpenError
		and GlobalStorageSiK.CraftSession.getLastOpenError()
	if openError then
		if openError == "addon_unavailable" then
			return sessionStatus, T("IGUI_GS_CraftOpenErrorAddon"), "error"
		elseif openError == "no_player" then
			return sessionStatus, T("IGUI_GS_CraftOpenErrorNoPlayer"), "error"
		elseif openError == "out_of_range" then
			return sessionStatus, T("IGUI_GS_CraftOpenErrorRange"), "error"
		end
		return sessionStatus, T("IGUI_GS_CraftOpenErrorOpener"), "error"
	elseif sessionStatus.active then
		return sessionStatus,
			T("IGUI_GS_CraftSessionActive", tostring(sessionStatus.networkContainers or 0)),
			"ok"
	elseif sessionStatus.lastEndReason == "access_lost" then
		return sessionStatus, T("IGUI_GS_CraftSessionAccessLost"), "warn"
	end
	return sessionStatus, T("IGUI_GS_CraftSessionInactive"), "info"
end

local function layoutContent(panel)
	local scroll = panel and panel.builderScroll
	if not scroll then return end
	local rect = GlobalStorageSiK.TerminalScroll.contentRect(scroll)
	local metrics = Controls.metrics(panel.profile)
	local x = rect.x
	local y = rect.y
	local w = math.max(0, rect.w)

	if panel.builderStatus then
		panel.builderStatus:setX(x)
		panel.builderStatus:setY(y)
		panel.builderStatus:setWidth(w)
		y = y + metrics.statusHeight + metrics.rowGap
	end
	if panel.builderInterfaceLbl then
		panel.builderInterfaceLbl:setX(x)
		panel.builderInterfaceLbl:setY(y)
		y = y + getTextManager():getFontHeight(UIFont.Small) + metrics.rowGap
	end
	if panel.builderWarning then
		panel.builderWarning:setX(x)
		panel.builderWarning:setY(y)
		panel.builderWarning:setWidth(w)
		y = y + metrics.statusHeight + metrics.rowGap
	end
	if panel.builderOpenBtn then
		panel.builderOpenBtn:setX(x)
		panel.builderOpenBtn:setY(y)
		panel.builderOpenBtn:setWidth(w)
		y = y + metrics.buttonHeight
	end

	local contentHeight = y + metrics.blockPadding
	if scroll._gsBuilderContentHeight ~= contentHeight then
		scroll._gsBuilderContentHeight = contentHeight
		GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, contentHeight)
	end
end

---@param panel ISPanel
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalBuilder.buildPanel(panel, terminal)
	if panel.builderBuilt then return end
	panel.builderBuilt = true
	panel.drawBackground = false
	panel.terminalRef = terminal

	local metrics = Controls.metrics(panel.profile)
	local initialW = math.max(1, (panel.width or 1) - metrics.blockPadding * 2)
	panel.builderHeader = Controls.blockHeader(panel, {
		x = metrics.blockPadding,
		y = metrics.blockPadding,
		w = initialW,
		text = T("IGUI_GS_SectionBuildRemote"),
		tooltip = T("IGUI_GS_BuildRemoteHint"),
		target = panel,
	})
	panel.builderScroll = GlobalStorageSiK.TerminalScroll.create(panel,
		metrics.blockPadding, 0, initialW, metrics.statusHeight)
	GlobalStorageSiK.TerminalScroll.setOnContentRectChanged(panel.builderScroll,
		function()
			layoutContent(panel)
		end)
end

---@param panel ISPanel
---@param innerW number
---@param innerH number
function GlobalStorageSiK.TerminalBuilder.layout(panel, innerW, innerH)
	if not panel or not panel.builderScroll then return end
	local metrics = Controls.metrics(panel.profile)
	local pad = metrics.blockPadding
	local headerH = panel.builderHeader and panel.builderHeader.height
		or metrics.sectionHeight
	local scrollY = pad + headerH + metrics.rowGap
	local scrollH = math.max(metrics.statusHeight, innerH - scrollY - pad)

	if panel.builderHeader then
		panel.builderHeader.title:setY(pad)
		if panel.builderHeader.info then
			panel.builderHeader.info:setY(pad
				+ math.floor((headerH - getTextManager():getFontHeight(UIFont.Small)) / 2))
		end
	end
	panel.builderScroll:setX(pad)
	panel.builderScroll:setY(scrollY)
	GlobalStorageSiK.TerminalScroll.resize(panel.builderScroll,
		math.max(0, innerW - pad * 2), scrollH)
	layoutContent(panel)
end

---@param panel ISPanel
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalBuilder.refresh(panel, terminal)
	if not panel or not panel.builderScroll then return end
	local scroll = panel.builderScroll
	local host = contentHost(scroll)
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	GlobalStorageSiK.TerminalScroll.clear(scroll, true)
	panel.builderStatus = nil
	panel.builderInterfaceLbl = nil
	panel.builderWarning = nil
	panel.builderOpenBtn = nil
	local initialW = math.max(1, GlobalStorageSiK.TerminalScroll.contentWidth(scroll))

	local sessionStatus, statusText, statusKind = sessionPresentation()
	panel.builderStatus = Controls.status(host, {
		x = 0, y = 0, w = initialW,
		text = statusText,
		status = statusKind,
	})

	local hasNeatBuilding = GlobalStorageSiK.Libs.hasNeatBuilding()
	local interfaceKey = hasNeatBuilding and "IGUI_GS_BuildInterfaceNeat"
		or "IGUI_GS_BuildInterfaceVanilla"
	panel.builderInterfaceLbl = ISLabel:new(0, 0,
		getTextManager():getFontHeight(UIFont.Small),
		T("IGUI_GS_BuildInterfaceDetected", T(interfaceKey)),
		SiK_UI.PALETTE.textPrimary[1], SiK_UI.PALETTE.textPrimary[2],
		SiK_UI.PALETTE.textPrimary[3], 1, UIFont.Small, true)
	panel.builderInterfaceLbl:initialise()
	host:addChild(panel.builderInterfaceLbl)

	if sessionStatus.active and (sessionStatus.unavailableContainers or 0) > 0 then
		panel.builderWarning = Controls.status(host, {
			x = 0, y = 0, w = initialW,
			text = T("IGUI_GS_CraftContainersUnavailable",
				tostring(sessionStatus.unavailableContainers)),
			status = "warn",
		})
	end

	local buildLabelKey = hasNeatBuilding and "IGUI_GS_CraftOpenBuildNeat"
		or "IGUI_GS_CraftOpenBuildVanilla"
	panel.builderOpenBtn = Controls.button(host, {
		x = 0, y = 0, w = initialW,
		text = T(buildLabelKey),
		target = scroll,
		fullWidth = true,
		onClick = function()
			if hasNeatBuilding then
				if terminal and terminal.onOpenNeatBuild then terminal:onOpenNeatBuild() end
			elseif terminal and terminal.onOpenVanillaBuild then
				terminal:onOpenVanillaBuild()
			end
		end,
	})

	layoutContent(panel)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
	GlobalStorageSiK.TerminalScroll.applyPanelOffset(scroll)
end

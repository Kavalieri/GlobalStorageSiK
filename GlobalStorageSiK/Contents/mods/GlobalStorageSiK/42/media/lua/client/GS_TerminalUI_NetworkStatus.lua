--[[
	GlobalStorageSiK - Pestaña Red: bloque 1 (estado + estadísticas)
	Autor: SiK
	Fecha: 2025-06-26
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_Sandbox"
require "GS_NetClient"
require "GS_TerminalUI_Scroll"
require "GS_SiK_UI_Core"
require "GS_SiK_UI_Palette"
require "GS_SiK_UI_Controls"

GlobalStorageSiK.TerminalNetworkStatus = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

-- Core 1.4.3-dev32.4.2: Estado vive dentro de la única tarjeta creada por
-- TerminalNetworkList. Sustituye las cuatro tarjetas históricas, la identidad
-- duplicada y las líneas de reescaneo que ahora pertenecen solo a Red/Zonas.
local function addV2Label(scroll, ui, key, x, y, text)
	local lbl = ISLabel:new(x, y, FONT_HGT_SMALL, text or "", 0.72, 0.76, 0.82, 1, UIFont.Small, true)
	lbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
	ui.stats[key] = lbl
	return lbl
end

local function addV2Indicator(scroll, ui, key, x, y, width)
	local row = GlobalStorageSiK.SiK_UI.Controls.status(nil, {
		x = x, y = y, w = width, h = FONT_HGT_SMALL + 4,
	})
	GlobalStorageSiK.TerminalScroll.addChild(scroll, row)
	ui.stats[key] = row
end

local function setV2Text(lbl, text)
	if not GlobalStorageSiK.TerminalScroll.isLiveWidget(lbl) then return end
	if lbl.setName then lbl:setName(text or "") else lbl.name = text or "" end
end

local function buildV2(scroll, terminal, ui, y, innerW)
	local pad, gap = 8, 8
	local contentW = math.max(160, innerW - pad * 2)
	ui.leftX, ui.contentW = pad, contentW

	ui.statusBlockY = y
	ui.statusBlockCard = GlobalStorageSiK.SiK_UI.createSectionCard(0, y, innerW, 10)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.statusBlockCard)
	y = y + pad
	ui.statusTitle = GlobalStorageSiK.SiK_UI.Controls.sectionTitle(nil, {
		x = pad, y = y, text = T("IGUI_GS_NetBlockOverview"),
	})
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.statusTitle)
	y = y + FONT_HGT_SMALL + gap
	local indColW = math.floor((contentW - gap) / 2)
	ui.indColW = indColW
	addV2Indicator(scroll, ui, "valPower", pad, y, indColW)
	addV2Indicator(scroll, ui, "valTerminal", pad + indColW + gap, y, indColW)
	y = y + FONT_HGT_SMALL + 6
	addV2Indicator(scroll, ui, "valZones", pad, y, indColW)
	addV2Indicator(scroll, ui, "valAccess", pad + indColW + gap, y, indColW)
	y = y + FONT_HGT_SMALL + pad
	ui.statusBlockEndY = y
	GlobalStorageSiK.SiK_UI.resizeSectionCard(ui.statusBlockCard, 0,
		ui.statusBlockY, innerW, ui.statusBlockEndY - ui.statusBlockY)
	y = y + gap

	ui.resourcesBlockY = y
	ui.resourcesBlockCard = GlobalStorageSiK.SiK_UI.createSectionCard(0, y, innerW, 10)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.resourcesBlockCard)
	y = y + pad
	ui.statsTitle = GlobalStorageSiK.SiK_UI.Controls.sectionTitle(nil, {
		x = pad, y = y, text = T("IGUI_GS_NetBlockStats"),
	})
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.statsTitle)
	y = y + FONT_HGT_SMALL + 10
	ui.resourceRow1Y = y
	addV2Label(scroll, ui, "statSummary", pad, y, "")
	addV2Label(scroll, ui, "statAccess", pad + indColW + gap, y, "")
	y = y + FONT_HGT_SMALL + 8
	ui.resourceRow2Y = y
	addV2Label(scroll, ui, "statFuel", pad, y, "")
	addV2Label(scroll, ui, "statCapacityAvailable", pad + indColW + gap, y, T("IGUI_GS_NetCapacityAvailable"))
	y = y + FONT_HGT_SMALL + 10

	local barH = math.max(8, math.floor(FONT_HGT_SMALL * 0.7))
	local weightRow = ISPanel:new(pad, y, contentW, FONT_HGT_SMALL + 6 + barH)
	weightRow:initialise()
	weightRow.drawBackground = false
	weightRow.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	weightRow.capacityPercent, weightRow.capacityStatus = 0, "ok"
	weightRow.prerender = function(b)
		ISPanel.prerender(b)
		local label = b.name or ""
		local pct = tostring(math.floor(tonumber(b.capacityPercent) or 0)) .. "%"
		b:drawText(label, 0, 0, 0.88, 0.9, 0.94, 1, UIFont.Small)
		local pw = getTextManager():MeasureStringX(UIFont.Small, pct)
		b:drawText(pct, b.width - pw, 0, 0.88, 0.9, 0.94, 1, UIFont.Small)
		local fill = math.max(0, math.min(1, (b.capacityPercent or 0) / 100))
		local fr, fg, fb = GlobalStorageSiK.SiK_UI.getBarColor(fill)
		GlobalStorageSiK.SiK_UI.drawProgressBar(b, 0, FONT_HGT_SMALL + 6, b.width, barH, fill, fr, fg, fb)
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, weightRow)
	ui.stats.statWeight, ui.weightBar = weightRow, weightRow
	y = y + weightRow.height + gap

	ui.reachTitle = GlobalStorageSiK.SiK_UI.Controls.sectionTitle(nil, {
		x = pad, y = y, text = T("IGUI_GS_NetBlockReach"),
	})
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.reachTitle)
	y = y + FONT_HGT_SMALL + 10
	ui.reachRowY = y
	addV2Label(scroll, ui, "statTerminalRange", pad, y,
		T("IGUI_GS_DistTerminalUse", GlobalStorageSiK.Sandbox.getTerminalProximityRange()))
	addV2Label(scroll, ui, "statNetworkRange", pad + indColW + gap, y,
		T("IGUI_GS_DistNetworkReach", GlobalStorageSiK.Sandbox.getContainerMaxDistance()))
	y = y + FONT_HGT_SMALL + pad
	ui.reachEndY = y
	ui.block1EndY = y
	ui.resourcesBlockEndY = y
	GlobalStorageSiK.SiK_UI.resizeSectionCard(ui.resourcesBlockCard, 0,
		ui.resourcesBlockY, innerW, ui.resourcesBlockEndY - ui.resourcesBlockY)

	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer
		and GlobalStorageSiK.NetClient.getPlayer()
	ui.paletteSelector = GlobalStorageSiK.SiK_UI.Palette.createSelector(
		pad, y + gap, contentW, player, function()
			if terminal and terminal.setDirty then terminal:setDirty(true) end
		end)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.paletteSelector)
	ui.paletteEndY = y + gap + ui.paletteSelector.height + pad
	return ui.paletteEndY
end

local function syncV2(ui, state)
	state = state or {}
	local setInd = GlobalStorageSiK.SiK_UI.setStatusIndicatorRow
	local colW = ui.indColW or 120
	local powered = state.powered ~= false
	local terminals = #(state.terminals or {})
	if state.terminalAnchor and state.terminalAnchor.x then terminals = math.max(terminals, 1) end
	local zones = #(state.zones or {})
	setInd(ui.stats.valPower, powered and T("IGUI_GS_ValPowerOk") or T("IGUI_GS_ValPowerOff"), powered and "ok" or "error", colW)
	setInd(ui.stats.valTerminal, terminals > 0 and T("IGUI_GS_ValTerminalOk") or T("IGUI_GS_ValTerminalMissing"), terminals > 0 and "ok" or "error", colW)
	setInd(ui.stats.valZones, zones > 0 and T("IGUI_GS_ValZonesOk", zones) or T("IGUI_GS_ValZonesMissing"), zones > 0 and "ok" or "warn", colW)
	setInd(ui.stats.valAccess, powered and zones > 0 and T("IGUI_GS_ValNetworkReady") or T("IGUI_GS_ValNetworkBlocked"), powered and zones > 0 and "ok" or "error", colW)

	setV2Text(ui.stats.statSummary, T("IGUI_GS_NetResourceSummary", #(state.nodes or {}), state.itemTypeCount or 0))
	local mode = state.accessMode
	local accessText = T("IGUI_GS_NetAccessPhysical")
	if mode == "wireless" then accessText = T("IGUI_GS_NetAccessWireless")
	elseif mode == "bypass" then accessText = T("IGUI_GS_NetAccessBypass") end
	setV2Text(ui.stats.statAccess, accessText)
	local fuel = state.fuelConsumption or {}
	setV2Text(ui.stats.statFuel, T("IGUI_GS_StatsFuel", string.format("%.2f", tonumber(fuel.total) or 0)))
	local cap = state.capacity or {}
	local used, total = string.format("%.0f", tonumber(cap.usedWeight) or 0), string.format("%.0f", tonumber(cap.totalCapacity) or 0)
	setV2Text(ui.stats.statWeight, T("IGUI_GS_NetCapacityLine", used, total))
	if ui.weightBar then
		ui.weightBar.capacityPercent = tonumber(cap.percent) or 0
		ui.weightBar.capacityStatus = cap.status or "ok"
	end
end

local function layoutV2(scroll, ui, innerW)
	if not ui or not ui.stats then return end
	local pad, gap = 8, 8
	local contentW = math.max(160, innerW - pad * 2)
	local colW = math.floor((contentW - gap) / 2)
	ui.leftX, ui.contentW, ui.indColW = pad, contentW, colW
	for _, key in ipairs({ "statusTitle", "statsTitle", "reachTitle" }) do
		local lbl = ui[key]
		if lbl then GlobalStorageSiK.TerminalScroll.setContentX(scroll, lbl, pad) end
	end
	for _, spec in ipairs({
		{ "valPower", pad }, { "valTerminal", pad + colW + gap },
		{ "valZones", pad }, { "valAccess", pad + colW + gap },
		{ "statSummary", pad }, { "statAccess", pad + colW + gap },
		{ "statFuel", pad }, { "statCapacityAvailable", pad + colW + gap },
		{ "statTerminalRange", pad }, { "statNetworkRange", pad + colW + gap },
	}) do
		local widget = ui.stats[spec[1]]
		if widget then
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, widget, spec[2])
			if widget.setWidth then widget:setWidth(colW) end
		end
	end
	if ui.weightBar then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.weightBar, pad)
		ui.weightBar:setWidth(contentW)
	end
	if ui.statusBlockCard then
		GlobalStorageSiK.SiK_UI.resizeSectionCard(ui.statusBlockCard, 0,
			ui.statusBlockY or 0, innerW,
			(ui.statusBlockEndY or 0) - (ui.statusBlockY or 0))
	end
	if ui.resourcesBlockCard then
		GlobalStorageSiK.SiK_UI.resizeSectionCard(ui.resourcesBlockCard, 0,
			ui.resourcesBlockY or 0, innerW,
			(ui.resourcesBlockEndY or 0) - (ui.resourcesBlockY or 0))
	end
	if ui.paletteSelector then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.paletteSelector, pad)
		GlobalStorageSiK.SiK_UI.Palette.layoutSelector(ui.paletteSelector, contentW)
	end
end

GlobalStorageSiK.TerminalNetworkStatus.build = buildV2
GlobalStorageSiK.TerminalNetworkStatus.sync = syncV2
GlobalStorageSiK.TerminalNetworkStatus.layout = layoutV2

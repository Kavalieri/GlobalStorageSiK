--[[
	GlobalStorageSiK - Pestaña Red: selector y gestión de redes GS
	Autor: SiK
	Fecha: 2026-06-28
	Descripción: Lista redes del jugador, sesión activa, crear/vincular terminal.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalUI_Scroll"
require "GS_SiK_UI_Core"
require "GS_SiK_UI_Window"

GlobalStorageSiK.TerminalNetworkList = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BTN_H = FONT_HGT_SMALL + 6
local ROW_GAP = 6
local INFO_LINE_COUNT = 2

---@param state table|nil
---@return table[]
local function networkRows(state)
	if state and state.networks and #state.networks > 0 then
		return state.networks
	end
	if GlobalStorageSiK.Client and GlobalStorageSiK.Client.networkList then
		return GlobalStorageSiK.Client.networkList
	end
	return {}
end

---@param ui table
---@param terminal GS_TerminalUI|nil
local function selectedNetworkId(ui, state)
	local rows = networkRows(state)
	local idx = ui.netCombo and ui.netCombo.selected or 1
	local row = rows[idx]
	return row and row.networkId or nil
end

local function selectedNetworkRow(ui, state)
	local rows = networkRows(state)
	return rows[ui.netCombo and ui.netCombo.selected or 1]
end

local function locationText(row)
	local p = row and (row.lastLocation or row.anchor)
	if not p or p.x == nil or p.y == nil then return T("IGUI_GS_NetLocationUnknown") end
	return string.format("%d, %d, %d", math.floor(p.x), math.floor(p.y), math.floor(p.z or 0))
end

---@param ui table
---@param state table|nil
local function refreshSelectedNetworkInfo(ui, state)
	local row = selectedNetworkRow(ui, state)
	local info = {}
	if row then
		info[1] = T("IGUI_GS_NetCounts", row.zoneCount or 0, row.nodeCount or 0)
			.. " · " .. T("IGUI_GS_NetLastLocation", locationText(row))
		if ui.netListTitle then
			ui.netListTitle:setName(row.label or row.name or row.networkId or "?")
		end
		if ui.netStatusLbl then
			local status = row.activeTerminals == 0
				and T("IGUI_GS_NetStatusSuspended") or T("IGUI_GS_NetStatusActive")
			ui.netStatusLbl:setName("· " .. status)
			ui.netStatusLbl.r = row.activeTerminals == 0 and 0.9 or 0.35
			ui.netStatusLbl.g = row.activeTerminals == 0 and 0.7 or 0.75
			ui.netStatusLbl.b = row.activeTerminals == 0 and 0.3 or 0.45
			local w = getTextManager():MeasureStringX(UIFont.Small, ui.netStatusLbl.name or "")
			ui.netStatusLbl:setX(math.max(8, (ui._netInnerW or 200) - 14 - w))
		end
	end
	local wrapped = {}
	local infoW = math.max(120, (ui.netCombo and ui.netCombo.width or 200) - 4)
	for i = 1, #info do
		local lines = GlobalStorageSiK.SiK_UI.wrapTextLines(info[i], infoW, UIFont.Small)
		for j = 1, #lines do wrapped[#wrapped + 1] = lines[j] end
	end
	for i = 1, #(ui.netInfoLabels or {}) do
		local lbl = ui.netInfoLabels[i]
		lbl.name = wrapped[i] or ""
		lbl:setVisible(wrapped[i] ~= nil)
	end

	if ui.netUseBtn then
		-- _sikUiLocked (2026-08-26, auditoria de botones): SOLO el aspecto
		-- visual (atenuado, sin la textura gris generica de setEnable) - el
		-- gating real de clic sigue en setEnable, igual que en el resto de
		-- botones migrados a este patron esta ronda.
		local canUse = row and (row.activeTerminals or 0) > 0
		ui.netUseBtn._sikUiLocked = not canUse
		ui.netUseBtn:setEnable(canUse == true)
		ui.netUseBtn:setTooltip(canUse and T("IGUI_GS_NetUseSelectedHint")
			or T("IGUI_GS_NetReactivateViaTerminal"))
	end
end

---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param ui table
---@param y number
---@param innerW number
---@return number
function GlobalStorageSiK.TerminalNetworkList.build(scroll, terminal, ui, y, innerW)
	local pad = 8
	ui.netListBlockY = y

	local card = GlobalStorageSiK.SiK_UI.createSectionCard(pad - 4, y - 2, innerW - (pad - 4) * 2, 10)
	card._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, card)
	ui.netListCard = card

	local title = GlobalStorageSiK.SiK_UI.createSectionLabel(pad + 6, y + 2, "")
	ui.netListTitle = title
	GlobalStorageSiK.TerminalScroll.addChild(scroll, title)
	y = y + FONT_HGT_SMALL + 8
	ui.netStatusLbl = ISLabel:new(pad, ui.netListBlockY + 2, FONT_HGT_SMALL, "", 0.35, 0.75, 0.45, 1, UIFont.Small, true)
	ui.netStatusLbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.netStatusLbl)
	local selectedLabel = GlobalStorageSiK.SiK_UI.createSectionLabel(pad, y, T("IGUI_GS_NetSelected"))
	ui.netSelectedLabel = selectedLabel
	GlobalStorageSiK.TerminalScroll.addChild(scroll, selectedLabel)
	y = y + FONT_HGT_SMALL + 6

	local comboW = math.max(160, innerW - pad * 2)
	ui.netCombo = ISComboBox:new(pad, y, comboW, BTN_H + 2, terminal, nil)
	ui.netCombo:initialise()
	GlobalStorageSiK.SiK_UI.styleComboBox(ui.netCombo)
	ui.netCombo:clear()
	ui.netCombo:addOption(T("IGUI_GS_NetNoNetworks"))
	ui.netCombo._gsSyncing = false
	ui.netCombo.onChange = function()
		if ui.netCombo._gsSyncing then return end
		local state = terminal and terminal.terminalState or {}
		-- Seleccionar sirve para inspeccionar. Una red suspendida solo se
		-- reactiva instalando/vinculando un terminal físico; nunca por mirar
		-- esta lista ni mediante un reescaneo implícito.
		refreshSelectedNetworkInfo(ui, state)
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.netCombo)
	y = y + BTN_H + ROW_GAP

	ui.netInfoLabels = {}
	for i = 1, INFO_LINE_COUNT do
		local lbl = ISLabel:new(pad, y, FONT_HGT_SMALL, "", 0.72, 0.76, 0.82, 1, UIFont.Small, true)
		lbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
		ui.netInfoLabels[i] = lbl
		y = y + FONT_HGT_SMALL + 2
	end
	y = y + ROW_GAP

	local btnW = math.floor((comboW - ROW_GAP) / 2)
	ui.netUseBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad, y, btnW, BTN_H + 2, T("IGUI_GS_NetUseSelected"), scroll, function()
			local state = terminal and terminal.terminalState or {}
			local nid = selectedNetworkId(ui, state)
			if not nid then
				return
			end
			GlobalStorageSiK.NetClient.sendNetworkCommand("setActiveNetwork", nid, {})
		end, nil, true)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.netUseBtn)
	ui.netRefreshBtn = GlobalStorageSiK.SiK_UI.createButton(
		pad + btnW + ROW_GAP, y, btnW, BTN_H + 2, T("IGUI_GS_NetRefreshList"), scroll, function()
			GlobalStorageSiK.NetClient.sendCommand("getNetworkList", {})
		end, nil, true)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.netRefreshBtn)
	y = y + BTN_H + 10

	ui.netListBlockEndY = y
	ui._netInnerW = innerW

	GlobalStorageSiK.SiK_UI.resizeSectionCard(card,
		pad - 4, ui.netListBlockY - 2,
		innerW - (pad - 4) * 2, y - ui.netListBlockY + 4)

	ui.terminalRef = terminal
	return y
end

---@param ui table
---@param state table|nil
function GlobalStorageSiK.TerminalNetworkList.sync(ui, state)
	state = state or {}
	local rows = networkRows(state)
	if not ui.netCombo then
		return
	end
	ui.netCombo._gsSyncing = true
	local labels = {}
	local activeId = state.activeNetworkId or GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId
	for i = 1, #rows do
		local row = rows[i]
		local label = row.label or row.name or row.networkId or "?"
		if row.activeTerminals and row.activeTerminals == 0 then
			label = label .. " [" .. T("IGUI_GS_TerminalSuspended") .. "]"
		end
		if row.networkId == activeId then
			-- "▶" (glifo Unicode) se renderizaba como "?": la fuente del
			-- juego no lo soporta. Usamos un marcador ASCII seguro.
			label = "> " .. label
		end
		labels[i] = label
	end
	if #labels == 0 then
		labels[1] = T("IGUI_GS_NetNoNetworks")
	end
	ui.netCombo:clear()
	for i = 1, #labels do
		ui.netCombo:addOption(labels[i])
	end
	if #rows > 0 then
		local pick = 1
		for i = 1, #rows do
			if rows[i].networkId == state.networkId or rows[i].networkId == activeId then
				pick = i
				break
			end
		end
		ui.netCombo.selected = pick
	end
	ui.netCombo._gsSyncing = false

	refreshSelectedNetworkInfo(ui, state)
end

---@param scroll ISPanel
---@param ui table
---@param innerW number
function GlobalStorageSiK.TerminalNetworkList.layout(scroll, ui, innerW)
	if not ui or not ui.netCombo then
		return
	end
	local pad = 8
	ui._netInnerW = innerW
	local comboW = math.max(160, innerW - pad * 2)
	ui.netCombo:setWidth(comboW)
	local btnW = math.floor((comboW - ROW_GAP) / 2)
	if ui.netUseBtn then ui.netUseBtn:setWidth(btnW) end
	if ui.netRefreshBtn then ui.netRefreshBtn:setX(pad + btnW + ROW_GAP); ui.netRefreshBtn:setWidth(btnW) end
	if ui.netListTitle then ui.netListTitle:setX(pad + 6) end
	if ui.netSelectedLabel then ui.netSelectedLabel:setX(pad) end
	if ui.netStatusLbl then
		local w = getTextManager():MeasureStringX(UIFont.Small, ui.netStatusLbl.name or "")
		ui.netStatusLbl:setX(math.max(8, innerW - 14 - w))
	end
	if ui.netListCard and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.netListCard) then
		ui.netListCard:setX(pad - 4)
		ui.netListCard:setWidth(innerW - (pad - 4) * 2)
	end
end

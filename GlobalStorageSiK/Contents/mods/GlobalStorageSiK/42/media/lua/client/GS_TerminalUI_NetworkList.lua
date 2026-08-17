--[[
	GlobalStorageSiK - Pestaña Red: selector y gestión de redes GS
	Autor: SiK
	Fecha: 2026-06-28
	Descripción: Lista redes del jugador, sesión activa, crear/vincular terminal.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "ISUI/ISModalDialog"
require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Chrome"

GlobalStorageSiK.TerminalNetworkList = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BTN_H = FONT_HGT_SMALL + 6
local ROW_GAP = 6
local INFO_LINE_COUNT = 8

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
		info[#info + 1] = row.activeTerminals == 0
			and T("IGUI_GS_NetStatusSuspended") or T("IGUI_GS_NetStatusActive")
		info[#info + 1] = T("IGUI_GS_NetCounts", row.zoneCount or 0, row.nodeCount or 0)
		info[#info + 1] = T("IGUI_GS_NetLastLocation", locationText(row))
	end
	local wrapped = {}
	local infoW = math.max(120, (ui.netCombo and ui.netCombo.width or 200) - 4)
	for i = 1, #info do
		local lines = GlobalStorageSiK.TerminalChrome.wrapTextLines(info[i], infoW, UIFont.Small)
		for j = 1, #lines do wrapped[#wrapped + 1] = lines[j] end
	end
	for i = 1, #(ui.netInfoLabels or {}) do
		local lbl = ui.netInfoLabels[i]
		lbl.name = wrapped[i] or ""
		lbl:setVisible(wrapped[i] ~= nil)
	end

	if ui.netUseBtn then
		local canUse = row and (row.activeTerminals or 0) > 0
		ui.netUseBtn:setEnable(canUse == true)
		ui.netUseBtn:setTooltip(canUse and T("IGUI_GS_NetUseSelectedHint")
			or T("IGUI_GS_NetReactivateViaTerminal"))
	end
	if ui.netDeleteBtn then
		local canDelete = row and row.activeTerminals == 0 and row.isOwner == true
		ui.netDeleteBtn:setEnable(canDelete == true)
		ui.netDeleteBtn:setTooltip(row and row.activeTerminals ~= 0
			and T("IGUI_GS_NetworkDeleteActive")
			or (row and row.isOwner ~= true and T("IGUI_GS_NetworkDeleteOwnerOnly")
				or T("IGUI_GS_NetworkDeleteHint")))
	end
end

local function showDeleteConfirm(terminal, row)
	if not row or not row.networkId or row.activeTerminals ~= 0 or row.isOwner ~= true then return end
	local text = T("IGUI_GS_NetworkDeleteConfirm", row.label or row.name or row.networkId,
		row.zoneCount or 0, row.nodeCount or 0)
	local lines = GlobalStorageSiK.TerminalChrome.wrapTextLines(text, 380, UIFont.Small)
	local function onResult(_, button)
		if button and button.internal == "YES" then
			GlobalStorageSiK.NetClient.sendCommand("deleteSuspendedNetwork", {
				targetNetworkId = row.networkId,
			})
		end
	end
	local modal = ISModalDialog:new(0, 0, 420,
		120 + #lines * (FONT_HGT_SMALL + 2), text, true, nil, onResult, nil)
	modal:initialise()
	modal:addToUIManager()
	modal:setX(getCore():getScreenWidth() / 2 - modal.width / 2)
	modal:setY(getCore():getScreenHeight() / 2 - modal.height / 2)
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

	local card = GlobalStorageSiK.TerminalChrome.createSectionCard(pad - 4, y - 2, innerW - (pad - 4) * 2, 10)
	card._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, card)
	ui.netListCard = card

	local title = GlobalStorageSiK.TerminalChrome.createSectionLabel(pad + 6, y + 2, T("IGUI_GS_NetBlockNetworks"))
	ui.netListTitle = title
	GlobalStorageSiK.TerminalScroll.addChild(scroll, title)
	y = y + FONT_HGT_SMALL + 8

	local comboW = math.max(160, innerW - pad * 2)
	ui.netCombo = ISComboBox:new(pad, y, comboW, BTN_H + 2, terminal, nil)
	ui.netCombo:initialise()
	GlobalStorageSiK.TerminalChrome.styleComboBox(ui.netCombo)
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
	ui.netUseBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		pad, y, btnW, BTN_H + 2, T("IGUI_GS_NetUseSelected"), scroll, function()
			local state = terminal and terminal.terminalState or {}
			local nid = selectedNetworkId(ui, state)
			if not nid then
				return
			end
			GlobalStorageSiK.NetClient.sendNetworkCommand("setActiveNetwork", nid, {})
			GlobalStorageSiK.NetClient.sendNetworkCommand("rescanNetwork", nid, {
				searchQuery = terminal and terminal.getSearchQuery and terminal:getSearchQuery() or "",
			})
		end)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.netUseBtn)
	ui.netRefreshBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		pad + btnW + ROW_GAP, y, btnW, BTN_H + 2, T("IGUI_GS_NetRefreshList"), scroll, function()
			GlobalStorageSiK.NetClient.sendCommand("getNetworkList", {})
		end)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.netRefreshBtn)
	y = y + BTN_H + 10

	ui.netDeleteBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		pad, y, comboW, BTN_H + 2, T("IGUI_GS_NetworkDeleteSuspended"), scroll, function()
			showDeleteConfirm(terminal, selectedNetworkRow(ui, terminal and terminal.terminalState or {}))
		end)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.netDeleteBtn)
	y = y + BTN_H + 10
	ui.netListBlockEndY = y

	GlobalStorageSiK.TerminalChrome.resizeSectionCard(card,
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
	local comboW = math.max(160, innerW - pad * 2)
	ui.netCombo:setWidth(comboW)
	local btnW = math.floor((comboW - ROW_GAP) / 2)
	if ui.netUseBtn then ui.netUseBtn:setWidth(btnW) end
	if ui.netRefreshBtn then ui.netRefreshBtn:setX(pad + btnW + ROW_GAP); ui.netRefreshBtn:setWidth(btnW) end
	if ui.netDeleteBtn then ui.netDeleteBtn:setWidth(comboW) end
	if ui.netListTitle then ui.netListTitle:setX(pad + 6) end
	if ui.netListCard and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.netListCard) then
		ui.netListCard:setX(pad - 4)
		ui.netListCard:setWidth(innerW - (pad - 4) * 2)
	end
end

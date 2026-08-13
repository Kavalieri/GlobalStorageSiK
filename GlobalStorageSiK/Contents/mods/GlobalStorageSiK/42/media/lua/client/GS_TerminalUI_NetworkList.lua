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
require "GS_TerminalUI_Chrome"

GlobalStorageSiK.TerminalNetworkList = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BTN_H = FONT_HGT_SMALL + 6
local ROW_GAP = 6

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
		local rows = networkRows(state)
		local row = rows[ui.netCombo.selected or 1]
		if not row or not row.networkId then return end
		GlobalStorageSiK.NetClient.sendNetworkCommand("setActiveNetwork", row.networkId, {})
		GlobalStorageSiK.NetClient.sendNetworkCommand("rescanNetwork", row.networkId, {
			searchQuery = terminal and terminal.getSearchQuery and terminal:getSearchQuery() or "",
		})
	end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.netCombo)
	y = y + BTN_H + ROW_GAP

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
	-- Metodo antiguo de colocar/vincular terminal (craftear GS_TerminalUnit)
	-- retirado por completo: unico camino soportado ahora es lector+disquete
	-- sobre un ordenador ya en el mapa. Los botones se quedan (evitan
	-- reordenar el layout) pero avisan claramente en vez de no hacer nada.
	ui.netNewBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		pad + btnW + ROW_GAP, y, btnW, BTN_H + 2, T("IGUI_GS_NetCreateNew"), scroll, function()
			local p = terminal and terminal.player
			if p and p.setHaloNote then
				p:setHaloNote(T("IGUI_GS_InstallReaderCardTitle"), 220, 200, 120, 350)
			end
		end)
	y = y + BTN_H + ROW_GAP

	ui.netLinkBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		pad, y, btnW, BTN_H + 2, T("IGUI_GS_NetLinkTerminal"), scroll, function()
			local p = terminal and terminal.player
			if p and p.setHaloNote then
				p:setHaloNote(T("IGUI_GS_InstallReaderCardTitle"), 220, 200, 120, 350)
			end
		end)
	ui.netRefreshBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		pad + btnW + ROW_GAP, y, btnW, BTN_H + 2, T("IGUI_GS_NetRefreshList"), scroll, function()
			GlobalStorageSiK.NetClient.sendCommand("getNetworkList", {})
		end)
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
	if ui.netNewBtn then ui.netNewBtn:setX(pad + btnW + ROW_GAP); ui.netNewBtn:setWidth(btnW) end
	if ui.netLinkBtn then ui.netLinkBtn:setWidth(btnW) end
	if ui.netRefreshBtn then ui.netRefreshBtn:setX(pad + btnW + ROW_GAP); ui.netRefreshBtn:setWidth(btnW) end
	if ui.netListTitle then ui.netListTitle:setX(pad + 6) end
	if ui.netListCard and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.netListCard) then
		ui.netListCard:setX(pad - 4)
		ui.netListCard:setWidth(innerW - (pad - 4) * 2)
	end
end

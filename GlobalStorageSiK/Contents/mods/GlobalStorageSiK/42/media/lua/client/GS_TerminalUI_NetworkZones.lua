--[[
	GlobalStorageSiK - Pestaña Red: bloque 2 (zonas + prioridad)
	Autor: SiK
	Fecha: 2025-06-26
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISTextBox"
require "GS_I18n"
require "GS_ZonePriority"
require "GS_NetClient"
require "GS_TerminalUI_Scroll"
require "GS_SiK_UI_Table"
require "GS_SiK_UI_Core"
require "GS_SiK_UI_Controls"

GlobalStorageSiK.TerminalNetworkZones = {}

local T = GlobalStorageSiK.I18n.text
local ACTION_BTN_MAX_W = 220
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BTN_H = GlobalStorageSiK.SiK_UI.Controls.metrics().buttonHeight
local TABLE_METRICS = GlobalStorageSiK.SiK_UI.Table.metrics()
local ROW_H = math.max(TABLE_METRICS.rowHeight, BTN_H + 4)
local HEADER_H = TABLE_METRICS.headerHeight
local ROW_GAP = 6
local TAG = "_gsNetZoneTbl"
local POOL = 4
local ACTION_GAP = 4
local COUNT_RESERVE = 28
local ACTION_BTN_MAX = 120
local ARROW_BTN_MAX = 32
local COL_PRIO_X = 4
local COL_TYPE_X = 26
local COL_TYPE_W = 110
local COL_NAME_X = 142

local function zoneActionColumnWidth()
	local total = 28 * 2
	for _, key in ipairs({ "IGUI_GS_ZoneRescan", "IGUI_GS_Rename", "IGUI_GS_DeleteZone" }) do
		total = total + GlobalStorageSiK.SiK_UI.measureButtonWidth(T(key), UIFont.Small, 18, 40, ACTION_BTN_MAX)
	end
	return total + ACTION_GAP * 5
end

local ZONE_TABLE_COLUMNS = {
	{ key = "priority", titleKey = "IGUI_GS_ColPriority", width = 22, pad = 4 },
	{ key = "type", titleKey = "IGUI_GS_ColZoneType", width = COL_TYPE_W + 6, pad = 0 },
	{ key = "name", titleKey = "IGUI_GS_ColZoneName", flex = 1, minWidth = 48, pad = 0 },
	{ key = "actions", titleKey = "IGUI_GS_ColZoneActions", align = "right", width = zoneActionColumnWidth(), pad = 0 },
	{ key = "containers", titleKey = "IGUI_GS_ColContainers", align = "right",
		measureValues = { "999", T("IGUI_GS_ZoneNeverLoaded") }, measurePad = 8, pad = 0 },
}
local ZONE_TABLE_OPTIONS = { left = 0, right = 8, gap = 4 }

local function zoneTypeLabel(source)
	local key = ({
		room = "IGUI_GS_ZoneSourceRoom",
		building = "IGUI_GS_ZoneSourceBuilding",
		safehouse = "IGUI_GS_ZoneSourceSafehouse",
		selection = "IGUI_GS_ZoneSourceSelection",
		manual = "IGUI_GS_ZoneSourceManual",
	})[source or "manual"] or "IGUI_GS_ZoneSourceManual"
	return T(key)
end

local function truncate(text, maxW)
	return GlobalStorageSiK.SiK_UI.truncateText(text, maxW, UIFont.Small)
end

--- Abre cuadro para renombrar una zona.
---@param terminal GS_TerminalUI
---@param zone table
local function promptRenameZone(terminal, zone)
	if not terminal or not zone then
		return
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer and GlobalStorageSiK.NetClient.getPlayer()
	local playerNum = player and player.getPlayerNum and player:getPlayerNum() or 0
	local function onClick(_, button)
		-- ISTextBox NO pasa el texto escrito como parametro al callback (ver
		-- ISTextBox.lua: self.onclick(self.target, button, self.param1, ...) -
		-- solo reenvia los param1-4 que se le pasaron a :new(), ninguno de
		-- los cuales es el texto). Hay que leerlo de button.parent.entry,
		-- igual que ya hace correctamente el renombrado de red (ver
		-- GS_TerminalUI_NetworkStatus.lua). Bug real: antes se esperaba un
		-- tercer argumento "text" que siempre llegaba nil, asi que renombrar
		-- zona nunca hacia nada.
		if button and button.internal == "OK" and terminal.onRenameZone then
			local text = button.parent and button.parent.entry and button.parent.entry:getText()
			if text and text ~= "" then
				terminal:onRenameZone(zone.id, text)
			end
		end
	end
	local bw, bh = 300, 180
	local bx = math.floor((getCore():getScreenWidth() - bw) / 2)
	local by = math.floor((getCore():getScreenHeight() - bh) / 2)
	local box = ISTextBox:new(bx, by, bw, bh, T("IGUI_GS_ZoneRenameLabel"), zone.name or "", nil, onClick, playerNum)
	box:initialise()
	box:addToUIManager()
	box:bringToTop()
end

--- Coloca botones de acción alineados a la derecha de la fila.
---@param row ISPanel
local function layoutZoneRowActions(row)
	if not row or not row.btnUp then
		return
	end
	local w = row.width or 200
	local cols = GlobalStorageSiK.SiK_UI.Table.resolveColumns(w, ZONE_TABLE_COLUMNS, ZONE_TABLE_OPTIONS)
	local btnY = math.floor((ROW_H - BTN_H) / 2)
	local x = cols[4].finish
	local btns = { row.btnDel, row.btnRename, row.btnRescan, row.btnDown, row.btnUp }
	for i = 1, #btns do
		local btn = btns[i]
		if btn and btn.setX then
			GlobalStorageSiK.SiK_UI.fitButtonToLabel(btn)
			btn:setHeight(BTN_H)
			btn:setY(btnY)
			x = x - btn.width
			btn:setX(x)
			x = x - ACTION_GAP
		end
	end
	row._nameMaxW = math.max(48, cols[3].width - 8)
end

---@param row ISPanel
---@param title string
---@param maxW number
---@param onClick function
---@return ISButton
local function addZoneRowButton(row, title, maxW, onClick)
	local btn = GlobalStorageSiK.SiK_UI.createButton(0, 0, maxW, BTN_H, title, row, onClick)
	row:addChild(btn)
	btn:bringToTop()
	return btn
end

--- Crea fila de tabla de zonas.
---@param host ISPanel
---@param terminal GS_TerminalUI
---@param ui table
local function createZoneRow(host, terminal, ui)
	local row = ISPanel:new(0, 0, 200, ROW_H)
	row:initialise()
	row[TAG] = true
	row._gsVirtualRow = true
	row.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	row.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	row.terminal = terminal
	row.uiRef = ui

	row.btnUp = addZoneRowButton(row, "^", ARROW_BTN_MAX, function()
		if row.zoneData and row.terminal then
			row.terminal:onMoveZonePriority(row.zoneData.id, "up")
		end
	end)
	row.btnUp._sikUiPadH = 8
	row.btnUp._sikUiMinW = 28
	row.btnDown = addZoneRowButton(row, "v", ARROW_BTN_MAX, function()
		if row.zoneData and row.terminal then
			row.terminal:onMoveZonePriority(row.zoneData.id, "down")
		end
	end)
	row.btnDown._sikUiPadH = 8
	row.btnDown._sikUiMinW = 28
	row.btnRescan = addZoneRowButton(row, T("IGUI_GS_ZoneRescan"), ACTION_BTN_MAX, function()
		if row.zoneData and row.terminal and row.terminal.onRescanZone then
			row.terminal:onRescanZone(row.zoneData.id)
		end
	end)
	row.btnRename = addZoneRowButton(row, T("IGUI_GS_Rename"), ACTION_BTN_MAX, function()
		if row.zoneData and row.terminal then
			promptRenameZone(row.terminal, row.zoneData)
		end
	end)
	row.btnDel = addZoneRowButton(row, T("IGUI_GS_DeleteZone"), ACTION_BTN_MAX, function()
		if row.zoneData and row.terminal then
			row.terminal:onDeleteZone(row.zoneData.id)
		end
	end)

	row.prerender = function(self)
		ISPanel.prerender(self)
		local data = self.zoneData
		if not data then
			return
		end
		GlobalStorageSiK.SiK_UI.drawTableRowBackground(self, self.rowIndex, self:isMouseOver(), false)
		local w = self.width
		local yMid = math.floor((self.height - FONT_HGT_SMALL) / 2)
		local pal = GlobalStorageSiK.SiK_UI.PALETTE
		local cols = GlobalStorageSiK.SiK_UI.Table.resolveColumns(w, ZONE_TABLE_COLUMNS, ZONE_TABLE_OPTIONS)
		local nameMaxW = self._nameMaxW or math.max(48, cols[3].width - 8)
		self:drawText(tostring(data.priority or T("IGUI_GS_PunctuationEmDash")), cols[1].x + cols[1].pad, yMid, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		self:drawText(truncate(zoneTypeLabel(data.source), cols[2].width), cols[2].x, yMid, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small)
		self:drawText(truncate(data.name or "?", nameMaxW), cols[3].x, yMid, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
		if (data.nodeCount or 0) == 0 and data.neverLoaded then
			-- Zona nunca escaneada con sus baldosas cargadas en memoria (RV
			-- interior, sotano de mods como Excavation, etc.): "0" confirmado
			-- vacio y "0" nunca-verificado son cosas MUY distintas para el
			-- jugador - sin esto, una zona en un interior lejano parece vacia
			-- para siempre aunque tenga contenedores reales dentro.
			self:drawTextRight(T("IGUI_GS_ZoneNeverLoaded"), cols[5].finish, yMid, 0.9, 0.75, 0.35, 1, UIFont.Small)
		else
			self:drawTextRight(tostring(data.nodeCount or 0), cols[5].finish, yMid, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		end
	end
	return row
end

---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param ui table
---@param y number
---@param innerW number
---@return number
function GlobalStorageSiK.TerminalNetworkZones.build(scroll, terminal, ui, y, innerW)
	local pad = 8
	ui.block2Y = y

	local card = GlobalStorageSiK.SiK_UI.createSectionCard(pad - 4, y - 2, innerW - (pad - 4) * 2, 10)
	card._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, card)
	ui.block2Card = card

	local title = GlobalStorageSiK.SiK_UI.createSectionLabel(pad + 6, y + 2, T("IGUI_GS_SectionZones"))
	title._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, title)
	y = y + FONT_HGT_SMALL + 6

	local hint = GlobalStorageSiK.SiK_UI.createHintLabel(pad + 6, y, T("IGUI_GS_ZonesPriorityHint"))
	hint._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, hint)
	y = y + FONT_HGT_SMALL + 8

	local btnH = BTN_H
	local roomTitle = T("IGUI_GS_CreateRoomZone")
	local structTitle = T("IGUI_GS_CreateStructureZone")
	local selectTitle = T("IGUI_GS_CreateSelectionZone")
	local roomW = GlobalStorageSiK.SiK_UI.measureButtonWidth(roomTitle, UIFont.Small, 18, 80, ACTION_BTN_MAX_W)
	local structW = GlobalStorageSiK.SiK_UI.measureButtonWidth(structTitle, UIFont.Small, 18, 80, ACTION_BTN_MAX_W)
	local selectW = GlobalStorageSiK.SiK_UI.measureButtonWidth(selectTitle, UIFont.Small, 18, 80, ACTION_BTN_MAX_W)
	ui.roomZoneBtn = GlobalStorageSiK.SiK_UI.createButton(pad, y, ACTION_BTN_MAX_W, btnH, roomTitle, scroll, function()
		terminal:onCreateRoomZone()
	end, nil, true)
	ui.roomZoneBtn._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.roomZoneBtn)
	roomW = ui.roomZoneBtn.width
	ui.structureZoneBtn = GlobalStorageSiK.SiK_UI.createButton(pad + roomW + ROW_GAP, y, ACTION_BTN_MAX_W, btnH, structTitle, scroll, function()
		terminal:onCreateStructureZone()
	end, nil, true)
	ui.structureZoneBtn._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.structureZoneBtn)
	structW = ui.structureZoneBtn.width
	ui.selectZoneBtn = GlobalStorageSiK.SiK_UI.createButton(pad + roomW + ROW_GAP + structW + ROW_GAP, y, ACTION_BTN_MAX_W, btnH, selectTitle, scroll, function()
		terminal:onCreateSelectionZone()
	end, nil, true)
	ui.selectZoneBtn._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.selectZoneBtn)
	y = y + btnH + 10

	ui.zoneTableHost = ISPanel:new(pad, y, innerW - pad * 2, HEADER_H + ROW_H + 10)
	ui.zoneTableHost:initialise()
	ui.zoneTableHost.drawBackground = false
	ui.zoneTableHost._gsNetStatic = true
	ui.zoneTableHost.clipChildren = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.zoneTableHost)

	ui.zoneHeader = ISPanel:new(0, 0, ui.zoneTableHost.width, HEADER_H)
	ui.zoneHeader:initialise()
	ui.zoneHeader.prerender = function(self)
		ISPanel.prerender(self)
		GlobalStorageSiK.SiK_UI.Table.drawHeader(self, ZONE_TABLE_COLUMNS, nil, true,
			2, UIFont.Small, ZONE_TABLE_OPTIONS)
	end
	GlobalStorageSiK.SiK_UI.Table.attachHeaderResize(
		ui.zoneHeader, ZONE_TABLE_COLUMNS, ZONE_TABLE_OPTIONS)
	ui.zoneTableHost:addChild(ui.zoneHeader)

	ui.zoneRowPool = {}
	for i = 1, POOL do
		local row = createZoneRow(ui.zoneTableHost, terminal, ui)
		row:setVisible(false)
		ui.zoneTableHost:addChild(row)
		ui.zoneRowPool[i] = row
	end

	ui.zoneTableY = y
	y = y + ui.zoneTableHost:getHeight() + 8
	ui.block2EndY = y
	GlobalStorageSiK.SiK_UI.resizeSectionCard(card,
		pad - 4, ui.block2Y - 2,
		innerW - (pad - 4) * 2, y - ui.block2Y + 4)
	ui.lastZoneFp = ""
	ui.terminalRef = terminal
	return y
end

--- Posiciona todas las filas de zonas (sin scroll interno).
---@param ui table
function GlobalStorageSiK.TerminalNetworkZones.layoutRows(ui)
	local zones = ui and ui.zoneRows
	local host = ui and ui.zoneTableHost
	if not host or not zones or not ui.zoneRowPool then
		return
	end
	local tableW = host.width or 200
	local needed = #zones
	local term = ui.terminalRef
	while #ui.zoneRowPool < needed do
		local row = createZoneRow(host, term, ui)
		row:setVisible(false)
		host:addChild(row)
		ui.zoneRowPool[#ui.zoneRowPool + 1] = row
	end
	for i = 1, #ui.zoneRowPool do
		local row = ui.zoneRowPool[i]
		if i <= needed then
			row.zoneData = zones[i]
			row.rowIndex = i
			row:setX(0)
			row:setY(HEADER_H + 2 + (i - 1) * ROW_H)
			row:setWidth(tableW)
			row:setHeight(ROW_H)
			layoutZoneRowActions(row)
			row:setVisible(true)
		else
			row.zoneData = nil
			row:setVisible(false)
		end
	end
	local bodyH = math.max(ROW_H, needed * ROW_H)
	host:setHeight(HEADER_H + 2 + bodyH + 8)
	if ui.zoneTableY then
		ui.block2EndY = ui.zoneTableY + host:getHeight() + 8
		if ui.block2Card and ui.block2Y then
			ui.block2Card:setHeight(math.max(24, ui.block2EndY - ui.block2Y + 4))
		end
	end
end

---@deprecated Usar layoutRows (zonas sin scroll interno).
---@param ui table
function GlobalStorageSiK.TerminalNetworkZones.updateVirtualRows(ui)
	GlobalStorageSiK.TerminalNetworkZones.layoutRows(ui)
end

---@param ui table
---@param zones table[]
function GlobalStorageSiK.TerminalNetworkZones.sync(ui, zones)
	zones = zones or {}
	GlobalStorageSiK.ZonePriority.sortSerialized(zones)
	local fp = ""
	for i = 1, #zones do
		local z = zones[i]
		fp = fp .. z.id .. ":" .. tostring(z.priority) .. ":" .. tostring(z.nodeCount) .. ":" .. tostring(z.neverLoaded) .. "|"
	end
	if ui.lastZoneFp == fp then
		GlobalStorageSiK.TerminalNetworkZones.layoutRows(ui)
		return
	end
	ui.lastZoneFp = fp
	ui.zoneRows = zones

	if not ui.zoneTableHost then return end
	GlobalStorageSiK.TerminalNetworkZones.layoutRows(ui)
end

---@param scroll ISPanel
---@param ui table
---@param innerW number
function GlobalStorageSiK.TerminalNetworkZones.layout(scroll, ui, innerW)
	if not ui or not ui.zoneTableHost then return end
	local pad = 8
	local tableW = innerW - pad * 2
	ui.zoneTableHost:setWidth(tableW)
	if ui.zoneHeader then ui.zoneHeader:setWidth(tableW) end
	GlobalStorageSiK.TerminalNetworkZones.layoutRows(ui)
	local roomW = ui.roomZoneBtn and ui.roomZoneBtn.width or 80
	local structW = ui.structureZoneBtn and ui.structureZoneBtn.width or 80
	if ui.structureZoneBtn then
		ui.structureZoneBtn:setX(pad + roomW + ROW_GAP)
	end
	if ui.selectZoneBtn and ui.structureZoneBtn then
		ui.selectZoneBtn:setX(pad + roomW + ROW_GAP + structW + ROW_GAP)
	end
	if ui.zoneTableHost and ui.zoneTableY then
		GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.zoneTableHost, ui.zoneTableY)
		ui.block2EndY = ui.zoneTableY + ui.zoneTableHost:getHeight() + 8
	end
	if ui.block2Card and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.block2Card) then
		ui.block2Card:setX(pad - 4)
		ui.block2Card:setWidth(innerW - (pad - 4) * 2)
		if ui.block2EndY and ui.block2Y then
			ui.block2Card:setHeight(math.max(24, ui.block2EndY - ui.block2Y + 4))
		end
	end
end

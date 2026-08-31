--[[
	GlobalStorageSiK - Pestaña Red: bloque terminales registrados
	Autor: SiK
	Fecha: 2025-06-28
	Descripción: Tabla de terminales con coordenadas, rol y estado físico.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalRegistry"
require "GS_TerminalUI_Scroll"
require "GS_SiK_UI_Core"
require "GS_TerminalCatalog"
require "GS_TerminalUI_TerminalEditor"
require "GS_SiK_UI_Table"
require "GS_SiK_UI_Controls"

GlobalStorageSiK.TerminalNetworkTerminals = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local TABLE_METRICS = GlobalStorageSiK.SiK_UI.Table.metrics()
local ROW_H = TABLE_METRICS.rowHeight
local HEADER_H = TABLE_METRICS.headerHeight
local ROW_GAP = 6
-- Nombre es la PRIMERA columna (a peticion del usuario), luego
-- coordenadas/rol/estado. El descriptor flexible permite que el mismo
-- divisor comun de SiK_UI.Table ajuste cabecera y filas sin una geometria
-- paralela solo para Administracion.
local TERMINAL_TABLE_COLUMNS = {
	{ key = "name", titleKey = "IGUI_GS_ColTerminalName", flex = 1, minWidth = 130, pad = 6 },
	{ key = "coords", titleKey = "IGUI_GS_ColTerminalCoords", flex = 1, minWidth = 130, pad = 6 },
	{ key = "role", titleKey = "IGUI_GS_ColTerminalRole", width = 110, pad = 6 },
	{ key = "status", titleKey = "IGUI_GS_ColTerminalStatus", width = 100, align = "right", pad = 6 },
}
local TERMINAL_TABLE_OPTIONS = { left = 0, right = 0, gap = 8 }

---@param row table|nil
---@return string
local function coordsLabel(row)
	if not row then
		return T("IGUI_GS_PunctuationEmDash")
	end
	return string.format("%d, %d, %d", row.x or 0, row.y or 0, row.z or 0)
end

---@param row table|nil
---@return string
local function nameLabel(row)
	if not row or not row.label or row.label == "" then
		return T("IGUI_GS_PunctuationEmDash")
	end
	return row.label
end

---@param row table|nil
---@return string
local function statusLabel(row)
	if not row then
		return T("IGUI_GS_PunctuationEmDash")
	end
	if row.unknown then
		return T("IGUI_GS_TerminalUnverified")
	end
	if row.missing or row.present == false then
		return T("IGUI_GS_TerminalMissingPhys")
	end
	if row.suspended then
		return T("IGUI_GS_TerminalSuspended")
	end
	return T("IGUI_GS_TerminalPresentPhys")
end

---@param row table|nil
---@return number
---@return number
---@return number
local function statusColor(row)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	if row and row.unknown then
		return pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3]
	end
	if row and (row.missing or row.present == false) then
		return pal.statusDanger[1], pal.statusDanger[2], pal.statusDanger[3]
	end
	if row and row.suspended then
		return pal.statusWarn[1], pal.statusWarn[2], pal.statusWarn[3]
	end
	return pal.statusOk[1], pal.statusOk[2], pal.statusOk[3]
end

---@param row table|nil
---@return string
local function roleLabel(row)
	if row and row.controller then
		return T("IGUI_GS_TerminalController")
	end
	return T("IGUI_GS_TerminalSecondary")
end

--- Elimina permanentemente un terminal (registro por coordenadas) de la red.
--- Sirve tanto para "purgar" una entrada ausente/suspendida (limpieza) como
--- para "desinstalar" un terminal presente y sano a petición del jugador -
--- el ordenador físico NO se toca, solo se deja de reconocer esa posición
--- como terminal (ver comentario de limpieza de ModData en GS_Server.lua,
--- comando removeTerminal).
---@param terminal GS_TerminalUI
---@param row table
local function purgeTerminal(terminal, row)
	if not row then return end
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("removeTerminal", {
			x = row.x,
			y = row.y,
			z = row.z,
			gsnNetworkId = terminal and terminal.terminalState and terminal.terminalState.networkId,
		})
	end
	if terminal and terminal.refreshNetworkPanel then
		terminal:refreshNetworkPanel()
	end
end

---@param host ISPanel
---@param terminal GS_TerminalUI
---@param ui table
---@return ISPanel
local function newTerminalTableRow(host, terminal, ui)
	local itemRow = ISPanel:new(0, 0, host.width, ROW_H)
	itemRow:initialise()
	itemRow.drawBackground = false
	itemRow.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	itemRow.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	itemRow.prerender = function(self)
		ISPanel.prerender(self)
		GlobalStorageSiK.SiK_UI.drawTableRowBackground(self, self.rowIndex, self:isMouseOver(), false)
		local data = self.terminalData
		if not data then
			return
		end
		local cols = GlobalStorageSiK.SiK_UI.Table.resolveColumns(
			self.width, TERMINAL_TABLE_COLUMNS, TERMINAL_TABLE_OPTIONS)
		local pal = GlobalStorageSiK.SiK_UI.PALETTE
		local sr, sg, sb = statusColor(data)
		local nameMaxW = cols[1].width - cols[1].pad * 2
		self:drawText(GlobalStorageSiK.SiK_UI.truncateText(nameLabel(data), nameMaxW, UIFont.Small),
			cols[1].x + cols[1].pad, 2, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
		self:drawText(GlobalStorageSiK.SiK_UI.truncateText(coordsLabel(data), cols[2].width - cols[2].pad * 2, UIFont.Small),
			cols[2].x + cols[2].pad, 2, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small)
		self:drawText(GlobalStorageSiK.SiK_UI.truncateText(roleLabel(data), cols[3].width - cols[3].pad * 2, UIFont.Small),
			cols[3].x + cols[3].pad, 2, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small)
		self:drawTextRight(statusLabel(data), cols[4].finish - cols[4].pad, 2, sr, sg, sb, 1, UIFont.Small)
	end
-- Un clic en la fila abre SIEMPRE el editor completo (renombrar, marcar
	-- como principal, suspender, eliminar) - a peticion del usuario, en vez de
	-- ir directo a un dialogo de confirmacion de baja sin mas opciones. Las
	-- entradas ya rotas/ausentes se purgan solas (nada que configurar en una
	-- entrada que ya no existe de verdad).
	itemRow.onMouseUp = function(self, x, y)
		local data = self.terminalData
		if not data or not terminal then
			return false
		end
		if data.missing or data.present == false then
			purgeTerminal(terminal, data)
		else
			GlobalStorageSiK.TerminalTerminalEditor.open(terminal, data)
		end
		return true
	end
	return itemRow
end

---@param row ISPanel
---@param data table|nil
---@param dataIndex number|nil
local function bindTerminalRow(row, data, dataIndex)
	row.terminalData = data
	row.rowIndex = dataIndex
end

---@param ui table
---@param tableW number
local function layoutTerminalTable(ui, tableW)
	local tableList = ui and ui.termTable
	if not tableList then return end
	local rows = ui.terminalRows or {}
	local bodyH = math.max(ROW_H, #rows * ROW_H)
	GlobalStorageSiK.TerminalScroll.resize(tableList, tableW, bodyH + 16)
	tableList:setConfig(ROW_H, 0)
	tableList:setDataSource(rows, true)
	tableList:setVisible(#rows > 0)

	local rect = GlobalStorageSiK.TerminalScroll.contentRect(tableList)
	if ui.termHeader then
		ui.termHeader:setX((tableList.x or 0) + rect.x)
		ui.termHeader:setWidth(rect.w)
	end
	if ui.termEmptyLbl then
		ui.termEmptyLbl:setVisible(#rows == 0)
	end
	ui.termBlockEndY = (ui.termTableY or 0) + HEADER_H + 2
		+ (#rows > 0 and tableList:getHeight() or (ROW_H + 16)) + 8
end

--- Construye bloque de gestión de terminales.
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param ui table
---@param y number
---@param innerW number
---@return number
function GlobalStorageSiK.TerminalNetworkTerminals.build(scroll, terminal, ui, y, innerW)
	local pad = 8
	ui.termBlockY = y
	-- Gestión de terminales es una tabla, no una tarjeta dentro de otra tarjeta.
	-- El antiguo createSectionCard introducía un marco/acento propio que Almacén,
	-- Zonas y Nodos no usan, aunque compartieran drawHeader/drawTableRowBackground.
	-- Dejar el host neutro hace que las cuatro superficies compongan el mismo
	-- componente SiK_UI.Table, sin una segunda envoltura visual local.
	ui.termBlockCard = nil

	local header = GlobalStorageSiK.SiK_UI.Controls.blockHeader(nil, {
		x = pad, y = y + pad, w = innerW - pad * 2,
		text = T("IGUI_GS_NetBlockTerminals"),
		tooltip = T("IGUI_GS_NetBlockTerminals"), target = scroll,
	})
	ui.termBlockHeader = header
	ui.termBlockTitle = header.title
	if header.info then GlobalStorageSiK.TerminalScroll.addChild(scroll, header.info) end
	GlobalStorageSiK.TerminalScroll.addChild(scroll, header.title)
	y = y + pad + header.height

	ui.termTableY = y
	local tableHeader = ISPanel:new(pad, y, innerW - pad * 2, HEADER_H)
	tableHeader:initialise()
	tableHeader.prerender = function(self)
		ISPanel.prerender(self)
		GlobalStorageSiK.SiK_UI.Table.drawHeader(self, TERMINAL_TABLE_COLUMNS, nil, true,
			2, UIFont.Small, TERMINAL_TABLE_OPTIONS)
	end
	GlobalStorageSiK.SiK_UI.Table.attachHeaderResize(
		tableHeader, TERMINAL_TABLE_COLUMNS, TERMINAL_TABLE_OPTIONS)
	ui.termHeader = tableHeader
	GlobalStorageSiK.TerminalScroll.addChild(scroll, tableHeader)

	local host = GlobalStorageSiK.TerminalScroll.childHost(scroll)
	ui.termTable = GlobalStorageSiK.SiK_UI.Table.createVirtual(
		host, pad, y + HEADER_H + 2, innerW - pad * 2, ROW_H + 16,
		ROW_H, 0, TERMINAL_TABLE_COLUMNS,
		function() return newTerminalTableRow(host, terminal, ui) end,
		bindTerminalRow, TERMINAL_TABLE_OPTIONS)
	ui.termTable.onMouseWheel = function(_, del)
		return scroll:onMouseWheel(del)
	end

	local _tpal = GlobalStorageSiK.SiK_UI.PALETTE
	ui.termEmptyLbl = ISLabel:new(pad, y + HEADER_H + 4, FONT_HGT_SMALL, T("IGUI_GS_NoTerminalsRegistered"), _tpal.textMuted[1], _tpal.textMuted[2], _tpal.textMuted[3], 1, UIFont.Small, true)
	ui.termEmptyLbl:initialise()
	ui.termEmptyLbl:setVisible(false)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.termEmptyLbl)

	y = y + HEADER_H + 2 + ui.termTable:getHeight() + pad
	ui.termBlockEndY = y
	ui.lastTermFp = ""
	ui.terminalRef = terminal
	return y
end

--- Posiciona filas de terminales.
---@param ui table
function GlobalStorageSiK.TerminalNetworkTerminals.layoutRows(ui)
	local tableList = ui and ui.termTable
	if not tableList then return end
	layoutTerminalTable(ui, tableList:getWidth())
end

---@param ui table
---@param state table|nil
function GlobalStorageSiK.TerminalNetworkTerminals.sync(ui, state)
	state = state or {}
	local rows = state.terminals or {}
	if #rows == 0 and state.networkId and GlobalStorageSiK.TerminalCatalog then
		rows = GlobalStorageSiK.TerminalCatalog.serializeRows(state.networkId)
	elseif #rows > 0 and GlobalStorageSiK.TerminalCatalog then
		local normalized = {}
		for i = 1, #rows do
			local row = rows[i]
			if row.unknown == nil and row.present == false and row.missing ~= true then
				row.unknown = true
				row.missing = false
			end
			normalized[#normalized + 1] = row
		end
		rows = normalized
	end
	local fp = ""
	for i = 1, #rows do
		local row = rows[i]
		fp = fp .. tostring(row.x) .. "," .. tostring(row.y) .. "," .. tostring(row.z)
			.. ":" .. tostring(row.controller) .. ":" .. tostring(row.missing) .. ":" .. tostring(row.label) .. "|"
	end
	if ui.lastTermFp == fp then
		GlobalStorageSiK.TerminalNetworkTerminals.layoutRows(ui)
		return
	end
	ui.lastTermFp = fp
	ui.terminalRows = rows
	if not ui.termTable then
		return
	end
	GlobalStorageSiK.TerminalNetworkTerminals.layoutRows(ui)
end

---@param scroll ISPanel
---@param ui table
---@param innerW number
function GlobalStorageSiK.TerminalNetworkTerminals.layout(scroll, ui, innerW)
	if not ui or not ui.termTable then
		return
	end
	local pad = 8
	local SECTION_GAP = 10

	-- Reposicionar el bloque entero si block2EndY cambió (zonas crecieron/encogieron)
	local newBlockY = ui.block2EndY and (ui.block2EndY + SECTION_GAP) or ui.termBlockY
	if newBlockY and ui.termBlockY and math.abs(newBlockY - ui.termBlockY) > 0.5 then
		local delta = newBlockY - ui.termBlockY
		ui.termBlockY = newBlockY
		ui.termTableY = (ui.termTableY or newBlockY) + delta
		ui.termBlockEndY = (ui.termBlockEndY or newBlockY) + delta
		if ui.termBlockCard and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.termBlockCard) then
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.termBlockCard, newBlockY)
		end
		if ui.termBlockHeader then
			if ui.termBlockHeader.info then
				GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.termBlockHeader.info, newBlockY + pad)
			end
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.termBlockHeader.title, newBlockY + pad)
		end
		if GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.termHeader) then
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.termHeader, ui.termTableY)
		end
		if GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.termTable) then
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.termTable, ui.termTableY + HEADER_H + 2)
		end
		if ui.termEmptyLbl and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.termEmptyLbl) then
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.termEmptyLbl, ui.termTableY + HEADER_H + 4)
		end
	end

	local tableW = innerW - pad * 2
	if ui.termBlockHeader then
		if ui.termBlockHeader.info then ui.termBlockHeader.info:setX(pad) end
		local titleX = pad
		if ui.termBlockHeader.info then
			titleX = pad + ui.termBlockHeader.info:getWidth() + ROW_GAP
		end
		ui.termBlockHeader.title:setX(titleX)
	end
	ui.termTable:setX(pad)
	ui.termTable:setY((ui.termTableY or 0) + HEADER_H + 2)
	layoutTerminalTable(ui, tableW)
	if ui.termBlockCard and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.termBlockCard) then
		ui.termBlockCard:setX(0)
		ui.termBlockCard:setWidth(innerW)
		if ui.termBlockEndY and ui.termBlockY then
			ui.termBlockCard:setHeight(math.max(24, ui.termBlockEndY - ui.termBlockY + 4))
		end
	end
end

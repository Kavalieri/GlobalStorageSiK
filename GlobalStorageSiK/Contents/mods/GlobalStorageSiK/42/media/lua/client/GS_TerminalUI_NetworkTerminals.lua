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
local POOL = 6
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
local function createTerminalRow(host, terminal, ui)
	local row = ISPanel:new(0, 0, host.width, ROW_H)
	row:initialise()
	row.drawBackground = false
	row.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	row.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	row.prerender = function(self)
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
	row.onMouseUp = function(self, x, y)
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
	return row
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

	local title = GlobalStorageSiK.SiK_UI.Controls.sectionTitle(nil, {
		x = pad, y = y + pad, text = T("IGUI_GS_NetBlockTerminals"),
	})
	ui.termBlockTitle = title
	GlobalStorageSiK.TerminalScroll.addChild(scroll, title)
	y = y + pad + FONT_HGT_SMALL + 8

	ui.termTableHost = ISPanel:new(pad, y, innerW - pad * 2, HEADER_H + ROW_H + 10)
	ui.termTableHost:initialise()
	ui.termTableHost.drawBackground = false
	ui.termTableHost._gsNetStatic = true
	ui.termTableHost.clipChildren = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.termTableHost)

	ui.termHeader = ISPanel:new(0, 0, ui.termTableHost.width, HEADER_H)
	ui.termHeader:initialise()
	ui.termHeader.prerender = function(self)
		ISPanel.prerender(self)
		GlobalStorageSiK.SiK_UI.Table.drawHeader(self, TERMINAL_TABLE_COLUMNS, nil, true,
			2, UIFont.Small, TERMINAL_TABLE_OPTIONS)
	end
	GlobalStorageSiK.SiK_UI.Table.attachHeaderResize(
		ui.termHeader, TERMINAL_TABLE_COLUMNS, TERMINAL_TABLE_OPTIONS)
	ui.termTableHost:addChild(ui.termHeader)

	ui.termRowPool = {}
	for i = 1, POOL do
		local row = createTerminalRow(ui.termTableHost, terminal, ui)
		row:setVisible(false)
		ui.termTableHost:addChild(row)
		ui.termRowPool[i] = row
	end

	local _tpal = GlobalStorageSiK.SiK_UI.PALETTE
	ui.termEmptyLbl = ISLabel:new(pad, y + HEADER_H + 4, FONT_HGT_SMALL, T("IGUI_GS_NoTerminalsRegistered"), _tpal.textMuted[1], _tpal.textMuted[2], _tpal.textMuted[3], 1, UIFont.Small, true)
	ui.termEmptyLbl:initialise()
	ui.termEmptyLbl:setVisible(false)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.termEmptyLbl)

	ui.termTableY = y
	y = y + ui.termTableHost:getHeight() + pad
	ui.termBlockEndY = y
	ui.lastTermFp = ""
	ui.terminalRef = terminal
	return y
end

--- Posiciona filas de terminales.
---@param ui table
function GlobalStorageSiK.TerminalNetworkTerminals.layoutRows(ui)
	local rows = ui and ui.terminalRows
	local host = ui and ui.termTableHost
	if not host or not rows or not ui.termRowPool then
		return
	end
	local tableW = host.width or 200
	local needed = #rows
	local term = ui.terminalRef
	while #ui.termRowPool < needed do
		local row = createTerminalRow(host, term, ui)
		row:setVisible(false)
		host:addChild(row)
		ui.termRowPool[#ui.termRowPool + 1] = row
	end
	for i = 1, #ui.termRowPool do
		local row = ui.termRowPool[i]
		if i <= needed then
			row.terminalData = rows[i]
			row.rowIndex = i
			row:setX(0)
			row:setY(HEADER_H + 2 + (i - 1) * ROW_H)
			row:setWidth(tableW)
			row:setHeight(ROW_H)
			row:setVisible(true)
		else
			row.terminalData = nil
			row:setVisible(false)
		end
	end
	local bodyH = math.max(ROW_H, needed * ROW_H)
	host:setHeight(HEADER_H + 2 + bodyH + 8)
	host:setVisible(needed > 0)
	if ui.termEmptyLbl then
		ui.termEmptyLbl:setVisible(needed == 0)
		if ui.termTableY then
			ui.termEmptyLbl:setY(ui.termTableY + HEADER_H + 4)
		end
	end
	if ui.termTableY then
		ui.termBlockEndY = ui.termTableY + host:getHeight() + 8
		if ui.termBlockCard and ui.termBlockY then
			ui.termBlockCard:setHeight(math.max(24, ui.termBlockEndY - ui.termBlockY + 4))
		end
	end
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
	if not ui.termTableHost then
		return
	end
	GlobalStorageSiK.TerminalNetworkTerminals.layoutRows(ui)
end

---@param scroll ISPanel
---@param ui table
---@param innerW number
function GlobalStorageSiK.TerminalNetworkTerminals.layout(scroll, ui, innerW)
	if not ui or not ui.termTableHost then
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
		if ui.termBlockTitle and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.termBlockTitle) then
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.termBlockTitle, newBlockY + pad)
		end
		if GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.termTableHost) then
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.termTableHost, ui.termTableY)
		end
		if ui.termEmptyLbl and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.termEmptyLbl) then
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.termEmptyLbl, ui.termTableY + HEADER_H + 4)
		end
	end

	local tableW = innerW - pad * 2
	ui.termTableHost:setWidth(tableW)
	if ui.termHeader then
		ui.termHeader:setWidth(tableW)
	end
	if ui.termBlockTitle then
		ui.termBlockTitle:setX(pad)
	end
	GlobalStorageSiK.TerminalNetworkTerminals.layoutRows(ui)
	if ui.termBlockCard and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.termBlockCard) then
		ui.termBlockCard:setX(0)
		ui.termBlockCard:setWidth(innerW)
		if ui.termBlockEndY and ui.termBlockY then
			ui.termBlockCard:setHeight(math.max(24, ui.termBlockEndY - ui.termBlockY + 4))
		end
	end
end

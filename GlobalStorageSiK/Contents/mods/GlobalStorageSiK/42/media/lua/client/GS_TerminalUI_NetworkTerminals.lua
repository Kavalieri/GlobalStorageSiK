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
require "GS_TerminalUI_Chrome"
require "GS_TerminalCatalog"
require "ISUI/ISModalDialog"
require "GS_TerminalUI_TerminalEditor"

GlobalStorageSiK.TerminalNetworkTerminals = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BTN_H = FONT_HGT_SMALL + 6
local ROW_H = BTN_H + 4
local HEADER_H = FONT_HGT_SMALL + 8
local ROW_GAP = 6
local POOL = 6
-- Nombre es la PRIMERA columna (a peticion del usuario), luego coordenadas/rol/estado.
local COL_NAME_FRAC   = 0.0   -- empieza en x=4 (absoluto)
local COL_COORD_FRAC  = 0.30
local COL_ROLE_FRAC   = 0.58
local COL_STATUS_FRAC = 0.80

---@param row table|nil
---@return string
local function coordsLabel(row)
	if not row then
		return "—"
	end
	return string.format("%d, %d, %d", row.x or 0, row.y or 0, row.z or 0)
end

---@param row table|nil
---@return string
local function nameLabel(row)
	if not row or not row.label or row.label == "" then
		return "—"
	end
	return row.label
end

---@param row table|nil
---@return string
local function statusLabel(row)
	if not row then
		return "—"
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
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE
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
		GlobalStorageSiK.TerminalChrome.drawTableRowBackground(self, self.rowIndex, self:isMouseOver(), false)
		local data = self.terminalData
		if not data then
			return
		end
local w = self.width
		local col0 = 4
		local colCoord = math.floor(w * COL_COORD_FRAC)
		local col1 = math.floor(w * COL_ROLE_FRAC)
		local col2 = math.floor(w * COL_STATUS_FRAC)
		local pal = GlobalStorageSiK.TerminalChrome.PALETTE
		local sr, sg, sb = statusColor(data)
		local nameMaxW = colCoord - col0 - 6
		self:drawText(GlobalStorageSiK.TerminalChrome.truncateText(nameLabel(data), nameMaxW, UIFont.Small),
			col0, 2, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
		self:drawText(coordsLabel(data), colCoord, 2, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small)
		self:drawText(roleLabel(data), col1, 2, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small)
		self:drawText(statusLabel(data), col2, 2, sr, sg, sb, 1, UIFont.Small)
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

	local card = GlobalStorageSiK.TerminalChrome.createSectionCard(pad - 4, y - 2, innerW - (pad - 4) * 2, 10)
	card._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, card)
	ui.termBlockCard = card

	local title = GlobalStorageSiK.TerminalChrome.createSectionLabel(pad + 6, y + 2, T("IGUI_GS_NetBlockTerminals"))
	ui.termBlockTitle = title
	GlobalStorageSiK.TerminalScroll.addChild(scroll, title)
	y = y + FONT_HGT_SMALL + 8

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
		GlobalStorageSiK.TerminalChrome.drawTableHeaderLine(self)
local w = self.width
		local colCoord = math.floor(w * COL_COORD_FRAC)
		local col1 = math.floor(w * COL_ROLE_FRAC)
		local col2 = math.floor(w * COL_STATUS_FRAC)
		local pal = GlobalStorageSiK.TerminalChrome.PALETTE
		self:drawText(T("IGUI_GS_ColTerminalName"), 4, 2, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		self:drawText(T("IGUI_GS_ColTerminalCoords"), colCoord, 2, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		self:drawText(T("IGUI_GS_ColTerminalRole"), col1, 2, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		self:drawText(T("IGUI_GS_ColTerminalStatus"), col2, 2, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
	end
	ui.termTableHost:addChild(ui.termHeader)

	ui.termRowPool = {}
	for i = 1, POOL do
		local row = createTerminalRow(ui.termTableHost, terminal, ui)
		row:setVisible(false)
		ui.termTableHost:addChild(row)
		ui.termRowPool[i] = row
	end

	local _tpal = GlobalStorageSiK.TerminalChrome.PALETTE
	ui.termEmptyLbl = ISLabel:new(pad, y + HEADER_H + 4, FONT_HGT_SMALL, T("IGUI_GS_NoTerminalsRegistered"), _tpal.textMuted[1], _tpal.textMuted[2], _tpal.textMuted[3], 1, UIFont.Small, true)
	ui.termEmptyLbl:initialise()
	ui.termEmptyLbl:setVisible(false)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.termEmptyLbl)

	ui.termTableY = y
	y = y + ui.termTableHost:getHeight() + 4

	ui.termPurgeBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		pad, y, math.min(240, innerW - pad * 2), BTN_H + 2, T("IGUI_GS_TerminalPurgeMissing"), scroll, function()
			local rows = ui.terminalRows or {}
			for i = 1, #rows do
				local r = rows[i]
				if r.missing or r.suspended or r.present == false then
					purgeTerminal(terminal, r)
				end
			end
		end)
	ui.termPurgeBtn._gsNetStatic = true
	ui.termPurgeBtn:setVisible(false)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.termPurgeBtn)

	y = y + BTN_H + 10
	ui.termBlockEndY = y
	GlobalStorageSiK.TerminalChrome.resizeSectionCard(card,
		pad - 4, ui.termBlockY - 2,
		innerW - (pad - 4) * 2, y - ui.termBlockY + 4)
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
	local hasMissing = false
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
			local r = rows[i]
			if r.missing or r.suspended or r.present == false then
				hasMissing = true
			end
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
	if ui.termPurgeBtn then
		ui.termPurgeBtn:setVisible(hasMissing)
		if ui.termTableY then
			ui.termPurgeBtn:setY(ui.termTableY + host:getHeight() + 4)
		end
	end
	if ui.termTableY then
		ui.termBlockEndY = ui.termTableY + host:getHeight() + (hasMissing and (BTN_H + 14) or 8)
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
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.termBlockCard, newBlockY - 2)
		end
		if ui.termBlockTitle and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.termBlockTitle) then
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.termBlockTitle, newBlockY + 2)
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
		ui.termBlockTitle:setX(pad + 6)
	end
	if ui.termPurgeBtn then
		ui.termPurgeBtn:setWidth(math.min(240, tableW))
	end
	GlobalStorageSiK.TerminalNetworkTerminals.layoutRows(ui)
	if ui.termBlockCard and GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.termBlockCard) then
		ui.termBlockCard:setX(pad - 4)
		ui.termBlockCard:setWidth(innerW - (pad - 4) * 2)
		if ui.termBlockEndY and ui.termBlockY then
			ui.termBlockCard:setHeight(math.max(24, ui.termBlockEndY - ui.termBlockY + 4))
		end
	end
end

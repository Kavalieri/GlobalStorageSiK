--[[
	GlobalStorageSiK - Editor modal de miembro de red (pestaña Red > Admin)
	Autor: SiK
	Fecha: 2026-08-15
	Descripción: Mismo patrón que GS_TerminalUI_TerminalEditor.lua (ventana
	oscura modal, no ISModalDialog vainilla) pero para un miembro de la red:
	rol actual, cambio de rol por desplegable (solo owner), transferencia de
	propiedad (solo owner), abandonar la red uno mismo, y quitar acceso a
	otro - todo con la MISMA autoridad y reglas ya validadas en servidor
	(GS_Server.lua: setMemberRole exige owner, removePermissionUser deja a
	admin quitar miembros pero solo el owner quita admins, leaveNetwork no
	exige ningun rol porque abandonar tu propia fila siempre esta permitido).
	Un clic en CUALQUIER fila de la tabla de miembros abre esta ventana,
	incluida la propia fila del jugador que la abre.

	Ancho estandar (TerminalChrome.STANDARD_MODAL_W) y alto SIEMPRE calculado
	desde el contenido real (wrapTextLines por cada linea que pueda superar
	el ancho, nunca una altura fija adivinada) - antes esta ventana tenia
	h=300 fijo y el texto largo se salia del panel sin wrapear. Ver también
	CLAUDE.md raiz: "Texto de longitud variable siempre con wrapTextLines".
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "ISUI/ISModalDialog"
require "ISUI/ISScrollingListBox"
require "GS_I18n"
require "GS_NetClient"
require "GS_Permissions"
require "GS_TerminalUI_Chrome"

GlobalStorageSiK.TerminalMemberEditor = {}
GlobalStorageSiK.TerminalMemberEditor.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local PAD = 14
local LINE_GAP = 6
local BTN_H = FONT_HGT_SMALL + 10
local ENTRY_H = FONT_HGT_SMALL + 8
local PANEL_W = GlobalStorageSiK.TerminalChrome.STANDARD_MODAL_W

GS_MemberEditorUI = ISPanel:derive("GS_MemberEditorUI")

---@param kind string
---@return string
local function roleLabel(kind)
	if kind == "owner" then return T("IGUI_GS_PermRoleOwner") end
	if kind == "admin" then return T("IGUI_GS_PermRoleAdmin") end
	if kind == "faction" then return T("IGUI_GS_PermRoleFaction") end
	return T("IGUI_GS_PermRoleMember")
end

--- Añade una etiqueta envuelta a varias lineas si hace falta (nunca se sale
--- del ancho del panel) y devuelve la Y siguiente.
---@param panel ISPanel
---@param x number
---@param y number
---@param w number
---@param text string
---@param r number
---@param g number
---@param b number
---@return number nextY
local function addWrappedLine(panel, x, y, w, text, r, g, b)
	local lines = GlobalStorageSiK.TerminalChrome.wrapTextLines(text, w, UIFont.Small)
	for i = 1, #lines do
		local lbl = ISLabel:new(x, y, FONT_HGT_SMALL, lines[i], r, g, b, 1, UIFont.Small, true)
		lbl:initialise()
		panel:addChild(lbl)
		y = y + FONT_HGT_SMALL + 2
	end
	return y
end

function GS_MemberEditorUI:initialise()
	ISPanel.initialise(self)
	self.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	self.borderColor = { r = 0.35, g = 0.38, b = 0.42, a = 0.95 }
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + LINE_GAP
	GlobalStorageSiK.TerminalChrome.setupModalPanel(self, function()
		self:destroy()
	end, PAD)
	self:buildLayout()
end

function GS_MemberEditorUI:destroy()
	GlobalStorageSiK.TerminalMemberEditor.instance = nil
	self:setVisible(false)
	if self.removeFromUIManager then
		self:removeFromUIManager()
	end
end

function GS_MemberEditorUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then
		self:destroy()
		return true
	end
	return ISPanel.onKeyRelease(self, key)
end

--- La tabla de detras (GS_TerminalUI_Permissions) se refresca sola cuando
--- llega el ModData actualizado del servidor - aqui solo cerramos.
function GS_MemberEditorUI:closeAfterAction()
	if self.terminal and self.terminal.refreshNetworkPanel then
		self.terminal:refreshNetworkPanel()
	end
	self:destroy()
end

function GS_MemberEditorUI:onApplyRole()
	if not self.roleCombo or not self.terminal or not self.data then return end
	local idx = self.roleCombo.selected or 1
	local role = self._roleOptions and self._roleOptions[idx]
	if not role then return end
	self.terminal:onSetMemberRole(self.data.name, role, self.data.characterId)
	self:closeAfterAction()
end

function GS_MemberEditorUI:setAllZonesAllowed(allowed)
	if not self.zoneList then return end
	for i = 1, #self.zoneList.items do
		local row = self.zoneList.items[i]
		if row and row.item then row.item.allowed = allowed == true end
	end
end

function GS_MemberEditorUI:onSaveZoneAccess()
	if not self.zoneList or not self.terminal or not self.data then return end
	local denied = {}
	for i = 1, #self.zoneList.items do
		local row = self.zoneList.items[i]
		if row and row.item and row.item.allowed ~= true then
			denied[#denied + 1] = row.item.zoneId
		end
	end
	self.terminal:onSetMemberZoneAccess(
		self.data.name, self.data.characterId, denied)
	self:closeAfterAction()
end

local function drawZoneAccessRow(list, y, item, alt)
	if not item.height then item.height = list.itemheight end
	if item.height <= 0 then return y + item.height end
	if list.selected == item.index then
		list:drawSelection(0, y, list:getWidth(), item.height - 1)
	elseif list.mouseoverselected == item.index and list:isMouseOver() and not list:isMouseOverScrollBar() then
		list:drawMouseOverHighlight(0, y, list:getWidth(), item.height - 1)
	end
	local box = math.min(18, item.height - 8)
	local boxY = y + math.floor((item.height - box) / 2)
	list:drawRectBorder(6, boxY, box, box, 1, 0.55, 0.58, 0.62)
	if item.item and item.item.allowed == true then
		list:drawRect(9, boxY + 3, box - 6, box - 6, 0.9, 0.2, 0.75, 0.35)
		list:drawText("X", 10, boxY - 1, 0.95, 0.98, 0.95, 1, UIFont.Small)
	end
	local label = item.text or "?"
	list:drawText(label, 6 + box + 8, y + math.floor((item.height - FONT_HGT_SMALL) / 2),
		0.88, 0.9, 0.94, 1, UIFont.Small)
	return y + item.height
end

function GS_MemberEditorUI:onTransferOwnership(keepFormer)
	if not self.terminal or not self.data then return end
	self.terminal:onTransferOwnership(
		self.data.name, keepFormer == true, self.data.characterId, self.data.username)
	self:closeAfterAction()
end

function GS_MemberEditorUI:onRemoveAccess()
	if not self.terminal or not self.data then return end
	local data = self.data
	local function doRemove()
		if data.kind == "faction" and self.terminal.onRemovePermissionFaction then
			self.terminal:onRemovePermissionFaction(data.name)
		elseif self.terminal.onRemovePermissionUser then
			self.terminal:onRemovePermissionUser(data.name, data.characterId)
		end
		self:closeAfterAction()
	end
	local function onResult(_, button)
		if button and button.internal == "YES" then
			doRemove()
		end
	end
	local modal = ISModalDialog:new(0, 0, 400, 180,
		T("IGUI_GS_PermRemoveConfirm", data.displayName or data.name or "?"), true, nil, onResult, nil)
	modal:initialise()
	modal:addToUIManager()
	modal:setX(getCore():getScreenWidth() / 2 - modal.width / 2)
	modal:setY(getCore():getScreenHeight() / 2 - modal.height / 2)
end

--- Abandona la red uno mismo (fila propia) - siempre permitido sin importar
--- el rol, ver GlobalStorageSiK.Permissions.leaveNetwork. Confirmacion
--- previa porque si eres el owner dispara sucesion automatica.
function GS_MemberEditorUI:onLeaveNetwork()
	if not self.terminal or not self.terminal.onLeaveNetwork then return end
	local terminal = self.terminal
	local function onResult(_, button)
		if button and button.internal == "YES" then
			terminal:onLeaveNetwork()
			if terminal.refreshNetworkPanel then
				terminal:refreshNetworkPanel()
			end
		end
	end
	local confirmLines = GlobalStorageSiK.TerminalChrome.wrapTextLines(T("IGUI_GS_MemberEditorLeaveConfirm"), 360, UIFont.Small)
	local modal = ISModalDialog:new(0, 0, 400, 120 + (#confirmLines * (FONT_HGT_SMALL + 2)), T("IGUI_GS_MemberEditorLeaveConfirm"), true, nil, onResult, nil)
	modal:initialise()
	modal:addToUIManager()
	modal:setX(getCore():getScreenWidth() / 2 - modal.width / 2)
	modal:setY(getCore():getScreenHeight() / 2 - modal.height / 2)
	self:destroy()
end

function GS_MemberEditorUI:buildLayout()
	local pad = PAD
	local y = pad
	local textW = self.width - pad * 2
	local data = self.data
	local viewerRole = self.viewerRole or "member"
	local isOwnerViewer = viewerRole == "owner"
	local isAdminViewer = viewerRole == "admin" or isOwnerViewer
	local pal = GlobalStorageSiK.TerminalChrome.PALETTE

	local title = ISLabel:new(pad, y, FONT_HGT_MEDIUM, T("IGUI_GS_MemberEditorTitle"), 0.95, 0.95, 0.95, 1, UIFont.Medium, true)
	title:initialise()
	self:addChild(title)
	y = y + FONT_HGT_MEDIUM + LINE_GAP

	local nameLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, data.displayName or data.name or "?", 0.78, 0.82, 0.88, 1, UIFont.Small, true)
	nameLbl:initialise()
	self:addChild(nameLbl)
	y = y + FONT_HGT_SMALL + 2

	y = addWrappedLine(self, pad, y, textW, T("IGUI_GS_MemberEditorCurrentRole", roleLabel(data.kind)),
		0.7, 0.75, 0.8)
	y = y + LINE_GAP + 4

	if self.isSelf then
		y = addWrappedLine(self, pad, y, textW, T("IGUI_GS_MemberEditorSelfNote"), 0.6, 0.63, 0.66)
		y = y + LINE_GAP
	end

	-- Las restricciones se editan sobre zonas (y por tanto sobre todos sus
	-- contenedores), nunca por objeto. Solo un owner/admin puede cambiarlas y
	-- solo se aplican a miembros normales; admins y owner tienen acceso total.
	local canManageZones = isAdminViewer and data.kind == "user"
	if canManageZones then
		local zoneTitle = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_MemberZoneAccessTitle"),
			0.88, 0.9, 0.94, 1, UIFont.Small, true)
		zoneTitle:initialise()
		self:addChild(zoneTitle)
		y = y + FONT_HGT_SMALL + 3
		y = addWrappedLine(self, pad, y, textW, T("IGUI_GS_MemberZoneAccessHint"), 0.6, 0.64, 0.68)
		y = y + 4

		local zones = (self.terminal.terminalState and self.terminal.terminalState.zones) or {}
		local sortedZones = {}
		for i = 1, #zones do sortedZones[#sortedZones + 1] = zones[i] end
		table.sort(sortedZones, function(a, b)
			return tostring(a.name or a.id or "") < tostring(b.name or b.id or "")
		end)
		if #sortedZones == 0 then
			y = addWrappedLine(self, pad, y, textW, T("IGUI_GS_NoZonesYet"), 0.55, 0.58, 0.6)
			y = y + LINE_GAP
		else
			local denied = {}
			for i = 1, #(data.deniedZoneIds or {}) do denied[tostring(data.deniedZoneIds[i])] = true end
			local rowH = FONT_HGT_SMALL + 10
			local listH = math.min(#sortedZones, 6) * rowH + 2
			self.zoneList = ISScrollingListBox:new(pad, y, textW, listH)
			self.zoneList:initialise()
			self.zoneList:instantiate()
			self.zoneList.itemheight = rowH
			self.zoneList.selected = 0
			self.zoneList.drawBorder = true
			self.zoneList.doDrawItem = drawZoneAccessRow
			self.zoneList.onMouseDown = function(list, x, mouseY)
				local rowIndex = list:rowAt(x, mouseY)
				if rowIndex >= 1 and rowIndex <= #list.items then
					list.selected = rowIndex
					local row = list.items[rowIndex]
					if row and row.item then row.item.allowed = row.item.allowed ~= true end
				end
				return true
			end
			for i = 1, #sortedZones do
				local zone = sortedZones[i]
				local label = tostring(zone.name or zone.id or "?")
				if zone.nodeCount ~= nil then label = label .. " (" .. tostring(zone.nodeCount) .. ")" end
				self.zoneList:addItem(label, {
					zoneId = tostring(zone.id),
					allowed = denied[tostring(zone.id)] ~= true,
				})
			end
			self:addChild(self.zoneList)
			y = y + listH + 5

			local halfW = math.floor((textW - 6) / 2)
			self.selectAllZonesBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
				pad, y, halfW, BTN_H, T("IGUI_GS_MemberZoneSelectAll"), self, function()
					self:setAllZonesAllowed(true)
				end)
			self:addChild(self.selectAllZonesBtn)
			self.deselectAllZonesBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
				pad + halfW + 6, y, textW - halfW - 6, BTN_H,
				T("IGUI_GS_MemberZoneDeselectAll"), self, function()
					self:setAllZonesAllowed(false)
				end)
			self:addChild(self.deselectAllZonesBtn)
			y = y + BTN_H + 5
			self.saveZonesBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
				pad, y, textW, BTN_H, T("IGUI_GS_MemberZoneSave"), self, function()
					self:onSaveZoneAccess()
				end)
			self:addChild(self.saveZonesBtn)
			y = y + BTN_H + LINE_GAP + 8
		end
	end

	-- ── Cambio de rol (solo owner, sobre usuarios que no sean el propio
	-- propietario ni una faccion ni uno mismo) ─────────────────────────────
	local canChangeRole = isOwnerViewer and not self.isSelf
		and (data.kind == "user" or data.kind == "admin")
	if canChangeRole then
		local roleTitle = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_MemberEditorRoleLabel"), 0.88, 0.9, 0.94, 1, UIFont.Small, true)
		roleTitle:initialise()
		self:addChild(roleTitle)
		y = y + FONT_HGT_SMALL + 4

		local applyW = 110
		self.roleCombo = ISComboBox:new(pad, y, textW - applyW - 6, ENTRY_H, self, nil)
		self.roleCombo:initialise()
		GlobalStorageSiK.TerminalChrome.styleComboBox(self.roleCombo)
		self._roleOptions = { "member", "admin" }
		self.roleCombo:addOption(T("IGUI_GS_PermRoleMember"))
		self.roleCombo:addOption(T("IGUI_GS_PermRoleAdmin"))
		self.roleCombo.selected = (data.kind == "admin") and 2 or 1
		self:addChild(self.roleCombo)

		self.applyRoleBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
			pad + textW - applyW, y, applyW, ENTRY_H, T("IGUI_GS_MemberEditorApplyRoleBtn"), self, function()
				self:onApplyRole()
			end)
		self:addChild(self.applyRoleBtn)
		y = y + ENTRY_H + LINE_GAP + 8
	end

	-- ── Transferencia de propiedad (solo owner, sobre un usuario que no
	-- sea uno mismo) ────────────────────────────────────────────────────
	local canTransfer = isOwnerViewer and not self.isSelf and data.kind == "user"
	if canTransfer then
		self.transferBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
			pad, y, textW, BTN_H, T("IGUI_GS_MemberEditorTransferBtn", data.displayName or data.name or "?"), self, function()
				self:onTransferOwnership(true)
			end)
		self:addChild(self.transferBtn)
		y = y + BTN_H + LINE_GAP
	end

	-- ── Quitar acceso (owner sobre cualquiera menos si mismo/dueño; admin
	-- solo sobre miembros/facciones que no sean admin) ─────────────────
	local canRemove = false
	if data.kind ~= "owner" and not self.isSelf then
		if isOwnerViewer then
			canRemove = true
		elseif viewerRole == "admin" and data.kind ~= "admin" then
			canRemove = true
		end
	end
	if canRemove then
		self.removeBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
			pad, y, textW, BTN_H, T("IGUI_GS_MemberEditorRemoveBtn"), self, function()
				self:onRemoveAccess()
			end)
		self:addChild(self.removeBtn)
		y = y + BTN_H + LINE_GAP
	end

	-- ── Abandonar red (solo en la propia fila, cualquier rol - el owner
	-- dispara sucesion automatica igual que al morir) ──────────────────
	local canLeave = self.isSelf and data.kind ~= "faction"
	if canLeave then
		self.leaveBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
			pad, y, textW, BTN_H, T("IGUI_GS_MemberEditorLeaveBtn"), self, function()
				self:onLeaveNetwork()
			end)
		self.leaveBtn.textColor = { r = pal.statusDanger[1], g = pal.statusDanger[2], b = pal.statusDanger[3] }
		self:addChild(self.leaveBtn)
		y = y + BTN_H + LINE_GAP
	end

	if not canManageZones and not canChangeRole and not canTransfer and not canRemove and not canLeave then
		y = addWrappedLine(self, pad, y, textW, T("IGUI_GS_MemberEditorNoActions"), 0.55, 0.58, 0.6)
		y = y + LINE_GAP
	end

	y = y + pad
	self:setHeight(y)
	GlobalStorageSiK.TerminalChrome.layoutModalChrome(self, pad)
	GlobalStorageSiK.TerminalChrome.centerModal(self)
end

--- Abre (o reemplaza) el editor de un miembro concreto.
---@param terminal GS_TerminalUI
---@param data table { kind, name }
---@param viewerRole string owner|admin|member
function GlobalStorageSiK.TerminalMemberEditor.open(terminal, data, viewerRole)
	if not data or data.kind == "empty" then return end
	if GlobalStorageSiK.TerminalMemberEditor.instance then
		GlobalStorageSiK.TerminalMemberEditor.instance:destroy()
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer and GlobalStorageSiK.NetClient.getPlayer()
	local myName = player and GlobalStorageSiK.Permissions.getCharacterName(player) or ""
	local myId = player and GlobalStorageSiK.Permissions.getCharacterId(player) or ""
	local myUsername = player and player.getUsername and tostring(player:getUsername() or "") or ""
	local function sameIdentityText(a, b)
		a = tostring(a or ""):lower():gsub("^%s*(.-)%s*$", "%1")
		b = tostring(b or ""):lower():gsub("^%s*(.-)%s*$", "%1")
		return a ~= "" and a == b
	end
	local isSelf = data.kind ~= "faction"
		and ((data.characterId and data.characterId ~= "" and data.characterId == myId)
			or sameIdentityText(data.username, myUsername)
			or ((not data.characterId or data.characterId == "")
				and (not data.username or data.username == "")
				and sameIdentityText(data.name, myName)))

	-- Posicion/alto provisionales - buildLayout() recalcula el alto real
	-- segun el contenido (numero de lineas envueltas, botones visibles) y
	-- se re-centra el mismo con TerminalChrome.centerModal al final.
	local ui = GS_MemberEditorUI:new(0, 0, PANEL_W, 100)
	ui.terminal = terminal
	ui.data = data
	ui.viewerRole = viewerRole or "member"
	ui.isSelf = isSelf
	ui:initialise()
	ui:addToUIManager()
	GlobalStorageSiK.TerminalMemberEditor.instance = ui
end

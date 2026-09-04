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

	Ancho estandar (SiK.UI.Modal.STANDARD_MODAL_W) y alto SIEMPRE calculado
	desde el contenido real (wrapTextLines por cada linea que pueda superar
	el ancho, nunca una altura fija adivinada) - antes esta ventana tenia
	h=300 fijo y el texto largo se salia del panel sin wrapear. Ver también
	CLAUDE.md raiz: "Texto de longitud variable siempre con wrapTextLines".
]]

require "GS_I18n"
require "GS_NetClient"
require "GS_Permissions"
local UI = require "GS_UI_Framework"

GlobalStorageSiK.TerminalMemberEditor = {}
GlobalStorageSiK.TerminalMemberEditor.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local PAD = 14
local LINE_GAP = 6
local CONTROL_METRICS = UI.Controls.metrics("compact")
local PANEL_W = UI.Modal.STANDARD_MODAL_W

GS_MemberEditorUI = UI.Window.derive("GS_MemberEditorUI")

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
---@param tone string|nil
---@return number nextY
local function addWrappedLine(panel, x, y, w, text, tone)
	local copy = UI.Controls.copyText(panel, {
		x = x, y = y, w = w, text = text,
		tone = tone or "textMuted", playerNum = panel.playerNum,
	})
	return y + copy.height
end

function GS_MemberEditorUI:initialise()
	UI.Window.callBase(self, "initialise")
	self.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	self.borderColor = { r = 0.35, g = 0.38, b = 0.42, a = 0.95 }
	self:setAlwaysOnTop(true)
	UI.Modal.apply(self, {
		kind = "compact", padding = PAD, resizable = false,
		title = T("IGUI_GS_MemberEditorTitle"),
		onClose = function()
			GlobalStorageSiK.TerminalMemberEditor.instance = nil
		end,
	})
	self:buildLayout()
end

function GS_MemberEditorUI:destroy()
	GlobalStorageSiK.TerminalMemberEditor.instance = nil
	if self.close then
		self:close("product")
	else
		self:setVisible(false)
		if self.removeFromUIManager then self:removeFromUIManager() end
	end
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
	local selected = self.roleCombo.getSelectedItem and self.roleCombo:getSelectedItem() or nil
	local role = type(selected) == "table" and selected.value or selected
	if not role then return end
	self.terminal:onSetMemberRole(self.data.name, role, self.data.characterId)
	self:closeAfterAction()
end

function GS_MemberEditorUI:setAllZonesAllowed(allowed)
	if not self.zoneList or not self._zoneRows then return end
	for i = 1, #self._zoneRows do
		self._zoneRows[i].allowed = allowed == true
	end
	self.zoneList:setData(self._zoneRows, true)
end

function GS_MemberEditorUI:onSaveZoneAccess()
	if not self.zoneList or not self._zoneRows or not self.terminal or not self.data then return end
	local denied = {}
	for i = 1, #self._zoneRows do
		local row = self._zoneRows[i]
		if row.allowed ~= true then
			denied[#denied + 1] = row.zoneId
		end
	end
	self.terminal:onSetMemberZoneAccess(
		self.data.name, self.data.characterId, denied)
	self:closeAfterAction()
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
	UI.Modal.confirm({
		message = T("IGUI_GS_PermRemoveConfirm", data.displayName or data.name or "?"),
		onAccept = doRemove,
	})
end

--- Abandona la red uno mismo (fila propia) - siempre permitido sin importar
--- el rol, ver GlobalStorageSiK.Permissions.leaveNetwork. Confirmacion
--- previa porque si eres el owner dispara sucesion automatica.
function GS_MemberEditorUI:onLeaveNetwork()
	if not self.terminal or not self.terminal.onLeaveNetwork then return end
	local terminal = self.terminal
	UI.Modal.confirm({
		message = T("IGUI_GS_MemberEditorLeaveConfirm"),
		onAccept = function()
			terminal:onLeaveNetwork()
			if terminal.refreshNetworkPanel then terminal:refreshNetworkPanel() end
		end,
	})
	self:destroy()
end

function GS_MemberEditorUI:buildLayout()
	local content = self:contentRect()
	local pad = content.x
	local y = content.y
	local textW = content.w
	local data = self.data
	local viewerRole = self.viewerRole or "member"
	local isOwnerViewer = viewerRole == "owner"
	local isAdminViewer = viewerRole == "admin" or isOwnerViewer
	local nameCopy = UI.Controls.copyText(self, {
		x = pad, y = y, w = textW, text = data.displayName or data.name or "?",
		tone = "text", playerNum = self.playerNum,
	})
	y = y + nameCopy.height

	y = addWrappedLine(self, pad, y, textW, T("IGUI_GS_MemberEditorCurrentRole", roleLabel(data.kind)),
		"textMuted")
	y = y + LINE_GAP + 4

	if self.isSelf then
		y = addWrappedLine(self, pad, y, textW, T("IGUI_GS_MemberEditorSelfNote"), "textMuted")
		y = y + LINE_GAP
	end

	-- Las restricciones se editan sobre zonas (y por tanto sobre todos sus
	-- contenedores), nunca por objeto. Solo un owner/admin puede cambiarlas y
	-- solo se aplican a miembros normales; admins y owner tienen acceso total.
	local canManageZones = isAdminViewer and data.kind == "user"
	if canManageZones then
		local zoneTitle = UI.Controls.sectionTitle(self, {
			x = pad, y = y, w = textW, h = CONTROL_METRICS.rowHeight,
			text = T("IGUI_GS_MemberZoneAccessTitle"), playerNum = self.playerNum,
		})
		y = y + zoneTitle.height + 3
		y = addWrappedLine(self, pad, y, textW, T("IGUI_GS_MemberZoneAccessHint"), "textMuted")
		y = y + 4

		local zones = (self.terminal.terminalState and self.terminal.terminalState.zones) or {}
		local sortedZones = {}
		for i = 1, #zones do sortedZones[#sortedZones + 1] = zones[i] end
		table.sort(sortedZones, function(a, b)
			return tostring(a.name or a.id or "") < tostring(b.name or b.id or "")
		end)
		if #sortedZones == 0 then
			y = addWrappedLine(self, pad, y, textW, T("IGUI_GS_NoZonesYet"), "textMuted")
			y = y + LINE_GAP
		else
			local denied = {}
			for i = 1, #(data.deniedZoneIds or {}) do denied[tostring(data.deniedZoneIds[i])] = true end
			local rowH = FONT_HGT_SMALL + 10
			local listH = math.min(#sortedZones, 6) * rowH + 2
			local listPanel = UI.Controls.panel(self, {
				x = pad, y = y, w = textW, h = listH,
				playerNum = self.playerNum,
			})
			local overflow = #sortedZones * rowH > listH
			local viewportRect, trackRect = UI.Metrics.blockRects(textW, listH, overflow)
			local scroll, scrollReason = UI.Scroll.create({
				parent = listPanel, viewportRect = viewportRect, trackRect = trackRect,
				rowHeight = rowH, wheelStep = rowH, playerNum = self.playerNum,
			})
			if not scroll then error("SiK.UI member zone scroll: " .. tostring(scrollReason)) end
			self._zoneRows = {}
			for i = 1, #sortedZones do
				local zone = sortedZones[i]
				local label = tostring(zone.name or zone.id or "?")
				if zone.nodeCount ~= nil then label = label .. " (" .. tostring(zone.nodeCount) .. ")" end
				self._zoneRows[#self._zoneRows + 1] = {
					zoneId = tostring(zone.id),
					label = label,
					allowed = denied[tostring(zone.id)] ~= true,
				}
			end
			local listReason
			self.zoneList, listReason = UI.VirtualList.create({
				scroll = scroll, rowHeight = rowH, buffer = 2,
				playerNum = self.playerNum, data = self._zoneRows,
				keyOf = function(item) return item.zoneId end,
				createRow = function(_, width, height)
					return UI.Controls.toggle(nil, {
						x = 0, y = 0, w = width, h = height, text = "",
						fullWidth = true, playerNum = self.playerNum,
					})
				end,
				updateRow = function(row, item)
					row:setText(item.label)
					row:setSelected(item.allowed == true, false)
				end,
				onActivate = function(context)
					context.item.allowed = context.item.allowed ~= true
					context.component:refresh()
				end,
			})
			if not self.zoneList then
				scroll:dispose()
				error("SiK.UI member zone list: " .. tostring(listReason))
			end
			UI.Lifecycle.own(self, self.zoneList)
			y = y + listH + 5

			local halfW = math.floor((textW - 6) / 2)
			self.selectAllZonesBtn = UI.Controls.button(self, {
				x = pad, y = y, w = halfW, h = CONTROL_METRICS.buttonHeight,
				text = T("IGUI_GS_MemberZoneSelectAll"), fullWidth = true,
				onClick = function() self:setAllZonesAllowed(true) end,
			})
			self.deselectAllZonesBtn = UI.Controls.button(self, {
				x = pad + halfW + 6, y = y, w = textW - halfW - 6,
				h = CONTROL_METRICS.buttonHeight,
				text = T("IGUI_GS_MemberZoneDeselectAll"), fullWidth = true,
				onClick = function() self:setAllZonesAllowed(false) end,
			})
			y = y + CONTROL_METRICS.buttonHeight + 5
			self.saveZonesBtn = UI.Controls.button(self, {
				x = pad, y = y, w = textW, h = CONTROL_METRICS.buttonHeight,
				text = T("IGUI_GS_MemberZoneSave"), fullWidth = true,
				onClick = function() self:onSaveZoneAccess() end,
			})
			y = y + CONTROL_METRICS.buttonHeight + LINE_GAP + 8
		end
	end

	-- ── Cambio de rol (solo owner, sobre usuarios que no sean el propio
	-- propietario ni una faccion ni uno mismo) ─────────────────────────────
	local canChangeRole = isOwnerViewer and not self.isSelf
		and (data.kind == "user" or data.kind == "admin")
	if canChangeRole then
		local roleTitle = UI.Controls.sectionTitle(self, {
			x = pad, y = y, w = textW, h = CONTROL_METRICS.rowHeight,
			text = T("IGUI_GS_MemberEditorRoleLabel"), playerNum = self.playerNum,
		})
		y = y + roleTitle.height + 4

		local applyW = 110
		self.roleCombo = UI.Controls.combo(self, {
			x = pad, y = y, w = textW - applyW - 6,
			h = CONTROL_METRICS.inputHeight, playerNum = self.playerNum,
			items = {
				{ text = T("IGUI_GS_PermRoleMember"), value = "member" },
				{ text = T("IGUI_GS_PermRoleAdmin"), value = "admin" },
			},
			selected = data.kind == "admin" and "admin" or "member",
		})

		self.applyRoleBtn = UI.Controls.button(self, {
			x = pad + textW - applyW, y = y, w = applyW,
			h = CONTROL_METRICS.inputHeight,
			text = T("IGUI_GS_MemberEditorApplyRoleBtn"),
			onClick = function() self:onApplyRole() end,
		})
		y = y + CONTROL_METRICS.inputHeight + LINE_GAP + 8
	end

	-- ── Transferencia de propiedad (solo owner, sobre un usuario que no
	-- sea uno mismo) ────────────────────────────────────────────────────
	local canTransfer = isOwnerViewer and not self.isSelf and data.kind == "user"
	if canTransfer then
		self.transferBtn = UI.Controls.button(self, {
			x = pad, y = y, w = textW, h = CONTROL_METRICS.buttonHeight,
			text = T("IGUI_GS_MemberEditorTransferBtn", data.displayName or data.name or "?"),
			fullWidth = true, onClick = function() self:onTransferOwnership(true) end,
		})
		y = y + CONTROL_METRICS.buttonHeight + LINE_GAP
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
		self.removeBtn = UI.Controls.button(self, {
			x = pad, y = y, w = textW, h = CONTROL_METRICS.buttonHeight,
			text = T("IGUI_GS_MemberEditorRemoveBtn"), danger = true,
			fullWidth = true, onClick = function() self:onRemoveAccess() end,
		})
		y = y + CONTROL_METRICS.buttonHeight + LINE_GAP
	end

	-- ── Abandonar red (solo en la propia fila, cualquier rol - el owner
	-- dispara sucesion automatica igual que al morir) ──────────────────
	local canLeave = self.isSelf and data.kind ~= "faction"
	if canLeave then
		self.leaveBtn = UI.Controls.button(self, {
			x = pad, y = y, w = textW, h = CONTROL_METRICS.buttonHeight,
			text = T("IGUI_GS_MemberEditorLeaveBtn"), danger = true,
			fullWidth = true, onClick = function() self:onLeaveNetwork() end,
		})
		y = y + CONTROL_METRICS.buttonHeight + LINE_GAP
	end

	if not canManageZones and not canChangeRole and not canTransfer and not canRemove and not canLeave then
		y = addWrappedLine(self, pad, y, textW, T("IGUI_GS_MemberEditorNoActions"), "textMuted")
		y = y + LINE_GAP
	end

	y = y + pad
	UI.Modal.fitContent(self, y - content.y, { bottomPadding = 0, center = true })
end

function GS_MemberEditorUI:new(x, y, width, height)
	return UI.Window.newInstance(GS_MemberEditorUI, x, y, width, height)
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
	-- BUG REAL cerrado (2026-08-22, confirmado con dos personajes de la MISMA
	-- cuenta - Kalva muerta, Kava viva): antes esto comparaba por username
	-- (cuenta) como alternativa AUNQUE ya hubiera un characterId (UUID) real
	-- en la ficha, así que una fila de un personaje distinto pero de la
	-- MISMA cuenta se detectaba como "tú mismo" (mostraba "Abandonar red" en
	-- vez de "Quitar acceso"). El UUID es la identidad autoritativa siempre
	-- que exista en la ficha - la cuenta/username SOLO es el fallback para
	-- fichas legacy sin UUID en absoluto, nunca una alternativa cuando ya
	-- hay un UUID que no coincide.
	local isSelf
	if data.kind == "faction" then
		isSelf = false
	elseif data.characterId and data.characterId ~= "" then
		isSelf = data.characterId == myId
	elseif data.username and data.username ~= "" then
		isSelf = sameIdentityText(data.username, myUsername)
	else
		isSelf = sameIdentityText(data.name, myName)
	end

	-- Posicion/alto provisionales - buildLayout() recalcula el alto real
	-- segun el contenido (numero de lineas envueltas, botones visibles) y
	-- Modal.fitContent lo ajusta al viewport despues del ultimo control.
	local ui = GS_MemberEditorUI:new(0, 0, PANEL_W, 100)
	ui.terminal = terminal
	ui.data = data
	ui.viewerRole = viewerRole or "member"
	ui.isSelf = isSelf
	ui:initialise()
	UI.Modal.show(ui)
	GlobalStorageSiK.TerminalMemberEditor.instance = ui
end

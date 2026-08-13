--[[
	GlobalStorageSiK - Editor modal de miembro de red (pestaña Red > Admin)
	Autor: SiK
	Fecha: 2026-08-10
	Descripción: Mismo patrón que GS_TerminalUI_TerminalEditor.lua (ventana
	oscura modal, no ISModalDialog vainilla) pero para un miembro de la red:
	rol actual, cambio de rol por desplegable (solo owner), transferencia de
	propiedad (solo owner) y quitar acceso - todo con la MISMA autoridad y
	reglas ya validadas en servidor (GS_Server.lua: setMemberRole exige
	owner, removePermissionUser deja a admin quitar miembros pero solo el
	owner quita admins). Un clic en CUALQUIER fila de la tabla de miembros
	abre esta ventana, incluida la propia fila del jugador que la abre (en
	modo solo-lectura si no hay ninguna accion valida sobre uno mismo).
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "ISUI/ISModalDialog"
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
local PANEL_W = 420

GS_MemberEditorUI = ISPanel:derive("GS_MemberEditorUI")

---@param kind string
---@return string
local function roleLabel(kind)
	if kind == "owner" then return T("IGUI_GS_PermRoleOwner") end
	if kind == "admin" then return T("IGUI_GS_PermRoleAdmin") end
	if kind == "faction" then return T("IGUI_GS_PermRoleFaction") end
	return T("IGUI_GS_PermRoleMember")
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
	self.terminal:onSetMemberRole(self.data.name, role)
	self:closeAfterAction()
end

function GS_MemberEditorUI:onTransferOwnership(keepFormer)
	if not self.terminal or not self.data then return end
	self.terminal:onTransferOwnership(self.data.name, keepFormer == true)
	self:closeAfterAction()
end

function GS_MemberEditorUI:onRemoveAccess()
	if not self.terminal or not self.data then return end
	local data = self.data
	local function doRemove()
		if data.kind == "faction" and self.terminal.onRemovePermissionFaction then
			self.terminal:onRemovePermissionFaction(data.name)
		elseif self.terminal.onRemovePermissionUser then
			self.terminal:onRemovePermissionUser(data.name)
		end
		self:closeAfterAction()
	end
	local function onResult(_, button)
		if button and button.internal == "YES" then
			doRemove()
		end
	end
	local modal = ISModalDialog:new(0, 0, 400, 180, T("IGUI_GS_PermRemoveConfirm", data.name or "?"), true, nil, onResult, nil)
	modal:initialise()
	modal:addToUIManager()
	modal:setX(getCore():getScreenWidth() / 2 - modal.width / 2)
	modal:setY(getCore():getScreenHeight() / 2 - modal.height / 2)
end

function GS_MemberEditorUI:buildLayout()
	local pad = PAD
	local y = pad
	local textW = self.width - pad * 2
	local data = self.data
	local viewerRole = self.viewerRole or "member"
	local isOwnerViewer = viewerRole == "owner"
	local isAdminViewer = viewerRole == "admin" or isOwnerViewer

	local title = ISLabel:new(pad, y, FONT_HGT_MEDIUM, T("IGUI_GS_MemberEditorTitle"), 0.95, 0.95, 0.95, 1, UIFont.Medium, true)
	title:initialise()
	self:addChild(title)
	y = y + FONT_HGT_MEDIUM + LINE_GAP

	local nameLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, data.name or "?", 0.78, 0.82, 0.88, 1, UIFont.Small, true)
	nameLbl:initialise()
	self:addChild(nameLbl)
	y = y + FONT_HGT_SMALL + 2

	local roleLbl = ISLabel:new(pad, y, FONT_HGT_SMALL,
		T("IGUI_GS_MemberEditorCurrentRole", roleLabel(data.kind)),
		0.7, 0.75, 0.8, 1, UIFont.Small, true)
	roleLbl:initialise()
	self:addChild(roleLbl)
	y = y + FONT_HGT_SMALL + LINE_GAP + 4

	if self.isSelf then
		local selfLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_MemberEditorSelfNote"), 0.6, 0.63, 0.66, 1, UIFont.Small, true)
		selfLbl:initialise()
		self:addChild(selfLbl)
		y = y + FONT_HGT_SMALL + LINE_GAP
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
			pad, y, textW, BTN_H, T("IGUI_GS_MemberEditorTransferBtn", data.name or "?"), self, function()
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

	if not canChangeRole and not canTransfer and not canRemove then
		local noneLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_MemberEditorNoActions"), 0.55, 0.58, 0.6, 1, UIFont.Small, true)
		noneLbl:initialise()
		self:addChild(noneLbl)
		y = y + FONT_HGT_SMALL + LINE_GAP
	end

	y = y + pad
	self:setHeight(y)
	GlobalStorageSiK.TerminalChrome.layoutModalChrome(self, pad)
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
	local isSelf = data.kind ~= "faction" and data.name == myName

	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	local h = 300
	local x = (sw - PANEL_W) / 2
	local y = (sh - h) / 2
	local ui = GS_MemberEditorUI:new(x, y, PANEL_W, h)
	ui.terminal = terminal
	ui.data = data
	ui.viewerRole = viewerRole or "member"
	ui.isSelf = isSelf
	ui:initialise()
	ui:addToUIManager()
	GlobalStorageSiK.TerminalMemberEditor.instance = ui
end

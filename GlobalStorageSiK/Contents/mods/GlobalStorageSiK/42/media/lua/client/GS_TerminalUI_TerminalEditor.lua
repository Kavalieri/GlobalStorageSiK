--[[
	GlobalStorageSiK - Editor modal de terminal (pestaña Red > Admin)
	Autor: SiK
	Descripción: Ventana de edición de un terminal registrado - renombrar,
	             marcar como principal, suspender o eliminar. Mismo patrón de
	             fondo oscuro (no azul) que el resto de editores del mod
	             (zonas, contenedores, instalación) - antes, un clic en la
	             fila iba directo a un dialogo de confirmacion de baja
	             (ISModalDialog vainilla, azul), sin ninguna otra opcion.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISModalDialog"
require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalUI_Chrome"

GlobalStorageSiK.TerminalTerminalEditor = {}
GlobalStorageSiK.TerminalTerminalEditor.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local PAD = 14
local LINE_GAP = 6
local ENTRY_H = FONT_HGT_SMALL + 8
local BTN_H = FONT_HGT_SMALL + 10
local PANEL_W = 420

GS_TerminalEditorUI = ISPanel:derive("GS_TerminalEditorUI")

---@param row table|nil
---@return string
local function statusText(row)
	if not row then return "?" end
	if row.unknown then return T("IGUI_GS_TerminalUnverified") end
	if row.missing or row.present == false then return T("IGUI_GS_TerminalMissingPhys") end
	if row.suspended then return T("IGUI_GS_TerminalSuspended") end
	return T("IGUI_GS_TerminalPresentPhys")
end

function GS_TerminalEditorUI:initialise()
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

function GS_TerminalEditorUI:destroy()
	GlobalStorageSiK.TerminalTerminalEditor.instance = nil
	self:setVisible(false)
	if self.removeFromUIManager then
		self:removeFromUIManager()
	end
end

function GS_TerminalEditorUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then
		self:destroy()
		return true
	end
	return ISPanel.onKeyRelease(self, key)
end

--- Refresca despues de una accion con exito: la ventana principal ya recibe
--- terminalState actualizado por su cuenta (ver fixes de pushTerminalState
--- en GS_Server.lua) - aqui solo cerramos, la fila desaparece/actualiza sola
--- en tiempo real en la tabla de detras.
function GS_TerminalEditorUI:closeAfterAction()
	if self.terminal and self.terminal.refreshNetworkPanel then
		self.terminal:refreshNetworkPanel()
	end
	self:destroy()
end

function GS_TerminalEditorUI:onRename()
	local name = self.nameEntry and self.nameEntry:getText() or ""
	GlobalStorageSiK.NetClient.sendCommand("renameTerminal", {
		x = self.row.x, y = self.row.y, z = self.row.z,
		gsnNetworkId = self.terminal and self.terminal.terminalState and self.terminal.terminalState.networkId,
		name = name,
	})
	self:closeAfterAction()
end

function GS_TerminalEditorUI:onSetController()
	GlobalStorageSiK.NetClient.sendCommand("setTerminalController", {
		x = self.row.x, y = self.row.y, z = self.row.z,
		gsnNetworkId = self.terminal and self.terminal.terminalState and self.terminal.terminalState.networkId,
	})
	self:closeAfterAction()
end

function GS_TerminalEditorUI:onSuspend()
	GlobalStorageSiK.NetClient.sendCommand("uninstallTerminalReader", {
		x = self.row.x, y = self.row.y, z = self.row.z,
		gsnNetworkId = self.terminal and self.terminal.terminalState and self.terminal.terminalState.networkId,
	})
	self:closeAfterAction()
end

function GS_TerminalEditorUI:onDelete()
	GlobalStorageSiK.NetClient.sendCommand("removeTerminal", {
		x = self.row.x, y = self.row.y, z = self.row.z,
		gsnNetworkId = self.terminal and self.terminal.terminalState and self.terminal.terminalState.networkId,
	})
	self:closeAfterAction()
end

--- Eliminar definitivamente un terminal SANO (presente, no suspendido/ausente)
--- puede sorprender - se pide confirmacion. Las entradas ya rotas/ausentes se
--- borran directo, no hay nada real que perder ahi.
function GS_TerminalEditorUI:onDeleteClicked()
	local healthy = self.row and not self.row.missing and self.row.present ~= false
		and not self.row.suspended and not self.row.unknown
	if not healthy then
		self:onDelete()
		return
	end
	local function onResult(_, button)
		if button and button.internal == "YES" then
			self:onDelete()
		end
	end
	local modal = ISModalDialog:new(0, 0, 400, 180, T("IGUI_GS_UninstallConfirm"), true, nil, onResult, nil)
	modal:initialise()
	modal:addToUIManager()
	modal:setX(getCore():getScreenWidth() / 2 - modal.width / 2)
	modal:setY(getCore():getScreenHeight() / 2 - modal.height / 2)
end

function GS_TerminalEditorUI:buildLayout()
	local pad = PAD
	local y = pad
	local textW = self.width - pad * 2
	local row = self.row

	local title = ISLabel:new(pad, y, FONT_HGT_MEDIUM, T("IGUI_GS_TerminalEditorTitle"), 0.95, 0.95, 0.95, 1, UIFont.Medium, true)
	title:initialise()
	self:addChild(title)
	y = y + FONT_HGT_MEDIUM + LINE_GAP

	local coordsLbl = ISLabel:new(pad, y, FONT_HGT_SMALL,
		string.format("%d, %d, %d", row.x or 0, row.y or 0, row.z or 0),
		0.78, 0.82, 0.88, 1, UIFont.Small, true)
	coordsLbl:initialise()
	self:addChild(coordsLbl)
	y = y + FONT_HGT_SMALL + 2

	local statusLbl = ISLabel:new(pad, y, FONT_HGT_SMALL,
		T("IGUI_GS_TerminalEditorStatus", statusText(row), row.controller and T("IGUI_GS_TerminalController") or T("IGUI_GS_TerminalSecondary")),
		0.7, 0.75, 0.8, 1, UIFont.Small, true)
	statusLbl:initialise()
	self:addChild(statusLbl)
	y = y + FONT_HGT_SMALL + LINE_GAP + 4

	-- ── Nombre ───────────────────────────────────────────────────────────
	local nameTitle = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_TerminalEditorNameLabel"), 0.88, 0.9, 0.94, 1, UIFont.Small, true)
	nameTitle:initialise()
	self:addChild(nameTitle)
	y = y + FONT_HGT_SMALL + 4

	local renameW = 110
	self.nameEntry = ISTextEntryBox:new(row.label or "", pad, y, textW - renameW - 6, ENTRY_H)
	self.nameEntry:initialise()
	GlobalStorageSiK.TerminalChrome.styleTextEntry(self.nameEntry)
	self.nameEntry:instantiate()
	self:addChild(self.nameEntry)

	self.renameBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		pad + textW - renameW, y, renameW, ENTRY_H, T("IGUI_GS_TerminalEditorRenameBtn"), self, function()
			self:onRename()
		end)
	self:addChild(self.renameBtn)
	y = y + ENTRY_H + LINE_GAP + 8

	-- ── Acciones ─────────────────────────────────────────────────────────
	local isActive = not row.missing and row.present ~= false and not row.suspended and not row.unknown
	if isActive and not row.controller then
		self.controllerBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
			pad, y, textW, BTN_H, T("IGUI_GS_TerminalEditorMakeControllerBtn"), self, function()
				self:onSetController()
			end)
		self:addChild(self.controllerBtn)
		y = y + BTN_H + LINE_GAP
	end

	if isActive then
		self.suspendBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
			pad, y, textW, BTN_H, T("IGUI_GS_TerminalEditorSuspendBtn"), self, function()
				self:onSuspend()
			end)
		self:addChild(self.suspendBtn)
		y = y + BTN_H + LINE_GAP
	end

	self.deleteBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(
		pad, y, textW, BTN_H, T("IGUI_GS_TerminalEditorDeleteBtn"), self, function()
			self:onDeleteClicked()
		end)
	self:addChild(self.deleteBtn)
	y = y + BTN_H + pad

	self:setHeight(y)
	GlobalStorageSiK.TerminalChrome.layoutModalChrome(self, pad)
	GlobalStorageSiK.TerminalChrome.centerModal(self)
end

--- Abre (o reemplaza) el editor de un terminal concreto.
---@param terminal GS_TerminalUI
---@param row table { x, y, z, controller, suspended, present, missing, unknown, label }
function GlobalStorageSiK.TerminalTerminalEditor.open(terminal, row)
	if not row then return end
	if GlobalStorageSiK.TerminalTerminalEditor.instance then
		GlobalStorageSiK.TerminalTerminalEditor.instance:destroy()
	end
	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	local h = 280
	local x = (sw - PANEL_W) / 2
	local y = (sh - h) / 2
	local ui = GS_TerminalEditorUI:new(x, y, PANEL_W, h)
	ui.terminal = terminal
	ui.row = row
	ui:initialise()
	ui:addToUIManager()
	GlobalStorageSiK.TerminalTerminalEditor.instance = ui
end

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

require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalUI_BlockedPanel"
local UI = require "GS_UI_Framework"
local Confirmation = require "GS_Confirmation"

GlobalStorageSiK.TerminalTerminalEditor = {}
GlobalStorageSiK.TerminalTerminalEditor.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local LINE_GAP = 6
local CONTROL_METRICS = UI.Controls.metrics("compact")
local PANEL_W = UI.Modal.STANDARD_MODAL_W

local function addCopy(parent, x, y, width, text, tone)
	return UI.Controls.copyText(parent, {
		x = x, y = y, w = width, text = text, font = UIFont.Small,
		tone = tone or "textMuted", playerNum = parent.playerNum,
	})
end

GS_TerminalEditorUI = UI.Window.derive("GS_TerminalEditorUI")

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
	UI.Window.callBase(self, "initialise")
	self.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	self.borderColor = { r = 0.35, g = 0.38, b = 0.42, a = 0.95 }
	self:setAlwaysOnTop(true)
	UI.Modal.apply(self, {
		kind = "compact", resizable = true, contentMode = "dock",
		title = T("IGUI_GS_TerminalEditorTitle"),
		onClose = function()
			if self.editorDock then self.editorDock:dispose(); self.editorDock = nil end
			GlobalStorageSiK.TerminalTerminalEditor.instance = nil
		end,
	})
	self:setHeader({ titleParts = { prefix = T("IGUI_GS_TerminalEditorTitle"), name = self.row.label } })
	local originalReflow = self.reflow
	self.reflow = function(panel)
		originalReflow(panel)
		panel:reflowEditor()
		return panel
	end
	self:buildLayout()
end

local function layoutHost(panel)
	local host = panel.contentHost or panel
	local rect = host and host.contentRect and host:contentRect()
	if not rect then
		local frame = panel:contentRect()
		rect = frame and frame.w and { x = 0, y = 0, w = frame.w, h = frame.h } or { x = 0, y = 0, w = 0, h = 0 }
	end
	return host, rect
end

function GS_TerminalEditorUI:destroy()
	GlobalStorageSiK.TerminalTerminalEditor.instance = nil
	if self.close then
		self:close("product")
	else
		self:setVisible(false)
		if self.removeFromUIManager then self:removeFromUIManager() end
	end
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

--- Muestra/oculta la cobertura de ESTE terminal concreto (pedido explicito
--- 2026-08-17: antes "mostrar cobertura" marcaba todas las redes conocidas
--- desde 2 sitios genericos - ahora es por terminal, desde su propio modal).
function GS_TerminalEditorUI:onToggleCoverage()
	local marking = GlobalStorageSiK.TerminalBlockedPanel.toggleSingleTerminalCoverage(self.row)
	if self.coverageBtn then
		self.coverageBtn:setText(marking and T("IGUI_GS_HideTerminalCoverage")
			or T("IGUI_GS_ShowTerminalCoverage"))
	end
end

function GS_TerminalEditorUI:onDelete()
	GlobalStorageSiK.NetClient.sendCommand("removeTerminal", {
		x = self.row.x, y = self.row.y, z = self.row.z,
		gsnNetworkId = self.terminal and self.terminal.terminalState and self.terminal.terminalState.networkId,
	})
	self:closeAfterAction()
end

--- Toda eliminación de terminal, también una entrada ausente o rota, requiere
--- confirmación explícita antes de enviar la mutación autoritativa.
function GS_TerminalEditorUI:onDeleteClicked()
	Confirmation.show({
		title = T("IGUI_GS_TerminalEditorTitle"),
		question = T("IGUI_GS_UninstallQuestion"),
		consequences = T("IGUI_GS_UninstallConsequences"),
		onAccept = function() self:onDelete() end,
	})
end

function GS_TerminalEditorUI:buildLayout()
	local host = self.contentHost
	self.editorDock = UI.ScrollDock.create({ parent = host, x = 0, y = 0,
		w = host.width, h = host.height, padding = 0, playerNum = self.playerNum })
	local identity = UI.Block.create({ parent = self.editorDock.contentHost,
		w = host.width, title = T("IGUI_GS_TerminalIdentity"),
		tooltip = T("IGUI_GS_TerminalIdentityHint"), playerNum = self.playerNum })
	self.identityBlock = identity
	self.nameTitle = addCopy(identity.childParent, 0, 0, host.width,
		T("IGUI_GS_TerminalEditorNameLabel"), "text")
	self.nameEntry = UI.Controls.field(identity.childParent, {
		text = self.row.label or "", playerNum = self.playerNum,
		onSubmit = function() self:onRename() end,
	})
	local row = self.row
	self.statusLabel = addCopy(identity.childParent, 0, 0, host.width,
		T("IGUI_GS_TerminalEditorStatus", statusText(row),
			row.controller and T("IGUI_GS_TerminalController") or T("IGUI_GS_TerminalSecondary"))
		.. " " .. T("IGUI_GS_PunctuationMiddleDot") .. " "
		.. string.format("%d, %d, %d", row.x or 0, row.y or 0, row.z or 0), "textMuted")
	self.actionsBlock = UI.Block.create({ parent = self.editorDock.fixedBottomHost,
		w = host.width, title = T("IGUI_GS_PermColActions"),
		tooltip = T("IGUI_GS_TerminalActionsHint"), playerNum = self.playerNum })
	local actions = self.actionsBlock.childParent
	local isActive = not row.missing and row.present ~= false and not row.suspended and not row.unknown
	self.controllerBtn = UI.Controls.button(actions, {
		text = T("IGUI_GS_TerminalEditorMakeControllerBtn"), enabled = isActive and not row.controller,
		playerNum = self.playerNum, onClick = function() self:onSetController() end })
	self.suspendBtn = UI.Controls.button(actions, {
		text = T("IGUI_GS_TerminalEditorSuspendBtn"), enabled = isActive,
		playerNum = self.playerNum, onClick = function() self:onSuspend() end })
	self.deleteBtn = UI.Controls.button(actions, {
		text = T("IGUI_GS_TerminalEditorDeleteBtn"), danger = true,
		playerNum = self.playerNum, onClick = function() self:onDeleteClicked() end })
	self:reflowEditor()
	UI.Modal.fitContent(self, self.identityBlock.h + self.actionsBlock.h + 8,
		{ bottomPadding = 0, center = true })
	self:reflowEditor()
end

function GS_TerminalEditorUI:reflowEditor()
	if not self.editorDock or self._layoutBusy then return end
	self._layoutBusy = true
	local host = self.contentHost
	self.editorDock:reflow({ x = 0, y = 0, w = host.width, h = host.height })
	local width = self.editorDock:getContentRect().w
	self.identityBlock:setBounds(0, 0, width, self.identityBlock.h)
	local identity = self.identityBlock:beginColumn()
	identity:block(self.nameTitle, self.nameTitle.height)
	identity:block(self.nameEntry, CONTROL_METRICS.inputHeight)
	identity:block(self.statusLabel, self.statusLabel.height)
	self.editorDock:setContentHeight(identity:finish())
	self.actionsBlock:setBounds(0, 0, host.width, self.actionsBlock.h)
	local actions = self.actionsBlock:beginColumn()
	actions:row(CONTROL_METRICS.buttonHeight, {
		{ widget = self.controllerBtn }, { widget = self.suspendBtn },
		{ widget = self.deleteBtn } })
	self.editorDock:setFixedBottomHeight(actions:finish())
	self._layoutBusy = false
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
	UI.Modal.show(ui)
	GlobalStorageSiK.TerminalTerminalEditor.instance = ui
end

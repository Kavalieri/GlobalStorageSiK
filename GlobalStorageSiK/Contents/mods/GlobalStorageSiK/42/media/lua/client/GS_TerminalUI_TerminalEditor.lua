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

GlobalStorageSiK.TerminalTerminalEditor = {}
GlobalStorageSiK.TerminalTerminalEditor.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local PAD = 14
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
		kind = "compact", padding = PAD, resizable = false,
		title = T("IGUI_GS_TerminalEditorTitle"),
		onClose = function()
			GlobalStorageSiK.TerminalTerminalEditor.instance = nil
		end,
	})
	self:buildLayout()
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
	UI.Modal.confirm({
		message = T("IGUI_GS_UninstallConfirm"),
		onAccept = function() self:onDelete() end,
	})
end

function GS_TerminalEditorUI:buildLayout()
	local content = self:contentRect()
	local pad = content.x
	local y = content.y
	local textW = content.w
	local row = self.row

	local coordsLbl = addCopy(self, pad, y, textW,
		string.format("%d, %d, %d", row.x or 0, row.y or 0, row.z or 0))
	y = y + coordsLbl.height + 2

	local statusLbl = addCopy(self, pad, y, textW,
		T("IGUI_GS_TerminalEditorStatus", statusText(row), row.controller and T("IGUI_GS_TerminalController") or T("IGUI_GS_TerminalSecondary")),
		"textMuted")
	y = y + statusLbl.height + LINE_GAP + 4

	-- ── Nombre ───────────────────────────────────────────────────────────
	local nameTitle = addCopy(self, pad, y, textW,
		T("IGUI_GS_TerminalEditorNameLabel"), "text")
	y = y + nameTitle.height + 4

	local renameW = 110
	self.nameEntry = UI.Controls.field(self, {
		x = pad, y = y, w = textW - renameW - 6,
		h = CONTROL_METRICS.inputHeight, text = row.label or "",
		playerNum = self.playerNum,
	})

	self.renameBtn = UI.Controls.button(self, {
		x = pad + textW - renameW, y = y, w = renameW,
		h = CONTROL_METRICS.inputHeight,
		text = T("IGUI_GS_TerminalEditorRenameBtn"),
		onClick = function() self:onRename() end,
	})
	y = y + CONTROL_METRICS.inputHeight + LINE_GAP + 8

	-- ── Acciones ─────────────────────────────────────────────────────────
	local isActive = not row.missing and row.present ~= false and not row.suspended and not row.unknown
	if isActive and not row.controller then
		self.controllerBtn = UI.Controls.button(self, {
			x = pad, y = y, w = textW, h = CONTROL_METRICS.buttonHeight,
			text = T("IGUI_GS_TerminalEditorMakeControllerBtn"), fullWidth = true,
			onClick = function() self:onSetController() end,
		})
		y = y + CONTROL_METRICS.buttonHeight + LINE_GAP
	end

	if isActive then
		self.suspendBtn = UI.Controls.button(self, {
			x = pad, y = y, w = textW, h = CONTROL_METRICS.buttonHeight,
			text = T("IGUI_GS_TerminalEditorSuspendBtn"), fullWidth = true,
			onClick = function() self:onSuspend() end,
		})
		y = y + CONTROL_METRICS.buttonHeight + LINE_GAP
	end

	local coverageLabel = GlobalStorageSiK.TerminalBlockedPanel._singleMarking
		and GlobalStorageSiK.TerminalBlockedPanel._singleMarkedRow == row
		and T("IGUI_GS_HideTerminalCoverage") or T("IGUI_GS_ShowTerminalCoverage")
	self.coverageBtn = UI.Controls.button(self, {
		x = pad, y = y, w = textW, h = CONTROL_METRICS.buttonHeight,
		text = coverageLabel, fullWidth = true,
		onClick = function() self:onToggleCoverage() end,
	})
	y = y + CONTROL_METRICS.buttonHeight + LINE_GAP

	self.deleteBtn = UI.Controls.button(self, {
		x = pad, y = y, w = textW, h = CONTROL_METRICS.buttonHeight,
		text = T("IGUI_GS_TerminalEditorDeleteBtn"), danger = true, fullWidth = true,
		onClick = function() self:onDeleteClicked() end,
	})
	y = y + CONTROL_METRICS.buttonHeight + pad

	UI.Modal.fitContent(self, y - content.y, { bottomPadding = 0, center = true })
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

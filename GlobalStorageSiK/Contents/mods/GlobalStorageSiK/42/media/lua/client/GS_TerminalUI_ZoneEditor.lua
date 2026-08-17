--[[
	GlobalStorageSiK - Editor modal de zona
	Autor: SiK
	Descripción: Ventana simple para renombrar, priorizar (escala 1-100,
	igual que los contenedores) y eliminar una zona. Se abre al pulsar
	sobre la cabecera de una zona en la sección Contenedores (bloque
	"nodos" de la pestaña Red), calcada en estructura del editor de
	contenedor (GS_TerminalUI_NodeEditor.lua) pero mucho mas simple: sin
	categorias ni listado de contenido, solo nombre/prioridad/eliminar.
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISModalDialog"
require "GS_I18n"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Chrome"
require "GS_NetClient"
require "GS_NodeHighlight"
require "GS_TerminalUI_NodeEditor"

GlobalStorageSiK.TerminalZoneEditor = {}
GlobalStorageSiK.TerminalZoneEditor.instance = nil

GS_ZoneEditorUI = ISPanel:derive("GS_ZoneEditorUI")

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local ENTRY_H = FONT_HGT_SMALL + 6
local BTN_H = FONT_HGT_SMALL + 10
local PAD = 10
local PANEL_W = 420

local function createBtn(x, y, w, title, target, onClick)
	return GlobalStorageSiK.TerminalChrome.createNeatButton(x, y, w, BTN_H, title, target, onClick)
end

function GS_ZoneEditorUI:new(x, y, w, h)
	local o = ISPanel:new(x, y, w, h)
	setmetatable(o, self)
	self.__index = self
	o.moveWithMouse = false
	o.drawBackground = false
	o.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	o.borderColor = { r = 0, g = 0, b = 0, a = 1 }
	o.padding = PAD
	o.headerHeight = math.floor(FONT_HGT_MEDIUM * 1.4)
	return o
end

--- Arrastrar por la cabecera para mover la ventana - el NodeEditor (editor
--- de contenedor) ya hace esto mismo; sin esto el modal se quedaba fijo en
--- el sitio donde se abrio, sin forma de apartarlo de en medio.
function GS_ZoneEditorUI:installMouseHandlers()
	self.onMouseDown = function(me, x, y)
		if y >= 0 and y < me.headerHeight and x < me.width - (me.closeBtn and me.closeBtn.width or 36) then
			me.moving = true
			me:setCapture(true)
			return true
		end
		return ISPanel.onMouseDown(me, x, y)
	end
	self.onMouseUp = function(me, x, y)
		if me.moving then
			me.moving = false
			me:setCapture(false)
			return true
		end
		return ISPanel.onMouseUp(me, x, y)
	end
	self.onMouseUpOutside = self.onMouseUp
	self.onMouseMove = function(me, dx, dy)
		if me.moving then
			me:setX(me.x + dx)
			me:setY(me.y + dy)
			return true
		end
		return ISPanel.onMouseMove(me, dx, dy)
	end
	self.onMouseMoveOutside = self.onMouseMove
end

function GS_ZoneEditorUI:calculateLayout()
	local closeSize = math.max(FONT_HGT_MEDIUM, 24)
	if self.closeBtn then
		self.closeBtn:setX(self.width - closeSize - self.padding)
		self.closeBtn:setY(math.floor((self.headerHeight - closeSize) / 2))
		self.closeBtn:setWidth(closeSize)
		self.closeBtn:setHeight(closeSize)
		self.closeBtn:bringToTop()
	end
end

function GS_ZoneEditorUI:initialise()
	ISPanel.initialise(self)
	self.clipChildren = true
	self:setVisible(true)
	self:setAlwaysOnTop(true)
	self:installMouseHandlers()
	self.closeBtn = GlobalStorageSiK.TerminalChrome.createCloseButton(self, self, function()
		GlobalStorageSiK.TerminalZoneEditor.close()
	end)
	self:buildForm()
	self:calculateLayout()
end

function GS_ZoneEditorUI:prerender()
	ISPanel.prerender(self)
	GlobalStorageSiK.TerminalChrome.renderPanelBackground(self)
	local title = T("IGUI_GS_ZoneEditorTitle") .. ": " .. (self.zone and self.zone.name or "?")
	local titleY = math.floor((self.headerHeight - FONT_HGT_MEDIUM) / 2)
	self:drawText(title, self.padding + 2, titleY, 1, 1, 1, 1, UIFont.Medium)
	if self.closeBtn then
		self.closeBtn:bringToTop()
	end
end

--- Envia el cambio de prioridad al servidor y refleja el valor localmente.
--- Los atajos Alta/Normal/Baja siguen aplicando de inmediato (accion
--- explicita de un solo valor, no arriesgan perder otro campo pendiente).
---@param n number
function GS_ZoneEditorUI:applyPriority(n)
	n = math.floor(n + 0.5)
	if n < 1 then n = 1 elseif n > 100 then n = 100 end
	if self.priorityEntry then
		self.priorityEntry:setText(tostring(n))
	end
	if self.terminal and self.terminal.onSetZonePriority and self.zone then
		self.terminal:onSetZonePriority(self.zone.id, n)
	end
end

--- Aplica TODOS los campos pendientes (nombre + prioridad) de una vez. Antes
--- cada campo tenia su propio boton "Aplicar"; si el jugador cambiaba varios
--- y solo pulsaba uno, el otro se perdia en el siguiente sync del servidor
--- (ver syncZoneData, que ya no pisa los campos directamente, pero antes si
--- lo hacia). Un unico boton evita ese riesgo por diseño: todo se manda junto.
function GS_ZoneEditorUI:applyAll()
	if not self.zone or not self.terminal then return end
	local name = self.nameEntry and self.nameEntry:getText() or ""
	if name ~= "" and name ~= self.zone.name and self.terminal.onRenameZone then
		self.terminal:onRenameZone(self.zone.id, name)
		self.zone.name = name
	end
	local n = tonumber(self.priorityEntry and self.priorityEntry:getText() or "")
	if n and math.floor(n + 0.5) ~= (self.zone.priority or 50) then
		self:applyPriority(n)
	end
end

local function countZoneNodes(nodes, zoneId)
	local count = 0
	for i = 1, #(nodes or {}) do
		if nodes[i].zoneId == zoneId then count = count + 1 end
	end
	return count
end

--- Confirma y aplica la plantilla copiada a todos los contenedores actuales de
--- esta zona en una sola orden. La confirmacion es deliberada: reemplaza
--- categorias, filtros y prioridad de varios nodos, aunque conserva identidad,
--- nombre, etiqueta, membresia y estado.
function GS_ZoneEditorUI:confirmApplyNodeTemplate()
	local template = GlobalStorageSiK.TerminalNodeEditor
		and GlobalStorageSiK.TerminalNodeEditor.configTemplate or nil
	if not template or not self.zone then return end
	local count = countZoneNodes(self.allNodes, self.zone.id)
	local message = T("IGUI_GS_ZoneTemplateConfirm", count, self.zone.name or "?", template.sourceName or "?")
	local function onResult(_, button)
		if not button or button.internal ~= "YES" then return end
		GlobalStorageSiK.NetClient.sendCommand("applyNodeTemplateToZone", {
			zoneId = self.zone.id,
			categories = template.categories or {},
			filters = template.filters or {},
			priority = template.priority or 50,
		})
	end
	local modal = ISModalDialog:new(0, 0, 520, 220, message, true, nil, onResult, nil)
	modal:initialise()
	modal:addToUIManager()
	modal:setX(getCore():getScreenWidth() / 2 - modal.width / 2)
	modal:setY(getCore():getScreenHeight() / 2 - modal.height / 2)
end

function GS_ZoneEditorUI:buildForm()
	local pad = self.padding
	local y = self.headerHeight + pad
	local innerW = self.width - pad * 2

	self.nameLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_ZoneRenameLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	self.nameLbl:initialise()
	self:addChild(self.nameLbl)
	y = y + FONT_HGT_SMALL + 2

	-- Nombre y prioridad ya NO tienen cada uno su propio "Aplicar": un solo
	-- clic en "Aplicar cambios" (mas abajo) manda ambos juntos - ver applyAll.
	self.nameEntry = ISTextEntryBox:new(self.zone and self.zone.name or "", pad, y, innerW, ENTRY_H)
	self.nameEntry:initialise()
	GlobalStorageSiK.TerminalChrome.styleTextEntry(self.nameEntry)
	self.nameEntry:instantiate()
	self:addChild(self.nameEntry)
	y = y + ENTRY_H + 12

	-- Etiqueta + pista en 2 lineas (no concatenadas en una sola): la pista
	-- ("1 = maxima prioridad, 100 = minima") desbordaba el ancho del panel
	-- en una sola linea, saliendose visualmente del modal.
	self.priorityLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_ZonePriorityLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	self.priorityLbl:initialise()
	self:addChild(self.priorityLbl)
	y = y + FONT_HGT_SMALL + 2
	self.priorityHintLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_ZonePriorityHint"), 0.5, 0.54, 0.58, 1, UIFont.Small, true)
	self.priorityHintLbl:initialise()
	self:addChild(self.priorityHintLbl)
	y = y + FONT_HGT_SMALL + 2

	self.priorityEntry = ISTextEntryBox:new(tostring((self.zone and self.zone.priority) or 50), pad, y, innerW, ENTRY_H)
	self.priorityEntry:initialise()
	GlobalStorageSiK.TerminalChrome.styleTextEntry(self.priorityEntry)
	self.priorityEntry:instantiate()
	if self.priorityEntry.setOnlyNumbers then self.priorityEntry:setOnlyNumbers(true) end
	self:addChild(self.priorityEntry)
	y = y + ENTRY_H + 4

	local presetW = math.floor((innerW - 8) / 3)
	self.priorityPresetHighBtn = createBtn(pad, y, presetW, T("IGUI_GS_NodePriorityPresetHigh"), self, function() self:applyPriority(10) end)
	self:addChild(self.priorityPresetHighBtn)
	self.priorityPresetNormalBtn = createBtn(pad + presetW + 4, y, presetW, T("IGUI_GS_NodePriorityPresetNormal"), self, function() self:applyPriority(50) end)
	self:addChild(self.priorityPresetNormalBtn)
	self.priorityPresetLowBtn = createBtn(pad + (presetW + 4) * 2, y, presetW, T("IGUI_GS_NodePriorityPresetLow"), self, function() self:applyPriority(90) end)
	self:addChild(self.priorityPresetLowBtn)
	y = y + BTN_H + 12

	self.applyAllBtn = createBtn(pad, y, innerW, T("IGUI_GS_ApplyAllChanges"), self, function()
		self:applyAll()
	end)
	self:addChild(self.applyAllBtn)
	y = y + BTN_H + 16

	local bulkTitle = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_ZoneTemplateTitle"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	bulkTitle:initialise()
	self:addChild(bulkTitle)
	y = y + FONT_HGT_SMALL + 3
	local template = GlobalStorageSiK.TerminalNodeEditor
		and GlobalStorageSiK.TerminalNodeEditor.configTemplate or nil
	local summary = template
		and T("IGUI_GS_ZoneTemplateReady", template.sourceName or "?", #(template.categories or {}), #(template.filters or {}), template.priority or 50)
		or T("IGUI_GS_ZoneTemplateEmpty")
	for _, line in ipairs(GlobalStorageSiK.TerminalChrome.wrapTextLines(summary, innerW, UIFont.Small)) do
		local lbl = ISLabel:new(pad, y, FONT_HGT_SMALL, line, 0.5, 0.54, 0.58, 1, UIFont.Small, true)
		lbl:initialise()
		self:addChild(lbl)
		y = y + FONT_HGT_SMALL + 2
	end
	self.applyTemplateBtn = createBtn(pad, y, innerW, T("IGUI_GS_ZoneTemplateApply"), self, function()
		self:confirmApplyNodeTemplate()
	end)
	self.applyTemplateBtn:setEnable(template ~= nil)
	if self.applyTemplateBtn.setToolTipMap then
		self.applyTemplateBtn:setToolTipMap({ toolTip = T("IGUI_GS_ZoneTemplateApplyTooltip") })
	end
	self:addChild(self.applyTemplateBtn)
	y = y + BTN_H + 16

	self.deleteBtn = createBtn(pad, y, innerW, T("IGUI_GS_DeleteZone"), self, function()
		self:confirmDelete()
	end)
	self:addChild(self.deleteBtn)
	y = y + BTN_H + pad

	self:setHeight(y)
	self:repositionRelativeToTerminal()
end

--- Recalcula X/Y con la altura REAL ya fijada por buildLayout (nunca con la
--- altura provisional pasada al construir) - relativo al terminal si esta
--- disponible, si no centrado en pantalla, siempre clampeado para no salirse
--- de los bordes. Antes se calculaba una sola vez con h=320 adivinado ANTES
--- de construir el contenido y nunca se recolocaba, igual bug que tenia
--- GS_TerminalUI_MemberEditor.lua/TerminalEditor.lua antes de corregirlo.
function GS_ZoneEditorUI:repositionRelativeToTerminal()
	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	local terminal = self.terminal
	local x, y
	if terminal and terminal.getX and terminal.getY and terminal.getWidth and terminal.getHeight then
		x = terminal:getX() + (terminal:getWidth() - self.width) / 2
		y = terminal:getY() + (terminal:getHeight() - self.height) / 2
	else
		x = (sw - self.width) / 2
		y = (sh - self.height) / 2
	end
	x = math.floor(math.max(0, math.min(x, sw - self.width)))
	y = math.floor(math.max(0, math.min(y, sh - self.height)))
	self:setX(x)
	self:setY(y)
end

function GS_ZoneEditorUI:confirmDelete()
	local function onResult(_, button)
		if button and button.internal == "YES" and self.zone and self.terminal then
			self.terminal:onDeleteZone(self.zone.id)
			GlobalStorageSiK.TerminalZoneEditor.close()
		end
	end
	local modal = ISModalDialog:new(0, 0, 400, 160, T("IGUI_GS_ZoneDeleteConfirm", self.zone and self.zone.name or "?"), true, nil, onResult, nil)
	modal:initialise()
	modal:addToUIManager()
	modal:setX(getCore():getScreenWidth() / 2 - modal.width / 2)
	modal:setY(getCore():getScreenHeight() / 2 - modal.height / 2)
end

--- Abre el editor modal para una zona.
---@param terminal GS_TerminalUI|nil
---@param zone table
---@param allNodes table[]|nil
function GlobalStorageSiK.TerminalZoneEditor.open(terminal, zone, allNodes)
	if not zone then
		return
	end
	local existing = GlobalStorageSiK.TerminalZoneEditor.instance
	if existing and existing.zone and existing.zone.id == zone.id then
		existing:bringToTop()
		return
	end
	GlobalStorageSiK.TerminalZoneEditor.close()

	-- Posicion/alto provisionales - buildLayout() fija la altura real segun
	-- el contenido y repositionRelativeToTerminal() recoloca con esa altura
	-- ya definitiva, no con esta suposicion inicial.
	local ui = GS_ZoneEditorUI:new(0, 0, PANEL_W, 100)
	ui.terminal = terminal
	ui.zone = zone
	ui.allNodes = allNodes or {}
	ui:initialise()
	ui:addToUIManager()
	GlobalStorageSiK.TerminalZoneEditor.instance = ui

	if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.highlightZone then
		GlobalStorageSiK.NodeHighlight.highlightZone(zone.id, zone.name, allNodes or {})
	end
end

--- Cierra el editor si está abierto.
function GlobalStorageSiK.TerminalZoneEditor.close()
	local ui = GlobalStorageSiK.TerminalZoneEditor.instance
	if not ui then
		return
	end
	ui:setVisible(false)
	ui:removeFromUIManager()
	GlobalStorageSiK.TerminalZoneEditor.instance = nil
	if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.clear then
		GlobalStorageSiK.NodeHighlight.clear()
	end
end

--- Sincroniza datos de zona tras un refresco de estado del servidor.
--- NO toca nameEntry/priorityEntry: son campos de edicion en curso del
--- jugador (ver applyAll, boton unico) y este sync puede llegar en cualquier
--- momento mientras el editor esta abierto (p.ej. tras aplicar OTRO campo, o
--- tras un rescan). Pisarlos aqui perdia en silencio texto/valores aun no
--- aplicados - el bug real que se reportaba como "se resetean los campos no
--- aplicados". Solo se actualiza ui.zone (usado por el titulo y por
--- confirmDelete), la fuente de verdad para los widgets es lo que el
--- jugador este escribiendo ahora mismo.
---@param zones table[]
function GlobalStorageSiK.TerminalZoneEditor.syncZoneData(zones)
	local ui = GlobalStorageSiK.TerminalZoneEditor.instance
	if not ui or not ui.zone then
		return
	end
	for i = 1, #(zones or {}) do
		if zones[i].id == ui.zone.id then
			ui.zone = zones[i]
			return
		end
	end
end

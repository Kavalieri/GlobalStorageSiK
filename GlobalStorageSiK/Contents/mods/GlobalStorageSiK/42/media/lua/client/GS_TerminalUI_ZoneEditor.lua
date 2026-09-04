--[[
	GlobalStorageSiK - Editor modal de zona
	Autor: SiK
	Descripción: Ventana para renombrar, priorizar (escala 1-100, igual que
	los contenedores), configurar el protocolo de reglas y eliminar una
	zona. Se abre al pulsar sobre la cabecera de una zona en la sección
	Contenedores (bloque "nodos" de la pestaña Red). Mismo "casco" de
	ventana (tamaño inicial, mínimos, redimensionable con asa en la
	esquina, scroll interno) que GS_TerminalUI_NodeEditor.lua - dev26 ronda
	4, pedido explícito de coherencia entre ambos editores - el contenido
	sigue siendo mucho más simple: sin listado de contenido de contenedor.
]]

require "GS_I18n"
require "GS_NetClient"
require "GS_NodeHighlight"
require "GS_RulesUI"
require "GS_FilterEditor"
local UI = require "GS_UI_Framework"

GlobalStorageSiK.TerminalZoneEditor = {}
GlobalStorageSiK.TerminalZoneEditor.instance = nil

GS_ZoneEditorUI = UI.Window.derive("GS_ZoneEditorUI")

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local CONTROL_METRICS = UI.Controls.metrics("editor")
local PALETTE = UI.Theme.palette()
local PAD = 10
local INFO_BTN_SIZE = FONT_HGT_SMALL

-- Conserva los rectangulos aprobados del editor y deja a SiK.UI la
-- construccion, el chrome y el lifecycle de las hojas visibles.
local function createText(parent, x, y, w, text, color)
	color = color or PALETTE.textMuted
	local copy = UI.Controls.copyText(parent, {
		x = x, y = y, w = math.max(1, w), text = text,
		font = UIFont.Small, lineGap = 0, tone = "editorText",
		theme = { editorText = {
			r = color[1], g = color[2], b = color[3], a = color[4] or 1,
		} },
	})
	if copy.setMouseTransparent then copy:setMouseTransparent(true) end
	return copy
end

local function createHost(parent, x, y, w, h)
	return UI.Controls.panel(parent, {
		x = x, y = y, w = w, h = h, controlId = "editorHost",
	})
end

local function createField(text, x, y, w, numeric)
	return UI.Controls.field(nil, {
		x = x, y = y, w = w, h = CONTROL_METRICS.inputHeight,
		text = text, numeric = numeric == true,
	})
end

local function addSummaryRuns(host, layout)
	for i = 1, #(layout and layout.runs or {}) do
		local run = layout.runs[i]
		local color = run.color
		createText(host, run.x, (run.line - 1) * (FONT_HGT_SMALL + 2),
			math.max(1, host.width - run.x), run.text, color)
	end
end

--- Coloca un boton "?" justo despues de un titulo de bloque ya creado, con
--- el texto largo que antes vivia siempre visible debajo como parrafo -
--- dev26 ronda 4, mismo helper que GS_TerminalUI_NodeEditor.lua.
---@param scroll table
---@param pad number
---@param y number
---@param titleText string
---@param tooltip string
---@param target any
local function addBlockInfoBtn(scroll, pad, y, titleText, tooltip, target)
	local titleW = getTextManager():MeasureStringX(UIFont.Small, titleText)
	local btn = UI.Controls.iconButton(nil, {
		x = pad + titleW + 6, y = y, w = INFO_BTN_SIZE, h = INFO_BTN_SIZE,
		text = "?", tooltip = tooltip, payload = target,
	})
	UI.Scroll.addChild(scroll, btn)
	return btn
end

-- fullWidth=true, mismo motivo que GS_TerminalUI_NodeEditor.lua.
local function createBtn(x, y, w, title, target, onClick)
	return UI.Controls.button(nil, {
		x = x, y = y, w = w, h = CONTROL_METRICS.buttonHeight,
		text = title, fullWidth = true, payload = target,
		onClick = function() return onClick(target) end,
	})
end

local function createSectionLabel(x, y, text)
	local width = getTextManager():MeasureStringX(UIFont.Small, text) + 2
	return UI.Controls.sectionTitle(nil, {
		x = x, y = y, w = width, h = FONT_HGT_SMALL, text = text,
	})
end

local function createSectionCard(scroll, x, y, w, h, color)
	local container = UI.Container.create({ parent = UI.Scroll.childHost(scroll),
		x = x, y = y, w = w, h = h, padding = 0, accent = color,
		background = { r = 0.08, g = 0.08, b = 0.08, a = 0.72 },
		border = { r = 0.28, g = 0.28, b = 0.28, a = 0.70 },
	})
	return container and container.panel or nil
end

local function createProductButton(x, y, w, h, title, target, onClick,
	activeColor, fullWidth)
	local button = UI.Controls.button(nil, {
		x = x, y = y, w = w, h = h, text = title,
		payload = target, fullWidth = fullWidth == true,
		danger = activeColor ~= nil,
		onClick = function() return onClick(target) end,
	})
	if activeColor then
		button.backgroundColor = { r = activeColor[1], g = activeColor[2],
			b = activeColor[3], a = activeColor[4] or 0.92 }
	end
	return button
end

local function confirmAction(message, onAccept)
	return UI.Modal.confirm({ message = message, onAccept = onAccept })
end

--- Color de acento por operador (mismo trio que GS_TerminalUI_NodeEditor.lua,
--- los puntos de composicion de la lista de contenedores y el borde del
--- modal "Anadir regla" - nunca inventado por separado).
local RULE_OP_COLOR = {
	OR  = PALETTE.ruleOr,
	AND = PALETTE.ruleAnd,
	NOT = PALETTE.ruleNot,
}

--- Contenedores de una zona (dev26 ronda 3, linea informativa). Se queda
--- deliberadamente en esto y no intenta sumar objetos/tipos: esos numeros
--- viven en GlobalStorageSiK.Client.nodeContentsCache, poblado solo para
--- contenedores cuyo editor se ha abierto individualmente - la mayoria de
--- contenedores de una zona nunca se han visitado, así que agregar desde
--- ahi mostraria "0 objetos" en la mayoria de zonas, mas enganoso que util.
--- Objetos/tipos por zona necesitaria su propio endpoint agregado en el
--- servidor (igual que GS_NetworkCapacity.lua para el peso de toda la red) -
--- trabajo aparte, no improvisado aqui.
---@param zone table
---@param terminal table
---@return number containerCount
local function zoneContainerCount(zone, terminal)
	if not zone then return 0 end
	local nodes = terminal and terminal.terminalState and terminal.terminalState.nodes or {}
	local count = 0
	for i = 1, #nodes do
		if nodes[i].zoneId == zone.id then count = count + 1 end
	end
	return count
end

--- Ocupacion (%peso) de la zona (dev26 ronda 4) - mismo formateador que
--- GS_TerminalUI_NodeEditor.lua, pero el dato llega via self.capacityInfo
--- (GS_ZoneEditorUI:onCapacityReceived), no de un payload de contenido -
--- ver GS_Server.lua:getZoneCapacity / GS_NetworkCapacity.computeZone.
---@param capacity table|nil
---@return string
local function occupancyLabelText(capacity)
	if not capacity then
		return T("IGUI_GS_OccupancyUnknown")
	end
	return T("IGUI_GS_OccupancyLine", capacity.percent or 0, capacity.usedWeight or 0, capacity.capacity or 0)
end

function GS_ZoneEditorUI:new(x, y, w, h)
	local o = UI.Window.newInstance(self, x, y, w, h)
	o.moveWithMouse = false
	o.drawBackground = false
	o.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	o.borderColor = { r = 0, g = 0, b = 0, a = 1 }
	o.padding = PAD
	o.headerHeight = math.floor(FONT_HGT_MEDIUM * 1.4)
	o._formBuilt = false
	return o
end

--- Ajusta el formulario al ancho actual, igual que GS_TerminalUI_NodeEditor.lua
--- (rebuild completo, mas simple y correcto que replicar el calculo de
--- anchos aqui). Guardia por ancho: durante un arrastre de redimensionado,
--- calculateLayout se llama en cada frame.
function GS_ZoneEditorUI:layoutForm()
	if not self._formBuilt or not self.editorScroll then
		return
	end
	local innerW = UI.Scroll.contentWidth(self.editorScroll)
	if self._lastLayoutW == innerW then
		return
	end
	self._lastLayoutW = innerW
	self:rebuildForm()
end

function GS_ZoneEditorUI:calculateLayout()
	local content = self.contentRect and self:contentRect()
		or { x = PAD, y = self.headerHeight + PAD,
			w = self.width - PAD * 2, h = self.height - self.headerHeight - PAD * 2 }
	local bodyH = math.max(120,
		content.h - UI.Scroll.listBottomGap())
	if self.editorScroll then
		self.editorScroll:setX(content.x)
		self.editorScroll:setY(content.y)
		UI.Scroll.resize(self.editorScroll, content.w, bodyH)
		self:layoutForm()
		self:updateScrollHeight()
	end
end

function GS_ZoneEditorUI:initialise()
	UI.Window.callBase(self, "initialise")
	UI.Window.applyEditor(self, {
		geometryKey = "zoneEditor",
		title = T("IGUI_GS_ZoneEditorTitle"),
		padding = PAD,
		onReflow = function() self:calculateLayout() end,
		onClose = function()
			GlobalStorageSiK.TerminalZoneEditor.instance = nil
			if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.clear then
				GlobalStorageSiK.NodeHighlight.clear()
			end
		end,
	})
	self.clipChildren = true
	self:setVisible(true)
	self:setAlwaysOnTop(true)
	self:createChildren()
	self:calculateLayout()
end

function GS_ZoneEditorUI:createChildren()
	if self._gsChildrenBuilt then return end
	self._gsChildrenBuilt = true
	-- El chrome se construye una sola vez por SiK.UI.Window.applyEditor().
	-- Crear otra X aquí registraba un segundo control que PZ podía conservar
	-- como raíz al cerrar el editor.
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
		if self.setHeader then
			self:setHeader(T("IGUI_GS_ZoneEditorTitle") .. ": " .. name)
		end
	end
	local n = tonumber(self.priorityEntry and self.priorityEntry:getText() or "")
	if n and math.floor(n + 0.5) ~= (self.zone.priority or 50) then
		self:applyPriority(n)
	end
end

--- Reconstruye el formulario dentro de editorScroll (llamar solo desde
--- rebuildForm/setZone) - igual que GS_TerminalUI_NodeEditor.lua:ensureForm.
function GS_ZoneEditorUI:ensureForm()
	local terminal = self.terminal
	local zone = self.zone
	if not terminal or not zone or not self.editorScroll then
		return
	end
	if self._formBuilt then
		self:layoutForm()
		return
	end

	local scroll = self.editorScroll
	UI.Scroll.clear(scroll, false)

	local pad = 8
	local y = pad
	local innerW = UI.Scroll.contentWidth(scroll)

	-- ── Linea informativa (dev26, ronda 3): cuantos contenedores tiene esta
	-- zona - ver zoneContainerCount arriba para por que NO intenta sumar
	-- objetos/tipos todavia (esa cuenta agregada es trabajo aparte). dev26
	-- ronda 4ter: movida ANTES del nombre (mismo orden que
	-- GS_TerminalUI_NodeEditor.lua - el bloque de informacion siempre
	-- precede al campo editable, en las dos ventanas).
	local zContainerCount = zoneContainerCount(self.zone, self.terminal)
	self.statsLbl = createText(nil, pad, y, innerW,
		T("IGUI_GS_ZoneStatsLine", zContainerCount), PALETTE.textMuted)
	UI.Scroll.addChild(scroll, self.statsLbl)
	y = y + FONT_HGT_SMALL + 2

	self.occupancyLbl = createText(nil, pad, y, innerW,
		occupancyLabelText(self.capacityInfo), PALETTE.textMuted)
	UI.Scroll.addChild(scroll, self.occupancyLbl)
	y = y + FONT_HGT_SMALL + 10

	self.nameLbl = createSectionLabel(pad, y, T("IGUI_GS_ZoneRenameLabel"))
	UI.Scroll.addChild(scroll, self.nameLbl)
	y = y + FONT_HGT_SMALL + 2

	-- Nombre y prioridad ya NO tienen cada uno su propio "Aplicar": un solo
	-- clic en "Aplicar cambios" (mas abajo) manda ambos juntos - ver applyAll.
	self.nameEntry = createField(self.zone and self.zone.name or "", pad, y, innerW, false)
	UI.Scroll.addChild(scroll, self.nameEntry)
	y = y + CONTROL_METRICS.inputHeight + 12

	-- Mismo esqueleto de frase pedagogica que GS_TerminalUI_NodeEditor.lua
	-- (solo cambia "zona" por "contenedor") - texto largo, envuelto linea a
	-- linea con wrapTextLines (regla 7, CLAUDE.md): una sola ISLabel se
	-- saldria del ancho del panel.
	self.priorityLbl = createSectionLabel(pad, y, T("IGUI_GS_ZonePriorityLabel"))
	UI.Scroll.addChild(scroll, self.priorityLbl)
	addBlockInfoBtn(scroll, pad, y, T("IGUI_GS_ZonePriorityLabel"), T("IGUI_GS_ZonePriorityHint"), scroll)
	y = y + FONT_HGT_SMALL + 4

	self.priorityEntry = createField(tostring((self.zone and self.zone.priority) or 50),
		pad, y, innerW, true)
	UI.Scroll.addChild(scroll, self.priorityEntry)
	y = y + CONTROL_METRICS.inputHeight + 4

	local presetW = math.floor((innerW - 8) / 3)
	self.priorityPresetHighBtn = createBtn(pad, y, presetW, T("IGUI_GS_NodePriorityPresetHigh"), scroll, function() self:applyPriority(10) end)
	UI.Scroll.addChild(scroll, self.priorityPresetHighBtn)
	self.priorityPresetNormalBtn = createBtn(pad + presetW + 4, y, presetW, T("IGUI_GS_NodePriorityPresetNormal"), scroll, function() self:applyPriority(50) end)
	UI.Scroll.addChild(scroll, self.priorityPresetNormalBtn)
	self.priorityPresetLowBtn = createBtn(pad + (presetW + 4) * 2, y, presetW, T("IGUI_GS_NodePriorityPresetLow"), scroll, function() self:applyPriority(90) end)
	UI.Scroll.addChild(scroll, self.priorityPresetLowBtn)
	y = y + CONTROL_METRICS.buttonHeight + 16

	-- ── Protocolo de aceptación de zona (dev26, ronda 2) ────────────────────
	-- Puerta binaria evaluada ANTES que las reglas de cada contenedor de esta
	-- zona (ver GS_Router.zoneRulesAllow) - sustituye a la antigua sección
	-- "Plantilla" (aplicar categorías/filtros/prioridad copiados a toda la
	-- zona de una vez), ahora cubierta por "Extender a la zona" desde el
	-- propio editor de contenedor (ver GS_TerminalUI_NodeEditor.lua).
	self.rulesTitleLbl = createSectionLabel(pad, y, T("IGUI_GS_ZoneRulesTitle"))
	UI.Scroll.addChild(scroll, self.rulesTitleLbl)
	addBlockInfoBtn(scroll, pad, y, T("IGUI_GS_ZoneRulesTitle"), T("IGUI_GS_ZoneRulesHint"), scroll)
	y = y + FONT_HGT_SMALL + 8

	local summaryLayout = GlobalStorageSiK.RulesUI.layoutSummary(
		self.zone and self.zone.rules, innerW - pad, UIFont.Small,
		PALETTE.textSecondary)
	local summaryHost = createHost(nil, pad, y, innerW - pad,
		summaryLayout.lineCount * (FONT_HGT_SMALL + 2))
	UI.Scroll.addChild(scroll, summaryHost)
	addSummaryRuns(summaryHost, summaryLayout)
	y = y + summaryHost:getHeight()
	y = y + 6

	for _, op in ipairs(GlobalStorageSiK.RulesUI.OPS) do
		y = self:buildRuleSection(scroll, pad, innerW, y, op)
	end
	y = y + 6
	-- Firma del numero de reglas usada para dimensionar tarjetas/hosts en
	-- ESTE build (ver GlobalStorageSiK.TerminalZoneEditor.syncZoneData) -
	-- mismo bug/mismo fix que GS_TerminalUI_NodeEditor.lua: anadir una regla
	-- dispara rebuildForm() de inmediato via el callback de
	-- GS_FilterEditor.lua ANTES de que zone.rules tenga la regla nueva.
	self._ruleCountAtBuild = #(self.zone and self.zone.rules or {})

	-- ── Acciones (dev26, ronda 3) ────────────────────────────────────────
	-- Aplicar/Excluir/Eliminar agrupados al final, mismo criterio que el
	-- editor de contenedor - antes Aplicar/Excluir vivian arriba, separados
	-- de Eliminar por todo el bloque de protocolo.
	self.applyAllBtn = createBtn(pad, y, innerW, T("IGUI_GS_ApplyAllChanges"), scroll, function()
		self:applyAll()
	end)
	UI.Scroll.addChild(scroll, self.applyAllBtn)
	y = y + CONTROL_METRICS.buttonHeight + 6

	local role = self.terminal and self.terminal.terminalState
		and self.terminal.terminalState.permissions and self.terminal.terminalState.permissions.myRole
	if role == "owner" or role == "admin" then
		self.rescanZoneBtn = createProductButton(
			pad, y, innerW, CONTROL_METRICS.buttonHeight,
			T("IGUI_GS_ZoneCtxRescan"), scroll, function()
				if self.zone and self.terminal and self.terminal.onRescanZone then
					self.terminal:onRescanZone(self.zone.id)
				end
			end)
		UI.Controls.setTooltip(self.rescanZoneBtn, T("IGUI_GS_ZonesManageHint"))
		UI.Scroll.addChild(scroll, self.rescanZoneBtn)
		y = y + CONTROL_METRICS.buttonHeight + 6
	end

	-- Simetrico al de contenedor: unica forma real de sacar TODA una zona
	-- (y por tanto sus contenedores) de deposito/extraccion - ver
	-- GS_Router.matchWithZoneGate. Rojo (PALETTE.statusDanger) SOLO cuando
	-- la accion es excluir, confirmación solo al excluir.
	local zoneExcluded = self.zone and self.zone.enabled == false
	local zoneMembLabel = zoneExcluded and T("IGUI_GS_ZoneBtnInclude") or T("IGUI_GS_ZoneBtnExclude")
	local zoneMembActiveColor = (not zoneExcluded) and PALETTE.statusDanger or nil
	self.zoneMembBtn = createProductButton(pad, y, innerW,
		CONTROL_METRICS.buttonHeight, zoneMembLabel, scroll, function()
		if self.zone and self.zone.enabled == false then
			GlobalStorageSiK.NetClient.sendCommand("setZoneEnabled", { zoneId = self.zone.id, enabled = true })
		else
			self:confirmExcludeZone()
		end
	end, zoneMembActiveColor, true)
	UI.Controls.setTooltip(self.zoneMembBtn, T("IGUI_GS_ZoneExcludeTooltip"))
	UI.Scroll.addChild(scroll, self.zoneMembBtn)
	y = y + CONTROL_METRICS.buttonHeight + 6

	self.deleteBtn = createProductButton(pad, y, innerW,
		CONTROL_METRICS.buttonHeight, T("IGUI_GS_DeleteZone"), scroll, function()
		self:confirmDelete()
	end, PALETTE.statusDanger, true)
	UI.Scroll.addChild(scroll, self.deleteBtn)
	y = y + CONTROL_METRICS.buttonHeight + pad

	self._formBuilt = true
	self:updateScrollHeight(y)
end

--- Crea/actualiza el zona activa del editor (igual que
--- GS_TerminalUI_NodeEditor.lua:setNode) - el scroll se crea perezosamente
--- la primera vez, tras eso solo se reconstruye el contenido.
---@param terminal table|nil
---@param zone table
function GS_ZoneEditorUI:setZone(terminal, zone)
	local sameZone = self.zone and zone and self.zone.id == zone.id
	self.terminal = terminal
	self.zone = zone
	if self.setHeader then
		self:setHeader(T("IGUI_GS_ZoneEditorTitle") .. ": " .. (zone.name or "?"))
	end
	if not sameZone then
		self:resetForm()
		self.capacityInfo = nil
		GlobalStorageSiK.NetClient.sendCommand("getZoneCapacity", { zoneId = zone.id })
	end
	if not self.editorScroll then
		self.editorScroll = UI.Scroll.create(self, PAD, 0, 400, 200, "panel")
	end
	self:calculateLayout()
	self:ensureForm()
	if not self.editorScroll._gsEditorContentRectBound then
		self.editorScroll._gsEditorContentRectBound = true
		UI.Scroll.setOnContentRectChanged(self.editorScroll, function()
			self:layoutForm()
		end)
	end
	self:layoutForm()
end

--- Respuesta de GS_Server.lua:getZoneCapacity (ver GS_Client.lua:onServerCommand,
--- caso "zoneCapacity") - actualiza SOLO el texto de la etiqueta ya creada,
--- sin reconstruir el formulario (evitaria perder texto pendiente de
--- "Aplicar cambios").
---@param capacity table|nil
function GS_ZoneEditorUI:onCapacityReceived(capacity)
	self.capacityInfo = capacity
	if self.occupancyLbl then
		self.occupancyLbl:setText(occupancyLabelText(capacity))
	end
end

--- Recalcula altura scrollable del panel.
---@param bottom number|nil
function GS_ZoneEditorUI:updateScrollHeight(bottom)
	if not self.editorScroll then
		return
	end
	bottom = bottom or self._lastContentBottom or 0
	self._lastContentBottom = bottom
	UI.Scroll.setContentHeight(self.editorScroll, bottom)
end

--- Vacía el contenido del scroll y limpia referencias a widgets del
--- formulario (mismo patron que GS_TerminalUI_NodeEditor.lua:resetForm).
function GS_ZoneEditorUI:resetForm()
	if self.editorScroll then
		UI.Scroll.clear(self.editorScroll, false)
	end
	self._formBuilt = false
	self.nameLbl = nil
	self.nameEntry = nil
	self.statsLbl = nil
	self.occupancyLbl = nil
	self.priorityLbl = nil
	self.priorityEntry = nil
	self.priorityPresetHighBtn = nil
	self.priorityPresetNormalBtn = nil
	self.priorityPresetLowBtn = nil
	self.rulesTitleLbl = nil
	self.applyAllBtn = nil
	self.rescanZoneBtn = nil
	self.zoneMembBtn = nil
	self.deleteBtn = nil
	self._ruleChipsHosts = nil
	self._ruleCards = nil
	self._ruleCountAtBuild = nil
end

--- Construye una sección de reglas de zona (OR/AND/NOT): título, panel de
--- chips y botón "+ Añadir regla <op>" - mismo patrón visual y mismo host de
--- scroll que GS_TerminalUI_NodeEditor.lua (dev26 ronda 4).
---@param scroll table
---@param pad number
---@param innerW number
---@param y number
---@param op string "OR"|"AND"|"NOT"
---@return number newY
function GS_ZoneEditorUI:buildRuleSection(scroll, pad, innerW, y, op)
	local rules = (self.zone and self.zone.rules) or {}
	local count = 0
	for i = 1, #rules do
		if rules[i].op == op then count = count + 1 end
	end
	local CHIP_H, CHIP_PAD = FONT_HGT_SMALL + 8, 3
	local chipsH = (count == 0)
		and (CHIP_PAD + FONT_HGT_SMALL + CHIP_PAD * 2)
		or  (CHIP_PAD + count * (CHIP_H + CHIP_PAD) + CHIP_PAD)

	local cardPad = 8
	local cardTop = y
	local cy = y + cardPad
	local cx = pad + cardPad + 4
	local innerContentW = innerW - pad - cardPad * 2 - 4
	local color = RULE_OP_COLOR[op]

	-- Tarjeta de fondo insertada ANTES que su contenido, redimensionada al
	-- final con el alto real (mismo patron que GS_TerminalUI_NodeEditor.lua
	-- y GS_TerminalUI_NetworkZones.lua) - si se insertara despues, taparia
	-- el titulo/chips/boton en vez de quedar detras.
	local card = createSectionCard(scroll, pad, cardTop, innerW - pad, 10, color)
	UI.Scroll.addChild(scroll, card)
	self._ruleCards = self._ruleCards or {}
	self._ruleCards[op] = card

	local titleLbl = createText(nil, cx, cy, innerContentW,
		T(GlobalStorageSiK.RulesUI.OP_TITLE_KEY[op]), color)
	UI.Scroll.addChild(scroll, titleLbl)
	cy = cy + FONT_HGT_SMALL + 6

	local host = createHost(nil, cx, cy, innerContentW, chipsH)
	UI.Scroll.addChild(scroll, host)
	self._ruleChipsHosts = self._ruleChipsHosts or {}
	self._ruleChipsHosts[op] = host
	self:rebuildRuleChips(op)
	cy = cy + chipsH + 6

	local addBtn = createBtn(cx, cy, innerContentW, T(GlobalStorageSiK.RulesUI.OP_ADD_KEY[op]), scroll, function()
		if not self.zone then return end
		-- containerGroups (dev26, ronda 2 - §4.4-quinquies, caso cruzado
		-- zona->contenedor): un contenedor por cada nodo de esta zona con
		-- reglas propias, para que el detector de contradicciones tambien
		-- avise si esta nueva regla de zona neutraliza algo ya configurado
		-- a nivel de contenedor.
		local containerGroups = {}
		local scopeRules = {}
		local zones = self.terminal and self.terminal.terminalState and self.terminal.terminalState.zones or {}
		for i = 1, #zones do
			local sibling = zones[i]
			if sibling.id ~= self.zone.id then
				for j = 1, #(sibling.rules or {}) do
					scopeRules[#scopeRules + 1] = sibling.rules[j]
				end
			end
		end
		local nodes = self.terminal and self.terminal.terminalState and self.terminal.terminalState.nodes or {}
		for i = 1, #nodes do
			if nodes[i].zoneId == self.zone.id and nodes[i].rules and #nodes[i].rules > 0 then
				containerGroups[#containerGroups + 1] = { name = nodes[i].displayName or nodes[i].name or "?", rules = nodes[i].rules }
			end
		end
		GlobalStorageSiK.FilterEditor.show({ kind = "zone", id = self.zone.id, rules = self.zone.rules, containerGroups = containerGroups, scopeRules = scopeRules }, op, function()
			self:rebuildForm()
		end)
	end)
	UI.Scroll.addChild(scroll, addBtn)
	cy = cy + CONTROL_METRICS.buttonHeight + cardPad

	UI.Layout.apply(card, { x = pad, y = cardTop,
		w = innerW - pad, h = cy - cardTop })
	y = cy + 8
	return y
end

--- Rellena los chips de UN grupo de reglas (OR/AND/NOT) de la zona. Quitar
--- una regla la borra directamente de zone.rules (server-authoritative,
--- mismo patrón que el editor de contenedor) y fuerza un rebuild completo
--- del panel (resumen y alturas de host siempre exactos).
---@param op string
function GS_ZoneEditorUI:rebuildRuleChips(op)
	local host = self._ruleChipsHosts and self._ruleChipsHosts[op]
	if not host then return end
	for i = #(host.childrenInOrder or {}), 1, -1 do
		local ch = host.childrenInOrder[i]
		host:removeChild(ch)
		if ch.removeFromUIManager then ch:removeFromUIManager() end
	end

	local allRules = (self.zone and self.zone.rules) or {}
	local CHIP_H, CHIP_PAD = FONT_HGT_SMALL + 8, 3
	local cy = CHIP_PAD
	local hostW = host.width
	local removeText = T("IGUI_GS_Remove")
	local removeBtnW = UI.Controls.measureButtonWidth(removeText, UIFont.Small, 20, 52, 120)
	local labelMaxW = math.max(20, hostW - removeBtnW - 12)

	local shown = 0
	for realIdx = 1, #allRules do
		local rule = allRules[realIdx]
		if rule.op == op then
			shown = shown + 1
			local label = GlobalStorageSiK.RulesUI.describeCondition(rule.condition)
			label = UI.Controls.truncateText(label, labelMaxW, UIFont.Small)
			local labelColor = GlobalStorageSiK.RulesUI.conditionColor(
				rule.condition, PALETTE.textPrimary)
			createText(host, 4, cy + 2, labelMaxW, label, labelColor)

			local capturedIdx = realIdx
			local removeBtn = createProductButton(
				hostW - removeBtnW - 2, cy, removeBtnW, CHIP_H,
				removeText, host,
				function()
					if not self.zone then return end
					GlobalStorageSiK.NetClient.sendCommand("updateZoneRules", { zoneId = self.zone.id, removeRuleIndex = capturedIdx })
					table.remove(self.zone.rules, capturedIdx)
					self:rebuildForm()
				end
			)
			UI.Controls.setTooltip(removeBtn, removeText)
			host:addChild(removeBtn)
			cy = cy + CHIP_H + CHIP_PAD
		end
	end
	if shown == 0 then
		createText(host, 4, CHIP_PAD, math.max(1, hostW - 8),
			T("IGUI_GS_NodeRulesEmpty"), PALETTE.textMuted)
	end
end

--- Reconstruye el panel completo (tras añadir/quitar una regla) - preserva
--- el nombre/prioridad pendientes de "Aplicar cambios" (mismo motivo que
--- GS_TerminalUI_NodeEditor.lua:rebuildForm, esto puede dispararse mientras
--- el jugador tiene texto sin guardar en esos campos).
--- Guarda estado de edición, destruye y reconstruye el formulario - mismo
--- patron que GS_TerminalUI_NodeEditor.lua:rebuildForm.
function GS_ZoneEditorUI:rebuildForm()
	if not self.editorScroll then return end
	local pendingName = self.nameEntry and self.nameEntry:getText() or nil
	local pendingPriority = self.priorityEntry and self.priorityEntry:getText() or nil
	local savedOffset = UI.Scroll.getScrollOffset(self.editorScroll)
	self:resetForm()
	self:ensureForm()
	if pendingName and self.nameEntry then self.nameEntry:setText(pendingName) end
	if pendingPriority and self.priorityEntry then self.priorityEntry:setText(pendingPriority) end
	UI.Scroll.setScrollOffset(self.editorScroll, savedOffset)
end

--- Confirmación antes de excluir la zona (dev26, ronda 2 - solo al excluir,
--- nunca al volver a incluir).
function GS_ZoneEditorUI:confirmExcludeZone()
	if not self.zone then return end
	local message = T("IGUI_GS_ZoneExcludeConfirm", self.zone.name or "?")
	confirmAction(message, function()
		if self.zone then
			GlobalStorageSiK.NetClient.sendCommand("setZoneEnabled", { zoneId = self.zone.id, enabled = false })
		end
	end)
end

function GS_ZoneEditorUI:confirmDelete()
	local count = 0
	local nodes = self.terminal and self.terminal.terminalState and self.terminal.terminalState.nodes or {}
	for i = 1, #nodes do
		if self.zone and nodes[i].zoneId == self.zone.id then count = count + 1 end
	end
	confirmAction(T("IGUI_GS_ZoneDeleteConfirm", self.zone and self.zone.name or "?", count), function()
		if self.zone and self.terminal then
			self.terminal:onDeleteZone(self.zone.id)
			GlobalStorageSiK.TerminalZoneEditor.close()
		end
	end)
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

	-- Tamano/posicion compartidos con GS_TerminalUI_NodeEditor.lua (dev26
	-- ronda 4; el perfil editor SiK.UI conserva geometria por jugador.
	local bounds = UI.Window.resolveBounds({ profile = "editor" })
	local x, y, w, h = bounds.x, bounds.y, bounds.w, bounds.h

	local ui = GS_ZoneEditorUI:new(x, y, w, h)
	ui:initialise()
	ui:addToUIManager()
	ui:setZone(terminal, zone)
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
	if ui.close then ui:close("product")
	else
		ui:setVisible(false)
		ui:removeFromUIManager()
		GlobalStorageSiK.TerminalZoneEditor.instance = nil
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
			if ui.setHeader then
				ui:setHeader(T("IGUI_GS_ZoneEditorTitle") .. ": " .. (ui.zone.name or "?"))
			end
			-- Mismo bug/mismo fix que GS_TerminalUI_NodeEditor.lua:syncFormButtons
			-- - anadir/quitar una regla dispara rebuildForm() de inmediato
			-- (callback de GS_FilterEditor.lua) ANTES de que este sync traiga
			-- la regla nueva/quitada; sin este chequeo, la zona se quedaba
			-- con las tarjetas OR/AND/NOT dimensionadas para el conteo
			-- ANTIGUO y el chip nuevo no aparecia (o quedaba tapado) hasta el
			-- siguiente rebuild por otro motivo.
			if ui._ruleCountAtBuild ~= nil and #(ui.zone.rules or {}) ~= ui._ruleCountAtBuild then
				ui:rebuildForm()
			end
			return
		end
	end
end

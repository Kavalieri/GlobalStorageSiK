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
require "GS_TerminalUI_Nodes"
local Confirmation = require "GS_Confirmation"
local CapacityPresentation = require "GlobalStorageSiK/UI/CapacityPresentation"
local UI = require "GS_UI_Framework"
local ScrollDock = UI.ScrollDock

GlobalStorageSiK.TerminalZoneEditor = {}
GlobalStorageSiK.TerminalZoneEditor.instance = nil

GS_ZoneEditorUI = UI.Window.derive("GS_ZoneEditorUI")

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local CONTROL_METRICS = UI.Controls.metrics("editor")
local PAD = 10

-- Conserva los rectangulos aprobados del editor y deja a SiK.UI la
-- construccion, el chrome y el lifecycle de las hojas visibles.
local function createText(parent, x, y, w, text, color)
	local explicit = type(color) == "table"
	local tone = explicit and "editorText" or (color or "textMuted")
	local copy = UI.Controls.copyText(parent, {
		x = x, y = y, w = math.max(1, w), text = text,
		font = UIFont.Small, lineGap = 0, tone = tone,
		theme = explicit and { editorText = {
			r = color[1], g = color[2], b = color[3], a = color[4] or 1,
		} } or nil,
	})
	if copy.setMouseTransparent then copy:setMouseTransparent(true) end
	return copy
end

local function createHost(parent, x, y, w, h)
	return UI.Controls.panel(parent, {
		x = x, y = y, w = w, h = h, controlId = "editorHost",
	})
end

local function createField(parent, text, x, y, w, numeric, onSubmit)
	return UI.Controls.field(parent, {
		x = x, y = y, w = w, h = CONTROL_METRICS.inputHeight,
		text = text, numeric = numeric == true, onSubmit = onSubmit,
	})
end

local function addSummaryRuns(host, layout)
	for i = 1, #(layout and layout.runs or {}) do
		local run = layout.runs[i]
		local color = run.fallback and "textMuted" or run.color
		createText(host, run.x, (run.line - 1) * (FONT_HGT_SMALL + 2),
			math.max(1, host.width - run.x), run.text, color)
	end
end

local function confirmAction(owner, title, question, consequences, onAccept)
	return Confirmation.show({ owner = owner, title = title, question = question,
		consequences = consequences, onAccept = onAccept })
end

--- Color de acento por operador (mismo trio que GS_TerminalUI_NodeEditor.lua,
--- los puntos de composicion de la lista de contenedores y el borde del
--- modal "Anadir regla" - nunca inventado por separado).
local RULE_OP_TONE = { OR = "info", AND = "warning", NOT = "danger" }

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
	local bottom = 0
	for _, block in ipairs(self._formBlocks or {}) do
		block:reflow({ x = 0, y = bottom, w = innerW, h = block.h })
		bottom = block.y + block.h + 8
	end
	self._actionsStartY = bottom
	if self.actionsBlock and self.editorDock then
		local rect = self.editorDock:getFixedBottomRect()
		self.actionsBlock:reflow({ x = 0, y = 0, w = rect.w, h = self.actionsBlock.h })
	end
	self:updateScrollHeight(bottom)
end

function GS_ZoneEditorUI:calculateLayout()
	local content = self.contentHost and { x = 0, y = 0,
		w = self.contentHost.width, h = self.contentHost.height }
		or { x = 0, y = 0, w = self.width, h = self.height }
	if self.editorDock then
		self.editorDock:reflow(content)
		self:layoutForm()
		self:updateScrollHeight()
	end
end

function GS_ZoneEditorUI:initialise()
	UI.Window.callBase(self, "initialise")
	UI.Modal.apply(self, {
		kind = "task", profile = "editor", scroll = false, contentMode = "dock",
		geometryKey = "zoneEditor", resizable = true,
		geometryVersion = 2,
		title = T("IGUI_GS_ZoneEditorTitle"),
		onReflow = function() self:calculateLayout() end,
		onClose = function()
			self._pendingRuleSync = nil
			if self.editorDock then self.editorDock:dispose(); self.editorDock = nil end
			GlobalStorageSiK.TerminalZoneEditor.instance = nil
			if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.clear then
				GlobalStorageSiK.NodeHighlight.clear()
			end
		end,
	})
	self.clipChildren = true
	self:setVisible(true)
	self:createChildren()
	self:calculateLayout()
end

function GS_ZoneEditorUI:createChildren()
	if self._gsChildrenBuilt then return end
	self._gsChildrenBuilt = true
	-- El chrome y el Block fisico se construyen una sola vez por Modal.apply().
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
			self:setHeader({ titleParts = { prefix = T("IGUI_GS_ZoneEditorTitle"), name = name,
				separator = " " .. T("IGUI_GS_PunctuationMiddleDot") .. " " } })
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
	local parent, width = UI.Scroll.childHost(scroll), UI.Scroll.contentWidth(scroll)
	local bottom = 0
	self._formBlocks = {}
	local function section(title, tooltip)
		return UI.Block.create({ parent = parent, x = 0, y = bottom, w = width,
			title = title, tooltip = tooltip or title, playerNum = self.playerNum })
	end
	local function finish(block, column)
		column:finish()
		self._formBlocks[#self._formBlocks + 1] = block
		bottom = block.y + block.h + 8
	end
	local function label(column, text, color)
		local widget = createText(column.parent, 0, 0, column.width, text, color or "text")
		column:label(widget, function(w) widget:reflow(w); return widget.height end)
		return widget
	end
	local function field(column, title, value, numeric, onSubmit)
		label(column, title)
		local widget = createField(column.parent, value, 0, 0, column.width, numeric, onSubmit)
		column:block(widget, CONTROL_METRICS.inputHeight)
		return widget
	end
	local function button(column, title, callback, danger, tooltip)
		return UI.Controls.button(column.parent, { text = title, onClick = callback,
			danger = danger == true, tooltip = tooltip, playerNum = self.playerNum })
	end

	-- Identity owns its capacity presentation and editable zone fields.
	local count = zoneContainerCount(zone, terminal)
	local identity = section(T("IGUI_GS_ZoneIdentity"))
	self.identityBlock = identity
	local identityColumn = identity:beginColumn({ retain = true })
	local presentation = CapacityPresentation.fromState(self.capacityInfo, { count = count, kind = "containers" })
	self.capacityBar = UI.Controls.progress(identityColumn.parent, {
		w = identityColumn.width, h = CONTROL_METRICS.rowHeight,
	})
	self.capacityBar:setProgress(presentation)
	identityColumn:block(self.capacityBar, CONTROL_METRICS.rowHeight)
	self.nameEntry = field(identityColumn, T("IGUI_GS_ZoneRenameLabel"), zone.name or "", false, function()
		local name = self.nameEntry:getText()
		if self.zone and name ~= "" and self.terminal and self.terminal.onRenameZone then
			self.terminal:onRenameZone(self.zone.id, name)
		end
	end)
	self.priorityEntry = field(identityColumn, T("IGUI_GS_ZonePriorityLabel"), tostring(zone.priority or 50), true, function()
		local value = tonumber(self.priorityEntry:getText())
		if value then self:applyPriority(value) end
	end)
	UI.Controls.setTooltip(self.priorityEntry, T("IGUI_GS_ZonePriorityHint"), { kind = "descriptive" })
	self.priorityPresetHighBtn = button(identityColumn, T("IGUI_GS_NodePriorityPresetHigh"), function() self:applyPriority(10) end)
	self.priorityPresetNormalBtn = button(identityColumn, T("IGUI_GS_NodePriorityPresetNormal"), function() self:applyPriority(50) end)
	self.priorityPresetLowBtn = button(identityColumn, T("IGUI_GS_NodePriorityPresetLow"), function() self:applyPriority(90) end)
	identityColumn:row(CONTROL_METRICS.buttonHeight, {
		{ widget = self.priorityPresetHighBtn }, { widget = self.priorityPresetNormalBtn },
		{ widget = self.priorityPresetLowBtn },
	})
	finish(identity, identityColumn)

	-- Rules is a parent Block. Protocol and operator groups are real child Blocks.
	local rulesBlock = section(T("IGUI_GS_EditorRules"), T("IGUI_GS_EditorRulesHint"))
	self.rulesBlock = rulesBlock
	local rulesColumn = rulesBlock:beginColumn({ retain = true })
	local protocol = UI.Block.create({ parent = rulesColumn.parent, w = rulesColumn.width,
		title = T("IGUI_GS_ZoneRulesTitle"), tooltip = T("IGUI_GS_ZoneRulesHint"), playerNum = self.playerNum })
	local protocolColumn = protocol:beginColumn({ retain = true })
	local summary = GlobalStorageSiK.RulesUI.layoutSummary(zone.rules or {}, protocolColumn.width,
		UIFont.Small, UI.Theme.palette(self._sikThemeContext).textSecondary)
	self.rulesSummaryHost = createHost(protocolColumn.parent, 0, 0, protocolColumn.width,
		math.max(FONT_HGT_SMALL, summary.lineCount * (FONT_HGT_SMALL + 2)))
	protocolColumn:block(self.rulesSummaryHost, function(w)
		return GlobalStorageSiK.RulesUI.refreshSummary(self.rulesSummaryHost,
			self.zone.rules or {}, w, UIFont.Small, UI.Theme.palette(self._sikThemeContext).textSecondary)
	end)
	rulesColumn:block(protocol, protocolColumn:finish())
	for _, op in ipairs(GlobalStorageSiK.RulesUI.OPS) do
		local group = self:buildRuleSection(rulesBlock, op)
		rulesColumn:block(group, group.h)
	end
	finish(rulesBlock, rulesColumn)
	-- Firma del numero de reglas usada para dimensionar tarjetas/hosts en
	-- ESTE build (ver GlobalStorageSiK.TerminalZoneEditor.syncZoneData) -
	-- mismo bug/mismo fix que GS_TerminalUI_NodeEditor.lua: anadir una regla
	-- dispara rebuildForm() de inmediato via el callback de
	-- GS_FilterEditor.lua ANTES de que zone.rules tenga la regla nueva.
        self._ruleCountAtBuild = #(self.zone and self.zone.rules or {})
	self._rulesLayoutAtBuild = GlobalStorageSiK.RulesUI.layoutSignature(zone.rules)
	self._rulesIdentityAtBuild = GlobalStorageSiK.RulesUI.stateSignature(zone.rules)

	-- Flat table: it is an action surface, not a disclosure hierarchy.
	local containers = section(T("IGUI_GS_NativeTax_containers"), T("IGUI_GS_ZonesPriorityHint"))
	self.containersBlock = containers
	local containersColumn = containers:beginColumn({ retain = true })
	local zoneRows = GlobalStorageSiK.TerminalNodes.zoneRows(
		terminal.terminalState and terminal.terminalState.nodes or {}, zone)
	local tableH = UI.Table.intrinsicHeight and UI.Table.intrinsicHeight(#zoneRows, { minRows = 1 })
		or math.max(56, (#zoneRows + 1) * CONTROL_METRICS.buttonHeight)
	local zoneNodesTable, tableReason = UI.Table.create({
		parent = containersColumn.parent, x = 0, y = 0, embedded = true,
		directBlock = false,
		w = containersColumn.width, h = tableH, columns = GlobalStorageSiK.TerminalNodes.columns(),
		rows = zoneRows, allRowsVisible = true, selectionMode = "single",
		keyOf = function(row) return row.id end,
		onRowClick = function(payload)
			local row = payload and payload.item
			if row and row.sourceNode then
				GlobalStorageSiK.TerminalNodeEditor.open(terminal, row.sourceNode, {}, self)
			end
		end,
	})
	if not zoneNodesTable then
		error("SiK.UI.Table.create(zone.containers): " .. tostring(tableReason))
	end
	self.zoneNodesTable = zoneNodesTable
	containersColumn:block(self.zoneNodesTable, self.zoneNodesTable:getHeight())
	finish(containers, containersColumn)

	self._formBuilt = true
	self._actionsStartY = bottom
	self:mountFixedActions()
	self:updateScrollHeight(containers.y + containers.h)
end

-- Refresh the flat inventory of nodes without replacing edited field values.
function GS_ZoneEditorUI:refreshZoneNodes()
	if not self.zoneNodesTable or not self.containersBlock or not self.zone then return end
	local nodes = self.terminal and self.terminal.terminalState and self.terminal.terminalState.nodes or {}
	self.zoneNodesTable:setRows(GlobalStorageSiK.TerminalNodes.zoneRows(nodes, self.zone), true)
	local column = self.containersBlock:beginColumn({ retain = true })
	column:block(self.zoneNodesTable, self.zoneNodesTable:getHeight())
	column:finish()
	self:updateScrollHeight(self.containersBlock.y + self.containersBlock.h)
end

function GS_ZoneEditorUI:mountFixedActions()
        if not self.editorDock or not self.editorDock.fixedBottomHost then return end
        if self.actionsBlock then self.actionsBlock:dispose() end
        local rect = self.editorDock:getFixedBottomRect()
        local block = UI.Block.create({ parent = self.editorDock.fixedBottomHost,
                w = rect.w, title = T("IGUI_GS_PermColActions"),
                tooltip = T("IGUI_GS_ZonesManageHint"), playerNum = self.playerNum })
        self.actionsBlock = block
	local column = block:beginColumn({ retain = true })
        local function action(title, callback, danger, tooltip)
                return UI.Controls.button(column.parent, { text = title, onClick = callback,
                        danger = danger == true, tooltip = tooltip, playerNum = self.playerNum })
        end
        local role = self.terminal and self.terminal.terminalState
                and self.terminal.terminalState.permissions and self.terminal.terminalState.permissions.myRole
        if role == "owner" or role == "admin" then
                self.rescanZoneBtn = action(T("IGUI_GS_ZoneCtxRescan"), function()
                        if self.zone and self.terminal and self.terminal.onRescanZone then
                                self.terminal:onRescanZone(self.zone.id)
                        end
                end, false, T("IGUI_GS_ZonesManageHint"))
        end
        local excluded = self.zone and self.zone.enabled == false
        self.zoneMembBtn = action(T(excluded and "IGUI_GS_ZoneBtnInclude" or "IGUI_GS_ZoneBtnExclude"), function()
                if self.zone and self.zone.enabled == false then
                        GlobalStorageSiK.NetClient.sendCommand("setZoneEnabled", { zoneId = self.zone.id, enabled = true })
                else self:confirmExcludeZone() end
        end, not excluded, T("IGUI_GS_ZoneExcludeTooltip"))
        if self.rescanZoneBtn then
                column:row(CONTROL_METRICS.buttonHeight, {
                        { widget = self.rescanZoneBtn }, { widget = self.zoneMembBtn },
                })
        else
                column:block(self.zoneMembBtn, CONTROL_METRICS.buttonHeight)
        end
        self.deleteBtn = action(T("IGUI_GS_DeleteZone"), function() self:confirmDelete() end, true)
        self.applyAllBtn = action(T("IGUI_GS_ApplyAllChanges"), function() self:applyAll() end,
                false, T("IGUI_GS_ApplyAllChangesTooltip"))
        column:row(CONTROL_METRICS.buttonHeight, {
                { widget = self.deleteBtn }, { widget = self.applyAllBtn },
        })
        self.editorDock:setFixedBottomHeight(column:finish())
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
		self:setHeader({ titleParts = { prefix = T("IGUI_GS_ZoneEditorTitle"), name = zone.name or "?",
			separator = " " .. T("IGUI_GS_PunctuationMiddleDot") .. " " } })
	end
	if not sameZone then
		self:resetForm()
		self.capacityInfo = nil
		GlobalStorageSiK.NetClient.sendCommand("getZoneCapacity", { zoneId = zone.id })
	end
	if not self.editorDock then
		self.editorDock = ScrollDock.create({
			parent = self.contentHost or self, x = 0, y = 0, w = 400, h = 200,
			padding = 0, gap = 8, contentHeight = 0,
		})
		self.editorScroll = self.editorDock and self.editorDock.scroll
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
--- caso "zoneCapacity") - actualiza SOLO la barra ya creada,
--- sin reconstruir el formulario (evitaria perder texto pendiente de
--- "Aplicar cambios").
---@param capacity table|nil
function GS_ZoneEditorUI:onCapacityReceived(capacity)
        self.capacityInfo = capacity
        if self.capacityBar then
                local presentation = CapacityPresentation.fromState(capacity, {
                        count = zoneContainerCount(self.zone, self.terminal), kind = "containers",
                })
                self.capacityBar:setProgress(presentation)
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
	if self.editorDock then
		self.editorDock:setContentHeight(bottom)
	else
		UI.Scroll.setContentHeight(self.editorScroll, bottom)
	end
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
	self.capacityBar = nil
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
	self._rulesLayoutAtBuild = nil
	self.identityBlock = nil
	self.rulesBlock = nil
	self.containersBlock = nil
	self.zoneNodesTable = nil
end

--- Construye una sección de reglas de zona (OR/AND/NOT): título, panel de
--- chips y botón "+ Añadir regla <op>" - mismo patrón visual y mismo host de
--- scroll que GS_TerminalUI_NodeEditor.lua (dev26 ronda 4).
---@param scroll table
---@param pad number
---@param contentW number
---@param y number
---@param op string "OR"|"AND"|"NOT"
---@return number newY
function GS_ZoneEditorUI:buildRuleSection(parentBlock, op)
	local rules = (self.zone and self.zone.rules) or {}
	local count = 0
	for i = 1, #rules do
		if rules[i].op == op then count = count + 1 end
	end
	local chipH, chipGap = UI.Controls.dismissibleRowHeight({ profile = "editor" }), 8
	local chipsH = math.max(FONT_HGT_SMALL, count * (chipH + chipGap) - chipGap)
	local card = UI.Block.create({ parent = parentBlock.childParent,
		w = parentBlock:getContentRect().w, title = T(GlobalStorageSiK.RulesUI.OP_TITLE_KEY[op]),
		tooltip = T("IGUI_GS_ZoneRulesHint"), playerNum = self.playerNum,
		accentTone = RULE_OP_TONE[op] })
	local column = card:beginColumn({ retain = true })
	local host = createHost(column.parent, 0, 0, column.width, chipsH)
	function host:reflow(w)
		for _, child in ipairs(self.childrenInOrder or {}) do
			if child.reflow then child:reflow(math.max(1, w - (child.x or 0) * 2)) end
		end
	end
	column:block(host, function() return host.height end)
	self._ruleCards = self._ruleCards or {}
	self._ruleCards[op] = card
	self._ruleChipsHosts = self._ruleChipsHosts or {}
	self._ruleChipsHosts[op] = host
	self:rebuildRuleChips(op)

	local addBtn = UI.Controls.button(column.parent, { text = T(GlobalStorageSiK.RulesUI.OP_ADD_KEY[op]),
		playerNum = self.playerNum, onClick = function()
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
			GlobalStorageSiK.RulesUI.refreshEditorRules(self, self.zone.rules)
		end, self)
	end })
	column:block(addBtn, CONTROL_METRICS.buttonHeight)
	column:finish()
	return card
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
		if ch.dispose then ch:dispose()
		else
			host:removeChild(ch)
			if ch.removeFromUIManager then ch:removeFromUIManager() end
		end
	end

	local allRules = (self.zone and self.zone.rules) or {}
	local CHIP_H, CHIP_PAD = UI.Controls.dismissibleRowHeight({ profile = "editor" }), 8
	local cy = 0
	local hostW = host.width
	local removeText = T("IGUI_GS_Remove")

	local shown = 0
	for realIdx = 1, #allRules do
		local rule = allRules[realIdx]
		if rule.op == op then
			shown = shown + 1
			local label = GlobalStorageSiK.RulesUI.describeCondition(rule.condition)
			local labelColor = GlobalStorageSiK.RulesUI.conditionColor(
				rule.condition, false)

			local capturedIdx = realIdx
			local capturedRule = GlobalStorageSiK.RuleIdentity.signature(rule)
			UI.Controls.dismissibleRow(host, {
				x = 0, y = cy, w = hostW, h = CHIP_H, profile = "editor",
				text = label, tooltip = label, actionTooltip = removeText, playerNum = self.playerNum,
				tone = labelColor and "ruleText" or "text",
				theme = labelColor and { ruleText = { r = labelColor[1],
					g = labelColor[2], b = labelColor[3], a = labelColor[4] or 1 } } or nil,
				onRemove = function()
					if not self.zone or not capturedRule then return end
					GlobalStorageSiK.NetClient.sendCommand("updateZoneRules", { zoneId = self.zone.id,
						removeRuleIndex = capturedIdx, expectedRule = capturedRule })
				end })
			cy = cy + CHIP_H + CHIP_PAD
		end
	end
	if shown == 0 then
		createText(host, 4, CHIP_PAD, math.max(1, hostW - 8),
			T("IGUI_GS_NodeRulesEmpty"), "textMuted")
	end
	host:setHeight(math.max(FONT_HGT_SMALL, cy - CHIP_PAD))
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
	confirmAction(self, T("IGUI_GS_ZoneEditorTitle"),
		T("IGUI_GS_ZoneExcludeQuestion", self.zone.name or "?"),
		T("IGUI_GS_ZoneExcludeConsequences"), function()
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
	confirmAction(self, T("IGUI_GS_ZoneEditorTitle"),
		T("IGUI_GS_ZoneDeleteQuestion", self.zone and self.zone.name or "?"),
		T("IGUI_GS_ZoneDeleteConsequences", count), function()
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
function GlobalStorageSiK.TerminalZoneEditor.open(terminal, zone, allNodes, owner)
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
	local modalOwner = owner or terminal
	local playerNum = modalOwner and modalOwner.playerNum or 0
	local bounds = UI.Window.resolveBounds({ profile = "editor", playerNum = playerNum })
	local x, y, w, h = bounds.x, bounds.y, bounds.w, bounds.h

	local ui = GS_ZoneEditorUI:new(x, y, w, h)
	ui.playerNum, ui._sikModalOwner = playerNum, modalOwner
	ui:initialise()
	UI.Modal.presentChild(owner or terminal, ui)
	GlobalStorageSiK.TerminalZoneEditor.instance = ui
	ui:setZone(terminal, zone)

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
			local updated = zones[i]
			GlobalStorageSiK.RulesUI.applyWhenIdle(ui, function()
			ui.zone = updated
			local state = ui.terminal and ui.terminal.terminalState
			local capacity = state and state.capacity and state.capacity.perZone
				and state.capacity.perZone[ui.zone.id]
			if capacity then ui:onCapacityReceived(capacity) end
			if ui.setHeader then
				ui:setHeader({ titleParts = { prefix = T("IGUI_GS_ZoneEditorTitle"), name = ui.zone.name or "?",
					separator = " " .. T("IGUI_GS_PunctuationMiddleDot") .. " " } })
			end
			GlobalStorageSiK.RulesUI.refreshEditorRules(ui, ui.zone.rules)
			ui:refreshZoneNodes()
			end)
			return
		end
	end
end

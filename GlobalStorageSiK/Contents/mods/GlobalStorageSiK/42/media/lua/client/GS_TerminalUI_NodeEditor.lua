--[[
	GlobalStorageSiK - Editor modal de contenedor
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Ventana separada para editar un contenedor de red.
	Formulario fijo (no se reconstruye al recibir contenidos); solo se refresca el bloque de ítems.
]]

require "GS_I18n"
require "GS_NativeProduct"
require "GS_TerminalUI_Config"
require "GS_NetClient"
require "GS_NodeHighlight"
require "GS_NodeFilters"
require "GS_RulesUI"
require "GS_FilterEditor"
require "GS_TerminalUI_ZoneEditor"
require "GS_CompatMods"
local ContainerInventory = require "GS_ContainerInventory"
local Confirmation = require "GS_Confirmation"
local UI = require "GS_UI_Framework"
local ScrollDock = UI.ScrollDock

GlobalStorageSiK.TerminalNodeEditor = {}
GlobalStorageSiK.TerminalNodeEditor.instance = nil
-- Plantilla puramente temporal de esta sesion de cliente. No contiene
-- identidad fisica ni permisos: solo las reglas de destino que tiene sentido
-- repetir en muchos contenedores de una red grande.
GlobalStorageSiK.TerminalNodeEditor.configTemplate = nil

GS_NodeEditorUI = UI.Window.derive("GS_NodeEditorUI")

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local CONTROL_METRICS = UI.Controls.metrics("editor")
local PALETTE = UI.Theme.palette()
local PAD = 10
local INFO_BTN_SIZE = 24

--- Coloca un boton "?" con el control de ayuda de SiK.UI.
--- justo despues de un titulo de bloque ya creado, con el texto largo que
--- antes vivia siempre visible debajo como parrafo - dev26 ronda 4.
---@param scroll table
---@param pad number
---@param y number
---@param titleText string
---@param tooltip string
---@param target any
local function createInfoSectionTitle(scroll, pad, y, width, titleText, tooltip, target)
	local title = UI.Controls.sectionTitle(nil, {
		x = pad, y = y, w = width, h = INFO_BTN_SIZE,
		text = titleText, info = { tooltip = tooltip, payload = target },
	})
	UI.Scroll.addChild(scroll, title)
	return title
end
local CONTENTS_TAG = "_gsNodeEditorContents"

---@param x number
---@param y number
---@param w number
---@param title string
---@param target any
---@param onClick function
---@return ISButton
-- fullWidth=true (ver SiK.UI.Controls.button): todos los
-- botones de este editor ocupan SIEMPRE el ancho de columna/fila que se les
-- pasa en vez de encogerse a su etiqueta - pedido explicito del usuario
-- comparando con el mockup ("de ancho dinamico... la diferencia es clara").
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
	local block = UI.Block.create({ parent = UI.Scroll.childHost(scroll),
		x = x, y = y, w = w, h = h, paddingX = 8, paddingY = 8,
		background = { r = 0.08, g = 0.08, b = 0.08, a = 0.72 },
		border = { r = 0.28, g = 0.28, b = 0.28, a = 0.70 },
	})
	return block and block.panel or nil
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

local function confirmAction(message, onAccept, consequences)
	return Confirmation.show({ question = message, consequences = consequences, onAccept = onAccept })
end

-- Estos helpers conservan la geometria historica del editor, pero delegan
-- construccion, chrome y lifecycle de cada hoja visible en SiK.UI.
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

local function createField(text, x, y, w, numeric, onSubmit)
	return UI.Controls.field(nil, {
		x = x, y = y, w = w, h = CONTROL_METRICS.inputHeight,
		text = text, numeric = numeric == true, onSubmit = onSubmit,
	})
end

function GS_NodeEditorUI:new(x, y, w, h)
	local o = UI.Window.newInstance(self, x, y, w, h)
	o.moveWithMouse = false
	o.drawBackground = false
	o.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	o.borderColor = { r = 0, g = 0, b = 0, a = 1 }
	o.padding = PAD
	o.headerHeight = math.floor(FONT_HGT_MEDIUM * 1.4)
	o._formBuilt = false
	o._contentsStartY = 0
	return o
end

function GS_NodeEditorUI:initialise()
	UI.Window.callBase(self, "initialise")
	UI.Modal.apply(self, {
		kind = "task", profile = "editor", scroll = false, contentMode = "dock",
		geometryKey = "nodeEditor",
		geometryVersion = 2,
		title = T("IGUI_GS_NodeEditorTitle"),
		onReflow = function() self:calculateLayout() end,
		onClose = function()
			if self.contentsView then self.contentsView:dispose(); self.contentsView = nil end
			if self.editorDock then self.editorDock:dispose(); self.editorDock = nil end
			GlobalStorageSiK.TerminalNodeEditor.instance = nil
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

function GS_NodeEditorUI:createChildren()
	-- PZ llama createChildren desde instantiate() y nuestro initialise() también:
    -- guard para construir una sola vez (evita elementos huérfanos duplicados).
	if self._gsChildrenBuilt then return end
	self._gsChildrenBuilt = true
	-- SiK.UI.Modal.apply() posee el chrome y el Block fisico compartidos.
end

--- Actualiza título de ventana con el nombre del nodo en red.
function GS_NodeEditorUI:syncTitleFromName()
	local name = self.node and (self.node.displayName or self.node.name) or "?"
	local zoneName = ""
	for _, zone in ipairs(self.terminal and self.terminal.terminalState and self.terminal.terminalState.zones or {}) do
		if self.node and zone.id == self.node.zoneId then zoneName = zone.name or ""; break end
	end
	local separator = " " .. T("IGUI_GS_PunctuationMiddleDot") .. " "
	self._titleText = T("IGUI_GS_NodeEditorTitle") .. separator .. name
		.. (zoneName ~= "" and (separator .. zoneName) or "")
	if self.setHeader then self:setHeader({ titleParts = {
		prefix = T("IGUI_GS_NodeEditorTitle"), name = name, zone = zoneName,
		separator = separator } }) end
end

--- Envía cambios de nodo al servidor.
---@param nodeId string
---@param opts table  { displayName, categories, filters, enabled, membership, priority, notes }
--- Manda SOLO los campos presentes en opts (todos opcionales). Cada campo del
--- formulario tiene su propio boton "Aplicar" que llama esto con un unico
--- campo; nunca se resetean sin querer los demas (antes `categories` se
--- mandaba siempre, incluso vacio, si no se incluia explicitamente).
function GlobalStorageSiK.TerminalNodeEditor.sendNodeUpdate(nodeId, opts)
	local searchQuery = ""
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if ui and ui.getSearchQuery then
		searchQuery = ui:getSearchQuery()
	end
	local payload = { nodeId = nodeId, searchQuery = searchQuery }
	if opts.displayName ~= nil then payload.displayName = opts.displayName end
	if opts.categories  ~= nil then payload.categories  = opts.categories  end
	if opts.filters     ~= nil then payload.filters     = opts.filters     end
	if opts.rules       ~= nil then payload.rules       = opts.rules       end
	if opts.enabled     ~= nil then payload.enabled     = opts.enabled     end
	if opts.membership  ~= nil then payload.membership  = opts.membership end
	if opts.priority    ~= nil then payload.priority    = opts.priority   end
	if opts.notes       ~= nil then payload.notes       = opts.notes      end
	GlobalStorageSiK.NetClient.sendCommand("updateNode", payload)
end

--- Captura la configuracion visible del editor. El nombre, la etiqueta, la
--- zona, el estado y la identidad del contenedor quedan fuera a proposito.
function GS_NodeEditorUI:copyConfigTemplate()
	if not self.node then return end
	local priority = tonumber(self.priorityEntry and self.priorityEntry:getText() or "")
		or tonumber(self._editPriority) or self.node.priority or 50
	priority = math.floor(priority + 0.5)
	if priority < 1 then priority = 1 elseif priority > 100 then priority = 100 end
	GlobalStorageSiK.TerminalNodeEditor.configTemplate = {
		sourceNodeId = self.node.id,
		sourceName = self.node.displayName or self.node.name or "?",
		rules = cloneRules(self.node.rules),
		priority = priority,
	}
	self:rebuildForm()
end

--- Sustituye de una vez el protocolo de aceptacion del nodo abierto. Se
--- envia un unico update acotado; el servidor vuelve a validar reglas y
--- prioridad y conserva intacta toda la metadata fisica/administrativa.
function GS_NodeEditorUI:pasteConfigTemplate()
	if not self.node then return end
	local template = GlobalStorageSiK.TerminalNodeEditor.configTemplate
	if not template then return end
	local rules = cloneRules(template.rules)
	local priority = tonumber(template.priority) or 50
	self._editPriority = priority
	if self.priorityEntry then self.priorityEntry:setText(tostring(priority)) end
	self.node.rules = cloneRules(rules)
	self.node.priority = priority
	self:requestNodeUpdate({
		rules = rules,
		priority = priority,
	})
	self:rebuildForm()
end

--- Cuenta contenedores de una zona (excluido el propio origen).
---@param nodes table
---@param zoneId string
---@param excludeNodeId string
---@return number
local function countOtherZoneNodes(nodes, zoneId, excludeNodeId)
	local count = 0
	for i = 1, #(nodes or {}) do
		if nodes[i].zoneId == zoneId and nodes[i].id ~= excludeNodeId then
			count = count + 1
		end
	end
	return count
end

--- Busca una zona por id dentro del estado ya sincronizado del terminal.
---@param terminal table
---@param zoneId string
---@return table|nil
local function findZoneById(terminal, zoneId)
	local zones = terminal and terminal.terminalState and terminal.terminalState.zones or {}
	for i = 1, #zones do
		if zones[i].id == zoneId then return zones[i] end
	end
	return nil
end

--- "Extender a la zona" (dev26, ronda 2 - ver
--- Documentacion/GS_FilterRedesign_Plan.md §4.4-quater): aplica el
--- protocolo de aceptacion de ESTE contenedor a todos los demas de su misma
--- zona, previa confirmacion (reemplaza sus reglas, nunca su prioridad,
--- nombre, etiqueta ni identidad). Sustituye a la antigua seccion
--- "Plantilla" del editor de zona.
function GS_NodeEditorUI:confirmExtendToZone()
	if not self.node or not self.node.zoneId then return end
	local nodes = self.terminal and self.terminal.terminalState and self.terminal.terminalState.nodes or {}
	local count = countOtherZoneNodes(nodes, self.node.zoneId, self.node.id)
	if count == 0 then return end
	local message = T("IGUI_GS_NodeExtendToZoneQuestion", count, self.node.zoneName or "?")
	confirmAction(message, function()
		GlobalStorageSiK.NetClient.sendCommand("applyNodeTemplateToZone", {
			zoneId = self.node.zoneId,
			rules = self.node.rules or {},
		})
	end, T("IGUI_GS_NodeExtendToZoneConsequences", count, self.node.zoneName or "?"))
end

--- Confirmacion antes de excluir (dev26, ronda 2 - ver §4.5 del plan): solo
--- al excluir, nunca al volver a incluir - excluir saca el contenedor por
--- completo de deposito/extraccion hasta que el jugador lo revierta a mano.
function GS_NodeEditorUI:confirmExclude()
	if not self.node then return end
	local message = T("IGUI_GS_NodeExcludeQuestion", self.node.displayName or self.node.name or "?")
	confirmAction(message, function()
		self:requestNodeUpdate({ enabled = false, membership = "excluded" })
	end, T("IGUI_GS_NodeExcludeConsequences"))
end

--- Aplica y persiste inmediatamente un unico campo del formulario.
---@param field string "displayName"|"categories"|"priority"|"notes"
---@param value any
function GS_NodeEditorUI:applyField(field, value)
	if not self.node then return end
	GlobalStorageSiK.TerminalNodeEditor.sendNodeUpdate(self.node.id, { [field] = value })
end

function GS_NodeEditorUI:requestNodeUpdate(opts)
	if not self.node or not opts then return end
	GlobalStorageSiK.TerminalNodeEditor.sendNodeUpdate(self.node.id, opts)
end

function GS_NodeEditorUI:requestNodeContents(nodeId)
	if self.terminal and self.terminal.onRequestNodeContents then
		self.terminal:onRequestNodeContents(nodeId)
	else
		GlobalStorageSiK.NetClient.sendCommand("getNodeContents", { nodeId = nodeId })
	end
end

--- Ajusta el formulario al ancho actual. Con parejas campo+Aplicar y combos a
--- medias/tercios, replicar el calculo de anchos aqui duplicaria ensureForm();
--- mas simple y correcto reconstruir completo (rebuildForm ya preserva
--- nombre/notas/prioridad/categorias pendientes y el offset del scroll).
--- Guardia por ancho: durante un arrastre de redimensionado, calculateLayout
--- se llama en cada frame; sin esto reconstruiria todo el formulario cada
--- frame aunque solo cambiase el alto.
function GS_NodeEditorUI:layoutForm()
	if self._buildingForm or not self._formBuilt or not self.editorScroll then
		return
	end
	local innerW = UI.Scroll.contentWidth(self.editorScroll)
	if self._lastLayoutW == innerW then
		return
	end
	self._lastLayoutW = innerW
	self:rebuildForm()
end

function GS_NodeEditorUI:calculateLayout()
	local content = self.contentHost and { x = 0, y = 0,
			w = self.contentHost.width, h = self.contentHost.height }
			or { x = 0, y = 0, w = self.width, h = self.height }
	if self.editorDock then
		self.editorDock:reflow(content)
		self:layoutForm()
		self:updateScrollHeight()
	end
end

-- Piezas de presentacion/edicion de reglas {op, condition} (etiquetas,
-- resumen en prosa, clonado, migracion legacy) viven en GS_RulesUI.lua
-- (dev26, ronda 2) - compartidas con GS_TerminalUI_ZoneEditor.lua, que
-- necesita exactamente la misma logica para sus propias reglas de zona.
local categoryDisplayLabel = GlobalStorageSiK.RulesUI.categoryLabel
local describeCondition    = GlobalStorageSiK.RulesUI.describeCondition
local cloneRules           = GlobalStorageSiK.RulesUI.cloneRules
local migrateLegacyToRules = GlobalStorageSiK.RulesUI.migrateLegacyToRules
local RULE_OP_TITLE_KEY    = GlobalStorageSiK.RulesUI.OP_TITLE_KEY
local RULE_OP_ADD_KEY      = GlobalStorageSiK.RulesUI.OP_ADD_KEY
local RULE_OPS             = GlobalStorageSiK.RulesUI.OPS

local function addSummaryRuns(host, layout, offsetY)
	offsetY = offsetY or 0
	for i = 1, #(layout and layout.runs or {}) do
		local run = layout.runs[i]
		local color = run.color
		createText(host, run.x,
			offsetY + (run.line - 1) * (FONT_HGT_SMALL + 2),
			math.max(1, host.width - run.x), run.text, color)
	end
end

function GS_NodeEditorUI:confirmRemoveFromNetwork()
	if not self.node or not self.terminal then return end
	local nodeName = self.node.displayName or self.node.name or "?"
	confirmAction(T("IGUI_GS_NodeRemoveQuestion", nodeName), function()
		if self.node and self.terminal then
			self.terminal:onRemoveNode(self.node.id)
			GlobalStorageSiK.TerminalNodeEditor.close()
		end
	end, T("IGUI_GS_NodeRemoveConsequences"))
end

function GS_NodeEditorUI:requestRebindProposal(targetNodeId)
	if not self.node or not self.terminal then return end
	self.terminal:onRequestRebindProposal(self.node.id, targetNodeId)
end

function GS_NodeEditorUI:requestConfigTransferProposal(targetNodeId)
	if not self.node or not self.terminal then return end
	self.terminal:onRequestConfigTransferProposal(self.node.id, targetNodeId)
end

function GS_NodeEditorUI:confirmConfigTransferProposal(proposal)
	if not proposal or not proposal.token or not self.node or not self.terminal
		or proposal.sourceId ~= self.node.id then return end
	local sourceName = self.node.displayName or self.node.name or "?"
	local targetName = proposal.targetName or "?"
	confirmAction(T("IGUI_GS_NodeTransferConfigQuestion", sourceName, targetName), function()
		self.terminal:onTransferNodeConfiguration(self.node.id, proposal.token)
	end, T("IGUI_GS_NodeTransferConfigConsequences", sourceName, targetName))
end

-- La lista nunca se infiere en cliente: llega ya filtrada por el servidor y
-- solo sirve para que el jugador elija cuando hay más de un destino válido.
function GS_NodeEditorUI:showRebindCandidates(response)
	if not response or response.sourceId ~= (self.node and self.node.id) then return end
	self._rebindCandidates = response.candidates or {}
	local ids = {}
	for i = 1, #self._rebindCandidates do
		ids[#ids + 1] = self._rebindCandidates[i].nodeId
	end
	local nodes = self.terminal and self.terminal.terminalState and self.terminal.terminalState.nodes or {}
	if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.highlightNodes then
		GlobalStorageSiK.NodeHighlight.highlightNodes(ids, nodes)
	end
	self:resetForm()
	self:ensureForm()
end

function GS_NodeEditorUI:confirmRebindProposal(proposal)
	if not proposal or not proposal.rebindToken or not self.node or not self.terminal
		or proposal.sourceId ~= self.node.id then return end
	local sourceName = self.node.displayName or self.node.name or "?"
	local targetName = proposal.targetName or "?"
	self._rebindCandidates = nil
	confirmAction(T("IGUI_GS_NodeRebindQuestion", sourceName, targetName), function()
		self.terminal:onRebindNode(self.node.id, proposal.rebindToken)
	end, T("IGUI_GS_NodeRebindConsequences", sourceName, targetName))
end

--- Color de acento (createSectionCard/createButton) por operador -
--- mismo trio en las 3 tarjetas de reglas, los puntos de composicion de la
--- lista de contenedores (GS_TerminalUI_Nodes.lua) y el borde del modal
--- "Anadir regla" (GS_FilterEditor.lua). Nunca inventado por separado.
local RULE_OP_COLOR = {
	OR  = PALETTE.ruleOr,
	AND = PALETTE.ruleAnd,
	NOT = PALETTE.ruleNot,
}

--- Cuenta tipos e instancias de items ya cacheados para un nodo (dev26
--- ronda 3, linea informativa "N objetos - M tipos"). Reutiliza
--- GlobalStorageSiK.Client.nodeContentsCache, ya poblado por
--- requestNodeContents/refreshContents - sin llamada de red aparte.
---@param node table
---@return number itemCount, number typeCount
local function nodeItemStats(node)
	local cache = GlobalStorageSiK.Client and GlobalStorageSiK.Client.nodeContentsCache or {}
	local payload = node and cache[node.id]
	local rows = payload and payload.rows or {}
	local itemCount = 0
	for i = 1, #rows do
		itemCount = itemCount + (tonumber(rows[i].count) or 0)
	end
	local typeCount = (node and node.itemTypeCount) or #rows
	return itemCount, typeCount
end

--- Ocupacion (%peso) del contenedor ya cacheada (dev26 ronda 4). El campo
--- `capacity` viaja DENTRO del mismo payload de nodeContents (ver
--- GS_Server.lua:getNodeContents / GS_NetworkCapacity.computeNode) - server
--- authoritative, sin recalcular nada en cliente. nil si el servidor aun no
--- ha respondido o el contenedor no expone capacidad legible (offline/sin
--- chunk/API vanilla ausente).
---@param node table
---@return table|nil
local function nodeCapacityInfo(node)
	local cache = GlobalStorageSiK.Client and GlobalStorageSiK.Client.nodeContentsCache or {}
	local payload = node and cache[node.id]
	return payload and payload.capacity or nil
end

---@param capacity table|nil
---@return string
local function occupancyLabelText(capacity)
	if not capacity then
		return T("IGUI_GS_OccupancyUnknown")
	end
	return T("IGUI_GS_OccupancyLine", capacity.percent or 0, capacity.usedWeight or 0, capacity.capacity or 0)
end

--- Construye el formulario de edición una sola vez (o reconstruye si _formBuilt=false).
function GS_NodeEditorUI:ensureForm()
	if not self.terminal or not self.node or not self.editorScroll then return end
	if self._buildingForm then return end
	if self._formBuilt then self:layoutForm(); return end
	self._buildingForm = true
	local node, scroll = self.node, self.editorScroll
	UI.Scroll.clear(scroll, false)
	local parent, width = UI.Scroll.childHost(scroll), UI.Scroll.contentWidth(scroll)
	local bottom = 0
	local function section(title, help)
		return UI.Block.create({ parent = parent, x = 0, y = bottom, w = width,
			title = title, tooltip = help or title, playerNum = self.playerNum })
	end
	local function finish(block, column)
		column:finish()
		bottom = block.y + block.h + 8
	end
	local function label(column, value)
		local widget = createText(column.parent, 0, 0, column.width, value, PALETTE.textPrimary)
		column:label(widget, FONT_HGT_SMALL)
		return widget
	end
	local function field(column, title, value, numeric, onSubmit)
		label(column, title)
		local widget = createField(value, 0, 0, column.width, numeric, onSubmit)
		column:block(widget, CONTROL_METRICS.inputHeight)
		return widget
	end
	local function button(column, title, callback, danger)
		return UI.Controls.button(column.parent, { text = title, onClick = callback,
			danger = danger == true, playerNum = self.playerNum })
	end
	local identity = section(T("IGUI_GS_EditorIdentity"))
	self.identityBlock = identity
	local form = identity:beginColumn()
	self.nameEntry = field(form, T("IGUI_GS_NodeRenameLabel"),
		self._editName or node.displayName or node.name or "", false, function()
			self._editName = self.nameEntry:getText()
			self:requestNodeUpdate({ displayName = self._editName })
		end)
	self.priorityEntry = field(form, T("IGUI_GS_NodePriorityLabel"),
		tostring(self._editPriority or node.priority or 50), true, function()
			local value = tonumber(self.priorityEntry:getText())
			if not value then return end
			value = math.max(1, math.min(100, math.floor(value + 0.5)))
			self._editPriority = value
			self.priorityEntry:setText(tostring(value))
			self:requestNodeUpdate({ priority = value })
		end)
	UI.Controls.setTooltip(self.priorityEntry, T("IGUI_GS_NodePriorityHint"))
	local function priority(value)
		self._editPriority = value
		self.priorityEntry:setText(tostring(value))
		self:requestNodeUpdate({ priority = value })
	end
	self.priorityPresetHighBtn = button(form, T("IGUI_GS_NodePriorityPresetHigh"), function() priority(10) end)
	self.priorityPresetNormalBtn = button(form, T("IGUI_GS_NodePriorityPresetNormal"), function() priority(50) end)
	self.priorityPresetLowBtn = button(form, T("IGUI_GS_NodePriorityPresetLow"), function() priority(90) end)
	form:row(CONTROL_METRICS.buttonHeight, {
		{ widget = self.priorityPresetHighBtn }, { widget = self.priorityPresetNormalBtn },
		{ widget = self.priorityPresetLowBtn } })
	-- Preserve the product's optional physical-container label integration.
	local notes = self._editNotes or node.notes or ""
	if self._editNotes == nil then
		notes = GlobalStorageSiK.CompatMods.getContainerLabelText(node, getSpecificPlayer(self.playerNum or 0)) or notes
	end
	self._editNotes = notes
	finish(identity, form)

	local rulesBlock = section(T("IGUI_GS_EditorRules"), T("IGUI_GS_EditorRulesHint"))
	self.rulesBlock = rulesBlock
	local rulesColumn = rulesBlock:beginColumn()
	local function nested(title, help)
		return UI.Block.create({ parent = rulesColumn.parent, w = rulesColumn.width,
			title = title, tooltip = help or title, playerNum = self.playerNum })
	end
	local zone = findZoneById(self.terminal, node.zoneId)
	if zone and #(zone.rules or {}) > 0 then
		local inherited = nested(T("IGUI_GS_NodeInheritedFromZone", zone.name or "?"))
		local inheritedColumn = inherited:beginColumn()
		local summary = GlobalStorageSiK.RulesUI.layoutSummary(zone.rules, inheritedColumn.width,
			UIFont.Small, PALETTE.textSecondary)
		self.inheritedZoneHost = createHost(inheritedColumn.parent, 0, 0, inheritedColumn.width,
			math.max(FONT_HGT_SMALL, summary.lineCount * (FONT_HGT_SMALL + 2)))
		addSummaryRuns(self.inheritedZoneHost, summary, 0)
		inheritedColumn:block(self.inheritedZoneHost, self.inheritedZoneHost.height)
		self.editZoneFromNodeBtn = button(inheritedColumn, T("IGUI_GS_NodeInheritedEditZoneBtn"), function()
			GlobalStorageSiK.TerminalZoneEditor.open(self.terminal, zone,
				self.terminal.terminalState and self.terminal.terminalState.nodes or {})
		end)
		inheritedColumn:block(self.editZoneFromNodeBtn, CONTROL_METRICS.buttonHeight)
		rulesColumn:block(inherited, inheritedColumn:finish())
	end
	local protocol = nested(T("IGUI_GS_NodeRulesTitle"), T("IGUI_GS_NodeRulesHint"))
	local protocolColumn = protocol:beginColumn()
	local summary = GlobalStorageSiK.RulesUI.layoutSummary(node.rules or {}, protocolColumn.width,
		UIFont.Small, PALETTE.textSecondary)
	self.rulesSummaryHost = createHost(protocolColumn.parent, 0, 0, protocolColumn.width,
		math.max(FONT_HGT_SMALL, summary.lineCount * (FONT_HGT_SMALL + 2)))
	protocolColumn:block(self.rulesSummaryHost, self.rulesSummaryHost.height)
	rulesColumn:block(protocol, protocolColumn:finish())

	local cache = GlobalStorageSiK.Client.nodeContentsCache or {}
	local payload = cache[node.id]
	local suggested = payload and payload.suggestedNativePath
	self._sugCardMissingData = payload == nil
	local present = false
	for _, rule in ipairs(node.rules or {}) do
		local condition = rule.condition or {}
		if condition.type == "category" and
			(condition.nativePath == suggested or condition.value == suggested) then present = true end
	end
	if suggested and suggested ~= "" and not present then
		local suggestion = nested(T("IGUI_GS_NodeSuggestedCat") .. " " .. categoryDisplayLabel(suggested))
		local suggestionColumn = suggestion:beginColumn()
		local function applySuggested(op)
			local condition = { type = "category", value = suggested }
			if GlobalStorageSiK.NativeProduct.decodePath(suggested) then condition.nativePath = suggested end
			local newRule = { op = op, condition = condition }
			local function apply()
				GlobalStorageSiK.NetClient.sendCommand("updateNode", { nodeId = node.id, addRule = newRule })
			end
			local conflict = GlobalStorageSiK.RulesUI.detectContradiction(node.rules, newRule)
			if conflict then
				confirmAction(T("IGUI_GS_RuleContradictionQuestion", conflict.op,
					describeCondition(conflict.condition), op, describeCondition(condition)), apply,
					T("IGUI_GS_RuleContradictionConsequences", conflict.op,
						describeCondition(conflict.condition), op, describeCondition(condition)))
			else apply() end
		end
		suggestionColumn:row(CONTROL_METRICS.buttonHeight, {
			{ widget = button(suggestionColumn, T("IGUI_GS_NodeApplySuggestedOr"), function() applySuggested("OR") end) },
			{ widget = button(suggestionColumn, T("IGUI_GS_NodeApplySuggestedAnd"), function() applySuggested("AND") end) } })
		rulesColumn:block(suggestion, suggestionColumn:finish())
	end
	for _, op in ipairs(RULE_OPS) do
		local ruleBlock = self:buildRuleSection(rulesBlock, op)
		rulesColumn:block(ruleBlock, ruleBlock.h)
	end
	finish(rulesBlock, rulesColumn)
	self._ruleCountAtBuild = #(node.rules or {})
	self._rulesLayoutAtBuild = GlobalStorageSiK.RulesUI.layoutSignature(node.rules)

	if node.offline == true then
		local recovery = section(T("IGUI_GS_NodeRecoveryTitle"), T("IGUI_GS_NodeRecoveryBody"))
		local recoveryColumn = recovery:beginColumn()
		local lines = UI.Controls.wrapText(T("IGUI_GS_NodeRecoveryBody"), recoveryColumn.width, UIFont.Small)
		for i = 1, #lines do label(recoveryColumn, lines[i]) end
		self.recoveryTransferBtn = button(recoveryColumn, T("IGUI_GS_NodeBtnTransferConfig"),
			function() self:requestConfigTransferProposal() end)
		recoveryColumn:block(self.recoveryTransferBtn, CONTROL_METRICS.buttonHeight)
		self.removeBtn = button(recoveryColumn, T("IGUI_GS_NodeBtnRemove"),
			function() self:confirmRemoveFromNetwork() end, true)
		recoveryColumn:block(self.removeBtn, CONTROL_METRICS.buttonHeight)
		self.rebindBtn = button(recoveryColumn, T("IGUI_GS_NodeBtnRebind"),
			function() self:requestRebindProposal() end)
		recoveryColumn:block(self.rebindBtn, CONTROL_METRICS.buttonHeight)
		for i = 1, #(self._rebindCandidates or {}) do
			local candidate = self._rebindCandidates[i]
			local text = T("IGUI_GS_NodeRebindCandidate", candidate.name or "?",
				candidate.x or "?", candidate.y or "?", candidate.z or "?")
			recoveryColumn:block(button(recoveryColumn, text,
				function() self:requestRebindProposal(candidate.nodeId) end), CONTROL_METRICS.buttonHeight)
		end
		finish(recovery, recoveryColumn)
	end
	self._contentsStartY = bottom
	self._contentsFingerprint = nil
	self._formBuilt = true
	self:syncTitleFromName()
	self:refreshRulesSummary()
	for _, op in ipairs(RULE_OPS) do self:rebuildRuleChips(op) end
	self:mountFixedActions()
	self:refreshContents()
	self._lastLayoutW = width
	self._buildingForm = false
end

function GS_NodeEditorUI:mountFixedActions()
	if not self.editorDock then return end
	if self.actionsBlock then self.actionsBlock:dispose() end
	local rect = self.editorDock:getFixedBottomRect()
	local block = UI.Block.create({ parent = self.editorDock.fixedBottomHost,
		w = rect.w, title = T("IGUI_GS_PermColActions"), tooltip = T("IGUI_GS_ApplyAllChangesTooltip"),
		playerNum = self.playerNum })
	self.actionsBlock = block
	local column = block:beginColumn()
	local function action(title, callback, danger, tooltip)
		return UI.Controls.button(column.parent, { text = title, onClick = callback,
			danger = danger == true, tooltip = tooltip, playerNum = self.playerNum })
	end
	local template = GlobalStorageSiK.TerminalNodeEditor.configTemplate
	self.copyConfigBtn = action(T("IGUI_GS_NodeConfigCopy"), function() self:copyConfigTemplate() end,
		false, T("IGUI_GS_NodeConfigCopyTooltip"))
	local pasteLabel = T("IGUI_GS_NodeConfigPaste") .. (template and (" "
		.. T("IGUI_GS_PunctuationMiddleDot") .. " "
		.. tostring(template.sourceName or "?")) or "")
	self.pasteConfigBtn = action(pasteLabel, function() self:pasteConfigTemplate() end, false,
		template and T("IGUI_GS_NodeConfigTemplateReadyRules", template.sourceName or "?",
			#(template.rules or {}), template.priority or 50) or T("IGUI_GS_NodeConfigTemplateEmpty"))
	self.pasteConfigBtn:setEnable(template ~= nil)
	self.extendToZoneBtn = action(T("IGUI_GS_NodeConfigExtendToZone"),
		function() self:confirmExtendToZone() end, false, T("IGUI_GS_NodeConfigExtendToZoneTooltip"))
	column:row(CONTROL_METRICS.buttonHeight, {
		{ widget = self.copyConfigBtn }, { widget = self.pasteConfigBtn }, { widget = self.extendToZoneBtn } })
	local excluded = self.node.membership == "excluded"
	self.membBtn = action(T(excluded and "IGUI_GS_NodeBtnInclude" or "IGUI_GS_NodeExcludeContainer"), function()
		if self.node.membership == "excluded" then
			self:requestNodeUpdate({ enabled = true, membership = "active" })
		else self:confirmExclude() end
	end, not excluded, T("IGUI_GS_NodeExcludeTooltip"))
	self.applyAllBtn = action(T("IGUI_GS_ApplyAllChanges"), function()
		if not self.node then return end
		self._editName = self.nameEntry:getText()
		local priority = tonumber(self.priorityEntry:getText())
		local opts = { displayName = self._editName, notes = self._editNotes }
		if priority then
			priority = math.max(1, math.min(100, math.floor(priority + 0.5)))
			self._editPriority, opts.priority = priority, priority
			self.priorityEntry:setText(tostring(priority))
		end
		GlobalStorageSiK.CompatMods.pushContainerLabelText(self.node,
			getSpecificPlayer(self.playerNum or 0), self._editNotes)
		self:requestNodeUpdate(opts)
		self:syncTitleFromName()
	end, false, T("IGUI_GS_ApplyAllChangesTooltip"))
	column:row(CONTROL_METRICS.buttonHeight, { { widget = self.membBtn }, { widget = self.applyAllBtn } })
	self.editorDock:setFixedBottomHeight(column:finish())
end

--- Each operator owns its controls inside the shared Rules Block.
function GS_NodeEditorUI:buildRuleSection(parentBlock, op)
	local rules = self.node.rules or {}
	local count = 0
	for i = 1, #rules do if rules[i].op == op then count = count + 1 end end
	local chipH, chipGap = UI.Controls.dismissibleRowHeight({ profile = "editor" }), 8
	local chipsH = math.max(FONT_HGT_SMALL, count * (chipH + chipGap) - chipGap)
	local card = UI.Block.create({ parent = parentBlock.childParent,
		w = parentBlock:getContentRect().w, title = T(RULE_OP_TITLE_KEY[op]),
		accent = RULE_OP_COLOR[op],
		tooltip = T("IGUI_GS_NodeRulesHint"), playerNum = self.playerNum })
	local column = card:beginColumn()
	local host = createHost(column.parent, 0, 0, column.width, chipsH)
	column:block(host, chipsH)
	self._ruleCards, self._ruleChipsHosts, self._ruleAddBtns =
		self._ruleCards or {}, self._ruleChipsHosts or {}, self._ruleAddBtns or {}
	self._ruleCards[op], self._ruleChipsHosts[op] = card, host
	local add = UI.Controls.button(column.parent, { text = T(RULE_OP_ADD_KEY[op]),
		playerNum = self.playerNum, onClick = function()
			if not self.node then return end
			local scopeRules = {}
			for _, sibling in ipairs(self.terminal.terminalState.nodes or {}) do
				if sibling.id ~= self.node.id and sibling.zoneId == self.node.zoneId then
					for _, rule in ipairs(sibling.rules or {}) do scopeRules[#scopeRules + 1] = rule end
				end
			end
			GlobalStorageSiK.FilterEditor.show({ kind = "node", id = self.node.id,
				rules = self.node.rules, scopeRules = scopeRules }, op,
				function() self:rebuildForm() end)
		end })
	self._ruleAddBtns[op] = add
	column:block(add, CONTROL_METRICS.buttonHeight)
	column:finish()
	return card
end

--- Recalcula la frase-resumen del protocolo dentro de rulesSummaryHost. El
--- host ya tiene la altura correcta calculada en ensureForm (regla 7,
--- CLAUDE.md: texto de longitud variable, nunca ISLabel de una sola linea).
function GS_NodeEditorUI:refreshRulesSummary()
	local host = self.rulesSummaryHost
	if not host then return end
	for i = #(host.childrenInOrder or {}), 1, -1 do
		local ch = host.childrenInOrder[i]
		if ch.dispose then ch:dispose()
		else
			host:removeChild(ch)
			if ch.removeFromUIManager then ch:removeFromUIManager() end
		end
	end
	local rules = (self.node and self.node.rules) or {}
	local layout = GlobalStorageSiK.RulesUI.layoutSummary(rules, host.width,
		UIFont.Small, PALETTE.textSecondary)
	addSummaryRuns(host, layout, 0)
end

--- Rellena los chips de UN grupo de reglas (OR/AND/NOT) dentro de su host.
--- Quitar una regla la borra directamente de node.rules (server-authoritative,
--- mismo patron que ya usaban los filtros legacy) y fuerza un rebuild
--- completo del formulario (resumen y alturas de host siempre exactos).
---@param op string
function GS_NodeEditorUI:rebuildRuleChips(op)
	local host = self._ruleChipsHosts and self._ruleChipsHosts[op]
	if not host then return end
	for i = #(host.childrenInOrder or {}), 1, -1 do
		local ch = host.childrenInOrder[i]
		host:removeChild(ch)
		if ch.removeFromUIManager then ch:removeFromUIManager() end
	end

	local allRules = (self.node and self.node.rules) or {}
	local CHIP_H, CHIP_PAD = UI.Controls.dismissibleRowHeight({ profile = "editor" }), 8
	local cy = 0
	local hostW = host.width
	local removeText = T("IGUI_GS_Remove")

	local shown = 0
	for realIdx = 1, #allRules do
		local rule = allRules[realIdx]
		if rule.op == op then
			shown = shown + 1
			local label = describeCondition(rule.condition)
			local labelColor = GlobalStorageSiK.RulesUI.conditionColor(
				rule.condition, PALETTE.textPrimary)

			local capturedIdx = realIdx
			UI.Controls.dismissibleRow(host, {
				x = 0, y = cy, w = hostW, h = CHIP_H, profile = "editor",
				text = label, tooltip = label, actionTooltip = removeText, playerNum = self.playerNum,
				tone = "ruleText", theme = { ruleText = { r = labelColor[1],
					g = labelColor[2], b = labelColor[3], a = labelColor[4] or 1 } },
				onRemove = function()
					if not self.node then return end
					GlobalStorageSiK.NetClient.sendCommand("updateNode", { nodeId = self.node.id, removeRuleIndex = capturedIdx })
					table.remove(self.node.rules, capturedIdx)
					self:rebuildForm()
				end })
			cy = cy + CHIP_H + CHIP_PAD
		end
	end
	if shown == 0 then
		createText(host, 4, CHIP_PAD, math.max(1, hostW - 8),
			T("IGUI_GS_NodeRulesEmpty"), PALETTE.textMuted)
	end
	self:updateScrollHeight()
end

--- Guarda estado de edición, destruye y reconstruye el formulario.
function GS_NodeEditorUI:rebuildForm()
	if not self.editorScroll then return end
	-- Preservar estado del formulario
	if self.nameEntry  then self._editName  = self.nameEntry:getText()  end
	if self.notesEntry then self._editNotes = self.notesEntry:getText() end
	if self.priorityEntry then
		self._editPriority = self.priorityEntry:getText()
	end
	local savedOffset = UI.Scroll.getScrollOffset(self.editorScroll)
	self:resetForm()
	self:ensureForm()
	UI.Scroll.setScrollOffset(self.editorScroll, savedOffset)
end

--- Actualiza etiquetas de botones según estado actual del nodo.
--- NO toca nameEntry/notesEntry/priorityEntry: son campos de edicion en curso
--- del jugador, y esta funcion se dispara en cada sync de red desde el
--- servidor (syncNodeData), que puede llegar en cualquier momento mientras el
--- editor esta abierto. Pisarlos aqui perdia silenciosamente texto/valores
--- pendientes de "Aplicar". El refresco real desde servidor ya ocurre en
--- setNode()/rebuildForm() al cambiar de nodo o justo tras aplicar un campo.
function GS_NodeEditorUI:syncFormButtons()
	if not self.node then
		return
	end
	-- Cantidad, distribucion OR/AND/NOT o texto pueden cambiar desde el build.
	-- La firma visible detecta tambien sustituciones con el mismo conteo. Los
	-- hosts de
	-- OR/AND/NOT solo se dimensionan de verdad en un build completo
	-- (buildRuleSection -> setBounds); si solo repintasemos los
	-- chips aqui (rebuildRuleChips) con un conteo distinto al que se uso
	-- para dimensionar, el chip nuevo (o el hueco de uno quitado) queda
	-- fuera de la tarjeta, tapado por/separado del boton "+ Anadir regla".
	if self._rulesLayoutAtBuild ~= GlobalStorageSiK.RulesUI.layoutSignature(self.node.rules) then
		self:rebuildForm()
		return
	end
	local excluded = self.node.membership == "excluded"
	if self.membBtn then
		local label = excluded and T("IGUI_GS_NodeBtnInclude") or T("IGUI_GS_NodeExcludeContainer")
		if self.membBtn.setText then self.membBtn:setText(label)
		elseif self.membBtn.setTitle then self.membBtn:setTitle(label) end
		local color = (not excluded) and UI.Theme.color("danger")
			or UI.Theme.color("surfaceAlt")
		self.membBtn.backgroundColor = { r = color.r, g = color.g,
			b = color.b, a = color.a }
	end
	if self.statsLbl then
		local itemCount, typeCount = nodeItemStats(self.node)
		self.statsLbl:setText(T("IGUI_GS_NodeStatsLine", itemCount, typeCount))
	end
	if self.occupancyLbl then
		self.occupancyLbl:setText(occupancyLabelText(nodeCapacityInfo(self.node)))
	end
	self:refreshRulesSummary()
	for _, op in ipairs(RULE_OPS) do
		self:rebuildRuleChips(op)
	end
end

--- Huella del bloque de contenido para evitar reconstrucciones redundantes.
---@param node table
---@return string
local function contentsFingerprint(node)
	local cache = GlobalStorageSiK.Client and GlobalStorageSiK.Client.nodeContentsCache or {}
	local payload = cache[node.id] or {}
	local rows = payload.rows or {}
	local rowCount = #rows
	local firstType = rowCount > 0 and (rows[1].fullType or "") or ""
	return string.format(
		"%s|%s|%d|%s|%s",
		tostring(payload.source or ""),
		tostring(payload.suggestedNativePath or ""),
		rowCount,
		tostring(node.itemTypeCount or 0),
		firstType
	)
end

--- Actualiza solo el bloque de contenido del contenedor (sin tocar el formulario).
function GS_NodeEditorUI:refreshContents()
	if not self._formBuilt or not self.editorScroll or not self.node or not self.terminal then
		return
	end

	local fp = contentsFingerprint(self.node)
	if self._contentsFingerprint == fp then
		return
	end
	self._contentsFingerprint = fp

	local scroll = self.editorScroll
	local savedOffset = UI.Scroll.getScrollOffset(scroll)
	local innerW = UI.Scroll.contentWidth(scroll)
	local contentW = math.max(1, innerW)

	self:ensureContentsHost()
	if not self.contentsHost then
		return
	end

	self.contentsHost:setX(0)
	self.contentsHost:setY(self._contentsStartY or 0)
	self.contentsHost:setWidth(contentW)
        self:syncFormButtons()
        if not self.contentsView then
                self.contentsView = ContainerInventory.mount(self.contentsHost, self, self.node, {
                        x = 0, y = 0, w = contentW,
			onHeightChanged = function(view)
				local currentOffset = self.editorScroll
					and UI.Scroll.getScrollOffset(self.editorScroll) or nil
				local height = view and view:getHeight() or 40
				self.contentsHost:setHeight(math.max(40, height))
                                self._lastContentBottom = (self._contentsStartY or 0)
                                        + self.contentsHost:getHeight()
				self:updateScrollHeight(self._lastContentBottom)
				if self.editorScroll and currentOffset ~= nil then
					UI.Scroll.setScrollOffset(self.editorScroll, currentOffset)
				end
			end,
                })
        elseif self.contentsView.refresh then
                self.contentsView:refresh(self.node)
        end
        local viewH = self.contentsView and self.contentsView:getHeight() or 40
        self.contentsHost:setHeight(math.max(40, viewH))
	self._lastContentBottom = (self._contentsStartY or 0) + self.contentsHost:getHeight()
	self:updateScrollHeight(self._lastContentBottom)
	UI.Scroll.setScrollOffset(scroll, savedOffset)
end

--- Recalcula altura scrollable del panel.
--- Sin argumento, usa la ultima altura total conocida (self._lastContentBottom),
--- NO self._contentsStartY (que es solo el INICIO del bloque de contenido: usarlo
--- como fallback colapsaba el scroll cada vez que rebuildRuleChips/syncFormButtons
--- se llamaban solos, p.ej. en cada sync de nodos desde el servidor con el editor abierto).
---@param contentBottom number|nil
function GS_NodeEditorUI:updateScrollHeight(contentBottom)
	if not self.editorScroll then
		return
	end
	local bottom = contentBottom
	if not bottom then
		bottom = self._lastContentBottom or self._contentsStartY or 0
	end
	if self.editorDock then
		self.editorDock:setContentHeight(bottom)
	else
		UI.Scroll.setContentHeight(self.editorScroll, bottom)
	end
end

--- Reconstruye formulario al cambiar de nodo (preserva _editName, etc. - las
--- reglas ya no tienen mirror local, se leen directamente de node.rules).
function GS_NodeEditorUI:resetForm()
	if self.contentsHost then
		self:clearContentsHost()
		if self.editorScroll then
			local host = UI.Scroll.childHost(self.editorScroll)
			if host and host.removeChild then
				host:removeChild(self.contentsHost)
			end
			if self.contentsHost.destroy then
				self.contentsHost:destroy()
			end
		end
	end
	self._formBuilt = false
	self.statsLbl        = nil
	self.occupancyLbl    = nil
	self.nameLbl         = nil
	self.nameEntry       = nil
	self.rulesTitleLbl   = nil
	self.rulesSummaryHost = nil
	self._ruleChipsHosts = nil
	self._ruleAddBtns    = nil
	self._ruleCards      = nil
	self._ruleCountAtBuild = nil
	self._rulesLayoutAtBuild = nil
	self.membBtn         = nil
	self.priorityLbl     = nil
	self.priorityHintLbl = nil
	self.priorityEntry   = nil
	self.priorityPresetHighBtn   = nil
	self.priorityPresetNormalBtn = nil
	self.priorityPresetLowBtn    = nil
	self.notesLbl        = nil
	self.notesEntry      = nil
	self.applyAllBtn     = nil
	self.configTemplateStatusLbl = nil
	self.copyConfigBtn   = nil
	self.pasteConfigBtn  = nil
	self.extendToZoneBtn = nil
	self.inheritedZoneHost = nil
	self.editZoneFromNodeBtn = nil
	self.contentsTitleLbl = nil
        self.contentsHost    = nil
        if self.contentsView and self.contentsView.dispose then self.contentsView:dispose() end
        self.contentsView    = nil
	self._contentsStartY = 0
	self._contentsFingerprint = nil
	self._lastContentBottom = nil
	self._rulesSummaryY  = 0
end

--- Elimina hijos del panel de contenido dinámico.
function GS_NodeEditorUI:clearContentsHost()
	local host = self.contentsHost
	if not host or not host.childrenInOrder then
		return
	end
	for i = #host.childrenInOrder, 1, -1 do
		local child = host.childrenInOrder[i]
		host:removeChild(child)
		if child.removeFromUIManager then
			child:removeFromUIManager()
		end
		if child.destroy then
			child:destroy()
		end
	end
end

--- Crea panel interno para contenido dinámico (se vacía en cada refresh).
function GS_NodeEditorUI:ensureContentsHost()
	if self.contentsHost and self.contentsHost.parent then
		return
	end
	local scroll = self.editorScroll
	if not scroll then
		return
	end
	local pad = 0
	local innerW = UI.Scroll.contentWidth(scroll)
	local contentW = math.max(1, innerW)
	self.contentsHost = createHost(nil, pad, self._contentsStartY or 0, contentW, 40)
	self.contentsHost.clipChildren = false
	UI.Scroll.addChild(scroll, self.contentsHost)
end

--- Asigna nodo y reconstruye UI.
---@param terminal GS_TerminalUI
---@param node table
---@param categories string[]
function GS_NodeEditorUI:setNode(terminal, node, categories)
	local sameNode = self.node and node and self.node.id == node.id
	self.terminal = terminal
	self.node = node
	self.categories = categories or {}
	-- Inicializar estado de edición al abrir un nodo nuevo
	if not sameNode then
		-- Las claves historicas se conservan literalmente: el servidor las
		-- clasifica y deja inactivas si pertenecen a un proveedor retirado.
		-- No se traducen ni se convierten al abrir el editor.
		local legacyCategories = node.categories or {}

		-- Migracion al motor unificado de reglas (dev26, ver
		-- Documentacion/GS_FilterRedesign_Plan.md): un contenedor que
		-- todavia no tiene entry.rules pero SI tenia categorias/filtros
		-- legacy los traduce a reglas OR (mismo comportamiento exacto, ver
		-- migrateLegacyToRules) y persiste de inmediato al abrir su editor -
		-- mismo patron ya establecido arriba para canonicalizar categorias.
		-- Un contenedor SIN ninguna regla configurada nunca migra (sigue
		-- vacio, protege el caso base de afinidad, ver §4.3 del plan).
		if (not node.rules or #node.rules == 0) and (#legacyCategories > 0 or #(node.filters or {}) > 0) then
			node.rules = migrateLegacyToRules(legacyCategories, node.filters)
			GlobalStorageSiK.TerminalNodeEditor.sendNodeUpdate(node.id, { rules = node.rules })
		end

		self._editName     = node.displayName or node.name or ""
		self._editNotes    = node.notes or ""
		self._editPriority = node.priority or 50
	end

	if not sameNode then
		self:resetForm()
	end

	if not self.editorDock then
		self.editorDock = ScrollDock.create({
			parent = self.contentHost or self, x = 0, y = 0, w = 400, h = 200,
			padding = 0, gap = 8, contentHeight = 0, playerNum = self.playerNum,
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
	-- Segunda pasada inicial: ensureForm puede haber activado overflow.
	self:layoutForm()
	self:syncTitleFromName()
	if sameNode then
		self._contentsFingerprint = nil
		self:refreshContents()
	end
end

--- Abre editor modal para un contenedor.
---@param terminal GS_TerminalUI|nil
---@param node table
---@param categories string[]
function GlobalStorageSiK.TerminalNodeEditor.open(terminal, node, categories)
	if not node then
		return
	end

	local existing = GlobalStorageSiK.TerminalNodeEditor.instance
	if existing and existing.node and existing.node.id == node.id then
		existing:bringToTop()
		return
	end

	GlobalStorageSiK.TerminalNodeEditor.close()

	-- Tamano/posicion compartidos con GS_TerminalUI_ZoneEditor.lua (dev26
	-- ronda 4; el perfil editor SiK.UI conserva geometria por jugador y se
	-- abre superpuesto sobre la ventana del terminal (este donde este en
	-- pantalla), no centrado en toda la pantalla: asi el jugador ve su
	-- personaje/inventario al lado en vez de que el modal los tape.
	local bounds = UI.Window.resolveBounds({ profile = "editor" })
	local x, y, w, h = bounds.x, bounds.y, bounds.w, bounds.h

	local ui = GS_NodeEditorUI:new(x, y, w, h)
	ui:initialise()
	UI.Modal.show(ui)
	ui:setNode(terminal, node, categories)
	GlobalStorageSiK.TerminalNodeEditor.instance = ui
	-- Verificación de solapes del modal al abrir (gated por DebugMode).
	if GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.checkOverlaps then
		GlobalStorageSiK.UIDebug.checkOverlaps(ui, "nodeEditor:open")
		GlobalStorageSiK.UIDebug.dumpTree(ui, "nodeEditor:open")
	end
	local allNodes = terminal and terminal.terminalState and terminal.terminalState.nodes or {}
	if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.highlightNode then
		GlobalStorageSiK.NodeHighlight.highlightNode(node, allNodes)
	end
end

--- Cierra editor si está abierto.
function GlobalStorageSiK.TerminalNodeEditor.close()
	local ui = GlobalStorageSiK.TerminalNodeEditor.instance
	if not ui then
		return
	end
	if ui.close then ui:close("product")
	else
		ui:setVisible(false)
		ui:removeFromUIManager()
		GlobalStorageSiK.TerminalNodeEditor.instance = nil
	end
end

--- Refresca contenido tras respuesta del servidor.
---@param args table|nil
function GlobalStorageSiK.TerminalNodeEditor.onContentsReceived(args)
	if args and args.detailPage then return end
	local ui = GlobalStorageSiK.TerminalNodeEditor.instance
	if not ui or not ui.node then
		return
	end
	local nodeId = args and args.nodeId
	if nodeId and ui.node.id ~= nodeId then
		return
	end
	ui._contentsFingerprint = nil
	ui:refreshContents()
	-- La tarjeta "Categoria sugerida" (con OR/AND) vive en el bloque de
	-- REGLAS, construido solo dentro de rebuildForm() - refreshContents()
	-- de arriba no la toca. Si al construir el formulario todavia no habia
	-- llegado la sugerencia del servidor, forzamos un unico rebuildForm()
	-- completo ahora que sí ha llegado, para que la tarjeta aparezca sin
	-- tener que cerrar y reabrir el editor.
	if ui._sugCardMissingData and args and args.suggestedNativePath and ui.rebuildForm then
		ui:rebuildForm()
	end
end

--- Actualiza datos del nodo tras cambio de estado del terminal.
---@param terminal GS_TerminalUI
---@param nodes table[]
function GlobalStorageSiK.TerminalNodeEditor.syncNodeData(terminal, nodes)
	local ui = GlobalStorageSiK.TerminalNodeEditor.instance
	if not ui or not ui.node then
		return
	end
	for i = 1, #(nodes or {}) do
		if nodes[i].id == ui.node.id then
			local updated = nodes[i]
			ui.node = updated
			-- Sincronizar estado de edición con datos del servidor (las
			-- reglas ya no tienen mirror local, se leen de updated.rules directamente)
			ui._editName = ui.nameEntry and ui.nameEntry:getText() or ui._editName
				or updated.displayName or updated.name or ""
			ui._editNotes = ui._editNotes or updated.notes or ""
			ui._editPriority = ui.priorityEntry and ui.priorityEntry:getText()
				or ui._editPriority or updated.priority or 50
			ui:syncTitleFromName()
			ui:syncFormButtons()
			if GlobalStorageSiK.NodeNaming and GlobalStorageSiK.NodeNaming.applyToNode then
				GlobalStorageSiK.NodeNaming.applyToNode(updated)
			end
			return
		end
	end
end

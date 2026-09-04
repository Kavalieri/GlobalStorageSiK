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
local UI = require "GS_UI_Framework"

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
local function addBlockInfoBtn(scroll, pad, y, titleText, tooltip, target)
	local titleW = getTextManager():MeasureStringX(UIFont.Small, titleText)
	local btn = UI.Controls.iconButton(nil, {
		x = pad + titleW + 6, y = y - math.floor((INFO_BTN_SIZE - FONT_HGT_SMALL) / 2),
		w = INFO_BTN_SIZE, h = INFO_BTN_SIZE, icon = "sik.info.24",
		text = "", tooltip = tooltip, payload = target,
	})
	UI.Scroll.addChild(scroll, btn)
	return btn
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

local function createField(text, x, y, w, numeric)
	return UI.Controls.field(nil, {
		x = x, y = y, w = w, h = CONTROL_METRICS.inputHeight,
		text = text, numeric = numeric == true,
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
	UI.Window.applyEditor(self, {
		geometryKey = "nodeEditor",
		geometryVersion = 2,
		title = T("IGUI_GS_NodeEditorTitle"),
		padding = PAD,
		onReflow = function() self:calculateLayout() end,
		onClose = function()
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
	-- SiK.UI.Window.applyEditor() posee el chrome compartido; no duplicarlo.
end

--- Actualiza título de ventana con el nombre del nodo en red.
function GS_NodeEditorUI:syncTitleFromName()
	local name = self.node and (self.node.displayName or self.node.name) or "?"
	self._titleText = T("IGUI_GS_NodeEditorTitle") .. ": " .. name
	if self.setHeader then self:setHeader(self._titleText) end
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
	if ui and ui.searchEntry and ui.searchEntry.getText then
		searchQuery = ui.searchEntry:getText() or ""
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
		or self._editPriority or self.node.priority or 50
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
	local message = T("IGUI_GS_NodeExtendToZoneConfirm", count, self.node.zoneName or "?")
	confirmAction(message, function()
		GlobalStorageSiK.NetClient.sendCommand("applyNodeTemplateToZone", {
			zoneId = self.node.zoneId,
			rules = self.node.rules or {},
		})
	end)
end

--- Confirmacion antes de excluir (dev26, ronda 2 - ver §4.5 del plan): solo
--- al excluir, nunca al volver a incluir - excluir saca el contenedor por
--- completo de deposito/extraccion hasta que el jugador lo revierta a mano.
function GS_NodeEditorUI:confirmExclude()
	if not self.node then return end
	local message = T("IGUI_GS_NodeExcludeConfirm", self.node.displayName or self.node.name or "?")
	confirmAction(message, function()
		self:requestNodeUpdate({ enabled = false, membership = "excluded" })
	end)
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

function GS_NodeEditorUI:calculateLayout()
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
	confirmAction(T("IGUI_GS_NodeRemoveConfirm", nodeName), function()
		if self.node and self.terminal then
			self.terminal:onRemoveNode(self.node.id)
			GlobalStorageSiK.TerminalNodeEditor.close()
		end
	end)
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
	confirmAction(T("IGUI_GS_NodeTransferConfigConfirm", sourceName, targetName), function()
		self.terminal:onTransferNodeConfiguration(self.node.id, proposal.token)
	end)
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
	confirmAction(T("IGUI_GS_NodeRebindConfirm", sourceName, targetName), function()
		self.terminal:onRebindNode(self.node.id, proposal.rebindToken)
	end)
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
	local terminal = self.terminal
	local node = self.node
	if not terminal or not node or not self.editorScroll then
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
	local contentW = math.max(1, innerW - pad * 2)
	local isExcluded       = node.membership == "excluded"

	-- Usar estado de edición pendiente si existe (sobrevive a rebuildForm)
	local editName     = self._editName     or node.displayName or node.name or ""
	local editNotes    = self._editNotes    or node.notes or ""
	local editPriority = self._editPriority or node.priority or 50

	-- Con Customizable Containers instalado, nuestro campo "Etiqueta" ES su
	-- etiqueta (una sola fuente de verdad, no dos campos "sincronizados"): al
	-- abrir el editor, su etiqueta manda si existe. Si CC no tiene aun
	-- etiqueta para este contenedor, partimos de nuestra nota guardada.
	if self._editNotes == nil then
		local ccLabel = GlobalStorageSiK.CompatMods.getContainerLabelText(node, getSpecificPlayer(0))
		if ccLabel and ccLabel ~= "" then
			editNotes = ccLabel
			self._editNotes = ccLabel
		end
	end

	-- ── Linea informativa (dev26, ronda 3): objetos y tipos ya conocidos
	-- para este contenedor (reutiliza GlobalStorageSiK.Client.nodeContentsCache,
	-- ya poblado por requestNodeContents - sin llamada de red aparte). Sin
	-- % de ocupacion todavia: no existe ninguna lectura de peso/capacidad a
	-- nivel de UN contenedor en el mod, solo agregada de red completa (ver
	-- GS_NetworkCapacity.lua) - queda para una ronda dedicada aparte.
	local itemCount, typeCount = nodeItemStats(self.node)
	self.statsLbl = createText(nil, pad, y, contentW,
		T("IGUI_GS_NodeStatsLine", itemCount, typeCount), PALETTE.textMuted)
	UI.Scroll.addChild(scroll, self.statsLbl)
	y = y + FONT_HGT_SMALL + 2

	self.occupancyLbl = createText(nil, pad, y, contentW,
		occupancyLabelText(nodeCapacityInfo(node)), PALETTE.textMuted)
	UI.Scroll.addChild(scroll, self.occupancyLbl)
	y = y + FONT_HGT_SMALL + 10
	if node.offline == true then
		local recoveryBody = T("IGUI_GS_NodeRecoveryBody")
		local recoveryW = math.max(1, contentW - 16)
		local bodyLines = UI.Controls.wrapText(recoveryBody, recoveryW, UIFont.Small)
		local summaryLayout = GlobalStorageSiK.RulesUI.layoutSummary(node.rules or {}, recoveryW,
			UIFont.Small, PALETTE.textSecondary)
		local cardH = FONT_HGT_SMALL + (#bodyLines + summaryLayout.lineCount) * (FONT_HGT_SMALL + 2)
			+ CONTROL_METRICS.buttonHeight * 2 + 28
		local card = createSectionCard(scroll, pad, y, contentW, cardH,
			PALETTE.statusDanger)
		UI.Scroll.addChild(scroll, card)
		local cy = y + 8
		local title = createText(nil, pad + 8, cy, recoveryW,
			T("IGUI_GS_NodeRecoveryTitle"), { 0.92, 0.35, 0.3, 1 })
		UI.Scroll.addChild(scroll, title); cy = cy + FONT_HGT_SMALL + 3
		for _, line in ipairs(bodyLines) do
			local label = createText(nil, pad + 8, cy, recoveryW, line,
				{ 0.72, 0.74, 0.78, 1 })
			UI.Scroll.addChild(scroll, label); cy = cy + FONT_HGT_SMALL + 2
		end
		self.recoverySummaryHost = createHost(nil, pad + 8, cy, recoveryW,
			math.max(FONT_HGT_SMALL, summaryLayout.lineCount * (FONT_HGT_SMALL + 2)))
		UI.Scroll.addChild(scroll, self.recoverySummaryHost)
		addSummaryRuns(self.recoverySummaryHost, summaryLayout, 0)
		cy = cy + self.recoverySummaryHost.height + 2
		self.recoveryTransferBtn = createBtn(pad + 8, cy + 3, recoveryW, T("IGUI_GS_NodeBtnTransferConfig"), scroll, function()
			self:requestConfigTransferProposal()
		end)
		UI.Controls.setTooltip(self.recoveryTransferBtn, T("IGUI_GS_NodeTransferConfigTip"))
		UI.Scroll.addChild(scroll, self.recoveryTransferBtn)
		self.recoveryRemoveBtn = createProductButton(
			pad + 8, cy + CONTROL_METRICS.buttonHeight + 7,
			recoveryW, CONTROL_METRICS.buttonHeight,
			T("IGUI_GS_NodeBtnRemove"), scroll, function()
			self:confirmRemoveFromNetwork()
		end, PALETTE.statusDanger, true)
		UI.Controls.setTooltip(self.recoveryRemoveBtn, T("IGUI_GS_NodeRemoveTooltip"))
		UI.Scroll.addChild(scroll, self.recoveryRemoveBtn)
		y = y + cardH + 10
	end

	-- ── Nombre (Aplicar unificado mas abajo, junto a Prioridad y Notas) ─────
	self.nameLbl = createSectionLabel(pad, y, T("IGUI_GS_NodeRenameLabel"))
	UI.Scroll.addChild(scroll, self.nameLbl)
	y = y + FONT_HGT_SMALL + 2

	self.nameEntry = createField(editName, pad, y, contentW, false)
	UI.Scroll.addChild(scroll, self.nameEntry)
	y = y + CONTROL_METRICS.inputHeight + 12

	-- ── Prioridad de llenado (escala 1-100, 1 = maxima) - dev26 ronda 3:
	-- movida a ser el SEGUNDO campo (justo tras el nombre), antes quedaba
	-- despues de todo el protocolo de reglas. Mismo esqueleto de frase que
	-- GS_TerminalUI_ZoneEditor.lua (solo cambia "contenedor"/"zona") -────
	self.priorityLbl = createSectionLabel(pad, y, T("IGUI_GS_NodePriorityLabel"))
	UI.Scroll.addChild(scroll, self.priorityLbl)
	addBlockInfoBtn(scroll, pad, y, T("IGUI_GS_NodePriorityLabel"), T("IGUI_GS_NodePriorityHint"), scroll)
	y = y + FONT_HGT_SMALL + 4

	self.priorityEntry = createField(tostring(editPriority), pad, y, contentW, true)
	UI.Scroll.addChild(scroll, self.priorityEntry)
	y = y + CONTROL_METRICS.inputHeight + 4

	-- Atajos rapidos: fijan el valor Y lo aplican de inmediato (accion
	-- explicita de un solo valor conocido, no arriesga perder otro campo).
	local function applyPriorityValue(n)
		n = math.floor(n + 0.5)
		if n < 1 then n = 1 elseif n > 100 then n = 100 end
		self._editPriority = n
		if self.priorityEntry then self.priorityEntry:setText(tostring(n)) end
		self:applyField("priority", n)
	end
	local presetW = math.floor((contentW - 8) / 3)
	self.priorityPresetHighBtn = createBtn(pad, y, presetW, T("IGUI_GS_NodePriorityPresetHigh"), scroll, function() applyPriorityValue(10) end)
	UI.Scroll.addChild(scroll, self.priorityPresetHighBtn)
	self.priorityPresetNormalBtn = createBtn(pad + presetW + 4, y, presetW, T("IGUI_GS_NodePriorityPresetNormal"), scroll, function() applyPriorityValue(50) end)
	UI.Scroll.addChild(scroll, self.priorityPresetNormalBtn)
	self.priorityPresetLowBtn = createBtn(pad + (presetW + 4) * 2, y, presetW, T("IGUI_GS_NodePriorityPresetLow"), scroll, function() applyPriorityValue(90) end)
	UI.Scroll.addChild(scroll, self.priorityPresetLowBtn)
	y = y + CONTROL_METRICS.buttonHeight + 14

	-- ── Heredado de tu zona (dev26, ronda 2 - ver §4.4-sexies del plan) ─────
	-- Bloque de solo lectura: si la zona de este contenedor tiene sus
	-- propias reglas, se muestran aqui con un enlace directo a su editor -
	-- la zona se evalua SIEMPRE antes que el contenedor (ver
	-- GS_Router.zoneRulesAllow), sin este bloque el jugador no tendria forma
	-- de saber por que un item "deberia" entrar aqui pero nunca llega.
	local zone = findZoneById(self.terminal, self.node.zoneId)
	if zone and zone.rules and #zone.rules > 0 then
		local inheritedLines = UI.Controls.wrapText(
			T("IGUI_GS_NodeInheritedFromZone", zone.name or "?"), contentW, UIFont.Small)
		local inheritedNeutral = { 0.6, 0.63, 0.67 }
		local inheritedLayout = GlobalStorageSiK.RulesUI.layoutSummary(
			zone.rules, contentW, UIFont.Small, inheritedNeutral)
		local hostH = (#inheritedLines + inheritedLayout.lineCount)
			* (FONT_HGT_SMALL + 2)
		self.inheritedZoneHost = createHost(nil, pad, y, contentW, hostH)
		UI.Scroll.addChild(scroll, self.inheritedZoneHost)
		local iy = 0
		for i, line in ipairs(inheritedLines) do
			local r, g, b = 0.6, 0.63, 0.67
			if i == 1 then r, g, b = 0.55, 0.75, 0.95 end
			createText(self.inheritedZoneHost, 0, iy, contentW, line,
				{ r, g, b, 1 })
			iy = iy + FONT_HGT_SMALL + 2
		end
		addSummaryRuns(self.inheritedZoneHost, inheritedLayout, iy)
		y = y + hostH + 4
		self.editZoneFromNodeBtn = createBtn(pad, y, contentW, T("IGUI_GS_NodeInheritedEditZoneBtn"), scroll, function()
			local zoneNodes = self.terminal and self.terminal.terminalState and self.terminal.terminalState.nodes or {}
			GlobalStorageSiK.TerminalZoneEditor.open(self.terminal, zone, zoneNodes)
		end)
		UI.Scroll.addChild(scroll, self.editZoneFromNodeBtn)
		y = y + CONTROL_METRICS.buttonHeight + 12
	end

	-- ── Protocolo de aceptación (motor AND/OR/NOT, dev26) ──────────────────
	-- Sustituye a los antiguos bloques "Categorias aceptadas"/"Filtros
	-- personalizados": un unico protocolo con tres grupos de reglas
	-- combinadas por operador (ver GS_Router.evaluateContainerRules y
	-- Documentacion/GS_FilterRedesign_Plan.md). Contenedores nunca abiertos
	-- con este editor siguen el camino legacy sin cambios (ver
	-- GlobalStorageSiK.Router.matchSpecificity) - abrir este editor migra el
	-- contenedor al nuevo modelo (mismo patron ya usado para canonicalizar
	-- categorias legacy en setNode, mas abajo).
	self.rulesTitleLbl = createSectionLabel(pad, y, T("IGUI_GS_NodeRulesTitle"))
	UI.Scroll.addChild(scroll, self.rulesTitleLbl)
	addBlockInfoBtn(scroll, pad, y, T("IGUI_GS_NodeRulesTitle"), T("IGUI_GS_NodeRulesHint"), scroll)
	y = y + FONT_HGT_SMALL + 8

	-- Resumen legible: se recalcula en rebuildRuleChips, aqui solo se reserva
	-- el hueco con el texto inicial para calcular su altura real (regla 7,
	-- CLAUDE.md: texto de longitud variable, nunca ISLabel de una sola linea).
	self._rulesSummaryY = y
	local summaryW = contentW
	local summaryLayout = GlobalStorageSiK.RulesUI.layoutSummary(self.node.rules,
		summaryW, UIFont.Small, PALETTE.textSecondary)
	self.rulesSummaryHost = createHost(nil, pad, y, summaryW,
		math.max(FONT_HGT_SMALL, summaryLayout.lineCount * (FONT_HGT_SMALL + 2)))
	UI.Scroll.addChild(scroll, self.rulesSummaryHost)
	y = y + self.rulesSummaryHost:getHeight() + 8

	-- ── Ruta nativa sugerida (basada en el contenido actual) ────────────────
	-- El servidor solo propone una ruta nativa útil. La ausencia de sugerencia
	-- no se sustituye por una categoría técnica, externa o inferida.
	local _sugCache = GlobalStorageSiK.Client and GlobalStorageSiK.Client.nodeContentsCache or {}
	local _sugPayload = self.node and _sugCache[self.node.id]
	local suggestedNativePath = _sugPayload and _sugPayload.suggestedNativePath
	local sugKey = suggestedNativePath and suggestedNativePath ~= "" and suggestedNativePath or nil
	-- El contenido del nodo (y con el, la sugerencia) llega ASYNC del
	-- servidor y puede no haber llegado todavia cuando se construye el
	-- formulario por primera vez al abrir el editor - `refreshContents()` se
	-- reejecuta solo con el bloque de "Contenido del contenedor", nunca con
	-- este bloque de reglas. Marcamos que faltaba dato para que
	-- `onContentsReceived` pueda pedir un `rebuildForm()` completo UNA vez
	-- cuando de verdad llegue la sugerencia (ver mas abajo en este fichero).
	self._sugCardMissingData = not sugKey
	if sugKey and sugKey ~= "" then
		local alreadyPresent = false
		for _, rule in ipairs(self.node.rules or {}) do
			if rule.condition and rule.condition.type == "category" then
				local existingNative = string.lower(tostring(rule.condition.nativePath or ""))
				local existingValue = string.lower(tostring(rule.condition.value or ""))
				if existingValue == string.lower(tostring(sugKey))
					or (suggestedNativePath
						and existingNative == string.lower(tostring(suggestedNativePath))) then
					alreadyPresent = true
					break
				end
			end
		end
		if not alreadyPresent then
			-- Rediseño (2026-08-25, protocolo de aceptación §07, "Categoría
			-- sugerida"): pasa de etiqueta+botón sueltos a una tarjeta más,
			-- la PRIMERA del bloque de reglas (justo encima de OR) - mismo
			-- patrón visual que las tarjetas OR/AND/NOT (createSectionCard),
			-- color L1 derivado siempre de suggestedNativePath; el prefijo queda
			-- neutro porque no forma parte de la categoria. Dos botones (OR/AND,
			-- sin NOT - excluir por
			-- una sugerencia automática no tiene caso de uso real), los dos
			-- pasan por el mismo detector de contradicciones que cualquier
			-- otro camino de añadir regla (GS_FilterEditor.lua:onAddClicked)
			-- - antes el único botón (solo OR) se lo saltaba (bug real
			-- cerrado en la auditoria pre-release del mismo día).
			local pal = PALETTE
			local neutral = GlobalStorageSiK.RulesUI.conditionColor({
				type = "category", value = sugKey,
				nativePath = suggestedNativePath,
			}, pal.textMuted)
			local cardPad = 8
			local cardX = pad
			local cardW = contentW
			local cardTop = y
			local cy = cardTop + cardPad
			local cx = pad + cardPad + 4

			local sugCard = createSectionCard(scroll, cardX, cardTop, cardW, 10, neutral)
			UI.Scroll.addChild(scroll, sugCard)

			local sugPrefix = T("IGUI_GS_NodeSuggestedCat") .. " "
			local prefixColor = pal.textSecondary
			local sugPrefixLbl = createText(nil, cx, cy, cardW - cardPad * 2,
				sugPrefix, prefixColor)
			UI.Scroll.addChild(scroll, sugPrefixLbl)
			local sugValueX = cx + getTextManager():MeasureStringX(UIFont.Small, sugPrefix)
			local sugValue = UI.Controls.truncateText(
				categoryDisplayLabel(sugKey), cardW - (sugValueX - cardX) - cardPad,
				UIFont.Small)
			local sugValueLbl = createText(nil, sugValueX, cy,
				math.max(1, cardW - (sugValueX - cardX) - cardPad), sugValue, neutral)
			UI.Scroll.addChild(scroll, sugValueLbl)
			cy = cy + FONT_HGT_SMALL + 6

			local function applySuggested(op)
				if not self.node then return end
				local condition = { type = "category", value = sugKey }
				if GlobalStorageSiK.NativeProduct.decodePath(suggestedNativePath) then
					condition.nativePath = suggestedNativePath
				elseif GlobalStorageSiK.NativeProduct.decodePath(sugKey) then
					condition.nativePath = sugKey
				end
				local newRule = { op = op, condition = condition }
			local function applyRule()
				GlobalStorageSiK.NetClient.sendCommand("updateNode", { nodeId = self.node.id, addRule = newRule })
			end
				local conflict = GlobalStorageSiK.RulesUI.detectContradiction(self.node.rules, newRule)
				if not conflict then
					applyRule()
					return
				end
				local existingLabel = describeCondition(conflict.condition)
				local newLabel = describeCondition(newRule.condition)
				local message = T("IGUI_GS_RuleContradictionConfirm", conflict.op, existingLabel, newRule.op, newLabel)
				confirmAction(message, applyRule)
			end

			local btnGap = 6
			local btnW = math.floor((cardW - cardPad * 2 - 4 - btnGap) / 2)
			local orBtn = createBtn(cx, cy, btnW, T("IGUI_GS_NodeApplySuggestedOr"), scroll, function()
				applySuggested("OR")
			end)
			UI.Controls.setTooltip(orBtn, T("IGUI_GS_NodeApplySuggestedOrTooltip"))
			UI.Scroll.addChild(scroll, orBtn)
			local andBtn = createBtn(cx + btnW + btnGap, cy, btnW, T("IGUI_GS_NodeApplySuggestedAnd"), scroll, function()
				applySuggested("AND")
			end)
			UI.Controls.setTooltip(andBtn, T("IGUI_GS_NodeApplySuggestedAndTooltip"))
			UI.Scroll.addChild(scroll, andBtn)
			cy = cy + CONTROL_METRICS.buttonHeight + cardPad

			UI.Layout.apply(sugCard, { x = cardX, y = cardTop,
				w = cardW, h = cy - cardTop })
			y = cy + 8
		end
	end

	for _, op in ipairs(RULE_OPS) do
		y = self:buildRuleSection(scroll, pad, contentW, y, op)
	end
	-- Firma del numero de reglas usada para dimensionar tarjetas/hosts en
	-- ESTE build (ver syncFormButtons) - dev26 ronda 4quater: anadir una
	-- regla dispara `rebuildForm()` de inmediato via el callback de
	-- GS_FilterEditor.lua ANTES de que node.rules tenga la regla nueva
	-- (llega despues, async, por el siguiente sync de terminalState) - ese
	-- sync solo repintaba los chips (rebuildRuleChips) sin volver a llamar
	-- resizeSectionCard, dejando el chip nuevo fuera de la tarjeta, tapado
	-- por el boton "+ Anadir regla" (bug real con captura del usuario).
	self._ruleCountAtBuild = #(self.node and self.node.rules or {})

	-- ── Notas / ubicacion (Aplicar unificado mas abajo) ─────────────────────
	self.notesLbl = createSectionLabel(pad, y, T("IGUI_GS_NodeNotesLabel"))
	UI.Scroll.addChild(scroll, self.notesLbl)
	y = y + FONT_HGT_SMALL + 2

	self.notesEntry = createField(editNotes, pad, y, contentW, false)
	UI.Controls.setTooltip(self.notesEntry, T("IGUI_GS_NodeNotesHint"))
	UI.Scroll.addChild(scroll, self.notesEntry)
	y = y + CONTROL_METRICS.inputHeight + 8

	-- ── Acciones (dev26, ronda 3): plantilla (copiar/pegar/extender a la
	-- zona) baja aqui desde el principio de la ventana, agrupada junto a
	-- Aplicar y Excluir - antes vivia arriba del todo, separada del resto de
	-- acciones del contenedor.
	local templateSectionTitle = createSectionLabel(pad, y, T("IGUI_GS_NodeConfigTemplateTitle"))
	UI.Scroll.addChild(scroll, templateSectionTitle)
	y = y + FONT_HGT_SMALL + 4
	local template = GlobalStorageSiK.TerminalNodeEditor.configTemplate
	local templateStatus = template
		and T("IGUI_GS_NodeConfigTemplateReadyRules", template.sourceName or "?", #(template.rules or {}), template.priority or 50)
		or T("IGUI_GS_NodeConfigTemplateEmpty")
	local statusText = UI.Controls.truncateText(templateStatus, contentW, UIFont.Small)
	self.configTemplateStatusLbl = createText(nil, pad, y, contentW,
		statusText, PALETTE.textMuted)
	UI.Scroll.addChild(scroll, self.configTemplateStatusLbl)
	y = y + FONT_HGT_SMALL + 6
	-- Copiar/Pegar en pareja (2 botones a mitad de ancho - encajaban bien asi
	-- antes de ronda 2), Extender a la zona en su propia fila a ancho
	-- completo: 3 botones apretados en una sola fila truncaban su texto
	-- (createButton se ajusta al ancho pasado pero nunca lo supera).
	local templateGap = 4
	local templateBtnW = math.floor((contentW - templateGap) / 2)
	self.copyConfigBtn = createBtn(pad, y, templateBtnW, T("IGUI_GS_NodeConfigCopy"), scroll, function()
		self:copyConfigTemplate()
	end)
	UI.Controls.setTooltip(self.copyConfigBtn, T("IGUI_GS_NodeConfigCopyTooltip"))
	UI.Scroll.addChild(scroll, self.copyConfigBtn)
	self.pasteConfigBtn = createBtn(pad + templateBtnW + templateGap, y, templateBtnW, T("IGUI_GS_NodeConfigPaste"), scroll, function()
		self:pasteConfigTemplate()
	end)
	self.pasteConfigBtn:setEnable(template ~= nil)
	UI.Controls.setTooltip(self.pasteConfigBtn, T("IGUI_GS_NodeConfigPasteTooltip"))
	UI.Scroll.addChild(scroll, self.pasteConfigBtn)
	y = y + CONTROL_METRICS.buttonHeight + 6
	-- "Extender a la zona" (dev26, ronda 2 - ver
	-- Documentacion/GS_FilterRedesign_Plan.md §4.4-quater): sustituye a la
	-- antigua seccion "Plantilla" del editor de ZONA (ya retirada) - aplica
	-- el protocolo de aceptacion de ESTE contenedor a todos los demas de su
	-- misma zona, con confirmacion previa. Nunca toca la prioridad.
	self.extendToZoneBtn = createBtn(pad, y, contentW, T("IGUI_GS_NodeConfigExtendToZone"), scroll, function()
		self:confirmExtendToZone()
	end)
	UI.Controls.setTooltip(self.extendToZoneBtn, T("IGUI_GS_NodeConfigExtendToZoneTooltip"))
	UI.Scroll.addChild(scroll, self.extendToZoneBtn)
	y = y + CONTROL_METRICS.buttonHeight + 12

	-- ── Aplicar TODO junto (nombre + prioridad + notas) ─────────────────────
	-- Antes cada campo tenia su propio "Aplicar"; si el jugador cambiaba
	-- varios y solo pulsaba uno, los demas quedaban sin guardar - un solo
	-- boton que manda TODO junto en un unico updateNode evita ese riesgo.
	self.applyAllBtn = createBtn(pad, y, contentW, T("IGUI_GS_ApplyAllChanges"), scroll, function()
		if not self.node then return end
		local name = self.nameEntry and self.nameEntry:getText() or ""
		local notes = self.notesEntry and self.notesEntry:getText() or ""
		local n = tonumber(self.priorityEntry and self.priorityEntry:getText() or "")
		self._editName = name
		self._editNotes = notes
		GlobalStorageSiK.CompatMods.pushContainerLabelText(self.node, getSpecificPlayer(0), notes)
		local opts = { displayName = name, notes = notes }
		if n then
			n = math.floor(n + 0.5)
			if n < 1 then n = 1 elseif n > 100 then n = 100 end
			self._editPriority = n
			self.priorityEntry:setText(tostring(n))
			opts.priority = n
		end
		self:requestNodeUpdate(opts)
		self:syncTitleFromName()
	end)
	UI.Controls.setTooltip(self.applyAllBtn, T("IGUI_GS_ApplyAllChangesTooltip"))
	UI.Scroll.addChild(scroll, self.applyAllBtn)
	y = y + CONTROL_METRICS.buttonHeight + 12

	-- ── Botón acción: excluir/incluir (dev26, ronda 2 - ver §4.5 del plan) ──
	-- "Desactivar contenedor" se retira por completo: enabled=false sin
	-- exclusion se revertia solo con el siguiente rescan de zona (ver
	-- GS_ZoneRefresh.lua:105-108, existing.enabled=true si membership no es
	-- "excluded") - era un boton que aparentaba funcionar pero no persistia
	-- nada. Excluir sigue siendo la unica forma real de sacar un contenedor
	-- de la red, ahora con confirmacion explicita (solo al excluir, nunca al
	-- volver a incluir).
	local membLabel = isExcluded and T("IGUI_GS_NodeBtnInclude") or T("IGUI_GS_NodeBtnExclude")
	-- Rojo (mismo PALETTE.statusDanger que el resto del terminal) SOLO
	-- cuando la accion es excluir - al volver a incluir el boton se queda en
	-- su estilo normal, no tiene sentido pintar de peligro una accion segura.
	local membActiveColor = (not isExcluded) and PALETTE.statusDanger or nil
	self.membBtn = createProductButton(pad, y, contentW,
		CONTROL_METRICS.buttonHeight, membLabel, scroll, function()
		if self.node and self.node.membership == "excluded" then
			self:requestNodeUpdate({ enabled = true, membership = "active" })
		else
			self:confirmExclude()
		end
	end, membActiveColor, true)
	UI.Controls.setTooltip(self.membBtn, T("IGUI_GS_NodeExcludeTooltip"))
	UI.Scroll.addChild(scroll, self.membBtn)
	y = y + CONTROL_METRICS.buttonHeight + 6

	self.removeBtn = createProductButton(pad, y, contentW,
		CONTROL_METRICS.buttonHeight,
		T("IGUI_GS_NodeBtnRemove"), scroll, function()
			self:confirmRemoveFromNetwork()
		end, PALETTE.statusDanger, true)
	UI.Controls.setTooltip(self.removeBtn, T("IGUI_GS_NodeRemoveTooltip"))
	UI.Scroll.addChild(scroll, self.removeBtn)
	y = y + CONTROL_METRICS.buttonHeight + 6
	if node and node.offline == true then
		self.rebindBtn = createBtn(pad, y, contentW, T("IGUI_GS_NodeBtnRebind"), scroll, function()
			self:requestRebindProposal()
		end)
		UI.Controls.setTooltip(self.rebindBtn, T("IGUI_GS_NodeRebindTooltip"))
		UI.Scroll.addChild(scroll, self.rebindBtn)
		y = y + CONTROL_METRICS.buttonHeight + 6
		if self._rebindCandidates and #self._rebindCandidates > 0 then
			local chooseLbl = createSectionLabel(pad, y,
				T("IGUI_GS_NodeRebindChooseTarget"))
			UI.Scroll.addChild(scroll, chooseLbl)
			y = y + FONT_HGT_SMALL + 4
			for i = 1, #self._rebindCandidates do
				local candidate = self._rebindCandidates[i]
				local label = T("IGUI_GS_NodeRebindCandidate", candidate.name or "?",
					candidate.x or "?", candidate.y or "?", candidate.z or "?")
				local choiceBtn = createBtn(pad, y, contentW, label, scroll, function()
					self:requestRebindProposal(candidate.nodeId)
				end)
				UI.Controls.setTooltip(choiceBtn, T("IGUI_GS_NodeRebindCandidateTooltip"))
				UI.Scroll.addChild(scroll, choiceBtn)
				y = y + CONTROL_METRICS.buttonHeight + 4
			end
		end
	end
	y = y + 6

	-- ── Contenido del contenedor ──────────────────────────────────────────
	local contentsTitle = createSectionLabel(pad, y, T("IGUI_GS_NodeContentsTitle"))
	self.contentsTitleLbl = contentsTitle
	UI.Scroll.addChild(scroll, contentsTitle)
	y = y + FONT_HGT_SMALL + 8

	self._contentsStartY = y
	self._contentsFingerprint = nil
	self._formBuilt = true
	self:syncTitleFromName()
	self:refreshRulesSummary()
	for _, op in ipairs(RULE_OPS) do
		self:rebuildRuleChips(op)
	end
	self:refreshContents()
end

--- Construye una seccion de reglas (OR/AND/NOT): tarjeta de fondo coloreada
--- por operador (createSectionCard, mismo patron "fondo decorativo + hijos
--- independientes en coordenadas absolutas del scroll" que el resto del
--- terminal - ver GS_TerminalUI_NetworkZones.lua), titulo en el mismo color,
--- panel de chips (altura calculada desde node.rules) y boton "+ Anadir
--- regla <op>".
---@param scroll table
---@param pad number
---@param contentW number
---@param y number
---@param op string "OR"|"AND"|"NOT"
---@return number newY
function GS_NodeEditorUI:buildRuleSection(scroll, pad, contentW, y, op)
	local rules = (self.node and self.node.rules) or {}
	local count = 0
	for i = 1, #rules do
		if rules[i].op == op then count = count + 1 end
	end
	local CHIP_H, CHIP_PAD = FONT_HGT_SMALL + 8, 3
	local chipsH = (count == 0)
		and (CHIP_PAD + FONT_HGT_SMALL + CHIP_PAD * 2)
		or  (CHIP_PAD + count * (CHIP_H + CHIP_PAD) + CHIP_PAD)

	local cardPad = 8
	local cardX = pad
	local cardW = contentW
	local cardTop = y
	local cy = y + cardPad
	local cx = pad + cardPad + 4
	local color = RULE_OP_COLOR[op]

	-- Tarjeta de fondo SiK.UI insertada
	-- ANTES que su contenido (mismo patron que GS_TerminalUI_NetworkZones.lua:
	-- card primero con alto provisional, setBounds al final con el
	-- alto real) - si se insertara despues, taparia el titulo/chips/boton en
	-- vez de quedar detras.
	local card = createSectionCard(scroll, cardX, cardTop, cardW, 10, color)
	UI.Scroll.addChild(scroll, card)
	self._ruleCards = self._ruleCards or {}
	self._ruleCards[op] = card

	local titleLbl = createText(nil, cx, cy, cardW - cardPad * 2 - 4,
		T(RULE_OP_TITLE_KEY[op]), color)
	UI.Scroll.addChild(scroll, titleLbl)
	cy = cy + FONT_HGT_SMALL + 6

	local host = createHost(nil, cx, cy, cardW - cardPad * 2 - 4, chipsH)
	UI.Scroll.addChild(scroll, host)
	self._ruleChipsHosts = self._ruleChipsHosts or {}
	self._ruleChipsHosts[op] = host
	cy = cy + chipsH + 6

	local addBtn = createBtn(cx, cy, cardW - cardPad * 2 - 4, T(RULE_OP_ADD_KEY[op]), scroll, function()
		if not self.node then return end
		local scopeRules = {}
		local nodes = self.terminal and self.terminal.terminalState and self.terminal.terminalState.nodes or {}
		for i = 1, #nodes do
			local sibling = nodes[i]
			if sibling.id ~= self.node.id and sibling.zoneId == self.node.zoneId then
				for j = 1, #(sibling.rules or {}) do
					scopeRules[#scopeRules + 1] = sibling.rules[j]
				end
			end
		end
		GlobalStorageSiK.FilterEditor.show({ kind = "node", id = self.node.id, rules = self.node.rules, scopeRules = scopeRules }, op, function()
			self:rebuildForm()
		end)
	end)
	UI.Scroll.addChild(scroll, addBtn)
	self._ruleAddBtns = self._ruleAddBtns or {}
	self._ruleAddBtns[op] = addBtn
	cy = cy + CONTROL_METRICS.buttonHeight + cardPad

	UI.Layout.apply(card, { x = cardX, y = cardTop,
		w = cardW, h = cy - cardTop })
	y = cy + 8
	return y
end

--- Recalcula la frase-resumen del protocolo dentro de rulesSummaryHost. El
--- host ya tiene la altura correcta calculada en ensureForm (regla 7,
--- CLAUDE.md: texto de longitud variable, nunca ISLabel de una sola linea).
function GS_NodeEditorUI:refreshRulesSummary()
	local host = self.rulesSummaryHost
	if not host then return end
	for i = #(host.childrenInOrder or {}), 1, -1 do
		local ch = host.childrenInOrder[i]
		host:removeChild(ch)
		if ch.removeFromUIManager then ch:removeFromUIManager() end
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
			local label = describeCondition(rule.condition)
			label = UI.Controls.truncateText(label, labelMaxW, UIFont.Small)
			local labelColor = GlobalStorageSiK.RulesUI.conditionColor(
				rule.condition, PALETTE.textPrimary)
			createText(host, 4, cy + 2, labelMaxW, label, labelColor)

			local capturedIdx = realIdx
			local removeBtn = createProductButton(
				hostW - removeBtnW - 2, cy, removeBtnW, CHIP_H,
				removeText, host,
				function()
					if not self.node then return end
					GlobalStorageSiK.NetClient.sendCommand("updateNode", { nodeId = self.node.id, removeRuleIndex = capturedIdx })
					table.remove(self.node.rules, capturedIdx)
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
	self:updateScrollHeight()
end

--- Guarda estado de edición, destruye y reconstruye el formulario.
function GS_NodeEditorUI:rebuildForm()
	if not self.editorScroll then return end
	-- Preservar estado del formulario
	if self.nameEntry  then self._editName  = self.nameEntry:getText()  end
	if self.notesEntry then self._editNotes = self.notesEntry:getText() end
	if self.priorityEntry then
		local n = tonumber(self.priorityEntry:getText())
		if n then self._editPriority = n end
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
	-- El numero de reglas puede haber cambiado desde el ultimo build (ver
	-- _ruleCountAtBuild en ensureForm) - las tarjetas/hosts de
	-- OR/AND/NOT solo se dimensionan de verdad en un build completo
	-- (buildRuleSection -> setBounds); si solo repintasemos los
	-- chips aqui (rebuildRuleChips) con un conteo distinto al que se uso
	-- para dimensionar, el chip nuevo (o el hueco de uno quitado) queda
	-- fuera de la tarjeta, tapado por/separado del boton "+ Anadir regla".
	if self._ruleCountAtBuild ~= nil and #(self.node.rules or {}) ~= self._ruleCountAtBuild then
		self:rebuildForm()
		return
	end
	local excluded = self.node.membership == "excluded"
	if self.membBtn then
		local label = excluded and T("IGUI_GS_NodeBtnInclude") or T("IGUI_GS_NodeBtnExclude")
		if self.membBtn.setText then self.membBtn:setText(label)
		elseif self.membBtn.setTitle then self.membBtn:setTitle(label) end
		local color = (not excluded) and UI.Theme.color("danger")
			or UI.Theme.color("surfaceAlt")
		self.membBtn.backgroundColor = { r = color[1], g = color[2],
			b = color[3], a = color[4] or 0.92 }
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
	local contentW = math.max(1, innerW - 16)

	self:ensureContentsHost()
	if not self.contentsHost then
		return
	end

	self.contentsHost:setX(8)
	self.contentsHost:setY(self._contentsStartY or 0)
	self.contentsHost:setWidth(contentW)
	self:clearContentsHost()
	self:syncFormButtons()

	local yEnd = GlobalStorageSiK.TerminalConfig.renderNodeContentsBlock(
		self.contentsHost, self.terminal, self.node, 0, 8, contentW, { plainHost = true }
	)

	self.contentsHost:setHeight(math.max(40, yEnd + 4))
	self._lastContentBottom = (self._contentsStartY or 0) + self.contentsHost:getHeight() + 8
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
	UI.Scroll.setContentHeight(self.editorScroll, bottom)
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
	local pad = 8
	local innerW = UI.Scroll.contentWidth(scroll)
	local contentW = math.max(1, innerW - pad * 2)
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
	-- Segunda pasada inicial: ensureForm puede haber activado overflow.
	self:layoutForm()
	self:syncTitleFromName()
	if sameNode then
		self._contentsFingerprint = nil
		self:refreshContents()
	end
	self:requestNodeContents(node.id)
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
	ui:addToUIManager()
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
	if ui._sugCardMissingData and ui.rebuildForm then
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
			ui._editName     = updated.displayName or updated.name or ""
			ui._editNotes    = updated.notes or ""
			ui._editPriority = updated.priority or 50
			ui:syncTitleFromName()
			ui:syncFormButtons()
			if GlobalStorageSiK.NodeNaming and GlobalStorageSiK.NodeNaming.applyToNode then
				GlobalStorageSiK.NodeNaming.applyToNode(updated)
			end
			return
		end
	end
end

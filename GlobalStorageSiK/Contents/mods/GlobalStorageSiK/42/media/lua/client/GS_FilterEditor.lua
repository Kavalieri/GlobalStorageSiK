--[[
	GlobalStorageSiK - Editor de filtro personalizado de contenedor
	Descripción: Modal para construir UN filtro (nombre/peso/tag/ítem exacto)
	y añadirlo al nodo que abrió el editor. Ver GS_NodeFilters.lua (lógica
	compartida de coincidencia) y GS_TerminalUI_NodeEditor.lua (quien lo abre).
]]

require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalUI_Config"
require "GS_RulesUI"
local UI = require "GS_UI_Framework"
local Confirmation = require "GS_Confirmation"

GlobalStorageSiK.FilterEditor = {}
GlobalStorageSiK.FilterEditor.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local CONTROL_METRICS = UI.Controls.metrics("compact")
local ENTRY_H = CONTROL_METRICS.inputHeight
local BTN_H = CONTROL_METRICS.buttonHeight
local RESULT_ROW_H = FONT_HGT_SMALL + 6
local MAX_RESULTS = 12
local BLOCK_GAP = 8

--- Color de acento por operador (mismo trio que GS_TerminalUI_NodeEditor.lua
--- y GS_TerminalUI_ZoneEditor.lua) - se usa en el borde superior del modal
--- para reforzar visualmente que operador se esta configurando.
local RULE_OP_TONE = { OR = "info", AND = "warning", NOT = "danger" }

local function addCopy(parent, x, y, width, text, tone, theme)
	local control = UI.Controls.copyText(parent, {
		x = x, y = y, w = width, text = text, font = UIFont.Small,
		lineGap = 0, tone = tone or "textMuted", theme = theme,
		playerNum = parent.playerNum,
	})
	if control.setMouseTransparent then control:setMouseTransparent(true) end
	return control
end

local function addCombo(parent, x, y, width, onChange)
	local combo = UI.Controls.combo(parent, {
		x = x, y = y, w = width, h = ENTRY_H, items = {},
		playerNum = parent.playerNum, onChange = onChange,
	})
	UI.Controls.styleCombo(combo)
	return combo
end

local function addField(parent, x, y, width, numeric, onChange)
	local field = UI.Controls.field(parent, {
		x = x, y = y, w = width, h = ENTRY_H, text = "",
		numeric = numeric == true, playerNum = parent.playerNum,
		onChange = onChange,
	})
	UI.Controls.styleField(field)
	return field
end

GS_FilterEditorUI = UI.Window.derive("GS_FilterEditorUI")

local NAME_MODES = { "contains", "exact", "startsWith", "endsWith" }
local NAME_MODE_LABELS = {
	contains = "IGUI_GS_FilterModeContains",
	exact = "IGUI_GS_FilterModeExact",
	startsWith = "IGUI_GS_FilterModeStartsWith",
	endsWith = "IGUI_GS_FilterModeEndsWith",
}
local WEIGHT_MODES = { "gt", "lt", "eq", "gte", "lte", "between" }
local WEIGHT_MODE_LABELS = {
	gt = "IGUI_GS_FilterModeGt",
	lt = "IGUI_GS_FilterModeLt",
	eq = "IGUI_GS_FilterModeEq",
	gte = "IGUI_GS_FilterModeGte",
	lte = "IGUI_GS_FilterModeLte",
	between = "IGUI_GS_FilterModeBetween",
}
local FILTER_TYPES = { "category", "name", "weight", "tag", "item" }
local FILTER_TYPE_LABELS = {
	category = "IGUI_GS_FilterTypeCategory",
	name = "IGUI_GS_FilterTypeName",
	weight = "IGUI_GS_FilterTypeWeight",
	tag = "IGUI_GS_FilterTypeTag",
	item = "IGUI_GS_FilterTypeItem",
}

function GS_FilterEditorUI:new(x, y, width, height)
	return UI.Window.newInstance(self, x, y, width, height)
end

--- Índice de todos los ítems del juego (fullType -> nombre visible),
--- construido UNA vez y reutilizado (evita recorrer ScriptManager en cada
--- pulsación de tecla - eso sí daría lag con miles de ítems).
local allItemsCache = nil
local function buildAllItemsCache()
	if allItemsCache then
		return allItemsCache
	end
	allItemsCache = {}
	local sm = getScriptManager and getScriptManager()
	if not sm or not sm.getAllItems then
		return allItemsCache
	end
	local ok, items = pcall(function() return sm:getAllItems() end)
	if not ok or not items then
		return allItemsCache
	end
	for i = 0, items:size() - 1 do
		local script = items:get(i)
		local ok2, fullType = pcall(function() return script:getFullName() end)
		if ok2 and fullType then
			local name = fullType
			local okName, dispName = pcall(function() return script:getDisplayName() end)
			if okName and dispName and dispName ~= "" then
				name = dispName
			end
			allItemsCache[#allItemsCache + 1] = { fullType = fullType, name = name, nameLower = string.lower(name) }
		end
	end
	return allItemsCache
end

---@param query string
---@return table[] results { fullType, name }
local function searchItems(query)
	local results = {}
	query = string.lower(query or "")
	if query == "" then
		return results
	end
	local all = buildAllItemsCache()
	for i = 1, #all do
		if all[i].nameLower:find(query, 1, true) then
			results[#results + 1] = all[i]
			if #results >= MAX_RESULTS then
				break
			end
		end
	end
	return results
end

function GS_FilterEditorUI:initialise()
	UI.Window.callBase(self, "initialise")
	self.backgroundColor = { r = 0.08, g = 0.09, b = 0.11, a = 0.96 }
	self.borderColor = { r = 0.35, g = 0.38, b = 0.42, a = 0.95 }
	self.operator = self.operator or "OR"
	self.filterType = self.filterType or "category"
	self.selectedItem = nil
        UI.Modal.apply(self, {
                kind = "task", profile = "editor", resizable = true,
                onReflow = function()
                        if self._filterLayoutReady then self:reflowContent() end
                end,
                title = T("IGUI_GS_FilterEditorTitle") .. " - "
                        .. T("IGUI_GS_FilterEditorOperatorLabel", self.operator),
                onClose = function() GlobalStorageSiK.FilterEditor.instance = nil end,
        })
        self._filterLayoutReady = true
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

function GS_FilterEditorUI:destroy()
	GlobalStorageSiK.FilterEditor.instance = nil
	if UI.Modal and UI.Modal.close then
		UI.Modal.close(self, "product")
	else
		self:dispose()
	end
end

local function clearContent(panel)
	for i = #(panel._contentWidgets or {}), 1, -1 do
		local child = panel._contentWidgets[i]
		if child and child.dispose then child:dispose()
		elseif child then
			panel:removeChild(child)
			if child.removeFromUIManager then child:removeFromUIManager() end
		end
	end
	panel._contentWidgets = {}
end

local function own(panel, child)
	panel._contentWidgets[#panel._contentWidgets + 1] = child
	return child
end

function GS_FilterEditorUI:captureDraft()
	self._drafts = self._drafts or {}
	local draft = self._drafts[self.filterType] or {}
	if self.filterType == "category" then
		draft.main = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catMainCombo)
		draft.sub = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catSubCombo)
		draft.leaf = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catLeafCombo)
	elseif self.filterType == "name" then
		draft.mode = self.nameModeCombo and self.nameModeCombo.selected or draft.mode
		draft.value = self.nameEntry and self.nameEntry:getText() or draft.value or ""
	elseif self.filterType == "weight" then
		draft.mode = self.weightModeCombo and self.weightModeCombo.selected or draft.mode
		draft.value = self.weightEntry and self.weightEntry:getText() or draft.value or ""
		draft.value2 = self.weightEntry2 and self.weightEntry2:getText() or draft.value2 or ""
	elseif self.filterType == "tag" then
		draft.value = self.tagEntry and self.tagEntry:getText() or draft.value or ""
	elseif self.filterType == "item" then
		draft.query = self.itemSearchEntry and self.itemSearchEntry:getText() or draft.query or ""
		draft.selected = self.selectedItem
	end
	self._drafts[self.filterType] = draft
end

--- Reconstruye el cuerpo del formulario según self.filterType.
function GS_FilterEditorUI:buildLayout()
	if self._layoutBusy then return end
	self._layoutBusy = true
	self:captureDraft()
	clearContent(self)

	local host, content = layoutHost(self)
	local operatorTone = RULE_OP_TONE[self.operator] or RULE_OP_TONE.OR
	self._filterLayoutWidth = content.w
	local filterBlock = own(self, UI.Block.create({
		parent = host, x = 0, y = 0, w = content.w,
		title = T("IGUI_GS_FilterPathTitle"),
		tooltip = T("IGUI_GS_EditorRulesHint"), accentTone = operatorTone,
		playerNum = self.playerNum,
	}))
	self.filterBlock = filterBlock
	local column = filterBlock:beginColumn()

	local typeLabel = addCopy(column.parent, 0, 0, column.width,
		T("IGUI_GS_FilterTypeLabel"))
	column:label(typeLabel, typeLabel.height, 2)
	self.typeCombo = addCombo(column.parent, 0, 0, column.width, function()
		self:captureDraft()
		local idx = self.typeCombo.selected or 1
		self.filterType = FILTER_TYPES[idx] or "name"
		self:buildLayout()
	end)
	for i = 1, #FILTER_TYPES do
		self.typeCombo:addOption(T(FILTER_TYPE_LABELS[FILTER_TYPES[i]]))
	end
	self.typeCombo.selected = 1
	for i = 1, #FILTER_TYPES do
		if FILTER_TYPES[i] == self.filterType then self.typeCombo.selected = i end
	end
	column:block(self.typeCombo, ENTRY_H)

	if self.filterType == "category" then
		self:buildCategoryFields(column)
	elseif self.filterType == "name" then
		self:buildNameFields(column)
	elseif self.filterType == "weight" then
		self:buildWeightFields(column)
	elseif self.filterType == "tag" then
		self:buildTagFields(column)
	elseif self.filterType == "item" then
		self:buildItemFields(column)
	end
	column:finish()

	local actions = own(self, UI.Block.create({
		parent = host, x = 0, y = filterBlock.y + filterBlock.h + BLOCK_GAP,
		w = content.w, title = T("IGUI_GS_PermColActions"),
		tooltip = T("IGUI_GS_PermColActions"), playerNum = self.playerNum,
	}))
	self.actionsBlock = actions
	local actionColumn = actions:beginColumn()
	self.addBtn = UI.Controls.button(actionColumn.parent, {
		x = 0, y = 0, w = actionColumn.width, h = BTN_H,
		text = T("IGUI_GS_FilterAddBtn"), fullWidth = true,
		onClick = function() self:onAddClicked() end,
	})
	actionColumn:block(self.addBtn, BTN_H)
	actionColumn:finish()

	local contentHeight = actions.y + actions.h
	if not self._initialLayoutFitted then
		self._initialLayoutFitted = true
		UI.Modal.fitContent(self, contentHeight, { center = true })
	elseif self.contentBlock then
		self.contentBlock:setContentHeight(contentHeight)
	end
	self._layoutBusy = false
	self:reflowContent()
end

--- Width changes rebuild only the active local form; draft values survive.
--- Height changes update the shared viewport without shrinking the user window.
function GS_FilterEditorUI:reflowContent()
	if self._layoutBusy then return end
	local _, content = layoutHost(self)
	if content.w ~= self._filterLayoutWidth then self:buildLayout() end
end

--- Categoria > Subcategoria > Sub-subcategoria en cascada VERTICAL (a
--- diferencia de GS_TerminalUI_NodeEditor.lua, que las pone en 3 columnas).
--- Reutiliza los mismos
--- helpers compartidos de GS_TerminalUI_Config.lua (mismo catalogo completo,
--- no solo lo que la red tiene ahora).
function GS_FilterEditorUI:buildCategoryFields(column)
	local draft = (self._drafts and self._drafts.category) or {}
	local mainLabel = addCopy(column.parent, 0, 0, column.width,
		T("IGUI_GS_NodeCategoryMainLabel"))
	column:label(mainLabel, mainLabel.height, 2)

	self.catMainCombo = addCombo(column.parent, 0, 0, column.width, function()
		local mainKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catMainCombo)
		GlobalStorageSiK.TerminalConfig.fillSubCategoryCombo(self.catSubCombo, mainKey, "", {})
		GlobalStorageSiK.TerminalConfig.fillLeafCategoryCombo(self.catLeafCombo, mainKey, "", "")
	end)
	-- El catálogo de reglas es de autoría, no un inventario de reservas. Dos
	-- destinos pueden aceptar exactamente la misma ruta; prioridad y afinidad
	-- resuelven el destino cuando se deposite el objeto.
	GlobalStorageSiK.TerminalConfig.fillMainCategoryCombo(self.catMainCombo, {}, draft.main)
	column:block(self.catMainCombo, ENTRY_H)

	local subLabel = addCopy(column.parent, 0, 0, column.width,
		T("IGUI_GS_NodeCategorySubLabel"))
	column:label(subLabel, subLabel.height, 2)

	self.catSubCombo = addCombo(column.parent, 0, 0, column.width, function()
		local mainKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catMainCombo)
		local subKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catSubCombo)
		GlobalStorageSiK.TerminalConfig.fillLeafCategoryCombo(self.catLeafCombo, mainKey, subKey, "")
	end)
	GlobalStorageSiK.TerminalConfig.fillSubCategoryCombo(self.catSubCombo, draft.main or "", draft.sub, {})
	column:block(self.catSubCombo, ENTRY_H)

	local leafLabel = addCopy(column.parent, 0, 0, column.width,
		T("IGUI_GS_NodeCategoryLeafLabel"))
	column:label(leafLabel, leafLabel.height, 2)

	self.catLeafCombo = addCombo(column.parent, 0, 0, column.width)
	GlobalStorageSiK.TerminalConfig.fillLeafCategoryCombo(self.catLeafCombo,
		draft.main or "", draft.sub or "", draft.leaf)
	column:block(self.catLeafCombo, ENTRY_H)
end

function GS_FilterEditorUI:buildNameFields(column)
	local draft = (self._drafts and self._drafts.name) or {}
	local modeLabel = addCopy(column.parent, 0, 0, column.width, T("IGUI_GS_FilterModeLabel"))
	column:label(modeLabel, modeLabel.height, 2)

	self.nameModeCombo = addCombo(column.parent, 0, 0, column.width)
	for i = 1, #NAME_MODES do
		self.nameModeCombo:addOption(T(NAME_MODE_LABELS[NAME_MODES[i]]))
	end
	self.nameModeCombo.selected = draft.mode or 1
	column:block(self.nameModeCombo, ENTRY_H)

	local valueLabel = addCopy(column.parent, 0, 0, column.width, T("IGUI_GS_FilterValueLabel"))
	column:label(valueLabel, valueLabel.height, 2)

	self.nameEntry = addField(column.parent, 0, 0, column.width)
	self.nameEntry:setText(draft.value or "")
	column:block(self.nameEntry, ENTRY_H)
end

function GS_FilterEditorUI:buildWeightFields(column)
	local draft = (self._drafts and self._drafts.weight) or {}
	local modeLabel = addCopy(column.parent, 0, 0, column.width, T("IGUI_GS_FilterModeLabel"))
	column:label(modeLabel, modeLabel.height, 2)

	self.weightModeCombo = addCombo(column.parent, 0, 0, column.width, function()
		self:captureDraft()
		self:buildLayout()
	end)
	for i = 1, #WEIGHT_MODES do
		self.weightModeCombo:addOption(T(WEIGHT_MODE_LABELS[WEIGHT_MODES[i]]))
	end
	self.weightModeCombo.selected = draft.mode or 1
	column:block(self.weightModeCombo, ENTRY_H)

	local idx = self.weightModeCombo.selected or 1
	local mode = WEIGHT_MODES[idx] or "eq"

	local valueLabel = addCopy(column.parent, 0, 0, column.width,
		T("IGUI_GS_FilterWeightValueLabel"))
	column:label(valueLabel, valueLabel.height, 2)

	if mode == "between" then
		self.weightEntry = addField(column.parent, 0, 0, 1, true)
		self.weightEntry2 = addField(column.parent, 0, 0, 1, true)
		self.weightEntry:setText(draft.value or "")
		self.weightEntry2:setText(draft.value2 or "")
		column:row(ENTRY_H, { { widget = self.weightEntry }, { widget = self.weightEntry2 } })
	else
		self.weightEntry = addField(column.parent, 0, 0, column.width, true)
		self.weightEntry:setText(draft.value or "")
		self.weightEntry2 = nil
		column:block(self.weightEntry, ENTRY_H)
	end
end

function GS_FilterEditorUI:buildTagFields(column)
	local draft = (self._drafts and self._drafts.tag) or {}
	local hint = addCopy(column.parent, 0, 0, column.width, T("IGUI_GS_FilterTagHint"), "textMuted")
	column:label(hint, hint.height)
	self.tagEntry = addField(column.parent, 0, 0, column.width)
	self.tagEntry:setText(draft.value or "")
	column:block(self.tagEntry, ENTRY_H)
end

function GS_FilterEditorUI:buildItemFields(column)
	local draft = (self._drafts and self._drafts.item) or {}
	local searchLabel = addCopy(column.parent, 0, 0, column.width,
		T("IGUI_GS_FilterItemSearchLabel"))
	column:label(searchLabel, searchLabel.height, 2)

	self.itemSearchEntry = addField(column.parent, 0, 0, column.width, false, function()
		self:refreshItemResults()
	end)
	self.itemSearchEntry:setText(draft.query or "")
	column:block(self.itemSearchEntry, ENTRY_H)
	self.selectedItem = draft.selected

	if self.selectedItem then
		local selected = addCopy(column.parent, 0, 0, column.width,
			T("IGUI_GS_FilterItemSelected", self.selectedItem.name), "success")
		column:label(selected, selected.height)
	end

	self.itemResultsHost = UI.Controls.panel(column.parent, {
		x = 0, y = 0, w = column.width, h = 0, drawBackground = false,
		backgroundColor = { r = 0, g = 0, b = 0, a = 0 },
		borderColor = { r = 0, g = 0, b = 0, a = 0 },
		controlId = "filterItemResultsHost", playerNum = self.playerNum,
	})
	self.itemResultsHost:setHeight(0)
	self._itemResultsBaseHeight = 0
	column:block(self.itemResultsHost, 0, 0)
	column:space(self:refreshItemResults(true))
end

--- Repinta la lista de resultados de búsqueda de ítem (sin reconstruir todo el formulario).
---@return number newY
function GS_FilterEditorUI:refreshItemResults(initial)
	if not self.itemResultsHost then
		return 0
	end
	for i = #(self.itemResultsHost.childrenInOrder or {}), 1, -1 do
		local child = self.itemResultsHost.childrenInOrder[i]
		if child.dispose then child:dispose()
		else
			self.itemResultsHost:removeChild(child)
			if child.removeFromUIManager then child:removeFromUIManager() end
		end
	end
	local query = self.itemSearchEntry and self.itemSearchEntry:getText() or ""
	local searched = searchItems(query)
	-- Una regla de ítem exacto tampoco reserva el ítem para un único destino.
	-- Mostrar todos los resultados evita que el editor contradiga el routing.
	local results = searched
	local innerW = self.itemResultsHost.width
	local ry = 0
	for i = 1, #results do
		local r = results[i]
		UI.Controls.button(self.itemResultsHost, {
			x = 0, y = ry, w = innerW, h = RESULT_ROW_H, text = r.name,
			fullWidth = true,
			onClick = function()
				self.selectedItem = { fullType = r.fullType, name = r.name }
				self:buildLayout()
			end,
		})
		ry = ry + RESULT_ROW_H + 3
	end
	self.itemResultsHost:setHeight(math.max(0, ry))
	local previous = self._itemResultsBaseHeight or 0
	self._itemResultsBaseHeight = ry
	if not initial and self.filterBlock and self.actionsBlock and ry ~= previous then
		self.filterBlock:setBounds(self.filterBlock.x, self.filterBlock.y,
			self.filterBlock.w, self.filterBlock.h + ry - previous)
		self.actionsBlock:setBounds(self.actionsBlock.x,
			self.filterBlock.y + self.filterBlock.h + BLOCK_GAP,
			self.actionsBlock.w, self.actionsBlock.h)
		if self.contentBlock then
			self.contentBlock:setContentHeight(self.actionsBlock.y + self.actionsBlock.h)
		end
		self:reflowContent()
	end
	return ry
end

function GS_FilterEditorUI:onAddClicked()
	if not self.target then return end
	local filter = nil

	if self.filterType == "category" then
		local mainKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catMainCombo)
		local subKey  = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catSubCombo)
		local leafKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catLeafCombo)
		-- Mismo criterio que GS_TerminalUI_NodeEditor.lua:catApplyBtn: se
		-- guarda SIEMPRE la clave del nivel MAS ESPECIFICO elegido.
		local key = (leafKey ~= "" and leafKey) or (subKey ~= "" and subKey) or (mainKey ~= "" and mainKey) or nil
		if not key then return end
		filter = { type = "category", value = key, nativePath = key }

	elseif self.filterType == "name" then
		local val = self.nameEntry and self.nameEntry:getText() or ""
		if val == "" then return end
		local idx = self.nameModeCombo and self.nameModeCombo.selected or 1
		filter = { type = "name", mode = NAME_MODES[idx] or "contains", value = val }

	elseif self.filterType == "weight" then
		local idx = self.weightModeCombo and self.weightModeCombo.selected or 1
		local mode = WEIGHT_MODES[idx] or "eq"
		local v1 = tonumber(self.weightEntry and self.weightEntry:getText())
		if not v1 then return end
		filter = { type = "weight", mode = mode, value = v1 }
		if mode == "between" then
			local v2 = tonumber(self.weightEntry2 and self.weightEntry2:getText())
			if not v2 then return end
			filter.value2 = v2
		end

	elseif self.filterType == "tag" then
		local val = self.tagEntry and self.tagEntry:getText() or ""
		if val == "" then return end
		filter = { type = "tag", value = val }

	elseif self.filterType == "item" then
		if not self.selectedItem then return end
		filter = { type = "item", itemType = self.selectedItem.fullType, itemDisplay = self.selectedItem.name }
	end

	if not filter then return end

	local newRule = { op = self.operator or "OR", condition = filter }
	-- Detector general de contradicciones (dev26, ronda 2 - ver
	-- Documentacion/GS_FilterRedesign_Plan.md §4.4-quinquies): si esta
	-- nueva regla neutraliza una ya guardada (un NOT contra un OR/AND que se
	-- solapa, o al reves), avisar ANTES de guardar en vez de aplicar en
	-- silencio - el jugador decide si de verdad quiere ese conflicto.
	local conflict = GlobalStorageSiK.RulesUI.detectContradiction(self.target.rules, newRule)
	local conflictContainerName = nil
	if not conflict and self.target.containerGroups then
		-- Version cruzada (§4.4-quinquies, "cambiar la categoria de zona
		-- deriva en cambio de contenedores que contiene"): solo se pasa
		-- containerGroups cuando target.kind == "zone" (ver
		-- GS_TerminalUI_ZoneEditor.lua) - una regla de zona nueva puede
		-- neutralizar una regla ya guardada de un contenedor de esa zona.
		conflictContainerName, conflict = GlobalStorageSiK.RulesUI.detectCrossLevelContradiction(newRule, self.target.containerGroups)
	end
	if conflict then
		self:confirmContradiction(conflict, newRule, conflictContainerName)
		return
	end
	self:sendAddRule(newRule)
end

--- Envia la regla ya validada (sin conflicto, o confirmado por el jugador).
---@param newRule table {op, condition}
function GS_FilterEditorUI:sendAddRule(newRule)
	if self.target.kind == "zone" then
		GlobalStorageSiK.NetClient.sendCommand("updateZoneRules", { zoneId = self.target.id, addRule = newRule })
	else
		GlobalStorageSiK.NetClient.sendCommand("updateNode", { nodeId = self.target.id, addRule = newRule })
	end
	if self.onAdded then
		self.onAdded()
	end
	self:destroy()
end

--- Confirmacion explicita antes de guardar una regla que contradice una ya
--- existente - nombra AMBAS reglas (ver §4.4-quinquies). Confirmar guarda de
--- todos modos; cancelar no manda nada y deja el editor abierto.
---@param conflict table regla existente en conflicto {op, condition}
---@param newRule table regla nueva {op, condition}
---@param conflictContainerName string|nil nombre del contenedor en conflicto (solo caso cruzado zona->contenedor)
function GS_FilterEditorUI:confirmContradiction(conflict, newRule, conflictContainerName)
	local existingLabel = GlobalStorageSiK.RulesUI.describeCondition(conflict.condition)
	local newLabel = GlobalStorageSiK.RulesUI.describeCondition(newRule.condition)
	local question, consequences
	if conflictContainerName then
		question = T("IGUI_GS_RuleContradictionCrossQuestion", conflictContainerName,
			conflict.op, existingLabel, newRule.op, newLabel)
		consequences = T("IGUI_GS_RuleContradictionCrossConsequences", conflictContainerName,
			conflict.op, existingLabel, newRule.op, newLabel)
	else
		question = T("IGUI_GS_RuleContradictionQuestion", conflict.op, existingLabel, newRule.op, newLabel)
		consequences = T("IGUI_GS_RuleContradictionConsequences", conflict.op, existingLabel, newRule.op, newLabel)
	end
	Confirmation.show({
		owner = self,
		title = T("IGUI_GS_FilterEditorTitle"),
		question = question,
		consequences = consequences,
		onAccept = function() self:sendAddRule(newRule) end,
	})
end

--- Abre el editor de regla (motor AND/OR/NOT, dev26) para un contenedor o
--- una zona.
---@param target table { kind="node"|"zone", id=string, rules=table|nil } - rules = lista actual del propietario, para el detector de contradicciones
---@param operator string "OR"|"AND"|"NOT" - operador con el que se combinara la regla creada
---@param onAdded function|nil callback tras enviar la regla al servidor
---@param parentModal table|nil editor de zona/contenedor que conserva el foco y la capa
function GlobalStorageSiK.FilterEditor.show(target, operator, onAdded, parentModal)
	if not target or not target.id then return end
	if GlobalStorageSiK.FilterEditor.instance then
		GlobalStorageSiK.FilterEditor.instance:destroy()
	end
	-- Mismo ancho que los editores de contenedor/zona (dev26 ronda 4quinquies,
	-- pedido explicito: el titulo largo con el operador - "Anadir regla
	-- personalizada - Operador: NOT" - se salia del modal de 460px, tapado
	-- por el boton de cerrar). Solo el ANCHO se comparte con
	-- resolveEditorWindowSize(); el alto sigue calculandose del contenido
	-- real al abrir; despues se conserva el tamano elegido por el jugador.
	local panelW = UI.Window.resolveBounds({ profile = "editor" }).w
	local ui = GS_FilterEditorUI:new(0, 0, panelW, 200)
	ui.playerNum = parentModal and parentModal.playerNum or 0
	ui._sikModalOwner = parentModal
	ui.target = target
	ui.operator = operator or "OR"
	ui.onAdded = onAdded
	ui:initialise()
	if parentModal then UI.Modal.presentChild(parentModal, ui)
	else UI.Modal.show(ui) end
	GlobalStorageSiK.FilterEditor.instance = ui
end

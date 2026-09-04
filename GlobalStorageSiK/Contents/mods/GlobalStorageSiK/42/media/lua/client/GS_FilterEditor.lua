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

GlobalStorageSiK.FilterEditor = {}
GlobalStorageSiK.FilterEditor.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local CONTROL_METRICS = UI.Controls.metrics("compact")
local PALETTE = UI.Theme.palette()
local PAD = 14
local ENTRY_H = CONTROL_METRICS.inputHeight
local BTN_H = CONTROL_METRICS.buttonHeight
local RESULT_ROW_H = FONT_HGT_SMALL + 6
local MAX_RESULTS = 12

--- Color de acento por operador (mismo trio que GS_TerminalUI_NodeEditor.lua
--- y GS_TerminalUI_ZoneEditor.lua) - se usa en el borde superior del modal
--- para reforzar visualmente que operador se esta configurando.
local RULE_OP_COLOR = {
	OR  = PALETTE.ruleOr,
	AND = PALETTE.ruleAnd,
	NOT = PALETTE.ruleNot,
}

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
	self:setAlwaysOnTop(true)
	self.operator = self.operator or "OR"
	self.filterType = self.filterType or "category"
	self.selectedItem = nil
	UI.Modal.apply(self, {
		kind = "task", profile = "editor", padding = PAD, resizable = false,
		title = T("IGUI_GS_FilterEditorTitle") .. " - "
			.. T("IGUI_GS_FilterEditorOperatorLabel", self.operator),
		onClose = function() GlobalStorageSiK.FilterEditor.instance = nil end,
	})
	self:buildLayout()
end

function GS_FilterEditorUI:destroy()
	GlobalStorageSiK.FilterEditor.instance = nil
	if self.close then
		self:close("product")
	else
		self:setVisible(false)
		if self.removeFromUIManager then self:removeFromUIManager() end
	end
end

--- Reconstruye el cuerpo del formulario según self.filterType.
function GS_FilterEditorUI:buildLayout()
	for i = #(self.childrenInOrder or {}), 1, -1 do
		local child = self.childrenInOrder[i]
		if child ~= self.closeControl and child ~= self.titleControl
			and child ~= self.headerStatusControl then
			if child.dispose then child:dispose()
			else
				self:removeChild(child)
				if child.removeFromUIManager then child:removeFromUIManager() end
			end
		end
	end

	local content = self:contentRect()
	local pad = content.x
	local innerW = content.w
	local y = content.y
	-- La franja es un control del framework, no pintura local del producto.
	local operatorColor = RULE_OP_COLOR[self.operator] or RULE_OP_COLOR.OR
	self.operatorAccent = UI.Controls.separator(self, {
		x = 0, y = 0, w = self.width, h = 3,
		color = { r = operatorColor[1], g = operatorColor[2],
			b = operatorColor[3], a = operatorColor[4] or 1 },
		controlId = "filterOperatorAccent", playerNum = self.playerNum,
	})
	if self.operatorAccent.setMouseTransparent then
		self.operatorAccent:setMouseTransparent(true)
	end

	-- Tipo de filtro
	addCopy(self, pad, y, innerW, T("IGUI_GS_FilterTypeLabel"))
	y = y + FONT_HGT_SMALL + 2

	self.typeCombo = addCombo(self, pad, y, innerW, function()
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
	y = y + ENTRY_H + 10

	if self.filterType == "category" then
		y = self:buildCategoryFields(pad, innerW, y)
	elseif self.filterType == "name" then
		y = self:buildNameFields(pad, innerW, y)
	elseif self.filterType == "weight" then
		y = self:buildWeightFields(pad, innerW, y)
	elseif self.filterType == "tag" then
		y = self:buildTagFields(pad, innerW, y)
	elseif self.filterType == "item" then
		y = self:buildItemFields(pad, innerW, y)
	end

	y = y + 6
	self.addBtn = UI.Controls.button(self, {
		x = pad, y = y, w = innerW, h = BTN_H,
		text = T("IGUI_GS_FilterAddBtn"), fullWidth = true,
		onClick = function() self:onAddClicked() end,
	})
	y = y + BTN_H + pad

	UI.Modal.fitContent(self, y - content.y, { center = true })
end

--- Categoria > Subcategoria > Sub-subcategoria en cascada VERTICAL (a
--- diferencia de GS_TerminalUI_NodeEditor.lua, que las pone en 3 columnas).
--- Reutiliza los mismos
--- helpers compartidos de GS_TerminalUI_Config.lua (mismo catalogo completo,
--- no solo lo que la red tiene ahora).
function GS_FilterEditorUI:buildCategoryFields(pad, innerW, y)
	addCopy(self, pad, y, innerW, T("IGUI_GS_NodeCategoryMainLabel"))
	y = y + FONT_HGT_SMALL + 2

	self.catMainCombo = addCombo(self, pad, y, innerW, function()
		local mainKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catMainCombo)
		GlobalStorageSiK.TerminalConfig.fillSubCategoryCombo(self.catSubCombo, mainKey, "", {})
		GlobalStorageSiK.TerminalConfig.fillLeafCategoryCombo(self.catLeafCombo, mainKey, "", "")
	end)
	-- El catálogo de reglas es de autoría, no un inventario de reservas. Dos
	-- destinos pueden aceptar exactamente la misma ruta; prioridad y afinidad
	-- resuelven el destino cuando se deposite el objeto.
	GlobalStorageSiK.TerminalConfig.fillMainCategoryCombo(self.catMainCombo, {}, "")
	y = y + ENTRY_H + 8

	addCopy(self, pad, y, innerW, T("IGUI_GS_NodeCategorySubLabel"))
	y = y + FONT_HGT_SMALL + 2

	self.catSubCombo = addCombo(self, pad, y, innerW, function()
		local mainKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catMainCombo)
		local subKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catSubCombo)
		GlobalStorageSiK.TerminalConfig.fillLeafCategoryCombo(self.catLeafCombo, mainKey, subKey, "")
	end)
	GlobalStorageSiK.TerminalConfig.fillSubCategoryCombo(self.catSubCombo, "", "", {})
	y = y + ENTRY_H + 8

	addCopy(self, pad, y, innerW, T("IGUI_GS_NodeCategoryLeafLabel"))
	y = y + FONT_HGT_SMALL + 2

	self.catLeafCombo = addCombo(self, pad, y, innerW)
	GlobalStorageSiK.TerminalConfig.fillLeafCategoryCombo(self.catLeafCombo, "", "", "")
	y = y + ENTRY_H + 4
	return y
end

function GS_FilterEditorUI:buildNameFields(pad, innerW, y)
	addCopy(self, pad, y, innerW, T("IGUI_GS_FilterModeLabel"))
	y = y + FONT_HGT_SMALL + 2

	self.nameModeCombo = addCombo(self, pad, y, innerW)
	for i = 1, #NAME_MODES do
		self.nameModeCombo:addOption(T(NAME_MODE_LABELS[NAME_MODES[i]]))
	end
	self.nameModeCombo.selected = 1
	y = y + ENTRY_H + 8

	addCopy(self, pad, y, innerW, T("IGUI_GS_FilterValueLabel"))
	y = y + FONT_HGT_SMALL + 2

	self.nameEntry = addField(self, pad, y, innerW)
	y = y + ENTRY_H + 4
	return y
end

function GS_FilterEditorUI:buildWeightFields(pad, innerW, y)
	addCopy(self, pad, y, innerW, T("IGUI_GS_FilterModeLabel"))
	y = y + FONT_HGT_SMALL + 2

	self.weightModeCombo = addCombo(self, pad, y, innerW, function()
		self:buildLayout()
	end)
	for i = 1, #WEIGHT_MODES do
		self.weightModeCombo:addOption(T(WEIGHT_MODE_LABELS[WEIGHT_MODES[i]]))
	end
	self.weightModeCombo.selected = 1
	y = y + ENTRY_H + 8

	local idx = self.weightModeCombo.selected or 1
	local mode = WEIGHT_MODES[idx] or "eq"

	addCopy(self, pad, y, innerW, T("IGUI_GS_FilterWeightValueLabel"))
	y = y + FONT_HGT_SMALL + 2

	local halfW = mode == "between" and math.floor((innerW - 8) / 2) or innerW
	self.weightEntry = addField(self, pad, y, halfW, true)

	if mode == "between" then
		self.weightEntry2 = addField(self, pad + halfW + 8, y, halfW, true)
	else
		self.weightEntry2 = nil
	end
	y = y + ENTRY_H + 4
	return y
end

function GS_FilterEditorUI:buildTagFields(pad, innerW, y)
	addCopy(self, pad, y, innerW, T("IGUI_GS_FilterTagHint"), "textMuted", {
		textMuted = { r = 0.5, g = 0.54, b = 0.58, a = 1 },
	})
	y = y + FONT_HGT_SMALL + 6

	self.tagEntry = addField(self, pad, y, innerW)
	y = y + ENTRY_H + 4
	return y
end

function GS_FilterEditorUI:buildItemFields(pad, innerW, y)
	addCopy(self, pad, y, innerW, T("IGUI_GS_FilterItemSearchLabel"))
	y = y + FONT_HGT_SMALL + 2

	self.itemSearchEntry = addField(self, pad, y, innerW, false, function()
		self:refreshItemResults()
	end)
	y = y + ENTRY_H + 6

	if self.selectedItem then
		addCopy(self, pad, y, innerW,
			T("IGUI_GS_FilterItemSelected", self.selectedItem.name), "success", {
				success = { r = 0.5, g = 0.78, b = 0.5, a = 1 },
			})
		y = y + FONT_HGT_SMALL + 6
	end

	self.itemResultsHost = UI.Controls.panel(self, {
		x = pad, y = y, w = innerW, h = 1, drawBackground = false,
		backgroundColor = { r = 0, g = 0, b = 0, a = 0 },
		borderColor = { r = 0, g = 0, b = 0, a = 0 },
		controlId = "filterItemResultsHost", playerNum = self.playerNum,
	})
	self.itemResultsHost:setHeight(0)
	self._itemResultsY = y
	y = self:refreshItemResults()
	return y
end

--- Repinta la lista de resultados de búsqueda de ítem (sin reconstruir todo el formulario).
---@return number newY
function GS_FilterEditorUI:refreshItemResults()
	if not self.itemResultsHost then
		return self._itemResultsY or 0
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
	local newY = (self._itemResultsY or 0) + ry + 4
	-- Ajusta la altura total del panel si la lista de resultados cambió,
	-- sin reconstruir el resto del formulario (evita perder el foco del
	-- campo de búsqueda mientras el jugador escribe).
	if self.addBtn then
		self.addBtn:setY(newY + 2)
		newY = newY + BTN_H + PAD + 2
		local content = self:contentRect()
		UI.Modal.fitContent(self, newY - content.y, { center = true })
	end
	return newY
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
	local message
	if conflictContainerName then
		message = T("IGUI_GS_RuleContradictionConfirmCross", conflictContainerName, conflict.op, existingLabel, newRule.op, newLabel)
	else
		message = T("IGUI_GS_RuleContradictionConfirm", conflict.op, existingLabel, newRule.op, newLabel)
	end
	UI.Modal.confirm({
		message = message,
		onAccept = function() self:sendAddRule(newRule) end,
	})
end

--- Abre el editor de regla (motor AND/OR/NOT, dev26) para un contenedor o
--- una zona.
---@param target table { kind="node"|"zone", id=string, rules=table|nil } - rules = lista actual del propietario, para el detector de contradicciones
---@param operator string "OR"|"AND"|"NOT" - operador con el que se combinara la regla creada
---@param onAdded function|nil callback tras enviar la regla al servidor
function GlobalStorageSiK.FilterEditor.show(target, operator, onAdded)
	if not target or not target.id then return end
	if GlobalStorageSiK.FilterEditor.instance then
		GlobalStorageSiK.FilterEditor.instance:destroy()
	end
	-- Mismo ancho que los editores de contenedor/zona (dev26 ronda 4quinquies,
	-- pedido explicito: el titulo largo con el operador - "Anadir regla
	-- personalizada - Operador: NOT" - se salia del modal de 460px, tapado
	-- por el boton de cerrar). Solo el ANCHO se comparte con
	-- resolveEditorWindowSize(); el alto sigue calculandose del contenido
	-- real como siempre, este modal no es una ventana redimensionable.
	local panelW = UI.Window.resolveBounds({ profile = "editor" }).w
	local ui = GS_FilterEditorUI:new(0, 0, panelW, 200)
	ui.target = target
	ui.operator = operator or "OR"
	ui.onAdded = onAdded
	ui:initialise()
	UI.Modal.show(ui)
	GlobalStorageSiK.FilterEditor.instance = ui
end

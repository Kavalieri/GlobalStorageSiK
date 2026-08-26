--[[
	GlobalStorageSiK - Editor de filtro personalizado de contenedor
	Descripción: Modal para construir UN filtro (nombre/peso/tag/ítem exacto)
	y añadirlo al nodo que abrió el editor. Ver GS_NodeFilters.lua (lógica
	compartida de coincidencia) y GS_TerminalUI_NodeEditor.lua (quien lo abre).
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "GS_I18n"
require "GS_NetClient"
require "GS_SiK_UI_Core"
require "GS_SiK_UI_Window"
require "GS_TerminalUI_Config"
require "GS_RulesUI"

GlobalStorageSiK.FilterEditor = {}
GlobalStorageSiK.FilterEditor.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local PAD = 14
local ENTRY_H = FONT_HGT_SMALL + 8
local BTN_H = FONT_HGT_SMALL + 10
local RESULT_ROW_H = FONT_HGT_SMALL + 6
local MAX_RESULTS = 12

--- Color de acento por operador (mismo trio que GS_TerminalUI_NodeEditor.lua
--- y GS_TerminalUI_ZoneEditor.lua) - se usa en el borde superior del modal
--- para reforzar visualmente que operador se esta configurando.
local RULE_OP_COLOR = {
	OR  = GlobalStorageSiK.SiK_UI.PALETTE.ruleOr,
	AND = GlobalStorageSiK.SiK_UI.PALETTE.ruleAnd,
	NOT = GlobalStorageSiK.SiK_UI.PALETTE.ruleNot,
}

GS_FilterEditorUI = ISPanel:derive("GS_FilterEditorUI")

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
	ISPanel.initialise(self)
	self.backgroundColor = { r = 0.08, g = 0.09, b = 0.11, a = 0.96 }
	self.borderColor = { r = 0.35, g = 0.38, b = 0.42, a = 0.95 }
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + 4
	GlobalStorageSiK.SiK_UI.setupModalPanel(self, function()
		self:destroy()
	end, PAD)
	self.operator = self.operator or "OR"
	self.filterType = self.filterType or "category"
	self.selectedItem = nil
	self:buildLayout()
end

function GS_FilterEditorUI:destroy()
	GlobalStorageSiK.FilterEditor.instance = nil
	self:setVisible(false)
	if self.removeFromUIManager then
		self:removeFromUIManager()
	end
end

function GS_FilterEditorUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then
		self:destroy()
	end
end

function GS_FilterEditorUI:prerender()
	ISPanel.prerender(self)
	GlobalStorageSiK.SiK_UI.renderPanelBackground(self)
	-- Franja superior del color del operador (dev26 ronda 3) - mismo trio
	-- que las tarjetas de reglas y el modal de contradicciones, refuerza de
	-- un vistazo que operador se esta configurando sin depender solo del texto.
	local color = RULE_OP_COLOR[self.operator] or RULE_OP_COLOR.OR
	self:drawRect(0, 0, self.width, 3, 1, color[1], color[2], color[3])
	local title = T("IGUI_GS_FilterEditorTitle") .. " - " .. T("IGUI_GS_FilterEditorOperatorLabel", self.operator or "OR")
	-- Truncar por si acaso (idioma largo, operador largo) en vez de dejar
	-- que se salga por encima del boton de cerrar como antes (bug real con
	-- captura del usuario, incluso ya con el panel mas ancho).
	local closeW = self.closeBtn and self.closeBtn.width or 24
	local titleMaxW = self.width - self.padding - 4 - closeW - 8
	title = GlobalStorageSiK.SiK_UI.truncateText(title, titleMaxW, UIFont.Medium)
	self:drawText(title, self.padding + 2,
		math.floor((self.headerHeight - FONT_HGT_MEDIUM) / 2), 1, 1, 1, 1, UIFont.Medium)
	if self.closeBtn then
		self.closeBtn:bringToTop()
	end
end

--- Reconstruye el cuerpo del formulario según self.filterType.
function GS_FilterEditorUI:buildLayout()
	for i = #(self.childrenInOrder or {}), 1, -1 do
		local child = self.childrenInOrder[i]
		if child ~= self.closeBtn then
			self:removeChild(child)
			if child.removeFromUIManager then child:removeFromUIManager() end
		end
	end

	local pad = self.padding
	local innerW = self.width - pad * 2
	local y = self.headerHeight + pad

	-- Tipo de filtro
	local typeLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_FilterTypeLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	typeLbl:initialise()
	self:addChild(typeLbl)
	y = y + FONT_HGT_SMALL + 2

	self.typeCombo = ISComboBox:new(pad, y, innerW, ENTRY_H, self, nil)
	self.typeCombo:initialise()
	GlobalStorageSiK.SiK_UI.styleComboBox(self.typeCombo)
	for i = 1, #FILTER_TYPES do
		self.typeCombo:addOption(T(FILTER_TYPE_LABELS[FILTER_TYPES[i]]))
	end
	self.typeCombo.selected = 1
	for i = 1, #FILTER_TYPES do
		if FILTER_TYPES[i] == self.filterType then self.typeCombo.selected = i end
	end
	self.typeCombo.onChange = function()
		local idx = self.typeCombo.selected or 1
		self.filterType = FILTER_TYPES[idx] or "name"
		self:buildLayout()
	end
	self:addChild(self.typeCombo)
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
	self.addBtn = GlobalStorageSiK.SiK_UI.createButton(pad, y, innerW, BTN_H, T("IGUI_GS_FilterAddBtn"), self, function()
		self:onAddClicked()
	end, nil, true)
	self:addChild(self.addBtn)
	y = y + BTN_H + pad

	self:setHeight(y)
	GlobalStorageSiK.SiK_UI.layoutModalFrame(self, pad)
	self:setY(math.floor((getCore():getScreenHeight() - self.height) / 2))
end

--- Categoria > Subcategoria > Sub-subcategoria en cascada VERTICAL (a
--- diferencia de GS_TerminalUI_NodeEditor.lua, que las pone en 3 columnas).
--- Reutiliza los mismos
--- helpers compartidos de GS_TerminalUI_Config.lua (mismo catalogo completo,
--- no solo lo que la red tiene ahora).
function GS_FilterEditorUI:buildCategoryFields(pad, innerW, y)
	local mainLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NodeCategoryMainLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	mainLbl:initialise()
	self:addChild(mainLbl)
	y = y + FONT_HGT_SMALL + 2

	self.catMainCombo = ISComboBox:new(pad, y, innerW, ENTRY_H, self, nil)
	self.catMainCombo:initialise()
	GlobalStorageSiK.SiK_UI.styleComboBox(self.catMainCombo)
	GlobalStorageSiK.TerminalConfig.fillMainCategoryCombo(self.catMainCombo, {}, "")
	self:addChild(self.catMainCombo)
	y = y + ENTRY_H + 8

	local subLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NodeCategorySubLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	subLbl:initialise()
	self:addChild(subLbl)
	y = y + FONT_HGT_SMALL + 2

	self.catSubCombo = ISComboBox:new(pad, y, innerW, ENTRY_H, self, nil)
	self.catSubCombo:initialise()
	GlobalStorageSiK.SiK_UI.styleComboBox(self.catSubCombo)
	GlobalStorageSiK.TerminalConfig.fillSubCategoryCombo(self.catSubCombo, "", "", {})
	self:addChild(self.catSubCombo)
	y = y + ENTRY_H + 8

	local leafLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NodeCategoryLeafLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	leafLbl:initialise()
	self:addChild(leafLbl)
	y = y + FONT_HGT_SMALL + 2

	self.catLeafCombo = ISComboBox:new(pad, y, innerW, ENTRY_H, self, nil)
	self.catLeafCombo:initialise()
	GlobalStorageSiK.SiK_UI.styleComboBox(self.catLeafCombo)
	GlobalStorageSiK.TerminalConfig.fillLeafCategoryCombo(self.catLeafCombo, "", "", "")
	self:addChild(self.catLeafCombo)

	self.catMainCombo.onChange = function()
		local mainKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catMainCombo)
		GlobalStorageSiK.TerminalConfig.fillSubCategoryCombo(self.catSubCombo, mainKey, "", {})
		GlobalStorageSiK.TerminalConfig.fillLeafCategoryCombo(self.catLeafCombo, mainKey, "", "")
	end
	self.catSubCombo.onChange = function()
		local mainKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catMainCombo)
		local subKey = GlobalStorageSiK.TerminalConfig.getSelectedCategory(self.catSubCombo)
		GlobalStorageSiK.TerminalConfig.fillLeafCategoryCombo(self.catLeafCombo, mainKey, subKey, "")
	end
	y = y + ENTRY_H + 4
	return y
end

function GS_FilterEditorUI:buildNameFields(pad, innerW, y)
	local modeLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_FilterModeLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	modeLbl:initialise()
	self:addChild(modeLbl)
	y = y + FONT_HGT_SMALL + 2

	self.nameModeCombo = ISComboBox:new(pad, y, innerW, ENTRY_H, self, nil)
	self.nameModeCombo:initialise()
	GlobalStorageSiK.SiK_UI.styleComboBox(self.nameModeCombo)
	for i = 1, #NAME_MODES do
		self.nameModeCombo:addOption(T(NAME_MODE_LABELS[NAME_MODES[i]]))
	end
	self.nameModeCombo.selected = 1
	self:addChild(self.nameModeCombo)
	y = y + ENTRY_H + 8

	local valLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_FilterValueLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	valLbl:initialise()
	self:addChild(valLbl)
	y = y + FONT_HGT_SMALL + 2

	self.nameEntry = ISTextEntryBox:new("", pad, y, innerW, ENTRY_H)
	self.nameEntry:initialise()
	GlobalStorageSiK.SiK_UI.styleTextEntry(self.nameEntry)
	self.nameEntry:instantiate()
	self:addChild(self.nameEntry)
	y = y + ENTRY_H + 4
	return y
end

function GS_FilterEditorUI:buildWeightFields(pad, innerW, y)
	local modeLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_FilterModeLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	modeLbl:initialise()
	self:addChild(modeLbl)
	y = y + FONT_HGT_SMALL + 2

	self.weightModeCombo = ISComboBox:new(pad, y, innerW, ENTRY_H, self, nil)
	self.weightModeCombo:initialise()
	GlobalStorageSiK.SiK_UI.styleComboBox(self.weightModeCombo)
	for i = 1, #WEIGHT_MODES do
		self.weightModeCombo:addOption(T(WEIGHT_MODE_LABELS[WEIGHT_MODES[i]]))
	end
	self.weightModeCombo.selected = 1
	self.weightModeCombo.onChange = function()
		self:buildLayout()
	end
	self:addChild(self.weightModeCombo)
	y = y + ENTRY_H + 8

	local idx = self.weightModeCombo.selected or 1
	local mode = WEIGHT_MODES[idx] or "eq"

	local valLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_FilterWeightValueLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	valLbl:initialise()
	self:addChild(valLbl)
	y = y + FONT_HGT_SMALL + 2

	local halfW = mode == "between" and math.floor((innerW - 8) / 2) or innerW
	self.weightEntry = ISTextEntryBox:new("", pad, y, halfW, ENTRY_H)
	self.weightEntry:initialise()
	GlobalStorageSiK.SiK_UI.styleTextEntry(self.weightEntry)
	self.weightEntry:instantiate()
	if self.weightEntry.setOnlyNumbers then self.weightEntry:setOnlyNumbers(true) end
	self:addChild(self.weightEntry)

	if mode == "between" then
		self.weightEntry2 = ISTextEntryBox:new("", pad + halfW + 8, y, halfW, ENTRY_H)
		self.weightEntry2:initialise()
		GlobalStorageSiK.SiK_UI.styleTextEntry(self.weightEntry2)
		self.weightEntry2:instantiate()
		if self.weightEntry2.setOnlyNumbers then self.weightEntry2:setOnlyNumbers(true) end
		self:addChild(self.weightEntry2)
	else
		self.weightEntry2 = nil
	end
	y = y + ENTRY_H + 4
	return y
end

function GS_FilterEditorUI:buildTagFields(pad, innerW, y)
	local hintLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_FilterTagHint"), 0.5, 0.54, 0.58, 1, UIFont.Small, true)
	hintLbl:initialise()
	self:addChild(hintLbl)
	y = y + FONT_HGT_SMALL + 6

	self.tagEntry = ISTextEntryBox:new("", pad, y, innerW, ENTRY_H)
	self.tagEntry:initialise()
	GlobalStorageSiK.SiK_UI.styleTextEntry(self.tagEntry)
	self.tagEntry:instantiate()
	self:addChild(self.tagEntry)
	y = y + ENTRY_H + 4
	return y
end

function GS_FilterEditorUI:buildItemFields(pad, innerW, y)
	local hintLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_FilterItemSearchLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	hintLbl:initialise()
	self:addChild(hintLbl)
	y = y + FONT_HGT_SMALL + 2

	self.itemSearchEntry = ISTextEntryBox:new("", pad, y, innerW, ENTRY_H)
	self.itemSearchEntry:initialise()
	GlobalStorageSiK.SiK_UI.styleTextEntry(self.itemSearchEntry)
	self.itemSearchEntry:instantiate()
	self.itemSearchEntry.onTextChange = function()
		self:refreshItemResults()
	end
	self:addChild(self.itemSearchEntry)
	y = y + ENTRY_H + 6

	if self.selectedItem then
		local selLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_FilterItemSelected", self.selectedItem.name), 0.5, 0.78, 0.5, 1, UIFont.Small, true)
		selLbl:initialise()
		self:addChild(selLbl)
		y = y + FONT_HGT_SMALL + 6
	end

	self.itemResultsHost = ISPanel:new(pad, y, innerW, 0)
	self.itemResultsHost:initialise()
	self.itemResultsHost.drawBackground = false
	self.itemResultsHost.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	self.itemResultsHost.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	self:addChild(self.itemResultsHost)
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
		self.itemResultsHost:removeChild(child)
		if child.removeFromUIManager then child:removeFromUIManager() end
	end
	local query = self.itemSearchEntry and self.itemSearchEntry:getText() or ""
	local results = searchItems(query)
	local innerW = self.itemResultsHost.width
	local ry = 0
	for i = 1, #results do
		local r = results[i]
		local btn = GlobalStorageSiK.SiK_UI.createButton(0, ry, innerW, RESULT_ROW_H, r.name, self.itemResultsHost, function()
			self.selectedItem = { fullType = r.fullType, name = r.name }
			self:buildLayout()
		end, nil, true)
		self.itemResultsHost:addChild(btn)
		ry = ry + RESULT_ROW_H + 3
	end
	self.itemResultsHost:setHeight(math.max(0, ry))
	local newY = (self._itemResultsY or 0) + ry + 4
	-- Ajusta la altura total del panel si la lista de resultados cambió,
	-- sin reconstruir el resto del formulario (evita perder el foco del
	-- campo de búsqueda mientras el jugador escribe).
	if self.addBtn then
		self.addBtn:setY(newY + 2)
		newY = newY + BTN_H + self.padding + 2
		self:setHeight(newY)
		GlobalStorageSiK.SiK_UI.layoutModalFrame(self, self.padding)
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
		filter = { type = "category", value = key }

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
	GlobalStorageSiK.SiK_UI.Modal.confirm(message, function()
		self:sendAddRule(newRule)
	end)
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
	local panelW = GlobalStorageSiK.SiK_UI.resolveEditorWindowSize()
	local ui = GS_FilterEditorUI:new(0, 0, panelW, 200)
	ui.target = target
	ui.operator = operator or "OR"
	ui.onAdded = onAdded
	ui:initialise()
	ui:addToUIManager()
	GlobalStorageSiK.SiK_UI.centerModal(ui)
	GlobalStorageSiK.SiK_UI.finalizeModalShow(ui)
	GlobalStorageSiK.FilterEditor.instance = ui
end

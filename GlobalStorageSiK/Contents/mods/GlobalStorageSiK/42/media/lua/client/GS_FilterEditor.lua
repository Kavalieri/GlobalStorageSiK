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
require "GS_TerminalUI_Chrome"

GlobalStorageSiK.FilterEditor = {}
GlobalStorageSiK.FilterEditor.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local PAD = 14
local ENTRY_H = FONT_HGT_SMALL + 8
local BTN_H = FONT_HGT_SMALL + 10
local PANEL_W = 420
local RESULT_ROW_H = FONT_HGT_SMALL + 6
local MAX_RESULTS = 12

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
local FILTER_TYPES = { "name", "weight", "tag", "item" }
local FILTER_TYPE_LABELS = {
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
	GlobalStorageSiK.TerminalChrome.setupModalPanel(self, function()
		self:destroy()
	end, PAD)
	self.filterType = "name"
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
	GlobalStorageSiK.TerminalChrome.renderPanelBackground(self)
	self:drawText(T("IGUI_GS_FilterEditorTitle"), self.padding + 2,
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
	GlobalStorageSiK.TerminalChrome.styleComboBox(self.typeCombo)
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

	if self.filterType == "name" then
		y = self:buildNameFields(pad, innerW, y)
	elseif self.filterType == "weight" then
		y = self:buildWeightFields(pad, innerW, y)
	elseif self.filterType == "tag" then
		y = self:buildTagFields(pad, innerW, y)
	elseif self.filterType == "item" then
		y = self:buildItemFields(pad, innerW, y)
	end

	y = y + 6
	self.addBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad, y, innerW, BTN_H, T("IGUI_GS_FilterAddBtn"), self, function()
		self:onAddClicked()
	end)
	self:addChild(self.addBtn)
	y = y + BTN_H + pad

	self:setHeight(y)
	GlobalStorageSiK.TerminalChrome.layoutModalChrome(self, pad)
	self:setY(math.floor((getCore():getScreenHeight() - self.height) / 2))
end

function GS_FilterEditorUI:buildNameFields(pad, innerW, y)
	local modeLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_FilterModeLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
	modeLbl:initialise()
	self:addChild(modeLbl)
	y = y + FONT_HGT_SMALL + 2

	self.nameModeCombo = ISComboBox:new(pad, y, innerW, ENTRY_H, self, nil)
	self.nameModeCombo:initialise()
	GlobalStorageSiK.TerminalChrome.styleComboBox(self.nameModeCombo)
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
	GlobalStorageSiK.TerminalChrome.styleTextEntry(self.nameEntry)
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
	GlobalStorageSiK.TerminalChrome.styleComboBox(self.weightModeCombo)
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
	GlobalStorageSiK.TerminalChrome.styleTextEntry(self.weightEntry)
	self.weightEntry:instantiate()
	if self.weightEntry.setOnlyNumbers then self.weightEntry:setOnlyNumbers(true) end
	self:addChild(self.weightEntry)

	if mode == "between" then
		self.weightEntry2 = ISTextEntryBox:new("", pad + halfW + 8, y, halfW, ENTRY_H)
		self.weightEntry2:initialise()
		GlobalStorageSiK.TerminalChrome.styleTextEntry(self.weightEntry2)
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
	GlobalStorageSiK.TerminalChrome.styleTextEntry(self.tagEntry)
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
	GlobalStorageSiK.TerminalChrome.styleTextEntry(self.itemSearchEntry)
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
		local btn = GlobalStorageSiK.TerminalChrome.createNeatButton(0, ry, innerW, RESULT_ROW_H, r.name, self.itemResultsHost, function()
			self.selectedItem = { fullType = r.fullType, name = r.name }
			self:buildLayout()
		end)
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
		GlobalStorageSiK.TerminalChrome.layoutModalChrome(self, self.padding)
	end
	return newY
end

function GS_FilterEditorUI:onAddClicked()
	if not self.node then return end
	local filter = nil

	if self.filterType == "name" then
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

	GlobalStorageSiK.NetClient.sendCommand("updateNode", { nodeId = self.node.id, addFilter = filter })
	if self.onAdded then
		self.onAdded()
	end
	self:destroy()
end

--- Abre el editor de filtro para un nodo.
---@param node table
---@param onAdded function|nil callback tras enviar el filtro al servidor
function GlobalStorageSiK.FilterEditor.show(node, onAdded)
	if not node then return end
	if GlobalStorageSiK.FilterEditor.instance then
		GlobalStorageSiK.FilterEditor.instance:destroy()
	end
	local ui = GS_FilterEditorUI:new(0, 0, PANEL_W, 200)
	ui.node = node
	ui.onAdded = onAdded
	ui:initialise()
	ui:addToUIManager()
	ui:setX(math.floor((getCore():getScreenWidth() - PANEL_W) / 2))
	GlobalStorageSiK.TerminalChrome.finalizeModalShow(ui)
	GlobalStorageSiK.FilterEditor.instance = ui
end

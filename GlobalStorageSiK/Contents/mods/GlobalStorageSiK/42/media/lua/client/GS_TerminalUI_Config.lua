--[[
	GlobalStorageSiK - Pestañas Configuración y Contenedores del terminal
	Autor: SiK
	Fecha: 2025-06-24
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "GS_I18n"
require "GS_NativeProduct"
require "GS_CategoryResolution"
require "GS_TerminalUI_Scroll"
require "GS_SiK_UI_Core"
require "GS_SiK_UI_Controls"

GlobalStorageSiK.TerminalConfig = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local CONTROL_METRICS = GlobalStorageSiK.SiK_UI.Controls.metrics()
local BLOCK_GAP = 10
local ENTRY_H = CONTROL_METRICS.inputHeight

--- Etiqueta de membresía del nodo.
---@param node table
---@return string
local function membershipStatusText(node)
	if node.membership == "excluded" then
		return T("IGUI_GS_NodeMembershipExcluded")
	end
	if node.enabled == false then
		return T("IGUI_GS_NodeDisabled")
	end
	if node.membership == "auto" then
		return T("IGUI_GS_NodeMembershipAuto")
	end
	return T("IGUI_GS_NodeMembershipActive")
end

--- Etiqueta legible de un contenedor detectado.
---@param node table
---@return string
function GlobalStorageSiK.TerminalConfig.formatNodeHeader(node)
	local vanilla = node.name or node.vanillaName or "?"
	local coords = string.format("%d,%d", node.x or 0, node.y or 0)
	local zone = node.zoneName or node.zoneId or "?"
	local status = node.offline and T("IGUI_GS_NodeOffline") or ""
	local types = node.itemTypeCount or 0
	local member = membershipStatusText(node)
	return string.format("%s (%s) | %s | %d tipos | %s%s", vanilla, coords, zone, types, member, status)
end

--- Metadatos del contenedor sin repetir el nombre (editor modal).
---@param node table
---@return string
function GlobalStorageSiK.TerminalConfig.formatNodeMeta(node)
	local coords = string.format("%d,%d", node.x or 0, node.y or 0)
	local zone = node.zoneName or node.zoneId or "?"
	local types = node.itemTypeCount or 0
	local member = membershipStatusText(node)
	local status = node.offline and T("IGUI_GS_NodeOffline") or ""
	return string.format("%s | %s | %d tipos | %s%s", coords, zone, types, member, status)
end

--- Crea botón SiK UI de ancho completo.
---@param x number
---@param y number
---@param w number
---@param title string
---@param target any
---@param onClick function
---@return ISButton
local function createFullButton(x, y, w, title, target, onClick)
	return GlobalStorageSiK.SiK_UI.createButton(
		x, y, w, CONTROL_METRICS.buttonHeight, title, target, onClick)
end

--- Crea botón compacto SiK UI.
local function createRowButton(x, y, w, h, title, target, onClick)
	return GlobalStorageSiK.SiK_UI.createButton(x, y, w, h, title, target, onClick)
end

--- Texto de categoría seleccionada en combo (vacío = cualquiera).
---@param combo ISComboBox
---@return string
function GlobalStorageSiK.TerminalConfig.getSelectedCategory(combo)
	if not combo then
		return ""
	end
	if combo.categoryKeys then
		local idx = combo.selected or 1
		return combo.categoryKeys[idx] or ""
	end
	local text = combo:getSelectedText()
	if not text or text == "" or text == T("IGUI_GS_CategoryAny") then
		return ""
	end
	return text
end

--- Cuenta opciones de un ISComboBox (Lua 5.1 / PZ).
---@param combo ISComboBox
---@return number
local function comboOptionCount(combo)
	if combo.options and combo.options.size then
		return combo.options:size()
	end
	return 1
end

--- Texto de opción de combo por índice 1-based.
---@param combo ISComboBox
---@param index number
---@return string|nil
local function comboOptionText(combo, index)
	if combo.getOptionText then
		return combo:getOptionText(index)
	end
	if combo.options and combo.options.get then
		local opt = combo.options:get(index - 1)
		if type(opt) == "string" then
			return opt
		end
		if opt and opt.text then
			return opt.text
		end
	end
	return nil
end

--- Etiqueta de display para cualquier clave (vanilla o gs_*).
---@param key string
---@return string
local function categoryLabel(key)
	local nativePath = GlobalStorageSiK.NativeProduct.decodePath(key)
	if nativePath then
		return GlobalStorageSiK.NativeProduct.getView(nativePath).fullLabel
	end
	return tostring(key or "Misc")
end

--- Rellena combo mostrando subcategorías GS anidadas bajo su categoría vanilla madre.
---@param combo ISComboBox
---@param categories string[]  -- claves vanilla del catálogo de la red
---@param selectedCategory string|nil
function GlobalStorageSiK.TerminalConfig.fillCategoryCombo(combo, categories, selectedCategory)
	if not combo then
		return
	end
	combo:clear()
	combo.categoryKeys = { "" }
	combo:addOption(T("IGUI_GS_CategoryAny"))

	for i = 1, #(categories or {}) do
		local key = categories[i]
		combo.categoryKeys[#combo.categoryKeys + 1] = key
		combo:addOption(categoryLabel(key))
	end

	local target = selectedCategory
	if not target or target == "" then
		combo.selected = 1
		return
	end

	for i = 2, #combo.categoryKeys do
		if combo.categoryKeys[i] ~= "" and string.lower(combo.categoryKeys[i]) == string.lower(target) then
			combo.selected = i
			return
		end
	end

	-- Clave no estaba en el catálogo: añadirla al final
	combo.categoryKeys[#combo.categoryKeys + 1] = target
	combo:addOption(categoryLabel(target))
	combo.selected = #combo.categoryKeys
end

--- Rellena combo de categoria PRINCIPAL a partir del CATALOGO COMPLETO del
--- juego (todo tipo de item existente), no solo lo que la red tiene ahora
--- mismo - a diferencia del filtro de la pestaña Almacen (que si se
--- restringe al stock real), aqui el jugador debe poder preparar un filtro
--- de contenedor para algo que todavia no tiene. collectMainFilters ya
--- agrupa por tax.groupLabel (fuente unica, ver GS_ItemTaxonomy.lua
--- resolve()) asi que no hay categorias duplicadas aunque el catalogo
--- completo mezcle items "genericos" y "cualificados" de la misma familia.
--- El parametro "items" ya no se usa para esto, se deja por compatibilidad
--- de firma con los llamantes existentes.
---@param combo ISComboBox
---@param items table[]|nil sin uso, ver nota de arriba
---@param selectedKey string|nil
function GlobalStorageSiK.TerminalConfig.fillMainCategoryCombo(combo, items, selectedKey, isAvailable)
	if not combo then return end
	combo:clear()
	combo.categoryKeys = { "" }
	combo:addOption(T("IGUI_GS_CategoryAny"))
	local filters = GlobalStorageSiK.NativeProduct.listOptions(nil)
	for i = 1, #filters do
		if not isAvailable or isAvailable(filters[i].key) then
			combo.categoryKeys[#combo.categoryKeys + 1] = filters[i].key
			combo:addOption(filters[i].label)
		end
	end
	combo.selected = 1
	if selectedKey and selectedKey ~= "" then
		for i = 2, #combo.categoryKeys do
			if string.lower(combo.categoryKeys[i]) == string.lower(selectedKey) then
				combo.selected = i
				break
			end
		end
	end
end

--- Rellena combo de SUBCATEGORIA a partir del CATALOGO COMPLETO del juego,
--- restringidos a la categoria principal elegida - ver nota en
--- fillMainCategoryCombo sobre por que aqui no restringimos al stock real.
---@param combo ISComboBox
---@param mainKey string|nil categoria principal ya elegida ("" = ninguna -> combo vacio)
---@param selectedKey string|nil
---@param items table[]|nil sin uso, ver nota de fillMainCategoryCombo
function GlobalStorageSiK.TerminalConfig.fillSubCategoryCombo(combo, mainKey, selectedKey, items, isAvailable)
	if not combo then return end
	combo:clear()
	combo.categoryKeys = { "" }
	combo:addOption(T("IGUI_GS_FilterSubCategoryAll"))
	local filters = GlobalStorageSiK.NativeProduct.decodePath(mainKey)
		and GlobalStorageSiK.NativeProduct.listOptions(mainKey)
		or {}
	for i = 1, #filters do
		if not isAvailable or isAvailable(filters[i].key) then
			combo.categoryKeys[#combo.categoryKeys + 1] = filters[i].key
			combo:addOption(filters[i].label)
		end
	end
	combo.selected = 1
	if selectedKey and selectedKey ~= "" then
		for i = 2, #combo.categoryKeys do
			if string.lower(combo.categoryKeys[i]) == string.lower(selectedKey) then
				combo.selected = i
				break
			end
		end
	end
end

--- Rellena combo de SUB-SUBCATEGORIA (Nivel 3: tipo de comida, hueco de
--- joyeria/ropa...) a partir del CATALOGO COMPLETO, restringido al Nivel 1
--- (y Nivel 2, si se eligio). Siempre visible aunque no haya opciones: en
--- ese caso solo queda seleccionable "Cualquiera".
---@param combo ISComboBox
---@param mainKey string|nil categoria de Nivel 1 ya elegida
---@param subKey string|nil categoria de Nivel 2 ya elegida, o "" para no restringir
---@param selectedKey string|nil
function GlobalStorageSiK.TerminalConfig.fillLeafCategoryCombo(combo, mainKey, subKey, selectedKey, isAvailable)
	if not combo then return end
	combo:clear()
	combo.categoryKeys = { "" }
	combo:addOption(T("IGUI_GS_FilterSubCategoryAll"))
	-- La cascada es estricta: L3 solo existe tras elegir L2. Usar L1 como
	-- parent repetia las opciones L2 dentro del tercer combo.
	local filters = {}
	if subKey and subKey ~= "" then
		filters = GlobalStorageSiK.NativeProduct.decodePath(subKey)
			and GlobalStorageSiK.NativeProduct.listOptions(subKey)
			or {}
	end
	for i = 1, #filters do
		if not isAvailable or isAvailable(filters[i].key) then
			combo.categoryKeys[#combo.categoryKeys + 1] = filters[i].key
			combo:addOption(filters[i].label)
		end
	end
	combo.selected = 1
	if selectedKey and selectedKey ~= "" then
		for i = 2, #combo.categoryKeys do
			if string.lower(combo.categoryKeys[i]) == string.lower(selectedKey) then
				combo.selected = i
				break
			end
		end
	end
end

--- Refresca lista de zonas con scroll a partir de Y dada.
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param zones table[]
---@param startY number|nil
---@return number nextY
function GlobalStorageSiK.TerminalConfig.refreshZonesPanelAt(scroll, terminal, zones, startY)
	if not scroll or not terminal then
		return startY or 8
	end
	scroll.zoneRows = scroll.zoneRows or {}

	local pad = 8
	local y = startY or pad
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local renameW = 78
	local deleteW = 72
	local btnGap = 6
	local entryW = innerW - renameW - deleteW - btnGap * 2

	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	if not zones or #zones == 0 then
		local emptyLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NoZonesYet"), pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small, true)
		emptyLbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, emptyLbl)
		return y + FONT_HGT_SMALL + pad
	end

	local hintLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_ZonesManageHint"), pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small, true)
	hintLbl:initialise()
	GlobalStorageSiK.TerminalScroll.addChild(scroll, hintLbl)
	y = y + FONT_HGT_SMALL + 8

	for i = 1, #zones do
		local zone = zones[i]
		local row = {}
		local line = string.format("[%s] %s", zone.source or "?", zone.name or zone.id)

		row.headerLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, line, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small, true)
		row.headerLbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.headerLbl)
		y = y + FONT_HGT_SMALL + 4

		row.nameLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_ZoneRenameLabel"), pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small, true)
		row.nameLbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.nameLbl)
		y = y + FONT_HGT_SMALL + 2

		row.nameEntry = ISTextEntryBox:new(zone.name or "", pad, y, entryW, ENTRY_H)
		row.nameEntry:initialise()
		GlobalStorageSiK.SiK_UI.styleTextEntry(row.nameEntry)
		row.nameEntry:instantiate()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.nameEntry)

		row.renameBtn = createRowButton(pad + entryW + btnGap, y, renameW, ENTRY_H, T("IGUI_GS_Rename"), scroll, function()
			terminal:onRenameZone(zone.id, row.nameEntry:getText())
		end)
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.renameBtn)

		row.deleteBtn = createRowButton(pad + entryW + btnGap + renameW + btnGap, y, deleteW, ENTRY_H, T("IGUI_GS_DeleteZone"), scroll, function()
			terminal:onDeleteZone(zone.id)
		end)
		GlobalStorageSiK.SiK_UI.applyDangerButton(row.deleteBtn)
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.deleteBtn)

		y = y + ENTRY_H + BLOCK_GAP
		table.insert(scroll.zoneRows, row)
	end

	return y + pad
end

--- Refresca lista de zonas con scroll.
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param zones table[]
function GlobalStorageSiK.TerminalConfig.refreshZonesPanel(scroll, terminal, zones)
	if not scroll or not terminal then
		return
	end
	GlobalStorageSiK.TerminalScroll.clear(scroll, true)
	local y = GlobalStorageSiK.TerminalConfig.refreshZonesPanelAt(scroll, terminal, zones, 8)
	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, y)
end

--- Ajusta geometría de filas en scroll de zonas.
---@param scroll ISPanel
---@param innerW number
function GlobalStorageSiK.TerminalConfig.layoutZonesScroll(scroll, innerW)
	if not scroll or not scroll.zoneRows then
		return
	end
	local pad = 8
	local w = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	local renameW = 78
	local deleteW = 72
	local btnGap = 6
	local entryW = w - renameW - deleteW - btnGap * 2
	for i = 1, #scroll.zoneRows do
		local row = scroll.zoneRows[i]
		if row.nameEntry then row.nameEntry:setWidth(entryW) end
		if row.renameBtn then row.renameBtn:setX(pad + entryW + btnGap) end
		if row.deleteBtn then row.deleteBtn:setX(pad + entryW + btnGap + renameW + btnGap) end
	end
end

--- Cabecera informativa de la pestaña contenedores.
---@param panel ISPanel
function GlobalStorageSiK.TerminalConfig.buildNodesHeader(panel)
	if panel.nodesHeaderBuilt then
		return
	end
	panel.nodesHeaderBuilt = true
	local pad = panel.contentPad or 8
	local _pal = GlobalStorageSiK.SiK_UI.PALETTE
	panel.nodesHelpLbl = ISLabel:new(
		pad, 0, FONT_HGT_SMALL, T("IGUI_GS_NodesHelpShort"),
		_pal.textMuted[1], _pal.textMuted[2], _pal.textMuted[3], 1, UIFont.Small, true
	)
	panel.nodesHelpLbl:initialise()
	panel:addChild(panel.nodesHelpLbl)
end

--- Refresca panel tras recibir contenido de nodo.
---@param args table|nil
function GlobalStorageSiK.TerminalConfig.onNodeContentsReceived(args)
	if GlobalStorageSiK.TerminalNodeEditor and GlobalStorageSiK.TerminalNodeEditor.onContentsReceived then
		GlobalStorageSiK.TerminalNodeEditor.onContentsReceived(args)
	end
end

--- Pinta filas de contenido expandido de un nodo (editor modal).
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param node table
---@param y number
---@param pad number
---@param innerW number
---@param innerW number
---@param opts table|nil opts.plainHost usa parent:addChild directo (editor modal)
---@return number nextY
function GlobalStorageSiK.TerminalConfig.renderNodeContentsBlock(scroll, terminal, node, y, pad, innerW, opts)
	opts = opts or {}
	local plainHost = opts.plainHost == true
	local function adopt(widget)
		if plainHost and scroll and scroll.addChild then
			scroll:addChild(widget)
		else
			GlobalStorageSiK.TerminalScroll.addChild(scroll, widget)
		end
	end
	local cache = GlobalStorageSiK.Client and GlobalStorageSiK.Client.nodeContentsCache or {}
	local payload = cache[node.id]
	local source = payload and payload.source or "empty"
	local rows = payload and payload.rows or {}
	local sourceLbl
	if source == "live" then
		sourceLbl = T("IGUI_GS_NodeContentsLive")
	elseif source == "snapshot" then
		sourceLbl = T("IGUI_GS_NodeContentsSnapshot")
	else
		sourceLbl = T("IGUI_GS_NodeContentsEmpty")
	end
	local _rpal = GlobalStorageSiK.SiK_UI.PALETTE
	local srcLabel = ISLabel:new(pad, y, FONT_HGT_SMALL, sourceLbl, _rpal.textMuted[1], _rpal.textMuted[2], _rpal.textMuted[3], 1, UIFont.Small, true)
	srcLabel:initialise()
	adopt(srcLabel)
	y = y + FONT_HGT_SMALL + 6

	-- dev25: bloque legacy "Sugerida: X [Aplicar]" ELIMINADO de aqui - era una
	-- segunda implementacion, mas vieja e independiente, del mismo concepto
	-- que ya cubre la tarjeta "Categoria sugerida" (con botones OR/AND y
	-- deteccion de contradicciones) construida al principio del bloque de
	-- reglas en GS_TerminalUI_NodeEditor.lua - las dos convivian sin que
	-- nadie retirase esta cuando se construyo la nueva, dejando un boton
	-- "Aplicar" suelto (sin OR/AND, sin pasar por detectContradiction) mas
	-- abajo del todo, bajo "Contenido del contenedor" (bug real con captura
	-- del usuario). `applyUpdate` e `IGUI_GS_NodeSuggestCategory` quedan sin
	-- uso aqui a proposito, la tarjeta nueva ya cubre el flujo completo.
	if #rows == 0 then
		return y + 4
	end
	for i = 1, math.min(#rows, 24) do
		local row = rows[i]
		local name = GlobalStorageSiK.I18n.itemDisplayName(row.fullType, row.displayName)
		local cat = GlobalStorageSiK.I18n.itemCategoryDisplay(row.fullType, row.category, row.subCategory, row.gsSubKeysStr)
		local line = string.format("- %s  [%s] x%d", name, cat, row.count or 0)
		local lbl = ISLabel:new(pad + 12, y, FONT_HGT_SMALL, line, _rpal.textSecondary[1], _rpal.textSecondary[2], _rpal.textSecondary[3], 1, UIFont.Small, true)
		lbl:initialise()
		adopt(lbl)
		y = y + FONT_HGT_SMALL + 2
	end
	if #rows > 24 then
		local moreLbl = ISLabel:new(pad + 20, y, FONT_HGT_SMALL, "…", _rpal.textMuted[1], _rpal.textMuted[2], _rpal.textMuted[3], 1, UIFont.Small, true)
		moreLbl:initialise()
		adopt(moreLbl)
		y = y + FONT_HGT_SMALL + 2
	end
	return y + 4
end

--- Refresca lista editable de contenedores detectados.
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param nodes table[]
---@param categories string[]
function GlobalStorageSiK.TerminalConfig.refreshNodesPanel(scroll, terminal, nodes, categories)
	if not scroll or not terminal then
		return
	end
	scroll.expandedNodes = scroll.expandedNodes or {}
	local savedOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	GlobalStorageSiK.TerminalScroll.clear(scroll, true)
	scroll.nodeRows = {}

	local pad = 8
	local y = pad
	local innerW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)

	local _npal = GlobalStorageSiK.SiK_UI.PALETTE
	if not nodes or #nodes == 0 then
		local emptyLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NoNodesYet"), _npal.textMuted[1], _npal.textMuted[2], _npal.textMuted[3], 1, UIFont.Small, true)
		emptyLbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, emptyLbl)
		GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, y + FONT_HGT_SMALL + pad)
		GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
		return
	end

	for i = 1, #nodes do
		local node = nodes[i]
		local row = {}
		local nodeId = node.id
		local primaryCategory = node.categories and node.categories[1] or ""
		local currentlyEnabled = node.enabled ~= false
		local isExcluded = node.membership == "excluded"
		local expanded = scroll.expandedNodes[nodeId] == true
		local btnH = FONT_HGT_SMALL + 10

		row.headerLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, GlobalStorageSiK.TerminalConfig.formatNodeHeader(node), _npal.textPrimary[1], _npal.textPrimary[2], _npal.textPrimary[3], 1, UIFont.Small, true)
		row.headerLbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.headerLbl)
		y = y + FONT_HGT_SMALL + 6

		row.nameLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_NodeRenameLabel"), _npal.textMuted[1], _npal.textMuted[2], _npal.textMuted[3], 1, UIFont.Small, true)
		row.nameLbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.nameLbl)
		y = y + FONT_HGT_SMALL + 2

		row.nameEntry = ISTextEntryBox:new(node.displayName or node.name or "", pad, y, innerW, ENTRY_H)
		row.nameEntry:initialise()
		GlobalStorageSiK.SiK_UI.styleTextEntry(row.nameEntry)
		row.nameEntry:instantiate()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.nameEntry)
		y = y + ENTRY_H + 4

		row.catLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_CategoryLabel"), 0.68, 0.72, 0.76, 1, UIFont.Small, true)
		row.catLbl:initialise()
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.catLbl)
		y = y + FONT_HGT_SMALL + 2

		row.catCombo = ISComboBox:new(pad, y, innerW, ENTRY_H, scroll, nil)
		row.catCombo:initialise()
		GlobalStorageSiK.SiK_UI.styleComboBox(row.catCombo)
		GlobalStorageSiK.TerminalConfig.fillCategoryCombo(row.catCombo, categories, primaryCategory)
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.catCombo)
		y = y + ENTRY_H + 6

		row.saveBtn = createFullButton(pad, y, innerW, T("IGUI_GS_NodeSaveAll"), scroll, function()
			terminal:onUpdateNode(
				nodeId,
				row.nameEntry:getText(),
				GlobalStorageSiK.TerminalConfig.getSelectedCategory(row.catCombo),
				nil,
				nil
			)
		end)
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.saveBtn)
		y = y + btnH + 4

		local enabledLabel = currentlyEnabled and T("IGUI_GS_NodeBtnDisable") or T("IGUI_GS_NodeBtnEnable")
		row.toggleBtn = createFullButton(pad, y, innerW, enabledLabel, scroll, function()
			terminal:onUpdateNode(
				nodeId,
				row.nameEntry:getText(),
				GlobalStorageSiK.TerminalConfig.getSelectedCategory(row.catCombo),
				not currentlyEnabled,
				nil
			)
		end)
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.toggleBtn)
		y = y + btnH + 4

		local membLabel = isExcluded and T("IGUI_GS_NodeBtnInclude") or T("IGUI_GS_NodeBtnExclude")
		row.membershipBtn = createFullButton(pad, y, innerW, membLabel, scroll, function()
			if isExcluded then
				terminal:onUpdateNode(nodeId, row.nameEntry:getText(), GlobalStorageSiK.TerminalConfig.getSelectedCategory(row.catCombo), true, "active")
			else
				terminal:onUpdateNode(nodeId, row.nameEntry:getText(), GlobalStorageSiK.TerminalConfig.getSelectedCategory(row.catCombo), false, "excluded")
			end
		end)
		row.membershipBtn.borderColor = isExcluded and { r = 0.35, g = 0.45, b = 0.35, a = 0.9 } or { r = 0.45, g = 0.35, b = 0.35, a = 0.9 }
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.membershipBtn)
		y = y + btnH + 4

		local expandLabel = expanded and T("IGUI_GS_NodeCollapse") or T("IGUI_GS_NodeExpand")
		row.expandBtn = createFullButton(pad, y, innerW, expandLabel, scroll, function()
			scroll.expandedNodes[nodeId] = not scroll.expandedNodes[nodeId]
			if scroll.expandedNodes[nodeId] then
				terminal:onRequestNodeContents(nodeId)
			end
			GlobalStorageSiK.TerminalConfig.refreshNodesPanel(scroll, terminal, nodes, categories)
		end)
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row.expandBtn)
		y = y + btnH + 4

		if expanded then
			y = GlobalStorageSiK.TerminalConfig.renderNodeContentsBlock(scroll, terminal, node, y, pad, innerW)
		end

		local sep = ISPanel:new(pad, y, innerW, 1)
		sep:initialise()
		sep.drawBackground = true
		sep.backgroundColor = { r = 0.28, g = 0.28, b = 0.28, a = 0.55 }
		sep.borderColor = { r = 0, g = 0, b = 0, a = 0 }
		GlobalStorageSiK.TerminalScroll.addChild(scroll, sep)
		y = y + BLOCK_GAP + 8

		table.insert(scroll.nodeRows, row)
	end

	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, y + pad)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, savedOffset)
end

--- Ajusta geometría de filas en scroll de contenedores (ancho responsivo).
---@param scroll ISPanel
---@param innerW number
function GlobalStorageSiK.TerminalConfig.layoutNodesScroll(scroll, innerW)
	if not scroll or not scroll.nodeRows then
		return
	end
	local w = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	for i = 1, #scroll.nodeRows do
		local row = scroll.nodeRows[i]
		if row.nameEntry then
			row.nameEntry:setWidth(w)
		end
		if row.catCombo then
			row.catCombo:setWidth(w)
		end
		if row.saveBtn then
			row.saveBtn:setWidth(w)
		end
		if row.toggleBtn then
			row.toggleBtn:setWidth(w)
		end
		if row.membershipBtn then
			row.membershipBtn:setWidth(w)
		end
		if row.expandBtn then
			row.expandBtn:setWidth(w)
		end
	end
end

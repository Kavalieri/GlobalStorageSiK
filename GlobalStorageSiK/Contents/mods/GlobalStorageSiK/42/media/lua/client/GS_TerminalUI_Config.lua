--[[
	GlobalStorageSiK - Pestañas Configuración y Contenedores del terminal
	Autor: SiK
	Fecha: 2025-06-24
]]

require "GS_I18n"
require "GS_NativeProduct"
require "GS_CategoryResolution"

local UI = require "GS_UI_Framework"
local Confirmation = require "GS_Confirmation"

GlobalStorageSiK.TerminalConfig = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local CONTROL_METRICS = UI.Controls.metrics()
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
        return UI.Controls.button(nil, {
                x = x, y = y, w = w, h = CONTROL_METRICS.buttonHeight,
                text = title, onClick = function() return onClick(target) end,
        })
end

--- Crea botón compacto SiK UI.
local function createRowButton(x, y, w, h, title, target, onClick, danger)
        return UI.Controls.button(nil, {
                x = x, y = y, w = w, h = h, text = title, danger = danger == true,
                onClick = function() return onClick(target) end,
        })
end

local function createCopy(x, y, w, text, tone)
	return UI.Controls.copyText(nil, {
		x = x, y = y, w = math.max(1, w), text = text or "",
		tone = tone or "text", font = UIFont.Small, lineGap = 2,
	})
end

--- Texto de categoría seleccionada en combo (vacío = cualquiera).
---@param combo ISComboBox
---@return string
function GlobalStorageSiK.TerminalConfig.getSelectedCategory(combo)
	if not combo then
		return ""
	end
	if combo.getSelectedItem then
		local item = combo:getSelectedItem()
		if item and item.value ~= nil then return tostring(item.value) end
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
	local entries = { { text = T("IGUI_GS_CategoryAny"), value = "" } }
	combo.categoryKeys = { "" }

	for i = 1, #(categories or {}) do
		local key = categories[i]
		combo.categoryKeys[#combo.categoryKeys + 1] = key
		entries[#entries + 1] = { text = categoryLabel(key), value = key }
	end

	local target = selectedCategory
	if not target or target == "" then
		combo:setItems(entries, 1)
		return
	end

	for i = 2, #combo.categoryKeys do
		if combo.categoryKeys[i] ~= "" and string.lower(combo.categoryKeys[i]) == string.lower(target) then
			combo:setItems(entries, i)
			return
		end
	end

	-- Clave no estaba en el catálogo: añadirla al final
	combo.categoryKeys[#combo.categoryKeys + 1] = target
	entries[#entries + 1] = { text = categoryLabel(target), value = target }
	combo:setItems(entries, #entries)
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
	local innerW = UI.Scroll.contentWidth(scroll)
	local renameW = 78
	local deleteW = 72
	local btnGap = 6
	local entryW = innerW - renameW - deleteW - btnGap * 2

	if not zones or #zones == 0 then
		local emptyLbl = createCopy(pad, y, innerW - pad,
			T("IGUI_GS_NoZonesYet"), "textMuted")
		UI.Scroll.addChild(scroll, emptyLbl)
		return y + FONT_HGT_SMALL + pad
	end

	local hintLbl = createCopy(pad, y, innerW - pad,
		T("IGUI_GS_ZonesManageHint"), "textMuted")
	UI.Scroll.addChild(scroll, hintLbl)
	y = y + FONT_HGT_SMALL + 8

	for i = 1, #zones do
		local zone = zones[i]
		local row = {}
		local line = string.format("[%s] %s", zone.source or "?", zone.name or zone.id)

		row.headerLbl = createCopy(pad, y, innerW - pad, line, "text")
		UI.Scroll.addChild(scroll, row.headerLbl)
		y = y + FONT_HGT_SMALL + 4

		row.nameLbl = createCopy(pad, y, innerW - pad,
			T("IGUI_GS_ZoneRenameLabel"), "textMuted")
		UI.Scroll.addChild(scroll, row.nameLbl)
		y = y + FONT_HGT_SMALL + 2

		row.nameEntry = UI.Controls.field(nil, {
			x = pad, y = y, w = entryW, h = ENTRY_H, text = zone.name or "",
		})
		UI.Scroll.addChild(scroll, row.nameEntry)

		row.renameBtn = createRowButton(pad + entryW + btnGap, y, renameW, ENTRY_H, T("IGUI_GS_Rename"), scroll, function()
			terminal:onRenameZone(zone.id, row.nameEntry:getText())
		end)
		UI.Scroll.addChild(scroll, row.renameBtn)

		row.deleteBtn = createRowButton(pad + entryW + btnGap + renameW + btnGap, y, deleteW, ENTRY_H, T("IGUI_GS_DeleteZone"), scroll, function()
			Confirmation.show({
				title = T("IGUI_GS_DeleteZone"),
				question = T("IGUI_GS_ZoneDeleteQuestion", zone.name or "?"),
				consequences = T("IGUI_GS_ZoneDeleteConsequences", tonumber(zone.nodeCount) or 0),
				onAccept = function() terminal:onDeleteZone(zone.id) end,
			})
		end, true)
		UI.Scroll.addChild(scroll, row.deleteBtn)

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
	UI.Scroll.clear(scroll, true)
	local y = GlobalStorageSiK.TerminalConfig.refreshZonesPanelAt(scroll, terminal, zones, 8)
	UI.Scroll.setContentHeight(scroll, y)
end

--- Ajusta geometría de filas en scroll de zonas.
---@param scroll ISPanel
---@param innerW number
function GlobalStorageSiK.TerminalConfig.layoutZonesScroll(scroll, innerW)
	if not scroll or not scroll.zoneRows then
		return
	end
	local pad = 8
	local w = UI.Scroll.contentWidth(scroll)
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
	panel.nodesHelpLbl = UI.Controls.copyText(panel, {
		x = pad, y = 0, w = math.max(1, panel.width - pad * 2),
		text = T("IGUI_GS_NodesHelpShort"), tone = "textMuted",
		font = UIFont.Small, lineGap = 2,
	})
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
			UI.Scroll.addChild(scroll, widget)
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
	local srcLabel = createCopy(pad, y, innerW - pad, sourceLbl, "textMuted")
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
		local lbl = createCopy(pad + 12, y, innerW - pad - 12, line, "text")
		adopt(lbl)
		y = y + FONT_HGT_SMALL + 2
	end
	if #rows > 24 then
		local moreLbl = createCopy(pad + 20, y, innerW - pad - 20,
			"…", "textMuted")
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
	local savedOffset = UI.Scroll.getScrollOffset(scroll)
	UI.Scroll.clear(scroll, true)
	scroll.nodeRows = {}

	local pad = 8
	local y = pad
	local innerW = UI.Scroll.contentWidth(scroll)

	if not nodes or #nodes == 0 then
		local emptyLbl = createCopy(pad, y, innerW - pad,
			T("IGUI_GS_NoNodesYet"), "textMuted")
		UI.Scroll.addChild(scroll, emptyLbl)
		UI.Scroll.setContentHeight(scroll, y + FONT_HGT_SMALL + pad)
		UI.Scroll.setScrollOffset(scroll, savedOffset)
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

		row.headerLbl = createCopy(pad, y, innerW - pad,
			GlobalStorageSiK.TerminalConfig.formatNodeHeader(node), "text")
		UI.Scroll.addChild(scroll, row.headerLbl)
		y = y + FONT_HGT_SMALL + 6

		row.nameLbl = createCopy(pad, y, innerW - pad,
			T("IGUI_GS_NodeRenameLabel"), "textMuted")
		UI.Scroll.addChild(scroll, row.nameLbl)
		y = y + FONT_HGT_SMALL + 2

		row.nameEntry = UI.Controls.field(nil, {
			x = pad, y = y, w = innerW, h = ENTRY_H,
			text = node.displayName or node.name or "",
		})
		UI.Scroll.addChild(scroll, row.nameEntry)
		y = y + ENTRY_H + 4

		row.catLbl = createCopy(pad, y, innerW - pad,
			T("IGUI_GS_CategoryLabel"), "textMuted")
		UI.Scroll.addChild(scroll, row.catLbl)
		y = y + FONT_HGT_SMALL + 2

		row.catCombo = UI.Controls.combo(nil, {
			x = pad, y = y, w = innerW, h = ENTRY_H,
		})
		GlobalStorageSiK.TerminalConfig.fillCategoryCombo(row.catCombo, categories, primaryCategory)
		UI.Scroll.addChild(scroll, row.catCombo)
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
		UI.Scroll.addChild(scroll, row.saveBtn)
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
		UI.Scroll.addChild(scroll, row.toggleBtn)
		y = y + btnH + 4

		local membLabel = isExcluded and T("IGUI_GS_NodeBtnInclude") or T("IGUI_GS_NodeBtnExclude")
		row.membershipBtn = UI.Controls.button(nil, {
			x = pad, y = y, w = innerW, h = CONTROL_METRICS.buttonHeight,
			text = membLabel, active = isExcluded,
			onClick = function()
				if isExcluded then
					terminal:onUpdateNode(nodeId, row.nameEntry:getText(), GlobalStorageSiK.TerminalConfig.getSelectedCategory(row.catCombo), true, "active")
				else
					terminal:onUpdateNode(nodeId, row.nameEntry:getText(), GlobalStorageSiK.TerminalConfig.getSelectedCategory(row.catCombo), false, "excluded")
				end
			end,
		})
		UI.Scroll.addChild(scroll, row.membershipBtn)
		y = y + btnH + 4

		local expandLabel = expanded and T("IGUI_GS_NodeCollapse") or T("IGUI_GS_NodeExpand")
		row.expandBtn = createFullButton(pad, y, innerW, expandLabel, scroll, function()
			scroll.expandedNodes[nodeId] = not scroll.expandedNodes[nodeId]
			if scroll.expandedNodes[nodeId] then
				terminal:onRequestNodeContents(nodeId)
			end
			GlobalStorageSiK.TerminalConfig.refreshNodesPanel(scroll, terminal, nodes, categories)
		end)
		UI.Scroll.addChild(scroll, row.expandBtn)
		y = y + btnH + 4

		if expanded then
			y = GlobalStorageSiK.TerminalConfig.renderNodeContentsBlock(scroll, terminal, node, y, pad, innerW)
		end

		local sep = UI.Controls.separator(nil, {
			x = pad, y = y, w = innerW, h = 1,
			controlId = "terminalConfigSeparator", playerNum = terminal.playerNum,
		})
		UI.Scroll.addChild(scroll, sep)
		y = y + BLOCK_GAP + 8

		table.insert(scroll.nodeRows, row)
	end

	UI.Scroll.setContentHeight(scroll, y + pad)
	UI.Scroll.setScrollOffset(scroll, savedOffset)
end

--- Ajusta geometría de filas en scroll de contenedores (ancho responsivo).
---@param scroll ISPanel
---@param innerW number
function GlobalStorageSiK.TerminalConfig.layoutNodesScroll(scroll, innerW)
	if not scroll or not scroll.nodeRows then
		return
	end
	local w = UI.Scroll.contentWidth(scroll)
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

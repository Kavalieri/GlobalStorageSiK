--[[
	GlobalStorageSiK - Pestaña de ítems del terminal (iconos, orden, menú contextual)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Lista virtual con NIVirtualScrollView (NeatUI) o pool legacy.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISContextMenu"
require "GS_I18n"
require "GS_ItemTaxonomy"
require "GS_Libs"
require "GS_BulkFilters"
require "GS_DepositSources"
require "GS_TerminalWithdrawDrag"
require "GS_WithdrawMenu"
require "GS_QuantityPrompt"
require "GS_Log"
require "GS_ContextMenuUi"
require "GS_ContainerTargets"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Chrome"
require "GS_ItemNetworkTooltip"
require "GS_NetworkReadAction"

GlobalStorageSiK.TerminalItems = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local ICON_SIZE = 32
local ROW_H = ICON_SIZE + 8
local HEADER_H = FONT_HGT_SMALL + 10
local DRAG_THRESHOLD = 6
local ITEM_TEXTURE_CACHE = {}

---@param panel ISPanel
---@param fullType string|nil
---@return number|nil
local function findItemIndex(panel, fullType)
	local items = panel and panel._lastItems
	if not items or not fullType then
		return nil
	end
	for i = 1, #items do
		if items[i].fullType == fullType then
			return i
		end
	end
	return nil
end

---@param panel ISPanel
---@return table[]
local function getSelectedRows(panel)
	local out = {}
	local items = panel and panel._lastItems
	if not items or not panel._selectedKeys then
		return out
	end
	for i = 1, #items do
		local row = items[i]
		if row.fullType and panel._selectedKeys[row.fullType] then
			out[#out + 1] = row
		end
	end
	return out
end

---@param panel ISPanel
---@param fullType string|nil
---@param index number|nil
local function selectSingleRow(panel, fullType, index)
	if not panel or not fullType then
		return
	end
	panel._selectedKeys = { [fullType] = true }
	panel._selectionAnchor = index or findItemIndex(panel, fullType) or 1
end

---@param panel ISPanel
---@param fullType string|nil
local function toggleRowSelection(panel, fullType)
	if not panel or not fullType then
		return
	end
	panel._selectedKeys = panel._selectedKeys or {}
	if panel._selectedKeys[fullType] then
		panel._selectedKeys[fullType] = nil
	else
		panel._selectedKeys[fullType] = true
		panel._selectionAnchor = findItemIndex(panel, fullType) or panel._selectionAnchor
	end
end

---@param panel ISPanel
---@param toIndex number
local function selectRangeTo(panel, toIndex)
	local items = panel._lastItems
	if not items or #items == 0 then
		return
	end
	local anchor = panel._selectionAnchor or toIndex
	local lo = math.max(1, math.min(anchor, toIndex))
	local hi = math.min(#items, math.max(anchor, toIndex))
	panel._selectedKeys = panel._selectedKeys or {}
	for i = lo, hi do
		local row = items[i]
		if row and row.fullType then
			panel._selectedKeys[row.fullType] = true
		end
	end
end

---@param panel ISPanel
---@param row ISPanel
local function handleRowClick(panel, row)
	local data = row.itemData
	if not data or not data.fullType then
		return
	end
	local idx = row.rowIndex or findItemIndex(panel, data.fullType) or 1
	if isCtrlKeyDown and isCtrlKeyDown() then
		toggleRowSelection(panel, data.fullType)
	elseif isShiftKeyDown and isShiftKeyDown() then
		if not panel._selectionAnchor then
			panel._selectionAnchor = idx
		end
		selectRangeTo(panel, idx)
	else
		selectSingleRow(panel, data.fullType, idx)
	end
end

--- Trunca texto al ancho máximo en píxeles.
---@param text string
---@param maxW number
---@param font UIFont|nil
---@return string
local function truncateText(text, maxW, font)
	return GlobalStorageSiK.TerminalChrome.truncateText(text, maxW, font or UIFont.Small)
end

GlobalStorageSiK.TerminalItems.ROW_H = ROW_H

---@param fullType string|nil
---@return any|nil
local function scriptItem(fullType)
	if not fullType then return nil end
	local sm = getScriptManager and getScriptManager()
	if not sm or not sm.getItem then return nil end
	local ok, script = pcall(function() return sm:getItem(fullType) end)
	return ok and script or nil
end

--- Crea una instancia de tooltip válida sin consultar como ScriptItem los
--- tokens de muebles recogidos.
---@param row table|nil
---@return InventoryItem|nil
local function itemProbe(row)
	if not row then return nil end
	-- Los muebles recogidos suelen compartir un fullType generico. Vanilla
	-- reconstruye el InventoryItem desde el sprite del mundo; hacerlo primero
	-- conserva su icono de inventario, nombre y propiedades reales.
	if row.worldSprite then
		if not ISMoveableSpriteProps then
			pcall(require, "Moveables/ISMoveableSpriteProps")
		end
		if ISMoveableSpriteProps and ISMoveableSpriteProps.new then
			local ok, probe = pcall(function()
				local props = ISMoveableSpriteProps.new(row.worldSprite)
				return props and props.instanceItem and props:instanceItem(row.worldSprite) or nil
			end)
			if ok and probe then return probe end
		end
	end
	if scriptItem(row.fullType) and instanceItem then
		local ok, probe = pcall(instanceItem, row.fullType)
		if ok then return probe end
	end
	return nil
end

--- Textura de inventario resuelta como vanilla (`InventoryItem:getTex()`).
--- El resultado se cachea porque la lista virtual puede redibujar la misma
--- fila muchas veces. ScriptItem y sprite del mundo son solo fallbacks.
---@param row table|nil
---@return Texture|nil
local function itemTexture(row)
	if not row or not row.fullType then
		return nil
	end
	local cacheKey = tostring(row.fullType) .. "\31" .. tostring(row.worldSprite or "")
	local cached = ITEM_TEXTURE_CACHE[cacheKey]
	if cached then
		return cached
	end

	local probe = itemProbe(row)
	if probe and probe.getTex then
		local ok, tex = pcall(function() return probe:getTex() end)
		if ok and tex then
			ITEM_TEXTURE_CACHE[cacheKey] = tex
			return tex
		end
	end

	local script = scriptItem(row.fullType)
	if script and script.getNormalTexture then
		local ok, tex = pcall(function() return script:getNormalTexture() end)
		if ok and tex then
			ITEM_TEXTURE_CACHE[cacheKey] = tex
			return tex
		end
	end
	if row.worldSprite and getSprite then
		local ok, tex = pcall(function()
			local sprite = getSprite(row.worldSprite)
			return sprite and sprite.getTexture and sprite:getTexture() or nil
		end)
		if ok and tex then
			ITEM_TEXTURE_CACHE[cacheKey] = tex
			return tex
		end
	end
	return nil
end

--- Ordena filas según clave y dirección.
---@param rows table[]
---@param sortKey string
---@param ascending boolean
---@return table[]
local function sortKeyValue(row, sortKey)
	if sortKey == "count" then
		return row.count or 0
	end
	if sortKey == "category" then
		if GlobalStorageSiK.ItemTaxonomy and GlobalStorageSiK.ItemTaxonomy.resolve then
			return string.lower(GlobalStorageSiK.ItemTaxonomy.resolve(row.fullType, row).fullLabel)
		end
		return string.lower(tostring(row.category or ""))
	end
	local name = GlobalStorageSiK.I18n.itemDisplayName(row.fullType, row.displayName, row.worldSprite)
	return string.lower(tostring(name or row.fullType or ""))
end

--- Ordena filas según clave y dirección.
---@param rows table[]
---@param sortKey string
---@param ascending boolean
---@return table[]
local function sortRows(rows, sortKey, ascending)
	local sorted = {}
	for i = 1, #rows do
		sorted[i] = rows[i]
	end
	table.sort(sorted, function(a, b)
		local av = sortKeyValue(a, sortKey)
		local bv = sortKeyValue(b, sortKey)
		if av == bv then
			return (a.fullType or "") < (b.fullType or "")
		end
		if ascending then
			return av < bv
		end
		return av > bv
	end)
	return sorted
end

--- Taxonomía vanilla resuelta de una fila.
---@param row table|nil
---@return table
function GlobalStorageSiK.TerminalItems.rowTaxonomy(row)
	if not row then
		return { mainKey = "", subKey = "", mainLabel = "", subLabel = "", fullLabel = "",
			groupKey = "", subGroupKey = nil, groupLabel = "", subGroupLabel = nil, leafLabel = nil }
	end
	return GlobalStorageSiK.ItemTaxonomy.resolve(row.fullType, row)
end

--- Recopila categorías principales únicas del catálogo.
---@param rows table[]
---@return table[] { key: string, label: string, typeCount: number }
function GlobalStorageSiK.TerminalItems.collectMainCategoryFilters(rows)
	return GlobalStorageSiK.ItemTaxonomy.collectMainFilters(rows or {})
end

--- Recopila subcategorías únicas (opcionalmente restringidas a una categoría principal).
---@param rows table[]
---@param mainKey string|nil
---@return table[] { key: string, label: string, typeCount: number }
function GlobalStorageSiK.TerminalItems.collectSubCategoryFilters(rows, mainKey)
	return GlobalStorageSiK.ItemTaxonomy.collectSubFilters(rows or {}, mainKey)
end

--- Filtra filas por categoría principal (vacío = todas).
---@param rows table[]
---@param mainKey string|nil
---@return table[]
function GlobalStorageSiK.TerminalItems.filterByMainCategory(rows, mainKey)
	if not mainKey or mainKey == "" then
		return rows
	end
	local EXT = GlobalStorageSiK.ItemTaxonomy.EXT_GROUP_PREFIX
	if mainKey:sub(1, #EXT) == EXT then
		-- Clave de familia canonica (groupKey, fuente unica - ver
		-- GS_ItemTaxonomy.lua resolve()/collectMainFilters): se compara por clave, NO
		-- solo por extGroupLabel, para incluir tambien los items "genericos"
		-- de la misma familia que no tienen division cualificada (antes se
		-- quedaban fuera del filtro sin que se notara, ya que rara vez se
		-- posee a la vez un item de cada variante).
		local group = string.lower(mainKey:sub(#EXT + 1))
		local filtered = {}
		for i = 1, #rows do
			local tax = GlobalStorageSiK.TerminalItems.rowTaxonomy(rows[i])
			if tax.groupKey and tax.groupKey ~= "" and string.lower(tax.groupKey) == group then
				filtered[#filtered + 1] = rows[i]
			end
		end
		return filtered
	end
	local key = string.lower(mainKey)
	local filtered = {}
	for i = 1, #rows do
		if GlobalStorageSiK.TerminalItems.rowTaxonomy(rows[i]).mainKey == key then
			filtered[#filtered + 1] = rows[i]
		end
	end
	return filtered
end

--- Recopila sub-subcategorías (Nivel 3) únicas, restringidas a Nivel 1 (y
--- Nivel 2, si se eligió).
---@param rows table[]
---@param mainKey string|nil
---@param subKey string|nil
---@return table[] { key: string, label: string, typeCount: number }
function GlobalStorageSiK.TerminalItems.collectLeafCategoryFilters(rows, mainKey, subKey)
	return GlobalStorageSiK.ItemTaxonomy.collectLeafFilters(rows or {}, mainKey, subKey)
end

--- Filtra filas por Nivel 2 (subcategoría, ej. "Perecedero" - vacío = todas).
--- Acepta CUALQUIER hoja de Nivel 3 dentro de ese subgrupo (fruta, queso,
--- carne perecederos...), no solo coincidencia exacta - misma fuente unica
--- (tax.groupKey/subGroupKey) que usa GS_Router.lua al depositar.
---@param rows table[]
---@param subKey string|nil clave con prefijo SUBGROUP_PREFIX
---@return table[]
function GlobalStorageSiK.TerminalItems.filterBySubCategory(rows, subKey)
	if not subKey or subKey == "" then
		return rows
	end
	local SUB = GlobalStorageSiK.ItemTaxonomy.SUBGROUP_PREFIX
	if subKey:sub(1, #SUB) ~= SUB then
		return rows
	end
	local rest = subKey:sub(#SUB + 1)
	local sepPos = rest:find("::", 1, true)
	if not sepPos then
		return rows
	end
	local wantGroup = string.lower(rest:sub(1, sepPos - 1))
	local wantSubGroup = string.lower(rest:sub(sepPos + 2))
	local filtered = {}
	for i = 1, #rows do
		local tax = GlobalStorageSiK.TerminalItems.rowTaxonomy(rows[i])
		if tax.groupKey and string.lower(tax.groupKey) == wantGroup
			and tax.subGroupKey and string.lower(tax.subGroupKey) == wantSubGroup then
			filtered[#filtered + 1] = rows[i]
		end
	end
	return filtered
end

--- Filtra filas por Nivel 3 (hoja final: tipo de comida, hueco de
--- joyeria/ropa, o tercer segmento con guion de un mod de categorias
--- extendidas - vacío = todas). Coincidencia EXACTA, es el nivel mas especifico.
---@param rows table[]
---@param leafKey string|nil
---@return table[]
function GlobalStorageSiK.TerminalItems.filterByLeafCategory(rows, leafKey)
	if not leafKey or leafKey == "" then
		return rows
	end
	local key = string.lower(leafKey)

	-- Clave compuesta "categoria::hueco" (joyeria O cualquier subcategoria
	-- vanilla cruda, ej. la prenda exacta de Ropa) - ver
	-- GS_ItemTaxonomy.lua:collectLeafFilters.
	local sepPos = key:find("::", 1, true)
	if sepPos then
		local mainPart = key:sub(1, sepPos - 1)
		local slotPart = key:sub(sepPos + 2)
		local filtered = {}
		for i = 1, #rows do
			local tax = GlobalStorageSiK.TerminalItems.rowTaxonomy(rows[i])
			if tax.mainKey == mainPart and (tax.jewelrySlotKey == slotPart or tax.subKey == slotPart) then
				filtered[#filtered + 1] = rows[i]
			end
		end
		return filtered
	end

	-- Hoja "plana": el tercer segmento con guion ya deja mainCanon completo
	-- y unico (ej. "foodperishablecheese"), coincidencia exacta contra mainKey.
	local filtered = {}
	for i = 1, #rows do
		if GlobalStorageSiK.TerminalItems.rowTaxonomy(rows[i]).mainKey == key then
			filtered[#filtered + 1] = rows[i]
		end
	end
	return filtered
end

---@param panel ISPanel
---@param fullType string|nil
---@return boolean
local function isRowSelected(panel, fullType)
	if not panel or not fullType or not panel._selectedKeys then
		return false
	end
	return panel._selectedKeys[fullType] == true
end

---@param panel ISPanel
local function clearRowSelection(panel)
	if panel then
		panel._selectedKeys = {}
		panel._selectionAnchor = nil
	end
end

--- Menú contextual de fila de ítem de la red.
---@param terminal GS_TerminalUI
---@param data table
---@param amount number
---@param targetKey string|nil
local function withdrawFromRowData(terminal, data, amount, targetKey)
	if terminal and data then
		terminal:onWithdrawRow(data, amount, targetKey)
	end
end

--- Retira usando inventario activo o bajo el ratón.
---@param terminal GS_TerminalUI
---@param data table
---@param amount number
local function withdrawRowWithActiveTarget(terminal, data, amount)
	if not terminal or not data then
		return
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getSpecificPlayer(0)
	local key = GlobalStorageSiK.ContainerTargets.resolveWithdrawTarget(player)
	terminal:onWithdrawRow(data, amount, key)
end

--- Construye titulo + descripcion (multi-linea, separador <LINE>) con los
--- datos utiles de un item de la red: tipo, categoria, peso unitario y
--- cantidad en esta red. Sin informacion de debug (no fullType interno de
--- Java, no ModData, etc.), solo lo que le interesa al jugador.
---@param fullType string
---@param data table|nil fila con count/category/subCategory
---@return string title
---@return string[] lines
local function buildItemDetailLines(fullType, data)
	local name = GlobalStorageSiK.I18n.itemDisplayName(fullType, data and data.displayName)
	local weightText = "?"
	-- Igual que GlobalStorageSiK.NetworkCapacity.estimateSnapshotWeight: prueba
	-- getActualWeight() primero, getWeight() como respaldo (en 42.20 no todos
	-- los script items resuelven getWeight() de forma fiable).
	if getScriptManager then
		local ok, w = pcall(function()
			local script = getScriptManager():getItem(fullType)
			if script and script.getActualWeight then
				return script:getActualWeight()
			end
			if script and script.getWeight then
				return script:getWeight()
			end
			return nil
		end)
		if ok and w then
			weightText = string.format("%.2f", w)
		end
	end
	local cat = GlobalStorageSiK.I18n.itemCategoryDisplay(fullType, data and data.category, data and data.subCategory, data and data.gsSubKeysStr)
	local count = data and data.count or 0
	local lines = {
		T("IGUI_GS_DetailType", fullType),
		T("IGUI_GS_DetailCategory", cat),
		T("IGUI_GS_DetailWeight", weightText),
		T("IGUI_GS_DetailCount", tostring(count)),
	}
	-- Desglose de OTRAS redes del jugador que tambien tengan este fullType
	-- (misma cache/fuente que el tooltip global vanilla, filtrada por
	-- Permissions.canAccess en el servidor: solo redes propias/con acceso,
	-- nunca de otros jugadores o facciones). La red activa ya se muestra
	-- arriba via "Cant." con el dato instantaneo del estado del terminal;
	-- aqui solo se añaden las DEMAS, para no duplicar la misma cifra.
	if GlobalStorageSiK.ItemNetworkTooltip and GlobalStorageSiK.ItemNetworkTooltip.getCachedCounts then
		local activeId = GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId
		local networks = GlobalStorageSiK.ItemNetworkTooltip.getCachedCounts(fullType)
		if networks then
			for i = 1, #networks do
				local n = networks[i]
				if n.id ~= activeId then
					lines[#lines + 1] = T("IGUI_GS_NetworkCountLine", n.name, tostring(n.count))
				end
			end
		end
	end
	return name, lines
end

--- Añade opción Examinar para ítems de la red (sin invocar menú vanilla).
---@param cm ISContextMenu
---@param player IsoPlayer|nil
---@param fullType string
local function addNetworkItemExamine(cm, player, fullType)
	if not cm or not fullType or not instanceItem then
		return
	end
	local probe = instanceItem(fullType)
	if not probe then
		return
	end
	local label = T("IGUI_GS_Examine")
	if getText then
		local ok, examine = pcall(getText, "ContextMenu_examine")
		if ok and examine and examine ~= "ContextMenu_examine" then
			label = examine
		else
			ok, examine = pcall(getText, "IGUI_invpanel_Inspect")
			if ok and examine and examine ~= "IGUI_invpanel_Inspect" then
				label = examine
			end
		end
	end
	cm:addOption(label, player, function(target)
		local p = target or player
		if not p or not p.setHaloNote then
			return
		end
		local sample = instanceItem(fullType)
		local text = sample and sample:getName() or fullType
		if sample and sample.getDescription then
			local desc = sample:getDescription()
			if desc and desc ~= "" then
				text = desc
			end
		end
		pcall(function()
			p:setHaloNote(text, 220, 220, 200, 450)
		end)
	end)
end

--- Menú contextual de fila de ítem.
---@param listPanel ISPanel
---@param terminal GS_TerminalUI
---@param data table
local function openItemContextMenu(listPanel, terminal, data)
	if not terminal or not data then
		return
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getSpecificPlayer(0)
	local playerNum = 0
	if player and player.getPlayerNum then
		playerNum = player:getPlayerNum()
	end

	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	local menuState = GlobalStorageSiK.ContextMenuUi.prepareTerminal(ui)

	local ok, err = pcall(function()
		local cm = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
		addNetworkItemExamine(cm, player, data.fullType)
		GlobalStorageSiK.NetworkReadAction.addToContext(cm, player, data, terminal)
		cm:addOption(T("IGUI_GS_ViewDetails"), player, function(target)
			local p = target or player
			if not p or not p.setHaloNote then return end
			local name, lines = buildItemDetailLines(data.fullType, data)
			pcall(function()
				p:setHaloNote(name .. " | " .. table.concat(lines, " | "), 220, 220, 200, 600)
			end)
		end)

		GlobalStorageSiK.WithdrawMenu.addFlatToContext(cm, player, data, function(rowData, amount, targetKey)
			withdrawFromRowData(terminal, rowData, amount, targetKey)
		end, getSelectedRows(listPanel))

		GlobalStorageSiK.ContextMenuUi.raiseMenu(cm)
	end)

	if not ok then
		GlobalStorageSiK.Log.error("TerminalUI", "openItemContextMenu failed", err)
		if menuState and menuState.ui then
			if menuState.wasVisible then
				menuState.ui:setVisible(true)
			end
			if menuState.wasAlwaysOnTop then
				menuState.ui:setAlwaysOnTop(true)
			end
		end
		return
	end

	GlobalStorageSiK.ContextMenuUi.scheduleTerminalRestore(menuState)
end

--- Crea fila de ítem (pool virtual o NIVirtualScrollView).
---@param scroll ISPanel
---@param listPanel ISPanel
---@param terminal GS_TerminalUI
---@return ISPanel
local function createItemRow(scroll, listPanel, terminal)
	local rowW = scroll.width or 200
	if scroll.getWidth then
		rowW = math.max(120, scroll:getWidth() - 8)
	end
	local row = ISPanel:new(0, 0, rowW, ROW_H)
	row:initialise()
	row.listPanel = listPanel
	row.terminal = terminal
	row.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	row.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	row._gsVirtualRow = true

	row.prerender = function(self)
		ISPanel.prerender(self)
		local data = self.itemData
		local selected = data and self.listPanel and isRowSelected(self.listPanel, data.fullType)
		GlobalStorageSiK.TerminalChrome.drawTableRowBackground(self, self.rowIndex, self:isMouseOver(), selected)
		if data and GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
			local types = GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes
			if types and data.fullType and types[data.fullType] then
				self:drawRect(0, 0, self.width, self.height, 0.25, 0.28, 0.28, 0.28)
			elseif GlobalStorageSiK.TerminalWithdrawDrag.activePreview
				and GlobalStorageSiK.TerminalWithdrawDrag.activePreview.fullType == data.fullType then
				self:drawRect(0, 0, self.width, self.height, 0.25, 0.28, 0.28, 0.28)
			end
		end
		if data then
			local pal = GlobalStorageSiK.TerminalChrome.PALETTE
			local tex = itemTexture(data)
			if tex then
				self:drawTextureScaledAspect(tex, 6, math.floor((self.height - ICON_SIZE) / 2), ICON_SIZE, ICON_SIZE, 1, 1, 1, 1)
			end
			local textX = 6 + ICON_SIZE + 8
			local name = GlobalStorageSiK.I18n.itemDisplayName(data.fullType, data.displayName, data.worldSprite)
			local cat = GlobalStorageSiK.I18n.itemCategoryDisplay(data.fullType, data.category, data.subCategory, data.gsSubKeysStr)
			local count = tostring(data.count or 0)
			local yMid = math.floor((self.height - FONT_HGT_SMALL) / 2)
			local catX = math.floor(self.width * 0.55)
			local nameMaxW = catX - textX - 8
			-- Reserva de espacio para la columna Cant. (numero corto, pero con
			-- margen holgado: hay contenedores con miles de unidades) antes de
			-- truncar la categoria - sin esto, una categoria/subcategoria larga
			-- (p.ej. "Herramienta / Arma - Arma de hoja corta") se dibujaba
			-- entera y se solapaba visualmente con la cantidad.
			local catMaxW = self.width - catX - 54
			self:drawText(truncateText(name, nameMaxW, UIFont.Small), textX, yMid, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
			self:drawText(truncateText(cat, catMaxW, UIFont.Small), catX, yMid, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small)
			self:drawTextRight(count, self.width - 8, yMid, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		end

		-- Tooltip al pasar el raton: en TODA la fila (icono/nombre/categoria)
		-- mostramos el mismo ISToolTipInv vanilla completo (comida, peso,
		-- estado, "cuanto tengo en red" + categoria detectada, ambos anadidos
		-- por GS_ItemNetworkTooltip.lua a CUALQUIER ISToolTipInv, incluido
		-- este). Ya no hace falta un tooltip de texto plano aparte para la
		-- columna Categoria (antes duplicaba la info que ahora ya sale aqui);
		-- si el texto no cabe en la columna, se trunca con "..." (ver
		-- drawText de arriba) y el detalle completo se lee en este tooltip.
		-- Se oculta mientras hay un arrastre activo (no tapar el preview de drop).
		if data and self:isMouseOver() and not GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
			local tooltipKey = tostring(data.fullType) .. "\31" .. tostring(data.worldSprite or "")
			if not self._gsTooltip or self._gsTooltip._gsItemKey ~= tooltipKey then
				local probe = itemProbe(data)
				if probe then
					if self._gsTooltip then
						self._gsTooltip:setItem(probe)
					else
						self._gsTooltip = ISToolTipInv:new(probe)
						self._gsTooltip:initialise()
						self._gsTooltip:setOwner(self)
						local ttPlayer = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getSpecificPlayer(0)
						self._gsTooltip:setCharacter(ttPlayer)
					end
					self._gsTooltip._gsItemKey = tooltipKey
				elseif self._gsTooltip then
					self._gsTooltip:removeFromUIManager()
					self._gsTooltip:setVisible(false)
					self._gsTooltip = nil
				end
			end
			if self._gsTooltip then
				self._gsTooltip:setVisible(true)
				self._gsTooltip:addToUIManager()
				self._gsTooltip:bringToTop()
			end
		else
			if self._gsTooltip and self._gsTooltip:isVisible() then
				self._gsTooltip:removeFromUIManager()
				self._gsTooltip:setVisible(false)
			end
		end
	end

	row.onMouseDown = function(self, x, y)
		if isRightMouseButtonDown and isRightMouseButtonDown() then
			return false
		end
		self._gsDragPending = true
		self._gsDragAccum = 0
		return true
	end

	row.onMouseMove = function(self, dx, dy)
		if not self._gsDragPending or not self.itemData or not self.terminal then
			return false
		end
		self._gsDragAccum = (self._gsDragAccum or 0) + math.abs(dx or 0) + math.abs(dy or 0)
		if self._gsDragAccum >= DRAG_THRESHOLD then
			self._gsDragPending = false
			local selection = getSelectedRows(self.listPanel)
			local rowSelected = isRowSelected(self.listPanel, self.itemData.fullType)
			local multiDrag = #selection > 1 and self.itemData and rowSelected
			-- amount=0 = "todo el stock de este fullType" (misma convencion que
			-- el menu de clic derecho). Antes se mandaba amount=1 a fuego: al
			-- arrastrar una fila con varias unidades solo se retiraba 1. El
			-- usuario pide que arrastrar mueva todo por defecto, y que las
			-- cantidades parciales queden solo para las opciones del menu.
			if multiDrag then
				GlobalStorageSiK.TerminalWithdrawDrag.begin(self.itemData, 0, selection)
			else
				GlobalStorageSiK.TerminalWithdrawDrag.begin(self.itemData, 0)
			end
			return true
		end
		return false
	end
	row.onMouseMoveOutside = row.onMouseMove

	row.onMouseUp = function(self, x, y)
		if GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
			return false
		end
		if self._gsDragPending and self.listPanel then
			self._gsDragPending = false
			handleRowClick(self.listPanel, self)
			return true
		end
		return false
	end

	row.onMouseDoubleClick = function(self, x, y)
		if self.itemData and self.terminal then
			withdrawRowWithActiveTarget(self.terminal, self.itemData, 1)
			return true
		end
		return false
	end

	row.onRightMouseUp = function(self, x, y)
		if self.itemData and self.listPanel and self.terminal then
			if not isRowSelected(self.listPanel, self.itemData.fullType) then
				selectSingleRow(self.listPanel, self.itemData.fullType, self.rowIndex)
			end
			openItemContextMenu(self.listPanel, self.terminal, self.itemData)
		end
		return true
	end

	return row
end

--- Actualiza fila con datos de ítem.
---@param row ISPanel
---@param data table|nil
local function updateItemRow(row, data)
	row.itemData = data
end

---@param panel ISPanel
local function bindItemRowIndex(row, data, panel)
	updateItemRow(row, data)
	row.rowIndex = nil
	if not data or not panel._lastItems then
		return
	end
	for i = 1, #panel._lastItems do
		local item = panel._lastItems[i]
		if item == data or (data.fullType and item.fullType == data.fullType) then
			row.rowIndex = i
			break
		end
	end
end

--- Actualiza filas visibles del pool virtual (legacy; NIVirtualScrollView no lo usa).
---@param listPanel ISPanel
function GlobalStorageSiK.TerminalItems.updateVirtualRows(listPanel)
	local scroll = listPanel and listPanel.itemScroll
	if scroll and scroll._gsScrollMode == "neat_virtual" then
		return
	end
	local items = listPanel and listPanel._lastItems
	if not scroll or not items or not listPanel.itemRowPool then
		return
	end

	local yScroll = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	local firstIdx = math.floor(yScroll / ROW_H) + 1
	local rowW = GlobalStorageSiK.TerminalScroll.contentWidth(scroll)

	for i = 1, #listPanel.itemRowPool do
		local row = listPanel.itemRowPool[i]
		local dataIdx = firstIdx + i - 1
		if dataIdx <= #items then
			row:setX(4)
			row:setY((i - 1) * ROW_H)
			row:setWidth(rowW)
			row.rowIndex = dataIdx
			updateItemRow(row, items[dataIdx])
			row:setVisible(true)
		else
			row:setVisible(false)
		end
	end
end

--- Cabecera de columnas ordenables.
---@param panel ISPanel
---@param terminal GS_TerminalUI
local function ensureColumnHeader(panel, terminal)
	if panel.columnHeader then
		return
	end
	panel.columnHeader = ISPanel:new(0, 0, panel.width, HEADER_H)
	panel.columnHeader:initialise()
	panel.columnHeader.drawBackground = false
	panel.columnHeader.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.columnHeader.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.columnHeader.prerender = function(self)
		ISPanel.prerender(self)
		GlobalStorageSiK.TerminalChrome.drawTableHeaderLine(self)
		local pal = GlobalStorageSiK.TerminalChrome.PALETTE
		local w = self.width
		local parent = self.parentPanel
		local sortKey = parent and parent.itemsSortKey or "displayName"
		local asc = parent and parent.itemsSortAsc ~= false
		local arrow = asc and " v" or " ^"
		local nameLbl = T("IGUI_GS_ColName") .. (sortKey == "displayName" and arrow or "")
		local catLbl = T("IGUI_GS_ColCategory") .. (sortKey == "category" and arrow or "")
		local cntLbl = T("IGUI_GS_ColCount") .. (sortKey == "count" and arrow or "")
		self:drawText(nameLbl, 6 + ICON_SIZE + 8, 2, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		self:drawText(catLbl, math.floor(w * 0.55), 2, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		self:drawTextRight(cntLbl, w - 12, 2, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
	end
	panel.columnHeader.parentPanel = panel
	panel.columnHeader.terminal = terminal
	panel.columnHeader.onMouseUp = function(self, x, y)
		local parent = self.parentPanel
		if not parent then
			return false
		end
		local w = self.width
		if x < w * 0.45 then
			parent.itemsSortKey = "displayName"
		elseif x < w * 0.78 then
			parent.itemsSortKey = "category"
		else
			parent.itemsSortKey = "count"
		end
		if parent.itemsSortKey == (parent._lastSortKey or "") then
			parent.itemsSortAsc = not parent.itemsSortAsc
		else
			parent.itemsSortAsc = true
		end
		parent._lastSortKey = parent.itemsSortKey
		parent._itemsScrollOffset = 0
		if self.terminal and self.terminal.refreshItemsTab then
			self.terminal:refreshItemsTab()
		elseif self.terminal then
			GlobalStorageSiK.TerminalItems.refresh(parent, self.terminal, parent._itemsCatalog or parent._lastItems or {})
		end
		return true
	end
	panel:addChild(panel.columnHeader)
end

--- Crea scroll de ítems (NIVirtualScrollView NeatUI; fallback pool legacy dinámico).
---@param panel ISPanel
---@param terminal GS_TerminalUI
local function disposeItemScroll(panel)
	if not panel or not panel.itemScroll then
		return
	end
	panel:removeChild(panel.itemScroll)
	if panel.itemScroll.removeFromUIManager then
		panel.itemScroll:removeFromUIManager()
	end
	if panel.itemScroll.destroy then
		panel.itemScroll:destroy()
	end
	panel.itemScroll = nil
	panel.itemRowPool = nil
	panel._usesNeatVirtual = nil
end

local function ensureItemScroll(panel, terminal)
	if panel.itemScroll and (panel.itemScroll._gsScrollMode == "neat_virtual" or panel.itemScroll._gsScrollMode == "rows") then
		return
	end
	disposeItemScroll(panel)

	local listGap = GlobalStorageSiK.TerminalScroll.listBottomGap()
	local scrollH = math.max(120, (panel.height or 200) - HEADER_H - listGap - 4)
	local scrollBarW = GlobalStorageSiK.TerminalChrome.scrollBarWidth()
	local itemW = math.max(120, (panel.width or 200) - scrollBarW - 8)

	local virtual = GlobalStorageSiK.TerminalScroll.createVirtual(panel, 0, HEADER_H + 2, panel.width, scrollH, ROW_H, 0)
	if virtual then
		panel.itemScroll = virtual
		panel._usesNeatVirtual = true
		virtual:setOnCreateItem(function()
			local row = createItemRow(virtual, panel, terminal)
			row:setWidth(itemW)
			return row
		end)
		virtual:setOnUpdateItem(function(row, data)
			bindItemRowIndex(row, data, panel)
		end)
		return
	end

	local scroll = GlobalStorageSiK.TerminalScroll.createLegacy(panel, 0, HEADER_H + 2, panel.width, scrollH, "rows")
	scroll._gsScrollBarGap = 12
	scroll._gsBarRightPad = 6
	panel.itemScroll = scroll
	panel.itemRowPool = {}

	local poolSize = GlobalStorageSiK.TerminalScroll.rowPoolSizeForViewport(scrollH, ROW_H)
	for i = 1, poolSize do
		local row = createItemRow(scroll, panel, terminal)
		row:setVisible(false)
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row)
		panel.itemRowPool[i] = row
	end

	scroll.onMouseWheel = function(self, del)
		GlobalStorageSiK.TerminalScroll.applyWheelDelta(self, del, ROW_H)
		panel._itemsScrollOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(self)
		GlobalStorageSiK.TerminalItems.updateVirtualRows(panel)
		return true
	end
	GlobalStorageSiK.TerminalScroll.bindScrollEvents(scroll, function()
		panel._itemsScrollOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
		GlobalStorageSiK.TerminalItems.updateVirtualRows(panel)
	end)

	local basePrerender = scroll.prerender
	scroll.prerender = function(self)
		if basePrerender then
			basePrerender(self)
		else
			ISPanel.prerender(self)
		end
		GlobalStorageSiK.TerminalItems.updateVirtualRows(panel)
	end
end

--- Lista opciones de depósito (jugador + contenedores cercanos).
---@param player IsoPlayer|nil
---@return table[]
function GlobalStorageSiK.TerminalItems.buildDepositSources(player)
	return GlobalStorageSiK.DepositSources.buildList(player)
end

--- Rellena combo de origen de depósito.
---@param combo ISComboBox
---@param player IsoPlayer|nil
function GlobalStorageSiK.TerminalItems.fillDepositCombo(combo, player)
	if not combo then
		return
	end
	combo:clear()
	local ok, sources = pcall(GlobalStorageSiK.TerminalItems.buildDepositSources, player)
	combo.depositSources = ok and sources or {}
	for i = 1, #combo.depositSources do
		combo:addOption(combo.depositSources[i].label)
	end
	combo.selected = 1
end

--- Obtiene índice de opción de depósito (1-based).
---@param combo ISComboBox
---@return number sourceIndex
function GlobalStorageSiK.TerminalItems.getDepositSelection(combo)
	if not combo then
		return 1
	end
	return combo.selected or 1
end

--- Fuerza actualización de filas visibles en NIVirtualScrollView.
---@param scroll ISUIElement|nil
local function forceVirtualListRefresh(scroll)
	if not scroll or scroll._gsScrollMode ~= "neat_virtual" or not scroll.refreshItems then
		return
	end
	scroll.visibleStartIndex = -1
	scroll.visibleEndIndex = -1
	scroll:refreshItems()
	if scroll.onUpdateItem and scroll.itemPool and scroll.dataSource then
		local startIndex = scroll.visibleStartIndex or 1
		local endIndex = scroll.visibleEndIndex or 0
		local poolIndex = 1
		for dataIndex = startIndex, endIndex do
			if poolIndex > #scroll.itemPool then
				break
			end
			local row = scroll.itemPool[poolIndex]
			local data = scroll.dataSource[dataIndex]
			if row and data then
				scroll.onUpdateItem(row, data)
				row:setVisible(true)
			end
			poolIndex = poolIndex + 1
		end
	end
end

--- Construye o refresca el scroll de ítems.
---@param panel ISPanel
---@param terminal GS_TerminalUI
---@param items table[]
function GlobalStorageSiK.TerminalItems.refresh(panel, terminal, items)
	if not panel then
		return
	end

	items = items or {}
	panel.itemsSortKey = panel.itemsSortKey or "displayName"
	panel.itemsSortAsc = panel.itemsSortAsc ~= false
	panel._selectedKeys = panel._selectedKeys or {}
	items = sortRows(items, panel.itemsSortKey, panel.itemsSortAsc)
	-- BUG REAL (Shift+Click seleccionaba rango incorrecto/inconsistente,
	-- reportado 2026-08-16): _lastItems se asignaba ANTES de ordenar, con la
	-- referencia SIN ORDENAR - pero sortRows() copia a una tabla NUEVA y
	-- distinta, que es la que de verdad se manda a la lista visual
	-- (setDataSource mas abajo). Toda la logica de seleccion (findItemIndex,
	-- selectRangeTo, bindItemRowIndex) buscaba posiciones en _lastItems, asi
	-- que operaba sobre un orden DISTINTO al que el jugador veia en pantalla
	-- - un indice de fila visual no correspondia al mismo indice en la lista
	-- sin ordenar, dando rangos de Shift+Click aparentemente aleatorios
	-- salvo que ambos ordenes coincidieran por casualidad. Fix: asignar
	-- _lastItems DESPUES de ordenar, con la MISMA tabla que se muestra.
	panel._lastItems = items

	ensureColumnHeader(panel, terminal)
	ensureItemScroll(panel, terminal)

	if panel.columnHeader then
		panel.columnHeader:setWidth(panel.width)
	end

	if #items == 0 then
		if panel.emptyLbl then
			panel.emptyLbl:setVisible(true)
		else
			local _epal = GlobalStorageSiK.TerminalChrome.PALETTE
			panel.emptyLbl = ISLabel:new(10, HEADER_H + 8, FONT_HGT_SMALL, T("IGUI_GS_NoItems"), _epal.textMuted[1], _epal.textMuted[2], _epal.textMuted[3], 1, UIFont.Small, true)
			panel.emptyLbl:initialise()
			panel:addChild(panel.emptyLbl)
		end
		if panel.itemScroll then
			panel.itemScroll:setVisible(false)
		end
	else
		if panel.emptyLbl then
			panel.emptyLbl:setVisible(false)
		end
		if panel.itemScroll then
			local listGap = GlobalStorageSiK.TerminalScroll.listBottomGap()
			local scrollH = math.max(120, panel.height - HEADER_H - listGap - 4)
			local savedOffset = panel._itemsScrollOffset
				or GlobalStorageSiK.TerminalScroll.getScrollOffset(panel.itemScroll)
			panel.itemScroll:setX(0)
			panel.itemScroll:setY(HEADER_H + 2)
			panel.itemScroll:setWidth(panel.width)
			panel.itemScroll:setHeight(scrollH)
			panel.itemScroll:setVisible(true)
			if panel.itemScroll._gsScrollMode == "neat_virtual" and panel.itemScroll.setDataSource then
				panel.itemScroll:setDataSource(items, true)
				-- forceVirtualListRefresh es imprescindible aqui: setDataSource
				-- por si sola solo cambia la referencia de datos, pero
				-- NIVirtualScrollView no vuelve a llamar onUpdateItem en filas
				-- YA visibles si el numero de filas y el scroll no cambian (solo
				-- lo hace al desplazarse a un indice nuevo). Sin esto, tras
				-- retirar/depositar sin cerrar la ventana, la fila seguia
				-- mostrando la cantidad vieja hasta cerrar y reabrir el
				-- Almacen (el usuario reporto justo este sintoma: cantidad
				-- visual desincronizada tras transferir desde el menu
				-- contextual, con los items moviendose bien de verdad).
				forceVirtualListRefresh(panel.itemScroll)
				GlobalStorageSiK.TerminalScroll.setScrollOffset(panel.itemScroll, savedOffset)
				GlobalStorageSiK.TerminalScroll.ensureScrollBars(panel.itemScroll)
				GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(
					panel.itemScroll, #items * ROW_H + 4 > scrollH + 2)
			else
				GlobalStorageSiK.TerminalScroll.setContentHeight(panel.itemScroll, math.max(scrollH, #items * ROW_H + 4))
				GlobalStorageSiK.TerminalScroll.setScrollOffset(panel.itemScroll, savedOffset)
				GlobalStorageSiK.TerminalScroll.ensureScrollBars(panel.itemScroll)
				GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(
					panel.itemScroll, #items * ROW_H + 4 > scrollH + 2)
				GlobalStorageSiK.TerminalItems.updateVirtualRows(panel)
			end
			panel._itemsScrollOffset = savedOffset
		end
	end
end

--- Solo geometría de la lista de ítems (resize); sin reconstruir datos.
---@param panel ISPanel|nil
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalItems.syncLayout(panel, terminal)
	if not panel then
		return
	end
	ensureColumnHeader(panel, terminal)
	if panel.columnHeader then
		panel.columnHeader:setWidth(panel.width)
	end
	if not panel.itemScroll then
		ensureItemScroll(panel, terminal)
	end
	if not panel.itemScroll then
		return
	end
	local items = panel._lastItems or {}
	local listGap = GlobalStorageSiK.TerminalScroll.listBottomGap()
	local scrollH = math.max(120, panel.height - HEADER_H - listGap - 4)
	local savedOffset = panel._itemsScrollOffset
		or GlobalStorageSiK.TerminalScroll.getScrollOffset(panel.itemScroll)
	panel.itemScroll:setX(0)
	panel.itemScroll:setY(HEADER_H + 2)
	panel.itemScroll:setWidth(panel.width)
	panel.itemScroll:setHeight(scrollH)
	panel.itemScroll:setVisible(#items > 0)
	if panel.itemScroll._gsScrollMode == "neat_virtual" then
		local scrollBarW = GlobalStorageSiK.TerminalChrome.scrollBarWidth()
		local itemW = math.max(120, panel.width - scrollBarW - 8)
		if panel.itemScroll.setConfig then
			panel.itemScroll:setConfig(ROW_H, 0)
		end
		if panel.itemScroll.itemPool then
			for _, row in ipairs(panel.itemScroll.itemPool) do
				if row and row.setWidth then
					row:setWidth(itemW)
				end
			end
		end
		if #items > 0 and panel.itemScroll.setDataSource then
			panel.itemScroll:setDataSource(items, false)
		end
		forceVirtualListRefresh(panel.itemScroll)
		GlobalStorageSiK.TerminalScroll.setScrollOffset(panel.itemScroll, savedOffset)
		GlobalStorageSiK.TerminalScroll.ensureScrollBars(panel.itemScroll)
		GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(
			panel.itemScroll, #items * ROW_H + 4 > scrollH + 2)
	elseif panel.itemScroll._gsScrollMode == "rows" and panel.itemRowPool then
		local needed = GlobalStorageSiK.TerminalScroll.rowPoolSizeForViewport(scrollH, ROW_H)
		while #panel.itemRowPool < needed do
			local row = createItemRow(panel.itemScroll, panel, terminal)
			row:setVisible(false)
			GlobalStorageSiK.TerminalScroll.addChild(panel.itemScroll, row)
			panel.itemRowPool[#panel.itemRowPool + 1] = row
		end
		if #items > 0 then
			GlobalStorageSiK.TerminalScroll.setContentHeight(panel.itemScroll, math.max(scrollH, #items * ROW_H + 4))
		end
		GlobalStorageSiK.TerminalScroll.setScrollOffset(panel.itemScroll, savedOffset)
		GlobalStorageSiK.TerminalScroll.ensureScrollBars(panel.itemScroll)
		GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(
			panel.itemScroll, #items * ROW_H + 4 > scrollH + 2)
		GlobalStorageSiK.TerminalItems.updateVirtualRows(panel)
	end
	panel._itemsScrollOffset = savedOffset
end

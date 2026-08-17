--[[
	GlobalStorageSiK - Pestaña Contenedores (tabla virtual + editor modal)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Lista agrupada por zonas; edición en modal.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Config"
require "GS_TerminalUI_NodeEditor"
require "GS_TerminalUI_ZoneEditor"
require "GS_NodeHighlight"
require "GS_TerminalUI_Chrome"

GlobalStorageSiK.TerminalNodes = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local ROW_H = FONT_HGT_SMALL + 10
local HEADER_H = FONT_HGT_SMALL + 10
local ROW_POOL_SIZE = 24
local MIN_EMBED_ROWS = 10
local SCROLLBAR_RESERVE = 14

--- True si la zona está colapsada (por defecto colapsada).
---@param collapsedZones table|nil
---@param zoneId string|nil
---@return boolean
local function zoneCollapsed(collapsedZones, zoneId)
	return collapsedZones[zoneId] ~= false
end

--- Alterna colapso de una zona en el mapa local.
---@param collapsedZones table
---@param zoneId string|nil
local function toggleZoneCollapsed(collapsedZones, zoneId)
	if zoneCollapsed(collapsedZones, zoneId) then
		collapsedZones[zoneId] = false
	else
		collapsedZones[zoneId] = true
	end
end

--- Ancho útil de filas reservando barra de scroll si hay desborde.
---@param scroll ISPanel|nil
---@return number
local function rowAreaWidth(scroll)
	local reserve = 0
	if scroll then
		local viewH = scroll.height or 0
		local contentH = scroll._gsContentHeight or viewH
		if contentH > viewH + 2 then
			reserve = SCROLLBAR_RESERVE + 4
		end
	end
	return math.max(120, (scroll and scroll.width or 0) - 8 - reserve)
end

--- Altura del viewport de scroll de la tabla de contenedores.
---@param panel ISPanel|nil
---@return number
local function nodeScrollViewportHeight(panel)
	local listGap = GlobalStorageSiK.TerminalScroll.listBottomGap()
	local minH = MIN_EMBED_ROWS * ROW_H
	local avail = math.max(80, (panel and panel.height or 200) - HEADER_H - listGap - 4)
	return math.max(minH, avail)
end

--- Altura total del panel embebido en pestaña Red.
---@param availableHeight number|nil alto que puede aprovechar al crecer la ventana
---@return number
function GlobalStorageSiK.TerminalNodes.embedPanelHeight(availableHeight)
	local listGap = GlobalStorageSiK.TerminalScroll.listBottomGap()
	local minimum = HEADER_H + 2 + MIN_EMBED_ROWS * ROW_H + listGap + 4
	return math.max(minimum, tonumber(availableHeight) or 0)
end

---@deprecated Usar GlobalStorageSiK.TerminalNodes.embedPanelHeight()
local function embedPanelHeight()
	return GlobalStorageSiK.TerminalNodes.embedPanelHeight()
end

--- Trunca texto al ancho máximo en píxeles.
---@param text string
---@param maxW number
---@param font UIFont|nil
---@return string
local function truncateText(text, maxW, font)
	return GlobalStorageSiK.TerminalChrome.truncateText(text, maxW, font or UIFont.Small)
end

-- Ancho reservado para la columna "Tipos" (siempre alineada a la derecha) y
-- separacion minima antes de ella. Antes "Prioridad" se calculaba como
-- max(statusX+90, w-150) SIN tener en cuenta el ancho real reservado para
-- "Tipos", asi que en paneles anchos ambas cabeceras (y valores) terminaban
-- solapandose ("Prioridatipos"). Ahora Prioridad se alinea a la derecha
-- justo antes del hueco de Tipos, con un margen fijo entre ambas.
local TYPES_COL_W = 60
local COL_GAP = 16

-- "Estado"/"Prioridad" seguian solapandose en la cabecera pese al tope
-- matematico (ver computeNodeColumns) porque los anchos reservados eran
-- CONSTANTES ADIVINADAS (60/90px) que no tenian en cuenta el ancho REAL del
-- texto traducido con la fuente del juego - en ES/otros idiomas "Prioridad"
-- (+ la flecha de orden " ^"/" v" cuando esa es la columna activa) podia
-- medir mas de los 90px reservados, invadiendo el hueco de "Estado" aunque
-- las cuentas fueran "correctas" sobre el papel. Ahora se mide el texto real
-- con getTextManager() una vez y se cachea (mismo idioma toda la sesion).
local _statusColW, _priorityColW
local function statusColW()
	if not _statusColW then
		local w = getTextManager():MeasureStringX(UIFont.Small, T("IGUI_GS_ColStatus") or "")
		_statusColW = math.max(50, math.floor(w) + 16)
	end
	return _statusColW
end
local function priorityColW()
	if not _priorityColW then
		-- Peor caso: columna activa de orden, con la flecha " v" anadida (ver headerLabel).
		local w = getTextManager():MeasureStringX(UIFont.Small, (T("IGUI_GS_ColNodePriority") or "") .. " v")
		_priorityColW = math.max(70, math.floor(w) + 16)
	end
	return _priorityColW
end

--- Etiqueta completa de una categoria de nodo: si es una subcategoria GS,
--- muestra "Principal / Sub" (ej. "Comida / Perecedero") en vez de solo el
--- nombre de la subcategoria en crudo. Separador ASCII simple (" / ") para
--- evitar glifos que el font del juego no tenga y rendericen como "?".
---@param key string|nil
---@return string
-- Los 5 huecos de joyeria reales (ver GS_Subcategories.lua:JEWELRY_SLOT_BUCKET) -
-- mismo enum ya establecido, no una lista nueva.
local JEWELRY_SLOT_KEYS_NODES = { ring = true, necklace = true, wrist = true, earring = true, nose = true }

local function fullCategoryLabel(key)
	if not key or key == "" then
		return T("IGUI_GS_CategoryAny")
	end
	local EXT = GlobalStorageSiK.ItemTaxonomy.EXT_GROUP_PREFIX
	local SUB = GlobalStorageSiK.ItemTaxonomy.SUBGROUP_PREFIX
	if key:sub(1, #EXT) == EXT then
		-- El sufijo es una clave canonica; se traduce solo al pintar.
		return GlobalStorageSiK.ItemTaxonomy.hierarchyLabel(key:sub(#EXT + 1), nil)
	end
	if key:sub(1, #SUB) == SUB then
		-- Clave de Nivel 2: "groupKey::subGroupKey", independiente del idioma.
		local rest = key:sub(#SUB + 1)
		local sepPos = rest:find("::", 1, true)
		if sepPos then
			local groupKey = rest:sub(1, sepPos - 1)
			local subKey = rest:sub(sepPos + 2)
			return GlobalStorageSiK.ItemTaxonomy.hierarchyLabel(groupKey, nil) .. " / "
				.. GlobalStorageSiK.ItemTaxonomy.hierarchyLabel(subKey, groupKey)
		end
		return rest
	end
	local sepPos = key:find("::", 1, true)
	if sepPos then
		-- Nivel 3 por combo (hueco de joyeria o subcategoria vanilla cruda).
		local mainPart = key:sub(1, sepPos - 1)
		local slotPart = key:sub(sepPos + 2)
		local mainLabel = GlobalStorageSiK.ItemTaxonomy.translateMainKey(mainPart)
		local slotLower = string.lower(slotPart)
		local slotLabel
		if JEWELRY_SLOT_KEYS_NODES[slotLower] and GlobalStorageSiK.Subcategories and GlobalStorageSiK.Subcategories.jewelrySlotLabel then
			slotLabel = GlobalStorageSiK.Subcategories.jewelrySlotLabel(slotLower)
		else
			slotLabel = GlobalStorageSiK.ItemTaxonomy.translateSubKey(slotPart, mainPart, nil) or slotPart
		end
		return mainLabel .. " / " .. slotLabel
	end
	local GSSub = GlobalStorageSiK.Subcategories
	if GSSub and GSSub.isSubcategoryKey(key) then
		local sub = GSSub.get(key)
		local mainLabel = GlobalStorageSiK.ItemTaxonomy.translateMainKey(sub and sub.parentCategory)
		local subLabel = GSSub.label(key)
		return mainLabel .. " / " .. subLabel
	end
	return GlobalStorageSiK.ItemTaxonomy.translateMainKey(key)
end

--- Calcula las posiciones X de las columnas de la tabla de nodos a partir
--- del ancho disponible. Unica fuente de verdad para cabecera y filas.
---@param w number
---@return number nameX, number catX, number statusX, number priorityRightX, number typesRightX
local function computeNodeColumns(w)
	local nameX = 8
	local catX = math.max(110, math.floor(w * 0.22))
	local typesRightX = w - 8
	local priorityRightX = typesRightX - TYPES_COL_W - COL_GAP
	local statusRightX = priorityRightX - priorityColW() - COL_GAP
	-- "Estado" es de ancho FIJO y estrecho (solo "OK"/"ERROR" — ver
	-- STATUS_COL_W); todo el espacio restante entre nombre y estado se lo
	-- lleva "Categoria", que ahora necesita bastante mas sitio para el
	-- formato combinado "Principal / Sub" (ej. "Comida / Perecedero").
	--
	-- IMPORTANTE: statusRightX - STATUS_COL_W es el UNICO valor que garantiza
	-- hueco frente a "Prioridad" (por construccion: statusRightX ya descuenta
	-- PRIORITY_COL_W + COL_GAP). Antes se usaba max(catX+170, ese valor), y en
	-- paneles de ancho "estandar" catX+170 ganaba y se colaba por delante del
	-- tope, solapando "Estado" con "Prioridad" en la cabecera. Ahora el tope
	-- manda siempre; catX+170 solo actua como suelo minimo cuando aun asi
	-- sobra sitio (paneles muy anchos), nunca puede empujar mas alla del tope.
	local statusX = statusRightX - statusColW()
	if statusX < catX + 4 then
		-- Panel extremadamente estrecho: ya no hay forma de dar holgura
		-- ideal, pero seguimos sin invadir "Prioridad" (ver arriba); el
		-- minimo caso limite es pegar "Estado" justo tras "Categoria".
		statusX = catX + 4
	end
	return nameX, catX, statusX, priorityRightX, typesRightX
end

--- Texto de estado del nodo para la tabla: solo indica si su inventario es
--- accesible para operar (OK) o no (ERROR), en vez de detalles internos de
--- membresia que confundian mas de lo que aclaraban (p.ej. "Detectado
--- automaticamente" sonaba a aviso, no a que todo funciona bien).
---@param node table
---@return string
local function nodeStatusText(node)
	if node.offline or node.enabled == false then
		return T("IGUI_GS_NodeStatusError")
	end
	return T("IGUI_GS_NodeStatusOk")
end

--- Color del texto de estado: rojo si el inventario no es accesible, verde si OK.
---@param node table
---@return number, number, number
local function nodeStatusColor(node)
	if node.offline or node.enabled == false then
		return 0.92, 0.35, 0.3
	end
	return 0.45, 0.85, 0.45
end

--- Ordena nodos por nombre visible (orden por defecto, sin cabecera clicada).
---@param nodes table[]
local function sortNodesByName(nodes)
	table.sort(nodes, function(a, b)
		return (a.displayName or a.name or ""):lower() < (b.displayName or b.name or ""):lower()
	end)
end

--- Valor comparable de un nodo para una columna concreta de la tabla.
---@param node table
---@param column string "name"|"category"|"status"|"priority"|"types"
---@return string|number
local function nodeSortValue(node, column)
	if column == "priority" then
		return tonumber(node.priority) or 50
	end
	if column == "types" then
		return tonumber(node.itemTypeCount) or 0
	end
	if column == "status" then
		return nodeStatusText(node)
	end
	if column == "category" then
		return fullCategoryLabel(node.categories and node.categories[1]):lower()
	end
	return (node.displayName or node.name or ""):lower()
end

--- Ordena una lista de nodos por la columna y direccion pedidas. Sin
--- columna (nil), mantiene el orden por nombre de siempre.
---@param nodes table[]
---@param column string|nil
---@param dir string|nil "asc"|"desc"
local function sortNodesByColumn(nodes, column, dir)
	if not column then
		sortNodesByName(nodes)
		return
	end
	local ascending = dir ~= "desc"
	table.sort(nodes, function(a, b)
		local va, vb = nodeSortValue(a, column), nodeSortValue(b, column)
		if va == vb then
			-- Desempate estable por nombre para que el orden no "salte" entre refrescos.
			local na, nb = (a.displayName or a.name or ""):lower(), (b.displayName or b.name or ""):lower()
			return ascending and (na < nb) or (na > nb)
		end
		if ascending then
			return va < vb
		end
		return va > vb
	end)
end

--- Construye filas de visualización agrupadas por zona (prioridad + colapso).
---@param nodes table[]
---@param zones table[]
---@param collapsedZones table|nil
---@param sortColumn string|nil columna clicada en la cabecera (nil = por nombre)
---@param sortDir string|nil "asc"|"desc"
---@return table[]
local function buildGroupedDisplayRows(nodes, zones, collapsedZones, sortColumn, sortDir)
	nodes = nodes or {}
	zones = zones or {}
	collapsedZones = collapsedZones or {}

	local zoneNames = {}
	local zonePriorities = {}
	local zoneOrder = {}
	for i = 1, #zones do
		local z = zones[i]
		if z and z.id then
			zoneNames[z.id] = z.name or z.id
			zonePriorities[z.id] = tonumber(z.priority) or 50
			zoneOrder[#zoneOrder + 1] = z.id
		end
	end

	-- El orden de cabecera de las zonas tambien respeta la columna clicada,
	-- cuando tiene sentido a nivel de zona: "name" (alfabetico) y "priority"
	-- (misma escala 1-100 que los contenedores). El resto de columnas
	-- (categoria/estado/tipos) no tienen un valor unico por zona, asi que
	-- las zonas se quedan en su orden de prioridad habitual y solo se
	-- reordenan los contenedores DENTRO de cada una (ver sortNodesByColumn
	-- mas abajo).
	if sortColumn == "name" or sortColumn == "priority" then
		local ascending = sortDir ~= "desc"
		table.sort(zoneOrder, function(a, b)
			local va, vb
			if sortColumn == "priority" then
				va, vb = zonePriorities[a] or 50, zonePriorities[b] or 50
			else
				va, vb = (zoneNames[a] or ""):lower(), (zoneNames[b] or ""):lower()
			end
			if va == vb then
				return ascending and (a < b) or (a > b)
			end
			if ascending then
				return va < vb
			end
			return va > vb
		end)
	end

	local byZone = {}
	local unknown = {}
	for i = 1, #nodes do
		local node = nodes[i]
		local zid = node.zoneId
		if zid and zid ~= "" then
			byZone[zid] = byZone[zid] or {}
			byZone[zid][#byZone[zid] + 1] = node
		else
			unknown[#unknown + 1] = node
		end
	end

	local rows = {}
	local function appendGroup(zoneId, zoneName, list)
		if not list or #list == 0 then
			return
		end
		sortNodesByColumn(list, sortColumn, sortDir)
		local collapsed = zoneCollapsed(collapsedZones, zoneId)
		rows[#rows + 1] = {
			kind = "zoneHeader",
			zoneId = zoneId,
			zoneName = zoneName,
			count = #list,
			zonePriority = zonePriorities[zoneId],
			collapsed = collapsed,
		}
		if not collapsed then
			for j = 1, #list do
				rows[#rows + 1] = { kind = "node", node = list[j] }
			end
		end
	end

	for i = 1, #zoneOrder do
		local zid = zoneOrder[i]
		appendGroup(zid, zoneNames[zid] or zid, byZone[zid])
		byZone[zid] = nil
	end

	for zid, list in pairs(byZone) do
		appendGroup(zid, zoneNames[zid] or zid, list)
	end

	if #unknown > 0 then
		appendGroup("", T("IGUI_GS_ZoneUnknown"), unknown)
	end

	return rows
end

--- Crea fila de tabla de contenedores.
---@param scroll ISPanel
---@param listPanel ISPanel
---@param terminal GS_TerminalUI
---@return ISPanel
local function createNodeRow(scroll, listPanel, terminal)
	local row = ISPanel:new(0, 0, scroll.width - 8, ROW_H)
	row:initialise()
	row.listPanel = listPanel
	row.terminal = terminal
	row.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	row.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	row._gsVirtualRow = true

	row.prerender = function(self)
		ISPanel.prerender(self)
		local data = self.rowData
		local yMid = math.floor((self.height - FONT_HGT_SMALL) / 2)
		local w = self.width
		local pal = GlobalStorageSiK.TerminalChrome.PALETTE

		if not data then
			return
		end

		if data.kind == "zoneHeader" then
			local hover = self:isMouseOver()
			GlobalStorageSiK.TerminalChrome.drawZoneHeaderBackground(self, hover)
			local arrow = data.collapsed and "+ " or "- "
			local title = arrow .. T("IGUI_GS_ZoneGroupHeader", data.zoneName or "—", data.count or 0)
			local _, _, _, priorityRightX = computeNodeColumns(w)
			local titleMaxW = math.max(40, priorityRightX - priorityColW() - 16)
			self:drawText(truncateText(title, titleMaxW, UIFont.Small), 8, yMid, hover and 1 or pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
			if data.zonePriority then
				self:drawTextRight(T("IGUI_GS_ZonePriorityValue", data.zonePriority), priorityRightX, yMid,
					pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
			end
			return
		end

		local editorInst = GlobalStorageSiK.TerminalNodeEditor and GlobalStorageSiK.TerminalNodeEditor.instance
		local isSelected = editorInst and editorInst.node and data.node and editorInst.node.id == data.node.id
		GlobalStorageSiK.TerminalChrome.drawTableRowBackground(self, self.rowIndex, self:isMouseOver(), isSelected)

		local node = data.node
		if not node then
			return
		end

		local nameX, catX, statusX, priorityRightX, typesRightX = computeNodeColumns(w)
		local name = node.displayName or node.name or "?"
		local cat = fullCategoryLabel(node.categories and node.categories[1])
		local status = nodeStatusText(node)
		local priority = tostring(node.priority or 50)
		local types = tostring(node.itemTypeCount or 0)
		local catW = statusX - catX - 8
		self:drawText(truncateText(name, catX - nameX - 8, UIFont.Small), nameX, yMid, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
		self:drawText(truncateText(cat, catW, UIFont.Small), catX, yMid, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small)
		local sr, sg, sb = nodeStatusColor(node)
		self:drawText(truncateText(status, priorityRightX - priorityColW() - statusX - 8, UIFont.Small), statusX, yMid, sr, sg, sb, 1, UIFont.Small)
		self:drawTextRight(priority, priorityRightX, yMid, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		self:drawTextRight(types, typesRightX, yMid, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)

		-- Tooltip de la columna Categoria: texto COMPLETO sin truncar (con
		-- niveles 1/2/3 desglosados, misma fuente que Almacen - ver
		-- GS_TerminalUI_Items.lua) + cuantas categorias mas acepta el
		-- contenedor si hay mas de una configurada.
		local overCatCol = self:isMouseOver() and self:getMouseX() >= catX and self:getMouseX() < statusX
		if overCatCol and node.categories and #node.categories > 0 then
			local firstKey = node.categories[1]
			local descLines = { T("IGUI_GS_CategoryTooltipMain", cat) }
			if #node.categories > 1 then
				descLines[#descLines + 1] = T("IGUI_GS_NodeMoreCategories", #node.categories - 1)
			end
			if not self._gsCatTooltip then
				self._gsCatTooltip = ISToolTip:new()
				self._gsCatTooltip:initialise()
				self._gsCatTooltip:instantiate()
				self._gsCatTooltip:setOwner(self)
			end
			self._gsCatTooltip:setName(T("IGUI_GS_CategoryTooltipTitle"))
			self._gsCatTooltip:setDescription(table.concat(descLines, " <LINE> "))
			self._gsCatTooltip:setVisible(true)
			self._gsCatTooltip:addToUIManager()
			self._gsCatTooltip:bringToTop()
		elseif self._gsCatTooltip and self._gsCatTooltip:isVisible() then
			self._gsCatTooltip:removeFromUIManager()
			self._gsCatTooltip:setVisible(false)
		end
	end

	row.onMouseUp = function(self, x, y, button)
		local data = self.rowData
		if not data or not self.listPanel then
			return false
		end
		local allNodes = self.listPanel._lastNodes or {}
		if data.kind == "zoneHeader" then
			-- El "+"/"-" de la izquierda (ver prerender) sigue plegando/
			-- desplegando con un clic normal en esa franja estrecha; el
			-- resto de la fila abre el editor de zona (renombrar, prioridad,
			-- eliminar), igual que clicar un contenedor abre su editor.
			if x < 20 then
				self.listPanel._collapsedZones = self.listPanel._collapsedZones or {}
				toggleZoneCollapsed(self.listPanel._collapsedZones, data.zoneId)
				if self.listPanel._onCollapseChanged then
					self.listPanel._onCollapseChanged()
				end
				if GlobalStorageSiK.NodeHighlight then
					GlobalStorageSiK.NodeHighlight.highlightZone(data.zoneId, data.zoneName, allNodes)
				end
				return true
			end
			if GlobalStorageSiK.NodeHighlight then
				GlobalStorageSiK.NodeHighlight.highlightZone(data.zoneId, data.zoneName, allNodes)
			end
			if self.terminal and self.terminal.canEditNetworkConfig
				and not self.terminal:canEditNetworkConfig(true) then return true end
			local zones = self.terminal and self.terminal.terminalState and self.terminal.terminalState.zones or {}
			local zoneObj = nil
			for i = 1, #zones do
				if zones[i].id == data.zoneId then
					zoneObj = zones[i]
					break
				end
			end
			if zoneObj and GlobalStorageSiK.TerminalZoneEditor then
				GlobalStorageSiK.TerminalZoneEditor.open(self.terminal, zoneObj, allNodes)
			end
			return true
		end
		if data.kind == "node" and data.node and self.terminal then
			if GlobalStorageSiK.NodeHighlight then
				GlobalStorageSiK.NodeHighlight.highlightNode(data.node, allNodes)
			end
			local state = self.terminal and self.terminal.terminalState or {}
			local playerRole = state.permissions and state.permissions.playerRole or "member"
			if playerRole ~= "member" and (not self.terminal.canEditNetworkConfig
				or self.terminal:canEditNetworkConfig(true)) then
				GlobalStorageSiK.TerminalNodeEditor.open(self.terminal, data.node, self.listPanel._categories or {})
			end
			return true
		end
		return false
	end

	row.onMouseDown = function(self, x, y)
		return self.rowData ~= nil
	end

	return row
end

--- Actualiza filas visibles del pool virtual.
---@param listPanel ISPanel
function GlobalStorageSiK.TerminalNodes.updateVirtualRows(listPanel)
	local scroll = listPanel and listPanel.nodeScroll
	local displayRows = listPanel and listPanel._displayRows
	if not scroll or not displayRows or not listPanel.nodeRowPool then
		return
	end

	local yScroll = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	local firstIdx = math.floor(yScroll / ROW_H) + 1
	local rowW = rowAreaWidth(scroll)

	for i = 1, #listPanel.nodeRowPool do
		local row = listPanel.nodeRowPool[i]
		local dataIdx = firstIdx + i - 1
		if dataIdx <= #displayRows then
			row:setX(4)
			row:setY((i - 1) * ROW_H)
			row:setWidth(rowW)
			row.rowIndex = dataIdx
			row.rowData = displayRows[dataIdx]
			row:setVisible(true)
		else
			row:setVisible(false)
		end
	end
end

--- Cabecera de columnas de la tabla de contenedores.
---@param panel ISPanel
local function ensureColumnHeader(panel)
	if panel.columnHeader then
		return
	end
	panel.columnHeader = ISPanel:new(0, 0, panel.width, HEADER_H)
	panel.columnHeader:initialise()
	panel.columnHeader.parentPanel = panel
	panel.columnHeader.drawBackground = false
	panel.columnHeader.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.columnHeader.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	--- Añade la flecha ▲/▼ al texto de cabecera si es la columna de orden activa.
	---@param self ISPanel
	---@param column string
	---@param label string
	---@return string
	local function headerLabel(self, column, label)
		if self.parentPanel and self.parentPanel.sortColumn == column then
			return label .. (self.parentPanel.sortDir == "desc" and " v" or " ^")
		end
		return label
	end

	panel.columnHeader.prerender = function(self)
		-- La cabecera se crea UNA sola vez (ensureColumnHeader hace early-return
		-- si ya existe) con el ancho del panel EN ESE MOMENTO. Si la ventana se
		-- redimensiona despues, las filas (que recalculan su ancho en cada
		-- updateVirtualRows via rowAreaWidth) se ajustan bien, pero la cabecera
		-- se quedaba con el ancho antiguo — desalineando "Estado"/"Prioridad"
		-- frente a las columnas reales de las filas. Ahora se resincroniza el
		-- ancho con el panel padre en cada prerender.
		if self.parentPanel and self.parentPanel.width and self.parentPanel.width ~= self.width then
			self:setWidth(self.parentPanel.width)
		end
		ISPanel.prerender(self)
		GlobalStorageSiK.TerminalChrome.drawTableHeaderLine(self)
		local pal = GlobalStorageSiK.TerminalChrome.PALETTE
		local w = self.width
		local nameX, catX, statusX, priorityRightX, typesRightX = computeNodeColumns(w)
		self:drawText(headerLabel(self, "name", T("IGUI_GS_ColName")), nameX, 2, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		self:drawText(headerLabel(self, "category", T("IGUI_GS_ColCategory")), catX, 2, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		self:drawText(headerLabel(self, "status", T("IGUI_GS_ColStatus")), statusX, 2, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		self:drawTextRight(headerLabel(self, "priority", T("IGUI_GS_ColNodePriority")), priorityRightX, 2, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		self:drawTextRight(headerLabel(self, "types", T("IGUI_GS_ColTypes")), typesRightX, 2, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
	end

	--- Clic en una cabecera de columna: ordena por esa columna, un clic
	--- alterna asc/desc, clicar otra columna reinicia a ascendente. Aplica a
	--- las 5 columnas (Nombre/Categoria/Estado/Prioridad/Tipos).
	panel.columnHeader.onMouseUp = function(self, x, y)
		local host = self.parentPanel
		if not host then
			return false
		end
		local w = self.width
		local nameX, catX, statusX, priorityRightX, typesRightX = computeNodeColumns(w)
		local column = nil
		if x >= nameX and x < catX then
			column = "name"
		elseif x >= catX and x < statusX then
			column = "category"
		elseif x >= statusX and x < priorityRightX - priorityColW() then
			column = "status"
		elseif x >= priorityRightX - priorityColW() and x < typesRightX - TYPES_COL_W then
			column = "priority"
		elseif x >= typesRightX - TYPES_COL_W then
			column = "types"
		end
		if not column then
			return false
		end
		if host.sortColumn == column then
			host.sortDir = (host.sortDir == "desc") and "asc" or "desc"
		else
			host.sortColumn = column
			host.sortDir = "asc"
		end
		host._displayRows = buildGroupedDisplayRows(host._lastNodes, host.terminalRef and host.terminalRef.terminalState and host.terminalRef.terminalState.zones or {}, host._collapsedZones, host.sortColumn, host.sortDir)
		GlobalStorageSiK.TerminalNodes.updateVirtualRows(host)
		return true
	end
	panel:addChild(panel.columnHeader)
end

--- Crea scroll virtual de contenedores.
---@param panel ISPanel
---@param terminal GS_TerminalUI
local function ensureNodeScroll(panel, terminal)
	if panel.nodeScroll and panel.nodeScroll._gsVirtualItems then
		return
	end
	if panel.nodeScroll then
		panel:removeChild(panel.nodeScroll)
		if panel.nodeScroll.removeFromUIManager then
			panel.nodeScroll:removeFromUIManager()
		end
		panel.nodeScroll = nil
		panel.nodeRowPool = nil
	end

	local scroll = GlobalStorageSiK.TerminalScroll.create(panel, 0, HEADER_H + 2, panel.width, 100, "rows")
	panel.nodeScroll = scroll
	panel.nodeRowPool = {}
	terminal.nodesScroll = scroll

	local listGap = GlobalStorageSiK.TerminalScroll.listBottomGap()
	local scrollH = math.max(80, (panel.height or 200) - HEADER_H - listGap - 4)
	local poolSize = GlobalStorageSiK.TerminalScroll.rowPoolSizeForViewport(scrollH, ROW_H)
	for i = 1, poolSize do
		local row = createNodeRow(scroll, panel, terminal)
		row:setVisible(false)
		GlobalStorageSiK.TerminalScroll.addChild(scroll, row)
		panel.nodeRowPool[i] = row
	end

	scroll.onMouseWheel = function(self, del)
		GlobalStorageSiK.TerminalScroll.applyWheelDelta(self, del, ROW_H)
		panel._nodesScrollOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(self)
		GlobalStorageSiK.TerminalNodes.updateVirtualRows(panel)
		return true
	end
	GlobalStorageSiK.TerminalScroll.bindScrollEvents(scroll, function()
		panel._nodesScrollOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
		GlobalStorageSiK.TerminalNodes.updateVirtualRows(panel)
	end)

	local basePrerender = scroll.prerender
	scroll.prerender = function(self)
		if basePrerender then
			basePrerender(self)
		else
			ISPanel.prerender(self)
		end
		GlobalStorageSiK.TerminalNodes.updateVirtualRows(panel)
	end
end

--- Construye panel de lista de contenedores en la pestaña.
---@param nodesPanel ISPanel
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalNodes.build(nodesPanel, terminal)
	if nodesPanel.nodesListPanel then
		return
	end
	local pad = terminal.padding or 8

	nodesPanel.nodesListPanel = ISPanel:new(pad, 0, 200, 120)
	nodesPanel.nodesListPanel:initialise()
	nodesPanel.nodesListPanel.drawBackground = false
	nodesPanel.nodesListPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	nodesPanel.nodesListPanel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	nodesPanel.nodesListPanel.clipChildren = true
	nodesPanel.nodesListPanel:setScrollWithParent(false)
	nodesPanel.nodesListPanel.prerender = function(self)
		ISPanel.prerender(self)
		GlobalStorageSiK.TerminalChrome.drawCardBackground(self, 0)
	end
	nodesPanel:addChild(nodesPanel.nodesListPanel)

	nodesPanel.nodesListPanel.terminalRef = terminal
	ensureColumnHeader(nodesPanel.nodesListPanel)
	ensureNodeScroll(nodesPanel.nodesListPanel, terminal)

	nodesPanel.nodesListPanel.emptyLbl = ISLabel:new(
		10, HEADER_H + 8, FONT_HGT_SMALL, T("IGUI_GS_NoNodesYet"),
		0.65, 0.68, 0.72, 1, UIFont.Small, true
	)
	nodesPanel.nodesListPanel.emptyLbl:initialise()
	nodesPanel.nodesListPanel.emptyLbl:setVisible(false)
	nodesPanel.nodesListPanel:addChild(nodesPanel.nodesListPanel.emptyLbl)
end

--- Refresca tabla de contenedores agrupada por zona.
---@param nodesPanel ISPanel
---@param terminal GS_TerminalUI
---@param nodes table[]
---@param categories string[]
function GlobalStorageSiK.TerminalNodes.refresh(nodesPanel, terminal, nodes, categories)
	if not nodesPanel or not nodesPanel.nodesListPanel then
		return
	end
	local panel = nodesPanel.nodesListPanel
	nodes = nodes or {}
	categories = categories or {}
	-- Migracion best-effort de las reglas v1 que persistian etiquetas del
	-- idioma del cliente. Se ejecuta al recibir la lista de Nodos, no obliga a
	-- abrir cada editor. El servidor conserva su validacion normal de permisos.
	panel._canonicalMigrationSent = panel._canonicalMigrationSent or {}
	local catalog = GlobalStorageSiK.ItemTaxonomy.getFullCatalogRows()
	local configLocked = terminal and terminal.canEditNetworkConfig
		and not terminal:canEditNetworkConfig(false)
	if not configLocked then
		for i = 1, #nodes do
			local node = nodes[i]
			local migrated = {}
			local changed = false
			local seen = {}
			for _, rule in ipairs(node.categories or {}) do
				local canonical = GlobalStorageSiK.ItemTaxonomy.canonicalizeFilterRule(rule, catalog)
				if canonical ~= rule then changed = true end
				local sig = string.lower(canonical)
				if not seen[sig] then
					seen[sig] = true
					migrated[#migrated + 1] = canonical
				end
			end
			if changed then
				node.categories = migrated
				if node.id and not panel._canonicalMigrationSent[node.id] then
					panel._canonicalMigrationSent[node.id] = true
					GlobalStorageSiK.TerminalNodeEditor.sendNodeUpdate(node.id, { categories = migrated })
				end
			end
		end
	end
	local zones = terminal and terminal.terminalState and terminal.terminalState.zones or {}
	panel._lastNodes = nodes
	panel._displayRows = buildGroupedDisplayRows(nodes, zones, panel._collapsedZones, panel.sortColumn, panel.sortDir)
	panel._categories = categories

	ensureNodeScroll(panel, terminal)
	if panel.columnHeader then
		panel.columnHeader:setWidth(panel.width)
	end

	local hasRows = #(panel._displayRows or {}) > 0
	if not hasRows then
		panel.emptyLbl:setVisible(true)
		if panel.nodeScroll then
			panel.nodeScroll:setVisible(false)
		end
	else
		panel.emptyLbl:setVisible(false)
		if panel.nodeScroll then
			local listGap = GlobalStorageSiK.TerminalScroll.listBottomGap()
			local scrollH = nodeScrollViewportHeight(panel)
			local savedOffset = panel._nodesScrollOffset
				or GlobalStorageSiK.TerminalScroll.getScrollOffset(panel.nodeScroll)
			panel.nodeScroll:setX(0)
			panel.nodeScroll:setY(HEADER_H + 2)
			panel.nodeScroll:setWidth(panel.width)
			panel.nodeScroll:setHeight(scrollH)
			panel.nodeScroll:setVisible(true)
			GlobalStorageSiK.TerminalScroll.setContentHeight(
				panel.nodeScroll, math.max(scrollH, #(panel._displayRows or {}) * ROW_H + 4)
			)
			if panel.nodeRowPool then
				local needed = GlobalStorageSiK.TerminalScroll.rowPoolSizeForViewport(scrollH, ROW_H)
				while #panel.nodeRowPool < needed do
					local row = createNodeRow(panel.nodeScroll, panel, panel.terminalRef or terminal)
					row:setVisible(false)
					GlobalStorageSiK.TerminalScroll.addChild(panel.nodeScroll, row)
					panel.nodeRowPool[#panel.nodeRowPool + 1] = row
				end
			end
			GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(
				panel.nodeScroll, #(panel._displayRows or {}) * ROW_H + 4 > scrollH + 2
			)
			GlobalStorageSiK.TerminalScroll.ensureScrollBars(panel.nodeScroll)
			GlobalStorageSiK.TerminalScroll.setScrollOffset(panel.nodeScroll, savedOffset)
			panel._nodesScrollOffset = savedOffset
			GlobalStorageSiK.TerminalNodes.updateVirtualRows(panel)
		end
	end

	if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.reapplyAfterRefresh then
		GlobalStorageSiK.NodeHighlight.reapplyAfterRefresh(nodes)
	end
end

--- Ajusta geometría del panel de lista.
---@param nodesPanel ISPanel
---@param innerW number
---@param innerH number
---@param pad number
---@param yStart number
function GlobalStorageSiK.TerminalNodes.layout(nodesPanel, innerW, innerH, pad, yStart)
	if not nodesPanel or not nodesPanel.nodesListPanel then
		return
	end
	local listH = math.max(120, innerH - yStart - pad)
	nodesPanel.nodesListPanel:setX(pad)
	nodesPanel.nodesListPanel:setY(yStart)
	nodesPanel.nodesListPanel:setWidth(innerW - pad * 2)
	nodesPanel.nodesListPanel:setHeight(listH)

	local panel = nodesPanel.nodesListPanel
	if panel.columnHeader then
		panel.columnHeader:setWidth(panel.width)
	end
	if panel.nodeScroll and panel._displayRows and #panel._displayRows > 0 then
		local scrollH = nodeScrollViewportHeight(panel)
		panel.nodeScroll:setWidth(panel.width)
		panel.nodeScroll:setHeight(scrollH)
		if panel.nodeRowPool then
			local needed = GlobalStorageSiK.TerminalScroll.rowPoolSizeForViewport(scrollH, ROW_H)
			while #panel.nodeRowPool < needed do
				local row = createNodeRow(panel.nodeScroll, panel, panel.terminalRef)
				row:setVisible(false)
				GlobalStorageSiK.TerminalScroll.addChild(panel.nodeScroll, row)
				panel.nodeRowPool[#panel.nodeRowPool + 1] = row
			end
		end
		GlobalStorageSiK.TerminalScroll.setContentHeight(
			panel.nodeScroll, math.max(scrollH, #panel._displayRows * ROW_H + 4)
		)
		GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(
			panel.nodeScroll, #panel._displayRows * ROW_H + 4 > scrollH + 2
		)
		GlobalStorageSiK.TerminalScroll.ensureScrollBars(panel.nodeScroll)
		GlobalStorageSiK.TerminalNodes.updateVirtualRows(panel)
	end
end

--- Crea los 3 botones de crear zona (Habitación/Edificio/Selección) dentro
--- de la sección Contenedores - mismos handlers que ya usa la sección
--- Zonas (terminal:onCreateRoomZone, etc.), no se duplica logica, solo se
--- ofrece el mismo atajo aqui tambien. Primer paso hacia gestionar zonas y
--- contenedores desde un solo sitio sin retirar todavia la seccion Zonas.
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param ui table
---@param pad number
---@param y number
---@return number y tras los botones
function GlobalStorageSiK.TerminalNodes.buildZoneCreateButtons(scroll, terminal, ui, pad, y)
	local btnH = FONT_HGT_SMALL + 8
	local maxW = 220
	local roomTitle = T("IGUI_GS_CreateRoomZone")
	local structTitle = T("IGUI_GS_CreateStructureZone")
	local selectTitle = T("IGUI_GS_CreateSelectionZone")
	ui.nodesRoomZoneBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad, y, maxW, btnH, roomTitle, scroll, function()
		terminal:onCreateRoomZone()
	end)
	ui.nodesRoomZoneBtn._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesRoomZoneBtn)
	local roomW = ui.nodesRoomZoneBtn.width
	ui.nodesStructureZoneBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad + roomW + 6, y, maxW, btnH, structTitle, scroll, function()
		terminal:onCreateStructureZone()
	end)
	ui.nodesStructureZoneBtn._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesStructureZoneBtn)
	local structW = ui.nodesStructureZoneBtn.width
	ui.nodesSelectZoneBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad + roomW + 6 + structW + 6, y, maxW, btnH, selectTitle, scroll, function()
		terminal:onCreateSelectionZone()
	end)
	ui.nodesSelectZoneBtn._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesSelectZoneBtn)
	return y + btnH + 10
end

--- Reposiciona (sin recrear) los botones de crear zona ya existentes.
---@param scroll ISPanel
---@param ui table
---@param pad number
---@param y number
---@return number y tras los botones
function GlobalStorageSiK.TerminalNodes.repositionZoneCreateButtons(scroll, ui, pad, y)
	local btnH = FONT_HGT_SMALL + 8
	if ui.nodesRoomZoneBtn then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.nodesRoomZoneBtn, pad)
		GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesRoomZoneBtn, y)
	end
	local roomW = ui.nodesRoomZoneBtn and ui.nodesRoomZoneBtn.width or 0
	if ui.nodesStructureZoneBtn then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.nodesStructureZoneBtn, pad + roomW + 6)
		GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesStructureZoneBtn, y)
	end
	local structW = ui.nodesStructureZoneBtn and ui.nodesStructureZoneBtn.width or 0
	if ui.nodesSelectZoneBtn then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.nodesSelectZoneBtn, pad + roomW + 6 + structW + 6)
		GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesSelectZoneBtn, y)
	end
	return y + btnH + 10
end

--- Incrusta lista de contenedores en scroll de pestaña Red (bloque 3).
---@param scroll ISPanel
---@param terminal GS_TerminalUI
---@param ui table
---@param y number
---@param innerW number
---@return number endY
function GlobalStorageSiK.TerminalNodes.embedInNetworkScroll(scroll, terminal, ui, y, innerW)
	local pad = 8
	local titleY = y
	local infoMaxW = innerW - pad * 2
	local infoLines = GlobalStorageSiK.TerminalChrome.wrapTextLines(T("IGUI_GS_NodesPriorityHelp"), infoMaxW, UIFont.Small)
	local infoH = #infoLines * (FONT_HGT_SMALL + 2) + 8
	local function heightFor(currentY)
		-- La ayuda queda visible debajo de la tabla. Si la ventana crece, todo
		-- el alto adicional se entrega al viewport virtual de filas; si es
		-- pequena se conserva el minimo y el scroll exterior cubre el resto.
		local available = (scroll.height or 0) - currentY - infoH - 24
		return GlobalStorageSiK.TerminalNodes.embedPanelHeight(available)
	end
	if not ui.nodesEmbedBuilt or not GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.nodesEmbedPanel) then
		ui.nodesEmbedBuilt = false
		local host = GlobalStorageSiK.TerminalScroll.childHost(scroll)
		for _, key in ipairs({ "nodesSectionTitle", "nodesHelpLbl", "nodesEmbedPanel",
			"nodesRoomZoneBtn", "nodesStructureZoneBtn", "nodesSelectZoneBtn" }) do
			local w = ui[key]
			if w and host then
				GlobalStorageSiK.TerminalScroll.disposeChild(host, w)
			end
			ui[key] = nil
		end
		if ui.nodesPriorityInfoLbls and host then
			for _, w in ipairs(ui.nodesPriorityInfoLbls) do
				GlobalStorageSiK.TerminalScroll.disposeChild(host, w)
			end
		end
		ui.nodesPriorityInfoLbls = nil
		ui.collapsedZones = ui.collapsedZones or {}
		ui.nodesSectionTitle = GlobalStorageSiK.TerminalChrome.createSectionLabel(pad, titleY, T("IGUI_GS_SectionNodes"))
		ui.nodesSectionTitle._gsNetStatic = true
		GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesSectionTitle)
		y = titleY + FONT_HGT_SMALL + 6
		ui.nodesHelpLbl = GlobalStorageSiK.TerminalChrome.createHintLabel(pad, y, T("IGUI_GS_NodesHelpShort"))
		ui.nodesHelpLbl._gsNetStatic = true
		GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesHelpLbl)
		y = y + FONT_HGT_SMALL + 8
		-- Bloque de creacion de zonas, tambien disponible aqui (ademas de en
		-- la seccion Zonas, que no se retira todavia) - primer paso hacia la
		-- gestion unificada de zonas+contenedores desde un solo sitio.
		y = GlobalStorageSiK.TerminalNodes.buildZoneCreateButtons(scroll, terminal, ui, pad, y)
		ui.nodesEmbedHeight = heightFor(y)
		ui.nodesEmbedPanel = ISPanel:new(0, y, innerW, ui.nodesEmbedHeight)
		ui.nodesEmbedPanel:initialise()
		ui.nodesEmbedPanel.drawBackground = false
		ui.nodesEmbedPanel._gsNetStatic = true
		ui.nodesEmbedPanel._gsEmbedMode = true
		ui.nodesEmbedPanel.clipChildren = true
		ui.nodesEmbedPanel.prerender = function(self)
			ISPanel.prerender(self)
			local pal = GlobalStorageSiK.TerminalChrome.PALETTE
			local br = pal.border
			self:drawRectBorder(0, 0, self.width, self.height, 0.2, br[1] * 0.35, br[2] * 0.35, br[3] * 0.35)
		end
		GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesEmbedPanel)
		GlobalStorageSiK.TerminalNodes.build(ui.nodesEmbedPanel, terminal)
		ui.nodesEmbedPanel._collapsedZones = ui.collapsedZones
		ui.nodesEmbedPanel._onCollapseChanged = function()
			GlobalStorageSiK.TerminalNodes.refresh(
				ui.nodesEmbedPanel, terminal,
				terminal.terminalState and terminal.terminalState.nodes or {},
				terminal.terminalState and terminal.terminalState.categories or {}
			)
		end
		-- Row.listPanel apunta al inner nodesListPanel; hay que exponer el callback allí.
		if ui.nodesEmbedPanel.nodesListPanel then
			ui.nodesEmbedPanel.nodesListPanel._onCollapseChanged = ui.nodesEmbedPanel._onCollapseChanged
		end
		ui.nodesEmbedBuilt = true
		ui.nodesEmbedY = y
		-- Bloque informativo inferior (pedido explicito): explica los 4
		-- niveles de especificidad que usa GS_Router.matchSpecificity para
		-- depositar/auto-ordenar, en el mismo texto plano que ya se usa para
		-- explicarselo al jugador en el chat - evita que el sistema parezca
		-- "aleatorio" cuando en realidad sigue un orden fijo y documentado.
		local infoY = y + ui.nodesEmbedHeight + 8
		ui.nodesPriorityInfoLbls = {}
		for _, line in ipairs(infoLines) do
			local lbl = ISLabel:new(pad, infoY, FONT_HGT_SMALL, line, 0.62, 0.66, 0.7, 1, UIFont.Small, true)
			lbl:initialise()
			lbl._gsNetStatic = true
			GlobalStorageSiK.TerminalScroll.addChild(scroll, lbl)
			ui.nodesPriorityInfoLbls[#ui.nodesPriorityInfoLbls + 1] = lbl
			infoY = infoY + FONT_HGT_SMALL + 2
		end
		ui.nodesPriorityInfoEndY = infoY
	else
		if ui.nodesSectionTitle then
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.nodesSectionTitle, pad)
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesSectionTitle, titleY)
		end
		y = titleY + FONT_HGT_SMALL + 6
		if ui.nodesHelpLbl then
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.nodesHelpLbl, pad)
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesHelpLbl, y)
		end
		y = y + FONT_HGT_SMALL + 8
		y = GlobalStorageSiK.TerminalNodes.repositionZoneCreateButtons(scroll, ui, pad, y)
		ui.nodesEmbedY = y
		ui.nodesEmbedHeight = heightFor(y)
		if ui.nodesPriorityInfoLbls and #ui.nodesPriorityInfoLbls > 0 then
			local infoY = y + ui.nodesEmbedHeight + 8
			for _, lbl in ipairs(ui.nodesPriorityInfoLbls) do
				GlobalStorageSiK.TerminalScroll.setContentX(scroll, lbl, pad)
				GlobalStorageSiK.TerminalScroll.setContentY(scroll, lbl, infoY)
				infoY = infoY + FONT_HGT_SMALL + 2
			end
			ui.nodesPriorityInfoEndY = infoY
		end
	end
	local configEnabled = not terminal.canEditNetworkConfig
		or terminal:canEditNetworkConfig(false)
	for _, button in ipairs({ ui.nodesRoomZoneBtn, ui.nodesStructureZoneBtn, ui.nodesSelectZoneBtn }) do
		if button then button:setEnable(configEnabled) end
	end

	local embedH = ui.nodesEmbedHeight or heightFor(y)
	if GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.nodesEmbedPanel) then
		GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesEmbedPanel, y)
		ui.nodesEmbedPanel:setWidth(innerW)
		ui.nodesEmbedPanel:setHeight(embedH)
		GlobalStorageSiK.TerminalNodes.layout(ui.nodesEmbedPanel, innerW, embedH, 0, 0)
		GlobalStorageSiK.TerminalNodes.refresh(
			ui.nodesEmbedPanel, terminal,
			terminal.terminalState and terminal.terminalState.nodes or {},
			terminal.terminalState and terminal.terminalState.categories or {}
		)
		local infoH = ui.nodesPriorityInfoLbls and (#ui.nodesPriorityInfoLbls * (FONT_HGT_SMALL + 2) + 8) or 0
		return y + embedH + 12 + infoH
	end
	ui.nodesEmbedBuilt = false
	return titleY + FONT_HGT_SMALL + 12
end

--[[
	GlobalStorageSiK - Pestaña Contenedores (tabla virtual + editor modal)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Lista agrupada por zonas; edición en modal.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_Config"
require "GS_I18n"
require "GS_TerminalUI_Scroll"
require "GS_TerminalUI_Config"
require "GS_TerminalUI_NodeEditor"
require "GS_TerminalUI_ZoneEditor"
require "GS_NodeHighlight"
require "GS_SiK_UI_Core"
require "GS_SiK_UI_Table"
require "GS_RulesUI"

GlobalStorageSiK.TerminalNodes = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local TABLE_METRICS = GlobalStorageSiK.SiK_UI.Table.metrics()
local ROW_H = TABLE_METRICS.rowHeight
local HEADER_H = TABLE_METRICS.headerHeight
local ROW_POOL_SIZE = 24
local MIN_EMBED_ROWS = 10

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

--- Ancho útil canónico de filas. Block reserva siempre el gutter, exista o no
--- overflow; tabla y filas no vuelven a calcular una barra local.
---@param scroll ISPanel|nil
---@return number
local function rowAreaWidth(scroll)
	return math.max(120, GlobalStorageSiK.TerminalScroll.contentWidth(scroll))
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
	return GlobalStorageSiK.SiK_UI.truncateText(text, maxW, font or UIFont.Small)
end

local COL_GAP = 8

-- "Estado"/"Prioridad"/"% Ocupación" seguian solapandose con "Protocolo"
-- pese al tope matematico por DOS motivos
-- distintos, corregidos aqui a la vez (pedido explicito del usuario, con
-- capturas): (1) los anchos reservados no median el texto REAL con la
-- fuente del juego, y (2) el ancho de truncado de "Protocolo" (ver mas
-- abajo, donde se dibuja) usaba como limite el borde derecho de la columna
-- "Estado" en vez de su borde IZQUIERDO, dejando que un resumen de reglas
-- largo se solapara visualmente con el texto de Estado. Cada columna
-- estrecha ahora considera tambien el PEOR VALOR real que puede mostrar
-- (p.ej. "Excluido"/"Excluded" en Estado, "100"/"100%" en Prioridad/
-- Ocupación), no solo su cabecera - mostrar el valor completo importa mas
-- que la cabecera.
-- Anchos ESTANDARIZADOS y CENTRADOS (dev24/dev25): las 3 columnas usan el
-- mismo criterio de alineacion (antes mezclado: Prioridad/% a la derecha,
-- Estado a la izquierda) y valores siempre cortos (100, OK/OFF/ERR, 100%).
-- BUG REAL de dev24 corregido en dev25 (captura del usuario: cabeceras
-- "P.."/"Es.." truncadas e ilegibles in-game): un numero de pixeles fijo
-- adivinado (34/42/46) bastaba para los VALORES pero no para las cabeceras
-- ("Prio."/"Estado" son mas largas que "100"/"OK") - la reserva tiene que
-- medir la fuente REAL del juego (como antes de dev24), incluyendo la
-- cabecera CON la flecha de orden (" v"/" ^") ademas del peor valor corto -
-- eso sigue dando un ancho pequeno y constante porque todos los textos son
-- cortos, pero ya no se trunca nada. Desde dev33 esas medidas viven solo en
-- NODE_TABLE_COLUMNS: cabecera, filas y deteccion de clic consumen el mismo
-- layout resuelto por SiK_UI.Table.

--- La ruta categórica usa color L1. Los colores de operador quedan reservados
--- a los puntos y a las tarjetas OR/AND/NOT de los editores.
-- Azul apagado para "heredado de la zona, sin regla propia" - mismo tono
-- que el bloque "Heredado de tu zona" del editor de contenedor.
local INHERIT_COLOR = { 0.36, 0.48, 0.58 }

--- Decide que mostrar en la columna "Protocolo" para un contenedor: reglas
--- PROPIAS (color por operador dominante, con "+N" si hay mas de una),
--- heredadas de zona si no tiene propias pero la zona si (azul apagado, sin
--- puntos), o "Global" (sin restriccion en ningun nivel) - nunca "Global"
--- si la zona restringe, aunque el contenedor no tenga reglas propias (ver
--- GS_Router.zoneRulesAllow: la zona filtra igual).
---@param ownRules table|nil
---@param zoneRules table|nil
---@return string label, number r, number g, number b, boolean showDots
local function nodeProtocolInfo(ownRules, zoneRules)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	if ownRules and #ownRules > 0 then
		local sum = GlobalStorageSiK.RulesUI.compactSummary(ownRules)
		if sum then
			local c = GlobalStorageSiK.RulesUI.conditionColor(
				sum.condition, pal.textSecondary)
			local label = sum.label
			if sum.extraCount > 0 then
				label = label .. " +" .. tostring(sum.extraCount)
			end
			return label, c[1], c[2], c[3], true
		end
	end
	if zoneRules and #zoneRules > 0 then
		local zsum = GlobalStorageSiK.RulesUI.compactSummary(zoneRules)
		if zsum then
			local c = GlobalStorageSiK.RulesUI.conditionColor(zsum.condition, INHERIT_COLOR)
			return zsum.label, c[1], c[2], c[3], false
		end
	end
	return T("IGUI_GS_ProtocolGlobal"), pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], false
end

-- Geometria fija del hueco de los 3 puntos de composicion en la columna
-- Protocolo - unica fuente de verdad, reutilizada tanto al DIBUJAR los
-- puntos como al RESERVAR el hueco cuando no se dibujan (herencia/Global).
-- Antes el texto arrancaba en protocolX cuando no habia puntos y en
-- protocolX+31 cuando si los habia, dejando la columna con el borde
-- izquierdo escalonado fila a fila - "no bien cuadrada" (feedback directo
-- del usuario con captura, dev26 ronda 4). Reservar SIEMPRE el mismo hueco
-- cuadra la columna de verdad.
local PROTOCOL_DOT_SIZE, PROTOCOL_DOT_GAP, PROTOCOL_DOTS_COUNT, PROTOCOL_TEXT_GAP = 6, 3, 3, 4
local PROTOCOL_DOTS_RESERVED_W = PROTOCOL_DOTS_COUNT * (PROTOCOL_DOT_SIZE + PROTOCOL_DOT_GAP) + PROTOCOL_TEXT_GAP

-- Modelo canónico de tabla SiK UI. Esta tabla fue la referencia visual para
-- el resto del framework; desde dev33 su geometría deja de ser una excepción
-- local y pasa por el mismo descriptor que usan cabecera, filas y clics.
local NODE_TABLE_COLUMNS = {
	{ key = "name", titleKey = "IGUI_GS_ColName", flex = 1, minWidth = 120, pad = 6 },
	{ key = "protocol", titleKey = "IGUI_GS_ColProtocol", flex = 1.7, minWidth = 180,
		hardMinWidth = 180, pad = 6, contentLeading = PROTOCOL_DOTS_RESERVED_W,
		contentTrailing = 4 },
	{ key = "priority", titleKey = "IGUI_GS_ColPriority", width = 60, align = "center", pad = 6 },
	{ key = "status", titleKey = "IGUI_GS_ColStatus", width = 76, align = "center", pad = 6 },
	{ key = "occupancy", titleKey = "IGUI_GS_ColOccupancy", width = 60, align = "right", pad = 6 },
}
local NODE_TABLE_OPTIONS = { left = 0, right = 0, gap = COL_GAP }

--- Dibuja los 3 puntos de composicion (OR/AND/NOT - relleno si ese operador
--- tiene al menos una regla propia, hueco si no) antes del texto de
--- Protocolo. Devuelve la X donde debe empezar el texto (siempre
--- x+PROTOCOL_DOTS_RESERVED_W).
---@param panel ISUIElement
---@param x number
---@param yMid number
---@param rules table
---@return number textX
local function drawProtocolDots(panel, x, yMid, rules)
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local hasOr, hasAnd, hasNot = false, false, false
	for i = 1, #rules do
		local rule = rules[i]
		if type(rule) == "table" and type(rule.condition) == "table"
			and not GlobalStorageSiK.RuleSanitizer.isJunkCategoryCondition(rule.condition) then
			if rule.op == "OR" then hasOr = true
			elseif rule.op == "AND" then hasAnd = true
			elseif rule.op == "NOT" then hasNot = true end
		end
	end
	local dy = yMid + math.floor((FONT_HGT_SMALL - PROTOCOL_DOT_SIZE) / 2)
	local specs = { { hasOr, pal.ruleOr }, { hasAnd, pal.ruleAnd }, { hasNot, pal.ruleNot } }
	local dx = x
	for i = 1, #specs do
		local on, color = specs[i][1], specs[i][2]
		if on then
			panel:drawRect(dx, dy, PROTOCOL_DOT_SIZE, PROTOCOL_DOT_SIZE, 1, color[1], color[2], color[3])
		else
			panel:drawRectBorder(dx, dy, PROTOCOL_DOT_SIZE, PROTOCOL_DOT_SIZE, 0.5, 0.3, 0.3, 0.3)
		end
		dx = dx + PROTOCOL_DOT_SIZE + PROTOCOL_DOT_GAP
	end
	return x + PROTOCOL_DOTS_RESERVED_W
end

local function protocolContentLayout(protocolCol)
	local leading = protocolCol.spec and protocolCol.spec.contentLeading
		or PROTOCOL_DOTS_RESERVED_W
	local trailing = protocolCol.spec and protocolCol.spec.contentTrailing or 0
	return protocolCol.x, protocolCol.x + leading,
		math.max(0, protocolCol.width - leading - trailing)
end

local function updateProtocolTooltip(panel, protocolCol, fullSummary, enabled)
	local overProtocol = enabled and panel:isMouseOver()
		and panel:getMouseX() >= protocolCol.x
		and panel:getMouseX() < protocolCol.finish
	if overProtocol then
		if not panel._gsCatTooltip then
			panel._gsCatTooltip = ISToolTip:new()
			panel._gsCatTooltip:initialise()
			panel._gsCatTooltip:instantiate()
			panel._gsCatTooltip:setOwner(panel)
		end
		panel._gsCatTooltip:setName(T("IGUI_GS_CategoryTooltipTitle"))
		panel._gsCatTooltip:setDescription(fullSummary)
		panel._gsCatTooltip:setVisible(true)
		panel._gsCatTooltip:addToUIManager()
		panel._gsCatTooltip:bringToTop()
		panel._gsCatTooltip:setX(getMouseX() + 16)
		panel._gsCatTooltip:setY(getMouseY() + 16)
	elseif panel._gsCatTooltip and panel._gsCatTooltip:isVisible() then
		panel._gsCatTooltip:removeFromUIManager()
		panel._gsCatTooltip:setVisible(false)
	end
end

--- Muestra el detalle de un estado de nodo o de una incidencia agregada.
---@param panel ISPanel
---@param statusCol table
---@param title string
---@param description string|nil
local function updateStatusTooltip(panel, statusCol, title, description)
	local overStatus = description and panel:isMouseOver()
		and panel:getMouseX() >= statusCol.x and panel:getMouseX() < statusCol.finish
	if overStatus then
		if not panel._gsStatusTooltip then
			panel._gsStatusTooltip = ISToolTip:new()
			panel._gsStatusTooltip:initialise()
			panel._gsStatusTooltip:instantiate()
			panel._gsStatusTooltip:setOwner(panel)
		end
		panel._gsStatusTooltip:setName(title)
		panel._gsStatusTooltip:setDescription(description)
		panel._gsStatusTooltip:setVisible(true)
		panel._gsStatusTooltip:addToUIManager()
		panel._gsStatusTooltip:bringToTop()
		panel._gsStatusTooltip:setX(getMouseX() + 16)
		panel._gsStatusTooltip:setY(getMouseY() + 16)
	elseif panel._gsStatusTooltip and panel._gsStatusTooltip:isVisible() then
		panel._gsStatusTooltip:removeFromUIManager()
		panel._gsStatusTooltip:setVisible(false)
	end
end

--- Calcula el layout completo de columnas de la tabla de nodos a partir del
--- ancho disponible. Unica fuente de verdad para cabecera, filas y clics.
--- Orden (pedido explicito del usuario, ronda de ajuste de espacio):
--- Nombre, Protocolo, Prioridad, Estado, % Ocupación - Prioridad se mueve
--- DESPUES de Protocolo (antes iba justo tras el Nombre) porque el resumen
--- de reglas es la columna que mas espacio necesita de verdad; Nombre
--- tambien se recorta a un ancho fijo modesto (se trunca con "...", el
--- nombre completo nunca fue tan importante como poder leer el protocolo).
---@param w number
---@return table[]
local function nodeColumnLayout(w)
	return GlobalStorageSiK.SiK_UI.Table.resolveColumns(w, NODE_TABLE_COLUMNS, NODE_TABLE_OPTIONS)
end

--- Estado visible y detalle accionable de un nodo. La tabla no vuelve a usar
--- ERR como cajón: cada estado explica su causa en el tooltip.
---@param node table
---@return table info
local function nodeStatusInfo(node)
	if node.offline then
		return { key = "offline", label = T("IGUI_GS_NodeStatusOffline"),
			detail = T("IGUI_GS_NodeStatusOfflineTip"), r = 0.92, g = 0.35, b = 0.3, incident = "red" }
	end
	if node.physicalAnomaly then
		return { key = "conflict", label = T("IGUI_GS_NodeStatusConflict"),
			detail = T("IGUI_GS_NodeStatusConflictTip"), r = 0.92, g = 0.35, b = 0.3, incident = "red" }
	end
	if node.membership == "excluded" then
		return { key = "excluded", label = T("IGUI_GS_NodeStatusExcluded"),
			detail = T("IGUI_GS_NodeStatusExcludedTip"), r = 0.75, g = 0.78, b = 0.82 }
	end
	if node.enabled == false then
		return { key = "disabled", label = T("IGUI_GS_NodeStatusDisabled"),
			detail = T("IGUI_GS_NodeStatusDisabledTip"), r = 0.92, g = 0.75, b = 0.35 }
	end
	if node.membership == "auto" and node.discoveredAtMs and node.lastSeenMs
		and node.discoveredAtMs == node.lastSeenMs then
		return { key = "new", label = T("IGUI_GS_NodeStatusNew"),
			detail = T("IGUI_GS_NodeStatusNewTip"), r = 0.45, g = 0.7, b = 0.95 }
	end
	return { key = "ok", label = T("IGUI_GS_NodeStatusOk"), r = 0.45, g = 0.85, b = 0.45 }
end

local function nodeStatusText(node)
	return nodeStatusInfo(node).label
end

--- Incidencias que requieren revisión humana, no elecciones explícitas de
--- exclusión/desactivación. Se reutiliza en cabecera de zona y pestaña Red.
---@param list table[]|nil
---@return table info
local function incidentInfo(list)
	local count, hasRed = 0, false
	for i = 1, #(list or {}) do
		local info = nodeStatusInfo(list[i])
		if info.incident then
			count = count + 1
			hasRed = hasRed or info.incident == "red"
		end
	end
	return { count = count, level = hasRed and "red" or (count > 0 and "amber" or nil) }
end

function GlobalStorageSiK.TerminalNodes.getNetworkIncidentInfo(nodes)
	return incidentInfo(nodes)
end

--- Texto + color de la columna "% Ocupación" - mismos umbrales que la barra
--- de la pestaña Almacén (GlobalStorageSiK.Config.WEIGHT_WARN_PERCENT/
--- WEIGHT_CRITICAL_PERCENT), mismo lenguaje visual en toda la interfaz.
--- `pct` ya viene trait-aware y capacidad-custom-aware desde el servidor
--- (ver GS_NetworkCapacity.compute, perNode/perZone) - aqui solo se colorea,
--- nunca se recalcula nada. nil cuando el contenedor esta offline/sin chunk
--- o no expone capacidad legible - nunca se inventa un numero.
---@param pct number|nil
---@return string text, number r, number g, number b
local function occupancyDisplay(pct)
	if not pct then
		return T("IGUI_GS_PunctuationEmDash"), 0.45, 0.48, 0.52
	end
	local warnPct = GlobalStorageSiK.Config.WEIGHT_WARN_PERCENT or 80
	local critPct = GlobalStorageSiK.Config.WEIGHT_CRITICAL_PERCENT or 95
	if pct >= critPct then
		return pct .. "%", 0.92, 0.35, 0.3
	elseif pct >= warnPct then
		return pct .. "%", 0.92, 0.75, 0.35
	end
	return pct .. "%", 0.75, 0.78, 0.82
end

--- Ordena nodos por nombre visible (orden por defecto, sin cabecera clicada).
---@param nodes table[]
local function sortNodesByName(nodes)
	table.sort(nodes, function(a, b)
		return (a.displayName or a.name or ""):lower() < (b.displayName or b.name or ""):lower()
	end)
end

--- Valor comparable de un nodo para una columna concreta de la tabla.
--- "protocol" (dev26 ronda 3, antes "category"/"types") ordena por la
--- regla propia mas relevante - no tiene en cuenta herencia de zona (un
--- contenedor sin reglas propias siempre ordena como "", junto a los que
--- de verdad son Global) - suficiente para ordenar, no para mostrar.
---@param node table
---@param column string "name"|"protocol"|"status"|"priority"
---@return string|number
local function nodeSortValue(node, column)
	if column == "priority" then
		return tonumber(node.priority) or 50
	end
	if column == "status" then
		return nodeStatusText(node)
	end
	if column == "occupancy" then
		return tonumber(node.occupancyPercent) or -1
	end
	if column == "protocol" then
		local sum = node.rules and #node.rules > 0 and GlobalStorageSiK.RulesUI.compactSummary(node.rules) or nil
		return sum and sum.label:lower() or ""
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
	local zoneEnabledMap = {}
	local zoneRulesMap = {}
	local zoneOccupancyMap = {}
	local zoneOrder = {}
	for i = 1, #zones do
		local z = zones[i]
		if z and z.id then
			zoneNames[z.id] = z.name or z.id
			zonePriorities[z.id] = tonumber(z.priority) or 50
			zoneEnabledMap[z.id] = z.enabled ~= false
			zoneRulesMap[z.id] = z.rules
			zoneOccupancyMap[z.id] = z.occupancyPercent
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
			zoneEnabled = zoneEnabledMap[zoneId],
			zoneRules = zoneRulesMap[zoneId],
			zoneOccupancy = zoneOccupancyMap[zoneId],
			zoneIncident = incidentInfo(list),
			collapsed = collapsed,
		}
		if not collapsed then
			for j = 1, #list do
				rows[#rows + 1] = { kind = "node", node = list[j], zoneRules = zoneRulesMap[zoneId] }
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
	local row = ISPanel:new(0, 0, rowAreaWidth(scroll), ROW_H)
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
		local pal = GlobalStorageSiK.SiK_UI.PALETTE

		if not data then
			return
		end

		if data.kind == "zoneHeader" then
			local hover = self:isMouseOver()
			GlobalStorageSiK.SiK_UI.drawZoneHeaderBackground(self, hover)
			local arrow = data.collapsed and "+ " or "- "
			local title = arrow .. T("IGUI_GS_ZoneGroupHeader", data.zoneName or T("IGUI_GS_PunctuationEmDash"), data.count or 0)
			local zoneExcluded = data.zoneEnabled == false
			local columns = nodeColumnLayout(w)
			local nameCol, protocolCol, priorityCol, statusCol, occupancyCol =
				columns[1], columns[2], columns[3], columns[4], columns[5]
			local nameX, protocolX = nameCol.x, protocolCol.x
			local titleMaxW = math.max(40, protocolX - 16)
			local tr, tg, tb = pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3]
			local titleTruncated = truncateText(title, titleMaxW, UIFont.Small)
			self:drawText(titleTruncated, 8, yMid, hover and 1 or tr, tg, tb, 1, UIFont.Small)
			-- Tooltip del nombre de zona, mismo motivo/patron que el de nombre
			-- de contenedor mas abajo - solo si se trunco de verdad.
			local overTitleCol = hover and self:getMouseX() >= 8 and self:getMouseX() < protocolX
			if overTitleCol and titleTruncated ~= title then
				if not self._gsNameTooltip then
					self._gsNameTooltip = ISToolTip:new()
					self._gsNameTooltip:initialise()
					self._gsNameTooltip:instantiate()
					self._gsNameTooltip:setOwner(self)
				end
				self._gsNameTooltip:setName(T("IGUI_GS_ColName"))
				self._gsNameTooltip:setDescription(title)
				self._gsNameTooltip:setVisible(true)
				self._gsNameTooltip:addToUIManager()
				self._gsNameTooltip:bringToTop()
				-- BUG REAL confirmado (2026-08-25, captura del usuario: la
				-- tarjeta se pintaba fija arriba a la derecha, sin relacion con
				-- el cursor) - a un ISToolTip anadido a la raiz del UIManager
				-- (addToUIManager) hay que decirle su posicion en pantalla cada
				-- fotograma; nunca se llamaba setX/setY, se quedaba en el
				-- ultimo valor por defecto. Mismo patron ya usado y funcional
				-- en GS_ItemNetworkTooltip.lua (coordenadas GLOBALES de raton,
				-- no self:getMouseX() que es relativo al panel).
				self._gsNameTooltip:setX(getMouseX() + 16)
				self._gsNameTooltip:setY(getMouseY() + 16)
			elseif self._gsNameTooltip and self._gsNameTooltip:isVisible() then
				self._gsNameTooltip:removeFromUIManager()
				self._gsNameTooltip:setVisible(false)
			end
			if data.zonePriority then
				self:drawTextCentre(tostring(data.zonePriority), priorityCol.x + math.floor(priorityCol.width / 2), yMid,
					pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
			end
			-- Protocolo/Estado de la ZONA misma (dev26 ronda 3): antes el
			-- "Excluido" de zona iba pegado al nombre como sufijo de texto,
			-- mezclado con un dato distinto en la misma columna - ahora cada
			-- dato vive en su propia columna, igual que en las filas de
			-- contenedor.
			local zLabel, zr, zg, zb, zDots = nodeProtocolInfo(data.zoneRules, nil)
			local zDotsX, zTextX, zTextW = protocolContentLayout(protocolCol)
			if zDots then
				drawProtocolDots(self, zDotsX, yMid, data.zoneRules)
			end
			-- La propia geometria de Protocolo fija inicio y ancho del texto;
			-- no se deriva desde una columna vecina.
			self:drawText(truncateText(zLabel, zTextW, UIFont.Small), zTextX,
				yMid, zr, zg, zb, 1, UIFont.Small)
			local zoneIncident = data.zoneIncident or { count = 0 }
			local zStatusText = zoneExcluded and T("IGUI_GS_NodeStatusExcluded") or T("IGUI_GS_NodeStatusOk")
			local zsr, zsg, zsb = 0.45, 0.85, 0.45
			local zStatusDetail = zoneExcluded and T("IGUI_GS_NodeStatusExcludedTip") or nil
			if zoneExcluded then
				zsr, zsg, zsb = 0.75, 0.78, 0.82
			elseif zoneIncident.count > 0 then
				zStatusText = "! " .. tostring(zoneIncident.count)
				zStatusDetail = T("IGUI_GS_ZoneIncidentTip", zoneIncident.count)
				if zoneIncident.level == "red" then
					zsr, zsg, zsb = 0.92, 0.35, 0.3
				else
					zsr, zsg, zsb = 0.92, 0.75, 0.35
				end
			end
			self:drawTextCentre(zStatusText, statusCol.x + math.floor(statusCol.width / 2), yMid, zsr, zsg, zsb, 1, UIFont.Small)
			updateStatusTooltip(self, statusCol, T("IGUI_GS_NodeStatusTipTitle"), zStatusDetail)
			local zOccText, zor, zog, zob = occupancyDisplay(data.zoneOccupancy)
			self:drawTextCentre(zOccText, occupancyCol.x + math.floor(occupancyCol.width / 2), yMid, zor, zog, zob, 1, UIFont.Small)
			updateProtocolTooltip(self, protocolCol,
				GlobalStorageSiK.RulesUI.buildSummary(data.zoneRules),
				data.zoneRules and #data.zoneRules > 0)
			return
		end

		local editorInst = GlobalStorageSiK.TerminalNodeEditor and GlobalStorageSiK.TerminalNodeEditor.instance
		local isSelected = editorInst and editorInst.node and data.node and editorInst.node.id == data.node.id
		GlobalStorageSiK.SiK_UI.drawTableRowBackground(self, self.rowIndex, self:isMouseOver(), isSelected)

		local node = data.node
		if not node then
			return
		end

		local columns = nodeColumnLayout(w)
		local nameCol, protocolCol, priorityCol, statusCol, occupancyCol =
			columns[1], columns[2], columns[3], columns[4], columns[5]
		local nameX, protocolX = nameCol.x, protocolCol.x
		local name = node.displayName or node.name or "?"
		local statusInfo = nodeStatusInfo(node)
		local status = statusInfo.label
		local priority = tostring(node.priority or 50)
		self:drawText(truncateText(name, protocolX - nameX - 8, UIFont.Small), nameX, yMid, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
		self:drawTextCentre(priority, priorityCol.x + math.floor(priorityCol.width / 2), yMid, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)

		local label, pr, pg, pb, showDots = nodeProtocolInfo(node.rules, data.zoneRules)
		local dotsX, textX, textW = protocolContentLayout(protocolCol)
		if showDots then
			drawProtocolDots(self, dotsX, yMid, node.rules)
		end
		-- Mismo descriptor que cabecera, puntos, tooltip e hitbox.
		self:drawText(truncateText(label, textW, UIFont.Small), textX, yMid,
			pr, pg, pb, 1, UIFont.Small)

		self:drawTextCentre(status, statusCol.x + math.floor(statusCol.width / 2), yMid,
			statusInfo.r, statusInfo.g, statusInfo.b, 1, UIFont.Small)
		updateStatusTooltip(self, statusCol, T("IGUI_GS_NodeStatusTipTitle"), statusInfo.detail)

		local occText, ocr, ocg, ocb = occupancyDisplay(node.occupancyPercent)
		self:drawTextCentre(occText, occupancyCol.x + math.floor(occupancyCol.width / 2), yMid, ocr, ocg, ocb, 1, UIFont.Small)

		-- Tooltip del Nombre (pedido explicito del usuario, 2026-08-25): la
		-- columna trunca nombres largos con "..." sin forma de ver el nombre
		-- completo - mismo patron que el tooltip de Protocolo de aqui abajo
		-- (ISToolTip propio de la fila), solo se muestra si el nombre
		-- realmente se trunco (nunca para un nombre que ya cabe entero).
		local overNameCol = self:isMouseOver() and self:getMouseX() >= nameX and self:getMouseX() < protocolX
		local nameTruncated = truncateText(name, protocolX - nameX - 8, UIFont.Small)
		if overNameCol and nameTruncated ~= name then
			if not self._gsNameTooltip then
				self._gsNameTooltip = ISToolTip:new()
				self._gsNameTooltip:initialise()
				self._gsNameTooltip:instantiate()
				self._gsNameTooltip:setOwner(self)
			end
			self._gsNameTooltip:setName(T("IGUI_GS_ColName"))
			self._gsNameTooltip:setDescription(name)
			self._gsNameTooltip:setVisible(true)
			self._gsNameTooltip:addToUIManager()
			self._gsNameTooltip:bringToTop()
			-- BUG REAL (ver mismo arreglo en la fila de cabecera de zona, mas
			-- arriba): sin setX/setY explicito cada fotograma, un ISToolTip
			-- anadido a la raiz del UIManager se queda pintado en un punto fijo
			-- de pantalla sin relacion con el raton.
			self._gsNameTooltip:setX(getMouseX() + 16)
			self._gsNameTooltip:setY(getMouseY() + 16)
		elseif self._gsNameTooltip and self._gsNameTooltip:isVisible() then
			self._gsNameTooltip:removeFromUIManager()
			self._gsNameTooltip:setVisible(false)
		end

		-- Tooltip de la columna Protocolo (dev26 ronda 3, antes "Categoria"):
		-- frase-resumen COMPLETA sin truncar (misma que en los editores, ver
		-- GS_RulesUI.buildSummary) - mucho mas util que el viejo recuento de
		-- categorias legacy.
		local hasOwnProtocol = node.rules and #node.rules > 0
		local hasZoneProtocol = data.zoneRules and #data.zoneRules > 0
		local fullSummary = hasOwnProtocol
			and GlobalStorageSiK.RulesUI.buildSummary(node.rules)
			or (hasZoneProtocol and (T("IGUI_GS_NodeInheritedFromZone",
				node.zoneName or "?") .. " "
				.. GlobalStorageSiK.RulesUI.buildSummary(data.zoneRules)) or "")
		updateProtocolTooltip(self, protocolCol, fullSummary,
			hasOwnProtocol or hasZoneProtocol)
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
	local contentRect = GlobalStorageSiK.TerminalScroll.contentRect(scroll)

	for i = 1, #listPanel.nodeRowPool do
		local row = listPanel.nodeRowPool[i]
		local dataIdx = firstIdx + i - 1
		if dataIdx <= #displayRows then
			row:setX(contentRect.x)
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
	panel.columnHeader.prerender = function(self)
		-- La cabecera se crea UNA sola vez (ensureColumnHeader hace early-return
		-- si ya existe) con el ancho del panel EN ESE MOMENTO. Si la ventana se
		-- redimensiona despues, las filas (que recalculan su ancho en cada
		-- updateVirtualRows via rowAreaWidth) se ajustan bien, pero la cabecera
		-- se quedaba con el ancho antiguo — desalineando "Estado"/"Prioridad"
		-- frente a las columnas reales de las filas. Ahora se resincroniza el
		-- ancho con el panel padre en cada prerender.
		local targetW = self.parentPanel and self.parentPanel.nodeScroll
			and rowAreaWidth(self.parentPanel.nodeScroll)
			or (self.parentPanel and self.parentPanel.width or self.width)
		if targetW ~= self.width then
			self:setWidth(targetW)
		end
		if self.parentPanel and self.parentPanel.nodeScroll then
			self:setX(GlobalStorageSiK.TerminalScroll.contentRect(
				self.parentPanel.nodeScroll).x)
		end
		ISPanel.prerender(self)
		local host = self.parentPanel
		GlobalStorageSiK.SiK_UI.Table.drawHeader(self, NODE_TABLE_COLUMNS,
			host and host.sortColumn or nil, not host or host.sortDir ~= "desc",
			2, UIFont.Small, NODE_TABLE_OPTIONS)
	end

	--- Clic en una cabecera de columna: ordena por esa columna, un clic
	--- alterna asc/desc, clicar otra columna reinicia a ascendente. Aplica a
	--- las 5 columnas (Nombre/Prioridad/Protocolo/Estado/% Ocupación) - dev26
	--- ronda 4bis, antes 4.
	panel.columnHeader.onMouseUp = function(self, x, y)
		local host = self.parentPanel
		if not host then
			return false
		end
		local layout = GlobalStorageSiK.SiK_UI.Table.resolveColumns(self.width, NODE_TABLE_COLUMNS, NODE_TABLE_OPTIONS)
		local hit = GlobalStorageSiK.SiK_UI.Table.columnAtX(layout, x)
		local column = hit and hit.key or nil
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
	GlobalStorageSiK.SiK_UI.Table.attachHeaderResize(
		panel.columnHeader, NODE_TABLE_COLUMNS, NODE_TABLE_OPTIONS)
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
		GlobalStorageSiK.SiK_UI.drawCardBackground(self, 0)
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
	-- Las reglas heredadas llegan sin normalización cliente: el saneado
	-- autoritativo conserva sus valores y clasifica las incompatibles.
	local zones = terminal and terminal.terminalState and terminal.terminalState.zones or {}
	panel._lastNodes = nodes
	panel._displayRows = buildGroupedDisplayRows(nodes, zones, panel._collapsedZones, panel.sortColumn, panel.sortDir)
	panel._categories = categories

	ensureNodeScroll(panel, terminal)
	if panel.columnHeader then
		local rect = GlobalStorageSiK.TerminalScroll.contentRect(panel.nodeScroll)
		panel.columnHeader:setX(rect.x)
		panel.columnHeader:setWidth(rect.w)
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
		local rect = GlobalStorageSiK.TerminalScroll.contentRect(panel.nodeScroll)
		panel.columnHeader:setX(rect.x)
		panel.columnHeader:setWidth(rect.w)
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
---@param innerW number
---@return number y tras los botones
function GlobalStorageSiK.TerminalNodes.buildZoneCreateButtons(scroll, terminal, ui, pad, y, innerW)
	local btnH = FONT_HGT_SMALL + 8
	local gap = 6
	-- Ancho dinamico: los 3 botones se reparten SIEMPRE el ancho disponible a
	-- partes iguales (fullWidth=true, ver GS_SiK_UI_Core.createButton)
	-- en vez de encogerse cada uno a su etiqueta - antes quedaban pegados a la
	-- izquierda con texto cortado ("+ Zona: edificio /.."), bug real con
	-- captura del usuario.
	local btnW = math.floor((innerW - pad * 2 - gap * 2) / 3)
	local roomTitle = T("IGUI_GS_CreateRoomZone")
	local structTitle = T("IGUI_GS_CreateStructureZone")
	local selectTitle = T("IGUI_GS_CreateSelectionZone")
	ui.nodesRoomZoneBtn = GlobalStorageSiK.SiK_UI.createButton(pad, y, btnW, btnH, roomTitle, scroll, function()
		terminal:onCreateRoomZone()
	end, nil, true)
	ui.nodesRoomZoneBtn._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesRoomZoneBtn)
	ui.nodesStructureZoneBtn = GlobalStorageSiK.SiK_UI.createButton(pad + btnW + gap, y, btnW, btnH, structTitle, scroll, function()
		terminal:onCreateStructureZone()
	end, nil, true)
	ui.nodesStructureZoneBtn._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesStructureZoneBtn)
	ui.nodesSelectZoneBtn = GlobalStorageSiK.SiK_UI.createButton(pad + (btnW + gap) * 2, y, btnW, btnH, selectTitle, scroll, function()
		terminal:onCreateSelectionZone()
	end, nil, true)
	ui.nodesSelectZoneBtn._gsNetStatic = true
	GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesSelectZoneBtn)
	return y + btnH + 10
end

--- Reposiciona (sin recrear) los botones de crear zona ya existentes -
--- recalcula tambien el ancho por si la ventana se redimensiono.
---@param scroll ISPanel
---@param ui table
---@param pad number
---@param y number
---@param innerW number
---@return number y tras los botones
function GlobalStorageSiK.TerminalNodes.repositionZoneCreateButtons(scroll, ui, pad, y, innerW)
	local btnH = FONT_HGT_SMALL + 8
	local gap = 6
	local btnW = math.floor((innerW - pad * 2 - gap * 2) / 3)
	if ui.nodesRoomZoneBtn then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.nodesRoomZoneBtn, pad)
		GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesRoomZoneBtn, y)
		ui.nodesRoomZoneBtn._sikUiMaxW = btnW
	end
	if ui.nodesStructureZoneBtn then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.nodesStructureZoneBtn, pad + btnW + gap)
		GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesStructureZoneBtn, y)
		ui.nodesStructureZoneBtn._sikUiMaxW = btnW
	end
	if ui.nodesSelectZoneBtn then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.nodesSelectZoneBtn, pad + (btnW + gap) * 2)
		GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesSelectZoneBtn, y)
		ui.nodesSelectZoneBtn._sikUiMaxW = btnW
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
	local state = terminal and terminal.terminalState or {}
	local role = state.permissions and state.permissions.playerRole or "member"
	local canRescanAll = role == "owner" or role == "admin"
	local scan = state.scan or {}
	local scanRunning = state.scanRunning == true or scan.state == "RUNNING"
	local scanBtnH = FONT_HGT_SMALL + 8
	local cardH = FONT_HGT_SMALL * 2 + scanBtnH + 26
	-- dev26 ronda 4quater (pedido explicito del usuario): "Contenedores de
	-- red" (redundante con la pestana ya renombrada "Zonas y nodos") y el
	-- parrafo de ayuda ("Clic en + de una zona...") se retiran de la vista
	-- permanente - toda esa informacion vive ahora en el tooltip del "?"
	-- junto a "Crea una nueva zona". El bloque de "Orden de destino" pasa de
	-- un parrafo multi-linea siempre visible a una sola linea + su propio
	-- "?" - mismo patron ya usado en los editores de contenedor/zona.
	local infoH = FONT_HGT_SMALL + 8
	local function heightFor(currentY)
		-- La ayuda queda visible debajo de la tabla. Si la ventana crece, todo
		-- el alto adicional se entrega al viewport virtual de filas; si es
		-- pequena se conserva el minimo y el scroll exterior cubre el resto.
		local footerReserve = infoH + 24
		if canRescanAll then
			-- Desde el final del viewport de filas hasta el borde inferior:
			-- separación + título de orden + separación + tarjeta + margen.
			footerReserve = FONT_HGT_SMALL + cardH + 26
		end
		local available = (scroll.height or 0) - currentY - footerReserve
		return GlobalStorageSiK.TerminalNodes.embedPanelHeight(available)
	end
	if not ui.nodesEmbedBuilt or not GlobalStorageSiK.TerminalScroll.isLiveWidget(ui.nodesEmbedPanel) then
		ui.nodesEmbedBuilt = false
		local host = GlobalStorageSiK.TerminalScroll.childHost(scroll)
		for _, key in ipairs({ "nodesZoneTitleLbl", "nodesZoneInfoBtn", "nodesEmbedPanel",
			"nodesRoomZoneBtn", "nodesStructureZoneBtn", "nodesSelectZoneBtn",
			"nodesDestOrderLbl", "nodesDestOrderBtn", "nodesRescanCard" }) do
			local w = ui[key]
			if w and host then
				GlobalStorageSiK.TerminalScroll.disposeChild(host, w)
			end
			ui[key] = nil
		end
		ui.collapsedZones = ui.collapsedZones or {}
		ui.nodesZoneTitleLbl = GlobalStorageSiK.SiK_UI.createSectionLabel(pad, titleY, T("IGUI_GS_CreateZoneTitle"))
		ui.nodesZoneTitleLbl._gsNetStatic = true
		GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesZoneTitleLbl)
		local zoneTitleW = getTextManager():MeasureStringX(UIFont.Small, T("IGUI_GS_CreateZoneTitle"))
		ui.nodesZoneInfoBtn = GlobalStorageSiK.SiK_UI.createInfoHintButton(
			pad + zoneTitleW + 6, titleY, FONT_HGT_SMALL, scroll, T("IGUI_GS_NodesHelpShort"))
		ui.nodesZoneInfoBtn._gsNetStatic = true
		GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesZoneInfoBtn)
		y = titleY + FONT_HGT_SMALL + 8
		-- Bloque de creacion de zonas, tambien disponible aqui (ademas de en
		-- la seccion Zonas, que no se retira todavia) - primer paso hacia la
		-- gestion unificada de zonas+contenedores desde un solo sitio.
		y = GlobalStorageSiK.TerminalNodes.buildZoneCreateButtons(scroll, terminal, ui, pad, y, innerW)
		ui.nodesEmbedHeight = heightFor(y)
		ui.nodesEmbedPanel = ISPanel:new(0, y, innerW, ui.nodesEmbedHeight)
		ui.nodesEmbedPanel:initialise()
		ui.nodesEmbedPanel.drawBackground = false
		ui.nodesEmbedPanel._gsNetStatic = true
		ui.nodesEmbedPanel._gsEmbedMode = true
		ui.nodesEmbedPanel.clipChildren = true
		ui.nodesEmbedPanel.prerender = function(self)
			ISPanel.prerender(self)
			local pal = GlobalStorageSiK.SiK_UI.PALETTE
			local br = pal.border
			self:drawRectBorder(0, 0, self.width, self.height, 0.2, br[1] * 0.35, br[2] * 0.35, br[3] * 0.35)
		end
		GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesEmbedPanel)
		GlobalStorageSiK.TerminalNodes.build(ui.nodesEmbedPanel, terminal)
		-- El toggle "+/-" y refresh()/build() leen y escriben SIEMPRE en
		-- nodesListPanel._collapsedZones (el panel interior de la lista, ver
		-- self.listPanel en onMouseUp y `panel` en TerminalNodes.refresh) -
		-- nunca en nodesEmbedPanel (el panel exterior). Asignar la tabla
		-- persistida solo al exterior (como antes) la dejaba sin leer nunca:
		-- cada reconstrucción (resize u otro caso que invalide el widget)
		-- arrancaba con una nodesListPanel._collapsedZones nueva y vacía,
		-- así que todas las zonas volvían a su colapso por defecto pese a
		-- que ui.collapsedZones sí sobrevive entre reconstrucciones.
		if ui.nodesEmbedPanel.nodesListPanel then
			ui.nodesEmbedPanel.nodesListPanel._collapsedZones = ui.collapsedZones
		end
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
		local infoY = y + ui.nodesEmbedHeight + 8
		ui.nodesDestOrderLbl = GlobalStorageSiK.SiK_UI.createSectionLabel(pad, infoY, T("IGUI_GS_NodesDestOrderLabel"))
		ui.nodesDestOrderLbl._gsNetStatic = true
		GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesDestOrderLbl)
		local destOrderW = getTextManager():MeasureStringX(UIFont.Small, T("IGUI_GS_NodesDestOrderLabel"))
		ui.nodesDestOrderBtn = GlobalStorageSiK.SiK_UI.createInfoHintButton(
			pad + destOrderW + 6, infoY, FONT_HGT_SMALL, scroll, T("IGUI_GS_NodesPriorityHelp"))
		ui.nodesDestOrderBtn._gsNetStatic = true
		GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesDestOrderBtn)
		ui.nodesPriorityInfoEndY = infoY + FONT_HGT_SMALL + 2
		local cardY = ui.nodesPriorityInfoEndY + 8
		ui.nodesRescanCard = GlobalStorageSiK.SiK_UI.createSectionCard(pad, cardY, innerW - pad * 2, 90)
		ui.nodesRescanCard._gsNetStatic = true
		GlobalStorageSiK.TerminalScroll.addChild(scroll, ui.nodesRescanCard)
		ui.nodesRescanTitle = GlobalStorageSiK.SiK_UI.createSectionLabel(10, 8, T("IGUI_GS_RescanAll"))
		ui.nodesRescanCard:addChild(ui.nodesRescanTitle)
		local scanTitleW = getTextManager():MeasureStringX(UIFont.Small, T("IGUI_GS_RescanAll"))
		ui.nodesRescanInfo = GlobalStorageSiK.SiK_UI.createInfoHintButton(
			16 + scanTitleW, 7, FONT_HGT_SMALL, ui.nodesRescanCard, T("IGUI_GS_RescanAllHint"))
		ui.nodesRescanCard:addChild(ui.nodesRescanInfo)
		ui.nodesRescanState = ISLabel:new(10, 8 + FONT_HGT_SMALL + 6, FONT_HGT_SMALL, "",
			0.72, 0.74, 0.78, 1, UIFont.Small, true)
		ui.nodesRescanState:initialise()
		ui.nodesRescanCard:addChild(ui.nodesRescanState)
		local scanBtnY = 8 + FONT_HGT_SMALL * 2 + 12
		ui.nodesRescanBtn = GlobalStorageSiK.SiK_UI.createButton(
			10, scanBtnY, innerW - pad * 2 - 20, FONT_HGT_SMALL + 8,
			T("IGUI_GS_RescanAll"), ui.nodesRescanCard, function()
				if terminal.onRescanNetwork then terminal:onRescanNetwork() end
			end, nil, true)
		ui.nodesRescanCard:addChild(ui.nodesRescanBtn)
		ui.nodesCancelScanBtn = GlobalStorageSiK.SiK_UI.createButton(
			10, scanBtnY, innerW - pad * 2 - 20, FONT_HGT_SMALL + 8,
			T("IGUI_GS_ScanCancel"), ui.nodesRescanCard, function()
				if terminal.onCancelZoneScan then terminal:onCancelZoneScan() end
			end, GlobalStorageSiK.SiK_UI.PALETTE.statusDanger, true)
		ui.nodesRescanCard:addChild(ui.nodesCancelScanBtn)
	else
		if ui.nodesZoneTitleLbl then
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.nodesZoneTitleLbl, pad)
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesZoneTitleLbl, titleY)
		end
		if ui.nodesZoneInfoBtn then
			local zoneTitleW = getTextManager():MeasureStringX(UIFont.Small, T("IGUI_GS_CreateZoneTitle"))
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.nodesZoneInfoBtn, pad + zoneTitleW + 6)
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesZoneInfoBtn, titleY)
		end
		y = titleY + FONT_HGT_SMALL + 8
		y = GlobalStorageSiK.TerminalNodes.repositionZoneCreateButtons(scroll, ui, pad, y, innerW)
		ui.nodesEmbedY = y
		ui.nodesEmbedHeight = heightFor(y)
		local infoY = y + ui.nodesEmbedHeight + 8
		if ui.nodesDestOrderLbl then
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.nodesDestOrderLbl, pad)
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesDestOrderLbl, infoY)
		end
		if ui.nodesDestOrderBtn then
			local destOrderW = getTextManager():MeasureStringX(UIFont.Small, T("IGUI_GS_NodesDestOrderLabel"))
			GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.nodesDestOrderBtn, pad + destOrderW + 6)
			GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesDestOrderBtn, infoY)
		end
		ui.nodesPriorityInfoEndY = infoY + FONT_HGT_SMALL + 2
	end
	local cardY = (ui.nodesPriorityInfoEndY or (y + ui.nodesEmbedHeight + infoH)) + 8
	if ui.nodesRescanCard then
		GlobalStorageSiK.TerminalScroll.setContentX(scroll, ui.nodesRescanCard, pad)
		GlobalStorageSiK.TerminalScroll.setContentY(scroll, ui.nodesRescanCard, cardY)
		ui.nodesRescanCard:setWidth(innerW - pad * 2)
		ui.nodesRescanCard:setHeight(cardH)
		ui.nodesRescanCard:setVisible(canRescanAll)
	end
	if ui.nodesRescanState then
		ui.nodesRescanState:setName(scanRunning and T("IGUI_GS_ScanRunningShort")
			or T("IGUI_GS_ScanSummary", scan.new or 0, scan.updated or 0, scan.offline or 0))
	end
	if ui.nodesRescanBtn then
		local availableW = innerW - pad * 2 - 20
		local buttonW = scanRunning and math.floor((availableW - 6) / 2) or availableW
		ui.nodesRescanBtn:setX(10)
		ui.nodesRescanBtn:setWidth(buttonW)
		ui.nodesRescanBtn:setEnable(not scanRunning)
		ui.nodesRescanBtn._sikUiLabel = scanRunning and T("IGUI_GS_ScanRunningShort") or T("IGUI_GS_RescanAll")
		ui.nodesRescanBtn:setTooltip(T("IGUI_GS_RescanAllHint"))
	end
	if ui.nodesCancelScanBtn then
		local availableW = innerW - pad * 2 - 20
		local buttonW = math.floor((availableW - 6) / 2)
		ui.nodesCancelScanBtn:setX(10 + buttonW + 6)
		ui.nodesCancelScanBtn:setWidth(buttonW)
		ui.nodesCancelScanBtn:setVisible(scanRunning)
		ui.nodesCancelScanBtn:setEnable(scanRunning)
		ui.nodesCancelScanBtn:setTooltip(T("IGUI_GS_ScanCancelHint"))
	end
	local configEnabled = not terminal.canEditNetworkConfig
		or terminal:canEditNetworkConfig(false)
	-- Auditoria de botones (2026-08-26): antes se deshabilitaban con la
	-- textura gris generica de setEnable y SIN ningun tooltip explicando el
	-- motivo (permiso insuficiente) - un jugador sin permisos solo veia los
	-- 3 botones apagados, sin saber por que. Ahora usan el mismo aspecto
	-- "bloqueado" del resto del proyecto, con tooltip.
	for _, button in ipairs({ ui.nodesRoomZoneBtn, ui.nodesStructureZoneBtn, ui.nodesSelectZoneBtn }) do
		if button then
			button:setEnable(configEnabled)
			button._sikUiLocked = not configEnabled
			if not configEnabled then
				button:setTooltip(T("IGUI_GS_NodesConfigNoPermission"))
			end
		end
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
		local endY = y + embedH + 12 + infoH
		if canRescanAll then endY = cardY + cardH + 8 end
		return endY
	end
	ui.nodesEmbedBuilt = false
	return titleY + FONT_HGT_SMALL + 12
end

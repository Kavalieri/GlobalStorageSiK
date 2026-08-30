--[[
	GlobalStorageSiK - Tabla reutilizable SiK UI
	Una sola geometria declarativa para cabeceras, filas y listas virtuales.
]]

require "GS_SiK_UI_Core"
if not GlobalStorageSiK.SiK_UI.Metrics then require "GS_SiK_UI_Metrics" end
require "GS_TerminalUI_Scroll"
if not GlobalStorageSiK.SiK_UI.List then require "GS_SiK_UI_List" end

GlobalStorageSiK.SiK_UI.Table = GlobalStorageSiK.SiK_UI.Table or {}

local Table = GlobalStorageSiK.SiK_UI.Table

Table.DEFAULTS = Table.DEFAULTS or {}
local TABLE_TOKENS = GlobalStorageSiK.SiK_UI.Metrics.tokens()
Table.DEFAULTS.font = UIFont.Small
Table.DEFAULTS.rowVerticalPadding = TABLE_TOKENS.controlVerticalPadding or 10
Table.DEFAULTS.headerVerticalPadding = TABLE_TOKENS.tableHeaderVerticalPadding or 10
Table.DEFAULTS.columnGap = TABLE_TOKENS.tableColumnGap or 8
Table.DEFAULTS.cellPadding = TABLE_TOKENS.tableCellPadding or 6
Table.DEFAULTS.left = 0
Table.DEFAULTS.right = 0

local function layoutCacheKey(width, columns, options, metrics)
	local parts = {
		tostring(width), tostring(metrics.gap), tostring(metrics.left), tostring(metrics.right),
		tostring(metrics.cellPadding),
	}
	for i = 1, #(columns or {}) do
		local spec = columns[i]
		parts[#parts + 1] = table.concat({
			tostring(spec.key or i), tostring(spec.flex or ""), tostring(spec.width or ""),
			tostring(spec.widthFraction or ""), tostring(spec.minWidth or ""),
			tostring(spec.hardMinWidth or ""), tostring(spec.start or ""),
			tostring(spec.startFraction or ""), tostring(spec.finish or ""),
			tostring(spec.finishFraction or ""), tostring(spec.right or ""),
			tostring(options.columnWidths and options.columnWidths[spec.key] or ""),
			tostring(spec.title or spec.titleKey or ""),
		}, ":")
		for j = 1, #(spec.measureValues or {}) do
			parts[#parts + 1] = tostring(spec.measureValues[j])
		end
	end
	return table.concat(parts, "|")
end

local function cacheLayout(columns, key, layout)
	if type(columns) == "table" then
		columns._sikUiLayoutCache = { key = key, layout = layout }
	end
	return layout
end

--- Métricas comunes de todas las tablas. Cada consumidor puede sobrescribir
--- solo lo que necesite; cambiar DEFAULTS propaga fuente y densidad globales.
function Table.metrics(options)
	options = options or {}
	local font = options.font or Table.DEFAULTS.font
	local fontHeight = getTextManager():getFontHeight(font)
	local rowPadding = tonumber(options.rowVerticalPadding)
		or Table.DEFAULTS.rowVerticalPadding
	local headerPadding = tonumber(options.headerVerticalPadding)
		or Table.DEFAULTS.headerVerticalPadding
	return {
		font = font,
		fontHeight = fontHeight,
		rowHeight = tonumber(options.rowHeight) or fontHeight + rowPadding,
		headerHeight = tonumber(options.headerHeight) or fontHeight + headerPadding,
		gap = tonumber(options.gap) or Table.DEFAULTS.columnGap,
		left = tonumber(options.left) or Table.DEFAULTS.left,
		right = tonumber(options.right) or Table.DEFAULTS.right,
		cellPadding = tonumber(options.cellPadding) or Table.DEFAULTS.cellPadding,
	}
end

local function resolveEdge(value, fraction, total, fallback)
	if tonumber(value) then
		return tonumber(value)
	end
	if tonumber(fraction) then
		return math.floor(total * tonumber(fraction))
	end
	return fallback
end

local function measuredWidth(spec, defaultFont)
	local font = spec.font or defaultFont or Table.DEFAULTS.font
	local title = spec.title or (spec.titleKey and GlobalStorageSiK.I18n.text(spec.titleKey)) or ""
	if spec.sortable ~= false then title = title .. " v" end
	local widest = getTextManager():MeasureStringX(font, title)
	for i = 1, #(spec.measureValues or {}) do
		widest = math.max(widest, getTextManager():MeasureStringX(font, tostring(spec.measureValues[i] or "")))
	end
	return math.max(tonumber(spec.minWidth) or 0, math.floor(widest) + (tonumber(spec.measurePad) or 12))
end

local function columnMinimum(spec, defaultFont)
	return math.max(tonumber(spec and spec.hardMinWidth) or 24,
		tonumber(spec and spec.minWidth) or 0,
		(spec and spec.measureValues) and measuredWidth(spec, defaultFont) or 0)
end

-- dev36 (debug SiK UI): resolveColumns() se llama cada prerender (cabecera,
-- filas y deteccion de clic comparten esta funcion) - loguear siempre
-- inundaria la consola. Se cachea el ultimo ancho ya logueado POR TABLA
-- (identidad de la propia lista `columns`, p.ej. NODE_TABLE_COLUMNS) y solo
-- se traza cuando el ancho disponible cambia de verdad (resize de ventana),
-- nunca fotograma a fotograma con el mismo ancho.
local function logColumnsIfChanged(columns, width, out)
	if columns._sikUiDebugWidth == width then
		return
	end
	columns._sikUiDebugWidth = width
	if not GlobalStorageSiK.Log then
		return
	end
	local parts = {}
	for i = 1, #out do
		parts[#parts + 1] = string.format("%s=%dpx@%d", tostring(out[i].key), out[i].width, out[i].x)
	end
	GlobalStorageSiK.Log.debug("SiKUITable", "resolveColumns w=" .. tostring(width), table.concat(parts, " "))
end

--- Convierte columnas declarativas en posiciones estables para el ancho actual.
--- Cada columna admite start/startFraction y finish/finishFraction; la ultima
--- puede usar right para reservar margen desde el borde derecho.
---@param width number
---@param columns table[]
---@return table[]
function Table.resolveColumns(width, columns, options)
	width = math.max(1, tonumber(width) or 1)
	columns = columns or {}
	options = options or {}
	local metrics = Table.metrics(options)
	local cacheKey = layoutCacheKey(width, columns, options, metrics)
	local cached = type(columns) == "table" and columns._sikUiLayoutCache or nil
	if cached and cached.key == cacheKey then
		return cached.layout
	end
	local flow = false
	for i = 1, #(columns or {}) do
		local spec = columns[i]
		if spec.flex or spec.width or spec.widthFraction or spec.measureValues then flow = true break end
	end
	local out = {}
	if flow then
		local left = metrics.left
		local right = metrics.right
		local gap = metrics.gap
		local fixed, flexTotal, flexMinimum = 0, 0, 0
		local widths = {}
		for i = 1, #columns do
			local spec = columns[i]
			local savedWidth = options.columnWidths and tonumber(options.columnWidths[spec.key]) or nil
			if savedWidth then
				widths[i] = math.max(columnMinimum(spec, metrics.font), math.floor(savedWidth))
			elseif spec.flex then
				flexTotal = flexTotal + math.max(0, tonumber(spec.flex) or 0)
				flexMinimum = flexMinimum + math.max(0, tonumber(spec.minWidth) or 0)
				widths[i] = 0
			elseif spec.widthFraction then
				widths[i] = math.max(tonumber(spec.minWidth) or 0, math.floor(width * spec.widthFraction))
			else
				widths[i] = tonumber(spec.width) or measuredWidth(spec, metrics.font)
			end
			fixed = fixed + widths[i]
		end
		local available = math.max(0, width - left - right - gap * math.max(0, #columns - 1) - fixed)
		local flexibleExtra = math.max(0, available - flexMinimum)
		local shrinkRatio = flexMinimum > 0 and math.min(1, available / flexMinimum) or 1
		local x = left
		for i = 1, #columns do
			local spec = columns[i]
			local colW = widths[i]
			if spec.flex and not (options.columnWidths and tonumber(options.columnWidths[spec.key])) then
				local minimum = math.max(0, tonumber(spec.minWidth) or 0)
				colW = math.floor(minimum * shrinkRatio)
				if flexibleExtra > 0 then
					colW = colW + math.floor(flexibleExtra * (tonumber(spec.flex) or 0) / math.max(1, flexTotal))
				end
				colW = math.max(tonumber(spec.hardMinWidth) or 24, colW)
			end
			out[i] = {
				key = spec.key, titleKey = spec.titleKey, title = spec.title,
				align = spec.align or "left", x = x, finish = x + colW,
				width = colW, pad = tonumber(spec.pad) or metrics.cellPadding, spec = spec,
			}
			x = x + colW + gap
		end
		local last = out[#out]
		local targetFinish = width - right
		if last and last.x <= targetFinish and last.finish <= targetFinish then
			last.finish = targetFinish
			last.width = targetFinish - last.x
		end
		logColumnsIfChanged(columns, width, out)
		return cacheLayout(columns, cacheKey, out)
	end
	for i = 1, #(columns or {}) do
		local spec = columns[i]
		local x1 = resolveEdge(spec.start, spec.startFraction, width, 0)
		local x2 = resolveEdge(spec.finish, spec.finishFraction, width, width - (tonumber(spec.right) or 0))
		if x2 < x1 then
			x2 = x1
		end
		out[i] = {
			key = spec.key,
			titleKey = spec.titleKey,
			title = spec.title,
			align = spec.align or "left",
			x = x1,
			finish = x2,
			width = x2 - x1,
			pad = tonumber(spec.pad) or metrics.cellPadding,
			spec = spec,
		}
	end
	logColumnsIfChanged(columns, width, out)
	return cacheLayout(columns, cacheKey, out)
end

--- Geometria de fila relativa al mismo contentRect que usa la cabecera.
--- Table consume contentW; la reserva de scrollbar pertenece exclusivamente a Block.
---@param contentRect table
---@param rowIndex number
---@param options table|nil
---@return table
function Table.rowRect(contentRect, rowIndex, options)
	contentRect = contentRect or {}
	options = options or {}
	local metrics = Table.metrics(options)
	local rowHeight = tonumber(options.rowHeight) or tonumber(contentRect.rowHeight)
		or metrics.rowHeight
	local headerHeight = tonumber(options.headerHeight) or tonumber(contentRect.headerHeight) or 0
	local index = math.max(1, math.floor(tonumber(rowIndex) or 1))
	return {
		x = tonumber(contentRect.x) or 0,
		y = (tonumber(contentRect.y) or 0) + headerHeight + (index - 1) * rowHeight,
		w = math.max(0, tonumber(contentRect.w or contentRect.contentW) or 0),
		h = math.max(0, rowHeight),
		rowIndex = index,
	}
end

--- Hitbox canonico: nunca vuelve a medir ni desplazar la fila renderizada.
---@param contentRect table
---@param rowIndex number
---@param options table|nil
---@return table
function Table.hitRect(contentRect, rowIndex, options)
	return Table.rowRect(contentRect, rowIndex, options)
end

--- Resuelve una tabla completa a partir del contentRect entregado por Block.
---@param contentRect table
---@param columns table[]
---@param options table|nil
---@return table
function Table.resolve(contentRect, columns, options)
	contentRect = contentRect or {}
	local contentW = math.max(0, tonumber(contentRect.w or contentRect.contentW) or 0)
	return {
		contentRect = {
			x = tonumber(contentRect.x) or 0,
			y = tonumber(contentRect.y) or 0,
			w = contentW,
			h = math.max(0, tonumber(contentRect.h) or 0),
		},
		columns = Table.resolveColumns(contentW, columns or {}, options),
	}
end

--- Conecta el divisor que ya dibuja drawHeader con un ajuste de ancho real.
--- La geometria sigue saliendo exclusivamente de resolveColumns(): cabecera,
--- filas, hit-testing y ordenacion leen las mismas columnas. El consumidor
--- instala este helper DESPUES de su onMouseUp para conservar su sort/clic.
function Table.attachHeaderResize(panel, columns, options)
	if not panel or panel._sikHeaderResizeAttached then return end
	options = options or {}
	options.columnWidths = options.columnWidths or {}
	panel._sikHeaderResizeAttached = true
	local oldDown = panel.onMouseDown
	local oldMove = panel.onMouseMove
	local oldUp = panel.onMouseUp

	panel.onMouseDown = function(self, x, y)
		local layout = Table.resolveColumns(self.width, columns, options)
		for i = 1, #layout - 1 do
			local boundary = layout[i].finish
			if layout[i].spec.resizable ~= false and math.abs((tonumber(x) or 0) - boundary) <= 6 then
				self._sikColumnResize = { index = i, delta = 0,
					left = layout[i].width, right = layout[i + 1].width }
				return true
			end
		end
		if oldDown then return oldDown(self, x, y) end
		return ISPanel.onMouseDown(self, x, y)
	end

	panel.onMouseMove = function(self, dx, dy)
		local drag = self._sikColumnResize
		if drag then
			drag.delta = drag.delta + (tonumber(dx) or 0)
			local leftSpec = columns[drag.index]
			local rightSpec = columns[drag.index + 1]
			local leftMin = columnMinimum(leftSpec, options.font)
			local rightMin = columnMinimum(rightSpec, options.font)
			local delta = math.max(leftMin - drag.left,
				math.min(drag.delta, drag.right - rightMin))
			options.columnWidths[leftSpec.key] = math.floor(drag.left + delta)
			options.columnWidths[rightSpec.key] = math.floor(drag.right - delta)
			return true
		end
		if oldMove then return oldMove(self, dx, dy) end
		return ISPanel.onMouseMove(self, dx, dy)
	end

	panel.onMouseUp = function(self, x, y)
		if self._sikColumnResize then
			self._sikColumnResize = nil
			return true
		end
		if oldUp then return oldUp(self, x, y) end
		return ISPanel.onMouseUp(self, x, y)
	end
end

---@param layout table[]
---@param x number
---@return table|nil
function Table.columnAtX(layout, x)
	for i = 1, #(layout or {}) do
		local col = layout[i]
		if x >= col.x and (x < col.finish or i == #layout) then
			return col
		end
	end
	return nil
end

--- Dibuja una cabecera consistente. El consumidor conserva la decision de
--- ordenacion; la tabla solo representa la columna activa.
function Table.drawHeader(panel, columns, sortKey, sortAsc, y, font, options)
	if not panel then return end
	options = options or {}
	font = font or options.font or Table.DEFAULTS.font
	y = tonumber(y) or 2
	local pal = GlobalStorageSiK.SiK_UI.PALETTE
	local layout = Table.resolveColumns(panel.width, columns, options)
	for i = 1, #layout do
		local col = layout[i]
		local label = col.title or (col.titleKey and GlobalStorageSiK.I18n.text(col.titleKey)) or ""
		if sortKey and sortKey == col.key then
			label = label .. (sortAsc == false and " v" or " ^")
		end
		local text = GlobalStorageSiK.SiK_UI.truncateText(label, math.max(0, col.width - col.pad * 2), font)
		if col.align == "right" then
			panel:drawTextRight(text, col.finish - col.pad, y, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, font)
		elseif col.align == "center" then
			panel:drawTextCentre(text, col.x + col.width / 2, y, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, font)
		else
			panel:drawText(text, col.x + col.pad, y, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, font)
		end
		-- Un único divisor por límite compartido: la geometría de la cabecera
		-- sigue siendo exactamente la de las filas, y el área de arrastre se
		-- superpone sin dibujar una segunda línea.
		if i < #layout then
			panel:drawRect(col.finish, 0, 1, panel.height - 1, 0.72,
				pal.divider[1], pal.divider[2], pal.divider[3])
		end
	end
	GlobalStorageSiK.SiK_UI.drawTableHeaderLine(panel)
	return layout
end

--- Crea el motor virtual que usan las tablas grandes. Se mantiene como una
--- API propia minima: el consumidor aporta la fila y su actualizador.
function Table.createVirtual(parent, x, y, w, h, rowHeight, padding, columns, onCreateRow, onUpdateRow, options)
	local metrics = Table.metrics(options)
	local list = GlobalStorageSiK.SiK_UI.List.createVirtual(parent, x, y, w, h,
		rowHeight or metrics.rowHeight, padding, onCreateRow, onUpdateRow)
	list._sikTableColumns = columns or {}
	list._sikTableOptions = options or {}
	list.getColumnLayout = function(self)
		return Table.resolveColumns(self.width, self._sikTableColumns, self._sikTableOptions)
	end
	list.setColumns = function(self, nextColumns)
		self._sikTableColumns = nextColumns or {}
		if self.refreshItems then self:refreshItems() end
	end
	return list
end

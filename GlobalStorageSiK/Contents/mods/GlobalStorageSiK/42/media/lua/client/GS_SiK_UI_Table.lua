--[[
	GlobalStorageSiK - Tabla reutilizable SiK UI
	Una sola geometria declarativa para cabeceras, filas y listas virtuales.
]]

require "GS_SiK_UI_Core"
require "GS_TerminalUI_Scroll"

GlobalStorageSiK.SiK_UI.Table = GlobalStorageSiK.SiK_UI.Table or {}

local Table = GlobalStorageSiK.SiK_UI.Table

Table.DEFAULTS = Table.DEFAULTS or {
	font = UIFont.Small,
	rowVerticalPadding = 10,
	headerVerticalPadding = 10,
	columnGap = 4,
	left = 0,
	right = 0,
}

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
	options = options or {}
	local metrics = Table.metrics(options)
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
			if spec.flex then
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
			if spec.flex then
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
				width = colW, pad = tonumber(spec.pad) or 0, spec = spec,
			}
			x = x + colW + gap
		end
		logColumnsIfChanged(columns, width, out)
		return out
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
			pad = tonumber(spec.pad) or 0,
			spec = spec,
		}
	end
	logColumnsIfChanged(columns, width, out)
	return out
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
	local list = GlobalStorageSiK.SiK_UI.VirtualList.create(parent, x, y, w, h,
		rowHeight or metrics.rowHeight, padding)
	list._sikTableColumns = columns or {}
	list._sikTableOptions = options or {}
	list.getColumnLayout = function(self)
		return Table.resolveColumns(self.width, self._sikTableColumns, self._sikTableOptions)
	end
	list.setColumns = function(self, nextColumns)
		self._sikTableColumns = nextColumns or {}
		if self.refreshItems then self:refreshItems() end
	end
	if onCreateRow then list:setOnCreateItem(onCreateRow) end
	if onUpdateRow then list:setOnUpdateItem(onUpdateRow) end
	return list
end

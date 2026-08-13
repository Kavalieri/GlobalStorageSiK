--[[
	GlobalStorageSiK - Layout por bloques (stack vertical)
	Autor: SiK
	Fecha: 2026-06-30
	Descripción: Helper de geometría PURA (no crea ni destruye widgets, solo
	             coloca/dimensiona los que se le pasan) inspirado en el layout
	             tipo fill de NeatUI (addColumn/addColumnFill/setElement).

	Garantías por construcción:
	  - Sin solapes: el cursor vertical solo avanza, nunca retrocede.
	  - Altura dinámica: cada bloque reserva exactamente la altura indicada.
	  - Reescalado total: el ancho de cada bloque = ancho del contenedor en
	    cada pasada de layout, así que al redimensionar TODO escala.
	  - Un bloque "fill" puede ocupar todo el espacio vertical restante.

	Uso típico (dentro de calculateLayout, recalculado en cada resize):
	  local col = GlobalStorageSiK.UILayout.column{ x=pad, y=pad, width=contentW,
	                                                bottom=innerH-pad, gap=8 }
	  col:label(self.titleLbl,  FONT_HGT_SMALL)
	  col:block(self.hintLbl,   hintH)
	  col:row(rowH, {
	      { self.searchBox, weight = 1, min = 120 },
	      { self.comboA,    w = filterW },
	      { self.comboB,    w = filterW },
	      { self.searchBtn, w = btnW },
	  }, { gap = 6 })
	  col:fill(self.listPanel)   -- ocupa hasta 'bottom'
]]

GlobalStorageSiK.UILayout = GlobalStorageSiK.UILayout or {}

local Column = {}
Column.__index = Column

--- Ajusta bounds de un widget de forma segura (solo si existe el setter).
local function setBounds(widget, x, y, w, h)
	if not widget then return end
	if x ~= nil and widget.setX then widget:setX(x) end
	if y ~= nil and widget.setY then widget:setY(y) end
	if w ~= nil and widget.setWidth then widget:setWidth(w) end
	if h ~= nil and widget.setHeight then widget:setHeight(h) end
end

--- Coloca un widget. Si la columna está ligada a un scroll NeatUI, usa
--- setContentX/Y (respeta el offset de scroll); si no, posicionado directo.
---@param widget any
function Column:_set(widget, x, y, w, h)
	if not widget then return end
	if self.scroll then
		local TS = GlobalStorageSiK.TerminalScroll
		if x ~= nil and TS and TS.setContentX then TS.setContentX(self.scroll, widget, x) end
		if y ~= nil and TS and TS.setContentY then TS.setContentY(self.scroll, widget, y) end
		if w ~= nil and widget.setWidth then widget:setWidth(w) end
		if h ~= nil and widget.setHeight then widget:setHeight(h) end
	else
		setBounds(widget, x, y, w, h)
	end
end

--- Crea una columna (stack vertical).
---@param o table { x, y, width, bottom?, gap?, pad? }
---@return table column
function GlobalStorageSiK.UILayout.column(o)
	o = o or {}
	local c = setmetatable({}, Column)
	c.x = o.x or 0
	c.width = math.max(0, o.width or 0)
	c.gap = o.gap or 6
	c.pad = o.pad or 0
	c.startY = o.y or 0
	c.cursor = c.startY
	c.bottom = o.bottom   -- y máximo absoluto para fill (opcional)
	c.scroll = o.scroll   -- si se da, posiciona vía setContentX/Y (contenido scrollable)
	return c
end

--- Avanza el cursor (reserva espacio) sin colocar nada.
---@param h number
function Column:space(h)
	self.cursor = self.cursor + (h or 0)
	return self
end

--- Coloca un widget fijando SOLO x/y (no toca ancho ni alto). Para títulos.
---@param widget any
---@param h number  altura reservada en el cursor
function Column:place(widget, h, gapAfter)
	if widget then
		self:_set(widget, self.x, self.cursor, nil, nil)
	end
	self.cursor = self.cursor + (h or 0) + (gapAfter or self.gap)
	return self
end

--- Coloca una etiqueta (solo x/y/width; la altura la gestiona el propio label).
---@param widget any
---@param h number  altura reservada en el cursor
function Column:label(widget, h, gapAfter)
	if widget then
		self:_set(widget, self.x, self.cursor, self.width, nil)
	end
	self.cursor = self.cursor + (h or 0) + (gapAfter or self.gap)
	return self
end

--- Coloca un bloque rectangular a ancho completo y altura fija.
---@param widget any
---@param h number
function Column:block(widget, h, gapAfter)
	if widget then
		self:_set(widget, self.x, self.cursor, self.width, h)
	end
	self.cursor = self.cursor + (h or 0) + (gapAfter or self.gap)
	return self
end

--- Coloca una fila horizontal de widgets que reparte el ancho de la columna.
--- Cada item: { widget, w = anchoFijo } o { widget, weight = peso, min = anchoMin }.
--- Los de ancho fijo reservan su 'w'; el resto se reparte por peso entre los flexibles.
---@param h number          altura de la fila
---@param items table[]     lista de items
---@param opts table|nil    { gap? }
function Column:row(h, items, opts)
	opts = opts or {}
	local gap = opts.gap or self.gap
	items = items or {}
	local n = #items

	-- 1) Reservar anchos fijos y sumar pesos de los flexibles.
	local fixedTotal = 0
	local weightTotal = 0
	for i = 1, n do
		local it = items[i]
		if it.w then
			fixedTotal = fixedTotal + it.w
		else
			weightTotal = weightTotal + (it.weight or 1)
		end
	end
	local gapsTotal = gap * math.max(0, n - 1)
	local flexSpace = math.max(0, self.width - fixedTotal - gapsTotal)

	-- 2) Colocar de izquierda a derecha.
	local x = self.x
	for i = 1, n do
		local it = items[i]
		local w
		if it.w then
			w = it.w
		else
			local share = (weightTotal > 0) and (flexSpace * (it.weight or 1) / weightTotal) or 0
			w = math.max(it.min or 0, math.floor(share))
		end
		local yoff = it.yoffset or 0
		self:_set(it.widget, x, self.cursor + yoff, w, it.h or h)
		x = x + w + gap
	end

	self.cursor = self.cursor + (h or 0) + self.gap
	return self
end

--- Bloque que ocupa todo el espacio vertical restante hasta 'bottom'.
--- Requiere haber pasado 'bottom' al crear la columna.
---@param widget any
---@param minH number|nil
---@return number height  altura asignada
function Column:fill(widget, minH)
	local bottom = self.bottom or (self.cursor + (minH or 120))
	local h = math.max(minH or 0, bottom - self.cursor)
	if widget then
		self:_set(widget, self.x, self.cursor, self.width, h)
	end
	self.cursor = self.cursor + h
	return h
end

--- Devuelve la Y actual del cursor (altura consumida desde el inicio).
---@return number
function Column:y()
	return self.cursor
end

--- Altura total consumida (desde startY).
---@return number
function Column:consumed()
	return self.cursor - self.startY
end

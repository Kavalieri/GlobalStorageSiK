--[[
	GlobalStorageSiK - Resaltado visual en el mundo (casillas y objetos)
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: WorldMarkers + FBO + setHighlighted como capas de fallback B42.
]]

require "GS_Log"

GlobalStorageSiK.WorldHighlight = GlobalStorageSiK.WorldHighlight or {}

---@type table[]
local squareMarkers = {}
---@type IsoObject[]
local fboObjects = {}
---@type IsoObject[]
local classicObjects = {}

--- Obtiene instancia FBO de resaltado.
---@return table|nil
local function fboInstance()
	if not FBORenderObjectHighlight or not FBORenderObjectHighlight.getInstance then
		return nil
	end
	return FBORenderObjectHighlight.getInstance()
end

--- Registra objeto en FBO.
---@param obj IsoObject|nil
---@return boolean
local function fboRegister(obj)
	if not obj then
		return false
	end
	local inst = fboInstance()
	if not inst or not inst.registerObject then
		return false
	end
	local ok = pcall(function()
		inst:registerObject(obj)
	end)
	if ok then
		fboObjects[#fboObjects + 1] = obj
	end
	return ok
end

--- Resaltado clásico IsoObject (contenedores, muebles).
---@param obj IsoObject|nil
---@param r number|nil
---@param g number|nil
---@param b number|nil
---@return boolean
local function classicHighlight(obj, r, g, b)
	if not obj then
		return false
	end
	local ok = pcall(function()
		if obj.setHighlighted then
			obj:setHighlighted(true)
		end
		if obj.setHighlightColor then
			obj:setHighlightColor(r or 0.35, g or 0.85, b or 0.45, 1)
		end
		if obj.setOutlineHighlight then
			obj:setOutlineHighlight(true)
		end
	end)
	if ok then
		classicObjects[#classicObjects + 1] = obj
	end
	return ok
end

--- Quita resaltado clásico de un objeto.
---@param obj IsoObject|nil
local function classicClear(obj)
	if not obj then
		return
	end
	pcall(function()
		if obj.setOutlineHighlight then
			obj:setOutlineHighlight(false)
		end
		if obj.setHighlighted then
			obj:setHighlighted(false)
		end
	end)
end

--- Añade marcador de casilla (selector de zona).
---@param sq IsoGridSquare|nil
---@param r number
---@param g number
---@param b number
---@param size number|nil
---@return table|nil marker
-- Diagnóstico de una sola vez: si ninguna de las dos APIs de marcador
-- funciona en este build de B42 (nombre cambiado, firma distinta, etc.),
-- antes fallaba en silencio (pcall se traga el error) y el botón "Mostrar
-- cobertura" no hacía nada visible sin explicación. Ahora se registra una
-- vez por sesión para poder diagnosticar sin adivinar a ciegas.
local _diagLogged = false
local function logMarkerDiag(reason)
	if _diagLogged then
		return
	end
	_diagLogged = true
	GlobalStorageSiK.Log.warn("WorldHighlight", "addSquareMarker: " .. tostring(reason),
		"WorldMarkers=" .. tostring(WorldMarkers ~= nil)
		.. ", WorldMarkers.addGridSquareMarker=" .. tostring(WorldMarkers and WorldMarkers.addGridSquareMarker ~= nil)
		.. ", IsoMarkers=" .. tostring(IsoMarkers ~= nil)
		.. ", IsoMarkers.addCircleIsoMarker=" .. tostring(IsoMarkers and IsoMarkers.addCircleIsoMarker ~= nil))
end

function GlobalStorageSiK.WorldHighlight.addSquareMarker(sq, r, g, b, size)
	if not sq then
		return nil
	end
	size = size or 0.48
	local marker = nil
	if WorldMarkers and WorldMarkers.addGridSquareMarker then
		local ok, result = pcall(function()
			return WorldMarkers.addGridSquareMarker(sq, r, g, b, true, size)
		end)
		if ok and result then
			marker = result
		elseif not ok then
			logMarkerDiag("WorldMarkers.addGridSquareMarker error: " .. tostring(result))
		end
	end
	if not marker and IsoMarkers and IsoMarkers.addCircleIsoMarker then
		local ok, err = pcall(function()
			marker = IsoMarkers.addCircleIsoMarker(sq, r, g, b, 0.55)
		end)
		if not ok then
			logMarkerDiag("IsoMarkers.addCircleIsoMarker error: " .. tostring(err))
		end
	end
	if not marker then
		logMarkerDiag("no marker API available/succeeded")
	end
	if marker then
		squareMarkers[#squareMarkers + 1] = marker
	end
	return marker
end

--- Resalta suelo y objetos visibles de una casilla (preview zona).
---@param sq IsoGridSquare|nil
---@param r number|nil
---@param g number|nil
---@param b number|nil
function GlobalStorageSiK.WorldHighlight.highlightSquare(sq, r, g, b)
	if not sq then
		return
	end
	r = r or 0.25
	g = g or 0.75
	b = b or 0.35
	GlobalStorageSiK.WorldHighlight.addSquareMarker(sq, r, g, b, 0.5)
	if sq.getFloor then
		fboRegister(sq:getFloor())
	end
	if sq.getObjects and sq.getObjects then
		local objects = sq:getObjects()
		if objects then
			for i = 0, objects:size() - 1 do
				local obj = objects:get(i)
				if obj and not fboRegister(obj) then
					classicHighlight(obj, r, g, b)
				end
			end
		end
	end
end

--- Resalta un objeto del mundo (contenedor).
---@param obj IsoObject|nil
---@param r number|nil
---@param g number|nil
---@param b number|nil
---@return boolean
function GlobalStorageSiK.WorldHighlight.highlightObject(obj, r, g, b)
	if not obj then
		return false
	end
	r = r or 0.35
	g = g or 0.88
	b = b or 0.42
	if fboRegister(obj) then
		return true
	end
	return classicHighlight(obj, r, g, b)
end

--- Rellena (o traza el perímetro de) una zona cuadrada alrededor de un
--- punto. `filled=true` cubre toda la superficie (pensado para radios
--- pequeños, ej. rango de uso del terminal); `filled=false` solo marca el
--- borde exterior (pensado para radios grandes, ej. alcance de vinculación
--- de red, donde rellenar todo el cuadrado generaría miles de marcadores).
---@param cell IsoCell|nil
---@param cx number
---@param cy number
---@param cz number
---@param radius number
---@param r number
---@param g number
---@param b number
---@param filled boolean
function GlobalStorageSiK.WorldHighlight.markArea(cell, cx, cy, cz, radius, r, g, b, filled)
	if not cell or not radius or radius <= 0 then
		return
	end
	radius = math.floor(radius)
	-- Usa highlightSquare (marcador + FBO de suelo + resaltado clasico de
	-- objetos), no solo addSquareMarker en solitario: si la API de
	-- "marcador" falla en este build de B42 (ver logMarkerDiag), el tinte de
	-- suelo (FBO/setHighlighted) es la capa con mas probabilidad real de
	-- verse, en vez de depender de una unica API sin confirmar.
	for dx = -radius, radius do
		for dy = -radius, radius do
			local onEdge = (math.abs(dx) == radius or math.abs(dy) == radius)
			if filled or onEdge then
				local sq = cell:getGridSquare(cx + dx, cy + dy, cz)
				if sq then
					GlobalStorageSiK.WorldHighlight.highlightSquare(sq, r, g, b)
				end
			end
		end
	end
end

--- Limpia todos los resaltados activos.
function GlobalStorageSiK.WorldHighlight.clearAll()
	if WorldMarkers and WorldMarkers.removeGridSquareMarker then
		for i = 1, #squareMarkers do
			local marker = squareMarkers[i]
			pcall(function()
				if marker.getID then
					WorldMarkers.removeGridSquareMarker(marker:getID())
				elseif type(marker) == "number" then
					WorldMarkers.removeGridSquareMarker(marker)
				end
			end)
		end
	end
	squareMarkers = {}

	local inst = fboInstance()
	if inst and inst.unregisterObject then
		for i = 1, #fboObjects do
			pcall(function()
				inst:unregisterObject(fboObjects[i])
			end)
		end
	end
	fboObjects = {}

	for i = 1, #classicObjects do
		classicClear(classicObjects[i])
	end
	classicObjects = {}
end

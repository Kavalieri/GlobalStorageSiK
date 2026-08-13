--[[
	GlobalStorageSiK - Escáner de contenedores por zona
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Detecta contenedores en una zona sin clic en el mundo.
]]

require "GS_Utils"
require "GS_Zones"
require "GS_ItemSnapshot"

GlobalStorageSiK.ZoneScanner = {}

---@param zone table
---@param maxContainers number|nil
---@return table[] results
---@return boolean limitHit
---@return boolean anySquareLoaded true si al menos una baldosa de la zona estaba cargada
function GlobalStorageSiK.ZoneScanner.scanZone(zone, maxContainers)
	local results = {}
	if not zone or not zone.bounds then
		return results, false, false
	end

	local cell = getCell and getCell() or nil
	if not cell then
		return results, false, false
	end

	local limit = maxContainers or 128
	local limitHit = false
	local anySquareLoaded = false
	local b = zone.bounds
	local x1 = math.min(b.x1 or b.x, b.x2 or b.x)
	local x2 = math.max(b.x1 or b.x, b.x2 or b.x)
	local y1 = math.min(b.y1 or b.y, b.y2 or b.y)
	local y2 = math.max(b.y1 or b.y, b.y2 or b.y)
	local zMin = b.z or b.zMin or 0
	local zMax = b.zMax or zMin

	for z = zMin, zMax do
		for x = x1, x2 do
			for y = y1, y2 do
				if #results >= limit then
					return results, true, anySquareLoaded
				end

				local square = cell:getGridSquare(x, y, z)
				if square then
					anySquareLoaded = true
					if GlobalStorageSiK.ZoneScanner.scanSquare(square, zone.id, results, limit) then
						limitHit = true
						return results, true, anySquareLoaded
					end
				end
			end
		end
	end

	return results, limitHit, anySquareLoaded
end

--- Añade contenedores de una baldosa a la lista de resultados.
---@param square IsoGridSquare
---@param zoneId string
---@param results table[]
---@param limit number
---@return boolean|nil limitHit true si se alcanzó el límite
function GlobalStorageSiK.ZoneScanner.scanSquare(square, zoneId, results, limit)
	-- Un mismo objeto del mundo puede exponer varios contenedores reales
	-- (mueble con nevera+congelador combinados, etc. - ver GS_Utils.lua,
	-- getContainerCount/getContainerByIndex): se registra UNA entrada por
	-- cada indice, no solo la del contenedor 0, o el resto quedaba invisible.
	local function tryObject(obj)
		local count = GlobalStorageSiK.Utils.getContainerCount(obj)
		for containerIndex = 0, count - 1 do
			if #results >= limit then
				return true
			end
			local entry = GlobalStorageSiK.Utils.buildContainerEntry(obj, containerIndex)
			if entry then
				entry.zoneId = zoneId
				entry.membership = "auto"
				entry.enabled = true
				entry.displayName = obj:getName() or entry.name
				local container = GlobalStorageSiK.Utils.getObjectContainer(obj, containerIndex)
				if container then
					entry.itemSnapshot = GlobalStorageSiK.ItemSnapshot.fromContainer(container)
					if container.getCapacity then
						local okCap, cap = pcall(function()
							return container:getCapacity()
						end)
						if okCap and cap and cap > 0 then
							entry.storedCapacity = cap
						end
					end
				end
				table.insert(results, entry)
			end
		end
		return false
	end

	for i = 0, square:getObjects():size() - 1 do
		if tryObject(square:getObjects():get(i)) then
			return true
		end
	end
	if square.getSpecialObjects then
		for i = 0, square:getSpecialObjects():size() - 1 do
			if tryObject(square:getSpecialObjects():get(i)) then
				return true
			end
		end
	end
	return false
end

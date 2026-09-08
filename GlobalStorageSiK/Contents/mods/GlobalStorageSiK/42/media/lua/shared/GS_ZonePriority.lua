--[[
	GlobalStorageSiK - Prioridad de zonas en escaneo
	Autor: SiK
	Fecha: 2025-06-26
	Descripción: Orden explícito de zonas; menor número = mayor prioridad.
]]

require "GS_Zones"

GlobalStorageSiK.ZonePriority = {}

--- Área en baldosas de una zona.
---@param zone table
---@return number
function GlobalStorageSiK.ZonePriority.zoneArea(zone)
	if type(zone) ~= "table" then
		return math.huge
	end
	local x1, x2, y1, y2, zMin, zMax = GlobalStorageSiK.ZoneBounds.normalize(zone.bounds)
	if x1 == nil then return math.huge end
	return (x2 - x1 + 1) * (y2 - y1 + 1) * (zMax - zMin + 1)
end

--- Asigna prioridades 1..N a zonas de red sin prioridad (por área ascendente).
---@param registry table
---@param networkId string
function GlobalStorageSiK.ZonePriority.ensurePriorities(registry, networkId)
	local list = {}
	for _, zone in pairs(registry.zones or {}) do
		if zone.networkId == networkId and zone.enabled ~= false then
			table.insert(list, zone)
		end
	end
	table.sort(list, function(a, b)
		local pa = tonumber(a.priority)
		local pb = tonumber(b.priority)
		if pa and pb and pa ~= pb then
			return pa < pb
		end
		if pa and not pb then
			return true
		end
		if pb and not pa then
			return false
		end
		local aa = GlobalStorageSiK.ZonePriority.zoneArea(a)
		local ab = GlobalStorageSiK.ZonePriority.zoneArea(b)
		if aa ~= ab then
			return aa < ab
		end
		return (a.id or "") < (b.id or "")
	end)
	for i = 1, #list do
		if list[i].priority == nil then
			list[i].priority = i
		end
	end
end

--- Lista zonas de red ordenadas por prioridad ascendente.
---@param registry table
---@param networkId string
---@return table[]
function GlobalStorageSiK.ZonePriority.listSorted(registry, networkId)
	GlobalStorageSiK.ZonePriority.ensurePriorities(registry, networkId)
	local list = {}
	for _, zone in pairs(registry.zones or {}) do
		if zone.networkId == networkId and zone.enabled ~= false then
			table.insert(list, zone)
		end
	end
	table.sort(list, function(a, b)
		local pa = tonumber(a.priority) or math.huge
		local pb = tonumber(b.priority) or math.huge
		if pa ~= pb then
			return pa < pb
		end
		return (a.name or a.id or ""):lower() < (b.name or b.id or ""):lower()
	end)
	return list
end

--- Ordena tabla serializada de zonas (cliente).
---@param zones table[]
---@return table[]
function GlobalStorageSiK.ZonePriority.sortSerialized(zones)
	table.sort(zones, function(a, b)
		local pa = tonumber(a.priority) or math.huge
		local pb = tonumber(b.priority) or math.huge
		if pa ~= pb then
			return pa < pb
		end
		return (a.name or a.id or ""):lower() < (b.name or b.id or ""):lower()
	end)
	return zones
end

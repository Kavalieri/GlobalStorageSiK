--[[
	GlobalStorageSiK - Categorías de red (servidor, sincronizadas)
	Autor: SiK
	Fecha: 2025-06-24
]]

require "GS_Network"
require "GS_Zones"
require "GS_Index"
require "GS_ItemTaxonomy"

GlobalStorageSiK.Categories = {}

-- Bootstrap reducido para redes nuevas. La detección real de categorías se
-- delega a GS_ItemTaxonomy. Food debe estar aquí: solo los perecederos se
-- reescriben a FoodPerishable; la comida estable conserva Food general.
GlobalStorageSiK.Categories.DEFAULTS = {
	"Ammo",
	"Clothing",
	"Container",
	"Cooking",
	"Electronics",
	"Food",
	"Literature",
	"Tool",
	"VehicleMaintenance",
	"WeaponPart",
}

--- Asegura lista de categorías en la red.
---@param registry table
---@param networkId string
function GlobalStorageSiK.Categories.ensure(registry, networkId)
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local net = registry.networks[networkId]
	if not net.categories or #net.categories == 0 then
		net.categories = {}
		for i = 1, #GlobalStorageSiK.Categories.DEFAULTS do
			table.insert(net.categories, GlobalStorageSiK.Categories.DEFAULTS[i])
		end
	end
end

--- Devuelve categorías de una red.
---@param networkId string|nil
---@return string[]
function GlobalStorageSiK.Categories.getList(networkId)
	local registry = GlobalStorageSiK.Network.getRegistry()
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	GlobalStorageSiK.Categories.ensure(registry, networkId)
	return registry.networks[networkId].categories
end

--- Añade categoría si no existe.
---@param networkId string
---@param name string
---@return boolean added
function GlobalStorageSiK.Categories.add(networkId, name)
	name = name and string.gsub(name, "^%s*(.-)%s*$", "%1") or ""
	if name == "" then
		return false
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Categories.ensure(registry, networkId)
	local list = registry.networks[networkId].categories
	for i = 1, #list do
		if string.lower(list[i]) == string.lower(name) then
			return false
		end
	end
	table.insert(list, name)
	table.sort(list, function(a, b) return a < b end)
	return true
end

--- Recoge categorías de ítems indexados en la red (solo DisplayCategory válidas).
---@param networkId string
---@return string[]
function GlobalStorageSiK.Categories.collectFromNetworkItems(networkId)
	local found = {}
	local seen = {}
	local rows = GlobalStorageSiK.Index.buildRows(networkId)
	for i = 1, #rows do
		local row = rows[i]
		local scriptItem = nil
		if getScriptManager then
			local sm = getScriptManager()
			if sm and sm.getItem and row.fullType then
				scriptItem = sm:getItem(row.fullType)
			end
		end
		local cat = GlobalStorageSiK.ItemTaxonomy.readMainKey(nil, scriptItem, row.category)
		if cat and cat ~= "" and GlobalStorageSiK.ItemTaxonomy.isDisplayCategoryKey(cat)
			and not seen[string.lower(cat)] then
			seen[string.lower(cat)] = true
			table.insert(found, cat)
		end
	end
	return found
end

--- Recoge categorías ya asignadas a contenedores de la red.
---@param networkId string
---@return string[]
function GlobalStorageSiK.Categories.collectFromNodeRules(networkId)
	local found = {}
	local seen = {}
	local registry = GlobalStorageSiK.Zones.getRegistry()
	for _, node in pairs(registry.nodes or {}) do
		local zone = registry.zones and registry.zones[node.zoneId]
		if zone and zone.networkId == networkId and node.categories then
			for j = 1, #node.categories do
				local cat = GlobalStorageSiK.ItemTaxonomy.normalizeDisplayCategoryKey(node.categories[j])
				if cat and cat ~= "" and cat ~= "*"
					and GlobalStorageSiK.ItemTaxonomy.isDisplayCategoryKey(cat)
					and not seen[string.lower(cat)] then
					seen[string.lower(cat)] = true
					table.insert(found, cat)
				end
			end
		end
	end
	return found
end

--- Catálogo para desplegables de contenedores (defaults + red + ítems presentes).
---@param networkId string
---@return string[]
function GlobalStorageSiK.Categories.buildCatalog(networkId)
	local seen = {}
	local catalog = {}

	local function add(cat)
		cat = GlobalStorageSiK.ItemTaxonomy.normalizeDisplayCategoryKey(cat)
		if not cat or cat == "" or cat == "*" then
			return
		end
		if not GlobalStorageSiK.ItemTaxonomy.isDisplayCategoryKey(cat) then
			return
		end
		local key = string.lower(cat)
		if seen[key] then
			return
		end
		seen[key] = true
		table.insert(catalog, cat)
	end

	for i = 1, #GlobalStorageSiK.Categories.DEFAULTS do
		add(GlobalStorageSiK.Categories.DEFAULTS[i])
	end
	for _, cat in ipairs(GlobalStorageSiK.Categories.getList(networkId)) do
		add(cat)
	end
	for _, cat in ipairs(GlobalStorageSiK.Categories.collectFromNetworkItems(networkId)) do
		add(cat)
	end
	for _, cat in ipairs(GlobalStorageSiK.Categories.collectFromNodeRules(networkId)) do
		add(cat)
	end

	table.sort(catalog, function(a, b)
		local la = GlobalStorageSiK.ItemTaxonomy.translateMainKey(a)
		local lb = GlobalStorageSiK.ItemTaxonomy.translateMainKey(b)
		return string.lower(la) < string.lower(lb)
	end)
	return catalog
end

--- Serializa catálogo detectado para el cliente.
---@param networkId string
---@return string[]
function GlobalStorageSiK.Categories.serialize(networkId)
	return GlobalStorageSiK.Categories.buildCatalog(networkId)
end

--[[
	GlobalStorageSiK - Instantánea de ítems en contenedor (MP / servidor)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Cachea inventario al escanear para cuando el chunk no está cargado en servidor.
]]

require "GS_Router"
require "GS_I18n"
require "GS_Subcategories"

GlobalStorageSiK.ItemSnapshot = {}

-- Metadatos invariantes por fullType. La UI de PZ puede mostrar una "pila"
-- de 100 clavos como una sola fila aunque internamente sean muchas instancias.
-- Debemos contar cada instancia/itemId para transferir con exactitud, pero no
-- volver a resolver nombre, taxonomía y subcategorías cien veces. El snapshot
-- ya agregaba por fullType, así que esta caché conserva su semántica.
local metadataByFullType = {}

local function readWorldSprite(item)
	if not item then return nil end
	local sprite = nil
	if item.getWorldSprite then
		local ok, value = pcall(function() return item:getWorldSprite() end)
		if ok then sprite = value end
	end
	if (not sprite or sprite == "") and item.getModData then
		local ok, md = pcall(function() return item:getModData() end)
		if ok and md then
			sprite = md.WorldObjectSprite or md.worldObjectSprite or md.worldSprite or md.sprite
		end
	end
	if sprite == "" then return nil end
	return sprite
end

local function metadataForItem(item, fullType)
	local worldSprite = readWorldSprite(item)
	local cacheKey = fullType .. "\31" .. tostring(worldSprite or "")
	local cached = metadataByFullType[cacheKey]
	if cached then return cached end
	local gsKeysList = GlobalStorageSiK.Subcategories.keysForItem(item) or {}
	local displayName = GlobalStorageSiK.I18n.nameFromItemInstance(item, fullType)
	if not displayName or GlobalStorageSiK.I18n.isLowQualityDisplayName(displayName) then
		displayName = GlobalStorageSiK.I18n.moveableDisplayNameFromSprite(worldSprite)
	end
	cached = {
		fullType = fullType,
		displayName = displayName or GlobalStorageSiK.I18n.typeDisplayName(fullType),
		worldSprite = worldSprite,
		category = GlobalStorageSiK.Router.getItemCategory(item),
		subCategory = GlobalStorageSiK.Router.getItemSubCategory(item),
		gsSubKeys = gsKeysList,
		gsSubKeysStr = table.concat(gsKeysList, "|"),
	}
	metadataByFullType[cacheKey] = cached
	return cached
end

--- Incorpora una instancia a un mapa de snapshot ya existente. Esta es la
--- primitiva incremental usada por el escaneo servidor: conserva exactamente
--- el mismo formato que fromContainer(), pero permite repartir contenedores
--- con miles de objetos entre varios ticks sin mantener un bucle monolitico.
---@param byType table<string, table>
---@param item InventoryItem|nil
---@param knownFullType string|nil evita repetir getFullType si el caller ya lo leyó
---@return boolean added
function GlobalStorageSiK.ItemSnapshot.addItem(byType, item, knownFullType)
	if not byType or not item or not item.getFullType then
		return false
	end
	local fullType = knownFullType or item:getFullType()
	if not fullType or fullType == "" then
		return false
	end
	local row = byType[fullType]
	if not row then
		local metadata = metadataForItem(item, fullType)
		row = {
			fullType = fullType,
			displayName = metadata.displayName,
			worldSprite = metadata.worldSprite,
			category = metadata.category,
			subCategory = metadata.subCategory,
			gsSubKeys = metadata.gsSubKeys,
			gsSubKeysStr = metadata.gsSubKeysStr,
			count = 0,
		}
		byType[fullType] = row
	end
	-- InventoryItem:getCount() NO es el número de instancias transferibles. En
	-- objetos como Base.Nails puede devolver el multiplicador definido por el
	-- script o por el contexto de receta (3/5), aunque este itemId siga siendo
	-- una sola entrada física. Usarlo aquí inflaba 84 clavos hasta 420 y hacía
	-- que la retirada eliminase 84 IDs mientras confirmaba 420 unidades.
	row.count = row.count + 1
	return true
end

--- Serializa ítems de un contenedor por tipo.
---@param container ItemContainer
---@return table<string, table>
function GlobalStorageSiK.ItemSnapshot.fromContainer(container)
	local byType = {}
	if not container or not container.getItems then
		return byType
	end
	local items = container:getItems()
	for i = 0, items:size() - 1 do
		GlobalStorageSiK.ItemSnapshot.addItem(byType, items:get(i))
	end
	return byType
end

--- Fusiona dos mapas por tipo (suma cantidades).
---@param target table<string, table>
---@param source table<string, table>
function GlobalStorageSiK.ItemSnapshot.mergeMaps(target, source)
	for fullType, row in pairs(source or {}) do
		local existing = target[fullType]
		if not existing then
			target[fullType] = {
				fullType = row.fullType,
				displayName = row.displayName,
				worldSprite = row.worldSprite,
				category = row.category,
				subCategory = row.subCategory,
				gsSubKeys = row.gsSubKeys or {},
				gsSubKeysStr = row.gsSubKeysStr or "",
				count = row.count or 0,
			}
		else
			existing.count = (existing.count or 0) + (row.count or 0)
		end
	end
end

--- Convierte mapa a filas ordenadas para el terminal.
---@param byType table<string, table>
---@return table[]
function GlobalStorageSiK.ItemSnapshot.toRows(byType)
	local rows = {}
	for _, row in pairs(byType or {}) do
		table.insert(rows, row)
	end
	table.sort(rows, function(a, b)
		return (a.displayName or "") < (b.displayName or "")
	end)
	return rows
end

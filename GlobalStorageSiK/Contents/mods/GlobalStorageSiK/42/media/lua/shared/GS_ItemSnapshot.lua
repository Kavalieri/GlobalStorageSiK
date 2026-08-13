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
		local item = items:get(i)
		if item then
			local fullType = item:getFullType()
			local displayName = GlobalStorageSiK.I18n.nameFromItemInstance(item, fullType)
				or GlobalStorageSiK.I18n.typeDisplayName(fullType)
			local row = byType[fullType]
			if not row then
				-- gsSubKeys se manda TAMBIEN como string "|"-separado
				-- (gsSubKeysStr): confirmado con NetTrace que una tabla
				-- anidada 3 niveles dentro del payload de red (items[] ->
				-- row -> gsSubKeys[]) se pierde en la transmision servidor
				-- -> cliente (llega nil aunque aqui se calcule bien) — la
				-- serializacion de comandos de red de PZ no soporta esa
				-- profundidad de anidamiento. Un string plano si sobrevive.
				local gsKeysList = GlobalStorageSiK.Subcategories.keysForItem(item) or {}
				row = {
					fullType = fullType,
					displayName = displayName,
					category = GlobalStorageSiK.Router.getItemCategory(item),
					subCategory = GlobalStorageSiK.Router.getItemSubCategory(item),
					gsSubKeys = gsKeysList,
					gsSubKeysStr = table.concat(gsKeysList, "|"),
					count = 0,
				}
				byType[fullType] = row
			elseif displayName and displayName ~= fullType
				and (not row.displayName or row.displayName == "" or row.displayName == fullType) then
				row.displayName = displayName
			end
			row.count = row.count + (item.getCount and item:getCount() or 1)
		end
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

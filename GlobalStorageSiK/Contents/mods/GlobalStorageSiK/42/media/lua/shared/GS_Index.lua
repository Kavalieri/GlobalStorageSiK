--[[
	GlobalStorageSiK - Índice agregado de la red
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Construye índice por tipo de ítem para búsqueda y terminal.
]]

require "GS_Network"
require "GS_Router"
require "GS_Zones"
require "GS_ItemSnapshot"
require "GS_ZoneRefresh"
require "GS_NativeProduct"
require "GS_CategoryResolution"
require "GS_Permissions"

GlobalStorageSiK.Index = {}

--- Fusiona filas de contenedor vivo en el mapa por tipo.
---@param byType table<string, table>
---@param container ItemContainer
---@param nodeId string
--- Añade/acumula la contribucion de UN nodo al desglose de ubicaciones de una
--- fila agregada - dev26 ronda 4quinquies (pestaña Almacén: columna "Zona" y
--- "Localizar objeto" del menú contextual). Antes solo se guardaba
--- `nodeId`/`existing.nodeId` del PRIMER nodo fusionado, sin actualizarlo
--- nunca mas - para un ítem repartido en varios contenedores, ese valor era
--- practicamente arbitrario (dependia del orden de iteracion de `pairs()`,
--- no determinista entre refrescos) y por tanto no fiable para resaltar "el"
--- contenedor real. `locations` guarda TODAS las contribuciones reales.
---@param row table fila agregada existente (byType[fullType])
---@param nodeId string
---@param count number
local function addLocation(row, nodeId, count)
	if not nodeId or not count or count <= 0 then
		return
	end
	row.locations = row.locations or {}
	for i = 1, #row.locations do
		if row.locations[i].nodeId == nodeId then
			row.locations[i].count = row.locations[i].count + count
			return
		end
	end
	row.locations[#row.locations + 1] = { nodeId = nodeId, count = count }
end

local function copyArray(values)
	local out = {}
	for i = 1, #(values or {}) do out[i] = values[i] end
	return out
end

local function copyMap(values)
	local out = {}
	for key, value in pairs(values or {}) do out[key] = value end
	return out
end

local function mergeLiveContainer(byType, container, nodeId)
	if not container then
		return
	end
	local snap = GlobalStorageSiK.ItemSnapshot.fromContainer(container)
	for groupKey, row in pairs(snap) do
		local existing = byType[groupKey]
		if not existing then
			byType[groupKey] = {
				rowKey = row.rowKey or groupKey,
				fullType = row.fullType,
				displayName = row.displayName,
				worldSprite = row.worldSprite,
				category = row.category,
				subCategory = row.subCategory,
				gsSubKeys = row.gsSubKeys or {},
				gsSubKeysStr = row.gsSubKeysStr or "",
				learnedRecipeNames = row.learnedRecipeNames,
				numberOfPages = row.numberOfPages,
				literatureTitle = row.literatureTitle,
				mediaIndex = row.mediaIndex,
				mediaTitle = row.mediaTitle,
				mediaCodes = row.mediaCodes,
				dynamicSignature = row.dynamicSignature,
				dynamicStateKey = row.dynamicStateKey,
				dynamicPercent = row.dynamicPercent,
				fluidState = row.fluidState,
				foodState = row.foodState,
				shapeFamily = row.shapeFamily,
				productFamilyKey = row.productFamilyKey,
				shapeKey = row.shapeKey,
				conditionSignature = row.conditionSignature,
				condition = row.condition,
				conditionMax = row.conditionMax,
				detailKind = row.detailKind,
				variantKey = row.variantKey,
				itemIds = copyArray(row.itemIds),
				unitDetails = copyMap(row.unitDetails),
				totalWeight = row.totalWeight or 0,
				totalFluidAmount = row.totalFluidAmount or 0,
				totalFluidCapacity = row.totalFluidCapacity or 0,
				nativePath = row.nativePath,
				nativeStatus = row.nativeStatus,
				vanillaKey = row.vanillaKey,
				effective = row.effective,
				categoryEffective = row.categoryEffective,
				routingIdentity = row.routingIdentity,
				categorySource = row.categorySource,
				count = row.count,
				nodeId = nodeId,
			}
			addLocation(byType[groupKey], nodeId, row.count)
		else
			existing.count = existing.count + row.count
			existing.itemIds = existing.itemIds or {}
			for j = 1, #(row.itemIds or {}) do existing.itemIds[#existing.itemIds + 1] = row.itemIds[j] end
			existing.unitDetails = existing.unitDetails or {}
			for itemId, detail in pairs(row.unitDetails or {}) do existing.unitDetails[itemId] = detail end
			existing.totalWeight = (existing.totalWeight or 0) + (row.totalWeight or 0)
			existing.totalFluidAmount = (existing.totalFluidAmount or 0) + (row.totalFluidAmount or 0)
			existing.totalFluidCapacity = (existing.totalFluidCapacity or 0) + (row.totalFluidCapacity or 0)
			addLocation(existing, nodeId, row.count)
		end
	end
end

--- Fusiona snapshot persistido de un nodo.
---@param byType table<string, table>
---@param node table
local function mergeNodeSnapshot(byType, node)
	if not node or not node.itemSnapshot then
		return
	end
	for groupKey, row in pairs(node.itemSnapshot) do
		local existing = byType[groupKey]
		if not existing then
			byType[groupKey] = {
				rowKey = row.rowKey or groupKey,
				fullType = row.fullType,
				displayName = row.displayName,
				worldSprite = row.worldSprite,
				category = row.category,
				subCategory = row.subCategory,
				gsSubKeys = row.gsSubKeys or {},
				gsSubKeysStr = row.gsSubKeysStr or "",
				learnedRecipeNames = row.learnedRecipeNames,
				numberOfPages = row.numberOfPages,
				literatureTitle = row.literatureTitle,
				mediaIndex = row.mediaIndex,
				mediaTitle = row.mediaTitle,
				mediaCodes = row.mediaCodes,
				dynamicSignature = row.dynamicSignature,
				dynamicStateKey = row.dynamicStateKey,
				dynamicPercent = row.dynamicPercent,
				fluidState = row.fluidState,
				foodState = row.foodState,
				shapeFamily = row.shapeFamily,
				productFamilyKey = row.productFamilyKey,
				shapeKey = row.shapeKey,
				conditionSignature = row.conditionSignature,
				condition = row.condition,
				conditionMax = row.conditionMax,
				detailKind = row.detailKind,
				variantKey = row.variantKey,
				itemIds = copyArray(row.itemIds),
				unitDetails = copyMap(row.unitDetails),
				totalWeight = row.totalWeight or 0,
				totalFluidAmount = row.totalFluidAmount or 0,
				totalFluidCapacity = row.totalFluidCapacity or 0,
				nativePath = row.nativePath,
				nativeStatus = row.nativeStatus,
				vanillaKey = row.vanillaKey,
				effective = row.effective,
				categoryEffective = row.categoryEffective,
				routingIdentity = row.routingIdentity,
				categorySource = row.categorySource,
				count = row.count or 0,
				nodeId = node.id,
			}
			addLocation(byType[groupKey], node.id, row.count or 0)
		else
			existing.count = (existing.count or 0) + (row.count or 0)
			existing.itemIds = existing.itemIds or {}
			for j = 1, #(row.itemIds or {}) do existing.itemIds[#existing.itemIds + 1] = row.itemIds[j] end
			existing.unitDetails = existing.unitDetails or {}
			for itemId, detail in pairs(row.unitDetails or {}) do existing.unitDetails[itemId] = detail end
			existing.totalWeight = (existing.totalWeight or 0) + (row.totalWeight or 0)
			existing.totalFluidAmount = (existing.totalFluidAmount or 0) + (row.totalFluidAmount or 0)
			existing.totalFluidCapacity = (existing.totalFluidCapacity or 0) + (row.totalFluidCapacity or 0)
			addLocation(existing, node.id, row.count or 0)
		end
	end
end

local variantFamilyCache = {}
local function variantFamilyKey(fullType)
	if variantFamilyCache[fullType] then return variantFamilyCache[fullType] end
	local mod, name = tostring(fullType or ""):match("^([^%.]+)%.(.+)$")
	local family = fullType
	if mod and name then
		local base = name:match("^(.-)%d+$")
		if base and base ~= "" then
			local candidate = mod .. "." .. base
			local script = GlobalStorageSiK.I18n.getScriptItem
				and GlobalStorageSiK.I18n.getScriptItem(candidate) or nil
			if script then family = candidate end
		end
	end
	variantFamilyCache[fullType] = family
	return family
end

local function parentKeyForRow(row)
        local key = tostring(variantFamilyKey(row.fullType) or "")
                .. "\31sprite:" .. tostring(row.worldSprite or "")
        -- Vanilla identifica las grabaciones por el índice autoritativo del
        -- medio, no solo por el tipo físico VHSTape. Mantenerlo en la clave del
        -- padre agrupa duplicados del mismo programa sin mezclar títulos.
	if row.mediaIndex ~= nil then
		key = key .. "\31media:" .. tostring(row.mediaIndex)
	end
	-- ItemSnapshot ya separa los fluidos por identidad canónica
	-- (forma + contenido/composición). Conservar esa identidad al compactar
	-- evita volver a mezclar, por ejemplo, un bidón lleno y otro vacío del
	-- mismo fullType, y mantiene exact_group limitado al grupo elegido.
	if row.dynamicSignature ~= nil and row.dynamicSignature ~= "" then
		key = key .. "\31dynamic:" .. tostring(row.dynamicSignature)
	end
	return key
end

local function detailKindForRow(row)
	if row.detailKind then return row.detailKind end
	if row.mediaIndex ~= nil or row.mediaTitle then return "recorded_media" end
	if row.dynamicSignature then return "fluid" end
	if row.conditionSignature then return "condition" end
	if row.literatureTitle or row.learnedRecipeNames or row.numberOfPages then return "literature" end
	return nil
end

local function compactParentRows(detailRows)
	local byParent = {}
	for i = 1, #detailRows do
		local detail = detailRows[i]
		local parentKey = parentKeyForRow(detail)
		local parent = byParent[parentKey]
		if not parent then
			parent = {
				rowKey = parentKey, fullType = detail.fullType,
				displayName = detail.displayName, worldSprite = detail.worldSprite,
				category = detail.category, subCategory = detail.subCategory,
				gsSubKeys = detail.gsSubKeys or {}, gsSubKeysStr = detail.gsSubKeysStr or "",
                                learnedRecipeNames = detail.learnedRecipeNames,
                                numberOfPages = detail.numberOfPages,
						mediaIndex = detail.mediaIndex, mediaTitle = detail.mediaTitle,
						mediaCodes = detail.mediaCodes,
				count = 0, locations = {}, variantSummary = {}, totalWeight = 0, foodSummary = {},
				totalFluidAmount = 0, totalFluidCapacity = 0,
				_variantSeen = {}, _pathSeen = {}, _detailKinds = {}, _fullTypeSeen = {},
			}
			byParent[parentKey] = parent
		end
		parent.count = parent.count + (detail.count or 0)
		-- Summarize six visible food states once while building the capture.
		-- Render/search must not walk every physical variant on every frame.
		if detail.foodState then
			local food = detail.foodState
			if food.rotten == true then parent.foodSummary.Rotten = true
			elseif food.fresh == true then parent.foodSummary.Fresh = true
			elseif food.fresh == false then parent.foodSummary.Stale = true end
			if food.burnt == true then parent.foodSummary.Burnt = true
			elseif food.cooked == true then parent.foodSummary.Cooked = true end
			if food.frozen == true then parent.foodSummary.Frozen = true end
		end
		parent.totalWeight = parent.totalWeight + (detail.totalWeight or 0)
		parent.totalFluidAmount = parent.totalFluidAmount + (detail.totalFluidAmount or 0)
		parent.totalFluidCapacity = parent.totalFluidCapacity + (detail.totalFluidCapacity or 0)
		parent._fullTypeSeen[detail.fullType] = true
		for j = 1, #(detail.locations or {}) do
			addLocation(parent, detail.locations[j].nodeId, detail.locations[j].count)
		end
		if detail.nodeId and #(detail.locations or {}) == 0 then
			addLocation(parent, detail.nodeId, detail.count or 0)
		end
		local detailKind = detailKindForRow(detail)
		local variantKey = tostring(detail.fullType) .. "\31" .. tostring(detail.variantKey or detail.rowKey or "fungible")
		local summary = parent._variantSeen[variantKey]
		if not summary then
			summary = {
				key = variantKey, count = 0, detailKind = detailKind,
				fullType = detail.fullType, displayName = detail.displayName,
				mediaIndex = detail.mediaIndex, mediaTitle = detail.mediaTitle,
				mediaCodes = detail.mediaCodes,
				dynamicSignature = detail.dynamicSignature,
				dynamicStateKey = detail.dynamicStateKey,
				dynamicPercent = detail.dynamicPercent,
				fluidState = detail.fluidState,
				foodState = detail.foodState,
				shapeFamily = detail.shapeFamily,
				productFamilyKey = detail.productFamilyKey,
				shapeKey = detail.shapeKey,
				condition = detail.condition, conditionMax = detail.conditionMax,
				nativePath = detail.nativePath,
			}
			parent._variantSeen[variantKey] = summary
			parent.variantSummary[#parent.variantSummary + 1] = summary
		end
		summary.count = summary.count + (detail.count or 0)
		if detailKind then parent._detailKinds[detailKind] = true end
		if detail.nativePath then parent._pathSeen[detail.nativePath] = true end
	end

	local rows = {}
	for _, parent in pairs(byParent) do
		local variantCount, pathCount, kindCount, fullTypeCount = 0, 0, 0, 0
		for _ in pairs(parent._variantSeen) do variantCount = variantCount + 1 end
		for _ in pairs(parent._pathSeen) do pathCount = pathCount + 1 end
		for _ in pairs(parent._detailKinds) do kindCount = kindCount + 1 end
		for _ in pairs(parent._fullTypeSeen) do fullTypeCount = fullTypeCount + 1 end
		parent.variantCount = variantCount
		parent.categoryCount = pathCount
		parent.nativePaths = {}
		for nativePath in pairs(parent._pathSeen) do
			parent.nativePaths[#parent.nativePaths + 1] = nativePath
		end
		table.sort(parent.nativePaths)
		parent.locationCount = #parent.locations
		local variantSearchParts = {}
		for i = 1, #parent.variantSummary do
			local summary = parent.variantSummary[i]
			variantSearchParts[#variantSearchParts + 1] = tostring(summary.key or "")
			if summary.displayName then variantSearchParts[#variantSearchParts + 1] = summary.displayName end
			if summary.mediaTitle then variantSearchParts[#variantSearchParts + 1] = summary.mediaTitle end
			if summary.dynamicStateKey then variantSearchParts[#variantSearchParts + 1] = summary.dynamicStateKey end
			if summary.nativePath then variantSearchParts[#variantSearchParts + 1] = summary.nativePath end
		end
		parent.variantSearchText = table.concat(variantSearchParts, " ")
                if parent._detailKinds.recorded_media and parent.mediaTitle then
                        parent.displayName = parent.mediaTitle
		end
		parent.cosmeticVariants = fullTypeCount > 1
		parent.fullTypes = {}
		for fullType in pairs(parent._fullTypeSeen) do parent.fullTypes[#parent.fullTypes + 1] = fullType end
		table.sort(parent.fullTypes)
		if parent.cosmeticVariants then
			local familyFullType = variantFamilyKey(parent.fullType)
			parent.fullType = familyFullType
			parent.displayName = GlobalStorageSiK.I18n.typeDisplayName(familyFullType)
		end
		parent.expandable = parent.count > 1
		parent.aggregateAllowed = parent.count == 1 or kindCount == 0
			or (parent._detailKinds.recorded_media and parent.mediaIndex ~= nil)
		parent.selectionMode = (kindCount > 0 or parent.cosmeticVariants)
			and "exact_group" or "aggregate"
		parent.detailMode = parent.cosmeticVariants and kindCount == 0 and "variants" or "instances"
		parent.mixedVariants = pathCount > 1
		-- Un padre que mezcla rutas no inventa una categoría representativa. La
		-- UI lo etiqueta como «Varias categorías» y cada hijo conserva la suya.
		if not parent.mixedVariants and #parent.variantSummary > 0 then
			parent.nativePath = parent.variantSummary[1].nativePath
		end
		parent._variantSeen, parent._pathSeen, parent._detailKinds, parent._fullTypeSeen = nil, nil, nil, nil
		rows[#rows + 1] = parent
	end
	table.sort(rows, function(a, b)
		local an, bn = tostring(a.displayName or ""), tostring(b.displayName or "")
		if an == bn then return tostring(a.rowKey) < tostring(b.rowKey) end
		return an < bn
	end)
	return rows
end

--- Construye índice serializable para el cliente.
---@param networkId string|nil
---@param player IsoPlayer|nil limita el indice a sus zonas autorizadas
---@param freshSnapshotScope string|nil "network" o zoneId cuyo snapshot acaba de actualizarse
---@return table rows Lista ordenada { fullType, displayName, category, count, nodeId }
function GlobalStorageSiK.Index.buildRows(networkId, player, freshSnapshotScope, sourceNodeId)
	local registry = GlobalStorageSiK.Zones.getRegistry()
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	local byType = {}
	local liveIds = {}

	local live = GlobalStorageSiK.Permissions.filterLiveContainers(
		player, networkId, GlobalStorageSiK.Network.getLiveContainers(networkId))
	for i = 1, #live do
		local liveEntry = live[i]
		local nodeId = liveEntry.entry and liveEntry.entry.id or ("node_" .. i)
		if sourceNodeId == nil or sourceNodeId == nodeId then
		liveIds[nodeId] = true
		local node = registry.nodes and registry.nodes[nodeId]
		local snapshotAvailable = node and node.itemSnapshot
		if snapshotAvailable then
			-- El snapshot persistido es la fuente de lectura del terminal. Abrir,
			-- buscar o editar configuración no debe volver a recorrer miles de
			-- InventoryItem. Un reescaneo incremental actualiza esta captura y al
			-- terminar envía el estado fresco solo a observadores de la red.
			mergeNodeSnapshot(byType, node)
		else
			-- Compatibilidad inicial/legacy: solo un nodo que aún no tenga captura
			-- paga una lectura viva. El siguiente scan lo deja cacheado.
			mergeLiveContainer(byType, liveEntry.container, nodeId)
		end
		end
	end

	for _, node in pairs(registry.nodes or {}) do
		local zone = registry.zones and registry.zones[node.zoneId]
		if zone and zone.networkId == networkId and node.membership ~= "excluded" and node.enabled ~= false and node.offline ~= true
			and (not player or GlobalStorageSiK.Permissions.canAccessZone(player, networkId, node.zoneId)) then
			if not liveIds[node.id] and (sourceNodeId == nil or sourceNodeId == node.id) then
				mergeNodeSnapshot(byType, node)
			end
		end
	end

	local rows = compactParentRows(GlobalStorageSiK.ItemSnapshot.toRows(byType))
	local selectionRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId)
	-- La clasificación se resuelve en el proceso autoritativo al construir el
	-- snapshot serializable, nunca desde refresh/search/sort del cliente. El
	-- propio NativeProduct conserva una referencia por fullType/epoch, por lo
	-- que snapshots posteriores no vuelven a invocar al clasificador.
	for i = 1, #rows do
		rows[i].selectionRevision = selectionRevision
		rows[i].sourceNodeId = sourceNodeId
		local resolution = nil
		if not rows[i].mixedVariants or rows[i].nativePath then
			resolution = GlobalStorageSiK.CategoryResolution.resolve(rows[i].fullType, rows[i], nil)
			rows[i].nativePath = resolution.nativePath
			rows[i].nativeStatus = resolution.nativeStatus
			rows[i].vanillaKey = resolution.vanillaKey
			rows[i].effective = resolution.effective
			rows[i].categoryEffective = resolution.effective
			rows[i].routingIdentity = resolution.routingIdentity
			rows[i].categorySource = resolution.categorySource
		else
			rows[i].nativeStatus = "variants"
			rows[i].effective = "variants"
			rows[i].categoryEffective = "variants"
			rows[i].routingIdentity = "variants:" .. tostring(rows[i].rowKey)
		end
		-- El snapshot ordinario nunca transporta todos los IDs físicos.
		rows[i].itemIds = nil
		GlobalStorageSiK.NativeProduct.tracePathSample("buildRows", rows[i].fullType, rows[i].nativePath)
	end
	return rows
end

---@param networkId string
---@param player IsoPlayer|nil
---@param rowKey string
---@param page number|nil
---@param pageSize number|nil
---@return table
function GlobalStorageSiK.Index.buildDetailPage(networkId, player, rowKey, page, pageSize, sourceNodeId)
	page = math.max(1, math.floor(tonumber(page) or 1))
	pageSize = math.max(1, math.min(25, math.floor(tonumber(pageSize) or 15)))
	local details = {}
	local hasStateful = false
	local detailFullTypes = {}
	local registry = GlobalStorageSiK.Zones.getRegistry()
	for _, node in pairs(registry.nodes or {}) do
		local zone = registry.zones and registry.zones[node.zoneId]
		if (sourceNodeId == nil or sourceNodeId == node.id)
			and zone and zone.networkId == networkId and node.membership ~= "excluded"
			and node.enabled ~= false and node.offline ~= true
			and (not player or GlobalStorageSiK.Permissions.canAccessZone(player, networkId, node.zoneId)) then
			for _, row in pairs(node.itemSnapshot or {}) do
				if parentKeyForRow(row) == rowKey then
					local detailKind = detailKindForRow(row)
					if detailKind then hasStateful = true end
					detailFullTypes[row.fullType] = true
					for i = 1, #(row.itemIds or {}) do
						local itemId = row.itemIds[i]
						local unit = row.unitDetails and row.unitDetails[itemId] or nil
							details[#details + 1] = {
							rowKey = rowKey .. "\31item:" .. tostring(itemId),
							parentRowKey = rowKey, fullType = row.fullType, itemId = itemId,
							itemIds = { itemId }, aggregateAllowed = false,
							selectionMode = "exact_ids",
							selectionRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId),
							count = 1,
							displayName = row.mediaTitle or row.displayName,
							nodeId = node.id, zoneId = node.zoneId,
							sourceNodeId = sourceNodeId,
							detailKind = detailKind, variantKey = row.variantKey,
							mediaIndex = unit and unit.mediaIndex or row.mediaIndex,
							mediaTitle = unit and unit.mediaTitle or row.mediaTitle,
							mediaCodes = unit and unit.mediaCodes or row.mediaCodes,
							dynamicSignature = row.dynamicSignature,
							dynamicStateKey = row.dynamicStateKey,
							dynamicPercent = unit and unit.dynamicPercent or row.dynamicPercent,
							fluidState = unit and unit.fluidState or row.fluidState,
							foodState = unit and unit.foodState or row.foodState,
							shapeFamily = row.shapeFamily,
							productFamilyKey = row.productFamilyKey,
							shapeKey = row.shapeKey,
							condition = unit and unit.condition or row.condition,
							conditionMax = unit and unit.conditionMax or row.conditionMax,
							literatureTitle = row.literatureTitle,
							nativePath = row.nativePath,
							nativeStatus = row.nativePath and "classified" or row.nativeStatus,
							effective = row.nativePath and "native" or row.effective,
							categoryEffective = row.nativePath and "native" or row.categoryEffective,
						}
					end
				end
			end
		end
	end
	local detailFullTypeCount = 0
	for _ in pairs(detailFullTypes) do detailFullTypeCount = detailFullTypeCount + 1 end
	local cosmeticOnly = not hasStateful and detailFullTypeCount > 1
	local recordedMediaOnly = #details > 0
	for i = 1, #details do
		if details[i].detailKind ~= "recorded_media" then recordedMediaOnly = false break end
	end
	-- Cada entrada actual representa un único itemId físico. Se captura antes
	-- de compactar filas cosméticas/medios. La cabecera padre nunca entra en
	-- `details`, por lo que no puede sumar una unidad fantasma.
	local totalUnits = #details
	if cosmeticOnly or recordedMediaOnly then
		local grouped, compact = {}, {}
		for i = 1, #details do
			local detail = details[i]
			local identity = recordedMediaOnly
				and ("media:" .. tostring(detail.mediaIndex or ("unknown:" .. tostring(detail.itemId))))
				or detail.fullType
			local group = grouped[identity]
			if not group then
				group = { rowKey = rowKey .. "\31detail:" .. identity,
					parentRowKey = rowKey, fullType = detail.fullType,
					displayName = detail.displayName,
					detailKind = recordedMediaOnly and "recorded_media" or "cosmetic_variant",
					mediaIndex = detail.mediaIndex, mediaTitle = detail.mediaTitle,
					mediaCodes = detail.mediaCodes,
					nativePath = detail.nativePath,
					nativeStatus = detail.nativePath and "classified" or nil,
					effective = detail.nativePath and "native" or nil,
					categoryEffective = detail.nativePath and "native" or nil,
					aggregateAllowed = not recordedMediaOnly,
					selectionMode = recordedMediaOnly and "exact_ids" or "exact_ids",
					selectionRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId),
					fullTypes = not recordedMediaOnly and { detail.fullType } or nil,
					count = 0, itemIds = {}, nodeIds = {}, locations = {} }
				grouped[identity] = group
				compact[#compact + 1] = group
			end
			group.count = group.count + 1
			group.itemIds[#group.itemIds + 1] = detail.itemId
			group.nodeIds[#group.nodeIds + 1] = detail.nodeId
			addLocation(group, detail.nodeId, 1)
		end
		details = compact
		table.sort(details, function(a, b) return tostring(a.displayName) < tostring(b.displayName) end)
	end
	if not cosmeticOnly and not recordedMediaOnly then
		table.sort(details, function(a, b)
			local av, bv = tostring(a.variantKey or ""), tostring(b.variantKey or "")
			if av == bv then return tonumber(a.itemId) < tonumber(b.itemId) end
			return av < bv
		end)
	end
	local totalRows = #details
	local first = (page - 1) * pageSize + 1
	local last = math.min(totalRows, first + pageSize - 1)
	local items = {}
	for i = first, last do items[#items + 1] = details[i] end
	return { rowKey = rowKey, page = page, pageSize = pageSize,
		totalRows = totalRows, totalUnits = totalUnits,
		-- Compatibilidad transitoria: `total` siempre fue paginación por filas.
		total = totalRows,
		hasPrevious = page > 1, hasNext = last < totalRows, items = items }
end

function GlobalStorageSiK.Index.requiresExactSelection(networkId, player, fullType)
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local total, stateful = 0, false
	for _, node in pairs(registry.nodes or {}) do
		local zone = registry.zones and registry.zones[node.zoneId]
		if zone and zone.networkId == networkId and node.membership ~= "excluded"
			and node.enabled ~= false and node.offline ~= true
			and (not player or GlobalStorageSiK.Permissions.canAccessZone(player, networkId, node.zoneId)) then
			for _, row in pairs(node.itemSnapshot or {}) do
				if row.fullType == fullType then
					total = total + (row.count or 0)
					if detailKindForRow(row) then stateful = true end
				end
			end
		end
	end
	return stateful and total > 1
end

function GlobalStorageSiK.Index.sanitizeFungibleFamily(fullType, values)
	if type(fullType) ~= "string" or type(values) ~= "table" then return nil end
	local family = variantFamilyKey(fullType)
	local out, seen = {}, {}
	for i = 1, math.min(#values, 16) do
		local value = type(values[i]) == "string" and string.sub(values[i], 1, 160) or nil
		if value and not seen[value] and variantFamilyKey(value) == family
			and GlobalStorageSiK.I18n.getScriptItem(value) then
			seen[value] = true
			out[#out + 1] = value
		end
	end
	return #out > 1 and out or nil
end

--- Refresca el itemSnapshot de UN nodo concreto ya resuelto por la propia
--- operacion (deposito/retirada), sin recorrer el resto de la red. Mas barato
--- y preciso que syncLiveSnapshots: la llamante ya tiene entry+container en
--- la mano en el momento exacto del movimiento (Transfer.depositItem /
--- withdrawUnits), asi que no hace falta un segundo getLiveContainers() ni
--- resolver el objeto de mundo de nuevo.
---@param entry table nodo del registro (registry.nodes[id], referencia real)
---@param container ItemContainer contenedor ya resuelto de ese nodo
---@return boolean captured
function GlobalStorageSiK.Index.syncNodeSnapshot(entry, container)
	if not GlobalStorageSiK.isAuthoritative() then
		return false
	end
	if not entry or not container then
		return false
	end
	local ok, snap = pcall(GlobalStorageSiK.ItemSnapshot.fromContainer, container)
	if ok and type(snap) == "table" then
		entry.itemSnapshot = snap
		return true
	end
	return false
end

--- Actualiza itemSnapshot de TODOS los nodos activos con contenedor vivo de
--- una red (barrido completo de getActiveNodes, hasta MAX_CONTAINERS_PER_NETWORK).
--- NO usar tras un deposito/retirada individual - eso ya lo cubre, mas barato
--- y preciso, GlobalStorageSiK.Index.syncNodeSnapshot (ver arriba) llamado
--- directamente desde GS_Transfer.lua sobre el nodo exacto tocado. Reservada
--- para un refresco deliberado de red completa (p.ej. tras reabrir el
--- terminal o una consolidacion manual), no para el camino caliente de cada
--- transferencia.
---@param networkId string|nil
function GlobalStorageSiK.Index.syncLiveSnapshots(networkId)
	-- En SP real la autoridad vive en este proceso aunque isServer() sea
	-- false. El mismo contrato se usa para dedicado y host.
	if not GlobalStorageSiK.isAuthoritative() then
		return
	end
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	if not networkId then
		return
	end
	local registry = GlobalStorageSiK.Zones.getRegistry()
	if not registry or not registry.nodes then
		return
	end
	local live = GlobalStorageSiK.Network.getLiveContainers(networkId)
	for i = 1, #live do
		local entry = live[i].entry
		local container = live[i].container
		if entry and entry.id and container then
			local node = registry.nodes[entry.id]
			if node then
				local ok, snap = pcall(GlobalStorageSiK.ItemSnapshot.fromContainer, container)
				if ok and snap then
					node.itemSnapshot = snap
				end
			end
		end
	end
end

-- Serializa solo el estado fisico que determina el catalogo. No incluye
-- nombres traducidos, categorias de presentacion ni ninguna referencia Java.
-- La cadena puede ser grande, pero solo se construye al principio y al final
-- de un escaneo fisico, y permite una comparacion exacta sin colisiones.
local CONTENT_FIELDS = {
	"fullType", "worldSprite", "count", "mediaIndex", "mediaTitle", "mediaCodes",
	"dynamicSignature", "dynamicStateKey", "dynamicPercent", "fluidState", "foodState",
	"shapeFamily", "productFamilyKey", "shapeKey", "conditionSignature", "condition",
	"conditionMax", "variantKey", "totalWeight", "totalFluidAmount", "totalFluidCapacity",
	"itemIds", "unitDetails",
}

local function stableScalar(value)
	local kind = type(value)
	if kind == "nil" then return "n" end
	if kind == "boolean" then return value and "b1" or "b0" end
	if kind == "number" then return "d" .. string.format("%.17g", value) end
	local text = tostring(value)
	return "s" .. tostring(#text) .. ":" .. text
end

local function stableValue(value, depth)
	if type(value) ~= "table" then return stableScalar(value) end
	if depth >= 6 then return "t0:" end
	local entries = {}
	for key, child in pairs(value) do
		local encodedKey = stableScalar(key)
		entries[#entries + 1] = encodedKey .. "=" .. stableValue(child, depth + 1)
	end
	table.sort(entries)
	return "t" .. tostring(#entries) .. ":" .. table.concat(entries, ";")
end

local function stableSet(value)
	if type(value) ~= "table" then return stableScalar(value) end
	local entries = {}
	for _, child in pairs(value) do entries[#entries + 1] = stableValue(child, 0) end
	table.sort(entries)
	return "u" .. tostring(#entries) .. ":" .. table.concat(entries, ";")
end

function GlobalStorageSiK.Index.snapshotSignature(snapshot)
	local rows = {}
	for _, row in pairs(snapshot or {}) do
		local encoded = { stableScalar(row.rowKey or row.fullType) }
		for i = 1, #CONTENT_FIELDS do
			local field = CONTENT_FIELDS[i]
			local value = (field == "itemIds" or field == "mediaCodes")
				and stableSet(row[field]) or stableValue(row[field], 0)
			encoded[#encoded + 1] = field .. "=" .. value
		end
		rows[#rows + 1] = table.concat(encoded, ";")
	end
	table.sort(rows)
	return table.concat(rows, ";")
end

---@param networkId string|nil
---@return string
function GlobalStorageSiK.Index.contentSignature(networkId)
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	if not networkId then return "network:nil" end
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local nodes = {}
	for _, node in pairs(registry.nodes or {}) do
		local zone = registry.zones and registry.zones[node.zoneId]
		if zone and zone.networkId == networkId and node.membership ~= "excluded"
			and node.enabled ~= false and node.offline ~= true then
			nodes[#nodes + 1] = node
		end
	end
	table.sort(nodes, function(a, b) return tostring(a.id) < tostring(b.id) end)
	local parts = { "network=", stableScalar(networkId), ";nodes=", tostring(#nodes) }
	for i = 1, #nodes do
		local node = nodes[i]
		parts[#parts + 1] = ";node=" .. stableScalar(node.id)
		parts[#parts + 1] = ";zone=" .. stableScalar(node.zoneId)
		local rows = {}
		for _, row in pairs(node.itemSnapshot or {}) do
			local encoded = { "row=", stableScalar(row.rowKey or row.fullType) }
			for k = 1, #CONTENT_FIELDS do
				local field = CONTENT_FIELDS[k]
				local value = (field == "itemIds" or field == "mediaCodes")
					and stableSet(row[field]) or stableValue(row[field], 0)
				encoded[#encoded + 1] = ";" .. field .. "=" .. value
			end
			rows[#rows + 1] = table.concat(encoded)
		end
		table.sort(rows)
		parts[#parts + 1] = ";rows=" .. tostring(#rows)
		for j = 1, #rows do parts[#parts + 1] = ";" .. rows[j] end
	end
	return table.concat(parts)
end

---@param networkId string|nil
---@return boolean hasAny
---@return boolean complete
function GlobalStorageSiK.Index.hasNetworkSnapshot(networkId)
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	if not networkId then return false, false end
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local hasAny = false
	for _, node in pairs(registry.nodes or {}) do
		local zone = registry.zones and registry.zones[node.zoneId]
		if zone and zone.networkId == networkId and node.membership ~= "excluded"
			and node.enabled ~= false and node.offline ~= true then
			hasAny = true
			if type(node.itemSnapshot) ~= "table" then return true, false end
		end
	end
	return hasAny, hasAny
end

--- Incrementa revisión de inventario de la red (servidor).
---@param networkId string|nil
---@param transmitModData boolean|nil si false, no llama ModData.transmit
---@return number revision
function GlobalStorageSiK.Index.bumpInventoryRevision(networkId, transmitModData)
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	if not networkId then
		return 0
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	registry._inventoryRevision = registry._inventoryRevision or {}
	local rev = (registry._inventoryRevision[networkId] or 0) + 1
	registry._inventoryRevision[networkId] = rev
	if transmitModData ~= false and isServer and isServer() and ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	return rev
end

--- Revisión actual del inventario agregado de la red.
---@param networkId string|nil
---@return number
function GlobalStorageSiK.Index.getInventoryRevision(networkId)
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	if not networkId then
		return 0
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	registry._inventoryRevision = registry._inventoryRevision or {}
	return registry._inventoryRevision[networkId] or 0
end

--- Reconstruye en autoridad el conjunto fisico de un padre. La UI nunca
--- aporta IDs ni paginas para este selector.
---@param networkId string
---@param player IsoPlayer|nil
---@param rowKey string
---@param selectionRevision number
---@return table|nil result
---@return string|nil reason
function GlobalStorageSiK.Index.resolveExactGroup(networkId, player, rowKey, selectionRevision, sourceNodeId)
	if type(rowKey) ~= "string" or rowKey == "" then return nil, "invalid_row_key" end
	local currentRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId)
	if math.floor(tonumber(selectionRevision) or -1) ~= currentRevision then
		return nil, "selection_stale"
	end
	-- Parent rows and exact selectors must refer to the same complete capture.
	-- The legacy live fallback can paint counts before IDs are captured; it
	-- must never turn an unfinished capture into a false 'not_found'. Exact-ID
	-- transfers remain independently valid and are revalidated on the item.
	local snapshotRevision = GlobalStorageSiK.Index.getSnapshotRevision(networkId)
	local _, complete = GlobalStorageSiK.Index.hasNetworkSnapshot(networkId)
	if snapshotRevision ~= currentRevision or not complete then
		return nil, "selection_stale"
	end
	local refs, seen = {}, {}
	local registry = GlobalStorageSiK.Zones.getRegistry()
	for _, node in pairs(registry.nodes or {}) do
		local zone = registry.zones and registry.zones[node.zoneId]
		if (sourceNodeId == nil or sourceNodeId == node.id)
			and zone and zone.networkId == networkId and node.membership ~= "excluded"
			and node.enabled ~= false and node.offline ~= true
			and (not player or GlobalStorageSiK.Permissions.canAccessZone(player, networkId, node.zoneId)) then
			for _, row in pairs(node.itemSnapshot or {}) do
				if parentKeyForRow(row) == rowKey then
					if #(row.itemIds or {}) < (tonumber(row.count) or 0) then
						return nil, "selection_stale"
					end
					for i = 1, #(row.itemIds or {}) do
						local itemId = tonumber(row.itemIds[i])
						if itemId and itemId >= 0 and itemId == math.floor(itemId) and not seen[itemId] then
							seen[itemId] = true
							refs[#refs + 1] = { itemId = itemId, fullType = row.fullType }
						end
					end
				end
			end
		end
	end
	table.sort(refs, function(a, b)
		if a.fullType == b.fullType then return a.itemId < b.itemId end
		return tostring(a.fullType) < tostring(b.fullType)
	end)
	if #refs == 0 then return nil, "not_found" end
	return { refs = refs, count = #refs, revision = currentRevision,
		snapshotRevision = snapshotRevision, rowKey = rowKey }, nil
end

--- Revisión hasta la que los snapshots persistidos representan una captura
--- completa y estable de la red. No debe adelantarse al inventoryRevision:
--- una transferencia incrementa este último inmediatamente, mientras que el
--- snapshot se consolida después mediante ZoneScanJob.
---@param networkId string|nil
---@param revision number|nil
---@return number
function GlobalStorageSiK.Index.setSnapshotRevision(networkId, revision)
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	if not networkId then
		return 0
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	registry._snapshotRevision = registry._snapshotRevision or {}
	local stableRevision = math.max(0, math.floor(tonumber(revision) or 0))
	registry._snapshotRevision[networkId] = stableRevision
	return stableRevision
end

--- Revisión de la última captura completa y estable de la red.
---@param networkId string|nil
---@return number
function GlobalStorageSiK.Index.getSnapshotRevision(networkId)
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	if not networkId then
		return 0
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	registry._snapshotRevision = registry._snapshotRevision or {}
	return registry._snapshotRevision[networkId] or 0
end

--- Cuenta cuántas unidades de un fullType tiene el jugador en cada red
--- accesible (para tooltip global "cuántos tengo en mi red"). Agrupa
--- variantes de sabor/color del mismo item base (Crisps/Crisps2/Crisps3...,
--- ver GlobalStorageSiK.ItemTaxonomy.getVariantFamilyKey): al explorar solo
--- nos interesa saber si tenemos "patatas fritas" en total, sin importar el
--- sabor concreto. La pestaña Almacen sigue mostrando cada fullType exacto
--- por separado (no usa esta funcion para sus filas, solo para su tooltip).
---@param player IsoPlayer
---@param fullType string
---@param mediaTitle string|nil si viene informado (cinta VHS/radio con
---  contenido concreto, ver GS_ItemSnapshot.recordedMediaTitleFromItem),
---  cuenta SOLO filas con ese mismo fullType+mediaTitle exacto, ignorando el
---  agrupado por familia de variantes (2026-08-26, fix de agrupacion de
---  VHS - "no podemos ver si ya tenemos un vhs determinado en el tooltip").
---  Sin esto, el tooltip sumaba TODAS las cintas VHS de la red sin importar
---  que habilidad enseñaba cada una, dando una cifra enganosa.
---@return table[], boolean out { name, count } ordenado por nombre; hasAnyNetwork indica si el jugador tiene AL MENOS una red accesible (para distinguir, en el tooltip, "no tienes redes todavia" de "tienes redes pero este item no esta en ninguna")
function GlobalStorageSiK.Index.getNetworkCountsForItem(player, fullType, mediaTitle, mediaIndex, dynamicStateKey)
	if not player or not fullType or not GlobalStorageSiK.Network then
		return {}, false
	end
	local familyKey = variantFamilyKey(fullType)
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local out = {}
	local hasAnyNetwork = false
	for networkId, net in pairs(registry.networks or {}) do
		local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(player, networkId))
		if allowed and net then
			hasAnyNetwork = true
			local total = 0
			for _, node in pairs(registry.nodes or {}) do
				local zone = registry.zones and registry.zones[node.zoneId]
				if zone and zone.networkId == networkId and node.membership ~= "excluded"
						and node.enabled ~= false and node.offline ~= true
						and GlobalStorageSiK.Permissions.canAccessZone(player, networkId, node.zoneId) then
					local snapshot = node.itemSnapshot
					if snapshot then
						for _, row in pairs(snapshot) do
							if mediaIndex ~= nil then
								if row.fullType == fullType and row.mediaIndex == mediaIndex then
									total = total + (row.count or 0)
								end
							elseif dynamicStateKey then
								if row.fullType == fullType and row.dynamicStateKey == dynamicStateKey then
									total = total + (row.count or 0)
								end
							elseif mediaTitle then
								if row.fullType == fullType and row.mediaTitle == mediaTitle then
									total = total + (row.count or 0)
								end
							elseif variantFamilyKey(row.fullType) == familyKey then
								total = total + (row.count or 0)
							end
						end
					end
				end
			end
			if total > 0 then
				out[#out + 1] = { id = networkId, name = net.name or networkId, count = total }
			end
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out, hasAnyNetwork
end

--- Filtra filas por texto de búsqueda (servidor / inglés en snapshot).
--- En cliente preferir `GlobalStorageSiK.I18n.filterItemRows` para idioma del jugador.
---@param rows table[]
---@param query string|nil
---@return table[]
function GlobalStorageSiK.Index.filterRows(rows, query)
	if not query or query == "" then
		return rows
	end
	local asciiLower = GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.asciiLower or string.lower
	local q = asciiLower(query)
	local filtered = {}
	for i = 1, #rows do
		local row = rows[i]
		local name = asciiLower(row.displayName or "")
		local cat = asciiLower(row.category or "")
		local typ = asciiLower(row.fullType or "")
		if string.find(name, q, 1, true) or string.find(cat, q, 1, true) or string.find(typ, q, 1, true) then
			table.insert(filtered, row)
		end
	end
	return filtered
end

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
				unitNodeIds = {},
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
			for j = 1, #(row.itemIds or {}) do
				byType[groupKey].unitNodeIds[row.itemIds[j]] = nodeId
			end
			addLocation(byType[groupKey], nodeId, row.count)
		else
			existing.count = existing.count + row.count
			existing.itemIds = existing.itemIds or {}
			for j = 1, #(row.itemIds or {}) do existing.itemIds[#existing.itemIds + 1] = row.itemIds[j] end
			existing.unitDetails = existing.unitDetails or {}
			for itemId, detail in pairs(row.unitDetails or {}) do existing.unitDetails[itemId] = detail end
			existing.unitNodeIds = existing.unitNodeIds or {}
			for j = 1, #(row.itemIds or {}) do existing.unitNodeIds[row.itemIds[j]] = nodeId end
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
				unitNodeIds = {},
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
			for j = 1, #(row.itemIds or {}) do
				byType[groupKey].unitNodeIds[row.itemIds[j]] = node.id
			end
			addLocation(byType[groupKey], node.id, row.count or 0)
		else
			existing.count = (existing.count or 0) + (row.count or 0)
			existing.itemIds = existing.itemIds or {}
			for j = 1, #(row.itemIds or {}) do existing.itemIds[#existing.itemIds + 1] = row.itemIds[j] end
			existing.unitDetails = existing.unitDetails or {}
			for itemId, detail in pairs(row.unitDetails or {}) do existing.unitDetails[itemId] = detail end
			existing.unitNodeIds = existing.unitNodeIds or {}
			for j = 1, #(row.itemIds or {}) do existing.unitNodeIds[row.itemIds[j]] = node.id end
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

local SUMMARY_IDENTITY_FIELDS={"fullType","worldSprite","displayName","literatureTitle","mediaIndex","mediaTitle","nativePath","dynamicStateKey"}
local SUMMARY_FOOD_FIELDS={"fresh","rotten","cooked","burnt","frozen","iconVariant"}
local function visibleVariantKey(detail,kind)
	local parts={tostring(kind or "")}
	local function add(value)
		local text=tostring(value)
		parts[#parts+1]=type(value)..":"..#text..":"..text
	end
	for i=1,#SUMMARY_IDENTITY_FIELDS do add(detail[SUMMARY_IDENTITY_FIELDS[i]]) end
	for i=1,#SUMMARY_FOOD_FIELDS do add(detail.foodState and detail.foodState[SUMMARY_FOOD_FIELDS[i]]) end
	return table.concat(parts,"|")
end
local function visibleFoodState(food)
	if not food then return nil end
	local result={}
	for i=1,#SUMMARY_FOOD_FIELDS do local key=SUMMARY_FOOD_FIELDS[i];result[key]=food[key] end
	return result
end
local function countPhysicalVariant(parent,detail)
	parent._physicalVariants=parent._physicalVariants or {}
	local key=tostring(detail.fullType).."\31"..tostring(detail.variantKey or detail.rowKey or "fungible")
	if not parent._physicalVariants[key] then
		parent._physicalVariants[key]=true;parent.variantCount=(parent.variantCount or 0)+1
	end
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
		for j = 1, #(detail.itemIds or {}) do
			local id = detail.itemIds[j]
			local nodeId = detail.unitNodeIds and detail.unitNodeIds[id] or detail.nodeId
			if type(id) == "number" and id >= 0 and id < math.huge
				and id == math.floor(id) and type(nodeId) == "string" then
				local better = not parent.representativeItemId
					or id < parent.representativeItemId
					or (id == parent.representativeItemId and nodeId < parent.representativeNodeId)
				if better then
					parent.representativeNodeId = nodeId
					parent.representativeItemId = id
					parent.representativeFullType = detail.fullType
					parent.representativeDynamicSignature = detail.dynamicSignature
				end
			end
		end
		for j = 1, #(detail.locations or {}) do
			addLocation(parent, detail.locations[j].nodeId, detail.locations[j].count)
		end
		if detail.nodeId and #(detail.locations or {}) == 0 then
			addLocation(parent, detail.nodeId, detail.count or 0)
		end
		local detailKind = detailKindForRow(detail)
		countPhysicalVariant(parent,detail)
		local variantKey = visibleVariantKey(detail,detailKind)
		local summary = parent._variantSeen[variantKey]
		if not summary then
			summary = {
				key = variantKey, count = 0, detailKind = detailKind,
				fullType = detail.fullType, displayName = detail.displayName,
				literatureTitle = detail.literatureTitle,
				mediaIndex = detail.mediaIndex, mediaTitle = detail.mediaTitle,
				mediaCodes = detail.mediaCodes,
				dynamicStateKey = detail.dynamicStateKey,
				foodState = visibleFoodState(detail.foodState),
				nativePath = detail.nativePath,
			}
			parent._variantSeen[variantKey] = summary
			parent.variantSummary[#parent.variantSummary + 1] = summary
		end
		-- Reuse one exact captured identity for every stateful variant. This is
		-- enough for lazy presentation and sequential reading without publishing
		-- the full physical-ID set in the ordinary catalog.
		for j = 1, #(detail.itemIds or {}) do
			local id = detail.itemIds[j]
			local nodeId = detail.unitNodeIds and detail.unitNodeIds[id] or detail.nodeId
			if type(id) == "number" and id >= 0 and id < math.huge
				and id == math.floor(id) and type(nodeId) == "string" then
				local better = not summary.representativeItemId
					or id < summary.representativeItemId
					or (id == summary.representativeItemId
						and nodeId < summary.representativeNodeId)
				if better then
					summary.representativeItemId = id
					summary.representativeNodeId = nodeId
					summary.representativeFullType = detail.fullType
					summary.representativeDynamicSignature = detail.dynamicSignature
				end
			end
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
		parent._physicalVariants = nil
		parent.categoryCount = pathCount
		parent.nativePaths = {}
		for nativePath in pairs(parent._pathSeen) do
			parent.nativePaths[#parent.nativePaths + 1] = nativePath
		end
		table.sort(parent.nativePaths)
		parent.locationCount = #parent.locations
		local variantSearchParts = {}
		local foodIconVariant, foodIconsAgree = nil, true
		for i = 1, #parent.variantSummary do
			local summary = parent.variantSummary[i]
			local icon = summary.foodState and summary.foodState.iconVariant
			if i == 1 then foodIconVariant = icon
			elseif icon ~= foodIconVariant then foodIconsAgree = false end
			variantSearchParts[#variantSearchParts + 1] = tostring(summary.key or "")
			if summary.displayName then variantSearchParts[#variantSearchParts + 1] = summary.displayName end
			if summary.mediaTitle then variantSearchParts[#variantSearchParts + 1] = summary.mediaTitle end
			if summary.dynamicStateKey then variantSearchParts[#variantSearchParts + 1] = summary.dynamicStateKey end
			if summary.nativePath then variantSearchParts[#variantSearchParts + 1] = summary.nativePath end
		end
		parent.variantSearchText = table.concat(variantSearchParts, " ")
		-- A collapsed group may project a food icon only when every variant
		-- agrees. Compute once with the index, never traverse variants in render.
		parent.foodIconVariant = foodIconsAgree and foodIconVariant or nil
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

-- Capturas ya publicadas en registry.nodes se sustituyen de forma atomica. La
-- caché conserva esas referencias inmutables y solo vuelve a inspeccionar el
-- nodo cuya referencia cambia. Los escaneos incrementales construyen su tabla
-- privada antes de publicarla en GS_ZoneRefresh.
local BUILD_CACHE_LIMIT = 64
local BUILD_CACHE_BYTES = 32 * 1024 * 1024
local BUILD_ENTRY_BYTES = 16 * 1024 * 1024
local buildCache = {}
local buildCacheClock = 0
local buildCacheBytes = 0
local buildGeneration = 0
local immutableSignatureCache = setmetatable({}, { __mode = "k" })
local rowSignatureCache = setmetatable({}, { __mode = "k" })
local scopedRowSignatureCache = setmetatable({}, { __mode = "k" })
local computeRowSignature
local stableScalar
local function classificationStamp()
	local manager, world = GlobalStorageSiK.CatalogManager, GlobalStorageSiK.NativeWorldOverrides
	return tostring(manager and manager.getEpoch and manager.getEpoch() or 0) .. "\31"
		.. tostring(world and world.getRevision and world.getRevision() or 0)
end
GlobalStorageSiK.Index.getClassificationStamp = classificationStamp

local function immutableSnapshotSignature(snapshot)
	if type(snapshot) ~= "table" then return "snapshot:nil" end
	local signature = immutableSignatureCache[snapshot]
	if signature == nil then
		signature = GlobalStorageSiK.Index.snapshotSignature(snapshot)
		immutableSignatureCache[snapshot] = signature
	end
	return signature
end

local function scopeKeyFor(registry, networkId, player, sourceNodeId)
	local zones = {}
	if player then
		for zoneId, zone in pairs(registry.zones or {}) do
			if zone and zone.networkId == networkId
				and GlobalStorageSiK.Permissions.canAccessZone(player, networkId, zoneId) then
				zones[#zones + 1] = tostring(zoneId)
			end
		end
		table.sort(zones)
	else
		zones[1] = "*"
	end
	return tostring(networkId) .. "\30" .. tostring(sourceNodeId or "*")
		.. "\30" .. table.concat(zones, "\31")
end

local function cacheEntryFor(key)
	buildCacheClock = buildCacheClock + 1
	local entry = buildCache[key]
	if entry then
		entry.usedAt = buildCacheClock
		return entry, true
	end
	local count, oldestKey, oldestAt = 0, nil, nil
	for cachedKey, cached in pairs(buildCache) do
		count = count + 1
		if oldestAt == nil or cached.usedAt < oldestAt then
			oldestKey, oldestAt = cachedKey, cached.usedAt
		end
	end
	if count >= BUILD_CACHE_LIMIT and oldestKey then
		buildCacheBytes = math.max(0, buildCacheBytes - (buildCache[oldestKey].bytes or 0))
		buildCache[oldestKey] = nil
	end
	entry = { nodes = {}, parents = {}, usedAt = buildCacheClock }
	buildCache[key] = entry
	return entry, false
end

local function trimBuildCache(protectedKey)
	while true do
		local count,oldestKey,oldestAt=0,nil,nil
		for key,entry in pairs(buildCache) do
			count=count+1
			if key~=protectedKey and (oldestAt==nil or entry.usedAt<oldestAt) then
				oldestKey,oldestAt=key,entry.usedAt
			end
		end
		if count<=BUILD_CACHE_LIMIT and buildCacheBytes<=BUILD_CACHE_BYTES then return end
		if not oldestKey then return end
		buildCacheBytes=math.max(0,buildCacheBytes-(buildCache[oldestKey].bytes or 0))
		buildCache[oldestKey]=nil
	end
end

local function collectVisibleNodes(registry, networkId, player, sourceNodeId)
	local visible, liveIds = {}, {}
	local live = GlobalStorageSiK.Permissions.filterLiveContainers(
		player, networkId, GlobalStorageSiK.Network.getLiveContainers(networkId))
	for i = 1, #live do
		local liveEntry = live[i]
		local nodeId = liveEntry.entry and liveEntry.entry.id or ("node_" .. i)
		if sourceNodeId == nil or sourceNodeId == nodeId then
			liveIds[nodeId] = true
			local node = registry.nodes and registry.nodes[nodeId]
			local snapshot = node and node.itemSnapshot
			if not snapshot then
				snapshot = GlobalStorageSiK.ItemSnapshot.fromContainer(liveEntry.container)
			end
			visible[nodeId] = { id = nodeId, zoneId = node and node.zoneId, snapshot = snapshot }
		end
	end
	for _, node in pairs(registry.nodes or {}) do
		local zone = registry.zones and registry.zones[node.zoneId]
		if zone and zone.networkId == networkId and node.membership ~= "excluded"
			and node.enabled ~= false and node.offline ~= true
			and (not player or GlobalStorageSiK.Permissions.canAccessZone(player, networkId, node.zoneId))
			and not liveIds[node.id] and (sourceNodeId == nil or sourceNodeId == node.id) then
			visible[node.id] = { id = node.id, zoneId = node.zoneId, snapshot = node.itemSnapshot }
		end
	end
	return visible
end

local function contributionForNode(nodeId, snapshot)
	local byType = {}
	mergeNodeSnapshot(byType, { id = nodeId, itemSnapshot = snapshot })
	local byParent = {}
	for _, detail in ipairs(GlobalStorageSiK.ItemSnapshot.toRows(byType)) do
		local parentKey = parentKeyForRow(detail)
		local contribution = byParent[parentKey]
		if not contribution then
			contribution = { rows = {} }
			byParent[parentKey] = contribution
		end
		contribution.rows[#contribution.rows + 1] = detail
	end
	for _, contribution in pairs(byParent) do
		contribution.signature = GlobalStorageSiK.Index.snapshotSignature(contribution.rows)
	end
	return byParent
end

local function markChangedParents(changed, previous, current)
	for parentKey, old in pairs(previous or {}) do
		local replacement = current and current[parentKey]
		if not replacement or replacement.signature ~= old.signature then changed[parentKey] = true end
	end
	for parentKey, replacement in pairs(current or {}) do
		local old = previous and previous[parentKey]
		if not old or old.signature ~= replacement.signature then changed[parentKey] = true end
	end
end

local function classifyParent(row)
	local resolution = nil
	if not row.mixedVariants or row.nativePath then
		resolution = GlobalStorageSiK.CategoryResolution.resolve(row.fullType, row, nil)
		row.nativePath = resolution.nativePath
		row.nativeStatus = resolution.nativeStatus
		row.vanillaKey = resolution.vanillaKey
		row.effective = resolution.effective
		row.categoryEffective = resolution.effective
		row.routingIdentity = resolution.routingIdentity
		row.categorySource = resolution.categorySource
	else
		row.nativeStatus = "variants"
		row.effective = "variants"
		row.categoryEffective = "variants"
		row.routingIdentity = "variants:" .. tostring(row.rowKey)
	end
	row.itemIds = nil
	row.unitDetails = nil
	row.unitNodeIds = nil
	rowSignatureCache[row] = computeRowSignature(row)
	GlobalStorageSiK.NativeProduct.tracePathSample("buildRows", row.fullType, row.nativePath)
	return row
end

local function rebuildChangedParents(entry, changed, stats)
	for parentKey in pairs(changed) do
		local details = {}
		for _, cachedNode in pairs(entry.nodes) do
			local contribution = cachedNode.byParent and cachedNode.byParent[parentKey]
			for i = 1, #(contribution and contribution.rows or {}) do
				details[#details + 1] = contribution.rows[i]
			end
		end
		local parents = compactParentRows(details)
		entry.parents[parentKey] = parents[1] and classifyParent(parents[1]) or nil
		stats.parentsProcessed = stats.parentsProcessed + 1
	end
end

local function copyCatalogRow(row, selectionRevision, sourceNodeId)
	local out = {}
	for key, value in pairs(row) do out[key] = value end
	out.selectionRevision = selectionRevision
	out.representativeRevision = selectionRevision
	out.sourceNodeId = sourceNodeId
	if row.variantSummary then
		out.variantSummary = {}
		for i = 1, #row.variantSummary do
			local source = row.variantSummary[i]
			local variant = {}
			for key, value in pairs(source) do variant[key] = value end
			if variant.representativeItemId then variant.representativeRevision = selectionRevision end
			out.variantSummary[i] = variant
		end
	end
	local signature = rowSignatureCache[row]
	if sourceNodeId ~= nil then
		local scoped = scopedRowSignatureCache[row] or {}
		scopedRowSignatureCache[row] = scoped
		signature = scoped[sourceNodeId]
		if not signature then signature=computeRowSignature(out); scoped[sourceNodeId]=signature end
	end
	rowSignatureCache[out] = signature or computeRowSignature(out)
	return out
end

--- Construye índice serializable para el cliente.
---@param networkId string|nil
---@param player IsoPlayer|nil limita el indice a sus zonas autorizadas
---@param freshSnapshotScope string|nil "network" o zoneId cuyo snapshot acaba de actualizarse
---@return table rows Lista ordenada { fullType, displayName, category, count, nodeId }
function GlobalStorageSiK.Index.buildRows(networkId, player, freshSnapshotScope, sourceNodeId)
	local registry = GlobalStorageSiK.Zones.getRegistry()
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	local key = scopeKeyFor(registry, networkId, player, sourceNodeId)
	local entry, cacheHit = cacheEntryFor(key)
	local visible = collectVisibleNodes(registry, networkId, player, sourceNodeId)
	local changed = {}
	local stats = { cacheHit = cacheHit, nodesVisited = 0, nodesProcessed = 0,
		parentsProcessed = 0, snapshotSignaturesComputed = 0 }
	for nodeId, current in pairs(visible) do
		stats.nodesVisited = stats.nodesVisited + 1
		local previous = entry.nodes[nodeId]
		if not previous or previous.snapshot ~= current.snapshot then
			stats.snapshotSignaturesComputed = stats.snapshotSignaturesComputed + 1
			local signature = immutableSnapshotSignature(current.snapshot)
			if previous and previous.signature == signature then
				previous.snapshot = current.snapshot
			else
				local byParent = contributionForNode(nodeId, current.snapshot)
				markChangedParents(changed, previous and previous.byParent, byParent)
				entry.nodes[nodeId] = { snapshot = current.snapshot,
					signature = signature, byParent = byParent }
				stats.nodesProcessed = stats.nodesProcessed + 1
			end
		end
	end
	local retired = {}
	for nodeId, previous in pairs(entry.nodes) do
		if not visible[nodeId] then
			markChangedParents(changed, previous.byParent, nil)
			retired[#retired+1] = nodeId
			stats.nodesProcessed = stats.nodesProcessed + 1
		end
	end
	for i=1,#retired do entry.nodes[retired[i]]=nil end
	local stamp = classificationStamp()
	if entry.classificationStamp ~= stamp then
		for _,cachedNode in pairs(entry.nodes) do
			for parentKey in pairs(cachedNode.byParent or {}) do changed[parentKey]=true end
		end
		entry.classificationStamp = stamp
		stats.classificationInvalidated = true
	end
	rebuildChangedParents(entry, changed, stats)
	local rows = {}
	local selectionRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId)
	local unitEstimate = 0
	for _, parent in pairs(entry.parents) do
		rows[#rows + 1] = copyCatalogRow(parent, selectionRevision, sourceNodeId)
		unitEstimate = unitEstimate + (parent.count or 0)
	end
	table.sort(rows, function(a, b)
		local an, bn = tostring(a.displayName or ""), tostring(b.displayName or "")
		if an == bn then return tostring(a.rowKey) < tostring(b.rowKey) end
		return an < bn
	end)
	buildCacheBytes = math.max(0, buildCacheBytes - (entry.bytes or 0))
	entry.revision = selectionRevision
	entry.bytes = stats.nodesVisited * 160 + #rows * 640 + unitEstimate * 24
	if entry.bytes <= BUILD_ENTRY_BYTES then
		buildCacheBytes = buildCacheBytes + entry.bytes; trimBuildCache(key)
	else buildCache[key] = nil end
	return rows, stats
end

-- Incremental catalog builder. It reads only atomically published snapshots;
-- live containers remain the responsibility of the scanner/reconciler.
local ASYNC_MAX_NODES = 8192
local ASYNC_MAX_RETAINED = 32 * 1024 * 1024
local EMPTY_ASYNC_SNAPSHOT = {}
local REVISION_KEYS = { selectionRevision=true, representativeRevision=true }

local function beginMergeSort(values, less)
	return {values=values,less=less,width=1,left=1,phase="prepare"}
end

local function stepMergeSort(sort)
	local values, count = sort.values, #sort.values
	if count < 2 or sort.width >= count then return true end
	-- A bounded primitive avoids hundreds of cursor transitions for the small
	-- field lists in every row signature. Larger collections still yield.
	if sort.width==1 and sort.left==1 and sort.phase=="prepare" and count<=64 then
		table.sort(values,sort.less);sort.width=count
		return true
	end
	if sort.phase == "prepare" then
		if sort.left > count then
			sort.width, sort.left = sort.width * 2, 1
			return sort.width >= count
		end
		sort.middle = math.min(sort.left + sort.width - 1, count)
		sort.right = math.min(sort.left + sort.width * 2 - 1, count)
		sort.i, sort.j, sort.temp, sort.copy = sort.left, sort.middle + 1, {}, 1
		sort.phase = "merge"
		return false
	end
	if sort.phase == "merge" then
		local takeLeft = sort.j > sort.right or (sort.i <= sort.middle
			and not sort.less(values[sort.j], values[sort.i]))
		if takeLeft and sort.i <= sort.middle then
			sort.temp[#sort.temp+1], sort.i = values[sort.i], sort.i+1
		elseif sort.j <= sort.right then
			sort.temp[#sort.temp+1], sort.j = values[sort.j], sort.j+1
		else sort.phase = "copy" end
		return false
	end
	values[sort.left + sort.copy - 1] = sort.temp[sort.copy]
	sort.copy = sort.copy + 1
	if sort.copy > #sort.temp then
		sort.left, sort.phase = sort.right + 1, "prepare"
	end
	return false
end

local function beginCanonical(value)
	return {stack={{value=value,depth=0,phase="start"}}, result=nil}
end

local function finishCanonicalFrame(state, result)
	table.remove(state.stack)
	local parent = state.stack[#state.stack]
	if not parent then state.result=result return end
	parent.entries[#parent.entries+1] = parent.pendingPrefix .. result
	parent.pendingPrefix = nil
end

local function stepCanonicalPrimitive(state)
	local frame = state.stack[#state.stack]
	if not frame then return true end
	if frame.phase == "start" then
		if type(frame.value) ~= "table" or frame.depth >= 8 then
			finishCanonicalFrame(state, type(frame.value)=="table" and "t0:" or stableScalar(frame.value))
			return state.result ~= nil
		end
		frame.entries={}
		frame.iter,frame.iterState,frame.key=pairs(frame.value)
		frame.phase="enumerate"
		return false
	end
	if frame.phase == "enumerate" then
		local key, child=frame.iter(frame.iterState,frame.key)
		frame.key=key
		if key ~= nil then
			if not REVISION_KEYS[key] then
				frame.pendingPrefix=stableScalar(key).."="
				state.stack[#state.stack+1]={value=child,depth=frame.depth+1,phase="start"}
			end
			return false
		end
		frame.sort=beginMergeSort(frame.entries,function(a,b) return a<b end)
		frame.phase="sort"
		return false
	end
	if frame.phase == "sort" then
		if not stepMergeSort(frame.sort) then return false end
		frame.parts={}; frame.partIndex=1; frame.phase="parts"
		return false
	end
	if frame.phase == "parts" then
		local entry=frame.entries[frame.partIndex]
		if entry then
			local prefix=frame.partIndex==1 and ("t"..tostring(#frame.entries)..":") or ";"
			frame.parts[#frame.parts+1]=prefix..entry; frame.partIndex=frame.partIndex+1
			return false
		end
		if #frame.parts==0 then frame.parts[1]="t0:" end
		frame.joinSource,frame.joinDest,frame.joinIndex=frame.parts,{},1
		frame.phase="join"
		return false
	end
	if #frame.joinSource <= 1 then
		finishCanonicalFrame(state,frame.joinSource[1] or "")
		return state.result ~= nil
	end
	local left=frame.joinSource[frame.joinIndex]
	local right=frame.joinSource[frame.joinIndex+1]
	if left then
		frame.joinDest[#frame.joinDest+1]=right and (left..right) or left
		frame.joinIndex=frame.joinIndex+2
		return false
	end
	frame.joinSource,frame.joinDest,frame.joinIndex=frame.joinDest,{},1
	return false
end

local function stepCanonical(state)
	-- Field cursor transitions are cheap primitives, not physical item captures.
	-- Batch a bounded number while retaining a one-millisecond yield boundary.
	local started=getTimestampMs and getTimestampMs() or 0
	for i=1,32 do
		if stepCanonicalPrimitive(state) then return true end
		if getTimestampMs and getTimestampMs()-started>=1 then break end
	end
	return false
end

local DETAIL_FIELDS = {"rowKey","fullType","displayName","worldSprite","category","subCategory",
	"gsSubKeys","gsSubKeysStr","learnedRecipeNames","numberOfPages","literatureTitle","mediaIndex",
	"mediaTitle","mediaCodes","dynamicSignature","dynamicStateKey","dynamicPercent","fluidState",
	"foodState","shapeFamily","productFamilyKey","shapeKey","conditionSignature","condition",
	"conditionMax","detailKind","variantKey","totalWeight","totalFluidAmount","totalFluidCapacity",
	"nativePath","nativeStatus","vanillaKey","effective","categoryEffective","routingIdentity","categorySource"}

local function markAsyncParent(job,key)
	if not job.affected[key] then job.affected[key]=true; job.stats.affectedParents=job.stats.affectedParents+1 end
end

local function finalNode(job,nodeId)
	local changed=job.nodeChanges[nodeId]
	if changed ~= nil then return changed ~= false and changed or nil end
	return job.previous and job.previous.nodes and job.previous.nodes[nodeId] or nil
end

local function startNode(job,captured)
	local previous=job.previous and job.previous.nodes and job.previous.nodes[captured.id] or nil
	-- Published node snapshots are replaced atomically by their producers. Their
	-- identity is the node revision: never serialize physical IDs/unit details to
	-- discover that a first-time node has no previous contribution.
	local iter,state,key=pairs(captured.snapshot)
	job.nodeWork={captured=captured,previous=previous,byParent={},iter=iter,
		iterState=state,key=key,phase="rows"}
end

local function stepNode(job)
	local work=job.nodeWork
	if not work then
		local captured=job.captured[job.nodeIndex]
		if not captured then job.phase="retire" return end
		job.stats.nodesVisited=job.stats.nodesVisited+1
		local previous=job.previous and job.previous.nodes and job.previous.nodes[captured.id] or nil
		if previous and previous.snapshot==captured.snapshot then
			job.nodeIndex=job.nodeIndex+1
			return
		end
		startNode(job,captured)
		return
	end
	if work.phase=="rows" then
		if work.detail then
			-- Only one representative is needed by an ordinary parent. The exact
			-- IDs and unit details remain in the authoritative snapshot for paging.
			local ids=work.detailSource.itemIds or {}
			local stop=math.min(#ids,work.detailIdIndex+31)
			for i=work.detailIdIndex,stop do
				local id=ids[i]
				if type(id)=="number" and id>=0 and id<math.huge and id==math.floor(id)
					and (not work.detailMinId or id<work.detailMinId) then work.detailMinId=id end
			end
			work.detailIdIndex=stop+1
			if work.detailIdIndex<=#ids then return end
			work.detail.itemIds=work.detailMinId and {work.detailMinId} or {}
			work.detail.rowKey=work.detail.rowKey or work.detailGroupKey
			local parentKey=parentKeyForRow(work.detail)
			local contribution=work.byParent[parentKey]
			if not contribution then contribution={rows={}}; work.byParent[parentKey]=contribution end
			contribution.rows[#contribution.rows+1]=work.detail
			job.stats.retainedBytes=job.stats.retainedBytes+320+#(work.detail.itemIds or {})*16
			work.detail,work.detailSource,work.detailGroupKey,work.detailMinId=nil,nil,nil,nil
			return
		end
		local groupKey,row=work.iter(work.iterState,work.key)
		work.key=groupKey
		if groupKey ~= nil then
			work.detail={nodeId=work.captured.id,count=row.count or 0}
			for i=1,#DETAIL_FIELDS do local field=DETAIL_FIELDS[i]; work.detail[field]=row[field] end
			work.detailSource,work.detailGroupKey,work.detailIdIndex=row,groupKey,1
			return
		end
		work.parentIter,work.parentState,work.parentKey=pairs(work.byParent)
		work.phase="contributionStart"
		return
	end
	if work.phase=="contributionStart" then
		local key,contribution=work.parentIter(work.parentState,work.parentKey); work.parentKey=key
		if key~=nil then
			work.contribution=contribution; work.contributionCanonical=beginCanonical(contribution.rows)
			work.phase="contributionSignature"; return
		end
		work.compareIter,work.compareState,work.compareKey=pairs(work.previous and work.previous.byParent or {})
		work.phase="compareOld"; return
	end
	if work.phase=="contributionSignature" then
		if not stepCanonical(work.contributionCanonical) then return end
		work.contribution.signature=work.contributionCanonical.result
		job.stats.retainedBytes=job.stats.retainedBytes+#work.contribution.signature
		work.contribution,work.contributionCanonical=nil,nil; work.phase="contributionStart"; return
	end
	if work.phase=="compareOld" then
		local key,old=work.compareIter(work.compareState,work.compareKey); work.compareKey=key
		if key~=nil then
			local replacement=work.byParent[key]
			if not replacement or replacement.signature~=old.signature then markAsyncParent(job,key) end
			return
		end
		work.compareIter,work.compareState,work.compareKey=pairs(work.byParent)
		work.phase="compareNew"; return
	end
	if work.phase=="compareNew" then
		local key,replacement=work.compareIter(work.compareState,work.compareKey); work.compareKey=key
		if key~=nil then
			local old=work.previous and work.previous.byParent and work.previous.byParent[key]
			if not old or old.signature~=replacement.signature then markAsyncParent(job,key) end
			return
		end
	end
	job.nodeChanges[work.captured.id]={snapshot=work.captured.snapshot,signature=work.signature,byParent=work.byParent}
	job.stats.nodesProcessed=job.stats.nodesProcessed+1
	job.nodeWork=nil; job.nodeIndex=job.nodeIndex+1
end

local function newParent(parentKey)
	return {rowKey=parentKey,count=0,locations={},variantSummary={},totalWeight=0,foodSummary={},
		totalFluidAmount=0,totalFluidCapacity=0,_variantSeen={},_pathSeen={},_detailKinds={},
		_fullTypeSeen={},nativePaths={},fullTypes={},_locationSeen={}}
end

local PARENT_COPY_FIELDS = {"fullType","displayName","worldSprite","category","subCategory","gsSubKeys",
	"gsSubKeysStr","learnedRecipeNames","numberOfPages","mediaIndex","mediaTitle","mediaCodes"}

local function beginDetail(parent,detail)
	local state={detail=detail,itemIndex=1,locationIndex=1,phase="aggregate"}
	if not parent.fullType then state.copyIndex=1; state.phase="copy" end
	return state
end

local function aggregateDetail(parent,state)
	local detail=state.detail
	parent.count=parent.count+(detail.count or 0)
	parent.totalWeight=parent.totalWeight+(detail.totalWeight or 0)
	parent.totalFluidAmount=parent.totalFluidAmount+(detail.totalFluidAmount or 0)
	parent.totalFluidCapacity=parent.totalFluidCapacity+(detail.totalFluidCapacity or 0)
	local food=detail.foodState
	if food then
		if food.rotten==true then parent.foodSummary.Rotten=true elseif food.fresh==true then parent.foodSummary.Fresh=true
		elseif food.fresh==false then parent.foodSummary.Stale=true end
		if food.burnt==true then parent.foodSummary.Burnt=true elseif food.cooked==true then parent.foodSummary.Cooked=true end
		if food.frozen==true then parent.foodSummary.Frozen=true end
	end
	if not parent._fullTypeSeen[detail.fullType] then
		parent._fullTypeSeen[detail.fullType]=true; parent.fullTypes[#parent.fullTypes+1]=detail.fullType
	end
	local kind=detailKindForRow(detail)
	if kind and not parent._detailKinds[kind] then parent._detailKinds[kind]=true; parent.kindCount=(parent.kindCount or 0)+1 end
	if detail.nativePath and not parent._pathSeen[detail.nativePath] then
		parent._pathSeen[detail.nativePath]=true; parent.nativePaths[#parent.nativePaths+1]=detail.nativePath
	end
	countPhysicalVariant(parent,detail)
	local variantKey=visibleVariantKey(detail,kind)
	local summary=parent._variantSeen[variantKey]
	if not summary then
		summary={key=variantKey,count=0,detailKind=kind,fullType=detail.fullType,displayName=detail.displayName,
			literatureTitle=detail.literatureTitle,mediaIndex=detail.mediaIndex,mediaTitle=detail.mediaTitle,
			mediaCodes=detail.mediaCodes,dynamicStateKey=detail.dynamicStateKey,
			foodState=visibleFoodState(detail.foodState),nativePath=detail.nativePath}
		parent._variantSeen[variantKey]=summary; parent.variantSummary[#parent.variantSummary+1]=summary
	end
	state.summary=summary
end

local function betterRepresentative(id,nodeId,currentId,currentNode)
	return type(id)=="number" and id>=0 and id<math.huge and id==math.floor(id) and type(nodeId)=="string"
		and (not currentId or id<currentId or (id==currentId and nodeId<currentNode))
end

local function stepDetail(parent,state)
	local detail=state.detail
	if state.phase=="copy" then
		for i=1,#PARENT_COPY_FIELDS do local field=PARENT_COPY_FIELDS[i]; parent[field]=detail[field] end
		state.phase="aggregate"; return false
	end
	if state.phase=="aggregate" then aggregateDetail(parent,state); state.phase="items"; return false end
	local summary=state.summary
	local id=(detail.itemIds or {})[state.itemIndex]
	if id ~= nil then
		local nodeId=detail.unitNodeIds and detail.unitNodeIds[id] or detail.nodeId
		if betterRepresentative(id,nodeId,parent.representativeItemId,parent.representativeNodeId) then
			parent.representativeItemId,parent.representativeNodeId=id,nodeId
			parent.representativeFullType,parent.representativeDynamicSignature=detail.fullType,detail.dynamicSignature
		end
		if betterRepresentative(id,nodeId,summary.representativeItemId,summary.representativeNodeId) then
			summary.representativeItemId,summary.representativeNodeId=id,nodeId
			summary.representativeFullType,summary.representativeDynamicSignature=detail.fullType,detail.dynamicSignature
		end
		state.itemIndex=state.itemIndex+1
		return false
	end
	local location=(detail.locations or {})[state.locationIndex]
	if location then
		local existing=parent._locationSeen[location.nodeId]
		if existing then existing.count=existing.count+(location.count or 0)
		elseif location.nodeId and (location.count or 0)>0 then
			existing={nodeId=location.nodeId,count=location.count}; parent._locationSeen[location.nodeId]=existing
			parent.locations[#parent.locations+1]=existing
		end
		state.locationIndex=state.locationIndex+1
		return false
	end
	if detail.nodeId and #(detail.locations or {})==0 then
		local existing=parent._locationSeen[detail.nodeId]
		if existing then existing.count=existing.count+(detail.count or 0)
		elseif (detail.count or 0)>0 then
			existing={nodeId=detail.nodeId,count=detail.count}; parent._locationSeen[detail.nodeId]=existing
			parent.locations[#parent.locations+1]=existing
		end
	end
	summary.count=summary.count+(detail.count or 0)
	return true
end

local function classifyAsync(row)
	local pathCount=#row.nativePaths
	row._physicalVariants=nil; row.categoryCount=pathCount; row.locationCount=#row.locations
	row.cosmeticVariants=#row.fullTypes>1
	if row.cosmeticVariants then
		row.fullType=variantFamilyKey(row.fullType); row.displayName=GlobalStorageSiK.I18n.typeDisplayName(row.fullType)
	end
	row.expandable=row.count>1
	row.aggregateAllowed=row.count==1 or (row.kindCount or 0)==0
		or (row._detailKinds.recorded_media and row.mediaIndex~=nil)
	row.selectionMode=((row.kindCount or 0)>0 or row.cosmeticVariants) and "exact_group" or "aggregate"
	row.detailMode=row.cosmeticVariants and (row.kindCount or 0)==0 and "variants" or "instances"
	row.mixedVariants=pathCount>1
	if not row.mixedVariants and #row.variantSummary>0 then row.nativePath=row.variantSummary[1].nativePath end
	if row._detailKinds.recorded_media and row.mediaTitle then row.displayName=row.mediaTitle end
	if not row.mixedVariants or row.nativePath then
		local resolution=GlobalStorageSiK.CategoryResolution.resolve(row.fullType,row,nil)
		row.nativePath=resolution.nativePath
		row.nativeStatus,row.vanillaKey=resolution.nativeStatus,resolution.vanillaKey
		row.effective,row.categoryEffective=resolution.effective,resolution.effective
		row.routingIdentity,row.categorySource=resolution.routingIdentity,resolution.categorySource
	else
		row.nativeStatus,row.effective,row.categoryEffective="variants","variants","variants"
		row.routingIdentity="variants:"..tostring(row.rowKey)
	end
	row.itemIds,row.unitDetails,row.unitNodeIds=nil,nil,nil
	row.kindCount,row._variantSeen,row._pathSeen,row._detailKinds,row._fullTypeSeen,row._locationSeen=nil,nil,nil,nil,nil,nil
	GlobalStorageSiK.NativeProduct.tracePathSample("buildRows",row.fullType,row.nativePath)
end

local function beginParent(job,parentKey)
	job.parentWork={key=parentKey,row=newParent(parentKey),nodeIndex=1,detailIndex=1,phase="gather"}
end

local ASYNC_SEARCH_FIELDS = {"key","displayName","mediaTitle","dynamicStateKey","nativePath"}

local function stepParent(job)
	local work=job.parentWork
	if not work then
		local key=job.parentKeys[job.parentIndex]
		if not key then job.phase="materialKeys" return end
		beginParent(job,key); return
	end
	if work.phase=="gather" then
		if work.detail then
			if stepDetail(work.row,work.detail) then work.detail=nil; work.detailIndex=work.detailIndex+1 end
			return
		end
		local captured=job.captured[work.nodeIndex]
		if not captured then
			if not work.hadDetail then
				job.parentChanges[work.key]=false
				job.stats.parentsProcessed=job.stats.parentsProcessed+1
				job.parentWork=nil; job.parentIndex=job.parentIndex+1
				return
			end
			work.pathSort=beginMergeSort(work.row.nativePaths,function(a,b)return a<b end)
			work.fullSort=beginMergeSort(work.row.fullTypes,function(a,b)return a<b end)
			work.phase="sortPaths"; return
		end
		local node=finalNode(job,captured.id)
		local contribution=node and node.byParent and node.byParent[work.key]
		local detail=contribution and contribution.rows[work.detailIndex]
		if detail then work.hadDetail=true; work.detail=beginDetail(work.row,detail)
		else work.nodeIndex=work.nodeIndex+1; work.detailIndex=1 end
		return
	end
	if work.phase=="sortPaths" then
		if stepMergeSort(work.pathSort) then work.phase="sortTypes" end; return
	end
	if work.phase=="sortTypes" then
		if stepMergeSort(work.fullSort) then work.searchIndex=1; work.searchParts={}; work.phase="search" end; return
	end
	if work.phase=="search" then
		local summary=work.row.variantSummary[work.searchIndex]
		if summary then
			work.searchField=work.searchField or 1
			local field=ASYNC_SEARCH_FIELDS[work.searchField]
			if field then
				local value=summary[field]
				if value then
					local prefix=#work.searchParts==0 and "" or " "
					work.searchParts[#work.searchParts+1]=prefix..tostring(value)
				end
				work.searchField=work.searchField+1; return
			end
			local icon=summary.foodState and summary.foodState.iconVariant
			if work.searchIndex==1 then work.foodIcon=icon elseif icon~=work.foodIcon then work.foodAgree=false end
			if work.foodAgree==nil then work.foodAgree=true end
			work.searchIndex=work.searchIndex+1; work.searchField=1; return
		end
		if #work.searchParts==0 then work.searchParts[1]="" end
		work.joinSource,work.joinDest,work.joinIndex=work.searchParts,{},1
		work.phase="searchJoin"; return
	end
	if work.phase=="searchJoin" then
		if #work.joinSource>1 then
			local left=work.joinSource[work.joinIndex]
			local right=work.joinSource[work.joinIndex+1]
			if left then
				work.joinDest[#work.joinDest+1]=right and (left..right) or left
				work.joinIndex=work.joinIndex+2; return
			end
			work.joinSource,work.joinDest,work.joinIndex=work.joinDest,{},1; return
		end
		work.row.variantSearchText=work.joinSource[1] or ""
		work.row.foodIconVariant=work.foodAgree and work.foodIcon or nil
		if classificationStamp()~=job.classificationStamp then
			job.error={stage="classification",cause="catalog_stale_classification"}; return
		end
		classifyAsync(work.row)
		work.canonical=beginCanonical(work.row); work.phase="signature"; return
	end
	if not stepCanonical(work.canonical) then return end
	rowSignatureCache[work.row]=work.canonical.result
	job.parentChanges[work.key]=work.row
	job.stats.parentsProcessed=job.stats.parentsProcessed+1
	job.stats.retainedBytes=job.stats.retainedBytes+640+(work.row.count or 0)*24
	job.parentWork=nil; job.parentIndex=job.parentIndex+1
end

local function stepMaterial(job)
	local work=job.materialWork
	if not work then
		local key=job.materialKeys[job.materialIndex]
		if not key then
			job.rowSort=beginMergeSort(job.rows,function(a,b)
				local an,bn=tostring(a.displayName or ""),tostring(b.displayName or "")
				return an==bn and tostring(a.rowKey)<tostring(b.rowKey) or an<bn
			end)
			job.phase="sortRows"; return
		end
		local parent=job.parentChanges[key]
		if parent==nil then parent=job.previous and job.previous.parents and job.previous.parents[key] end
		if parent==false or not parent then job.materialIndex=job.materialIndex+1; return end
		local iter,state,key0=pairs(parent)
		job.materialWork={parent=parent,row={},iter=iter,iterState=state,key=key0,phase="fields"}
		return
	end
	if work.phase=="fields" then
		local key,value=work.iter(work.iterState,work.key); work.key=key
		if key~=nil then
			if key~="variantSummary" then work.row[key]=value end
			return
		end
		work.row.variantSummary={}; work.variantIndex=1; work.phase="variants"; return
	end
	if work.phase=="variants" then
		local variant=work.parent.variantSummary and work.parent.variantSummary[work.variantIndex]
		if variant then
			work.variantSource,work.variantCopy=variant,{}
			work.variantIter,work.variantState,work.variantKey=pairs(variant)
			work.phase="variantFields"; return
		end
		work.row.selectionRevision,work.row.representativeRevision=job.revision,job.revision
		work.row.sourceNodeId=job.sourceNodeId
		local signature=rowSignatureCache[work.parent]
		if job.sourceNodeId~=nil then
			local scoped=scopedRowSignatureCache[work.parent] or {}
			scopedRowSignatureCache[work.parent]=scoped; signature=scoped[job.sourceNodeId]
			if not signature then work.canonical=beginCanonical(work.row); work.phase="signature"; return end
		end
		rowSignatureCache[work.row]=signature
		job.rows[#job.rows+1]=work.row
		job.stats.outputUnits=job.stats.outputUnits+(work.row.count or 0)
		job.stats.retainedBytes=job.stats.retainedBytes+640
		job.materialWork=nil; job.materialIndex=job.materialIndex+1
		return
	end
	if work.phase=="variantFields" then
		local key,value=work.variantIter(work.variantState,work.variantKey); work.variantKey=key
		if key~=nil then work.variantCopy[key]=value; return end
		if work.variantCopy.representativeItemId then work.variantCopy.representativeRevision=job.revision end
		work.row.variantSummary[work.variantIndex]=work.variantCopy
		work.variantIndex=work.variantIndex+1; work.phase="variants"; return
	end
	if not stepCanonical(work.canonical) then return end
	local scoped=scopedRowSignatureCache[work.parent]
	scoped[job.sourceNodeId]=work.canonical.result
	rowSignatureCache[work.row]=work.canonical.result
	job.rows[#job.rows+1]=work.row
	job.stats.outputUnits=job.stats.outputUnits+(work.row.count or 0)
	job.stats.retainedBytes=job.stats.retainedBytes+640+#work.canonical.result
	job.materialWork=nil; job.materialIndex=job.materialIndex+1
end

function GlobalStorageSiK.Index.beginCatalogBuild(networkId,player,sourceNodeId,inventoryRevision)
	local registry=GlobalStorageSiK.Zones.getRegistry()
	networkId=networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	buildGeneration=buildGeneration+1
	local job={networkId=networkId,player=player,sourceNodeId=sourceNodeId,
		revision=tonumber(inventoryRevision) or GlobalStorageSiK.Index.getInventoryRevision(networkId),
		classificationStamp=classificationStamp(),generation=buildGeneration,captured={},visible={},
		nodeChanges={},parentChanges={},affected={},nodeIndex=1,phase="nodes",rows={},cancelled=false,
		stats={nodesVisited=0,nodesProcessed=0,parentsProcessed=0,snapshotSignaturesComputed=0,
			affectedParents=0,workTotal=0,workLastStep=0,sortWork=0,retainedBytes=1024,
			outputUnits=0,beginNodesCaptured=0}}
	job.cacheKey=scopeKeyFor(registry,networkId,player,sourceNodeId)
	job.previous=buildCache[job.cacheKey]
	local scanned=0
	for nodeId,node in pairs(registry.nodes or {}) do
		scanned=scanned+1
		if scanned>ASYNC_MAX_NODES then
			job.error={stage="begin",cause="catalog_nodes_limit"}; break
		end
		local zone=registry.zones and registry.zones[node.zoneId]
		if zone and zone.networkId==networkId and node.membership~="excluded" and node.enabled~=false
			and node.offline~=true and (sourceNodeId==nil or sourceNodeId==node.id)
			and (not player or GlobalStorageSiK.Permissions.canAccessZone(player,networkId,node.zoneId)) then
			if #job.captured>=ASYNC_MAX_NODES then
				job.error={stage="begin",cause="catalog_nodes_limit"}; break
			end
			local id=node.id or nodeId
			job.captured[#job.captured+1]={id=id,zoneId=node.zoneId,snapshot=node.itemSnapshot or EMPTY_ASYNC_SNAPSHOT}
			job.visible[id]=true
		end
	end
	job.stats.beginNodesCaptured=#job.captured
	job.stats.beginNodesScanned=scanned
	job.stats.retainedBytes=job.stats.retainedBytes+#job.captured*96
	return job
end

function GlobalStorageSiK.Index.cancelCatalogBuild(job)
	if type(job)=="table" then
		job.cancelled=true; job.nodeWork=nil; job.parentWork=nil; job.materialWork=nil
		job.rows=nil; job.captured=nil; job.visible=nil; job.nodeChanges=nil; job.parentChanges=nil
		return true
	end
	return false
end

local function advanceAsync(job)
	if job.phase=="nodes" then stepNode(job)
	elseif job.phase=="retire" then
		if job.retireParentIter then
			local parentKey=job.retireParentIter(job.retireParentState,job.retireParentKey)
			job.retireParentKey=parentKey
			if parentKey~=nil then markAsyncParent(job,parentKey)
			else job.retireParentIter,job.retireParentState,job.retireParentKey=nil,nil,nil end
			return
		end
		if not job.retireIter then
			local nodes=job.previous and job.previous.nodes or {}
			job.retireIter,job.retireState,job.retireKey=pairs(nodes)
		end
		local key,node=job.retireIter(job.retireState,job.retireKey); job.retireKey=key
		if key~=nil then
			if not job.visible[key] then
				job.nodeChanges[key]=false
				job.retireParentIter,job.retireParentState,job.retireParentKey=pairs(node.byParent or {})
				job.stats.nodesProcessed=job.stats.nodesProcessed+1
			end
		else
			if not job.previous or job.previous.classificationStamp~=job.classificationStamp then
				job.stats.classificationInvalidated=true
				job.phase="invalidateParents"
				job.phaseIter,job.phaseState,job.phaseKey=pairs(job.previous and job.previous.parents or {})
			else
				job.phase="collectParentKeys"
				job.phaseIter,job.phaseState,job.phaseKey=pairs(job.affected)
				job.parentKeys={}
			end
		end
	elseif job.phase=="invalidateParents" then
		local key=job.phaseIter(job.phaseState,job.phaseKey); job.phaseKey=key
		if key~=nil then markAsyncParent(job,key)
		else
			job.phase="collectParentKeys"; job.parentKeys={}
			job.phaseIter,job.phaseState,job.phaseKey=pairs(job.affected)
		end
	elseif job.phase=="collectParentKeys" then
		local key=job.phaseIter(job.phaseState,job.phaseKey); job.phaseKey=key
		if key~=nil then job.parentKeys[#job.parentKeys+1]=key
		else job.parentIndex=1; job.phase="parents" end
	elseif job.phase=="parents" then stepParent(job)
	elseif job.phase=="materialKeys" then
		job.materialSet={}; job.materialKeys={}
		job.phaseIter,job.phaseState,job.phaseKey=pairs(job.previous and job.previous.parents or {})
		job.phase="materialPrevious"
	elseif job.phase=="materialPrevious" then
		local key=job.phaseIter(job.phaseState,job.phaseKey); job.phaseKey=key
		if key~=nil then job.materialSet[key]=true
		else
			job.phaseIter,job.phaseState,job.phaseKey=pairs(job.parentChanges)
			job.phase="materialChanges"
		end
	elseif job.phase=="materialChanges" then
		local key,value=job.phaseIter(job.phaseState,job.phaseKey); job.phaseKey=key
		if key~=nil then job.materialSet[key]=value~=false or nil
		else
			job.phaseIter,job.phaseState,job.phaseKey=pairs(job.materialSet)
			job.phase="materialCollect"
		end
	elseif job.phase=="materialCollect" then
		local key=job.phaseIter(job.phaseState,job.phaseKey); job.phaseKey=key
		if key~=nil then job.materialKeys[#job.materialKeys+1]=key
		else job.materialSet=nil; job.materialIndex=1; job.phase="material" end
	elseif job.phase=="material" then stepMaterial(job)
	elseif job.phase=="sortRows" then
		job.stats.sortWork=job.stats.sortWork+1
		if stepMergeSort(job.rowSort) then
			job.commitEntry={nodes={},parents={},classificationStamp=job.classificationStamp,
				revision=job.revision,generation=job.generation}
			job.commitIndex=1; job.phase="commitNodes"
		end
	elseif job.phase=="commitNodes" then
		local captured=job.captured[job.commitIndex]
		if captured then
			job.commitEntry.nodes[captured.id]=finalNode(job,captured.id); job.commitIndex=job.commitIndex+1
		else job.commitIndex=1; job.phase="commitParents" end
	elseif job.phase=="commitParents" then
		local key=job.materialKeys[job.commitIndex]
		if key then
			local value=job.parentChanges[key]
			if value==nil then value=job.previous and job.previous.parents and job.previous.parents[key] end
			if value and value~=false then job.commitEntry.parents[key]=value end
			job.commitIndex=job.commitIndex+1
		else
			local bytes=#job.captured*160+#job.rows*640+job.stats.outputUnits*24
			job.stats.cacheBytes=bytes; job.commitEntry.bytes=bytes
			if bytes>BUILD_ENTRY_BYTES then job.error={stage="cache",cause="catalog_budget"}; return end
			job.phase="commitPublish"
		end
	elseif job.phase=="commitPublish" then
		local current=buildCache[job.cacheKey]
		if classificationStamp()~=job.classificationStamp then
			job.error={stage="classification",cause="catalog_stale_classification"}; return
		end
		local sameClass=not current or current.classificationStamp==job.classificationStamp
		local currentRevision=tonumber(current and current.revision) or -1
		local publish=sameClass and (not current
			or currentRevision<job.revision or (currentRevision==job.revision and (current.generation or 0)<=job.generation))
		if publish then
			buildCacheClock=buildCacheClock+1; job.commitEntry.usedAt=buildCacheClock
			buildCacheBytes=math.max(0,buildCacheBytes-(current and current.bytes or 0))+job.commitEntry.bytes
			buildCache[job.cacheKey]=job.commitEntry
		end
		job.trimProtected=publish and job.cacheKey or nil; job.trimCount=0
		job.phaseIter,job.phaseState,job.phaseKey=pairs(buildCache)
		job.phase="trimScan"
	elseif job.phase=="trimScan" then
		local key,entry=job.phaseIter(job.phaseState,job.phaseKey); job.phaseKey=key
		if key~=nil then
			job.trimCount=job.trimCount+1
			if key~=job.trimProtected and (not job.trimOldestAt or entry.usedAt<job.trimOldestAt) then
				job.trimOldestKey,job.trimOldestAt=key,entry.usedAt
			end
		else
			if (buildCacheBytes>BUILD_CACHE_BYTES or job.trimCount>BUILD_CACHE_LIMIT) and job.trimOldestKey then
				local old=buildCache[job.trimOldestKey]
				buildCacheBytes=math.max(0,buildCacheBytes-(old and old.bytes or 0)); buildCache[job.trimOldestKey]=nil
				job.trimCount,job.trimOldestKey,job.trimOldestAt=0,nil,nil
				job.phaseIter,job.phaseState,job.phaseKey=pairs(buildCache)
			else job.done=true end
		end
	end
end

function GlobalStorageSiK.Index.stepCatalogBuild(job,maxWork,maxMillis)
	if type(job)~="table" then return true,nil,nil end
	if job.cancelled then
		job.error=job.error or {stage="cancel",cause="catalog_cancelled"}
		if job.stats then job.stats.workLastStep=0 end
		return true,nil,job.stats
	end
	if job.done or job.error then return true,job.done and job.rows or nil,job.stats end
	local budget=math.max(1,math.floor(tonumber(maxWork) or 32))
	local millis=tonumber(maxMillis); if millis==nil then millis=4 end
	local started=type(getTimestampMs)=="function" and getTimestampMs() or 0
	local work=0
	while not job.done and not job.error and work<budget do
		if millis>0 and type(getTimestampMs)=="function" and getTimestampMs()-started>=millis then break end
		advanceAsync(job); work=work+1
		if job.stats.retainedBytes>ASYNC_MAX_RETAINED then
			job.error={stage="memory",cause="catalog_budget"}
		end
	end
	job.stats.workLastStep=work; job.stats.workTotal=job.stats.workTotal+work
	return job.done or job.error~=nil,job.done and job.rows or nil,job.stats
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
	local seenPhysicalIds = {}
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
						if seenPhysicalIds[itemId] then
							if GlobalStorageSiK.Log then GlobalStorageSiK.Log.warn("ItemIdentity",
								"duplicate_physical_id network=" .. tostring(networkId) .. " source=itemDetails") end
							return {rowKey=rowKey, page=page, pageSize=pageSize,
								items={}, reason="item_id_duplicate", invalidIdentity=true}
						end
						seenPhysicalIds[itemId] = true
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
							nativeStatus = row.nativeStatus or (row.nativePath and "classified" or nil),
							vanillaKey = row.vanillaKey,
							effective = row.effective or (row.nativePath and "native" or nil),
							categoryEffective = row.categoryEffective or row.effective
								or (row.nativePath and "native" or nil),
							routingIdentity = row.routingIdentity,
							categorySource = row.categorySource,
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

stableScalar = function(value)
	local kind = type(value)
	if kind == "nil" then return "n" end
	if kind == "boolean" then return value and "b1" or "b0" end
	if kind == "number" then return "d" .. string.format("%.17g", value) end
	local text = tostring(value)
	return "s" .. tostring(#text) .. ":" .. text
end

-- Delta de catálogo: incluye recursivamente todo campo observable de cada fila.
-- Solo los sellos de revisión se excluyen porque cambian sin alterar contenido.
local REVISION_STAMPS = { selectionRevision = true, representativeRevision = true }
local function stableVisibleValue(value, depth)
	if type(value) ~= "table" then return stableScalar(value) end
	if depth >= 8 then return "t0:" end
	local entries = {}
	for key, child in pairs(value) do
		if not REVISION_STAMPS[key] then
			entries[#entries + 1] = stableScalar(key) .. "=" .. stableVisibleValue(child, depth + 1)
		end
	end
	table.sort(entries)
	return "t" .. tostring(#entries) .. ":" .. table.concat(entries, ";")
end

computeRowSignature = function(row) return stableVisibleValue(row, 0) end
function GlobalStorageSiK.Index.rowSignature(row)
	if type(row) ~= "table" then return nil, "catalog_schema" end
	local signature = rowSignatureCache[row]
	if not signature then signature=computeRowSignature(row); rowSignatureCache[row]=signature end
	return signature
end

function GlobalStorageSiK.Index.snapshotSignature(snapshot)
	local rows = {}
	for _, row in pairs(snapshot or {}) do
		rows[#rows + 1] = stableVisibleValue(row, 0)
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
		parts[#parts + 1] = ";snapshot=" .. immutableSnapshotSignature(node.itemSnapshot)
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
						if itemId and seen[itemId] then
							if GlobalStorageSiK.Log then GlobalStorageSiK.Log.warn("ItemIdentity",
								"duplicate_physical_id network=" .. tostring(networkId) .. " source=exactGroup") end
							return nil, "item_id_duplicate"
						end
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

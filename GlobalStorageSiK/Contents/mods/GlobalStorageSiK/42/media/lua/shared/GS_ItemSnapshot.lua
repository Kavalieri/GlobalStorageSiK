--[[
	GlobalStorageSiK - Instantánea de ítems en contenedor (MP / servidor)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Cachea inventario al escanear para cuando el chunk no está cargado en servidor.
]]

require "GS_Router"
require "GS_I18n"
require "GS_FluidTaxonomy"
require "GS_NativeProduct"
require "GS_RecordedMedia"

-- El publicador forma parte del runtime completo, pero ItemSnapshot tambien se
-- carga aislado en harnesses y consumidores de la API shared. Intentar cargarlo
-- sin convertirlo en una dependencia dura conserva ambos contratos.
if not GlobalStorageSiK.DisplayCategoryPublisher then
	pcall(require, "GS_DisplayCategoryPublisher")
end

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
	if (not sprite or sprite == "") and item.getWorldObjectSprite then
		local ok, value = pcall(function() return item:getWorldObjectSprite() end)
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

--- Nombres de receta que enseña este ítem (para el tick de "ya leído" del
--- Almacén), leídos de un item REAL, tal cual hace vanilla (ISInventoryPane.lua,
--- ISReadABook.lua: siempre item:getLearnedRecipes() sobre un item vivo, nunca
--- un script ni una sonda instanceItem()). Aquí SÍ tenemos items reales -
--- ItemSnapshot.fromContainer/addItem se llama durante el escaneo de zona
--- sobre instancias genuinas del contenedor, no sobre nada sintético. Capturar
--- esto aquí (una vez por fullType, dato invariante del tipo) y mandarlo al
--- cliente evita depender de instanceItem() en el terminal - que nunca se
--- confirmó funcionando ni para revistas propias ni vanilla, tras varias
--- rondas de intentos (bug real 2026-08-21, señalado por el usuario: "si el
--- juego puede validar su lectura, nosotros también debemos poder").
---@param item InventoryItem|nil
---@return string[]|nil
local function learnedRecipeNamesFromItem(item)
	if not item or not item.getLearnedRecipes then return nil end
	local ok, recipes = pcall(function() return item:getLearnedRecipes() end)
	if not ok or not recipes or not recipes.size or recipes:size() == 0 then return nil end
	local names = {}
	local okNames = pcall(function()
		for i = 0, recipes:size() - 1 do
			names[#names + 1] = tostring(recipes:get(i))
		end
	end)
	if not okNames or #names == 0 then return nil end
	return names
end

--- Revistas de receta (OnCreate = ItemCodeOnCreate.onCreateRecipeMagazine) NO
--- llevan NumberOfPages en el script como los libros de habilidad - lo asigna
--- el motor en tiempo de ejecucion sobre la instancia real al crearla. Un
--- scriptItem()/instanceItem() sin esa instanciacion real da NumberOfPages=0,
--- por lo que el check "paginas ya leidas == paginas totales" (el mismo que
--- YA funciona para libros de habilidad, ISInventoryPane:isLiteratureRead)
--- nunca se disparaba para revistas - no es un problema de recetas en
--- absoluto. Aqui SI tenemos una instancia real (escaneo de zona), se captura
--- una vez por fullType igual que learnedRecipeNamesFromItem.
---@param item InventoryItem|nil
---@return integer|nil
local function numberOfPagesFromItem(item)
	if not item or not item.getNumberOfPages then return nil end
	local ok, pages = pcall(function() return item:getNumberOfPages() end)
	if not ok or not pages or pages <= 0 then return nil end
	return pages
end

--- Mecanismo REAL del tick "ya leido" de vanilla (ISInventoryPane.lua:2585-2599,
--- confirmado leyendo el .lua real del juego instalado, no supuesto): NO es
--- getKnownRecipes() ni las paginas - esos son solo fallbacks al final de la
--- funcion vanilla. El camino PRINCIPAL, primero en el orden vanilla, es
--- item:getModData().literatureTitle comparado con
--- playerObj:isLiteratureRead(literatureTitle). El titulo es un valor
--- ALEATORIO POR COPIA asignado por el motor al crear la instancia (por eso
--- NO se puede meter en metadataByFullType como learnedRecipeNames/
--- numberOfPages, que si son invariantes de tipo - cachearlo por fullType
--- aplicaria el titulo de la PRIMERA copia vista a todas las demas). Se lee
--- fresco en cada llamada, directo del item real de esta instancia concreta.
---@param item InventoryItem|nil
---@return string|nil
local function literatureTitleFromItem(item)
	if not item or not item.hasModData or not item:hasModData() then return nil end
	local ok, modData = pcall(function() return item:getModData() end)
	if not ok or not modData then return nil end
	local title = modData.literatureTitle
	if not title or title == "" then return nil end
	return title
end

--- BUG REAL confirmado (2026-08-26, "agrupados por fullType nos perjudica
--- con los VHS"): a diferencia de los libros de habilidad (fullType DISTINTO
--- por habilidad/nivel, ej. Base.CarpentryBook1), TODAS las cintas VHS/radio
--- vanilla comparten el MISMO fullType generico - lo que enseña cada cinta
--- concreta vive en un dato de instancia (getRecordedMediaIndex(), un indice
--- a la tabla global RecMedia), asi que nuestro Almacen (agregado por
--- fullType) fundia todas las cintas del jugador en una sola fila sin poder
--- ver cual tenia, retirar una en concreto, ni aplicar el check verde que si
--- tienen libros/revistas.
---
--- Solucion B42.20: InventoryItem expone getMediaData(), que devuelve la
--- MediaData exacta de esta instancia sin convertir el indice short desde Lua.
--- Su ID/indice son identidad estable y getTranslatedItemDisplayName() es el
--- titulo localizado que usa vanilla. getDisplayName() NO sirve: puede ser el
--- nombre generico del soporte (p. ej. "Cinta VHS") y fundir ediciones.
--- Publica (no solo local) a proposito: GS_Transfer.lua (filtrar que cinta
--- fisica retirar) y GS_ItemNetworkTooltip.lua (contar en red solo cintas
--- con este mismo contenido) reutilizan EXACTAMENTE esta misma lectura, en
--- vez de cada uno duplicar su propia version del mismo pcall.
---@param item InventoryItem|nil
---@return string|nil
function GlobalStorageSiK.ItemSnapshot.recordedMediaIndexFromItem(item)
	if not item or not item.getRecordedMediaIndex then return nil end
	local okIdx, idx = pcall(function() return item:getRecordedMediaIndex() end)
	if not okIdx or not idx or idx < 0 then return nil end
	return math.floor(tonumber(idx) or -1)
end

function GlobalStorageSiK.ItemSnapshot.recordedMediaTitleFromItem(item)
	local idx = GlobalStorageSiK.ItemSnapshot.recordedMediaIndexFromItem(item)
	if not idx then return nil end
	if not item.getMediaData then return nil end
	local okData, mediaData = pcall(function() return item:getMediaData() end)
	if not okData or not mediaData or not mediaData.getTranslatedItemDisplayName then
		return nil
	end
	local okName, name = pcall(function() return mediaData:getTranslatedItemDisplayName() end)
	if not okName or not name or name == "" then return nil end
	return name
end

function GlobalStorageSiK.ItemSnapshot.recordedMediaIdFromItem(item)
	local idx = GlobalStorageSiK.ItemSnapshot.recordedMediaIndexFromItem(item)
	if not idx or not item or not item.getMediaData then return nil end
	local okData, mediaData = pcall(function() return item:getMediaData() end)
	if not okData or not mediaData or not mediaData.getId then return nil end
	local okId, id = pcall(function() return mediaData:getId() end)
	if not okId or not id or id == "" then return nil end
	return tostring(id)
end
local recordedMediaTitleFromItem = GlobalStorageSiK.ItemSnapshot.recordedMediaTitleFromItem

local function conditionState(item)
	if not item or not item.getCondition or not item.getConditionMax then return nil, nil, nil end
	local ok, current, maximum = pcall(function() return item:getCondition(), item:getConditionMax() end)
	if not ok or type(current) ~= "number" or type(maximum) ~= "number" or maximum <= 0 then
		return nil, nil, nil
	end
	current, maximum = math.floor(current), math.floor(maximum)
	return "condition=" .. tostring(current) .. "/" .. tostring(maximum), current, maximum
end

local function boolState(item, methodName)
	local method = item and item[methodName]
	if not method then return false end
	local ok, value = pcall(function() return method(item) end)
	return ok and value == true
end

local function scalarState(item, methodName)
	local method = item and item[methodName]
	if not method then return nil end
	local ok, value = pcall(function() return method(item) end)
	return ok and value or nil
end

local function collectionState(item, methodName)
	local collection = scalarState(item, methodName)
	if not collection then return nil end
	local values = {}
	if collection.size and collection.get then
		local size = tonumber(scalarState(collection, "size")) or 0
		for i = 0, size - 1 do
			local ok, value = pcall(function() return collection:get(i) end)
			if ok and value ~= nil then values[#values + 1] = tostring(value) end
		end
	elseif type(collection) == "table" then
		for _, value in pairs(collection) do
			if value ~= nil then values[#values + 1] = tostring(value) end
		end
	end
	if #values == 0 then return nil end
	table.sort(values)
	return values
end

local function encodeStateList(values)
	return values and table.concat(values, "\30") or ""
end

-- Estado discreto que hace que dos raciones de comida dejen de ser
-- intercambiables. No incluye la edad cruda: cambia continuamente y partiría
-- el índice en una fila por unidad aun cuando vanilla las presenta en el mismo
-- estado. Las transiciones que sí cambian lo que el jugador recibe (crudo,
-- cocinado, quemado, congelado o podrido) forman parte de la identidad.
local function foodState(item)
	if not item then return nil, nil end
	local isFood = boolState(item, "isFood") or boolState(item, "IsFood")
	if instanceof then
		local ok, value = pcall(function() return instanceof(item, "Food") end)
		isFood = ok and value == true
	end
	if not isFood and item.getAge then
		local ok, age = pcall(function() return item:getAge() end)
		isFood = ok and type(age) == "number"
	end
	if not isFood then return nil, nil end
	local extraItems = collectionState(item, "getExtraItems")
	local spices = collectionState(item, "getSpices")
	local uses = scalarState(item, "getCurrentUsesFloat")
	if type(uses) ~= "number" then uses = scalarState(item, "getCurrentUses") end
	if type(uses) == "number" then uses = math.floor(uses * 10000 + 0.5) / 10000 else uses = nil end
	local customName = nil
	if boolState(item, "isCustomName") then
		customName = scalarState(item, "getDisplayName") or scalarState(item, "getName")
		customName = customName and tostring(customName) or nil
	end
	local state = {
		fresh = boolState(item, "isFresh"),
		cooked = boolState(item, "isCooked"),
		burnt = boolState(item, "isBurnt"),
		frozen = boolState(item, "isFrozen"),
		rotten = boolState(item, "isRotten"),
		extraItems = extraItems,
		spices = spices,
		uses = uses,
		customName = customName,
	}
	local signature = string.format(
		"food:fresh=%d;cooked=%d;burnt=%d;frozen=%d;rotten=%d;uses=%s;extra=%s;spices=%s;name=%s",
		state.fresh and 1 or 0, state.cooked and 1 or 0, state.burnt and 1 or 0,
		state.frozen and 1 or 0, state.rotten and 1 or 0,
		tostring(uses or ""), encodeStateList(extraItems), encodeStateList(spices),
		tostring(customName or ""))
	return signature, state
end

local function actualWeight(item)
	if not item then return nil end
	local ok, value = pcall(function()
		if item.getActualWeight then return item:getActualWeight() end
		if item.getWeight then return item:getWeight() end
		return nil
	end)
	return ok and type(value) == "number" and value or nil
end

---@param item InventoryItem|nil
---@return table detalle serializable exacto para tooltip remoto
local function recordedMediaCodes(item)
	if not item or not item.getMediaData then return nil end
	local okData, mediaData = pcall(function() return item:getMediaData() end)
	if not okData or not mediaData or not mediaData.getLineCount or not mediaData.getLine then
		return nil
	end
	local okCount, count = pcall(function() return mediaData:getLineCount() end)
	if not okCount or type(count) ~= "number" then return nil end
	local result, seen, totalLength = {}, {}, 0
	for i = 0, math.min(63, math.max(0, math.floor(count) - 1)) do
		local okLine, line = pcall(function() return mediaData:getLine(i) end)
		local okCodes, codes = false, nil
		if okLine and line and line.getCodes then
			okCodes, codes = pcall(function() return line:getCodes() end)
		end
		codes = okCodes and codes and string.sub(tostring(codes), 1, 160) or nil
		if codes and codes ~= "" and not seen[codes] and totalLength + #codes <= 512 then
			seen[codes] = true
			result[#result + 1] = codes
			totalLength = totalLength + #codes
		end
	end
	return result
end
GlobalStorageSiK.ItemSnapshot.recordedMediaCodesFromItem = recordedMediaCodes

function GlobalStorageSiK.ItemSnapshot.tooltipDetailFromItem(item)
	if not item then return {} end
	local fullType = item.getFullType and item:getFullType() or nil
	local _, condition, conditionMax = conditionState(item)
	local fluid = GlobalStorageSiK.FluidTaxonomy.inspect
		and GlobalStorageSiK.FluidTaxonomy.inspect(item) or nil
	local fluidAmount, fluidCapacity = fluid and fluid.amount or nil, fluid and fluid.capacity or nil
	local fluidState = fluid and fluid.detail or nil
	local dynamicPath = fluid and fluid.path or nil
	local foodStateKey, food = foodState(item)
	return {
		fullType = fullType,
		displayName = fullType and GlobalStorageSiK.I18n.nameFromItemInstance(item, fullType) or nil,
		weight = actualWeight(item),
		condition = condition,
		conditionMax = conditionMax,
		mediaIndex = GlobalStorageSiK.ItemSnapshot.recordedMediaIndexFromItem(item),
		mediaTitle = recordedMediaTitleFromItem(item),
		mediaCodes = recordedMediaCodes(item),
		dynamicStateKey = (fluid and fluid.stateKey) or foodStateKey,
		dynamicPercent = fluid and fluid.fillPercent or nil,
		fluidType = fluid and fluid.canonicalType or nil,
		fluidAmount = fluidAmount,
		fluidCapacity = fluidCapacity,
		fluidState = fluidState,
		foodState = food,
		nativePath = dynamicPath and GlobalStorageSiK.NativeProduct
			and GlobalStorageSiK.NativeProduct.encodePath(dynamicPath) or nil,
	}
end

local function looksRecordedMedia(item, fullType)
	if item and item.isRecordedMedia then
		local ok, value = pcall(function() return item:isRecordedMedia() end)
		if ok and value == true then return true end
	end
	local scriptItem = item and item.getScriptItem
		and select(2, pcall(function() return item:getScriptItem() end)) or nil
	if scriptItem and scriptItem.getRecordedMediaCat then
		local ok, value = pcall(function() return scriptItem:getRecordedMediaCat() end)
		if ok and value and tostring(value) ~= "" then return true end
	end
	-- Compatibilidad acotada para fixtures/mods antiguos sin señal estructural.
	-- Solo tipos que empiezan como soporte grabado; nunca CDPlayer/DVDPlayer.
	local name = string.lower(tostring(fullType or "")):match("^[^.]+%.(.+)$")
	name = name or string.lower(tostring(fullType or ""))
	return name:find("vhs", 1, true) == 1 or name:find("cassette", 1, true) == 1
		or name:find("dvd_disc", 1, true) == 1 or name:find("cd_disc", 1, true) == 1
end

local function metadataForItem(item, fullType)
	local worldSprite = readWorldSprite(item)
	local cacheKey = fullType .. "\31" .. tostring(worldSprite or "")
	local cached = metadataByFullType[cacheKey]
	if cached then return cached end
	local gsKeysList = {}
	local displayName = GlobalStorageSiK.I18n.nameFromItemInstance(item, fullType)
	if not displayName or GlobalStorageSiK.I18n.isLowQualityDisplayName(displayName) then
		displayName = GlobalStorageSiK.I18n.moveableDisplayNameFromSprite(worldSprite)
	end
	-- Si tiene worldSprite y aun asi moveableDisplayNameFromSprite no supo
	-- resolverlo, es (2026-08-22, confirmado en pruebas reales - spam de
	-- "Couldn't find item Base.carpentry_01_16") un moveable sin traduccion
	-- conocida, NO un ScriptItem real - preguntarle a ScriptManager
	-- (typeDisplayName completo) va a fallar siempre e imprime ese log
	-- vanilla de forma incondicional. Usar el humanizado sin tocar
	-- ScriptManager; typeDisplayName completo se reserva para fullTypes sin
	-- worldSprite, donde SI puede tratarse de un item real.
	if not displayName and worldSprite then
		displayName = GlobalStorageSiK.I18n.humanizeFallbackName(fullType)
	end
	cached = {
		fullType = fullType,
		displayName = displayName or GlobalStorageSiK.I18n.typeDisplayName(fullType),
		worldSprite = worldSprite,
		category = GlobalStorageSiK.Router.getItemCategory(item),
		subCategory = GlobalStorageSiK.Router.getItemSubCategory(item),
		gsSubKeys = gsKeysList,
		gsSubKeysStr = table.concat(gsKeysList, "|"),
		learnedRecipeNames = learnedRecipeNamesFromItem(item),
		numberOfPages = numberOfPagesFromItem(item),
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
	-- Clave de agrupacion: fullType a secas para el 99% de los items (sigue
	-- siendo lo correcto - "bolsas de patatas" deben sumarse en una sola
	-- fila), PERO fullType+mediaTitle para cintas VHS/radio, para que cada
	-- contenido distinto sea su propia fila. row.fullType se conserva SIEMPRE
	-- como el tipo real (retirada/instanceItem lo necesitan intacto); la
	-- clave compuesta solo decide como se agrupan las filas, nunca que se
	-- transfiere.
	local mediaIndex = GlobalStorageSiK.ItemSnapshot.recordedMediaIndexFromItem(item)
	local mediaTitle = recordedMediaTitleFromItem(item)
	local mediaCodes = mediaIndex ~= nil and recordedMediaCodes(item) or nil
	local worldSprite = readWorldSprite(item)
	local isMoveable = false
	if instanceof then
		local ok, value = pcall(function() return instanceof(item, "Moveable") end)
		isMoveable = ok and value == true
	elseif item.getScriptItem then
		local okScript, scriptItem = pcall(function() return item:getScriptItem() end)
		if okScript and scriptItem and scriptItem.getItemType then
			local okType, itemType = pcall(function() return scriptItem:getItemType() end)
			isMoveable = okType and string.lower(tostring(itemType or "")) == "base:moveable"
		end
	end
	local fluid = GlobalStorageSiK.FluidTaxonomy.inspect
		and GlobalStorageSiK.FluidTaxonomy.inspect(item) or nil
	local dynamicPath, dynamicSignature = fluid and fluid.path or nil, fluid and fluid.signature or nil
	if mediaIndex ~= nil then
		dynamicPath = GlobalStorageSiK.RecordedMedia.nativePath(mediaIndex, mediaCodes) or dynamicPath
	end
	local dynamicStateKey = fluid and fluid.stateKey or nil
	local dynamicPercent = fluid and fluid.fillPercent or nil
	local fluidAmount, fluidCapacity = fluid and fluid.amount or nil, fluid and fluid.capacity or nil
	local fluidState = fluid and fluid.detail or nil
	if dynamicPath and GlobalStorageSiK.DisplayCategoryPublisher then
		GlobalStorageSiK.DisplayCategoryPublisher.publishDynamicItem(item, dynamicPath)
	end
	local foodStateKey, food = foodState(item)
	if not dynamicStateKey then dynamicStateKey = foodStateKey end
	local conditionSignature, condition, conditionMax = conditionState(item)
	local literatureTitle = literatureTitleFromItem(item)
	local itemId = nil
	if item.getID then
		local okId, value = pcall(function() return item:getID() end)
		if okId and value ~= nil then itemId = value end
	end
	local detailKind = nil
	local variantKey = "fungible"
	if mediaIndex ~= nil or looksRecordedMedia(item, fullType) then
		detailKind = "recorded_media"
		variantKey = mediaIndex ~= nil and ("media:" .. tostring(mediaIndex))
			or ("media:unknown:" .. tostring(itemId or "missing"))
	elseif dynamicSignature then
		detailKind = "fluid"
		variantKey = "fluid:" .. dynamicSignature
		if fluidState and fluidState.mixture and fluidState.compositionExact == false then
			-- Sin enumeración completa de la mezcla nunca se promete fungibilidad:
			-- cada unidad permanece seleccionable por su itemId hasta que el
			-- runtime confirme la composición exacta.
			variantKey = variantKey .. ";unit=" .. tostring(itemId or "missing")
		end
	elseif foodStateKey then
		detailKind = "food"
		variantKey = foodStateKey
	elseif conditionSignature then
		detailKind = "condition"
		variantKey = conditionSignature
	elseif literatureTitle or learnedRecipeNamesFromItem(item) or numberOfPagesFromItem(item) then
		detailKind = "literature"
		variantKey = "literature:" .. tostring(literatureTitle or fullType)
	end
	-- El mismo fullType Moveable puede representar sprites y funciones físicas
	-- distintas. El sprite participa siempre en la identidad de la fila, sin
	-- borrar el estado dinámico adicional que pudiera tener la unidad.
	if worldSprite then
		local spriteKey = "sprite:" .. tostring(worldSprite)
		variantKey = variantKey == "fungible" and spriteKey or (spriteKey .. "|" .. variantKey)
		if isMoveable and not detailKind then detailKind = "moveable" end
	end
	local groupKey = fullType
	if variantKey ~= "fungible" then groupKey = groupKey .. "\31variant:" .. variantKey end
	local row = byType[groupKey]
	if not row then
		local metadata = metadataForItem(item, fullType)
		local instanceDisplayName = GlobalStorageSiK.I18n.nameFromItemInstance(item, fullType)
		row = {
			rowKey = groupKey,
			fullType = fullType,
			-- mediaTitle (getDisplayName() real de ESTA cinta, ej. "Carpentry
			-- for Beginners") sustituye al nombre generico por fullType ("VHS
			-- Tape") cuando existe - es mas especifico y es exactamente lo que
			-- ya usa vanilla para distinguir cintas, sin inventar redaccion
			-- propia.
			displayName = mediaTitle or (detailKind and instanceDisplayName) or metadata.displayName,
			worldSprite = metadata.worldSprite,
			category = metadata.category,
			subCategory = metadata.subCategory,
			gsSubKeys = metadata.gsSubKeys,
			gsSubKeysStr = metadata.gsSubKeysStr,
			learnedRecipeNames = metadata.learnedRecipeNames,
			numberOfPages = metadata.numberOfPages,
			literatureTitle = literatureTitle,
			mediaIndex = mediaIndex,
			mediaTitle = mediaTitle,
			mediaCodes = mediaCodes,
			dynamicSignature = dynamicSignature,
			dynamicStateKey = dynamicStateKey,
			dynamicPercent = dynamicPercent,
			fluidState = fluidState,
			shapeFamily = fluidState and fluidState.shapeFamily or nil,
			productFamilyKey = fluidState and fluidState.productFamilyKey or nil,
			shapeKey = fluidState and fluidState.shapeKey or nil,
			foodState = food,
			conditionSignature = conditionSignature,
			condition = condition,
			conditionMax = conditionMax,
			detailKind = detailKind,
			variantKey = variantKey,
			itemIds = {},
			totalWeight = 0,
			totalFluidAmount = 0,
			totalFluidCapacity = 0,
			count = 0,
		}
		-- La ruta del contenido líquido es por instancia y no puede recuperarse
		-- después desde el ScriptItem estático. Se publica ya resuelta dentro de
		-- la fila autoritativa para que UI y enrutado describan la misma variante.
		if (dynamicPath or worldSprite) and GlobalStorageSiK.CategoryResolution then
			local resolved = GlobalStorageSiK.CategoryResolution.resolve(fullType, nil, item, dynamicPath)
			row.nativePath = resolved.nativePath
			row.nativeStatus = resolved.nativeStatus
			row.vanillaKey = resolved.vanillaKey
			row.effective = resolved.effective
			row.categoryEffective = resolved.effective
			row.routingIdentity = resolved.routingIdentity
			row.categorySource = resolved.categorySource
		end
		byType[groupKey] = row
	end
	-- InventoryItem:getCount() NO es el número de instancias transferibles. En
	-- objetos como Base.Nails puede devolver el multiplicador definido por el
	-- script o por el contexto de receta (3/5), aunque este itemId siga siendo
	-- una sola entrada física. Usarlo aquí inflaba 84 clavos hasta 420 y hacía
	-- que la retirada eliminase 84 IDs mientras confirmaba 420 unidades.
	row.count = row.count + 1
	local weight = actualWeight(item)
	if weight then row.totalWeight = (row.totalWeight or 0) + weight end
	if type(fluidAmount) == "number" then row.totalFluidAmount = (row.totalFluidAmount or 0) + fluidAmount end
	if type(fluidCapacity) == "number" then row.totalFluidCapacity = (row.totalFluidCapacity or 0) + fluidCapacity end
	if itemId ~= nil then
		row.itemIds[#row.itemIds + 1] = itemId
		-- No persistir una tabla vacia por cada unidad fungible. El mapa por ID
		-- solo existe cuando una futura fila hija necesita estado de instancia.
		if mediaIndex ~= nil or mediaTitle ~= nil or dynamicSignature ~= nil or foodStateKey ~= nil
			or conditionSignature ~= nil or worldSprite ~= nil then
			row.unitDetails = row.unitDetails or {}
			row.unitDetails[itemId] = {
				dynamicPercent = dynamicPercent,
				fluidState = fluidState,
				foodState = food,
				condition = condition,
				conditionMax = conditionMax,
				mediaIndex = mediaIndex,
				mediaTitle = mediaTitle,
				mediaCodes = mediaCodes,
			}
		end
	end
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
	for groupKey, row in pairs(source or {}) do
		local existing = target[groupKey]
		if not existing then
			local itemIds, unitDetails = {}, nil
			for i = 1, #(row.itemIds or {}) do itemIds[i] = row.itemIds[i] end
			for itemId, detail in pairs(row.unitDetails or {}) do
				unitDetails = unitDetails or {}
				unitDetails[itemId] = detail
			end
			target[groupKey] = {
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
				shapeFamily = row.shapeFamily,
				productFamilyKey = row.productFamilyKey,
				shapeKey = row.shapeKey,
				foodState = row.foodState,
				conditionSignature = row.conditionSignature,
				condition = row.condition,
				conditionMax = row.conditionMax,
				detailKind = row.detailKind,
				variantKey = row.variantKey,
				itemIds = itemIds,
				unitDetails = unitDetails,
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
			}
		else
			existing.count = (existing.count or 0) + (row.count or 0)
			existing.itemIds = existing.itemIds or {}
			for i = 1, #(row.itemIds or {}) do existing.itemIds[#existing.itemIds + 1] = row.itemIds[i] end
			for itemId, detail in pairs(row.unitDetails or {}) do
				existing.unitDetails = existing.unitDetails or {}
				existing.unitDetails[itemId] = detail
			end
			existing.totalWeight = (existing.totalWeight or 0) + (row.totalWeight or 0)
			existing.totalFluidAmount = (existing.totalFluidAmount or 0) + (row.totalFluidAmount or 0)
			existing.totalFluidCapacity = (existing.totalFluidCapacity or 0) + (row.totalFluidCapacity or 0)
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

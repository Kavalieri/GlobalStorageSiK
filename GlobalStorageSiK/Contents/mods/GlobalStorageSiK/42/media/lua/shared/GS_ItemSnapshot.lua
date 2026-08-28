--[[
	GlobalStorageSiK - Instantánea de ítems en contenedor (MP / servidor)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Cachea inventario al escanear para cuando el chunk no está cargado en servidor.
]]

require "GS_Router"
require "GS_I18n"

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
--- Solucion: NO parsear RecMedia aqui (esa tabla exige pasar el indice como
--- "short" al lado Java, marshalling que Kahlua rompe siempre a Double - ver
--- el rodeo ya documentado en GS_ItemNetworkTooltip.getVHSTrainingLines,
--- mismo motivo por el que el mod retirado "Show VHS skills in tooltip" tenia
--- el mismo problema). En su lugar, exactamente igual que literatureTitle
--- (mismo motivo: valor por-instancia, NO cacheable por fullType): vanilla ya
--- resuelve un getDisplayName() distinto por cada entrada de RecMedia (asi es
--- como el propio GS_ItemNetworkTooltip correlaciona indice->habilidad, vía
--- nombre) - leerlo aqui basta como clave de agrupacion Y como nombre a
--- mostrar, sin tocar RecMedia en absoluto ni depender de su marshalling.
--- Publica (no solo local) a proposito: GS_Transfer.lua (filtrar que cinta
--- fisica retirar) y GS_ItemNetworkTooltip.lua (contar en red solo cintas
--- con este mismo contenido) reutilizan EXACTAMENTE esta misma lectura, en
--- vez de cada uno duplicar su propia version del mismo pcall.
---@param item InventoryItem|nil
---@return string|nil
function GlobalStorageSiK.ItemSnapshot.recordedMediaTitleFromItem(item)
	if not item or not item.getRecordedMediaIndex then return nil end
	local okIdx, idx = pcall(function() return item:getRecordedMediaIndex() end)
	if not okIdx or not idx or idx < 0 then return nil end
	local okName, name = pcall(function() return item:getDisplayName() end)
	if not okName or not name or name == "" then return nil end
	return name
end
local recordedMediaTitleFromItem = GlobalStorageSiK.ItemSnapshot.recordedMediaTitleFromItem

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
	local mediaTitle = recordedMediaTitleFromItem(item)
	local groupKey = mediaTitle and (fullType .. "\31media:" .. mediaTitle) or fullType
	local row = byType[groupKey]
	if not row then
		local metadata = metadataForItem(item, fullType)
		row = {
			fullType = fullType,
			-- mediaTitle (getDisplayName() real de ESTA cinta, ej. "Carpentry
			-- for Beginners") sustituye al nombre generico por fullType ("VHS
			-- Tape") cuando existe - es mas especifico y es exactamente lo que
			-- ya usa vanilla para distinguir cintas, sin inventar redaccion
			-- propia.
			displayName = mediaTitle or metadata.displayName,
			worldSprite = metadata.worldSprite,
			category = metadata.category,
			subCategory = metadata.subCategory,
			gsSubKeys = metadata.gsSubKeys,
			gsSubKeysStr = metadata.gsSubKeysStr,
			learnedRecipeNames = metadata.learnedRecipeNames,
			numberOfPages = metadata.numberOfPages,
			literatureTitle = literatureTitleFromItem(item),
			mediaTitle = mediaTitle,
			count = 0,
		}
		byType[groupKey] = row
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
	for groupKey, row in pairs(source or {}) do
		local existing = target[groupKey]
		if not existing then
			target[groupKey] = {
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
				mediaTitle = row.mediaTitle,
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

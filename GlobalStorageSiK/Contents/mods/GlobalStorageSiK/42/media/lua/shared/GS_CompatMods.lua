--[[
	GlobalStorageSiK - Compatibilidad con mods de terceros (opcional, solo lectura)
	No crea dependencias duras: si el mod de terceros no esta cargado, todo
	esto es un no-op seguro.

	- Extended Categories (CAExtendedCategories): no requiere ninguna accion.
	  GS_Subcategories.lua ya SOLO LEE getDisplayCategory() del item, nunca la
	  fija, asi que si Extended Categories esta activo y reescribe esa
	  categoria, nuestras subcategorias se recalculan automaticamente sobre
	  el valor que el haya puesto. hasExtendedCategories() se deja aqui como
	  punto de deteccion reutilizable (p.ej. para diagnostico/debug).

	- Organized Categories: Core (organizedCategories_core, Workshop 3370707195):
	  igual que Extended Categories, no una accion. Reescribe DisplayCategory via
	  su propia libreria "Item Tweaker Core" (TweakItem, en OnGameBoot) con
	  jerarquia PROPIA rica (p.ej. Food: foodPerishable, foodNonPerishable,
	  foodNonPerishable_condiment/spice/candy/canned/ingredient...) - mas
	  detallada que nuestra propia base (solo Perishable/NonPerishable), asi
	  que no aporta nada competir: GS_CategoryRewrite.lua debe DEJAR DE escribir
	  por completo cuando este mod esta activo (2026-08-21, pedido explicito:
	  "cualquier mod de categorias debe pasar por encima de nuestras
	  categorias"). GS_ItemTaxonomy.isDisplayCategoryKey() ya reconoce sus
	  categorias solas via IGUI_ItemCat_<codigo> (mismo mecanismo que EC), asi
	  que el filtro del Almacen las muestra sin codigo extra. Deteccion via
	  getActivatedMods() (no hay tabla global propia fiable: TweakItem/
	  ItemTweaker son de una libreria compartida que otros mods tambien pueden
	  embeber, detectar solo esa presencia daria falsos positivos).

	- Better Sorting (BetterSortCC, Workshop 2313387159): a diferencia de
	  Extended Categories, NO tiene jerarquia de 3 niveles ni API publica -
	  solo reescribe getDisplayCategory() a ~79 codigos propios y planos
	  (FoodA/FoodB/FoodN/FoodP, WepMAxe/WepFire, ClothAcc/ClothJew,
	  CraftBlack/CraftG/CraftMas/CraftTailor/CraftCarv, MedI/MedM/MedT,
	  SurFarm...) en Events.OnGameBoot, el MISMO evento que usa
	  GS_CategoryRewrite.lua. Por eso GS_Subcategories.lua normaliza esos
	  codigos de vuelta a su raiz vanilla (tabla BETTER_SORTING_CANON, local a
	  ese fichero por el mismo motivo que extendedCategoriesActive() no pasa
	  por aqui: carga muy temprana) ANTES de comparar, en vez de desactivar su
	  propio motor de subcategorias como con EC - Better Sorting no aporta ese
	  detalle, asi que apagarnos seria una perdida neta. hasBetterSorting() se
	  deja aqui como punto de deteccion reutilizable (diagnostico/debug y para
	  que GS_CategoryRewrite.lua evite competir por el mismo campo/evento).

	- Customizable Containers (CustomizableBackpacks): expone su registro de
	  etiquetas de contenedor en la tabla global CCLabelRegistry. Leemos su
	  API publica (getWorldObjectKey/getFactionName) y su ModData conocido
	  (CCContainerPersonalLabels en el jugador, CCContainerFactionLabels
	  global) para poder SUGERIR el texto de su etiqueta como nota de un
	  contenedor nuestro. Nunca escribimos en su moddata.
]]

-- BUG REAL reportado por Sistemas (2026-08-26): "GS_CompatMods.lua > recursive
-- require(): .../GS_Network.lua" - este fichero tenia un `require "GS_Network"`
-- a nivel de modulo que creaba un ciclo (GS_Network, en su propia cadena de
-- requires, termina volviendo a requerir este fichero), dejando a Lua con la
-- posibilidad real de entregar un modulo a medio inicializar segun el orden
-- de carga - no llegaba a impedir el arranque, pero no es ruido inofensivo.
-- Quitado sin sustituir por un require diferido: las 2 unicas llamadas a
-- `GlobalStorageSiK.Network.findWorldObject` de este fichero viven DENTRO de
-- funciones (`getContainerLabelText`/`pushContainerLabelText`), nunca se
-- ejecutan durante la carga del fichero - para cuando el juego real las llame
-- (tras un clic o refresco de UI), todos los ficheros compartidos ya se
-- cargaron, `GlobalStorageSiK.Network` existe siempre. El require solo
-- garantizaba orden de carga que aqui no hacia falta.

GlobalStorageSiK.CompatMods = {}

local function safeGet(fn)
	local ok, v = pcall(fn)
	return ok and v or nil
end

--- CAExtendedCategories fija CAEC_Global = CAEC_Global or {} al cargar su shared file.
---@return boolean
function GlobalStorageSiK.CompatMods.hasExtendedCategories()
	return rawget(_G, "CAEC_Global") ~= nil
end

--- CustomizableBackpacks fija CCLabelRegistry = CCLabelRegistry or {} al cargar su shared file.
---@return boolean
function GlobalStorageSiK.CompatMods.hasCustomizableContainers()
	return rawget(_G, "CCLabelRegistry") ~= nil
end

--- Better Sorting fija BScats = BScats or {} al cargar su shared file BaseCategories.lua.
---@return boolean
function GlobalStorageSiK.CompatMods.hasBetterSorting()
	return rawget(_G, "BScats") ~= nil
end

--- Organized Categories: Core, Workshop 3370707195, mod id "organizedCategories_core".
--- Via getActivatedMods() (no tabla global propia fiable, ver comentario de
--- cabecera): funciona en cualquier proceso (cliente/servidor/SP) igual que
--- el resto de detecciones de este fichero. UNICA fuente de esta deteccion en
--- todo el mod - GS_Subcategories.lua y GS_ItemTaxonomy.lua la llaman desde
--- aqui, nunca reimplementan su propia copia (evita el mismo mod ID como
--- literal repetido en varios ficheros que puedan desincronizarse). Cacheado
--- tras la primera llamada: la lista de mods activos no cambia durante la
--- sesion, y se consulta por item (potencialmente miles de veces por
--- refresco del Almacen) - repetir :contains() cada vez seria coste puro.
---@return boolean
local _hasOrganizedCategoriesCoreCache = nil
function GlobalStorageSiK.CompatMods.hasOrganizedCategoriesCore()
	if _hasOrganizedCategoriesCoreCache ~= nil then
		return _hasOrganizedCategoriesCoreCache
	end
	_hasOrganizedCategoriesCoreCache = getActivatedMods ~= nil
		and safeGet(function() return getActivatedMods():contains("organizedCategories_core") end) == true
	return _hasOrganizedCategoriesCoreCache
end

--- Busca la etiqueta (personal o de faccion) que Customizable Containers tenga puesta
--- sobre el objeto del mundo de un contenedor de nuestra red, sin tocar su moddata.
---@param entry table  -- contenedor de red GS: necesita x,y,z,id
---@param player IsoPlayer
---@return string|nil
function GlobalStorageSiK.CompatMods.getContainerLabelText(entry, player)
	if not GlobalStorageSiK.CompatMods.hasCustomizableContainers() then return nil end
	if not entry or not player then return nil end

	local worldObject = safeGet(function() return GlobalStorageSiK.Network.findWorldObject(entry) end)
	if not worldObject then return nil end

	local registry = _G.CCLabelRegistry
	local key = safeGet(function() return registry.getWorldObjectKey(worldObject) end)
	if not key then return nil end

	local personal = safeGet(function() return player:getModData()["CCContainerPersonalLabels"] end)
	local personalEntry = personal and personal[key]
	if type(personalEntry) == "table" and type(personalEntry.tagText) == "string" and personalEntry.tagText ~= "" then
		return personalEntry.tagText
	end

	local factionName = safeGet(function() return registry.getFactionName(player) end)
	if factionName then
		local store = safeGet(function() return ModData.getOrCreate(registry.FACTION_LABELS_KEY) end)
		local bucket = store and store.tags and store.tags[factionName]
		local factionEntry = bucket and bucket[key]
		if type(factionEntry) == "table" and type(factionEntry.tagText) == "string" and factionEntry.tagText ~= "" then
			return factionEntry.tagText
		end
	end

	return nil
end

--- Si Customizable Containers ya tiene una etiqueta PERSONAL puesta sobre este
--- contenedor, actualiza su texto para que coincida con nuestra nota.
--- Deliberadamente NO tocamos su campo "appearance" (estilo/color): esa parte
--- la normaliza una funcion privada de su mod (LabelStyle, local a su cliente,
--- no accesible desde fuera) y no podemos reproducirla con garantias. Por la
--- misma razon, si CC todavia NO tiene etiqueta para este contenedor, no
--- creamos una nueva de cero: solo sincronizamos texto sobre una etiqueta que
--- el jugador ya creo alguna vez desde la UI de CC. Es la unica direccion de
--- escritura segura sin adivinar el formato interno del mod ajeno.
---@param entry table  -- contenedor de red GS: necesita x,y,z,id
---@param player IsoPlayer
---@param tagText string
---@return boolean actualizado
function GlobalStorageSiK.CompatMods.pushContainerLabelText(entry, player, tagText)
	if not GlobalStorageSiK.CompatMods.hasCustomizableContainers() then return false end
	if not entry or not player then return false end
	tagText = type(tagText) == "string" and tagText or ""
	if tagText == "" then return false end
	if #tagText > 28 then tagText = tagText:sub(1, 28) end

	local worldObject = safeGet(function() return GlobalStorageSiK.Network.findWorldObject(entry) end)
	if not worldObject then return false end

	local registry = _G.CCLabelRegistry
	local key = safeGet(function() return registry.getWorldObjectKey(worldObject) end)
	if not key then return false end

	local modData = safeGet(function() return player:getModData() end)
	local bucket = modData and modData["CCContainerPersonalLabels"]
	local existing = type(bucket) == "table" and bucket[key] or nil
	if type(existing) ~= "table" or type(existing.tagText) ~= "string" then
		return false
	end

	if existing.tagText == tagText then
		return true
	end

	existing.tagText = tagText
	bucket[key] = existing
	safeGet(function() player:transmitModData() end)
	return true
end

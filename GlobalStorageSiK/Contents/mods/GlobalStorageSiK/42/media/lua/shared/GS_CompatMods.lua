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

require "GS_Network"

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

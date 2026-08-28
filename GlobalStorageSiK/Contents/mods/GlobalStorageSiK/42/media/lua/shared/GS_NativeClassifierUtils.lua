--[[
	GlobalStorageSiK - Helpers compartidos por los clasificadores de bloque
	Autor: SiK
	Fecha: 2026-08-27

	Funciones pequeñas y seguras (siempre pcall, siempre sobre el SCRIPT item,
	nunca sobre una instancia viva moddeada) reutilizadas por cada bloque de
	clasificacion (Combate, Herramientas, Materiales...). Ningun bloque debe
	llamar a un getter del motor directamente sin pasar por aqui, para no
	repetir la misma proteccion pcall en cada fichero.
]]

GlobalStorageSiK.NativeClassifierUtils = GlobalStorageSiK.NativeClassifierUtils or {}

---@param fn function
---@return any|nil
local function safeCall(fn)
	local ok, v = pcall(fn)
	if ok then return v end
	return nil
end
GlobalStorageSiK.NativeClassifierUtils.safeCall = safeCall

--- Set de tags (zombie.scripting.objects.Item:getTags()) del script item, o
--- nil si el metodo no existe/falla. Mismo patron ya confirmado seguro en
--- GS_Subcategories.lua (getWeaponCategories) - un Set real con :contains().
---@param si table|nil script item
---@return table|nil
function GlobalStorageSiK.NativeClassifierUtils.getTags(si)
	if not si or not si.getTags then return nil end
	local tags = safeCall(function() return si:getTags() end)
	if not tags or not tags.contains then return nil end
	return tags
end

--- Comprueba una etiqueta concreta sobre el script item, con toda la
--- proteccion pcall ya resuelta - un bloque de clasificacion solo necesita
--- llamar hasTag(si, ItemTag.HAMMER).
---@param si table|nil
---@param tag any ItemTag.XXX
---@return boolean
function GlobalStorageSiK.NativeClassifierUtils.hasTag(si, tag)
	if not tag then return false end
	local tags = GlobalStorageSiK.NativeClassifierUtils.getTags(si)
	if not tags then return false end
	return safeCall(function() return tags:contains(tag) end) == true
end

--- true si el script item tiene AL MENOS UNA de la lista de tags.
---@param si table|nil
---@param tagList table lista de ItemTag.XXX
---@return boolean
function GlobalStorageSiK.NativeClassifierUtils.hasAnyTag(si, tagList)
	local tags = GlobalStorageSiK.NativeClassifierUtils.getTags(si)
	if not tags then return false end
	for i = 1, #tagList do
		if safeCall(function() return tags:contains(tagList[i]) end) == true then
			return true
		end
	end
	return false
end

--- Set de categorias de arma (WeaponCategory) del script item, o nil. Mismo
--- patron ya confirmado en GS_Subcategories.lua.
---@param si table|nil
---@return table|nil
function GlobalStorageSiK.NativeClassifierUtils.getWeaponCategories(si)
	if not si or not si.getWeaponCategories then return nil end
	local cats = safeCall(function() return si:getWeaponCategories() end)
	if not cats or not cats.contains then return nil end
	return cats
end

-- Cache de tags resueltos por ResourceLocation (namespace:nombre) - algunos
-- tags reales (p.ej. "base:hasmetal") no tienen constante directa
-- ItemTag.XXX expuesta, solo se resuelven via ItemTag.get(ResourceLocation.of(...)),
-- mismo patron ya confirmado y en produccion en GS_Subcategories.lua/
-- GS_CraftUtils.lua (buildMetalSet/buildScrewdriverSet).
local _tagByLocation = {}

---@param namespace string p.ej. "base"
---@param name string p.ej. "hasmetal"
---@return any|nil ItemTag resuelto, o nil si no existe/fallo
function GlobalStorageSiK.NativeClassifierUtils.tagByLocation(namespace, name)
	local key = namespace .. ":" .. name
	local cached = _tagByLocation[key]
	if cached ~= nil then
		return cached or nil
	end
	local tag = (ItemTag and ResourceLocation) and safeCall(function()
		return ItemTag.get(ResourceLocation.of(key))
	end) or nil
	_tagByLocation[key] = tag or false
	return tag
end

--- Hueco de equipacion del script item (ItemBodyLocation), en minusculas, o
--- cadena vacia si no aplica - un objeto EQUIPABLE (ropa, protección,
--- accesorio) nunca deberia clasificar como material en bruto aunque su
--- nombre o tags coincidan por casualidad (p.ej. una prenda con tag
--- "hasmetal") - mismo patron ya usado en GS_Subcategories.lua
--- (bodyLocationLower).
---@param si table|nil
---@return string
function GlobalStorageSiK.NativeClassifierUtils.bodyLocationLower(si)
	if not si or not si.getBodyLocation then return "" end
	local loc = safeCall(function() return si:getBodyLocation() end)
	return loc and string.lower(tostring(loc)) or ""
end

--- Hueco de equipacion (ItemBodyLocation), case ORIGINAL preservado (para
--- tokenize() - "ShortSleeveShirt" necesita las mayusculas internas para
--- dividirse en {"short","sleeve","shirt"}, bodyLocationLower() ya lo
--- devuelve en minusculas y pierde esa frontera).
---@param si table|nil
---@return string
function GlobalStorageSiK.NativeClassifierUtils.bodyLocation(si)
	if not si or not si.getBodyLocation then return "" end
	local loc = safeCall(function() return si:getBodyLocation() end)
	return loc and tostring(loc) or ""
end

-- dev14 (probe controlado de sistemas, confirmado via javap sobre
-- projectzomboid.jar): `zombie.scripting.objects.Item.getItemType()` es un
-- getter OFICIAL y ya presente en el ScriptItem estatico (a diferencia de
-- `getFoodType()`, que solo existe sobre la instancia) - resuelve sin
-- ambiguedad casos como Base.PizzaRecipe (base:food, es comida real pese al
-- sufijo "Recipe") o Base.RecipeClipping (base:literature, es literatura
-- real). tostring() devuelve el id con namespace ("base:food"), igual que
-- confirmaron los scripts generados del juego.
---@param si table|nil
---@return string minusculas, cadena vacia si no se pudo resolver
function GlobalStorageSiK.NativeClassifierUtils.itemTypeLower(si)
	if not si or not si.getItemType then return "" end
	local it = safeCall(function() return si:getItemType() end)
	return it and string.lower(tostring(it)) or ""
end

-- dev14 (probe controlado de sistemas, confirmado via javap): ScriptItem
-- hereda de GameEntityScript, que expone `containsComponent(ComponentType)`
-- - señal ESTATICA real de "tiene un FluidContainer" (Base.Bucket/Canteen
-- confirmados con el componente; Base.CookieJar/JarLid/BottleOpener*
-- confirmados SIN el). `ComponentType` puede no estar expuesto a Kahlua
-- como global (sin confirmar todavia) - degrada con seguridad a `nil` si
-- no lo esta, nunca lanza.
---@param si table|nil
---@return boolean|nil nil si no se pudo determinar (API no disponible), true/false si se pudo
function GlobalStorageSiK.NativeClassifierUtils.hasFluidContainerComponent(si)
	if not si or not si.containsComponent or not ComponentType or not ComponentType.FluidContainer then
		return nil
	end
	return safeCall(function() return si:containsComponent(ComponentType.FluidContainer) end)
end

--- fullType en minusculas, vacio si no se pudo resolver.
---@param si table|nil
---@return string
function GlobalStorageSiK.NativeClassifierUtils.fullTypeLower(si)
	if not si or not si.getFullName then return "" end
	local ft = safeCall(function() return si:getFullName() end)
	return ft and string.lower(tostring(ft)) or ""
end

-- BUG REAL cerrado (2026-08-27, hallazgo del equipo de sistemas sobre dev5):
-- "el modulo tambien forma parte del fullType" - Materiales/Medicina/Hogar-
-- ocio buscaban subcadenas sobre el fullType COMPLETO (namespace incluido),
-- asi que practicamente cualquier tipo del modulo "AuthenticZClothing.*"
-- terminaba en Textil solo por contener la palabra "clothing" en el NOMBRE
-- DEL MODULO, sin relacion alguna con el objeto real (AuthenticZClothing.PipeBomb,
-- .FlameTrapRemote, .WaterBottleFull...). Cualquier heuristica de nombre
-- debe operar SOLO sobre la parte tras el primer punto (el tipo real), nunca
-- sobre el fullType completo.
---@param si table|nil
---@return string tipo real (sin namespace de modulo), case original preservado
function GlobalStorageSiK.NativeClassifierUtils.typeName(si)
	if not si or not si.getFullName then return "" end
	local ft = safeCall(function() return si:getFullName() end)
	ft = ft and tostring(ft) or ""
	if ft == "" then return "" end
	local typeName = ft:match("^[^.]+%.(.+)$")
	return typeName or ft
end

-- BUG REAL cerrado (2026-08-27, hallazgo del equipo de sistemas sobre dev5):
-- las heuristicas de nombre usaban "find(needle, 1, true)" (subcadena sin
-- limites) sobre el nombre completo - "stick" dentro de "Lipstick"/
-- "Nightstick"/"Drumstick", "log" dentro de "Catalog"/"Cologne", "rag"
-- dentro de "Foraging"/"Fragment" eran todos falsos positivos reales,
-- confirmados en produccion. Tokenizar por limite CamelCase/guion bajo
-- convierte "LogStacks2" en {"log","stacks"} (coincidencia real) pero deja
-- "Catalog"/"Lipstick" como un unico token ("catalog"/"lipstick", sin
-- fragmento interno que colisione) - la comparacion pasa a ser por TOKEN
-- COMPLETO, nunca por subcadena.
---@param name string case original preservado (usar typeName(si), NUNCA fullTypeLower)
---@return string[] tokens en minusculas
function GlobalStorageSiK.NativeClassifierUtils.tokenize(name)
	if not name or name == "" then return {} end
	local spaced = name:gsub("_", " ")
	spaced = spaced:gsub("(%l)(%u)", "%1 %2")
	spaced = spaced:gsub("(%u)(%u%l)", "%1 %2")
	local tokens = {}
	for word in spaced:gmatch("%a+") do
		tokens[#tokens + 1] = word:lower()
	end
	return tokens
end

--- true si algun token de la lista esta en el set (tabla word->true).
---@param tokens string[]
---@param wordSet table<string, boolean>
---@return boolean
function GlobalStorageSiK.NativeClassifierUtils.hasAnyToken(tokens, wordSet)
	for i = 1, #tokens do
		if wordSet[tokens[i]] then return true end
	end
	return false
end

--- Construye una evidencia minima valida para evidence.primary.
---@param source string
---@param confidence number
---@return table
function GlobalStorageSiK.NativeClassifierUtils.evidence(source, confidence)
	return { primary = { source = source, scope = "script", confidence = confidence }, supporting = {}, conflicting = {} }
end

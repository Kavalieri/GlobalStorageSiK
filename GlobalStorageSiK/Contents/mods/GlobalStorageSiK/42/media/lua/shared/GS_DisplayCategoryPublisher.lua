--[[
	GlobalStorageSiK - Publicación estable de la taxonomía en DisplayCategory
	Core 1.4.3-dev32.3

	La ruta nativa sigue siendo la verdad completa de GS. Este módulo publica
	una clave plana, estable y sin traducir en el ScriptItem para que el
	inventario vanilla y los lectores externos reciban la misma categoría. No
	modifica InventoryItem vivos salvo que exista una variante realmente
	dinámica declarada. Los fluidos publican sobre la instancia su ruta viva,
	incluidos vacío y mezcla; nunca reescriben el ScriptItem global por contenido.
]]

require "GS_CatalogManager"
require "GS_I18n"
require "GS_NativeProduct"
require "GS_FluidTaxonomy"

GlobalStorageSiK.DisplayCategoryPublisher = GlobalStorageSiK.DisplayCategoryPublisher or {}

local Publisher = GlobalStorageSiK.DisplayCategoryPublisher
local PREFIX = "GSSiK_"
local state = {
	status = "pending",
	writers = {},
	published = 0,
	unchanged = 0,
	preservedAmmo = 0,
	unsupported = 0,
}

-- Identidades observables, no heurísticas sobre nombres de categorías. Los
-- globales cubren los dos proveedores con API conocida; los IDs normalizados
-- cubren instalaciones que no llegan a crear su global hasta más tarde.
local KNOWN_WRITERS = {
	{ name = "Extended Categories", globals = { "CAEC_Global" }, ids = { "caextendedcategories", "extendedcategories" } },
	{ name = "Better Sorting", globals = { "BScats" }, ids = { "bettersorting" } },
	{ name = "Organized Categories", globals = { "OrganizedCategories", "OC" }, ids = { "organizedcategories" } },
}

local function safeCall(fn)
	local ok, value = pcall(fn)
	return ok and value or nil
end

local function normalizedModId(value)
	if type(value) ~= "string" then return nil end
	return value:lower():gsub("[^a-z0-9]", "")
end

---@param path table|string|nil
---@return string|nil
function Publisher.publicKey(path)
	path = GlobalStorageSiK.NativeProduct.decodePath(path)
	if not path then return nil end
	local key = PREFIX .. path.l1
	if path.l2 then key = key .. "_" .. path.l2 end
	if path.l3 then key = key .. "_" .. path.l3 end
	return key
end

---@param value string|nil
---@return boolean
function Publisher.isPublishedKey(value)
	return type(value) == "string" and value:match("^" .. PREFIX .. "[a-z0-9_]+$") ~= nil
end

--- Publica exclusivamente una variante dinámica declarada sobre el item vivo.
--- El caller proporciona la ruta ya resuelta (incluidos vacío y mezcla)
--- para no repetir getters del fluido durante el pintado de inventario.
---@param item InventoryItem|nil
---@param path table|string|nil
---@return boolean
function Publisher.publishDynamicItem(item, path)
	path = GlobalStorageSiK.NativeProduct.decodePath(path)
	if not item or not path or not item.setDisplayCategory then return false end
	if state.status == "conflict" then return false end
	local key = Publisher.publicKey(path)
	if not key then return false end
	local current = item.getDisplayCategory and safeCall(function() return item:getDisplayCategory() end) or nil
	if current == key then return false end
	return pcall(function() item:setDisplayCategory(key) end)
end

---@return table estado de solo lectura para diagnostico/soporte
function Publisher.getStatus()
	return {
		status = state.status,
		writers = state.writers,
		published = state.published,
		unchanged = state.unchanged,
		preservedAmmo = state.preservedAmmo,
		unsupported = state.unsupported,
	}
end

local function activeModIds()
	local ids = {}
	if not getActivatedMods then return ids end
	local mods = safeCall(getActivatedMods)
	if not mods or not mods.size or not mods.get then return ids end
	for i = 0, mods:size() - 1 do
		local id = normalizedModId(safeCall(function() return mods:get(i) end))
		if id then ids[id] = true end
	end
	return ids
end

local function detectWriters()
	local active = activeModIds()
	local found = {}
	for i = 1, #KNOWN_WRITERS do
		local writer = KNOWN_WRITERS[i]
		local detected = false
		for j = 1, #writer.globals do
			if _G and _G[writer.globals[j]] ~= nil then
				detected = true
				break
			end
		end
		if not detected then
			for j = 1, #writer.ids do
				if active[writer.ids[j]] then
					detected = true
					break
				end
			end
		end
		if detected then found[#found + 1] = writer.name end
	end
	return found
end

local function originalDisplayCategory(scriptItem)
	if not scriptItem or not scriptItem.getDisplayCategory then return nil end
	return safeCall(function() return scriptItem:getDisplayCategory() end)
end

local function isAmmoCompatibilityException(path, current)
	return current == "Ammo" and path and path.l1 == "combat"
		and path.l2 == "firearm" and path.l3 == "ammunition"
end

local function publishScriptItem(scriptItem)
	if not scriptItem or not scriptItem.getFullName or not scriptItem.DoParam then
		state.unsupported = state.unsupported + 1
		return false
	end
	local fullType = safeCall(function() return scriptItem:getFullName() end)
	if type(fullType) ~= "string" or fullType == "" then
		state.unsupported = state.unsupported + 1
		return false
	end
	local result = GlobalStorageSiK.NativeClassifier.classify(fullType)
	local path = result and GlobalStorageSiK.NativeProduct.normalizePath(result.primaryPath) or nil
	if not result or result.pending or result.classifierError
		or not path or path.l1 == "other" then return false end
	local key = Publisher.publicKey(path)
	if not key then return false end
	local current = originalDisplayCategory(scriptItem)
	if isAmmoCompatibilityException(path, current) then
		state.preservedAmmo = state.preservedAmmo + 1
		return false
	end
	if current == key then
		state.unchanged = state.unchanged + 1
		return false
	end
	local ok = pcall(function() scriptItem:DoParam("DisplayCategory", key) end)
	if ok then
		state.published = state.published + 1
		return true
	end
	state.unsupported = state.unsupported + 1
	return false
end

local function publishAll()
	state.writers = detectWriters()
	if #state.writers > 0 then
		state.status = "conflict"
		if GlobalStorageSiK.Log then
			GlobalStorageSiK.Log.warn("DisplayCategory", "publication skipped: external writer active "
				.. table.concat(state.writers, ", "))
		end
		return
	end
	local manager = ScriptManager and ScriptManager.instance or nil
	local allItems = manager and safeCall(function() return manager:getAllItems() end) or nil
	if not allItems or not allItems.size or not allItems.get then
		state.status = "unavailable"
		if GlobalStorageSiK.Log then
			GlobalStorageSiK.Log.warn("DisplayCategory", "publication unavailable: ScriptManager item list missing")
		end
		return
	end
	state.published = 0
	state.unchanged = 0
	state.preservedAmmo = 0
	state.unsupported = 0
	for i = 0, allItems:size() - 1 do
		publishScriptItem(safeCall(function() return allItems:get(i) end))
	end
	state.status = "published"
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.info("DisplayCategory", "published=" .. tostring(state.published)
			.. " unchanged=" .. tostring(state.unchanged)
			.. " ammoPreserved=" .. tostring(state.preservedAmmo)
			.. " unsupported=" .. tostring(state.unsupported))
	end
	-- Los consumidores memorizan ScriptItem por epoch. Tras DoParam se abre
	-- uno nuevo para que ninguno siga leyendo la categoría anterior.
	if state.published > 0 then
		GlobalStorageSiK.CatalogManager.forceNewEpoch()
	end
end

-- CatalogManager registra su OnGameBoot al cargarse antes que este módulo;
-- por ello la clasificación y ScriptManager ya están disponibles aquí, tanto
-- en cliente como en dedicado y SP real.
Events.OnGameBoot.Add(publishAll)

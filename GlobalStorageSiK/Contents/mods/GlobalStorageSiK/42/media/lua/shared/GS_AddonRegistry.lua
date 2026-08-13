--[[

	GlobalStorageSiK - Registro de addons de red

	Autor: SiK

	Fecha: 2025-06-27

	Descripción: API para mods addon que extienden el terminal GS.

	Registro mínimo: id, modId, itemType, magazineType, recipeNames, moduleRecipeName.

]]



require "GS_Config"

require "GS_CraftUtils"



GlobalStorageSiK.AddonRegistry = GlobalStorageSiK.AddonRegistry or {}

GlobalStorageSiK.AddonRegistry._defs = GlobalStorageSiK.AddonRegistry._defs or {}

GlobalStorageSiK.AddonRegistry.DEFAULT_MODULE_SKILL = 5



--- Registra un addon disponible (llamado por cada mod addon al cargar shared).

---@param def table { id, modId, itemType, magazineType, recipeNames, moduleRecipeName, moduleSkillLevel, moduleIngredients, moduleCraftTime, iconPath, titleKey, descKey, workshopId, installDiskItem }
--- installDiskItem (opcional): fullType del disquete de instalacion propio
--- del addon (se conserva, no se consume - igual que GS_FloppyDisk del
--- terminal). Si un addon lo define, instalar el modulo exige tambien
--- tener ese disquete en el inventario, ademas del lector universal
--- GS_TerminalReader (siempre exigido, sea cual sea el addon) y de los
--- requisitos que ya existian (revista, item de modulo crafteado). Ningun
--- addon actual lo define todavia - es aditivo, no rompe los que no lo usan.

---@return boolean

function GlobalStorageSiK.AddonRegistry.register(def)

	if not def or not def.id or def.id == "" then

		return false

	end

	if not def.modId or def.modId == "" then

		return false

	end

	if not def.itemType or def.itemType == "" then

		return false

	end

	if not def.magazineType or def.magazineType == "" then

		return false

	end

	if not def.recipeNames or #def.recipeNames == 0 then

		return false

	end

	if not def.moduleRecipeName or def.moduleRecipeName == "" then

		return false

	end

	def.moduleSkillLevel = def.moduleSkillLevel or GlobalStorageSiK.AddonRegistry.DEFAULT_MODULE_SKILL

	GlobalStorageSiK.AddonRegistry._defs[def.id] = def

	return true

end



---@param addonId string

---@return table|nil

function GlobalStorageSiK.AddonRegistry.get(addonId)

	return GlobalStorageSiK.AddonRegistry._defs[addonId]

end



---@return table<string, table>

function GlobalStorageSiK.AddonRegistry.all()

	return GlobalStorageSiK.AddonRegistry._defs

end



--- Orden UI: Reader primero (periferico universal, hace falta antes de
--- instalar cualquier otro addon), luego TabletLink, Craft, resto alfabético.
local ADDON_UI_ORDER = {
	Reader = 1,
	TabletLink = 2,
	Craft = 3,
	Builder = 4,
	Cook = 5,
}

local function addonSortRank(def)
	if not def or not def.id then
		return 99
	end
	return ADDON_UI_ORDER[def.id] or 50
end

--- Lista ordenada para UI (todos los registrados).
---@return table[]
function GlobalStorageSiK.AddonRegistry.listSorted()
	local rows = {}
	for _, def in pairs(GlobalStorageSiK.AddonRegistry._defs) do
		rows[#rows + 1] = def
	end
	table.sort(rows, function(a, b)
		local ra = addonSortRank(a)
		local rb = addonSortRank(b)
		if ra ~= rb then
			return ra < rb
		end
		return (a.id or "") < (b.id or "")
	end)
	return rows
end



--- Solo addons cuyo mod está activo en la partida.

---@return table[]

function GlobalStorageSiK.AddonRegistry.listActive()

	local rows = {}

	for _, def in pairs(GlobalStorageSiK.AddonRegistry._defs) do

		if GlobalStorageSiK.AddonRegistry.isModActive(def.id) then

			rows[#rows + 1] = def

		end

	end

	table.sort(rows, function(a, b)
		local ra = addonSortRank(a)
		local rb = addonSortRank(b)
		if ra ~= rb then
			return ra < rb
		end
		return (a.id or "") < (b.id or "")
	end)

	return rows

end



--- Comprueba si el mod Workshop del addon está activo.

---@param addonId string

---@return boolean

function GlobalStorageSiK.AddonRegistry.isModActive(addonId)

	local def = GlobalStorageSiK.AddonRegistry.get(addonId)

	if not def or not def.modId or def.modId == "" then

		return false

	end

	if not getActivatedMods then

		return true

	end

	return getActivatedMods():contains(def.modId) == true

end



--- Conoce la receta del módulo instalable (revista leída como mínimo).

---@param player IsoPlayer|nil

---@param addonId string

---@return boolean

function GlobalStorageSiK.AddonRegistry.playerKnowsModuleRecipe(player, addonId)

	local def = GlobalStorageSiK.AddonRegistry.get(addonId)

	if not def or not player or not def.moduleRecipeName then

		return false

	end

	return GlobalStorageSiK.CraftUtils.knowsRecipeStrict(player, def.moduleRecipeName)

end



--- Revista leída: conoce todas las recetas del addon (siempre obligatorio).

---@param player IsoPlayer|nil

---@param addonId string

---@return boolean

--- BUG REAL encontrado (reportado: instalar Builder pedia "necesitas leer la
--- revista del addon" aunque el jugador ya la habia leido): antes exigia
--- conocer TODAS las recetas de def.recipeNames, incluida la de programar
--- el disco de instalacion - una revista APARTE (regla "una revista = una
--- receta de disco" de este mod), sin relacion con saber montar el modulo
--- fisico. Instalar el modulo en el terminal solo deberia exigir saber
--- fabricarlO (def.moduleRecipeName), no ademas saber programar discos -
--- son dos habilidades distintas que no tienen por que aprenderse juntas.
--- Mismo bug en los 3 addons (Craft/Builder/Tablet comparten este codigo);
--- solo tocaba a Builder primero porque el jugador aun no habia encontrado
--- esa segunda revista para ese addon en concreto.
function GlobalStorageSiK.AddonRegistry.playerKnowsMagazine(player, addonId)

	local def = GlobalStorageSiK.AddonRegistry.get(addonId)

	if not def or not player or not def.moduleRecipeName then

		return false

	end

	return GlobalStorageSiK.CraftUtils.knowsRecipeStrict(player, def.moduleRecipeName)

end



--- Comprueba el lector universal (SIEMPRE exigido, en inventario principal
--- - no vale dentro de una mochila, mismo criterio que instalar el
--- terminal en un PC - salvo que la disquetera ya esté instalada en red en
--- este terminal, ver GS_FloppyDriveNetwork) y el disquete propio del
--- addon si lo define (installDiskItem, se conserva, no hace falta que
--- este en el inventario principal). Punto unico compartido por
--- canInstallModule y Addons.install para no repetir esta logica en dos
--- sitios.
---@param player IsoPlayer|nil
---@param def table|nil
---@param networkId string|nil
---@param anchor table|nil
---@return boolean
---@return string|nil reason
function GlobalStorageSiK.AddonRegistry.hasRequiredInstallItems(player, def, networkId, anchor)
	if not player or not player.getInventory or not def then
		return false, "invalid"
	end
	local inv = player:getInventory()
	local readerType = GlobalStorageSiK.Config and GlobalStorageSiK.Config.ITEM_TERMINAL_READER
	local readerInInventory = readerType and (inv:getItemCount(readerType) or 0) >= 1
	-- Antes referenciaba GlobalStorageSiK.FloppyDriveNetwork.isInstalled
	-- directamente (unico caso especial cableado a un addon concreto en todo
	-- este fichero) - el Lector ahora es una entrada mas del registro (ver
	-- GS_ReaderAddon.lua), asi que se comprueba igual que cualquier otra:
	-- generico, sin conocer su nombre de antemano. Referencia "suave" (sin
	-- require "GS_Addons" aqui) para no crear el ciclo que ya evitaba el
	-- codigo anterior: GS_Addons requiere GS_AddonRegistry, nunca al reves -
	-- para cuando esta funcion se LLAMA de verdad (nunca en tiempo de carga
	-- de este fichero), GS_Addons ya esta cargado.
	local readerInNetwork = networkId ~= nil
		and GlobalStorageSiK.Addons
		and GlobalStorageSiK.Addons.isInstalled(networkId, anchor, "Reader")
	if not readerInInventory and not readerInNetwork then
		return false, "reader"
	end
	if def.installDiskItem and def.installDiskItem ~= "" then
		if (inv:getItemCountRecurse(def.installDiskItem) or 0) < 1 then
			return false, "disk"
		end
	end
	return true, nil
end

--- Lista de fullTypes validos como "el modulo instalable" de un addon. La
--- mayoria de addons solo tienen uno (def.itemType); un addon puede definir
--- ademas def.moduleItemTypes (varios tiers del mismo periferico - p.ej. la
--- Antena WiFi T1/T2/T3 del addon Tablet) y CUALQUIERA de ellos sirve para
--- instalar/contar como modulo en mano.
---@param def table
---@return string[]
function GlobalStorageSiK.AddonRegistry.moduleItemTypes(def)
	if def and def.moduleItemTypes and #def.moduleItemTypes > 0 then
		return def.moduleItemTypes
	end
	return { def and def.itemType }
end

--- Cuenta total del modulo instalable (cualquiera de sus tiers) en el
--- inventario del jugador.
---@param inv ItemContainer
---@param def table
---@return number
local function countModuleItems(inv, def)
	local types = GlobalStorageSiK.AddonRegistry.moduleItemTypes(def)
	local total = 0
	for i = 1, #types do
		if types[i] then
			total = total + (inv:getItemCountRecurse(types[i]) or 0)
		end
	end
	return total
end

--- Puede instalar el módulo en el terminal (mod activo + revista + ítem +
--- lector universal + disquete propio del addon si lo define).

---@param player IsoPlayer|nil

---@param addonId string

---@param networkId string|nil

---@param anchor table|nil

---@return boolean

---@return string|nil reason

function GlobalStorageSiK.AddonRegistry.canInstallModule(player, addonId, networkId, anchor)

	if not GlobalStorageSiK.AddonRegistry.isModActive(addonId) then

		return false, "mod_off"

	end

	if not GlobalStorageSiK.AddonRegistry.playerKnowsMagazine(player, addonId) then

		return false, "magazine"

	end

	local def = GlobalStorageSiK.AddonRegistry.get(addonId)

	if not def or not player or not player.getInventory then

		return false, "invalid"

	end

	local hasItems, itemsReason = GlobalStorageSiK.AddonRegistry.hasRequiredInstallItems(player, def, networkId, anchor)
	if not hasItems then
		return false, itemsReason
	end

	local inv = player:getInventory()

	if countModuleItems(inv, def) < 1 then

		return false, "module"

	end

	return true, nil

end



--- Indica si el jugador lleva el módulo instalable en el inventario.

---@param player IsoPlayer|nil

---@param addonId string

---@return boolean

function GlobalStorageSiK.AddonRegistry.playerHasModuleItem(player, addonId)

	local def = GlobalStorageSiK.AddonRegistry.get(addonId)

	if not def or not player or not player.getInventory then

		return false

	end

	local inv = player:getInventory()

	return countModuleItems(inv, def) >= 1

end



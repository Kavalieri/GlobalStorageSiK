--[[
	GlobalStorageSiK - GS-Router (auto-ordenado propio)
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Elige nodo destino por categoría y capacidad. Sin modData de Manage Containers.
	Inspiración: StrogareSimpleMP (3739374300) — lógica propia.
]]

require "GS_Sandbox"
require "GS_ItemTaxonomy"
require "GS_Subcategories"
require "GS_Log"
require "GS_NodeFilters"

GlobalStorageSiK.Router = {}

local CATEGORY_ALIASES = {
	Medical = "FirstAid",
	FirstAid = "Medical",
	Tools = "Tool",
	Tool = "Tools",
	Materials = "Material",
	Material = "Materials",

	-- Migracion (v1.2.76): estas subcategorias gs_* pasaron de ser una
	-- etiqueta interna nuestra a una DisplayCategory real (ver
	-- GS_CategoryRewrite.lua). Un contenedor configurado ANTES de esa version
	-- con la clave vieja debe seguir aceptando los mismos items ahora que
	-- reportan la clave nueva - de ahi el alias en ambos sentidos.
	gs_accessory_jewelry = "AccessoryJewelry", AccessoryJewelry = "gs_accessory_jewelry",
	gs_accessory_other = "AccessoryOther", AccessoryOther = "gs_accessory_other",
	gs_food_cold = "FoodPerishable", FoodPerishable = "gs_food_cold",
	gs_food_dry = "FoodNonPerishable", FoodNonPerishable = "gs_food_dry",
	gs_food_seed = "GardeningSeed", GardeningSeed = "gs_food_seed",
	gs_tool_farm = "GardeningTool", GardeningTool = "gs_tool_farm",
	gs_med_aid = "FirstAidAid", FirstAidAid = "gs_med_aid",
	gs_med_surgery = "FirstAidSurgery", FirstAidSurgery = "gs_med_surgery",
	gs_weapon_firearm = "Firearm", Firearm = "gs_weapon_firearm",
	gs_weapon_melee = "WeaponMelee", WeaponMelee = "gs_weapon_melee",
	gs_mat_metal = "MaterialMetalworking", MaterialMetalworking = "gs_mat_metal",
	gs_mat_leather = "MaterialLeather", MaterialLeather = "gs_mat_leather",
	gs_mat_wood = "MaterialWood", MaterialWood = "gs_mat_wood",
}

--- Obtiene la categoría principal vanilla (DisplayCategory) de un ítem.
---@param item InventoryItem
---@return string
function GlobalStorageSiK.Router.getItemCategory(item)
	if not item then
		return "Misc"
	end
	if GlobalStorageSiK.ItemTaxonomy and GlobalStorageSiK.ItemTaxonomy.keysFromItem then
		local mainKey, _ = GlobalStorageSiK.ItemTaxonomy.keysFromItem(item)
		if mainKey and mainKey ~= "" then
			return mainKey
		end
	end
	if item.getDisplayCategory then
		local cat = item:getDisplayCategory()
		if cat and cat ~= "" then
			return cat
		end
	end
	return "Misc"
end

--- Obtiene la subcategoría vanilla de un ítem (perk, BodyLocation, etc.).
---@param item InventoryItem
---@return string|nil
function GlobalStorageSiK.Router.getItemSubCategory(item)
	if not item or not GlobalStorageSiK.ItemTaxonomy or not GlobalStorageSiK.ItemTaxonomy.keysFromItem then
		return nil
	end
	local _, subKey = GlobalStorageSiK.ItemTaxonomy.keysFromItem(item)
	if subKey and subKey ~= "" then
		return subKey
	end
	return nil
end

--- Comprueba coincidencia de categoría incluyendo alias legacy (Medical/FirstAid…).
---@param rule string
---@param category string
---@return boolean
local function categoryMatches(rule, category)
	if not rule or not category then
		return false
	end
	if string.lower(rule) == string.lower(category) then
		return true
	end
	if CATEGORY_ALIASES[rule] and string.lower(CATEGORY_ALIASES[rule]) == string.lower(category) then
		return true
	end
	if CATEGORY_ALIASES[category] and string.lower(CATEGORY_ALIASES[category]) == string.lower(rule) then
		return true
	end
	return false
end

--- Comprueba si un nodo acepta una categoría (reglas en entry.categories).
---@param entry table
---@param category string
---@return boolean
function GlobalStorageSiK.Router.nodeAcceptsCategory(entry, category)
	if not entry or not category then
		return true
	end
	local rules = entry.categories
	if not rules or #rules == 0 then
		return true
	end
	for i = 1, #rules do
		local rule = rules[i]
		if rule == "*" then
			return true
		end
		if rule == category then
			return true
		end
		if categoryMatches(rule, category) then
			return true
		end
	end
	return false
end

--- Indica si el contenedor tiene espacio para el ítem (B42: hasRoomFor(character, item)).
---@param container ItemContainer
---@param item InventoryItem
---@param character IsoPlayer|IsoGameCharacter|nil
---@return boolean
function GlobalStorageSiK.Router.containerHasSpace(container, item, character)
	if not container or not item then
		return false
	end
	if container.hasRoomFor and character then
		local ok, result = pcall(function()
			return container:hasRoomFor(character, item)
		end)
		if ok then
			return result == true
		end
	end
	if container.hasRoomFor then
		local okLegacy, resultLegacy = pcall(function()
			return container:hasRoomFor(item)
		end)
		if okLegacy then
			return resultLegacy == true
		end
	end
	if container.getCapacity and container.getWeight then
		local cap = container:getCapacity()
		local cur = container:getWeight()
		local w = 0
		if item.getActualWeight then
			w = item:getActualWeight()
		elseif item.getWeight then
			w = item:getWeight()
		end
		return (cur + w) <= cap
	end
	return true
end

--- Calcula el nivel de especificidad con que un nodo acepta un item, en 4
--- niveles (sistema de 3 desplegables: Categoria > Subcategoria > Sub-subcategoria):
--- 1 = filtro personalizado, subcategoria GS exacta, hueco de joyeria/ropa, o
---     hoja de Nivel 3 exacta (el mas especifico posible para este item).
--- 2 = Nivel 2 elegido sin bajar a Nivel 3 (ej. "Comida > Perecedero": acepta
---     fruta perecedera, queso perecedero... cualquier variante de esa subcategoria).
--- 3 = Nivel 1 elegido sin mas detalle (ej. "Comida": acepta CUALQUIER comida).
--- 4 = el nodo no tiene ninguna restriccion configurada (acepta cualquier cosa, incluida regla "*").
--- nil = el nodo SI tiene reglas configuradas pero ninguna encaja con este item (rechazado)
---
--- `pickDepositTarget` prueba los nodos en orden de tier (1 primero, luego 2,
--- 3, 4) y dentro de cada tier por prioridad numerica - un item con Nivel 3
--- exacto (fruta perecedera) prueba primero un nodo configurado para esa hoja
--- exacta; si no hay o esta lleno, prueba un nodo de Nivel 2 (Perecedero,
--- que incluye esa fruta); si tampoco, un nodo de Nivel 1 (Comida); si
--- tampoco, cualquier nodo sin restriccion. Mas especifico SIEMPRE gana
--- primero, la prioridad numerica solo desempata DENTRO del mismo nivel.
---@param entry table
---@param item InventoryItem
---@return number|nil
function GlobalStorageSiK.Router.matchSpecificity(entry, item)
	if not entry or not item then return 4 end
	-- Filtros personalizados (nombre/peso/tag/ítem exacto): un ítem que
	-- coincide con cualquiera de ellos se trata como maxima especificidad,
	-- igual que una subcategoria GS exacta (tier 1) - el jugador definio la
	-- regla a mano, es intencionadamente mas fino que cualquier categoria.
	if entry.filters and #entry.filters > 0 and GlobalStorageSiK.NodeFilters.matchesAny(entry.filters, item) then
		return 1
	end
	local rules = entry.categories
	if not rules or #rules == 0 then return 4 end
	-- Calcular subcategorías del ítem una sola vez
	local subKeys = GlobalStorageSiK.Subcategories and GlobalStorageSiK.Subcategories.keysForItem
		and GlobalStorageSiK.Subcategories.keysForItem(item) or {}
	local category = GlobalStorageSiK.Router.getItemCategory(item)
	-- Subcategoria vanilla real del item (BodyLocation/perk - ej. la prenda
	-- exacta de Ropa, o el hueco de joyeria en crudo) - GlobalStorageSiK.Router.getItemSubCategory
	-- ya existia pero nunca se usaba aqui: sin ella, CUALQUIER regla "::"
	-- basada en subcategoria vanilla que no fuera joyeria (ej. Ropa por
	-- prenda sin Extended Categories) nunca hacia match real al depositar.
	local subCategory = GlobalStorageSiK.Router.getItemSubCategory(item)
	local EXT = GlobalStorageSiK.ItemTaxonomy.EXT_GROUP_PREFIX
	local SUB = GlobalStorageSiK.ItemTaxonomy.SUBGROUP_PREFIX
	local bestTier = nil
	for i = 1, #rules do
		local rule = rules[i]
		if rule == "*" then
			bestTier = bestTier and math.min(bestTier, 4) or 4
		elseif GlobalStorageSiK.Subcategories and GlobalStorageSiK.Subcategories.isSubcategoryKey(rule) then
			for j = 1, #subKeys do
				if subKeys[j] == rule then
					bestTier = 1
					break
				end
			end
		elseif rule:sub(1, #SUB) == SUB then
			-- Regla de NIVEL 2 (subcategoria elegida sin bajar a Nivel 3, ej.
			-- "Comida > Perecedero"): acepta cualquier item cuyo groupLabel Y
			-- subGroupLabel coincidan (fuente unica, ver GS_ItemTaxonomy.resolve()).
			local rest = rule:sub(#SUB + 1)
			local sepPos = rest:find("::", 1, true)
			if sepPos then
				local wantGroup = string.lower(rest:sub(1, sepPos - 1))
				local wantSubGroup = string.lower(rest:sub(sepPos + 2))
				local ftOk, fullType = pcall(function() return item:getFullType() end)
				if ftOk then
					local ok, tax = pcall(GlobalStorageSiK.ItemTaxonomy.resolve, fullType, {})
					if ok and tax and tax.groupLabel ~= "" and string.lower(tax.groupLabel) == wantGroup
						and tax.subGroupLabel and string.lower(tax.subGroupLabel) == wantSubGroup then
						bestTier = bestTier and math.min(bestTier, 2) or 2
					end
				end
			end
		elseif rule:sub(1, #EXT) == EXT then
			-- Regla de NIVEL 1 (familia completa, ej. "Comida" sola): acepta
			-- cualquier item cuyo groupLabel coincida, tenga o no Nivel 2/3.
			local group = string.lower(rule:sub(#EXT + 1))
			local ftOk, fullType = pcall(function() return item:getFullType() end)
			if ftOk then
				local ok, tax = pcall(GlobalStorageSiK.ItemTaxonomy.resolve, fullType, {})
				if ok and tax and tax.groupLabel ~= "" and string.lower(tax.groupLabel) == group then
					bestTier = bestTier and math.min(bestTier, 3) or 3
				end
			end
		elseif rule:find("::", 1, true) then
			-- Regla "categoria::hueco" (joyeria, ropa por prenda, o cualquier
			-- subcategoria vanilla con hueco - ver GS_ItemTaxonomy.lua:
			-- collectLeafFilters). Tan especifica como una subcategoria GS (tier 1).
			-- Se acepta el hueco tanto si es de joyeria (jewelrySlotKey,
			-- agrupado) como si es la subcategoria vanilla cruda (subCategory,
			-- ej. la prenda exacta de Ropa) - mismo formato de clave, dos
			-- fuentes posibles segun la categoria del item.
			local sepPos = rule:find("::", 1, true)
			local mainPart = string.lower(rule:sub(1, sepPos - 1))
			local slotPart = string.lower(rule:sub(sepPos + 2))
			if string.lower(category) == mainPart then
				if subCategory and string.lower(subCategory) == slotPart then
					bestTier = 1
				else
					local ftOk, fullType = pcall(function() return item:getFullType() end)
					if ftOk then
						local ok, tax = pcall(GlobalStorageSiK.ItemTaxonomy.resolve, fullType, {})
						if ok and tax and tax.jewelrySlotKey == slotPart then
							bestTier = 1
						end
					end
				end
			end
		else
			if categoryMatches(rule, category) then
				bestTier = 1
			end
		end
	end
	return bestTier
end

--- Comprueba si un nodo acepta un ítem concreto (incluye subcategorías GS y categoría vanilla).
---@param entry table
---@param item InventoryItem
---@return boolean
function GlobalStorageSiK.Router.nodeAcceptsItem(entry, item)
	return GlobalStorageSiK.Router.matchSpecificity(entry, item) ~= nil
end

--- Indica si el contenedor ya tiene al menos una unidad de este fullType -
--- usado para la afinidad "mismo item, mismo contenedor" (ver
--- pickDepositTarget mas abajo).
---@param container ItemContainer
---@param fullType string|nil
---@return boolean
function GlobalStorageSiK.Router.containerHasItemType(container, fullType)
	if not container or not fullType or not container.getItems then
		return false
	end
	-- Iteracion manual en vez de container:FindAndReturn(fullType): ese
	-- metodo Java-bridge no detecta de forma fiable todos los tipos de item
	-- (confirmado por reporte de usuario: afinidad fallaba con unos items
	-- pero no con otros, ej. planchas de madera si, otros no) - mismo motivo
	-- por el que el resto del codigo ya evita depender de metodos Java
	-- directos y prefiere recorrer getItems() a mano.
	local ok, items = pcall(function() return container:getItems() end)
	if not ok or not items or not items.size then
		return false
	end
	for i = 0, items:size() - 1 do
		local it = items:get(i)
		if it and it.getFullType and it:getFullType() == fullType then
			return true
		end
	end
	return false
end

--- Elige el mejor nodo vivo para depositar un ítem.
---@param item InventoryItem
---@param liveNodes table[]
---@param character IsoPlayer|IsoGameCharacter|nil
---@return table|nil liveEntry
---@return string|nil reason "no_match" cuando el sandbox RejectDepositIfNoMatch
--- rechazo el deposito por falta de categoria/filtro/afinidad (ver mas abajo)
function GlobalStorageSiK.Router.pickDepositTarget(item, liveNodes, character)
	if not item or not liveNodes or #liveNodes == 0 then
		return nil
	end

	-- Afinidad "mismo item, mismo contenedor" (pedido explicitamente: "si ya
	-- existe ese mismo objeto en alguna caja de la red, al arrastrarlo se
	-- envie automaticamente a ese mismo contenedor, en vez de elegir
	-- cualquiera al azar"). Se aplica SOLO donde no hay configuracion
	-- explicita del jugador que ya decida el destino (tier 4 = nodo sin
	-- ninguna regla de categoria, y el fallback final sin match alguno) -
	-- una regla de categoria/filtro que el jugador SI configuro a mano
	-- siempre gana, esto no la pisa.
	local fullType = item.getFullType and item:getFullType() or nil

	local autoSort = GlobalStorageSiK.Sandbox.autoSortEnabled()
	-- Sandbox "rechazar si no hay match": desactiva SOLO los fallbacks que
	-- ignoran categoria por completo (tier 4 sin afinidad y el catch-all
	-- final "cualquier hueco libre"). Un match real por categoria (tiers
	-- 1-3) o por afinidad de mismo item SIGUE funcionando igual, esto no
	-- los toca - solo evita que el item acabe "a lo loco" en un contenedor
	-- sin ninguna relacion con el.
	local strictNoMatch = GlobalStorageSiK.Sandbox.rejectDepositIfNoMatch and GlobalStorageSiK.Sandbox.rejectDepositIfNoMatch()
	local debugOn = GlobalStorageSiK.Sandbox.debugMode()
	if debugOn then
		local ft = item.getFullType and item:getFullType() or "?"
		local subKeys = GlobalStorageSiK.Subcategories and GlobalStorageSiK.Subcategories.keysForItem
			and GlobalStorageSiK.Subcategories.keysForItem(item) or {}
		GlobalStorageSiK.Log.debug("Router", "pickDepositTarget | fullType=" .. tostring(ft)
			.. " category=" .. tostring(GlobalStorageSiK.Router.getItemCategory(item))
			.. " subKeys=" .. (#subKeys > 0 and table.concat(subKeys, ",") or "(ninguna)")
			.. " autoSort=" .. tostring(autoSort) .. " liveNodes=" .. tostring(#liveNodes))
	end

	if autoSort then
		-- Ordenar por prioridad ascendente: 1 = Alta (se elige primero),
		-- 100 = Baja (se elige de ultimo), 50 = Normal por defecto. Misma
		-- convencion que GS_Redistribute.lua y GS_ZonePriority.lua (numero
		-- mas bajo = mas prioritario). Antes esto ordenaba al reves
		-- (descendente), asi que un contenedor marcado "Baja" prioridad
		-- (numero alto) se elegia ANTES que uno "Alta" (numero bajo).
		--
		-- Especificidad de categoria PRIMERO, prioridad numerica solo como
		-- desempate DENTRO del mismo nivel (ver comentario de matchSpecificity):
		-- tier 1 = hoja exacta (Nivel 3), tier 2 = Nivel 2 (subcategoria sin
		-- hoja), tier 3 = Nivel 1 (categoria sin mas detalle), tier 4 = nodo
		-- sin restriccion. Se procesan los 4 tiers en orden.
		local tiers = { {}, {}, {}, {} }
		for i = 1, #liveNodes do
			local live = liveNodes[i]
			local entry = live.entry or {}
			local tier = GlobalStorageSiK.Router.matchSpecificity(entry, item)
			if tier then
				table.insert(tiers[tier], live)
			end
			if debugOn then
				GlobalStorageSiK.Log.debug("Router", "pickDepositTarget | nodeId=" .. tostring(entry.id)
					.. " displayName=" .. tostring(entry.displayName or entry.name)
					.. " rules=" .. (entry.categories and #entry.categories > 0 and table.concat(entry.categories, ",") or "(sin restriccion)")
					.. " priority=" .. tostring(entry.priority or 50)
					.. " tier=" .. tostring(tier or "rechazado"))
			end
		end
		for tierIdx = 1, 4 do
			local sorted = tiers[tierIdx]
			table.sort(sorted, function(a, b)
				return ((a.entry or {}).priority or 50) < ((b.entry or {}).priority or 50)
			end)
			if tierIdx == 4 and fullType then
				for i = 1, #sorted do
					local live = sorted[i]
					if GlobalStorageSiK.Router.containerHasItemType(live.container, fullType)
						and GlobalStorageSiK.Router.containerHasSpace(live.container, item, character) then
						if debugOn then
							GlobalStorageSiK.Log.debug("Router", "pickDepositTarget | tier=4 afinidad mismo item -> nodeId="
								.. tostring((live.entry or {}).id))
						end
						return live
					end
				end
			end
			-- Tier 4 = sin restriccion de categoria: el barrido generico
			-- (ignora afinidad, solo mira hueco libre) es exactamente el "a
			-- lo loco" que rejectDepositIfNoMatch debe evitar. Tiers 1-3 son
			-- match real por categoria, se permiten siempre.
			if tierIdx < 4 or not strictNoMatch then
				for i = 1, #sorted do
					local live = sorted[i]
					local hasSpace = GlobalStorageSiK.Router.containerHasSpace(live.container, item, character)
					if debugOn then
						GlobalStorageSiK.Log.debug("Router", "pickDepositTarget | tier=" .. tostring(tierIdx)
							.. " nodeId=" .. tostring((live.entry or {}).id) .. " hasSpace=" .. tostring(hasSpace))
					end
					if hasSpace then
						return live
					end
				end
			end
		end
	end

	if fullType then
		for i = 1, #liveNodes do
			local live = liveNodes[i]
			if GlobalStorageSiK.Router.containerHasItemType(live.container, fullType)
				and GlobalStorageSiK.Router.containerHasSpace(live.container, item, character) then
				if debugOn then
					GlobalStorageSiK.Log.debug("Router", "pickDepositTarget | RESULT: afinidad mismo item sin match por categoria (nodeId="
						.. tostring((live.entry or {}).id) .. ")")
				end
				return live
			end
		end
	end

	if strictNoMatch then
		if debugOn then
			GlobalStorageSiK.Log.debug("Router", "pickDepositTarget | RESULT: sin categoria/afinidad, rechazado por sandbox RejectDepositIfNoMatch")
		end
		return nil, "no_match"
	end

	for i = 1, #liveNodes do
		local live = liveNodes[i]
		if GlobalStorageSiK.Router.containerHasSpace(live.container, item, character) then
			if debugOn then
				GlobalStorageSiK.Log.debug("Router", "pickDepositTarget | RESULT: sin match por categoria, cayendo al primer nodo con espacio (nodeId=" .. tostring((live.entry or {}).id) .. ")")
			end
			return live
		end
	end

	return nil
end

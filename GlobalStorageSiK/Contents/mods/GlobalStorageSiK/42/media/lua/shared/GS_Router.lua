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
require "GS_InventorySync"

GlobalStorageSiK.Router = {}

-- Cache de ItemTaxonomy.resolve() por fullType (dev22, eficiencia): sin esto,
-- matchSpecificity recalculaba resolve() para el MISMO item hasta 2 veces por
-- nodo (contexto vacio + contexto de fila) en pickDepositTarget, que ya
-- itera todos los nodos vivos (tipicamente 10-20) para el mismo item - decenas
-- de llamadas identicas por deposito. El resultado de resolve() depende solo
-- del fullType (via ScriptItem, mismo para toda instancia de ese tipo) y de
-- category/subCategory, que a su vez tambien salen del fullType (mismo
-- ScriptItem) - no del item vivo concreto, asi que cachear por fullType es
-- seguro y valido durante toda la vida del proceso (servidor o SP real),
-- nunca queda obsoleto salvo que cambie el catalogo de items (solo con un
-- cambio de mods, que ya requiere reiniciar el proceso).
local _taxResolveCache = {}
local function resolveCached(fullType, ctxKind, ctx)
	if not fullType then
		return nil
	end
	local key = fullType .. "|" .. ctxKind
	local cached = _taxResolveCache[key]
	if cached ~= nil then
		if cached == false then
			return nil
		end
		return cached
	end
	local ok, tax = pcall(GlobalStorageSiK.ItemTaxonomy.resolve, fullType, ctx)
	if not ok or not tax then
		_taxResolveCache[key] = false
		return nil
	end
	_taxResolveCache[key] = tax
	return tax
end

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
	return GlobalStorageSiK.InventorySync.containerHasRoom(container, item, character)
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
	-- BUG REAL sospechado (2026-08-16, "comida perecedera configurada en
	-- congelador con Nivel 2 (Comida > Perecedero, sin Nivel 3) nunca llega
	-- ahi"): las dos llamadas a ItemTaxonomy.resolve() de mas abajo (reglas
	-- Nivel 1 y Nivel 2) pasaban un contexto de fila VACIO ({}), mientras que
	-- collectSubFilters/collectLeafFilters (que construyen las opciones del
	-- desplegable en la UI y SI resuelven bien "Perecedero" para items de
	-- comida, confirmado en logs reales) siempre pasan la fila completa
	-- (row.category/row.subCategory ya resueltos server-side). resolve() solo
	-- usa esos campos como FALLBACK si el lookup por scriptItem falla, pero
	-- si esa categoria compuesta (ej. via Extended Categories) no es
	-- recuperable desde el ScriptItem "en frio" que usa este camino, el
	-- resultado puede divergir silenciosamente del que vio el jugador al
	-- configurar el filtro. Se pasa aqui el mismo category/subCategory ya
	-- calculado arriba (via el ITEM VIVO, no fallback vacio) para cerrar ese
	-- hueco sin duplicar logica.
	local rowContext = { category = category, subCategory = subCategory }
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
			-- "Food > FoodPerishable"): acepta cualquier item cuyas claves
			-- canonicas groupKey Y subGroupKey coincidan. Las etiquetas traducidas
			-- se aceptan solo como fallback legacy hasta migrar el nodo desde la UI.
			local rest = rule:sub(#SUB + 1)
			local sepPos = rest:find("::", 1, true)
			if sepPos then
				local wantGroup = string.lower(rest:sub(1, sepPos - 1))
				local wantSubGroup = string.lower(rest:sub(sepPos + 2))
				local ftOk, fullType = pcall(function() return item:getFullType() end)
				if ftOk then
					-- dev22: probar resolve() con DOS contextos distintos (vacio y
					-- con category/subCategory del item vivo), ambos cacheados por
					-- fullType (ver resolveCached arriba) - antes se llamaba
					-- resolve() sin cache, hasta 2 veces por nodo evaluado (10-20
					-- nodos por deposito) para el MISMO item, puro trabajo repetido.
					local taxEmpty = resolveCached(fullType, "empty", {})
					local taxRow = resolveCached(fullType, "row", rowContext)
					local function matches(tax)
						if not tax then return false end
						local groupMatches = tax.groupKey and string.lower(tax.groupKey) == wantGroup
							or (tax.groupLabel and string.lower(tax.groupLabel) == wantGroup)
						local subMatches = tax.subGroupKey and string.lower(tax.subGroupKey) == wantSubGroup
							or (tax.subGroupLabel and string.lower(tax.subGroupLabel) == wantSubGroup)
						return groupMatches and subMatches
					end
					if matches(taxEmpty) or matches(taxRow) then
						bestTier = bestTier and math.min(bestTier, 2) or 2
					end
				end
			end
		elseif rule:sub(1, #EXT) == EXT then
			-- Regla de NIVEL 1 (familia completa, ej. "Comida" sola): acepta
			-- cualquier item cuyo groupKey canonico coincida, tenga o no Nivel 2/3.
			local group = string.lower(rule:sub(#EXT + 1))
			local ftOk, fullType = pcall(function() return item:getFullType() end)
			if ftOk then
				local tax = resolveCached(fullType, "empty", {})
				if tax and ((tax.groupKey and string.lower(tax.groupKey) == group)
					or (tax.groupLabel and string.lower(tax.groupLabel) == group)) then
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
						local tax = resolveCached(fullType, "row", rowContext)
						if tax and tax.jewelrySlotKey == slotPart then
							bestTier = 1
						end
					end
				end
			end
		else
			-- Regla de NIVEL 3 sin combo (hoja EC compuesta, ej. "Comida >
			-- Perecedero > Carne" = clave cruda "FoodPerishableMeat" completa,
			-- ver GS_ItemTaxonomy.collectLeafFilters "elseif tax.hyphenLeafLabel
			-- then key = tax.mainCanon"). category (arriba, via
			-- Router.getItemCategory del ITEM VIVO) deberia coincidir en crudo
			-- con rule sin mas, pero por la misma cautela que Nivel 2 (dev22):
			-- si el match directo falla, reintentar contra tax.mainCanon
			-- resuelto via resolve() con rowContext antes de rendirse.
			if categoryMatches(rule, category) then
				bestTier = 1
			else
				local ftOk, fullType = pcall(function() return item:getFullType() end)
				if ftOk then
					local tax = resolveCached(fullType, "row", rowContext)
					if tax and tax.mainCanon and categoryMatches(rule, tax.mainCanon) then
						bestTier = 1
					end
				end
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

--- Construye una captura de afinidad por nodo para todo un micro-lote. Evita
--- volver a recorrer cada contenedor por cada item depositado y mantiene las
--- decisiones del lote coherentes a medida que se incorporan objetos.
---@param liveNodes table[]
---@return table
function GlobalStorageSiK.Router.buildAffinityIndex(liveNodes)
	local index = { exactByNode = {}, taxonomyByNode = {}, nodeIndexById = {} }
	for i = 1, #(liveNodes or {}) do
		local live = liveNodes[i]
		local entry = live and live.entry or {}
		if entry.id then index.nodeIndexById[tostring(entry.id)] = i end
		local exact = {}
		local taxonomy = {}
		index.exactByNode[i] = exact
		index.taxonomyByNode[i] = taxonomy
		local container = live and live.container
		local items = container and container.getItems and container:getItems() or nil
		if items and items.size then
			for j = 0, items:size() - 1 do
				local existing = items:get(j)
				local fullType = existing and existing.getFullType and existing:getFullType() or nil
				if fullType then exact[fullType] = (exact[fullType] or 0) + 1 end
				local affinityKey = GlobalStorageSiK.ItemTaxonomy.affinityKeyFromItem(existing)
				if affinityKey then taxonomy[affinityKey] = (taxonomy[affinityKey] or 0) + 1 end
			end
		end
	end
	return index
end

---@param index table|nil
---@param nodeIndex number|nil
---@param item InventoryItem|nil
---@param delta number
function GlobalStorageSiK.Router.updateAffinityIndex(index, nodeIndex, item, delta)
	if not index or not nodeIndex or not item then return end
	local fullType = item.getFullType and item:getFullType() or nil
	local affinityKey = GlobalStorageSiK.ItemTaxonomy.affinityKeyFromItem(item)
	local exact = index.exactByNode[nodeIndex] or {}
	local taxonomy = index.taxonomyByNode[nodeIndex] or {}
	index.exactByNode[nodeIndex] = exact
	index.taxonomyByNode[nodeIndex] = taxonomy
	if fullType then exact[fullType] = math.max(0, (exact[fullType] or 0) + delta) end
	if affinityKey then taxonomy[affinityKey] = math.max(0, (taxonomy[affinityKey] or 0) + delta) end
end

--- Expande el tier sin restricciones: exacto, familia taxonomica o generico.
---@param excludeCurrent boolean|nil Resta la propia instancia al evaluar su nodo de origen en Auto Sort
---@return number 4=fullType, 5=taxonomia, 6=generico
function GlobalStorageSiK.Router.unrestrictedAffinityTier(item, nodeIndex, affinityIndex, excludeCurrent)
	local fullType = item and item.getFullType and item:getFullType() or nil
	local exact = affinityIndex and affinityIndex.exactByNode
		and affinityIndex.exactByNode[nodeIndex] or {}
	local exactCount = fullType and (exact[fullType] or 0) or 0
	if excludeCurrent then exactCount = math.max(0, exactCount - 1) end
	if exactCount > 0 then return 4 end
	local affinityKey = GlobalStorageSiK.ItemTaxonomy.affinityKeyFromItem(item)
	local taxonomy = affinityIndex and affinityIndex.taxonomyByNode
		and affinityIndex.taxonomyByNode[nodeIndex] or {}
	local taxonomyCount = affinityKey and (taxonomy[affinityKey] or 0) or 0
	if excludeCurrent then taxonomyCount = math.max(0, taxonomyCount - 1) end
	if taxonomyCount > 0 then return 5 end
	return 6
end

--- Orden total para candidatos que YA pertenecen al mismo tier de
--- coincidencia. La categoria/filtro decide antes de llegar aqui; por tanto
--- ninguna prioridad puede hacer ganar a un contenedor generico frente a una
--- coincidencia o afinidad mejores.
local function depositCandidateBetter(a, b)
	local ea, eb = a.entry or {}, b.entry or {}
	local pa = tonumber(ea.priority) or 50
	local pb = tonumber(eb.priority) or 50
	if pa ~= pb then return pa < pb end
	local za = tonumber(a.zonePriority) or tonumber(ea.zonePriority) or 50
	local zb = tonumber(b.zonePriority) or tonumber(eb.zonePriority) or 50
	if za ~= zb then return za < zb end
	-- Desempate estable: evita que table.sort deje resultados equivalentes en
	-- un orden dependiente del recorrido de tablas/ModData.
	return tostring(ea.id or "") < tostring(eb.id or "")
end

--- Elige el mejor nodo vivo para depositar un ítem.
---@param item InventoryItem
---@param liveNodes table[]
---@param character IsoPlayer|IsoGameCharacter|nil
---@return table|nil liveEntry
---@param options table|nil { affinityIndex=table, preferredNodeId=string }
---@return string|nil reason "no_match" cuando el sandbox RejectDepositIfNoMatch
--- rechazo el deposito por falta de categoria/filtro/afinidad (ver mas abajo)
function GlobalStorageSiK.Router.pickDepositTarget(item, liveNodes, character, options)
	if not item or not liveNodes or #liveNodes == 0 then
		return nil
	end

	-- Afinidad "mismo item, mismo contenedor" (pedido explicitamente: "si ya
	-- existe ese mismo objeto en alguna caja de la red, al arrastrarlo se
	-- envie automaticamente a ese mismo contenedor, en vez de elegir
	-- cualquiera al azar"). Se aplica SOLO donde no hay configuracion
	-- explicita del jugador que ya decida el destino (tier 4 = nodo sin
	-- reglas que ya contiene el mismo fullType, o su ruta taxonomica) -
	-- una regla de categoria/filtro que el jugador SI configuro a mano
	-- siempre gana, esto no la pisa.
	options = options or {}
	local fullType = item.getFullType and item:getFullType() or nil
	local affinityIndex = options.affinityIndex or GlobalStorageSiK.Router.buildAffinityIndex(liveNodes)
	local preferredNodeId = options.preferredNodeId and tostring(options.preferredNodeId) or nil

	local autoSort = GlobalStorageSiK.Sandbox.autoSortEnabled()
	-- Sandbox "rechazar si no hay match": desactiva SOLO el tier 6 que
	-- ignora categoria y afinidad ("cualquier hueco libre"). Un match real (tiers
	-- 1-3) o por afinidad exacta/taxonomica SIGUE funcionando igual, esto no
	-- los toca - solo evita que el item acabe "a lo loco" en un contenedor
	-- sin ninguna relacion con el.
	local strictNoMatch = GlobalStorageSiK.Sandbox.rejectDepositIfNoMatch and GlobalStorageSiK.Sandbox.rejectDepositIfNoMatch()
	local debugOn = GlobalStorageSiK.Sandbox.debugMode()
	local detailOn = GlobalStorageSiK.Sandbox.debugDetailEnabled("Router")
	local ft = item.getFullType and item:getFullType() or "?"
	if debugOn then
		local subKeys = GlobalStorageSiK.Subcategories and GlobalStorageSiK.Subcategories.keysForItem
			and GlobalStorageSiK.Subcategories.keysForItem(item) or {}
		GlobalStorageSiK.Log.debug("Router", "pickDepositTarget | fullType=" .. tostring(ft)
			.. " category=" .. tostring(GlobalStorageSiK.Router.getItemCategory(item))
			.. " subKeys=" .. (#subKeys > 0 and table.concat(subKeys, ",") or "(ninguna)")
			.. " affinityKey=" .. tostring(GlobalStorageSiK.ItemTaxonomy.affinityKeyFromItem(item))
			.. " autoSort=" .. tostring(autoSort) .. " liveNodes=" .. tostring(#liveNodes))
	end

	-- «Leer y devolver» conserva el contenedor fisico de origen. El servidor
	-- solo entrega preferredNodeId para ese origen y aun revalida pertenencia,
	-- permisos, reglas actuales y espacio; si ya no sirve, cae al router normal.
	if preferredNodeId then
		local preferredIndex = affinityIndex.nodeIndexById
			and affinityIndex.nodeIndexById[preferredNodeId] or nil
		local preferred = preferredIndex and liveNodes[preferredIndex] or nil
		if preferred and GlobalStorageSiK.Router.matchSpecificity(preferred.entry or {}, item)
			and GlobalStorageSiK.Router.containerHasSpace(preferred.container, item, character) then
			if debugOn then
				GlobalStorageSiK.Log.debug("Router", "RESULT preferred source nodeId=" .. preferredNodeId)
			end
			return preferred
		end
		if debugOn then
			GlobalStorageSiK.Log.debug("Router", "preferred source unavailable; using shared routing nodeId="
				.. preferredNodeId)
		end
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
		-- desempate DENTRO del mismo nivel (ver comentario de matchSpecificity).
		-- Dentro de un tier: contenedor primero, zona despues e ID como empate
		-- tecnico final. Esta misma jerarquia se usa en GS_Redistribute.lua:
		-- tier 1 = hoja/custom exacto, tier 2 = subcategoria, tier 3 = categoria,
		-- tier 4 = mismo fullType, tier 5 = misma ruta taxonomica y tier 6 =
		-- nodo sin restriccion cualquiera. "Queda en inventario" es el resultado
		-- terminal cuando ninguno tiene hueco, no otro tier de destino.
		local tiers = { {}, {}, {}, {}, {}, {} }
		local hasStrictCandidate = false
		for i = 1, #liveNodes do
			local live = liveNodes[i]
			local entry = live.entry or {}
			local matchTier = GlobalStorageSiK.Router.matchSpecificity(entry, item)
			local destinationTier = matchTier
			if matchTier == 4 then
				destinationTier = GlobalStorageSiK.Router.unrestrictedAffinityTier(item, i, affinityIndex)
			end
			if destinationTier then
				table.insert(tiers[destinationTier], live)
			end
			if detailOn then
				GlobalStorageSiK.Log.detail("Router", "pickDepositTarget | nodeId=" .. tostring(entry.id)
					.. " displayName=" .. tostring(entry.displayName or entry.name)
					.. " rules=" .. (entry.categories and #entry.categories > 0 and table.concat(entry.categories, ",") or "(sin restriccion)")
					.. " zonePriority=" .. tostring(live.zonePriority or entry.zonePriority or 50)
					.. " priority=" .. tostring(entry.priority or 50)
					.. " tier=" .. tostring(destinationTier or "rechazado"))
			end
		end
		for tierIdx = 1, 6 do
			local sorted = tiers[tierIdx]
			if tierIdx < 6 and #sorted > 0 then
				-- Categoría/filtro (1-3) o afinidad real (4-5). Si existe pero
				-- está lleno, el motivo correcto será no_space, no no_match.
				hasStrictCandidate = true
			end
			table.sort(sorted, depositCandidateBetter)
			-- Tier 6 = sin restriccion ni afinidad: el barrido generico
			-- (ignora afinidad, solo mira hueco libre) es exactamente el "a
			-- lo loco" que rejectDepositIfNoMatch debe evitar. Tiers 1-3 son
			-- match real y tiers 4-5 son afinidad real; se permiten siempre.
			if tierIdx < 6 or not strictNoMatch then
				for i = 1, #sorted do
					local live = sorted[i]
					local hasSpace = GlobalStorageSiK.Router.containerHasSpace(live.container, item, character)
					if detailOn then
						GlobalStorageSiK.Log.detail("Router", "pickDepositTarget | tier=" .. tostring(tierIdx)
							.. " nodeId=" .. tostring((live.entry or {}).id) .. " hasSpace=" .. tostring(hasSpace))
					end
					if hasSpace then
						local reason = tierIdx <= 3 and "match por categoria"
							or (tierIdx == 4 and "afinidad mismo item"
								or (tierIdx == 5 and "afinidad taxonomica" or "contenedor sin restriccion"))
						if debugOn then
							GlobalStorageSiK.Log.debug("Router", string.format("RESULT tier=%s nodeId=%s (%s)",
								tostring(tierIdx), tostring((live.entry or {}).id), reason))
						end
						return live
					end
				end
			end
		end
		if strictNoMatch and not hasStrictCandidate then
			if debugOn then
				GlobalStorageSiK.Log.debug("Router", "RESULT no_match: no hay categoria, filtro ni afinidad permitida para fullType="
					.. tostring(fullType))
			end
			return nil, "no_match"
		end
	end

	-- BUG REAL confirmado con logs reales (2026-08-16, "los tablones van a
	-- Cocina" con el almacen general lleno): estos dos fallbacks finales
	-- iteraban TODOS los liveNodes sin comprobar si el nodo tenia categoria
	-- configurada que RECHAZABA este item. Primer intento de fix (-dev17):
	-- exigir matchSpecificity(entry, item) ~= nil aqui tambien - pero logs
	-- reales de -dev22 (2026-08-16, ronda posterior) muestran Cocina
	-- (rules=__extgroup__:Cocina) recibiendo Patatas fritas Y un Tablon
	-- pese a aparecer "tier=rechazado" para esos mismos items en el barrido
	-- normal de matchSpecificity segundos antes - la revalidacion aqui no es
	-- de fiar (causa exacta no aislada). Se elimina por completo esa segunda
	-- llamada: el ultimo recurso ahora SOLO acepta nodos SIN ninguna
	-- categoria configurada, sin revalidacion. Mas estricto a proposito:
	-- preferible que un deposito falle a que viole en silencio una
	-- categoria configurada a mano.
	--
	-- dev24 (eficiencia, pedido explicito - evitar reescaneos redundantes):
	-- "nodo sin ninguna categoria configurada" es EXACTAMENTE la definicion
	-- de los tiers 4/5 en pickDepositTarget, y con autoSort activo el bucle de
	-- arriba YA
	-- prueba exactamente ese mismo conjunto de nodos, en el mismo orden de
	-- prioridad. Repetir aqui el mismo escaneo para el mismo resultado era
	-- trabajo duplicado en el camino mas comun (autoSort=true, el valor por
	-- defecto) - estos dos fallbacks ahora SOLO se ejecutan cuando autoSort
	-- esta desactivado (la unica situacion en que el bucle de tiers de
	-- arriba no llego a correr en absoluto).
	if not autoSort then
		local function nodeHasNoCategories(entry)
			local rules = entry and entry.categories
			return not rules or #rules == 0
		end

		local hasAffinityCandidate = false
		for affinityTier = 4, 5 do
			for i = 1, #liveNodes do
				local live = liveNodes[i]
				local destinationTier = nodeHasNoCategories(live.entry)
					and GlobalStorageSiK.Router.unrestrictedAffinityTier(item, i, affinityIndex) or nil
				if destinationTier == affinityTier then
					hasAffinityCandidate = true
					if GlobalStorageSiK.Router.containerHasSpace(live.container, item, character) then
						if debugOn then
							GlobalStorageSiK.Log.debug("Router", "RESULT fallback final: affinityTier="
								.. tostring(affinityTier) .. " nodeId=" .. tostring((live.entry or {}).id))
						end
						return live
					end
				end
			end
		end

		if strictNoMatch and not hasAffinityCandidate then
			return nil, "no_match"
		end

		for i = 1, #liveNodes do
			local live = liveNodes[i]
			if nodeHasNoCategories(live.entry) and GlobalStorageSiK.Router.containerHasSpace(live.container, item, character) then
				return live
			end
		end
	end

	if debugOn then
		GlobalStorageSiK.Log.debug("Router", "RESULT no_space: ningun nodo compatible tenia hueco para fullType=" .. tostring(fullType))
	end

	return nil, "no_space"
end

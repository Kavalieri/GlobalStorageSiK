--[[
	GlobalStorageSiK - GS-Router (auto-ordenado propio)
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Elige nodo destino por categoría y capacidad. Sin modData de Manage Containers.
	Inspiración: StrogareSimpleMP (3739374300) — lógica propia.
]]

require "GS_Sandbox"
require "GS_NativeProduct"
require "GS_RuleCoverage"
require "GS_CategoryResolution"
require "GS_RuleSanitizer"
require "GS_Log"
require "GS_NodeFilters"
require "GS_InventorySync"

GlobalStorageSiK.Router = {}

--- Obtiene la categoría principal vanilla (DisplayCategory) de un ítem.
---@param item InventoryItem
---@return string
function GlobalStorageSiK.Router.getItemCategory(item)
	if not item or not item.getFullType then return "Misc" end
	return GlobalStorageSiK.CategoryResolution.resolve(item:getFullType(), nil, item).vanillaKey
end

--- Obtiene la subcategoría vanilla de un ítem (perk, BodyLocation, etc.).
---@param item InventoryItem
---@return string|nil
function GlobalStorageSiK.Router.getItemSubCategory(item)
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
--- Calcula el tier (1-4) con que UNA regla de categoria concreta acepta un
--- item ya resuelto (category/subCategory/subKeys/rowContext calculados una
--- sola vez por el llamante). Extraida de matchSpecificity (dev26, motor de
--- reglas AND/OR/NOT - ver Documentacion/GS_FilterRedesign_Plan.md) para que
--- tanto el camino legacy (entry.categories) como el nuevo (entry.rules,
--- condicion tipo "category") compartan exactamente la misma logica de
--- resolucion, sin duplicarla.
---@param rule string
---@param item InventoryItem
---@param category string
---@param subCategory string|nil
---@param subKeys table
---@param rowContext table
---@return number|nil
local function categoryRuleTier(rule, item, categorySource)
	if type(rule) ~= "string" then return nil end
	if rule == "*" then return 4 end
	rule = GlobalStorageSiK.CategoryResolution.legacyAliasNativePath(rule) or rule
	local stored = GlobalStorageSiK.CategoryResolution.classifyStoredRule({
		type = "category", value = rule, categorySource = categorySource,
	})
	if stored == "DEPRECATED_EXTERNAL" or stored == "TECHNICAL_RESIDUE" or stored == "LEGACY_GS_ALIAS" then return nil end
	local fullType = item and item.getFullType and item:getFullType() or nil
	if not fullType then return nil end
	local resolved = GlobalStorageSiK.CategoryResolution.resolve(fullType, nil, item)
	local nativeRule = GlobalStorageSiK.NativeProduct.decodePath(rule)
	if nativeRule then
		if resolved.effective ~= "native" or not GlobalStorageSiK.NativeProduct.pathMatches(nativeRule, resolved.nativePath) then return nil end
		if nativeRule.l3 then return 1 end
		if nativeRule.l2 then return 2 end
		return 3
	end
	return categoryMatches(rule, resolved.vanillaKey) and 1 or nil
end

--- Una categoría configurada puede existir en varios destinos. La resolución
--- del candidato pertenece a prioridad/afinidad, no a una reserva de hojas.
---@param condition table
---@param item InventoryItem
---@return number|nil
local function categoryConditionTier(condition, item)
	return categoryRuleTier(condition.nativePath or condition.value, item, condition.categorySource)
end

function GlobalStorageSiK.Router.matchSpecificity(entry, item)
	if not entry or not item then return 4 end
	-- Motor nuevo (dev26): si el contenedor ya usa el modelo unificado
	-- entry.rules (AND/OR/NOT), delega ahi por completo y no toca el camino
	-- legacy de abajo. Ver Documentacion/GS_FilterRedesign_Plan.md §3.
	if entry.rules and #entry.rules > 0 then
		return GlobalStorageSiK.Router.evaluateContainerRules(entry, item)
	end
	-- Filtros personalizados (nombre/peso/tag/ítem exacto): un ítem que
	-- coincide con cualquiera de ellos se trata como maxima especificidad,
	-- igual que una subcategoria GS exacta (tier 1) - el jugador definio la
	-- regla a mano, es intencionadamente mas fino que cualquier categoria.
	if entry.filters and #entry.filters > 0 and GlobalStorageSiK.NodeFilters.matchesAny(entry.filters, item) then
		return 1
	end
	local rules = entry.categories
	if not rules or #rules == 0 then return 4 end
	local bestTier = nil
	for i = 1, #rules do
		local tier = categoryRuleTier(rules[i], item)
		if tier then
			bestTier = bestTier and math.min(bestTier, tier) or tier
		end
	end
	return bestTier
end

--- Motor unificado de reglas AND/OR/NOT (dev26, ver
--- Documentacion/GS_FilterRedesign_Plan.md §3.2). Formula:
---   excluido_por_NOT = alguna regla NOT coincide con el item
---   cumple_AND        = TODAS las reglas AND coinciden (vacio = sin restriccion)
---   cumple_OR         = OR vacio, O al menos una regla OR coincide
---   aceptado          = cumple_AND AND cumple_OR AND NOT excluido_por_NOT
--- entry.rules vacio o ausente = sin restriccion (tier 4), identico al
--- comportamiento legacy de entry.categories vacio - ver §4.3 "caso base"
--- (afinidad sigue siendo el UNICO desempate cuando no se toca nada).
---@param entry table
---@param item InventoryItem
---@return number|nil
function GlobalStorageSiK.Router.evaluateContainerRules(entry, item)
	local rules = entry and entry.rules
	if not rules or #rules == 0 then return 4 end
	local function conditionTier(condition)
		if not condition then return nil end
		if condition.type == "category" then
			-- nativePath es autoritativa cuando existe. `value` se conserva como
			-- alias recuperable para mundos/reglas anteriores y solo se consulta
			-- mientras la migración aditiva todavía no añadió nativePath.
			local status = GlobalStorageSiK.CategoryResolution.classifyStoredRule(condition)
			if status == "DEPRECATED_EXTERNAL" or status == "TECHNICAL_RESIDUE" then return nil end
			return categoryConditionTier(condition, item)
		end
		if GlobalStorageSiK.NodeFilters.matchesOne(condition, item) then
			return 1
		end
		return nil
	end

	local orTier, andTier = nil, nil
	local hasOr, hasAnd = false, false
	local andFailed = false

	for i = 1, #rules do
		local rule = rules[i]
		local junk = GlobalStorageSiK.RuleSanitizer.isJunkCategoryCondition(rule.condition)
		local op = rule.op
		local tier = not junk and conditionTier(rule.condition) or nil
		if junk then
			-- Condición legacy inequívocamente basura: queda fuera del routing.
		elseif op == "NOT" then
			if tier then
				return nil
			end
		elseif op == "AND" then
			hasAnd = true
			if not tier then
				andFailed = true
			else
				andTier = andTier and math.min(andTier, tier) or tier
			end
		else
			-- OR (op == "OR" o desconocido: tratar como OR por seguridad,
			-- nunca dejar una regla mal etiquetada excluya silenciosamente)
			hasOr = true
			if tier then
				orTier = orTier and math.min(orTier, tier) or tier
			end
		end
	end

	if hasAnd and (andFailed or not andTier) then return nil end
	if hasOr and not orTier then return nil end

	local resultTier = andTier
	if orTier then
		resultTier = resultTier and math.min(resultTier, orTier) or orTier
	end
	return resultTier or 4
end

--- Puerta binaria de zona (dev26, ronda 2 - ver
--- Documentacion/GS_FilterRedesign_Plan.md §4.4-bis): las reglas de zona se
--- evalúan ANTES que las del contenedor, con la MISMA formula AND/OR/NOT
--- (reutiliza evaluateContainerRules pasandole {rules=zoneRules} - no hay
--- nada especifico de "contenedor" en esa funcion, solo agrupa/combina
--- condiciones). Zona sin reglas = totalmente transparente (no cambia nada
--- del comportamiento actual). Un NOT de zona excluye siempre, igual que un
--- NOT de contenedor - "las exclusiones de zona ganan siempre" se cumple
--- automaticamente porque evaluateContainerRules ya prioriza NOT sobre todo
--- lo demas.
---@param zoneRules table|nil
---@param item InventoryItem
---@return boolean
function GlobalStorageSiK.Router.zoneRulesAllow(zoneRules, item)
	if not zoneRules or #zoneRules == 0 then
		return true
	end
	return GlobalStorageSiK.Router.evaluateContainerRules({ rules = zoneRules }, item) ~= nil
end

--- Combina la puerta de zona (reglas Y exclusion de zona) con
--- matchSpecificity del contenedor: un item debe pasar AMBOS niveles (zona Y
--- contenedor) para ser aceptado. Punto de entrada unico para el enrutado
--- con zona - pickDepositTarget/Auto-ordenar usan esto en vez de
--- matchSpecificity directamente. zoneEnabled=false (dev26, ronda 2 - ver
--- §4.5 del plan, "Excluir zona") rechaza sin mirar ni reglas ni contenedor,
--- simetrico a como membership="excluded" ya rechaza un contenedor.
---@param entry table
---@param zoneRules table|nil
---@param zoneEnabled boolean|nil
---@param item InventoryItem
---@return number|nil
function GlobalStorageSiK.Router.matchWithZoneGate(entry, zoneRules, zoneEnabled, item)
	if zoneEnabled == false then
		return nil
	end
	if not GlobalStorageSiK.Router.zoneRulesAllow(zoneRules, item) then
		return nil
	end
	return GlobalStorageSiK.Router.matchSpecificity(entry, item)
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
				local affinityKey = existing and existing.getFullType
					and GlobalStorageSiK.CategoryResolution.resolve(existing:getFullType(), nil, existing).routingIdentity or nil
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
	local affinityKey = item and item.getFullType
		and GlobalStorageSiK.CategoryResolution.resolve(item:getFullType(), nil, item).routingIdentity or nil
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
	local affinityKey = item and item.getFullType
		and GlobalStorageSiK.CategoryResolution.resolve(item:getFullType(), nil, item).routingIdentity or nil
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
--- coincidencia o afinidad mejores. Prioridad de ZONA primero (2026-08-24,
--- pedido explicito del usuario: "lo mas normal es que el jugador no toque el
--- campo de zona; si lo toca, es porque quiere que primero se revise esa
--- zona" - mas amplio/deliberado que un solo contenedor cuando se configura,
--- asi que decide antes). Mismo orden en GS_Redistribute.lua (candidateBetter).
local function depositCandidateBetter(a, b)
	local ea, eb = a.entry or {}, b.entry or {}
	local za = tonumber(a.zonePriority) or tonumber(ea.zonePriority) or 50
	local zb = tonumber(b.zonePriority) or tonumber(eb.zonePriority) or 50
	if za ~= zb then return za < zb end
	local pa = tonumber(ea.priority) or 50
	local pb = tonumber(eb.priority) or 50
	if pa ~= pb then return pa < pb end
	-- Desempate estable: evita que table.sort deje resultados equivalentes en
	-- un orden dependiente del recorrido de tablas/ModData.
	return tostring(ea.id or "") < tostring(eb.id or "")
end

--- Compara candidatos SIN categoria/filtro configurado (tiers 4/5/6
--- fusionados): aqui la PRIORIDAD (zona primero, contenedor despues - mismo
--- orden que depositCandidateBetter arriba) manda antes que la afinidad
--- (pedido explicito del usuario, 2026-08-24 - antes la afinidad exacta/
--- taxonomica ganaba siempre y un contenedor nuevo vacio con prioridad alta
--- nunca podia atraer objetos de un contenedor viejo que ya los tenia). La
--- afinidad solo desempata entre candidatos que comparten AMBAS prioridades
--- (zona Y contenedor) - cambiar la prioridad de un contenedor/zona SI
--- afecta al resultado de la afinidad, no es un criterio aislado. Mismo
--- cambio en paralelo en GS_Redistribute.lua (unrestrictedCandidateBetter)
--- para que Auto-ordenar y el deposito manual decidan igual.
---@param a table candidato { live=table, affinityTier=number }
---@param b table candidato { live=table, affinityTier=number }
---@return boolean
local function unrestrictedDepositCandidateBetter(a, b)
	local ea, eb = a.live.entry or {}, b.live.entry or {}
	local za = tonumber(a.live.zonePriority) or tonumber(ea.zonePriority) or 50
	local zb = tonumber(b.live.zonePriority) or tonumber(eb.zonePriority) or 50
	if za ~= zb then return za < zb end
	local pa = tonumber(ea.priority) or 50
	local pb = tonumber(eb.priority) or 50
	if pa ~= pb then return pa < pb end
	if a.affinityTier ~= b.affinityTier then return a.affinityTier < b.affinityTier end
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
		local resolution = GlobalStorageSiK.CategoryResolution.resolve(ft, nil, item)
		GlobalStorageSiK.Log.debug("Router", "pickDepositTarget | fullType=" .. tostring(ft)
			.. " effective=" .. tostring(resolution.routingIdentity)
			.. " nativeStatus=" .. tostring(resolution.nativeStatus)
			.. " autoSort=" .. tostring(autoSort) .. " liveNodes=" .. tostring(#liveNodes))
	end

	-- «Leer y devolver» conserva el contenedor fisico de origen. El servidor
	-- solo entrega preferredNodeId para ese origen y aun revalida pertenencia,
	-- permisos, reglas actuales y espacio; si ya no sirve, cae al router normal.
	if preferredNodeId then
		local preferredIndex = affinityIndex.nodeIndexById
			and affinityIndex.nodeIndexById[preferredNodeId] or nil
		local preferred = preferredIndex and liveNodes[preferredIndex] or nil
		if preferred and GlobalStorageSiK.Router.matchWithZoneGate(preferred.entry or {}, preferred.zoneRules, preferred.zoneEnabled, item)
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
		-- Especificidad de categoria PRIMERO (tiers 1-3: filtro/categoria
		-- configurada a mano), prioridad numerica solo como desempate DENTRO
		-- del mismo nivel ahi (ver comentario de matchSpecificity). Dentro de
		-- un tier 1-3: ZONA primero, contenedor despues, ID como empate
		-- tecnico final (2026-08-24, pedido explicito del usuario: la
		-- prioridad de zona es mas amplia/deliberada cuando se configura, asi
		-- que decide antes que la de un solo contenedor). Esta misma
		-- jerarquia se usa en GS_Redistribute.lua.
		--
		-- Tiers 4/5/6 (sin categoria configurada en ningun lado - "afinidad")
		-- se tratan distinto desde 2026-08-24 (pedido explicito del usuario):
		-- se FUSIONAN en un solo grupo donde la PRIORIDAD (zona, luego
		-- contenedor - mismo orden que arriba) manda primero y la afinidad
		-- exacta(4)/taxonomica(5)/ninguna(6) solo desempata entre candidatos
		-- que comparten AMBAS prioridades - antes la afinidad ganaba siempre
		-- y un contenedor nuevo vacio con prioridad alta nunca podia atraer
		-- objetos de un contenedor viejo que ya los contenia (se
		-- autocalificaba mejor tier por afinidad consigo mismo). Cambiar la
		-- prioridad de zona o de contenedor SI afecta al resultado de la
		-- afinidad ahora, no es un criterio aislado. "Queda en inventario" es
		-- el resultado terminal cuando ninguno tiene hueco, no otro tier de
		-- destino.
		local tiers = { {}, {}, {}, {}, {}, {} }
		local hasStrictCandidate = false
		for i = 1, #liveNodes do
			local live = liveNodes[i]
			local entry = live.entry or {}
			local matchTier = GlobalStorageSiK.Router.matchWithZoneGate(entry, live.zoneRules, live.zoneEnabled, item)
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
		for tierIdx = 1, 3 do
			-- Categoria/filtro configurado a mano: sin cambios, sigue ganando
			-- siempre a la familia "sin restriccion" de abajo.
			local sorted = tiers[tierIdx]
			if #sorted > 0 then
				hasStrictCandidate = true
			end
			table.sort(sorted, depositCandidateBetter)
			for i = 1, #sorted do
				local live = sorted[i]
				local hasSpace = GlobalStorageSiK.Router.containerHasSpace(live.container, item, character)
				if detailOn then
					GlobalStorageSiK.Log.detail("Router", "pickDepositTarget | tier=" .. tostring(tierIdx)
						.. " nodeId=" .. tostring((live.entry or {}).id) .. " hasSpace=" .. tostring(hasSpace))
				end
				if hasSpace then
					if debugOn then
						GlobalStorageSiK.Log.debug("Router", string.format("RESULT tier=%s nodeId=%s (match por categoria)",
							tostring(tierIdx), tostring((live.entry or {}).id)))
					end
					return live
				end
			end
		end
		-- Tiers 4/5/6 fusionados: sin categoria configurada en ningun lado, la
		-- prioridad del contenedor manda primero y la afinidad solo desempata
		-- entre candidatos de la misma prioridad (pedido explicito del
		-- usuario, 2026-08-24 - ver unrestrictedDepositCandidateBetter). Tier
		-- 6 (sin afinidad) se excluye del todo si el sandbox exige rechazar
		-- sin match.
		local unrestrictedMerged = {}
		for srcTier = 4, 6 do
			if srcTier < 6 and #tiers[srcTier] > 0 then
				hasStrictCandidate = true
			end
			if srcTier < 6 or not strictNoMatch then
				for _, live in ipairs(tiers[srcTier]) do
					table.insert(unrestrictedMerged, { live = live, affinityTier = srcTier })
				end
			end
		end
		table.sort(unrestrictedMerged, unrestrictedDepositCandidateBetter)
		for i = 1, #unrestrictedMerged do
			local cand = unrestrictedMerged[i]
			local live = cand.live
			local hasSpace = GlobalStorageSiK.Router.containerHasSpace(live.container, item, character)
			if detailOn then
				GlobalStorageSiK.Log.detail("Router", "pickDepositTarget | tier=" .. tostring(cand.affinityTier)
					.. " nodeId=" .. tostring((live.entry or {}).id) .. " hasSpace=" .. tostring(hasSpace))
			end
			if hasSpace then
				local reason = cand.affinityTier == 4 and "afinidad mismo item"
					or (cand.affinityTier == 5 and "afinidad de categoría" or "contenedor sin restriccion")
				if debugOn then
					GlobalStorageSiK.Log.debug("Router", string.format("RESULT tier=%s nodeId=%s (%s)",
						tostring(cand.affinityTier), tostring((live.entry or {}).id), reason))
				end
				return live
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
		-- dev26: un contenedor con entry.rules (motor nuevo) o con reglas de
		-- ZONA no es "sin restriccion" aunque entry.categories legacy este
		-- vacio - antes solo se miraba entry.categories, un contenedor
		-- migrado a reglas (o cubierto por una regla de zona) se colaba aqui
		-- como "acepta cualquier cosa" pese a tener restricciones reales.
		local function nodeUnrestricted(live)
			if live and live.zoneEnabled == false then return false end
			local entry = live and live.entry
			if entry and entry.rules and #entry.rules > 0 then return false end
			local legacyRules = entry and entry.categories
			if legacyRules and #legacyRules > 0 then return false end
			if live and live.zoneRules and #live.zoneRules > 0 then return false end
			return true
		end

		local hasAffinityCandidate = false
		for affinityTier = 4, 5 do
			for i = 1, #liveNodes do
				local live = liveNodes[i]
				local destinationTier = nodeUnrestricted(live)
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
			if nodeUnrestricted(live) and GlobalStorageSiK.Router.containerHasSpace(live.container, item, character) then
				return live
			end
		end
	end

	if debugOn then
		GlobalStorageSiK.Log.debug("Router", "RESULT no_space: ningun nodo compatible tenia hueco para fullType=" .. tostring(fullType))
	end

	return nil, "no_space"
end

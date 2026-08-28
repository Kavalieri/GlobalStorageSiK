--[[
	GlobalStorageSiK - Clasificador de bloque: Alimentos y bebidas
	Autor: SiK
	Fecha: 2026-08-27

	dev9: pedido explícito del usuario ("añade los bloques restantes...
	mejor hacerlo mal e ir arreglando"). Registrado ANTES que Hogar-ocio
	para que "comida cocinada en un recipiente" (PotOfSoupRecipe,
	WaterSaucepanRice...) se reclame aquí de verdad.

	dev14 (probe controlado de sistemas, confirmado via javap sobre
	projectzomboid.jar): `si:getItemType()` es un getter OFICIAL disponible
	sobre el ScriptItem ESTÁTICO (a diferencia de `getFoodType()`, que solo
	existe sobre la instancia) - `Base.PizzaRecipe`/`BurgerRecipe`/
	`OmeletteRecipe`/`OmeletteRecipeForged`/`PotOfSoupRecipe` confirmados
	con `ItemType=base:food` a pesar del sufijo técnico "Recipe". Cuando
	`itemTypeLower(si) == "base:food"`, la identidad ya está CONFIRMADA
	(confianza 100) - el resto de reglas por nombre solo deciden el L2
	(sub-tipo), nunca si es comida o no; sin ninguna palabra reconocida,
	cae a `ingredient` como sub-tipo genérico honesto. Objetos SIN ese
	`ItemType` siguen la heurística débil de siempre (confianza 30, con
	blindaje por `WeaponCategory` y exclusiones de nombre).
]]

require "GS_NativeClassifierApi"
require "GS_NativeClassifierUtils"

local U = GlobalStorageSiK.NativeClassifierUtils

---@param si table|nil
---@return boolean
local function isWearable(si)
	return U.bodyLocationLower(si) ~= ""
end

---@param list string[]
---@return table<string, boolean>
local function toSet(list)
	local set = {}
	for i = 1, #list do set[list[i]] = true end
	return set
end

local MEAT_PROTEIN_TOKENS = toSet({ "steak", "chicken", "bacon", "sausage", "ham", "meat" })
local DAIRY_EGG_TOKENS = toSet({ "cheese", "milk", "egg", "yogurt", "butter" })
local FISH_SEAFOOD_TOKENS = toSet({ "fish", "shrimp", "crab", "lobster" })
local PRODUCE_TOKENS = toSet({ "apple", "banana", "carrot", "tomato", "lettuce", "onion", "corn", "pepper", "potato" })
local PANTRY_TOKENS = toSet({ "flour", "sugar", "salt", "rice", "pasta", "cereal" })
local INGREDIENT_TOKENS = toSet({ "dough", "batter", "stock", "broth" })
-- "clipping" (RecipeClipping) NO va aqui - es un documento de conocimiento
-- (ItemType=base:literature confirmado, ver GS_NativeClassifierKnowledgeMedia.lua).
local PREPARED_MEAL_TOKENS = toSet({ "recipe", "stew", "soup", "fried", "boiled", "roasted", "pancake", "cooked" })
local BEVERAGE_TOKENS = toSet({ "juice", "soda", "beer", "wine", "cola", "coffee", "tea" })
local ANIMAL_FEED_TOKENS = toSet({ "petfood" })

-- Orden fijo: { l2, tokens, fuente-débil }. Recorrido una vez para decidir
-- el sub-tipo tanto si la identidad viene confirmada por ItemType como si
-- viene solo por nombre (confianza distinta, mismo orden).
local L2_RULES = {
	{ l2 = "prepared_meal", tokens = PREPARED_MEAL_TOKENS, weakSource = "name_food_prepared_meal" },
	{ l2 = "meat_protein", tokens = MEAT_PROTEIN_TOKENS, weakSource = "name_food_meat_protein" },
	{ l2 = "dairy_egg", tokens = DAIRY_EGG_TOKENS, weakSource = "name_food_dairy_egg" },
	{ l2 = "fish_seafood", tokens = FISH_SEAFOOD_TOKENS, weakSource = "name_food_fish_seafood" },
	{ l2 = "produce", tokens = PRODUCE_TOKENS, weakSource = "name_food_produce" },
	{ l2 = "pantry", tokens = PANTRY_TOKENS, weakSource = "name_food_pantry" },
	{ l2 = "ingredient", tokens = INGREDIENT_TOKENS, weakSource = "name_food_ingredient" },
	{ l2 = "beverage", tokens = BEVERAGE_TOKENS, weakSource = "name_food_beverage" },
	{ l2 = "animal_feed", tokens = ANIMAL_FEED_TOKENS, weakSource = "name_food_animal_feed" },
}

-- dev15 (hallazgo de sistemas sobre dev14): "Base.RecipeClipping sigue mal
-- clasificado" - ItemType real es base:literature (confirmado, no
-- ambiguo), pero la heuristica debil de nombre ("recipe" -> prepared_meal)
-- se ejecutaba IGUAL aunque tuvieramos una clase tecnica CONOCIDA Y
-- CONTRADICTORIA. "Una clase tecnica conocida y contradictoria debe vetar
-- una heuristica debil" - unico valor confirmado hasta ahora de
-- contradiccion real (mas ItemType podrian añadirse aqui si sistemas
-- confirma otros via javap).
local KNOWN_NON_FOOD_ITEM_TYPES = toSet({ "base:literature" })

-- dev17 (hallazgo de sistemas sobre dev16): "Base.RyeSeed -> food_drink/
-- other_food, alternativa: survival_outdoors/farming - RyeSeed debería
-- ganar Agricultura". Confirmado leyendo items.txt real del juego:
-- Base.RyeSeed tiene `ItemType=base:food` (por eso Alimentos lo reclamaba)
-- PERO TAMBIÉN `Tags=base:isseed` (además `CantEat=true`,
-- `AnimalFeedType=Seeds`) - una semilla real para plantar, no un alimento.
-- Confirmado a la vez que Base.SeedPaste (harina de semilla molida, sí
-- comestible de verdad - Calories/Lipids reales, SIN `base:isseed`) no
-- lleva ese tag - la regla NO agrupa "contiene la palabra seed", usa la
-- señal oficial exacta que los distingue. Mismo patrón que
-- KNOWN_NON_FOOD_ITEM_TYPES pero por TAG en vez de por ItemType.

-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev9): ver
-- CURRENT.md/dev9 - falsos positivos claros por subcadena libre. Solo
-- aplica cuando la identidad NO está confirmada por ItemType (un radio-
-- aficionado real nunca tiene ItemType=base:food, así que esta lista nunca
-- excluye comida genuina).
local FOOD_EXCLUDE_TOKENS = toSet({
	"radio", "certificate", "tire", "knife", "cleaver", "spray",
	"maker", "machine", "vending", "mov", "dung", "skull", "head", "seed",
})

---@param tokens string[]
---@return string|nil l2
---@return string|nil weakSource
local function matchL2(tokens)
	for i = 1, #L2_RULES do
		local rule = L2_RULES[i]
		if U.hasAnyToken(tokens, rule.tokens) then
			return rule.l2, rule.weakSource
		end
	end
	return nil, nil
end

---@param fullType string
---@param si table|nil
---@return table|nil primaryPath
---@return table|nil facets
---@return table|nil attributes
---@return table|nil evidence
local function classifyFood(fullType, si)
	if not si or isWearable(si) then return nil end

	-- dev16 (política explícita del usuario, 2026-08-27: "un contenedor
	-- vacío se define por su contenedor, un contenedor lleno se define por
	-- su contenido" - si buscamos gasolina no queremos un bidón vacío que
	-- PUEDA contener gasolina, pero si buscamos un bidón sí lo queremos
	-- vacío). "Empty" en el nombre es una señal ESTÁTICA real (fullTypes
	-- distintos - Base.BeerEmpty vs Base.Beer, nunca el mismo tipo con
	-- estado mutable) - nunca comida/bebida, siempre cede a Contenedores
	-- (GS_NativeClassifierContainers.lua, registrado al final de la
	-- cadena). Se comprueba ANTES incluso de la identidad confirmada por
	-- ItemType - un envase vacío nunca debería tener ItemType=base:food de
	-- todos modos, pero la regla es honesta en cualquier caso.
	if U.hasAnyToken(U.tokenize(U.typeName(si)), { empty = true }) then
		return nil
	end

	-- dev17: veto por tag oficial confirmado - una semilla real para
	-- plantar nunca es Alimentos, sea cual sea su ItemType. Se comprueba
	-- ANTES de la identidad confirmada por ItemType (RyeSeed es
	-- ItemType=base:food Y base:isseed a la vez - la señal de "es semilla"
	-- gana).
	local isSeedTag = U.tagByLocation("base", "isseed")
	if isSeedTag and U.hasTag(si, isSeedTag) then
		return nil
	end

	local itemType = U.itemTypeLower(si)
	local isConfirmedFood = itemType == "base:food"

	-- Veto por clase tecnica conocida y contradictoria (dev15) - ver
	-- KNOWN_NON_FOOD_ITEM_TYPES arriba. Se comprueba ANTES que cualquier
	-- heuristica de nombre, no solo antes del match de L2.
	if not isConfirmedFood and KNOWN_NON_FOOD_ITEM_TYPES[itemType] then
		return nil
	end

	if not isConfirmedFood then
		-- Blindaje generico: un arma real (Base.SpearSteakKnife, Base.
		-- MeatCleaverForged...) nunca deberia perder frente a una
		-- coincidencia de nombre de Alimentos - getWeaponCategories() no
		-- vacio es una señal mas fuerte y generica que enumerar cada
		-- palabra ambigua a mano. Nunca se aplica si ItemType ya confirmo
		-- comida real (ningun arma real tiene ItemType=base:food).
		local weaponCats = U.getWeaponCategories(si)
		if weaponCats and weaponCats.isEmpty and U.safeCall(function() return weaponCats:isEmpty() end) == false then
			return nil
		end
	end

	local tokens = U.tokenize(U.typeName(si))
	if not isConfirmedFood then
		if #tokens == 0 then return nil end
		if U.hasAnyToken(tokens, FOOD_EXCLUDE_TOKENS) then return nil end
	end

	local l2, weakSource = matchL2(tokens)
	-- `isSpice()` es un getter oficial del ScriptItem, confirmado en B42. Es una
	-- señal estática más fuerte que los tokens y evita instanciar objetos.
	if U.safeCall(function() return si:isSpice() end) == true then
		return { l1 = "food_drink", l2 = "ingredient", l3 = "spice" }, {}, {},
			U.evidence("script_item_is_spice", 100)
	end

	if isConfirmedFood then
		-- dev15 (hallazgo de sistemas): "usar ItemType como identidad
		-- primaria generica introduce un comodin enganoso" - defaultear a
		-- "ingredient" afirmaba un SUBTIPO concreto sin evidencia real (puede
		-- ser conserva, plato preparado, alimento crudo, bebida...).
		-- "other_food" separa la certeza de L1 (confirmada por ItemType,
		-- confianza 100) de la certeza de L2 (sin evidencia, honesto).
		return { l1 = "food_drink", l2 = l2 or "other_food", l3 = nil }, {}, {}, U.evidence("script_item_type", 100)
	end

	if l2 then
		return { l1 = "food_drink", l2 = l2, l3 = nil }, {}, {}, U.evidence(weakSource, 30)
	end

	return nil
end

GlobalStorageSiK.NativeClassifier.registerBlock(classifyFood, "food_drink")

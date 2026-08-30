--[[
	GlobalStorageSiK - Clasificador de bloque: Conocimiento y medios
	Autor: SiK
	Fecha: 2026-08-27

	dev9: pedido explícito del usuario ("añade los bloques restantes... mejor
	hacerlo mal e ir arreglando"). Registrado ANTES que Electrónica/
	Vehículos/Supervivencia y Hogar-ocio: una revista de radioaficionado
	(RadioMag1) es Literatura antes que Comunicación, y una cinta VHS es un
	medio grabado antes que un objeto de colección genérico.

	dev14 (probe controlado de sistemas, confirmado via javap sobre
	projectzomboid.jar): `si:getItemType()` confirma `Base.RecipeClipping`
	como `base:literature` (con `ReadType=photo`/`DisplayCategory=
	RecipeResource` en los scripts generados) - identidad real, no una
	entidad interna de receta. Cuando `itemTypeLower(si) == "base:literature"`,
	el sub-tipo (L2) sube a confianza 100 si además coincide una palabra real.

	dev15 (regresión real confirmada por sistemas sobre dev14): "numerosos
	paquetes de semillas son técnicamente base:literature, pero para un
	acumulador pertenecen a Agricultura" - el motor asigna ese ItemType de
	forma mucho más amplia de lo asumido (cualquier objeto que pueda
	"enseñar" algo, incluidas bolsas de semillas con información de
	temporada). El default anterior ("sin palabra reconocida, cae a
	literature genérico") CONVERTÍA esa amplitud en un comodín que robaba
	~120 tipos a Supervivencia/Agricultura. Corregido: `base:literature`
	SIN una palabra de conocimiento real que lo acompañe ya NO se clasifica
	aquí - se deja pasar para que un bloque de identidad más específico
	(Supervivencia, registrado después) lo reclame. Solo si NINGÚN otro
	bloque lo reclama existe un último recurso honesto, ver
	`GS_NativeClassifierKnowledgeFallback.lua` (registrado al final de
	todos, junto a Contenedores/Materiales débiles).

	Objetos EQUIPABLES se excluyen (mismo criterio que el resto de bloques
	débiles).
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

local SKILL_BOOK_TOKENS = toSet({ "skillbook" })
-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev9): "mag"/
-- "magazine" solos capturaban TODAS las revistas como recipe_magazine,
-- incluidas las de tema general - separado en temas de receta/oficio
-- confirmados (recipe_magazine) vs. "magazine"/"mag" sueltos sin tema
-- confirmado (general_magazine, honesto). "clipping" (RecipeClipping)
-- cuenta como receta real.
local RECIPE_TOPIC_TOKENS = toSet({
	"recipe", "clipping", "carpentry", "electrician", "farming",
	"glassmaking", "primitivetool", "cooking", "metalworking",
	"tailoring", "mechanic", "foraging",
})
local GENERIC_MAGAZINE_TOKENS = toSet({ "magazine", "mag" })
local LITERATURE_TOKENS = toSet({ "book", "novel", "comic" })
local DOCUMENT_TOKENS = toSet({ "document", "note", "letter" })
local RECORDED_MEDIA_TOKENS = toSet({ "vhs", "cd", "dvd", "cassette" })
local RECORDED_MEDIA_DEVICE_TOKENS = toSet({ "player", "radio", "television", "tv", "stereo" })

--- Los manuales propios son revistas de receta por contrato del producto, no
--- literatura genérica. La identidad estable combina el namespace/marcador
--- propio, `DisplayCategory=RecipeResource` y `base:magazine`; no depende
--- del título traducido ni de que Kahlua exponga `getLearnedRecipes()`.
local function isGsRecipeManual(fullType, si)
	local ownManual = type(fullType) == "string"
		and (string.find(fullType, "^GlobalStorageSiK%.GS_Manual_")
			or string.find(fullType, "^GSSiK_Addon_[A-Za-z]+%.GS_Manual_")) ~= nil
	if not ownManual then return false end
	-- El namespace y prefijo propios son el marcador versionado que controla
	-- GS. DisplayCategory y el tag magazine no son estables en todos los
	-- ScriptItem de TEST; exigirlos degradaba manuales válidos a literatura.
	return U.itemTypeLower(si) == "base:literature"
end

local function hasSkillTraining(si)
	local skill = U.safeCall(function() return si:getSkillTrained() end)
	if skill == nil then return false end
	local text = tostring(skill)
	return text ~= "" and text ~= "None" and text ~= "nil"
end

local function hasLearnedRecipes(si)
	local recipes = U.safeCall(function() return si:getLearnedRecipes() end)
	if recipes == nil then return false end
	if type(recipes) == "table" then return #recipes > 0 end
	local size = U.safeCall(function() return recipes:size() end)
	return type(size) == "number" and size > 0
end

-- Orden fijo: { l2, tokens, fuente-débil }. Mismo recorrido tanto si la
-- identidad viene confirmada por ItemType como si viene solo por nombre.
local L2_RULES = {
	{ l2 = "skill_book", tokens = SKILL_BOOK_TOKENS, weakSource = "name_knowledge_skill_book" },
	{ l2 = "recipe_magazine", tokens = RECIPE_TOPIC_TOKENS, weakSource = "name_knowledge_recipe_magazine" },
	{ l2 = "general_magazine", tokens = GENERIC_MAGAZINE_TOKENS, weakSource = "name_knowledge_general_magazine" },
	{ l2 = "literature", tokens = LITERATURE_TOKENS, weakSource = "name_knowledge_literature" },
	{ l2 = "document", tokens = DOCUMENT_TOKENS, weakSource = "name_knowledge_document" },
	{ l2 = "recorded_media", tokens = RECORDED_MEDIA_TOKENS, weakSource = "name_knowledge_recorded_media" },
}

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
local function classifyKnowledgeMedia(fullType, si)
	if not si or isWearable(si) then return nil end
	if isGsRecipeManual(fullType, si) then
		return { l1 = "knowledge_media", l2 = "recipe_magazine", l3 = nil }, {}, {},
			U.evidence("gs_recipe_manual_structural", 100)
	end
	local recordedMediaCat = si.getRecordedMediaCat
		and U.safeCall(function() return si:getRecordedMediaCat() end) or nil
	if recordedMediaCat and tostring(recordedMediaCat) ~= "" then
		return { l1 = "knowledge_media", l2 = "recorded_media", l3 = nil }, {}, {},
			U.evidence("script_recorded_media_category", 100)
	end

	local isConfirmedLiterature = U.itemTypeLower(si) == "base:literature"
	local tokens = U.tokenize(U.typeName(si))
	-- Las bolsas de semillas B42 son literatura porque su etiqueta enseña la
	-- temporada de cultivo, pero su identidad de producto es farming. Tanto
	-- Gardening como RecipeResource aparecen en variantes llenas/vacías; la
	-- combinación estructural `base:literature` + bag/seed debe llegar al
	-- bloque Survival antes que la regla genérica de recetas.
	if isConfirmedLiterature and U.hasAnyToken(tokens, { seed = true })
		and U.hasAnyToken(tokens, { bag = true, packet = true }) then
		return nil
	end
	if isConfirmedLiterature and hasSkillTraining(si) then
		return { l1 = "knowledge_media", l2 = "skill_book", l3 = nil }, {}, {},
			U.evidence("script_skill_trained", 100)
	end
	if isConfirmedLiterature and (hasLearnedRecipes(si) or U.displayCategoryLower(si) == "reciperesource") then
		return { l1 = "knowledge_media", l2 = "recipe_magazine", l3 = nil }, {}, {},
			U.evidence("script_recipe_resource", 100)
	end

	if not isConfirmedLiterature then
		-- Blindaje generico (hallazgo de sistemas: Base.LetterOpener caia
		-- como "document" por el token "letter" - es un arma real, tiene
		-- WeaponCategory). Nunca se aplica si ItemType ya confirmo
		-- literatura real.
		local weaponCats = U.getWeaponCategories(si)
		if weaponCats and weaponCats.isEmpty and U.safeCall(function() return weaponCats:isEmpty() end) == false then
			return nil
		end
	end

	if not isConfirmedLiterature and #tokens == 0 then return nil end

	local l2, weakSource = matchL2(tokens)
	if l2 == "recorded_media" and U.hasAnyToken(tokens, RECORDED_MEDIA_DEVICE_TOKENS) then
		return nil
	end

	-- dev15: SIN palabra real, un base:literature confirmado ya NO se
	-- clasifica aqui - se cede el turno (ver cabecera del fichero).
	if not l2 then return nil end

	if isConfirmedLiterature then
		return { l1 = "knowledge_media", l2 = l2, l3 = nil }, {}, {}, U.evidence("script_item_type", 100)
	end

	return { l1 = "knowledge_media", l2 = l2, l3 = nil }, {}, {}, U.evidence(weakSource, 30)
end

GlobalStorageSiK.NativeClassifier.registerBlock(classifyKnowledgeMedia, "knowledge_media")

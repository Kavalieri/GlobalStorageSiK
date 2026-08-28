--[[
	GlobalStorageSiK - Runner del corpus ground-truth de la taxonomia nativa
	Autor: SiK
	Fecha: 2026-08-27

	dev24 (pedido explicito de sistemas): suite DIFERENCIADA de la auditoria
	completa (GS_NativeAudit.lua) - compara el resultado REAL de
	NativeClassifier.classify() contra el corpus declarativo de
	GS_NativeTaxonomy_GroundTruth.lua, caso a caso. Herramienta DEV/admin
	explicita (mismo criterio que GS_NativeAudit.lua, §8.1/§11 del documento
	de taxonomia) - NUNCA se ejecuta automaticamente en el arranque normal.

	Politica required/optional/missing (contrato exacto pedido por
	sistemas): un caso cuyo `fullType` NO existe en el catalogo real de esta
	partida (mod no instalado, item renombrado/eliminado) es "missing".
	- presence="required" y missing -> cuenta como FALLIDO (absentCases).
	- presence="optional" y missing -> cuenta como OMITIDO, NUNCA como
	  fallo (skippedCases) - ninguno de los dos suma a `applicableCases`.

	Metricas: NUNCA se llama "precision"/"recall" a un porcentaje que no
	corresponda matematicamente a esas metricas (pedido explicito de
	sistemas) - aqui solo se reportan conteos y "exactitud" simple
	(aciertos/aplicables) por nivel L1/L2/L3, mas los 4 tipos de fallo
	distinguidos (clasificacion falsa-positiva, falsa-negativa, evidencia,
	facets/attributes). La representatividad del corpus frente al catalogo
	completo (7.600 tipos) es responsabilidad de quien lo interpreta, no de
	este runner - el corpus piloto de dev24 es deliberadamente pequeño.
]]

require "GS_CatalogManager"
require "GS_NativeClassifier"
require "GS_NativeTaxonomy_GroundTruth"
require "GS_I18n"
require "GS_Libs"
require "GS_NativeClassifierOwnItems"
require "GS_NativeClassifierUtils"

-- dev26 (pedido explicito de sistemas: "generalizar el mecanismo de DEV25
-- para poder calcular tools sin codigo especifico duplicado... la
-- definicion de umbrales debe ser declarativa por bloque, no una cadena de
-- if block == ..."). Cada entrada declara los umbrales de SU bloque -
-- computeBlockAcceptance() (mas abajo) es generico y nunca menciona un
-- nombre de bloque por su nombre propio.
--
-- minCorpusCases: casos autorados para el bloque (aplicables+ausentes+
--   omitidos) por debajo de esto -> REVIEW, cobertura insuficiente todavia
--   demostrada (nunca FAIL - la infraestructura puede ser correcta con un
--   corpus parcial).
-- requireOwnItemsCrossCheck: solo el bloque propio (globalstoragesik) tiene
--   una tabla EXACT contra la que cruzar - los demas bloques no la tienen,
--   por eso es opcional y no generico.
-- minCollisionsReviewed / minModdedReviewed: cobertura minima de casos
--   marcados `collisionWith`/`moddedOrigin` en el ground-truth (dev26,
--   Herramientas: colisiones con Combate/Materiales, objetos modded) - por
--   debajo de esto -> REVIEW, igual que minCorpusCases.
local BLOCK_ACCEPTANCE_CONFIG = {
	globalstoragesik = {
		minCorpusCases = 44,
		requireOwnItemsCrossCheck = true,
	},
	-- dev26.1 (correccion de fallo bloqueante: dev26 declaraba
	-- collisionsReviewed=10 como si fuera la lista COMPLETA de colisiones,
	-- pero el inventario completo real de 114 items muestra 98 con algun
	-- alternativo - la muestra de 20 del audit log nunca fue universo
	-- fiable). requireFullCollisionCoverage=true compara contra el
	-- universo REAL calculado por computeCollisionUniverse() en cada
	-- ejecucion, nunca contra un numero fijo adivinado - si el corpus no
	-- cubre TODO el universo real, el bloque queda en REVIEW (cobertura
	-- insuficiente), nunca se declara PASS con una cobertura falseada.
	-- minModdedReviewed sigue siendo un numero fijo porque SI viene de
	-- metadata explicita y verificada (investigacion real de sistemas de
	-- los scripts de MWPWeapons42, nunca de la heuristica module==Base).
	tools = {
		minCorpusCases = 75,
		requireFullCollisionCoverage = true,
		minModdedReviewed = 10,
		fullInventory = true,
	},
	-- dev27: mismo mecanismo generalizado, 3 bloques nuevos (Combate, Ropa/
	-- Proteccion, Contenedores). minModdedReviewed solo se exige donde hay
	-- metadata investigada real que lo permita - el unico mod de Workshop
	-- instalado (MWPWeapons42) solo aporta armas/herramientas; Ropa y
	-- Contenedores no tienen ningun modded confirmado en este modset, asi
	-- que exigir un minimo aqui forzaria a inventar procedencia (prohibido,
	-- ver resolveHonestOrigin) - quedan honestamente sin ese umbral, la
	-- ausencia de mods se documenta en CURRENT.md, nunca se finge.
	combat = {
		minCorpusCases = 75,
		requireFullCollisionCoverage = true,
		minModdedReviewed = 10,
		fullInventory = true,
	},
	clothing_protection = {
		minCorpusCases = 100,
		requireFullCollisionCoverage = true,
		fullInventory = true,
	},
	containers = {
		minCorpusCases = 100,
		requireFullCollisionCoverage = true,
		fullInventory = true,
	},
}

-- dev26 (pedido explicito de sistemas §1: "incorporar al informe del
-- corpus una seccion tecnica completa para tools... el volumen es pequeño:
-- deben aparecer los 114 reclamados, no una muestra de 20"). Tags oficiales
-- conocidos por ESTE runner para mostrar en el inventario - los mismos 21
-- nombres reales que usa GS_NativeClassifierTools.lua, nunca una lista
-- inventada. Reutilizada aqui SOLO para diagnostico/inventario, nunca para
-- decidir clasificacion (eso sigue siendo responsabilidad exclusiva del
-- propio bloque).
local KNOWN_TOOL_TAG_NAMES = {
	"SAW", "SMALL_SAW", "CARPENTRY_CHISEL", "BLOW_TORCH", "METALWORKING_CHISEL",
	"MASONS_CHISEL", "PLASTER_TROWEL", "WRENCH", "PIPE_WRENCH", "LUG_WRENCH",
	"PLIERS", "TONGS", "SCREWDRIVER", "SEWING_NEEDLE", "KNITTING_NEEDLES",
	"HAMMER", "SLEDGEHAMMER", "SHARP_KNIFE", "KNAPPING_TOOL", "FLESHING_TOOL",
	"FISHING_ROD", "FISHING_NET",
}

GlobalStorageSiK.NativeCorpus = GlobalStorageSiK.NativeCorpus or {}

local U = GlobalStorageSiK.NativeClassifierUtils

local REPORT_FILE_NAME = "GlobalStorageSiK_NativeCorpus.log"

-- dev24.2 (fallo bloqueante confirmado por sistemas sobre dev24.1): el
-- probe anterior escribia literales Lua no-ASCII ("señal", "§2", "风。")
-- directamente en el codigo fuente de este fichero - la corrupcion (U+FFFD
-- literal) ya estaba presente ANTES de que asciiSafeEscape() viera el
-- texto, confirmado porque asciiSafeEscape() recibia ya U+FFFD/U+0002 en
-- vez del codepoint real. El escritor (getFileWriter) deja de ser
-- sospechoso - el problema esta en como Kahlua/el parser Lua de PZ carga
-- literales de cadena no-ASCII desde el fichero fuente.
--
-- Correccion: los 4 casos del probe se construyen aqui EN RUNTIME a partir
-- de PUNTOS DE CODIGO NUMERICOS explicitos (solo digitos ASCII en el
-- fuente, sin ningun literal no-ASCII que el parser pueda corromper) via
-- string.char() - "no asumir que string.char acepta codepoints completos
-- sin comprobarlo" (pedido explicito de sistemas): por eso el propio
-- informe registra los codepoints REALMENTE OBSERVADOS tras construir la
-- cadena (via GlobalStorageSiK.Libs.unicodeCodepoints, ya usado y probado
-- en el resto del mod para CJK) antes de intentar cualquier escape - si
-- string.char no reprodujo el codepoint pedido, se vera aqui directamente,
-- nunca oculto detras de un escape que ya recibio datos corruptos.
local UNICODE_PROBE_CASES = {
	{ caseId = "accent_senial", codepoints = { 0x0073, 0x0065, 0x00F1, 0x0061, 0x006C }, expectedEscaped = "se\\u00F1al" },
	{ caseId = "symbol_section", codepoints = { 0x00A7, 0x0032 }, expectedEscaped = "\\u00A72" },
	{ caseId = "cjk_feng_ideographic_period", codepoints = { 0x98CE, 0x3002 }, expectedEscaped = "\\u98CE\\u3002" },
	-- dev24.2 §5: caso suplementario (>U+FFFF) construido como par
	-- sustituto valido - U+1F600 (GRINNING FACE), fuera del BMP, confirma
	-- el camino \u{XXXXX} de asciiSafeEscape() con un codepoint real.
	{ caseId = "supplementary_grinning_face", codepoints = { 0x1F600 }, expectedEscaped = "\\u{1F600}" },
}

--- Construye una cadena Kahlua a partir de codepoints Unicode EXPLICITOS -
--- nunca desde un literal de fuente. Para BMP (<=0xFFFF) usa string.char()
--- directo (coherente con la premisa ya documentada en GS_Libs.lua de que
--- string.byte/string.char operan sobre unidades UTF-16, no bytes UTF-8);
--- para fuera del BMP construye el par sustituto alto+bajo manualmente,
--- exactamente el inverso de GlobalStorageSiK.Libs.unicodeCodepoints().
---@param codepoints number[]
---@return string
local function buildStringFromCodepoints(codepoints)
	local parts = {}
	for i = 1, #codepoints do
		local cp = codepoints[i]
		if cp <= 0xFFFF then
			parts[#parts + 1] = string.char(cp)
		else
			local v = cp - 0x10000
			local high = 0xD800 + math.floor(v / 0x400)
			local low = 0xDC00 + (v % 0x400)
			parts[#parts + 1] = string.char(high) .. string.char(low)
		end
	end
	return table.concat(parts)
end

--- true si la lista de codepoints observados contiene evidencia de
--- corrupcion: U+FFFD real, un sustituto UTF-16 aislado (alto sin bajo o
--- viceversa - unicodeCodepoints() ya los deja sueltos si estan huerfanos)
--- o un caracter de control inesperado (fuera de los esperados por este
--- probe, que no usa ninguno). Pedido explicito de sistemas §6: el
--- resultado agregado debe fallar tambien ante esto, no solo ante U+FFFD.
---@param codepoints number[]
---@return boolean
local function hasCorruptionSentinel(codepoints)
	for i = 1, #codepoints do
		local cp = codepoints[i]
		if cp == 0xFFFD then return true end
		if cp >= 0xD800 and cp <= 0xDFFF then return true end
		if cp < 0x20 then return true end
	end
	return false
end

--- true si el TEXTO ESCAPADO contiene la secuencia ASCII literal "�"
--- (4 caracteres ASCII backslash-u-F-F-F-D) - pedido explicito de
--- sistemas: "tambien deben rechazarse las secuencias ASCII �", no
--- solo el caracter real U+FFFD (ya cubierto por hasCorruptionSentinel
--- sobre los codepoints de ENTRADA, esto cubre el caso de que la
--- corrupcion ya escapada se cuele en la SALIDA).
---@param escaped string
---@return boolean
local function escapedTextHasFFFDSentinel(escaped)
	return tostring(escaped or ""):find("\\uFFFD", 1, true) ~= nil
end

--- Ejecuta los 4 casos del probe Unicode y devuelve el detalle completo +
--- un booleano agregado. Nunca depende de literales de fuente no-ASCII ni
--- de las notas humanas del corpus (dev24.2 §7).
---@return table[] results { caseId, codepointsObserved, escaped, matchExpected, corruptionDetected }
---@return boolean allPass
local function runUnicodeProbe()
	local results = {}
	local allPass = true
	for i = 1, #UNICODE_PROBE_CASES do
		local case = UNICODE_PROBE_CASES[i]
		local built = buildStringFromCodepoints(case.codepoints)
		local observed = GlobalStorageSiK.Libs.unicodeCodepoints(built, 32)
		local escaped = GlobalStorageSiK.Libs.asciiSafeEscape(built)
		local corrupted = hasCorruptionSentinel(observed) or escapedTextHasFFFDSentinel(escaped)
		local matches = (escaped == case.expectedEscaped) and not corrupted
		if not matches then allPass = false end
		results[#results + 1] = {
			caseId = case.caseId,
			codepointsExpected = case.codepoints,
			codepointsObserved = observed,
			escaped = escaped,
			expectedEscaped = case.expectedEscaped,
			corruptionDetected = corrupted,
			match = matches,
		}
	end
	return results, allPass
end

---@param n number|nil
---@return string
local function fmt(n)
	return tostring(n or 0)
end

--- Normaliza el sentinel `false` usado por el ground truth para expresar que
--- L3 debe estar ausente. Evita el falso ternario `cond and nil or value`,
--- que en Lua recupera `value` porque nil es falsy.
---@param case table entrada de GS_NativeTaxonomyGroundTruth.cases
---@return string|nil expectedL3
local function getExpectedL3(case)
	local expectedL3 = case.expectedL3
	if case.expectAbstain or expectedL3 == false then
		return nil
	end
	return expectedL3
end

--- Compara un unico caso ya confirmado presente (`si` no nil) contra el
--- resultado real de NativeClassifier.classify() - NUNCA decide presencia
--- (eso ya lo resolvio el llamador), solo evalua la expectativa.
---@param case table entrada de GS_NativeTaxonomyGroundTruth.cases
---@param result table NativeClassificationResult real
---@return boolean pass
---@return string[] reasons lista de motivos de fallo (vacia si pass)
---@return string kind "classification"|"evidence"|"facetAttribute"|"" - primer motivo de fallo relevante para las metricas agregadas
local function evaluateCase(case, result)
	local reasons = {}
	local kind = ""
	local path = (result and result.primaryPath) or {}

	if case.expectAbstain then
		local isAbstain = (path.l1 == "other" and path.l2 == "unclassified_modded")
		if not isAbstain then
			reasons[#reasons + 1] = "se esperaba abstencion (other/unclassified_modded), obtenido "
				.. tostring(path.l1) .. "/" .. tostring(path.l2) .. "/" .. tostring(path.l3)
			kind = "classification"
		end
	else
		local expectedL3 = getExpectedL3(case)
		if path.l1 ~= case.expectedL1 then
			reasons[#reasons + 1] = "L1 esperado=" .. tostring(case.expectedL1) .. " obtenido=" .. tostring(path.l1)
			kind = "classification"
		end
		if case.expectedL2 ~= nil and path.l2 ~= case.expectedL2 then
			reasons[#reasons + 1] = "L2 esperado=" .. tostring(case.expectedL2) .. " obtenido=" .. tostring(path.l2)
			kind = "classification"
		end
		if case.expectedL3 ~= nil and path.l3 ~= expectedL3 then
			reasons[#reasons + 1] = "L3 esperado=" .. tostring(expectedL3) .. " obtenido=" .. tostring(path.l3)
			kind = "classification"
		end
	end

	local primaryEv = result and result.evidence and result.evidence.primary
	if case.minConfidence then
		local confidence = (primaryEv and primaryEv.confidence) or 0
		if confidence < case.minConfidence then
			reasons[#reasons + 1] = "confianza=" .. tostring(confidence) .. " < minima=" .. tostring(case.minConfidence)
			if kind == "" then kind = "evidence" end
		end
	end
	if case.expectedSource then
		local source = primaryEv and primaryEv.source
		if source ~= case.expectedSource then
			reasons[#reasons + 1] = "source esperado=" .. tostring(case.expectedSource) .. " obtenido=" .. tostring(source)
			if kind == "" then kind = "evidence" end
		end
	end

	if case.expectFacets then
		for facetKey, facetValue in pairs(case.expectFacets) do
			local actual = result and result.facets and result.facets[facetKey]
			if actual ~= facetValue then
				reasons[#reasons + 1] = "facet " .. tostring(facetKey) .. " esperado=" .. tostring(facetValue) .. " obtenido=" .. tostring(actual)
				if kind == "" then kind = "facetAttribute" end
			end
		end
	end
	if case.expectAttributes then
		for attrKey, attrValue in pairs(case.expectAttributes) do
			local actual = result and result.attributes and result.attributes[attrKey]
			if tostring(actual) ~= tostring(attrValue) then
				reasons[#reasons + 1] = "attribute " .. tostring(attrKey) .. " esperado=" .. tostring(attrValue) .. " obtenido=" .. tostring(actual)
				if kind == "" then kind = "facetAttribute" end
			end
		end
	end

	return #reasons == 0, reasons, kind
end

-- dev25 (pedido explicito de sistemas, §3: "auditoria bidireccional del
-- bloque propio"): 2 comprobaciones independientes de la evaluacion normal
-- caso-a-caso (que ya cubre "groundTruth -> catalogo/clasificador"):
-- (a) todo fullType del mapa exacto propio (GS_NativeClassifierOwnItems.
--     getOwnItemsExactTable()) tiene un caso en el corpus - "mapa exacto
--     propio -> groundTruth".
-- (b) todo caso del corpus que afirma la fuente "exact_fulltype_own_item"
--     tiene de verdad una entrada en el mapa exacto - "groundTruth -> mapa
--     exacto propio".
-- NUNCA corrige nada solo, solo reporta - "no corregir automaticamente el
-- corpus desde el mapping" (pedido explicito).
---@param cases table[] GlobalStorageSiK.NativeTaxonomyGroundTruth.cases
---@return table exactWithoutCase[] fullTypes del mapa exacto sin caso en el corpus
---@return table caseWithoutExact[] caseId de casos exact_fulltype_own_item sin mapping real
local function computeOwnItemsCrossCheck(cases)
	local exactTable = GlobalStorageSiK.NativeClassifier.getOwnItemsExactTable
		and GlobalStorageSiK.NativeClassifier.getOwnItemsExactTable() or {}
	local caseFullTypesByBlock = {}
	for i = 1, #cases do
		if cases[i].block == "globalstoragesik" then
			caseFullTypesByBlock[cases[i].fullType] = true
		end
	end

	local exactWithoutCase = {}
	for fullType in pairs(exactTable) do
		if not caseFullTypesByBlock[fullType] then
			exactWithoutCase[#exactWithoutCase + 1] = fullType
		end
	end

	local caseWithoutExact = {}
	for i = 1, #cases do
		local case = cases[i]
		if case.expectedSource == "exact_fulltype_own_item" and not exactTable[case.fullType] then
			caseWithoutExact[#caseWithoutExact + 1] = tostring(case.caseId or case.fullType)
		end
	end

	return exactWithoutCase, caseWithoutExact
end

-- dev25/dev26 (pedido explicito de sistemas §2/§4: "resumen estructurado
-- por bloque... generalizar el mecanismo... nunca una cadena de
-- if block == ..."): funcion UNICA y GENERICA para cualquier bloque
-- listado en BLOCK_ACCEPTANCE_CONFIG - nunca menciona un nombre de bloque
-- por su nombre propio, toda diferencia de criterio viene de `config`.
--
-- Separacion de severidad: cualquier discrepancia de CORRECCION real
-- (required ausente, ruta L1/L2/L3 incorrecta, facet/attribute incorrecta,
-- cross-check del mapa propio roto) es FAIL SIEMPRE. Cualquier hueco de
-- COBERTURA declarado en `config` (corpus por debajo del minimo acordado,
-- colisiones/objetos modded insuficientemente revisados) es REVIEW SI Y
-- SOLO SI no hay ademas ningun FAIL - un bloque con errores reales nunca
-- se queda en REVIEW solo porque tambien le falte cobertura.
---@param blockName string
---@param stats table blockStats de report.byBlock[blockName]
---@param config table entrada de BLOCK_ACCEPTANCE_CONFIG[blockName]
---@param crossCheck table|nil { exactWithoutCase, caseWithoutExact } - solo si config.requireOwnItemsCrossCheck
---@return string status "PASS"|"REVIEW"|"FAIL"
---@return string[] reasons
local function computeBlockAcceptance(blockName, stats, config, crossCheck)
	local failReasons, reviewReasons = {}, {}

	if stats.absent > 0 then
		failReasons[#failReasons + 1] = "requiredMissing=" .. tostring(stats.absent) .. " (caso required ausente del catalogo)"
	end
	if stats.l1Total > 0 and stats.l1Correct < stats.l1Total then
		failReasons[#failReasons + 1] = "L1 incorrecto en " .. tostring(stats.l1Total - stats.l1Correct) .. " caso(s)"
	end
	if stats.l2Total > 0 and stats.l2Correct < stats.l2Total then
		failReasons[#failReasons + 1] = "L2 incorrecto en " .. tostring(stats.l2Total - stats.l2Correct) .. " caso(s)"
	end
	if stats.l3Total > 0 and stats.l3Correct < stats.l3Total then
		failReasons[#failReasons + 1] = "L3 incorrecto en " .. tostring(stats.l3Total - stats.l3Correct) .. " caso(s) de los declarados"
	end
	if stats.facetAttributeChecks > 0 and stats.facetAttributeCorrect < stats.facetAttributeChecks then
		failReasons[#failReasons + 1] = "facet/attribute incorrecto en " .. tostring(stats.facetAttributeChecks - stats.facetAttributeCorrect) .. " comprobacion(es)"
	end
	if crossCheck then
		local exactWithoutCase, caseWithoutExact = crossCheck[1], crossCheck[2]
		if #exactWithoutCase > 0 then
			failReasons[#failReasons + 1] = "mapping propio sin caso en el corpus: " .. table.concat(exactWithoutCase, ", ")
		end
		if #caseWithoutExact > 0 then
			failReasons[#failReasons + 1] = "caso exact_fulltype_own_item sin mapping real: " .. table.concat(caseWithoutExact, ", ")
		end
	end

	local corpusExpected = stats.applicable + stats.absent + stats.skipped
	if config.minCorpusCases and corpusExpected < config.minCorpusCases then
		reviewReasons[#reviewReasons + 1] = "corpus con " .. tostring(corpusExpected) .. " casos, por debajo del minimo acordado (" .. tostring(config.minCorpusCases) .. ")"
	end
	-- dev26.1: denominador REAL (universo calculado por
	-- computeCollisionUniverse sobre el inventario completo), nunca un
	-- numero fijo adivinado - ver stats.collisionUniverseTotal, poblado en
	-- run() solo si config.requireFullCollisionCoverage.
	if config.requireFullCollisionCoverage then
		local universe = stats.collisionUniverseTotal or 0
		local reviewed = stats.collisionsReviewed or 0
		if universe > 0 and reviewed < universe then
			reviewReasons[#reviewReasons + 1] = "colisiones revisadas=" .. tostring(reviewed) .. "/" .. tostring(universe)
				.. " (universo real calculado sobre el inventario completo, no cubierto al 100%)"
		end
	end
	if config.minModdedReviewed and (stats.moddedReviewed or 0) < config.minModdedReviewed then
		reviewReasons[#reviewReasons + 1] = "objetos modded revisados=" .. tostring(stats.moddedReviewed or 0) .. ", por debajo del minimo acordado (" .. tostring(config.minModdedReviewed) .. ")"
	end

	if #failReasons > 0 then
		return "FAIL", failReasons
	end
	if #reviewReasons > 0 then
		return "REVIEW", reviewReasons
	end
	return "PASS", { "corpus completo segun el minimo acordado, todos los required presentes, 100% L1/L2, 100% de los L3 declarados, facetas/atributos correctos, cero fallos criticos" }
end

-- dev26 (pedido explicito de sistemas §1: "seccion tecnica completa para
-- tools, ordenada por fullType... deben aparecer los 114 reclamados, no
-- una muestra de 20"). UN solo recorrido de getAllItems() (mismo costo que
-- GS_NativeAudit.lua) - calcula, para CADA bloque de BLOCK_ACCEPTANCE_CONFIG,
-- cuantos tipos reclama de verdad hoy el clasificador (`claimed`), y para
-- los bloques con `fullInventory=true` un listado COMPLETO sin muestreo:
-- fullType, ruta L1/L2/L3, tags oficiales conocidos presentes, categorias
-- de arma, fuente/confianza, facets/attributes, alternativas de otros
-- bloques (colision), y si es vanilla o modded (por el modulo del fullType).
-- Inventario de REVISION, nunca ground-truth generado (pedido explicito).
-- dev26.1 (punto #6 de sistemas: reconciliar 112 investigados vs 114
-- reclamados en runtime). Explicacion honesta, sin poder ejecutar el
-- juego para confirmarla mas alla: el 112 vino de un grep estatico
-- (agente Explore, ronda dev26) sobre los .txt de scripts de vanilla +
-- MWPWeapons42 buscando los 9 grupos de ItemTag de TAG_RULES - un metodo
-- de texto, no ejecuta getScriptManager() real y puede perder items
-- registrados via herencia de plantilla, alias, o cualquier variante que
-- el patron de grep no cubriera. El 114 viene de getAllItems() en
-- caliente, que es la MISMA fuente que usa el clasificador real en
-- juego - es la cifra autoritativa, no el grep. No se investiga mas la
-- diferencia de 2 items en este parche (fuera del alcance de dev26.1,
-- que no toca clasificadores/cobertura) - el inventario completo de 114
-- (ver mas abajo) es lo que QA debe inspeccionar, no el conteo estatico.
---@param blockConfigs table BLOCK_ACCEPTANCE_CONFIG
---@return table<string, number> claimedByBlock
---@return table<string, table[]> inventoryByBlock (solo bloques con fullInventory=true)
-- dev26.1 (fallo bloqueante confirmado por sistemas sobre dev26): el
-- inventario marcaba "vanilla" a cualquier fullType con `module=="Base"` -
-- FALSO, varios items reales de un mod (MWPWeapons42) se registran bajo el
-- modulo Base y son indistinguibles por nombre de modulo. "El modulo Lua no
-- prueba procedencia Workshop" (cita literal de sistemas). Corregido:
-- procedencia SOLO se afirma si viene de metadata explicita y verificada -
-- el mapping `moddedOrigin` ya curado a mano en el ground-truth (dev26,
-- investigacion real de los scripts de cada mod, nunca inferido del
-- nombre del modulo). Fuera de esa lista: `module=="Base"` -> honesto
-- "base_module_unknown" (no podemos afirmar vanilla ni modded); cualquier
-- otro modulo real -> "external_module:<modulo>" (un modulo QUE NO ES Base
-- si es evidencia real de que no es contenido base del juego).
---@param cases table[] GlobalStorageSiK.NativeTaxonomyGroundTruth.cases
---@return table<string,string> fullType -> moddedOrigin conocido
local function buildModdedOriginLookup(cases)
	local lookup = {}
	for i = 1, #cases do
		if cases[i].moddedOrigin then
			lookup[cases[i].fullType] = cases[i].moddedOrigin
		end
	end
	return lookup
end

---@param fullType string
---@param module string
---@param moddedOriginLookup table<string,string>
---@return string origin "base_module_unknown"|"external_module:<modulo>"|<moddedOrigin del corpus>
local function resolveHonestOrigin(fullType, module, moddedOriginLookup)
	local known = moddedOriginLookup[fullType]
	if known then return known end
	if module == "Base" then return "base_module_unknown" end
	return "external_module:" .. module
end

-- dev26.1 (fallo bloqueante confirmado por sistemas: "collisionsReviewed=10
-- se presento como la lista COMPLETA de colisiones, pero el propio
-- inventario de 114 ya mostraba alternates no vacios=98" - la muestra
-- historica de 20 del audit log nunca fue un universo fiable). Cuenta,
-- sobre el inventario COMPLETO ya escaneado, cuantos items tienen algun
-- bloque alternativo (otro bloque tambien los habria reclamado), y hacia
-- que bloques concretos - denominador REAL para collisionsReviewed, nunca
-- mas una cifra fija adivinada.
---@param inventory table[]
---@return table { withAnyAlternate=, withMultipleAlternates=, towardBlock={blockName->count} }
local function computeCollisionUniverse(inventory)
	local stats = { withAnyAlternate = 0, withMultipleAlternates = 0, towardBlock = {} }
	for i = 1, #inventory do
		local alternates = inventory[i].alternates
		if #alternates > 0 then
			stats.withAnyAlternate = stats.withAnyAlternate + 1
			if #alternates > 1 then
				stats.withMultipleAlternates = stats.withMultipleAlternates + 1
			end
			local seenBlocks = {}
			for a = 1, #alternates do
				local otherBlock = alternates[a]:match("^([^:]+):")
				if otherBlock and not seenBlocks[otherBlock] then
					seenBlocks[otherBlock] = true
					stats.towardBlock[otherBlock] = (stats.towardBlock[otherBlock] or 0) + 1
				end
			end
		end
	end
	return stats
end

---@param blockConfigs table BLOCK_ACCEPTANCE_CONFIG
---@param moddedOriginLookup table<string,string>
---@return table<string, number> claimedByBlock
---@return table<string, table[]> inventoryByBlock (solo bloques con fullInventory=true)
---@return table<string, table> collisionUniverseByBlock (solo bloques con fullInventory=true)
local function scanCatalogForBlocks(blockConfigs, moddedOriginLookup)
	local claimedByBlock = {}
	local inventoryByBlock = {}
	for blockName, config in pairs(blockConfigs) do
		claimedByBlock[blockName] = 0
		if config.fullInventory then
			inventoryByBlock[blockName] = {}
		end
	end

	if not getAllItems then
		return claimedByBlock, inventoryByBlock, {}
	end
	local ok, items = pcall(getAllItems)
	if not ok or not items then
		return claimedByBlock, inventoryByBlock, {}
	end

	local total = items:size()
	for i = 0, total - 1 do
		local si = items:get(i)
		local okFt, fullType = pcall(function() return si:getFullName() end)
		if okFt and fullType then
			local result = GlobalStorageSiK.NativeClassifier.classify(fullType)
			local path = result and result.primaryPath
			local l1 = path and path.l1
			if l1 and claimedByBlock[l1] ~= nil then
				claimedByBlock[l1] = claimedByBlock[l1] + 1
				local inventory = inventoryByBlock[l1]
				if inventory then
					local matchedTags = {}
					for t = 1, #KNOWN_TOOL_TAG_NAMES do
						local tagName = KNOWN_TOOL_TAG_NAMES[t]
						local tag = ItemTag and ItemTag[tagName]
						if tag and U.hasTag(si, tag) then
							matchedTags[#matchedTags + 1] = tagName
						end
					end
					local weaponCats = U.getWeaponCategories(si)
					local weaponCatText = "none"
					if weaponCats and U.safeCall(function() return weaponCats:isEmpty() end) == false then
						weaponCatText = U.safeCall(function() return tostring(weaponCats) end) or "?"
					end
					local primaryEv = result.evidence and result.evidence.primary
					local allClaims = GlobalStorageSiK.NativeClassifier.diagnosticClassifyAllBlocks(fullType)
					local alternates = {}
					for c = 1, #allClaims do
						local cp = allClaims[c].primaryPath or {}
						if cp.l1 ~= path.l1 or cp.l2 ~= path.l2 or cp.l3 ~= path.l3 then
							alternates[#alternates + 1] = allClaims[c].blockName .. ":" .. tostring(cp.l1) .. "/" .. tostring(cp.l2) .. "/" .. tostring(cp.l3)
						end
					end
					local module = fullType:match("^([^.]+)%.") or "?"
					inventory[#inventory + 1] = {
						fullType = fullType,
						module = module,
						origin = resolveHonestOrigin(fullType, module, moddedOriginLookup),
						l1 = path.l1, l2 = path.l2, l3 = path.l3,
						matchedTags = matchedTags,
						weaponCategories = weaponCatText,
						source = (primaryEv and primaryEv.source) or "?",
						confidence = (primaryEv and primaryEv.confidence) or 0,
						facets = result.facets or {},
						attributes = result.attributes or {},
						alternates = alternates,
					}
				end
			end
		end
	end

	local collisionUniverseByBlock = {}
	for blockName, inventory in pairs(inventoryByBlock) do
		table.sort(inventory, function(a, b) return a.fullType < b.fullType end)
		collisionUniverseByBlock[blockName] = computeCollisionUniverse(inventory)
	end

	return claimedByBlock, inventoryByBlock, collisionUniverseByBlock
end

--- Ejecuta el corpus completo. Debe llamarse explicitamente (comando de
--- debug/admin, ver GS_NativeCorpusServer.lua) - nunca desde OnGameBoot.
---@return table report
function GlobalStorageSiK.NativeCorpus.run()
	local cases = GlobalStorageSiK.NativeTaxonomyGroundTruth.cases or {}
	local report = {
		ranAt = (getTimestampMs and getTimestampMs()) or 0,
		corpusVersion = GlobalStorageSiK.NativeTaxonomyGroundTruth.VERSION,
		ready = GlobalStorageSiK.CatalogManager.isReady(),
		sealed = GlobalStorageSiK.NativeClassifier.isSealed(),
		catalogEpoch = GlobalStorageSiK.CatalogManager.getEpoch(),
		totalCases = #cases,
		applicableCases = 0,
		absentCases = 0,   -- presence=required, missing -> cuenta como fallo
		skippedCases = 0,  -- presence=optional, missing -> NUNCA fallo
		passedCases = 0,
		failedCases = 0,
		-- "exactitud" simple (aciertos/aplicables), nunca precision/recall.
		l1CorrectCount = 0, l1Total = 0,
		l2CorrectCount = 0, l2Total = 0,
		l3CorrectCount = 0, l3Total = 0,
		classificationFailures = 0,   -- falso positivo (se esperaba abstencion) o falso negativo (se esperaba clasificar)
		evidenceFailures = 0,         -- confianza/source por debajo/distinto de lo esperado
		facetAttributeFailures = 0,
		-- dev24.1 (observacion no bloqueante de sistemas: "failed=1 con
		-- clasificacion/evidencia/facet a cero es coherente pero conviene
		-- que se vea claramente requiredMissingFailures=1, para que la suma
		-- de causas sea inmediatamente comprensible"): contador propio,
		-- SUMA junto a los otros 3 para dar failedCases - nunca solapado.
		requiredMissingFailures = 0,
		byBlock = {},   -- block -> { applicable=, absent=, skipped=, passed=, failed= }
		divergences = {},   -- detalle SOLO para el fichero server-side, nunca enviado por red
		-- dev27: matriz cruzada de colisiones (§5) - "winnerBlock|alternativeBlock" -> stats.
		collisionPairStats = {},
		timeMs = 0,
	}

	if not report.ready or not report.sealed then
		report.aborted = true
		report.abortReason = not report.ready and "catalog_not_ready" or "blocks_not_sealed"
		return report
	end

	local startMs = (getTimestampMs and getTimestampMs()) or 0

	for i = 1, #cases do
		local case = cases[i]
		local block = case.block or "?"
		local blockStats = report.byBlock[block]
		if not blockStats then
			-- dev25: contadores propios por bloque (antes solo global) -
			-- necesarios para declarar PASS/REVIEW/FAIL con denominadores
			-- reales de ESE bloque, no del corpus entero.
			blockStats = {
				applicable = 0, absent = 0, skipped = 0, passed = 0, failed = 0,
				l1Correct = 0, l1Total = 0, l2Correct = 0, l2Total = 0,
				l3Correct = 0, l3Total = 0,
				facetAttributeChecks = 0, facetAttributeCorrect = 0,
				criticalFailures = 0,
				-- dev26: cobertura de casos marcados collisionWith/moddedOrigin
				-- en el ground-truth - solo se cuentan si el caso ademas paso
				-- (un caso en colision marcado pero que falla no "revisa" nada
				-- de forma fiable).
				collisionsReviewed = 0, moddedReviewed = 0,
			}
			report.byBlock[block] = blockStats
		end

		local si = GlobalStorageSiK.I18n.getScriptItem and GlobalStorageSiK.I18n.getScriptItem(case.fullType)
		if not si then
			if case.presence == "optional" then
				report.skippedCases = report.skippedCases + 1
				blockStats.skipped = blockStats.skipped + 1
				report.divergences[#report.divergences + 1] =
					tostring(case.caseId or case.fullType) .. " (" .. case.fullType .. ") -> OMITIDO (optional, ausente del catalogo real) [block=" .. tostring(block) .. "]"
			else
				report.absentCases = report.absentCases + 1
				report.failedCases = report.failedCases + 1
				report.requiredMissingFailures = report.requiredMissingFailures + 1
				blockStats.absent = blockStats.absent + 1
				blockStats.failed = blockStats.failed + 1
				blockStats.criticalFailures = blockStats.criticalFailures + 1
				report.divergences[#report.divergences + 1] =
					tostring(case.caseId or case.fullType) .. " (" .. case.fullType .. ") -> FALLO (required, ausente del catalogo real) [block=" .. tostring(block) .. "]"
			end
		else
			report.applicableCases = report.applicableCases + 1
			blockStats.applicable = blockStats.applicable + 1

			local result = GlobalStorageSiK.NativeClassifier.classify(case.fullType)
			local path = (result and result.primaryPath) or {}
			local expectedL1 = case.expectAbstain and "other" or case.expectedL1
			local expectedL2 = case.expectAbstain and "unclassified_modded" or case.expectedL2
			report.l1Total = report.l1Total + 1
			blockStats.l1Total = blockStats.l1Total + 1
			local l1Ok = path.l1 == expectedL1
			if l1Ok then
				report.l1CorrectCount = report.l1CorrectCount + 1
				blockStats.l1Correct = blockStats.l1Correct + 1
			end
			if expectedL2 ~= nil then
				report.l2Total = report.l2Total + 1
				blockStats.l2Total = blockStats.l2Total + 1
				if path.l2 == expectedL2 then
					report.l2CorrectCount = report.l2CorrectCount + 1
					blockStats.l2Correct = blockStats.l2Correct + 1
				end
			end
			if case.expectedL3 ~= nil or case.expectAbstain then
				local expectedL3 = getExpectedL3(case)
				report.l3Total = report.l3Total + 1
				blockStats.l3Total = blockStats.l3Total + 1
				if path.l3 == expectedL3 then
					report.l3CorrectCount = report.l3CorrectCount + 1
					blockStats.l3Correct = blockStats.l3Correct + 1
				end
			end

			-- dev25: conteo de comprobaciones facet/attribute POR BLOQUE,
			-- independiente de evaluateCase() (que solo agrega el resultado
			-- global pass/fail) - necesario para el campo
			-- facetAttributeChecks/facetAttributeCorrect del resumen de
			-- aceptacion por bloque.
			if case.expectFacets then
				for facetKey, facetValue in pairs(case.expectFacets) do
					blockStats.facetAttributeChecks = blockStats.facetAttributeChecks + 1
					if result and result.facets and result.facets[facetKey] == facetValue then
						blockStats.facetAttributeCorrect = blockStats.facetAttributeCorrect + 1
					end
				end
			end
			if case.expectAttributes then
				for attrKey, attrValue in pairs(case.expectAttributes) do
					blockStats.facetAttributeChecks = blockStats.facetAttributeChecks + 1
					if result and result.attributes and tostring(result.attributes[attrKey]) == tostring(attrValue) then
						blockStats.facetAttributeCorrect = blockStats.facetAttributeCorrect + 1
					end
				end
			end

			local pass, reasons, kind = evaluateCase(case, result)
			-- dev27 (§5, matriz cruzada de colisiones pedida por sistemas):
			-- acumula por pareja (bloque ganador real del corpus / bloque
			-- alternativo declarado en collisionWith) - reviewedCount = casos
			-- del corpus que prueban esa pareja; criticalCount = los mismos
			-- (todo caso de colision curado a mano se trata como caso critico
			-- de precedencia); criticalFailures = cuantos de esos fallaron.
			-- count (cuantos objetos reales del catalogo tienen esa pareja) se
			-- rellena mas abajo desde collisionUniverseByBlock, no aqui.
			if case.collisionWith then
				local pairKey = tostring(block) .. "|" .. tostring(case.collisionWith)
				local pairStats = report.collisionPairStats[pairKey]
				if not pairStats then
					pairStats = { winnerBlock = block, alternativeBlock = case.collisionWith, reviewedCount = 0, criticalCount = 0, criticalFailures = 0 }
					report.collisionPairStats[pairKey] = pairStats
				end
				pairStats.reviewedCount = pairStats.reviewedCount + 1
				pairStats.criticalCount = pairStats.criticalCount + 1
				if not pass then pairStats.criticalFailures = pairStats.criticalFailures + 1 end
			end
			if pass then
				report.passedCases = report.passedCases + 1
				blockStats.passed = blockStats.passed + 1
				if case.collisionWith then blockStats.collisionsReviewed = blockStats.collisionsReviewed + 1 end
				if case.moddedOrigin then blockStats.moddedReviewed = blockStats.moddedReviewed + 1 end
			else
				report.failedCases = report.failedCases + 1
				blockStats.failed = blockStats.failed + 1
				blockStats.criticalFailures = blockStats.criticalFailures + 1
				if kind == "classification" then
					report.classificationFailures = report.classificationFailures + 1
				elseif kind == "evidence" then
					report.evidenceFailures = report.evidenceFailures + 1
				elseif kind == "facetAttribute" then
					report.facetAttributeFailures = report.facetAttributeFailures + 1
				end
				report.divergences[#report.divergences + 1] =
					tostring(case.caseId or case.fullType) .. " (" .. case.fullType .. ") -> FALLO: " .. table.concat(reasons, " | ") .. " [block=" .. tostring(block) .. "]"
			end
		end
	end

	-- dev26: UN recorrido del catalogo completo, reutilizado para "claimed"
	-- (cuantos tipos reclama HOY el clasificador de ese bloque) y el
	-- inventario completo sin muestreo de los bloques que lo piden
	-- (fullInventory=true en BLOCK_ACCEPTANCE_CONFIG).
	local moddedOriginLookup = buildModdedOriginLookup(cases)
	local claimedByBlock, inventoryByBlock, collisionUniverseByBlock = scanCatalogForBlocks(BLOCK_ACCEPTANCE_CONFIG, moddedOriginLookup)
	report.blockInventories = inventoryByBlock
	report.collisionUniverseByBlock = collisionUniverseByBlock

	-- dev27: rellena "count" real (cuantos objetos del catalogo tienen esa
	-- pareja ganador/alternativo) en la matriz de colisiones, usando el
	-- mismo universo REAL ya calculado por bloque - nunca una cifra
	-- adivinada. Crea la fila si el corpus no la habia revisado todavia
	-- (reviewedCount=0 es honesto: universo real detectado, sin cobertura
	-- de corpus curada aun para esa pareja concreta).
	for winnerBlock, universe in pairs(collisionUniverseByBlock) do
		for alternativeBlock, count in pairs(universe.towardBlock) do
			local pairKey = tostring(winnerBlock) .. "|" .. tostring(alternativeBlock)
			local pairStats = report.collisionPairStats[pairKey]
			if not pairStats then
				pairStats = { winnerBlock = winnerBlock, alternativeBlock = alternativeBlock, reviewedCount = 0, criticalCount = 0, criticalFailures = 0 }
				report.collisionPairStats[pairKey] = pairStats
			end
			pairStats.count = count
		end
	end

	-- dev25/dev26: resumen de aceptacion PASS/REVIEW/FAIL por bloque, solo
	-- para los bloques listados en BLOCK_ACCEPTANCE_CONFIG - generico,
	-- nunca un bloque mencionado por su nombre propio fuera de la config.
	report.blockAcceptance = {}
	for blockName, config in pairs(BLOCK_ACCEPTANCE_CONFIG) do
		local stats = report.byBlock[blockName]
		if stats then
			stats.claimed = claimedByBlock[blockName] or 0
			if config.requireFullCollisionCoverage then
				local universe = collisionUniverseByBlock[blockName]
				stats.collisionUniverseTotal = universe and universe.withAnyAlternate or 0
			end
			local crossCheck = nil
			if config.requireOwnItemsCrossCheck then
				local exactWithoutCase, caseWithoutExact = computeOwnItemsCrossCheck(cases)
				crossCheck = { exactWithoutCase, caseWithoutExact }
				report.ownItemsExactWithoutCase = exactWithoutCase
				report.ownItemsCaseWithoutExact = caseWithoutExact
			end
			local status, reasons = computeBlockAcceptance(blockName, stats, config, crossCheck)
			report.blockAcceptance[blockName] = { status = status, reasons = reasons, stats = stats }
			if status ~= "PASS" then
				for i = 1, #reasons do
					report.divergences[#report.divergences + 1] =
						"[block-status] " .. blockName .. " -> " .. status .. ": " .. tostring(reasons[i])
				end
			end
		end
	end

	-- dev24.2: probe Unicode ejecutado SIEMPRE (no gateado, mismo criterio
	-- que el resto de esta herramienta de diagnostico) - construido desde
	-- codepoints explicitos, ver runUnicodeProbe() arriba.
	report.unicodeProbeResults, report.unicodeProbePassed = runUnicodeProbe()

	report.timeMs = ((getTimestampMs and getTimestampMs()) or 0) - startMs
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.info("NativeCorpus",
			string.format(
				"corpus: version=%s total=%d aplicables=%d ausentes=%d omitidos=%d aprobados=%d fallidos=%d tiempo=%dms",
				tostring(report.corpusVersion), report.totalCases, report.applicableCases, report.absentCases,
				report.skippedCases, report.passedCases, report.failedCases, report.timeMs))
	end
	return report
end

--- Escribe el informe COMPLETO (con la lista detallada de divergencias) a
--- fichero server-side - mismo patron que GS_NativeAudit.writeReportToFile,
--- fichero PROPIO y distinto (nunca mezclado con el de la auditoria de
--- catalogo completo).
---@param report table
function GlobalStorageSiK.NativeCorpus.writeReportToFile(report)
	if not getFileWriter then
		return false
	end
	local fileName = (report and report.diagnosticReportFile) or REPORT_FILE_NAME
	local ok, writer = pcall(getFileWriter, fileName, true, false)
	if not ok or not writer then
		return false
	end
	local okWrite = pcall(function()
		writer:write("=== GlobalStorageSiK NativeCorpus ===\r\n")
		if report.aborted then
			writer:write("ABORTADO: " .. tostring(report.abortReason) .. "\r\n")
			return
		end
		writer:write("corpusVersion=" .. tostring(report.corpusVersion)
			.. " catalogEpoch=" .. fmt(report.catalogEpoch) .. "\r\n")
		writer:write("totalCases=" .. fmt(report.totalCases)
			.. " applicable=" .. fmt(report.applicableCases)
			.. " absent(required)=" .. fmt(report.absentCases)
			.. " skipped(optional)=" .. fmt(report.skippedCases)
			.. " passed=" .. fmt(report.passedCases)
			.. " failed=" .. fmt(report.failedCases)
			.. " tiempoMs=" .. fmt(report.timeMs) .. "\r\n")
		writer:write("exactitud L1=" .. fmt(report.l1CorrectCount) .. "/" .. fmt(report.l1Total)
			.. " L2=" .. fmt(report.l2CorrectCount) .. "/" .. fmt(report.l2Total)
			.. " L3=" .. fmt(report.l3CorrectCount) .. "/" .. fmt(report.l3Total) .. "\r\n")
		writer:write("fallos por tipo: clasificacion=" .. fmt(report.classificationFailures)
			.. " evidencia=" .. fmt(report.evidenceFailures)
			.. " facet/attribute=" .. fmt(report.facetAttributeFailures)
			.. " ausenciaObligatoria=" .. fmt(report.requiredMissingFailures) .. "\r\n")
		writer:write("--- Resumen por bloque ---\r\n")
		for block, stats in pairs(report.byBlock or {}) do
			writer:write("  " .. tostring(block) .. ": aplicables=" .. fmt(stats.applicable)
				.. " ausentes=" .. fmt(stats.absent) .. " omitidos=" .. fmt(stats.skipped)
				.. " aprobados=" .. fmt(stats.passed) .. " fallidos=" .. fmt(stats.failed) .. "\r\n")
		end
		-- dev25 (pedido explicito de sistemas, §2 - campos exactos): resumen
		-- de aceptacion PASS/REVIEW/FAIL con denominadores reales, solo para
		-- los bloques con umbral formal esta ronda (globalstoragesik).
		writer:write("--- Aceptacion por bloque (PASS/REVIEW/FAIL) ---\r\n")
		for block, acceptance in pairs(report.blockAcceptance or {}) do
			local stats = acceptance.stats
			writer:write("block=" .. tostring(block) .. "\r\n")
			writer:write("  claimed=" .. fmt(stats.claimed) .. "\r\n")
			writer:write("  corpusExpected=" .. fmt(stats.applicable + stats.absent + stats.skipped)
				.. " corpusApplicable=" .. fmt(stats.applicable)
				.. " requiredMissing=" .. fmt(stats.absent) .. "\r\n")
			writer:write("  l1Correct=" .. fmt(stats.l1Correct) .. "/" .. fmt(stats.l1Total)
				.. " l2Correct=" .. fmt(stats.l2Correct) .. "/" .. fmt(stats.l2Total)
				.. " l3Expected=" .. fmt(stats.l3Total) .. " l3Correct=" .. fmt(stats.l3Correct) .. "\r\n")
			writer:write("  facetAttributeChecks=" .. fmt(stats.facetAttributeChecks)
				.. " facetAttributeCorrect=" .. fmt(stats.facetAttributeCorrect) .. "\r\n")
			writer:write("  collisionsReviewed=" .. fmt(stats.collisionsReviewed)
				.. " moddedReviewed=" .. fmt(stats.moddedReviewed)
				.. " criticalFailures=" .. fmt(stats.criticalFailures) .. "\r\n")
			writer:write("  status=" .. tostring(acceptance.status) .. "\r\n")
			for i = 1, #(acceptance.reasons or {}) do
				writer:write("  statusReasons[" .. tostring(i) .. "]=" .. GlobalStorageSiK.Libs.asciiSafeEscape(acceptance.reasons[i]) .. "\r\n")
			end
			if block == "globalstoragesik" then
				writer:write("  ownItemsExactWithoutCase=[" .. table.concat(report.ownItemsExactWithoutCase or {}, ", ") .. "]\r\n")
				writer:write("  ownItemsCaseWithoutExact=[" .. table.concat(report.ownItemsCaseWithoutExact or {}, ", ") .. "]\r\n")
			end
		end
		-- dev26 (pedido explicito de sistemas §1: inventario tecnico COMPLETO,
		-- sin muestreo, ordenado por fullType - solo para bloques con
		-- fullInventory=true, esta ronda unicamente "tools"). Inventario de
		-- REVISION, nunca ground-truth generado.
		for block, inventory in pairs(report.blockInventories or {}) do
			writer:write("--- Inventario completo del bloque " .. tostring(block) .. " (" .. fmt(#inventory) .. " tipos, sin muestreo) ---\r\n")
			for i = 1, #inventory do
				local item = inventory[i]
				writer:write("  " .. item.fullType
					.. " modulo=" .. tostring(item.module)
					.. " origin=" .. tostring(item.origin)
					.. " ruta=" .. tostring(item.l1) .. "/" .. tostring(item.l2) .. "/" .. tostring(item.l3)
					.. " tags=[" .. table.concat(item.matchedTags, ",") .. "]"
					.. " weaponCategories=" .. tostring(item.weaponCategories)
					.. " source=" .. tostring(item.source) .. " confidence=" .. fmt(item.confidence)
					.. " facets=[" .. table.concat((function() local k={} for f in pairs(item.facets) do k[#k+1]=f end return k end)(), ",") .. "]"
					.. " alternates=[" .. table.concat(item.alternates, ", ") .. "]\r\n")
			end
		end
		-- dev26.1 (pedido explicito de sistemas §2: informar por separado
		-- objetos con cualquier alternativo, colisiones con Combat, colisiones
		-- con Materials, y objetos con mas de un alternativo - universo REAL
		-- calculado sobre el inventario completo, nunca la muestra de 10
		-- casos curados del corpus).
		for block, universe in pairs(report.collisionUniverseByBlock or {}) do
			writer:write("--- Universo de colisiones del bloque " .. tostring(block) .. " (calculado sobre el inventario completo) ---\r\n")
			writer:write("  conCualquierAlternativo=" .. fmt(universe.withAnyAlternate)
				.. " conMasDeUnAlternativo=" .. fmt(universe.withMultipleAlternates) .. "\r\n")
			for otherBlock, count in pairs(universe.towardBlock) do
				writer:write("  hacia:" .. tostring(otherBlock) .. "=" .. fmt(count) .. "\r\n")
			end
		end
		-- dev27 (§5, matriz cruzada de colisiones pedida por sistemas):
		-- winnerBlock/alternativeBlock/count(real, universo completo)/
		-- reviewedCount(corpus)/criticalCount/criticalFailures - nunca solo
		-- un numero agregado.
		writer:write("--- Matriz cruzada de colisiones (winnerBlock/alternativeBlock/count/reviewedCount/criticalCount/criticalFailures) ---\r\n")
		for _, pairStats in pairs(report.collisionPairStats or {}) do
			writer:write("  " .. tostring(pairStats.winnerBlock) .. "->" .. tostring(pairStats.alternativeBlock)
				.. " count=" .. fmt(pairStats.count or 0)
				.. " reviewedCount=" .. fmt(pairStats.reviewedCount)
				.. " criticalCount=" .. fmt(pairStats.criticalCount)
				.. " criticalFailures=" .. fmt(pairStats.criticalFailures) .. "\r\n")
		end
		-- dev24.2 (corrige el fallo bloqueante de dev24.1: el probe anterior
		-- usaba literales de fuente no-ASCII, que ya llegaban corruptos
		-- antes de asciiSafeEscape() - ver runUnicodeProbe() arriba, ahora
		-- construido desde codepoints numericos explicitos). Registra,
		-- POR CASO: caseId ASCII estable, codepoints esperados Y
		-- observados tras construir la cadena, texto escapado, y
		-- match=true/false contra el valor esperado exacto - nunca solo
		-- "no contiene U+FFFD" (insuficiente, pedido explicito de
		-- sistemas: tambien deben rechazarse � como texto ASCII y
		-- sustitutos aislados).
		writer:write("--- Probe Unicode (codepoints explicitos, ver GS_NativeCorpus.lua:runUnicodeProbe) ---\r\n")
		local probeResults, probePassed = report.unicodeProbeResults, report.unicodeProbePassed
		writer:write("  resultadoAgregado=" .. (probePassed and "PASS" or "FAIL") .. "\r\n")
		for i = 1, #(probeResults or {}) do
			local r = probeResults[i]
			local expectedCp, observedCp = {}, {}
			for j = 1, #r.codepointsExpected do expectedCp[j] = string.format("U+%04X", r.codepointsExpected[j]) end
			for j = 1, #r.codepointsObserved do observedCp[j] = string.format("U+%04X", r.codepointsObserved[j]) end
			writer:write("  caseId=" .. tostring(r.caseId)
				.. " codepointsExpected=[" .. table.concat(expectedCp, " ") .. "]"
				.. " codepointsObserved=[" .. table.concat(observedCp, " ") .. "]"
				.. " escaped=" .. tostring(r.escaped)
				.. " expectedEscaped=" .. tostring(r.expectedEscaped)
				.. " corruptionDetected=" .. tostring(r.corruptionDetected)
				.. " match=" .. tostring(r.match) .. "\r\n")
		end
		writer:write("--- Divergencias detalladas, texto escapado a ASCII reversible (solo en este fichero, nunca enviadas por red) ---\r\n")
		for i = 1, #(report.divergences or {}) do
			writer:write("  " .. GlobalStorageSiK.Libs.asciiSafeEscape(report.divergences[i]) .. "\r\n")
		end
	end)
	writer:close()
	return okWrite
end

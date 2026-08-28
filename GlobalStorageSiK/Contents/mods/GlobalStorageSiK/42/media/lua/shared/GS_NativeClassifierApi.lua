--[[
	GlobalStorageSiK - Contrato de clasificacion nativa (NativeClassifier)
	Autor: SiK
	Fecha: 2026-08-27

	Primera pieza de codigo real de la taxonomia nativa, tras cerrar el
	ciclo de cache por epoca (GS_CatalogManager.createEpochCache, ver
	GS_I18n.lua) y fijar el registro L1/L2/L3 (GS_NativeTaxonomyRegistry.lua).

	Implementa el contrato de datos de
	Documentacion/GSSiK_Taxonomia_Nativa_Analisis.md §6-7:
	- NativeClassificationResult: cacheable, ASCII puro, nunca instancia
	  objetos moddeados, nunca depende de si hay mod de categorias externo.
	- ClassificationView: envuelve el nativo POR REFERENCIA + external/
	  projection - nunca cacheado como unidad junto al nativo.
	- ClassificationDiagnostics: NUNCA parte permanente de la vista, solo se
	  construye bajo auditoria/debug (ver GS_NativeAudit.lua).

	SEPARADO de GS_NativeClassifier.lua en dev8 (hallazgo de sistemas: avisos
	"recursive require" en consola) - este fichero es SOLO el contrato
	(registerBlock/classify/sealBlocks...), sin requerir ningun bloque de
	clasificacion concreto. Cada bloque (GS_NativeClassifierCombat.lua...)
	requiere ESTE fichero para llamar a registerBlock() en su carga; el
	agregador GS_NativeClassifier.lua requiere este fichero Y ADEMAS todos
	los bloques, en el orden de precedencia real. Sin esta separacion, un
	bloque que hiciera `require "GS_NativeClassifier"` (el agregador)
	disparaba un ciclo real: agregador -> bloque -> agregador (todavia a
	medio cargar) - mismo patron ya resuelto para GS_ContextMenu.lua/
	GS_TerminalUI_Api.lua.
]]

require "GS_CatalogManager"
require "GS_NativeTaxonomyRegistry"

GlobalStorageSiK.NativeClassifier = GlobalStorageSiK.NativeClassifier or {}

--- NativeClassificationCache (§8.2 dominio 2): fullType -> NativeClassificationResult.
--- Epoch-cache reutilizable (GS_CatalogManager.createEpochCache) - se vacia
--- por completo en cada cambio real de catalogEpoch, correcto por
--- construccion, sin bookkeeping por entrada.
local classificationCache = GlobalStorageSiK.CatalogManager.createEpochCache()

-- Contadores de producto DEV30. Son deliberadamente escalares y se reinician
-- con catalogEpoch: permiten demostrar que una apertura/filtro/sort posterior
-- reutiliza el resultado canónico sin guardar referencias de diagnóstico.
local metrics = {
	requests = 0,
	effectiveClassifications = 0,
	cacheHits = 0,
	pendingRequests = 0,
	invalidRequests = 0,
}

local function resetMetrics()
	metrics.requests = 0
	metrics.effectiveClassifications = 0
	metrics.cacheHits = 0
	metrics.pendingRequests = 0
	metrics.invalidRequests = 0
end

GlobalStorageSiK.CatalogManager.onEpochChanged(resetMetrics)

--- Lista ordenada de clasificadores por bloque, registrados por cada ronda
--- de implementacion (Combate, Herramientas, Materiales...). Cada
--- clasificador es function(fullType, scriptItem) -> primaryPath, facets,
--- attributes, evidence | nil (nil si no le corresponde clasificar este
--- fullType - el siguiente clasificador de la lista lo intenta). Se prueban
--- en el orden de registro, nunca en paralelo ni por prioridad implicita.
local blockClassifiers = {}
--- Nombre legible de cada bloque (mismo indice que blockClassifiers) - solo
--- para diagnostico (auditoria, errores) - nunca decide nada por si mismo.
local blockNames = {}

-- BUG REAL cerrado (2026-08-27, hallazgo del equipo de sistemas):
-- registerBlock() no invalidaba clasificaciones ya calculadas - un
-- fullType clasificado como "unclassified_modded" ANTES de que su bloque
-- real se registrara se quedaba asi hasta el siguiente cambio de epoch,
-- aunque el bloque correcto ya estuviera disponible. Fase explicita de
-- registro (registerBlock) + sello (sealBlocks): classify() se niega a
-- clasificar (y sobre todo a CACHEAR) nada hasta que todos los bloques
-- de esta sesion esten registrados y el dispatcher este sellado - evita
-- por completo la invalidacion repetida en vez de intentar detectarla.
local sealed = false

--- Registra un clasificador de bloque (llamado desde el fichero propio de
--- cada bloque, p.ej. GS_NativeClassifierCombat.lua cuando se implemente -
--- este fichero de contrato nunca conoce blocks concretos por adelantado,
--- coherente con la frontera Core/addon ya establecida en el resto del mod).
--- Debe llamarse ANTES de sealBlocks() - registrar despues de sellar es un
--- error de programacion (orden de requires/inicializacion incorrecto) y se
--- ignora con un aviso, nunca se acepta en caliente.
---@param fn fun(fullType:string, scriptItem:table|nil): table|nil, table|nil, table|nil, table|nil
---@param name string|nil nombre legible para diagnostico (p.ej. "materials") - opcional, cae a "block#N" si se omite
function GlobalStorageSiK.NativeClassifier.registerBlock(fn, name)
	if sealed then
		if GlobalStorageSiK.Log then
			GlobalStorageSiK.Log.warn("NativeClassifier", "registerBlock llamado tras sealBlocks() - ignorado")
		end
		return
	end
	if type(fn) == "function" then
		blockClassifiers[#blockClassifiers + 1] = fn
		blockNames[#blockClassifiers] = type(name) == "string" and name or ("block#" .. tostring(#blockClassifiers))
	end
end

--- SOLO DIAGNOSTICO - nombre legible de cada bloque en orden de registro.
---@return string[]
function GlobalStorageSiK.NativeClassifier.getBlockNames()
	return blockNames
end

--- Cierra la fase de registro - a partir de aqui, classify() puede
--- clasificar y cachear de verdad. Debe llamarse una unica vez, despues de
--- que todos los ficheros de bloque hayan tenido ocasion de registrarse
--- (mismo momento que GS_CatalogManager.markReady, ver Events.OnGameBoot
--- mas abajo - todos los require de bloque ya se han ejecutado para
--- entonces, coherente con como el resto del mod usa OnGameBoot como
--- barrera de "todo el catalogo/registro ya esta listo").
function GlobalStorageSiK.NativeClassifier.sealBlocks()
	sealed = true
end

---@return boolean
function GlobalStorageSiK.NativeClassifier.isSealed()
	return sealed
end

---@param l1 string
---@param l2 string|nil
---@param l3 string|nil
---@return table
local function buildPrimaryPath(l1, l2, l3)
	return { l1 = l1, l2 = l2, l3 = l3 }
end

--- Construye el NativeClassificationResult final para un fullType, a partir
--- de lo que devuelva el primer clasificador de bloque que reclame el tipo.
--- Nunca instancia el objeto (los clasificadores de bloque reciben el
--- ScriptItem ya resuelto via GlobalStorageSiK.I18n.getScriptItem, misma
--- fuente unica de siempre - nunca sm:getItem a pelo).
-- BUG REAL cerrado (2026-08-27, hallazgo del equipo de sistemas):
-- "classifierErrors todavia no es una metrica fiable" - una excepcion real
-- dentro de un bloque (pcall con ok=false) simplemente pasaba al siguiente
-- clasificador sin dejar rastro; si ninguno reclamaba el tipo despues, el
-- resultado final era indistinguible de "unclassified_modded" normal - el
-- auditor nunca podria contarlo como classifierErrors ni mostrar una
-- muestra. Ahora cada excepcion se recuerda (mensaje + indice de bloque) y,
-- si al final ningun bloque reclamo el tipo, el resultado se marca
-- explicitamente como error de clasificador (campo `classifierError`,
-- evidence describe el mensaje real) en vez de caer en el mismo cajon que
-- "todavia no hay bloque para esto".
---@param fullType string
---@return table result NativeClassificationResult, "other/unclassified_modded" si ningun bloque reclama el tipo (y ninguno fallo)
local function computeClassification(fullType)
	local scriptItem = GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.getScriptItem
		and GlobalStorageSiK.I18n.getScriptItem(fullType)

	-- dev14 (hallazgo de sistemas): "BaseScriptObject, padre del ScriptItem,
	-- expone isDebugOnly() - ya existe una señal oficial para al menos una
	-- parte de los tipos internos/de desarrollo". Blindaje ANTES de probar
	-- ningun bloque - un objeto marcado por el propio motor como debug-only
	-- nunca deberia terminar en un grupo de identidad real (Combate,
	-- Materiales...) solo porque su nombre tambien contenga una palabra
	-- reconocida. No sustituye el diagnostico por nombre de GS_NativeAudit.lua
	-- (sistemas advierte: "no todos los ZedDmg_* tienen por que llevar esa
	-- bandera") - son señales complementarias, no una la sustituye a la otra.
	local isDebugOnly = nil
	if scriptItem and scriptItem.isDebugOnly then
		local okDebug, valueDebug = pcall(function() return scriptItem:isDebugOnly() end)
		if okDebug then isDebugOnly = valueDebug end
	end
	if isDebugOnly == true then
		return {
			schemaVersion = 1,
			catalogEpoch = GlobalStorageSiK.CatalogManager.getEpoch(),
			catalogFingerprint = GlobalStorageSiK.CatalogManager.getCatalogFingerprint(),
			fullType = fullType,
			classificationScope = "script",
			primaryPath = buildPrimaryPath("other", "debug", nil),
			facets = {},
			attributes = {},
			evidence = { primary = { source = "script_is_debug_only", scope = "script", confidence = 100 }, supporting = {}, conflicting = {} },
			legacyAliases = {},
		}
	end

	local blockErrors = nil
	for i = 1, #blockClassifiers do
		local ok, primaryPath, facets, attributes, evidence = pcall(blockClassifiers[i], fullType, scriptItem)
		if ok and primaryPath then
			return {
				schemaVersion = 1,
				catalogEpoch = GlobalStorageSiK.CatalogManager.getEpoch(),
				catalogFingerprint = GlobalStorageSiK.CatalogManager.getCatalogFingerprint(),
				fullType = fullType,
				classificationScope = "script",
				primaryPath = primaryPath,
				facets = facets or {},
				attributes = attributes or {},
				evidence = evidence or { primary = { source = "unknown", scope = "script", confidence = 0 }, supporting = {}, conflicting = {} },
				legacyAliases = {},
			}
		elseif not ok then
			blockErrors = blockErrors or {}
			blockErrors[#blockErrors + 1] = (blockNames[i] or ("block#" .. tostring(i))) .. ": " .. tostring(primaryPath)
		end
	end
	if blockErrors then
		return {
			schemaVersion = 1,
			catalogEpoch = GlobalStorageSiK.CatalogManager.getEpoch(),
			catalogFingerprint = GlobalStorageSiK.CatalogManager.getCatalogFingerprint(),
			fullType = fullType,
			classificationScope = "script",
			primaryPath = buildPrimaryPath("other", "classifier_error", nil),
			facets = {},
			attributes = {},
			evidence = { primary = { source = "classifier_exception", scope = "script", confidence = 0 }, supporting = {}, conflicting = blockErrors },
			legacyAliases = {},
			classifierError = true,
		}
	end
	-- Ningun bloque reclama este fullType todavia (normal mientras los
	-- clasificadores se implementan uno a uno, §12) - grupo de diagnostico
	-- visible, nunca un fallback silencioso.
	return {
		schemaVersion = 1,
		catalogEpoch = GlobalStorageSiK.CatalogManager.getEpoch(),
		catalogFingerprint = GlobalStorageSiK.CatalogManager.getCatalogFingerprint(),
		fullType = fullType,
		classificationScope = "script",
		primaryPath = buildPrimaryPath("other", "unclassified_modded", nil),
		facets = {},
		attributes = {},
		evidence = { primary = { source = "no_block_classifier", scope = "script", confidence = 0 }, supporting = {}, conflicting = {} },
		legacyAliases = {},
	}
end

-- BUG REAL cerrado (2026-08-27, hallazgo del equipo de sistemas):
-- classify() permitia clasificar (y CACHEAR) con CatalogManager.isReady()
-- todavia en false - el resultado quedaba grabado con
-- catalogFingerprint=nil, y como OnGameBoot llama markReady(false) (sin
-- bumpEpoch), ese cambio a ready=true NUNCA dispara onEpochChanged ni vacia
-- la entrada prematura. Resultado transitorio: mientras no este ready+sealed,
-- se devuelve un marcador "pending" (mismo shape que un resultado real, para
-- que un consumidor descuidado no reviente con un nil) pero JAMAS se
-- escribe en classificationCache.
local PENDING_RESULT = {
	schemaVersion = 1,
	catalogEpoch = -1,
	catalogFingerprint = nil,
	fullType = nil,
	classificationScope = "script",
	primaryPath = { l1 = "other", l2 = "pending", l3 = nil },
	facets = {},
	attributes = {},
	evidence = { primary = { source = "catalog_not_ready", scope = "script", confidence = 0 }, supporting = {}, conflicting = {} },
	legacyAliases = {},
	pending = true,
}

--- Punto de entrada publico - una sola clasificacion real por fullType y
--- epoca (§8.1), resultado compartido por referencia, nunca copiado.
---@param fullType string|nil
---@return table|nil NativeClassificationResult, nil si fullType invalido, PENDING_RESULT si el catalogo aun no esta listo/sellado
function GlobalStorageSiK.NativeClassifier.classify(fullType)
	metrics.requests = metrics.requests + 1
	if not fullType or fullType == "" then
		metrics.invalidRequests = metrics.invalidRequests + 1
		return nil
	end
	if not sealed or not GlobalStorageSiK.CatalogManager.isReady() then
		metrics.pendingRequests = metrics.pendingRequests + 1
		return PENDING_RESULT
	end
	local cached = classificationCache[fullType]
	if cached ~= nil then
		metrics.cacheHits = metrics.cacheHits + 1
		return cached
	end
	local result = computeClassification(fullType)
	metrics.effectiveClassifications = metrics.effectiveClassifications + 1
	classificationCache[fullType] = result
	return result
end

--- Copia plana de telemetría; ningún consumidor puede mutar los contadores.
---@return table
function GlobalStorageSiK.NativeClassifier.getMetrics()
	return {
		catalogEpoch = GlobalStorageSiK.CatalogManager.getEpoch(),
		requests = metrics.requests,
		effectiveClassifications = metrics.effectiveClassifications,
		cacheHits = metrics.cacheHits,
		pendingRequests = metrics.pendingRequests,
		invalidRequests = metrics.invalidRequests,
	}
end

--- SOLO DIAGNOSTICO (GS_NativeAudit.lua) - a diferencia de classify(), que
--- se detiene en el PRIMER bloque que reclama el fullType (asi decide la
--- precedencia real, ver comentario de mas abajo), esto prueba TODOS los
--- bloques y devuelve la ruta que cada uno habria propuesto - permite
--- detectar "colisiones de precedencia" (p.ej. un objeto que Materiales
--- reclama pero que Combate tambien habria clasificado como arma) sin
--- alterar en nada el resultado real cacheado. Nunca se usa desde classify(),
--- nunca se cachea - recorrer todos los bloques es mas caro y solo tiene
--- sentido bajo demanda de auditoria.
---@param fullType string
---@return table[] lista de { blockIndex, blockName, primaryPath } - uno por cada bloque que reclama el tipo
function GlobalStorageSiK.NativeClassifier.diagnosticClassifyAllBlocks(fullType)
	if not fullType or fullType == "" then return {} end
	local scriptItem = GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.getScriptItem
		and GlobalStorageSiK.I18n.getScriptItem(fullType)
	local out = {}
	for i = 1, #blockClassifiers do
		local ok, primaryPath = pcall(blockClassifiers[i], fullType, scriptItem)
		if ok and primaryPath then
			out[#out + 1] = { blockIndex = i, blockName = blockNames[i] or ("block#" .. tostring(i)), primaryPath = primaryPath }
		end
	end
	return out
end

--- OnGameBoot es el mismo evento que ya usa GS_CategoryRewrite.lua (recorrer
--- getAllItems() con seguridad confirmada) y que GS_CatalogManager usa para
--- marcar ready - para entonces, todos los ficheros de bloque (que se
--- registran a si mismos al cargar, fuera de cualquier evento) ya han
--- tenido ocasion de llamar a registerBlock(). Sellar aqui, no antes.
local function onGameBoot()
	GlobalStorageSiK.NativeClassifier.sealBlocks()
end

Events.OnGameBoot.Add(onGameBoot)

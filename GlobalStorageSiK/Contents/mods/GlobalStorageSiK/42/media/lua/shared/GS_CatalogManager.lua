--[[
	GlobalStorageSiK - Propietario unico del ciclo de vida del catalogo de items
	Autor: SiK
	Fecha: 2026-08-27

	Cimiento de la taxonomia nativa (ver Documentacion/GSSiK_Taxonomia_Nativa_Analisis.md,
	Core 1.4.2-dev2). Sustituye la idea de "una cifra global incrementada desde
	eventos ambiguos" por un unico gestor con:
	- catalogEpoch: se incrementa cuando el catalogo de scripts puede haber
	  cambiado (arranque, recarga Lua en debug). Toda cache positiva de
	  clasificacion nativa es valida mientras el epoch no cambie; toda cache
	  negativa queda atada al epoch en el que se produjo.
	- ready: barrera MINIMA, no garantia absoluta. Antes de ready=true,
	  cualquier consulta debe responder "pendiente" y NUNCA guardar un
	  negativo permanente (esto es lo que corrige de raiz el bug real de
	  cachedScriptItem en GS_I18n.lua: cachear `false` para siempre si
	  ScriptManager no estaba listo en el primer intento).
	- catalogFingerprint: identifica la generacion de catalogo para la que un
	  resultado de clasificacion es valido (build de PZ + mods activos+orden +
	  version del clasificador). No se usa todavia por ningun clasificador
	  real (eso llega en fases posteriores), pero el propietario del ciclo
	  debe existir antes de que cualquier cache dependa de el.
	- languageEpoch: separado de catalogEpoch a proposito - cambiar idioma
	  invalida presentacion (traducciones/etiquetas), nunca clasificacion.

	Se ejecuta en TODOS los procesos (cliente, servidor dedicado, SP) porque
	cada uno carga su propio ScriptManager de forma independiente - mismo
	criterio ya usado en GS_CategoryRewrite.lua.
]]

GlobalStorageSiK.CatalogManager = GlobalStorageSiK.CatalogManager or {}

--- Version interna del clasificador nativo - se incrementa cuando cambia el
--- comportamiento de clasificacion en si (no cuando solo cambian datos), para
--- que un catalogFingerprint calculado con una version vieja del codigo nunca
--- se confunda con uno calculado con la version nueva.
-- dev27: bump obligatorio (GS_NativeTaxonomyRegistry.lua:19) - se retira la
-- clave containers.wearable.backpack y se sustituye por
-- clothing_protection.equipment.backpack (mochilas vestibles pasan a Ropa/
-- Equipamiento, decision de producto de sistemas para DEV27).
local CLASSIFIER_SCHEMA = "1"

local state = {
	catalogEpoch = 0,
	classifierSchema = CLASSIFIER_SCHEMA,
	catalogFingerprint = nil,
	catalogFingerprintDigest = nil,
	externalModsFingerprint = nil,
	activeModCount = 0,
	gameBuildVersion = nil,
	languageEpoch = 0,
	ready = false,
}

-- BUG REAL cerrado (2026-08-27, hallazgo del equipo de sistemas): esto
-- ordenaba alfabeticamente los IDs antes de concatenarlos - detecta altas y
-- bajas de mods, pero NO un cambio en el ORDEN DE CARGA real (getActivatedMods()
-- ya devuelve los mods en su orden de carga real), que puede alterar que
-- script sobreescribe a cual y por tanto la clasificacion final. El
-- documento exige explicitamente "mods activos + orden" en el fingerprint -
-- ahora se conserva el orden devuelto por el motor, sin ordenar nada.
---@return string, number ids-concatenados, numero de mods activos
local function activeModsFingerprint()
	if not getActivatedMods then
		return "unknown", 0
	end
	local ok, mods = pcall(getActivatedMods)
	if not ok or not mods then
		return "unknown", 0
	end
	local ids = {}
	for i = 0, mods:size() - 1 do
		local okId, id = pcall(function() return mods:get(i) end)
		if okId and id then
			ids[#ids + 1] = tostring(id)
		end
	end
	return table.concat(ids, ","), #ids
end

-- dev23 (pedido explicito de sistemas: "el fingerprint actual es demasiado
-- largo para una interfaz - Desarrollo puede calcular un digest estable
-- server-side y enviarlo junto con modCount"). DJB2 de toda la vida - no
-- necesita ser criptografico, solo estable y corto; el fingerprint COMPLETO
-- sigue disponible via getCatalogFingerprint() para el fichero de
-- diagnostico, esto es solo una representacion compacta para UI.
---@param text string
---@return string digest hexadecimal de 8 caracteres
local function shortDigest(text)
	local hash = 5381
	for i = 1, #text do
		hash = (hash * 33 + string.byte(text, i)) % 4294967296
	end
	return string.format("%08x", hash)
end

---@return string
local function gameBuildFingerprint()
	local ok, version = pcall(function()
		return getCore and getCore():getVersionNumber()
	end)
	if ok and version then
		return tostring(version)
	end
	return "unknown"
end

--- Calcula catalogFingerprint/externalModsFingerprint a partir del estado
--- real del proceso. Llamado una sola vez en OnGameBoot (mismo evento en el
--- que GS_CategoryRewrite.lua ya recorre getAllItems() con seguridad
--- confirmada) - nunca antes, nunca de forma perezosa desde una consulta.
local function computeFingerprints()
	local modsFingerprint, modCount = activeModsFingerprint()
	state.externalModsFingerprint = modsFingerprint
	state.activeModCount = modCount
	state.gameBuildVersion = gameBuildFingerprint()
	state.catalogFingerprint = table.concat({
		state.gameBuildVersion,
		modsFingerprint,
		"schema=" .. CLASSIFIER_SCHEMA,
	}, "|")
	-- dev23: digest corto calculado UNA vez aqui mismo, junto al
	-- fingerprint completo - nunca recalculado en caliente por un consumidor
	-- de UI, mismo criterio que el resto de este modulo (computeFingerprints
	-- solo se llama en OnGameBoot/forceNewEpoch, nunca de forma perezosa).
	state.catalogFingerprintDigest = shortDigest(state.catalogFingerprint)
end

-- BUG REAL cerrado (2026-08-27, hallazgo del equipo de sistemas: "los
-- positivos de ScriptItem siguen siendo permanentes" en GS_I18n.lua): atar
-- cada positivo a su epoch individualmente es propenso a error (facil de
-- olvidar en un consumidor nuevo) - en vez de eso, CUALQUIER cache que
-- dependa del catalogo (ScriptItemCache y las que vengan despues,
-- NativeClassificationCache incluida) se registra aqui para ser vaciada por
-- COMPLETO cada vez que el epoch cambia de verdad. Mas simple y mas seguro
-- que perseguir cada positivo suelto por el codebase.
local epochListeners = {}

--- Se llama SIEMPRE que catalogEpoch cambia de verdad (nunca en un
--- markReady sin bumpEpoch). El callback recibe el nuevo epoch; cualquier
--- excepcion se aisla con pcall para no romper el arranque por un listener
--- de un modulo que fallara al vaciar su propia cache.
---@param fn fun(newEpoch:number)
function GlobalStorageSiK.CatalogManager.onEpochChanged(fn)
	if type(fn) == "function" then
		epochListeners[#epochListeners + 1] = fn
	end
end

local function notifyEpochChanged()
	for i = 1, #epochListeners do
		pcall(epochListeners[i], state.catalogEpoch)
	end
end

--- Marca el catalogo disponible. Idempotente: llamarlo mas de una vez solo
--- incrementa catalogEpoch si de verdad hay indicios de que el catalogo pudo
--- cambiar (recarga Lua en debug) - el propio caller decide eso, esta
--- funcion solo aplica el efecto.
---@param bumpEpoch boolean|nil si true, incrementa catalogEpoch antes de marcar ready
function GlobalStorageSiK.CatalogManager.markReady(bumpEpoch)
	if bumpEpoch then
		state.catalogEpoch = state.catalogEpoch + 1
		notifyEpochChanged()
	end
	computeFingerprints()
	state.ready = true
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.debug("CatalogManager",
			string.format("catalogo listo epoch=%d fingerprint=%s",
				state.catalogEpoch, tostring(state.catalogFingerprint)))
	end
end

---@return boolean
function GlobalStorageSiK.CatalogManager.isReady()
	return state.ready
end

---@return number
function GlobalStorageSiK.CatalogManager.getEpoch()
	return state.catalogEpoch
end

---@return string
function GlobalStorageSiK.CatalogManager.getClassifierSchema()
	return state.classifierSchema
end

---@return string|nil nil si todavia no esta listo (ver isReady)
function GlobalStorageSiK.CatalogManager.getCatalogFingerprint()
	return state.catalogFingerprint
end

-- dev23 (pedido explicito de sistemas, "digest corto para UI, fingerprint
-- completo solo en el fichero de diagnostico"): 3 getters nuevos, mismo
-- criterio que el resto - valores ya calculados en computeFingerprints(),
-- nunca recalculados por el consumidor.
---@return string|nil nil si todavia no esta listo
function GlobalStorageSiK.CatalogManager.getCatalogFingerprintDigest()
	return state.catalogFingerprintDigest
end

---@return number
function GlobalStorageSiK.CatalogManager.getActiveModCount()
	return state.activeModCount or 0
end

---@return string
function GlobalStorageSiK.CatalogManager.getGameBuildVersion()
	return state.gameBuildVersion or "unknown"
end

---@return string|nil
function GlobalStorageSiK.CatalogManager.getExternalModsFingerprint()
	return state.externalModsFingerprint
end

---@return number
function GlobalStorageSiK.CatalogManager.getLanguageEpoch()
	return state.languageEpoch
end

-- BUG REAL cerrado (2026-08-27, hallazgo del equipo de sistemas: "los
-- positivos de ScriptItem siguen siendo permanentes"): la solucion aplicada
-- en GS_I18n.lua (suscribirse a onEpochChanged y vaciar sus 3 tablas a mano)
-- funciona, pero es un patron ad-hoc que cualquier modulo nuevo tendria que
-- reinventar - y facil de olvidar (exactamente el bug que motivo este
-- comentario). Antes de construir NativeClassificationCache (la taxonomia
-- nativa consultara MUCHAS mas propiedades por objeto que hoy) se cierra
-- el ciclo de una vez: un unico helper reutilizable que CUALQUIER cache
-- "valida durante una epoca del catalogo, nunca mas" debe usar - correcto
-- por construccion, sin depender de que cada consumidor recuerde
-- suscribirse el mismo.
---@return table cache tabla viva; leer/escribir directamente como cache normal.
--- Se vacia por completo (todas las claves) cada vez que catalogEpoch
--- cambia de verdad - nunca antes, nunca parcialmente.
function GlobalStorageSiK.CatalogManager.createEpochCache()
	local cache = {}
	local function clearAll()
		for k in pairs(cache) do
			cache[k] = nil
		end
	end
	GlobalStorageSiK.CatalogManager.onEpochChanged(clearAll)
	-- dev20 (ver comentario de bumpLanguageEpoch, mas abajo en este mismo
	-- fichero): tambien se vacia si languageEpoch cambia de verdad, no solo
	-- catalogEpoch - infraestructura lista aunque hoy B42 no dispare este
	-- evento en caliente.
	GlobalStorageSiK.CatalogManager.onLanguageEpochChanged(clearAll)
	return cache
end

-- BUG POTENCIAL cerrado por adelantado (2026-08-27, observacion de sistemas
-- en la validacion de dev20: "las nuevas cachés localizadas usan
-- catalogEpoch pero no languageEpoch - decidir/documentar si el cambio de
-- idioma en caliente se soporta"). Respuesta: B42 no tiene hoy ningun evento
-- real de cambio de idioma en caliente (exige reiniciar, confirmado ya en el
-- comentario original de bumpLanguageEpoch), asi que un reinicio del
-- proceso ya vacia CUALQUIER cache en memoria sin necesitar este mecanismo -
-- por eso ninguna cache de presentacion (typeDisplayNameCache,
-- itemDisplayNameCache, itemSearchHaystackCache, sortKeyValueCache) fallaba
-- hasta ahora por depender solo de catalogEpoch. Aun asi, en vez de dejarlo
-- solo documentado como limitacion aceptada, se cablea aqui mismo: cualquier
-- cache creada via createEpochCache() (arriba) ahora TAMBIEN se vacia
-- cuando languageEpoch cambia de verdad - infraestructura correcta desde ya
-- si en el futuro se cablea un evento real de cambio de idioma sin
-- reiniciar, sin tener que revisar cache por cache en ese momento.
local languageEpochListeners = {}

---@param fn fun(newLanguageEpoch:number)
function GlobalStorageSiK.CatalogManager.onLanguageEpochChanged(fn)
	if type(fn) == "function" then
		languageEpochListeners[#languageEpochListeners + 1] = fn
	end
end

local function notifyLanguageEpochChanged()
	for i = 1, #languageEpochListeners do
		pcall(languageEpochListeners[i], state.languageEpoch)
	end
end

--- Invalida solo PresentationCache (traducciones/etiquetas/orden visible) -
--- nunca toca catalogEpoch ni ninguna clasificacion nativa. No hay todavia
--- ningun evento real de cambio de idioma en caliente en B42 (normalmente
--- exige reiniciar), pero el propietario del ciclo debe exponer esto desde
--- ya para que la capa de presentacion (fases posteriores) pueda depender de
--- el en vez de inventar su propio contador.
function GlobalStorageSiK.CatalogManager.bumpLanguageEpoch()
	state.languageEpoch = state.languageEpoch + 1
	notifyLanguageEpochChanged()
end

--- Fuerza una nueva generacion de catalogo (recarga Lua en debug, o cualquier
--- caller que detecte que el conjunto de scripts pudo cambiar en caliente).
--- Cualquier NativeClassificationCache/ScriptItemCache existente queda
--- invalidada de facto en cuanto los consumidores comparen su catalogEpoch
--- almacenado contra este nuevo valor.
function GlobalStorageSiK.CatalogManager.forceNewEpoch()
	state.ready = false
	GlobalStorageSiK.CatalogManager.markReady(true)
end

local function onGameBoot()
	GlobalStorageSiK.CatalogManager.markReady(false)
end

Events.OnGameBoot.Add(onGameBoot)

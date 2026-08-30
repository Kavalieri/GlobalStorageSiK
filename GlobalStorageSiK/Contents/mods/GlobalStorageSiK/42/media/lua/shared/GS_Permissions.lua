--[[
	GlobalStorageSiK - Permisos de acceso a la red (MP)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Permisos por ID persistente de personaje, con migración de nombres legacy.
]]

require "GS_Network"

GlobalStorageSiK.Permissions = {}

GlobalStorageSiK.Permissions.ROLE_OWNER  = "owner"
GlobalStorageSiK.Permissions.ROLE_ADMIN  = "admin"
GlobalStorageSiK.Permissions.ROLE_MEMBER = "member"
-- Rediseño 2026-08-22 ("de hecho, podemos usar la columna rol... rol de un
-- pj muerto sea 'muerto' y listo"): un personaje fallecido pasa a valer
-- ROLE_DEAD en su propio campo role, la MISMA fuente unica de verdad que ya
-- decide owner/admin/member para cualquier consumidor. No es un cuarto rol
-- "activo" mas: ROLE_DEAD nunca coincide con ninguna comparacion role==owner/
-- admin/member de todo el fichero, asi que el vaciado de permisos, acceso y
-- escalada de reclamo (Nivel 1/2 de canClaimVacantOwnership) ocurre gratis,
-- en el origen, sin tener que tocar cada punto de codigo que ya comprueba
-- role. record.priorRole guarda el rol que tenia justo antes de morir - lo
-- necesita el Nivel 3 (herencia por cuenta) para seguir identificando "esto
-- fue un admin de esta red", que de otra forma dejaria de encontrarlo.
GlobalStorageSiK.Permissions.ROLE_DEAD = "dead"

-- Agrupador de ModData.transmit (2026-08-25, bug real confirmado: reclamar
-- una red justo despues de que una misma cuenta vuelva con un characterId
-- nuevo podia reconciliar VARIAS redes vacantes en la misma pasada, y cada
-- reconciliacion disparaba su propia llamada a ModData.transmit sin agrupar
-- - hasta 3 difusiones COMPLETAS seguidas de todo el registro de permisos
-- del servidor (todas las redes, todas las fichas de personaje, vivas y
-- muertas) a TODOS los clientes conectados, cuando una sola bastaba.
-- handleOwnerDeath ya evitaba esto (transmite una vez tras su propio bucle);
-- el resto de puntos de escritura no. requestTransmit() sustituye cualquier
-- llamada directa a ModData.transmit con esa clave: agrupa cualquier numero
-- de mutaciones dentro del mismo tick en un unico envio via Events.OnTick,
-- sin cambiar cuando el propio servidor ve la mutacion (ya esta aplicada en
-- memoria antes de llamar aqui) - solo difiere unos milisegundos cuando se
-- difunde a los clientes.
local pendingPermissionsTransmit = false
local permissionsTransmitTickInstalled = false

-- Diagnostico de tamaño (2026-08-25, investigacion del cuelgue de cliente al
-- reclamar tras morir): nunca existio ningun log que midiera CUANTO se envia
-- en cada difusion de permisos - solo trazas narrativas de que paso, nunca de
-- volumen. Cuenta redes y fichas de personaje (vivas+muertas, nunca se
-- borran) en TODO el registro, no solo la red que motivo el cambio, porque
-- ModData.transmit con esta clave siempre manda la tabla entera del servidor.
-- Siempre visible (Log.warn, no depende de Modo depuracion) mientras dure
-- esta investigacion - bajar a Log.info si se confirma que el tamaño no es
-- la causa.
local function logPermissionsTransmitSize()
	if not GlobalStorageSiK.Log or not GlobalStorageSiK.Network or not GlobalStorageSiK.Network.getRegistry then
		return
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local networks = registry and registry.networks
	if not networks then return end
	local networkCount, characterCount = 0, 0
	for networkId in pairs(networks) do
		networkCount = networkCount + 1
		local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
		if net and net.characterPermissions then
			for _ in pairs(net.characterPermissions) do
				characterCount = characterCount + 1
			end
		end
	end
	GlobalStorageSiK.Log.warn("Permissions", "transmitSize",
		"networks=" .. tostring(networkCount) .. " characterRecordsTotal=" .. tostring(characterCount))
end

local function flushPermissionsTransmit()
	permissionsTransmitTickInstalled = false
	if Events and Events.OnTick then Events.OnTick.Remove(flushPermissionsTransmit) end
	if not pendingPermissionsTransmit then return end
	pendingPermissionsTransmit = false
	if ModData and ModData.transmit then
		logPermissionsTransmitSize()
		ModData.transmit(GlobalStorageSiK.PERMISSIONS_MODDATA_KEY)
	end
end

--- Difunde GlobalStorageSiK_Permissions a todos los clientes, agrupando
--- cualquier numero de llamadas dentro del mismo tick/rafaga en un unico
--- envio - usar SIEMPRE en vez de llamar a ModData.transmit directamente con
--- GlobalStorageSiK.PERMISSIONS_MODDATA_KEY.
function GlobalStorageSiK.Permissions.requestTransmit()
	pendingPermissionsTransmit = true
	if not ModData or not ModData.transmit then return end
	if not Events or not Events.OnTick then
		-- Fallback defensivo (no deberia pasar en runtime real): sin OnTick no
		-- hay forma de agrupar, transmitir de inmediato en vez de perder el cambio.
		flushPermissionsTransmit()
		return
	end
	if not permissionsTransmitTickInstalled then
		permissionsTransmitTickInstalled = true
		Events.OnTick.Add(flushPermissionsTransmit)
	end
end

--- Indica si deben aplicarse permisos (no en SP solo).
---@return boolean
function GlobalStorageSiK.Permissions.shouldEnforce()
	return GlobalStorageSiK.isMultiplayerActive()
end

-- ============================================================================
-- Registro de permisos, ModData PROPIA (2026-08-22, separacion de
-- responsabilidades pedida explicitamente - ver comentario de
-- PERMISSIONS_MODDATA_KEY en GS_Config.lua). Antes estos campos vivian
-- mezclados dentro de registry.networks[id] (GlobalStorageSiK.Network.
-- getRegistry(), MODDATA_KEY) junto con containers/terminals/addonInstalls -
-- identidad/permisos y datos operativos del almacen en el mismo objeto. A
-- partir de aqui, TODO este fichero opera sobre su PROPIA tabla por red
-- (getPermNet), nunca sobre registry.networks[id] directamente - es la unica
-- fuente de verdad para "quien tiene acceso, con que rol, quien es el
-- propietario" para cualquier consumidor (UI normal, servidor, panel de
-- soporte de staff).
-- ============================================================================

local function getPermissionsStore()
	if not ModData or not ModData.getOrCreate then return {} end
	local data = ModData.getOrCreate(GlobalStorageSiK.PERMISSIONS_MODDATA_KEY)
	data.networks = data.networks or {}
	return data.networks
end

--- Migracion retroactiva UNA sola vez por red: si una red ya existia en el
--- registro operativo (creada antes de esta separacion) y todavia no tiene
--- entrada en la ModData de permisos, se trae su estado de permisos de ahi.
--- Nunca se ejecuta si la red ya tiene entrada propia - no pisa datos ya
--- migrados. Red genuinamente nueva: legacyNet es nil, se crean campos vacios.
---@param legacyNet table|nil
---@return table
local function buildPermNetFromLegacy(legacyNet)
	legacyNet = legacyNet or {}
	return {
		characterPermissions = legacyNet.characterPermissions or {},
		allowedUsers = legacyNet.allowedUsers or {},
		allowedFactions = legacyNet.allowedFactions or {},
		adminUsers = legacyNet.adminUsers or {},
		memberZoneDenials = legacyNet.memberZoneDenials or {},
		factionOnly = legacyNet.factionOnly == true,
		owner = legacyNet.owner or "",
		ownerCharacterId = legacyNet.ownerCharacterId,
		-- DEV anterior persistía `ownerAccount`; la ModData separada usa
		-- `ownerAccountLogin`. Conservar ese ancla durante la migración es
		-- imprescindible para verificar al propietario sin confiar en nombre o
		-- descriptor numérico, que pueden colisionar entre personajes.
		ownerAccountLogin = legacyNet.ownerAccountLogin or legacyNet.ownerAccount,
		ownerSteamId = legacyNet.ownerSteamId,
	}
end

--- UNICO punto de entrada a la tabla de permisos de una red. Sustituye a
--- "registry.networks[networkId]" en todo este fichero.
---@param networkId string
---@return table|nil
function GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not networkId or networkId == "" then return nil end
	local store = getPermissionsStore()
	local permNet = store[networkId]
	if not permNet then
		local registry = GlobalStorageSiK.Network.getRegistry()
		local legacyNet = registry and registry.networks and registry.networks[networkId]
		permNet = buildPermNetFromLegacy(legacyNet)
		store[networkId] = permNet
	end
	return permNet
end

--- Borra la entrada de permisos de una red (usado solo por adminDeleteNetwork,
--- que borra la red por completo).
---@param networkId string
function GlobalStorageSiK.Permissions.deletePermNet(networkId)
	local store = getPermissionsStore()
	store[networkId] = nil
end

--- Normaliza un nombre para comparación.
---@param name string|nil
---@return string
local function normalizeName(name)
	if not name then
		return ""
	end
	return (tostring(name):lower():gsub("^%s*(.-)%s*$", "%1"))
end

--- Limpia espacios sin alterar mayúsculas ni bytes UTF-8. Los nombres de
--- presentación no son identidad y nunca deben pasar por normalizeName().
---@param value any
---@return string
local function displayText(value)
	if value == nil then return "" end
	return (tostring(value):gsub("^%s*(.-)%s*$", "%1"))
end

local function permissionLogText(value)
	local text = tostring(value or "")
	text = string.gsub(text, "[%c]", " ")
	-- No cortar por bytes: Lua 5.1 no conoce límites UTF-8 y podría dejar una
	-- secuencia china/cirílica inválida. El juego ya limita nombres/usuarios.
	return text
end

--- Clave estable para las restricciones de zona. Los miembros ya vinculados
--- usan el ID persistente del personaje; los permisos nominales/offline usan
--- una clave legacy que se migra al ID en cuanto el personaje se conecta.
local function zoneMemberKey(characterId, characterName)
	characterId = tostring(characterId or "")
	if characterId ~= "" then return characterId end
	local name = normalizeName(characterName)
	return name ~= "" and ("legacy-name:" .. name) or ""
end

local function tableHasEntries(values)
	for _ in pairs(values or {}) do return true end
	return false
end

local isCharacterNameAmbiguous

--- Nombre visible del personaje (forename + surname). Conserva mayúsculas y
--- UTF-8: la normalización solo se usa al comparar, nunca al presentar.
---@param player IsoPlayer|nil
---@return string
--- Resuelve el mejor nombre disponible para mostrar un miembro/entry
--- serializado (memberEntries, filas de picker, etc.), con UNA prioridad
--- fija - antes cada interfaz (pestaña normal de permisos, panel de soporte
--- de staff) tenia su propio orden de campos DISTINTO (name>displayName>
--- username en una, displayName>name en la otra), lo que podia mostrar un
--- resultado diferente para el MISMO miembro segun que ventana se abriera
--- (bug real senalado en revision tecnica 2026-08-26, plausible explicacion
--- adicional del reporte "nombre chino se ve mal en un panel pero no en el
--- otro"). Unica fuente de verdad para ambas interfaces desde ahora.
---@param entry table|nil { characterName?, displayName?, name?, username? }
---@return string
function GlobalStorageSiK.Permissions.resolveMemberDisplayName(entry)
	if not entry then return "" end
	local characterName = displayText(entry.characterName)
	if characterName ~= "" then return characterName end
	local displayName = displayText(entry.displayName)
	if displayName ~= "" then return displayName end
	local name = displayText(entry.name)
	if name ~= "" then return name end
	return displayText(entry.username)
end

function GlobalStorageSiK.Permissions.getCharacterName(player)
	if not player then
		return ""
	end
	local ok, name = pcall(function()
		if player.getDescriptor then
			local desc = player:getDescriptor()
			if desc and desc.getForename and desc.getSurname then
				local full = displayText((desc:getForename() or "") .. " " .. (desc:getSurname() or ""))
				if full ~= "" then
					return full
				end
			end
		end
		if player.getForename and player.getSurname then
			local full = displayText((player:getForename() or "") .. " " .. (player:getSurname() or ""))
			if full ~= "" then
				return full
			end
		end
		if player.getForname and player.getSurname then
			local full = displayText((player:getForname() or "") .. " " .. (player:getSurname() or ""))
			if full ~= "" then
				return full
			end
		end
		return displayText(player:getUsername() or "")
	end)
	if ok and name and name ~= "" then
		return name
	end
	if player.getUsername then
		return displayText(player:getUsername() or "")
	end
	return ""
end

--- Nombre visible que GS muestra para el jugador. El personaje es la fuente
--- primaria también en dedicado: getDisplayName/getUsername pueden representar
--- la cuenta (por ejemplo "admin") y nunca deben sustituir a Kalva, 凯 瓦, etc.
--- Cuenta e IDs quedan reservados para autorización y desambiguación interna.
---@param player IsoPlayer|nil
---@return string
function GlobalStorageSiK.Permissions.getPlayerDisplayName(player)
	if not player then return "" end
	local characterName = displayText(GlobalStorageSiK.Permissions.getCharacterName(player))
	if characterName ~= "" then return characterName end
	if player.getDisplayName then
		local ok, value = pcall(function() return player:getDisplayName() end)
		value = ok and displayText(value) or ""
		if value ~= "" then return value end
	end
	if player.getUsername then
		local ok, value = pcall(function() return player:getUsername() end)
		value = ok and displayText(value) or ""
		if value ~= "" then return value end
	end
	return ""
end

local function getPlayerUsername(player)
	if not player or not player.getUsername then return "" end
	local ok, value = pcall(function() return player:getUsername() end)
	return ok and displayText(value) or ""
end

-- BUG REAL DE SEGURIDAD cerrado (2026-08-26, revision tecnica de Desarrollo
-- tras probar en TEST, log real: steamId="7.656119799703734E16" en vez de
-- "76561197997037351"): IsoPlayer:getSteamID() devuelve un `long` de Java
-- (confirmado con javap) - Kahlua lo marshalla como numero Lua (double de
-- 64 bits), que NO puede representar exactamente enteros de 17 digitos como
-- un SteamID64 (pierde precision por encima de 2^53, la perdida ocurre en
-- el marshalling, antes de que este codigo vea el valor - ningun tostring/
-- string.format posterior la recupera). Este campo SI se usa en una
-- comprobacion real anti-suplantacion (ver comparaciones displayText(net.
-- ownerSteamId) == currentSteamId mas abajo en este fichero) - un valor
-- redondeado podia no coincidir nunca con el steamId "bueno" capturado en
-- otro momento via la API de String, provocando un falso rechazo de
-- alguien legitimo. getSteamIDFromUsername(username) (confirmado con
-- javap: devuelve java.lang.String, nunca pasa por un numero Lua) es la
-- UNICA fuente usada ahora - si falla/esta vacia, se deja steamId vacio
-- (ya tratado como "sin verificar, no bloquea" en todas las comprobaciones
-- que lo leen) en vez de caer a un valor numerico que puede ser
-- silenciosamente incorrecto.
local function getSteamIdForUsername(username)
	username = displayText(username)
	if username ~= "" and getSteamIDFromUsername then
		local ok, value = pcall(getSteamIDFromUsername, username)
		value = ok and displayText(value) or ""
		if value ~= "" and value ~= "0" and value ~= "-1" then return value end
	end
	return ""
end

local CHARACTER_UUID_KEY = "GS_CharacterUUID"
-- Expuesta para diagnostico externo puntual (GS_Server.lua, OnCreatePlayer) -
-- sin esto, la unica forma de leer el UUID crudo desde otro fichero seria
-- duplicar el literal, con riesgo real de que diverjan si esta clave cambia.
GlobalStorageSiK.Permissions.CHARACTER_UUID_KEY = CHARACTER_UUID_KEY
local characterUuidSequence = 0

-- Cache de UUID por sesion (2026-08-21, segundo intento tras revertir la
-- version que escribia un campo nuevo sobre el objeto IsoPlayer - eso
-- coincidio con un bloqueo total del terminal y se revirtio sin poder
-- confirmar al 100% la causa exacta). Este intento NO toca el objeto del
-- motor en absoluto: usa el propio `player` como CLAVE de una tabla Lua
-- nuestra (mismo patron ya probado y en uso real en GS_ContainerTargets.lua,
-- sessionTargets[player] = ...), nunca como valor a mutar. No es la SteamID
-- (cambia con reinstalaciones/comparticion familiar), ni el indice dinamico
-- de jugador (se reutiliza entre reconexiones), ni el nombre (puede
-- duplicarse/cambiar) - sigue siendo nuestro propio UUID persistente
-- (GS_CharacterUUID en modData), solo que ahora el resultado YA resuelto se
-- guarda en memoria para no releer modData innecesariamente muchas veces
-- por la misma peticion. Claves debiles (__mode="k"): si el objeto IsoPlayer
-- deja de existir (desconexion), su entrada puede recolectarse sola sin
-- dejar basura acumulandose en un servidor dedicado de larga duracion.
local characterUuidCache = setmetatable({}, { __mode = "k" })
local permissionRosterLogSignatures = {}

--- Solo usa un getter público si alguna build lo expone. Nunca intenta acceder
--- al campo ni usa reflexión: B42 lanza una IllegalStateException fuera de
--- debug incluso dentro de pcall. sqlId es diagnóstico opcional, no identidad.
local function getPersistentSqlId(player)
	if not player then return nil end
	if player.getSqlId then
		local ok, value = pcall(function() return player:getSqlId() end)
		value = ok and tonumber(value) or nil
		if value and value >= 0 then return math.floor(value) end
	end
	return nil
end

local function identityDiagnosticFields(player)
	local onlineId = ""
	if player and player.getOnlineID then
		local ok, value = pcall(function() return player:getOnlineID() end)
		if ok and value ~= nil then onlineId = tostring(value) end
	end
	-- BUG REAL cerrado (2026-08-26, revision tecnica de Desarrollo tras
	-- probar en TEST, "sqlId=" siempre vacio en el log real): IsoPlayer no
	-- expone getSqlId() en B42.20.4 (confirmado con javap) - el campo nunca
	-- puede tener valor. Mostrarlo vacio en cada linea de diagnostico daba
	-- una falsa sensacion de respaldo disponible que nunca llega a existir.
	-- Retirado del log (getPersistentSqlId sigue existiendo para el campo
	-- de auditoria record.sqlId, sin cambios, marcado ya como "diagnostico
	-- opcional, no identidad").
	-- Diagnostico CJK pedido explicitamente (2026-08-26, preparacion pruebas
	-- 风。): "ver ?? no implica que el servidor haya recibido ??" - characterName
	-- y username son ya campos separados (nunca se confunden entre si en este
	-- log), pero para poder diferenciar en la proxima ronda "cadena correcta,
	-- fuente sin glifo" de "sustitucion real por U+003F" o "corte a mitad de
	-- caracter" se vuelcan tambien los puntos de codigo Unicode reales del
	-- nombre de personaje (fuente: getForename+getSurname via
	-- getCharacterName), nunca el texto tal como lo renderizaria el cliente.
	-- BUG REAL cerrado (2026-08-26, revision tecnica de Desarrollo tras el
	-- banco CJK de 4 vidas en DEV15): el campo se llamaba "nameBytes" y
	-- volcaba #characterName como si fuera longitud UTF-8 - en Kahlua/PZ toda
	-- cadena esta respaldada por un java.lang.String, `#text` cuenta UNIDADES
	-- UTF-16, no bytes (confirmado matematicamente: los "puntos de codigo"
	-- falsos que dio DEV15, p.ej. U+E802 para "风 。", coinciden exacto con
	-- tratar 3 unidades UTF-16 como si fueran continuacion de 1 secuencia
	-- UTF-8 de 3 bytes). Renombrado a nameUtf16Units (lo que realmente mide)
	-- y el propio decodificador (GS_Libs.unicodeCodepoints) ahora combina
	-- pares subrogados en vez de decodificar como UTF-8.
	local characterName = GlobalStorageSiK.Permissions.getCharacterName(player)
	-- BUG REAL cerrado (2026-08-26, recomendacion no bloqueante de Desarrollo
	-- tras dev8: "steamId= siempre vacio en el log real, incluso en el propio
	-- servidor de pruebas - anadir campos de telemetria explicitos en vez de
	-- seguir registrando un valor vacio sin contexto"): un `steamId=` vacio
	-- por si solo no distingue "la API fallo" de "este jugador nunca tuvo
	-- SteamID resoluble" - `steamIdSource` deja constancia explicita de que
	-- unica fuente se intento (getSteamIDFromUsername, ver comentario de
	-- getSteamIdForUsername mas arriba - la unica que no pierde precision al
	-- pasar por un numero Lua) y si tuvo exito o no.
	local steamId = getSteamIdForUsername(getPlayerUsername(player))
	local steamIdSource = steamId ~= "" and "username_lookup" or "unavailable"
	return " characterName=" .. permissionLogText(characterName, 128)
		.. " nameUtf16Units=" .. tostring(#tostring(characterName or ""))
		.. " nameCodepoints=" .. GlobalStorageSiK.Libs.formatCodepoints(characterName, 12)
		.. " username=" .. permissionLogText(getPlayerUsername(player), 128)
		.. " steamId=" .. permissionLogText(steamId, 64)
		.. " steamIdSource=" .. steamIdSource
		.. " onlineId=" .. permissionLogText(onlineId, 32)
end

local function validCharacterUuid(value)
	value = tostring(value or "")
	return value:match("^gsc_[0-9a-f]+_[0-9a-f]+_[0-9a-f]+_[0-9a-f]+$") ~= nil
end

local function generateCharacterUuid()
	characterUuidSequence = characterUuidSequence + 1
	local now = (getTimestampMs and getTimestampMs())
		or (os and os.time and os.time() * 1000) or 0
	local rndA = (ZombRand and ZombRand(0, 65535)) or math.random(0, 65535)
	local rndB = (ZombRand and ZombRand(0, 65535)) or math.random(0, 65535)
	return string.format("gsc_%x_%x_%04x_%04x",
		now % 0xFFFFFFF, characterUuidSequence % 0xFFFFFF, rndA, rndB)
end

--- Identidad propia de la encarnación concreta. Solo el proceso autoritativo
--- genera el UUID; player modData lo persiste dentro del BLOB del personaje y
--- transmitModData intenta reflejarlo al cliente. Una ranura sqlId puede ser
--- reutilizada al crear otro personaje, por lo que nunca autoriza por sí sola.
local function getOrCreateCharacterUuid(player, reason)
	-- Cache por sesion (ver characterUuidCache arriba): el jugador es la
	-- CLAVE de una tabla Lua nuestra, nunca se escribe nada sobre el objeto
	-- IsoPlayer en si. Corta aqui el resto de la funcion (log de diagnostico,
	-- lectura de modData, validacion) para el caso comun de "ya resuelto en
	-- esta sesion".
	if player and characterUuidCache[player] ~= nil then
		return characterUuidCache[player]
	end
	-- DIAGNOSTICO DIRIGIDO (2026-08-20, degradado a Log.debug 2026-08-21): esta
	-- traza confirmo que la funcion SI se llama en el flujo normal de
	-- conexion+apertura de terminal (duda original ya resuelta, ver
	-- pending-work.md) - degradada de Log.warn (siempre visible) a
	-- Log.debug (categoria Permissions) porque en producción se dispara
	-- decenas de veces por accion y ya no aporta nada sin gatear, solo ruido.
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.debug("Identity", "getOrCreateCharacterUuid CALLED reason=" .. tostring(reason or "?")
			.. " hasPlayer=" .. tostring(player ~= nil) .. " hasGetModData=" .. tostring(player and player.getModData ~= nil))
	end
	if not player or not player.getModData then return "" end
	local okData, data = pcall(function() return player:getModData() end)
	if not okData or not data then return "" end
	local existing = tostring(data[CHARACTER_UUID_KEY] or "")
	if validCharacterUuid(existing) then
		if player then characterUuidCache[player] = existing end
		-- BUG REAL cerrado (2026-08-26, revision tecnica de Desarrollo tras
		-- probar en TEST): antes se gateaba por "esta cadena de UUID ya se
		-- registro alguna vez en este proceso" - la cache por-objeto-jugador
		-- de la linea de arriba (characterUuidCache[player]) YA garantiza que
		-- esta funcion solo se ejecuta hasta aqui una vez por conexion/sesion
		-- (un player Lua nuevo en cada reconexion) - aquel segundo filtro por
		-- valor de UUID solo servia para que la SEGUNDA reconexion en
		-- adelante del MISMO personaje dejara de confirmar nada, justo la
		-- prueba que Desarrollo necesitaba ver ("una linea por conexion, no
		-- una por UUID en toda la vida del proceso"). Retirado.
		if GlobalStorageSiK.Log then
			GlobalStorageSiK.Log.info("Identity", "characterUuidReused",
				"reason=" .. tostring(reason or "lookup")
					.. " characterId=character:" .. existing
					.. identityDiagnosticFields(player))
		end
		return existing
	end
	if not GlobalStorageSiK.isAuthoritative() then return "" end
	local value = generateCharacterUuid()
	data[CHARACTER_UUID_KEY] = value
	if player then characterUuidCache[player] = value end
	if player.transmitModData then
		pcall(function() player:transmitModData() end)
	end
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.info("Identity", "characterUuidGenerated",
			"reason=" .. tostring(reason or "lookup_fallback")
				.. " characterId=character:" .. value
				.. identityDiagnosticFields(player))
	end
	-- DIAGNOSTICO DIRIGIDO (2026-08-19, feedback comunidad china: "cada
	-- reinicio del servidor me duplica la entrada de miembro, incluso a mi
	-- mismo, y los nuevos no reciben permiso") - sospecha concreta: la
	-- escritura de arriba (data[CHARACTER_UUID_KEY] = value) NO esta
	-- sobreviviendo hasta el siguiente arranque del proceso, asi que cada
	-- reinicio regenera un UUID nuevo para el MISMO personaje en vez de
	-- reutilizar el guardado. Relectura inmediata de getModData() (una
	-- llamada nueva, no la tabla "data" ya en mano, para descartar que sea
	-- solo un problema de referencia local) - si no coincide, error SIEMPRE
	-- visible (no gateado por Modo depuracion) para poder confirmarlo en el
	-- primer log que mande el usuario tras el proximo reinicio, sin tener
	-- que pedirle que active nada de antemano. No cambia ningun
	-- comportamiento, solo diagnostica.
	local okVerify, verifyData = pcall(function() return player:getModData() end)
	local verified = okVerify and verifyData and tostring(verifyData[CHARACTER_UUID_KEY] or "") or ""
	if verified ~= value and GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.error("Identity", "characterUuidWriteMismatch",
			"expected=" .. value .. " readback=" .. tostring(verified)
				.. " reason=" .. tostring(reason or "lookup_fallback")
				.. identityDiagnosticFields(player))
	end
	return value
end

local function getPersistentCharacterToken(player)
	-- BUG REAL de nombre, no de logica (2026-08-21, señalado por comunidad
	-- china via log analizado con IA, y confirmado al leer el codigo): este
	-- "reason" se pasaba SIEMPRE, incondicionalmente, en la ruta PRINCIPAL de
	-- resolucion de identidad (getCharacterId -> aqui, usada por
	-- canAccessZone/isOwnerPlayer/etc en cada comprobacion de permisos
	-- normal) - nunca fue una rama de emergencia. El nombre "fallback" hacia
	-- parecer una ruta de error disparandose sin parar en el log, cuando es
	-- el camino principal funcionando tal como esta diseñado. Renombrado
	-- para que el log describa lo que de verdad pasa.
	return getOrCreateCharacterUuid(player, "runtime_lookup")
end

--- Inicializa explícitamente la identidad al crear/cargar el personaje. El
--- lookup conserva un fallback seguro porque OnCreatePlayer no se entrega en
--- todos los contextos de SP/host, pero el log permite detectar esa ruta.
---@param player IsoPlayer|nil
---@param reason string|nil
---@return string characterId
function GlobalStorageSiK.Permissions.initializeCharacterIdentity(player, reason)
	local token = getOrCreateCharacterUuid(player, reason or "on_create_player")
	return token ~= "" and ("character:" .. token) or ""
end

--- ID legacy usado entre 1.3.71 y 1.3.76. SurvivorDesc.ID procede de un
--- contador local al proceso y puede repetirse entre clientes MP; jamás debe
--- autorizar por sí solo. Solo se conserva para migrar registros cuya cuenta
--- autoritativa también coincide.
local function getLegacyDescriptorId(player)
	if not player then return "" end
	local ok, value = pcall(function()
		local desc = player.getDescriptor and player:getDescriptor() or nil
		local id = desc and desc.getID and desc:getID() or nil
		if id ~= nil and tonumber(id) and tonumber(id) >= 0 then
			return "character:" .. tostring(id)
		end
		return ""
	end)
	return ok and value or ""
end

--- Identidad persistente de la encarnación. La única clave moderna es el UUID
--- GS guardado en player modData. Cuenta, Steam y sqlId son auditoría/migración:
--- una cuenta o ranura reutilizada por otro personaje nunca hereda permisos.
---@param player IsoPlayer|nil
---@return string
function GlobalStorageSiK.Permissions.getCharacterId(player)
	if not player then return "" end
	local username = normalizeName(getPlayerUsername(player))
	if GlobalStorageSiK.Permissions.shouldEnforce() and username == "" then
		return ""
	end
	local characterToken = getPersistentCharacterToken(player)
	if characterToken ~= "" then return "character:" .. characterToken end
	-- En cliente remoto el UUID puede no haber llegado todavía. Fallar cerrado
	-- es preferible a inventar una identidad basada en cuenta o nombre.
	if GlobalStorageSiK.Permissions.shouldEnforce() then return "" end
	local name = GlobalStorageSiK.Permissions.getCharacterName(player)
	return name ~= "" and ("legacy-name:" .. normalizeName(name)) or ""
end

local function isModernCharacterId(value)
	value = tostring(value or "")
	return validCharacterUuid(string.match(value, "^character:(gsc_.+)$") or "")
end

--- IDs emitidos únicamente por DEV4. Se aceptan solo como candidatos de una
--- migración acotada; nunca como prueba moderna de autorización.
local function getDev4CharacterIds(net, player)
	local result = {}
	local username = normalizeName(getPlayerUsername(player))
	if username == "" then return result end
	local prefix = "account:" .. username
	for storedId in pairs(net and net.characterPermissions or {}) do
		storedId = tostring(storedId or "")
		if storedId == prefix or string.sub(storedId, 1, #prefix + 1) == prefix .. "|" then
			result[#result + 1] = storedId
		end
	end
	return result
end

--- Rango de servidor (admin/moderator/overseer/gm) del jugador. DEUDA TECNICA
--- cerrada (2026-08-22): hasta dev3 esta funcion se usaba para saltarse TODA
--- la logica de permisos de red (canAccess, canAccessZone, isAdminPlayer,
--- requireAdminAccess) en cuanto el jugador tenia rango de staff - error de
--- diseno del sistema de permisos original, que confundio rango del SERVIDOR
--- con rol dentro de UNA red del mod (jugador puede ser admin del servidor y
--- no tener ningun rol en una red concreta, o vicecersa). Confirmado en
--- pruebas reales: bloqueaba probar el flujo de "red vacante/reclamar
--- propiedad" porque el admin de pruebas nunca llegaba a evaluarse contra esa
--- logica. Ya NO se usa en ninguna puerta operativa del mod - se conserva
--- solo como primitiva reservada para un futuro panel de soporte dedicado
--- (herramientas de GM/moderacion para redes ajenas, pendiente de diseno).
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.Permissions.isServerStaff(player)
	if not player then return false end
	local levels = { "admin", "moderator", "overseer", "gm" }
	for i = 1, #levels do
		local ok, allowed = pcall(function() return player:isAccessLevel(levels[i]) end)
		if ok and allowed == true then return true end
	end
	return false
end

local function mergeZoneDenials(net, oldKey, newKey)
	if not net or oldKey == "" or newKey == "" or oldKey == newKey then return end
	net.memberZoneDenials = net.memberZoneDenials or {}
	local source = net.memberZoneDenials[oldKey]
	if not source then return end
	local target = net.memberZoneDenials[newKey] or {}
	for zoneId, denied in pairs(source) do
		if denied == true then target[zoneId] = true end
	end
	net.memberZoneDenials[newKey] = target
	net.memberZoneDenials[oldKey] = nil
end

local function listContainsIdentity(values, name, username)
	local wantedName = normalizeName(name)
	local wantedUsername = normalizeName(username)
	for i = 1, #(values or {}) do
		local stored = normalizeName(values[i])
		if (wantedName ~= "" and stored == wantedName)
			or (wantedUsername ~= "" and stored == wantedUsername) then
			return true
		end
	end
	return false
end

local function logIdentityMigration(net, kind, oldId, newId, username)
	if not GlobalStorageSiK.Log then return end
	GlobalStorageSiK.Log.info("Permissions", "identityMigration",
		tostring(kind or "member")
			.. " network=" .. tostring(net and net.id or "")
			.. " account=" .. permissionLogText(username, 64)
			.. " old=" .. tostring(oldId or "")
			.. " new=" .. tostring(newId or ""))
end

--- Marca de tiempo estable para auditoria (joinedAt/diedAt/lastSeenAt).
--- Mismo patron que generateCharacterUuid() (GS_Permissions.lua:210-218):
--- getTimestampMs() si existe (motor), si no os.time()*1000, nunca falla.
---@return number
local function nowMs()
	return (getTimestampMs and getTimestampMs()) or (os and os.time and os.time() * 1000) or 0
end

-- BUG REAL de rendimiento cerrado (2026-08-23, reportado por analisis de
-- telemetria real de servidor: "canAccessDenied" repitiendose varias veces
-- por segundo para las mismas 2 redes, en una ruta sincrona muy frecuente).
-- canAccessDenied() se llama en CADA comprobacion de acceso fallida (varias
-- por segundo mientras una UI sigue pidiendo estado) - sin throttle, cada
-- personaje+red+DebugMode activo generaba una linea nueva por llamada. Una
-- linea por combinacion personaje+red cada DENIED_LOG_THROTTLE_MS es
-- suficiente para diagnosticar sin añadir trabajo perceptible a esta ruta.
local DENIED_LOG_THROTTLE_MS = 30000
local deniedLogLastMs = {}

---@param characterId string
---@param networkId string
---@return boolean shouldLog
local function shouldLogDenied(characterId, networkId)
	local key = tostring(characterId) .. "|" .. tostring(networkId)
	local last = deniedLogLastMs[key]
	local now = nowMs()
	if last and (now - last) < DENIED_LOG_THROTTLE_MS then
		return false
	end
	deniedLogLastMs[key] = now
	return true
end

-- Historico de auditoria por red (2026-08-22, ver comentario de
-- HISTORY_MODDATA_KEY en GS_Config.lua). Cada entrada: {ts, type, detail}.
-- Acotado a HISTORY_MAX_ENTRIES por red - descarta las mas antiguas al
-- superar el limite, nunca crece sin fin.
local HISTORY_MAX_ENTRIES = 40

local function getHistoryRegistry()
	if not ModData or not ModData.getOrCreate then return {} end
	local data = ModData.getOrCreate(GlobalStorageSiK.HISTORY_MODDATA_KEY)
	data.networks = data.networks or {}
	return data.networks
end

--- Añade una entrada al historico de una red. NUNCA llama a ModData.transmit
--- - esta ModData es deliberadamente propia del proceso autoritativo, se
--- persiste en disco igual (ModData.getOrCreate ya lo garantiza) pero no se
--- difunde a los clientes. Solo se lee para responder al comando
--- adminGetNetworkHistory.
---@param networkId string
---@param eventType string
---@param detail string
local function recordNetworkHistoryEvent(networkId, eventType, detail)
	if not networkId or networkId == "" then return end
	local historyByNetwork = getHistoryRegistry()
	local list = historyByNetwork[networkId]
	if not list then
		list = {}
		historyByNetwork[networkId] = list
	end
	list[#list + 1] = { ts = nowMs(), type = tostring(eventType or "?"), detail = tostring(detail or "") }
	while #list > HISTORY_MAX_ENTRIES do
		table.remove(list, 1)
	end
end

--- Wrapper publico de recordNetworkHistoryEvent - para llamantes fuera de
--- este fichero (GS_Server.lua: acciones del panel de soporte, donde el
--- jugador que actua ya esta a mano en el dispatcher de comandos).
---@param networkId string
---@param eventType string
---@param detail string
function GlobalStorageSiK.Permissions.recordHistoryEvent(networkId, eventType, detail)
	recordNetworkHistoryEvent(networkId, eventType, detail)
end

--- Vacia el historial de auditoria de una red (pedido explicito 2026-08-26,
--- "por si el usuario quiere iniciar un historial nuevo, efectivo") - NUNCA
--- toca miembros, roles ni ownership, solo este registro informativo.
---@param networkId string
---@return boolean
function GlobalStorageSiK.Permissions.clearNetworkHistory(networkId)
	if not networkId or networkId == "" then return false end
	local historyByNetwork = getHistoryRegistry()
	historyByNetwork[networkId] = {}
	return true
end

--- Lee el historico de una red para el panel de soporte. Copia superficial
--- (nunca la tabla interna) para que el llamante pueda serializarla en un
--- payload de red sin arriesgar mutarla por accidente.
---@param networkId string
---@return table[]
function GlobalStorageSiK.Permissions.adminGetNetworkHistory(networkId)
	local list = getHistoryRegistry()[networkId] or {}
	local out = {}
	for i = 1, #list do
		out[i] = { ts = list[i].ts, type = list[i].type, detail = list[i].detail }
	end
	return out
end

local function bindCharacter(net, player, role)
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	if characterId == "" then return nil end
	net.characterPermissions = net.characterPermissions or {}
	local record = net.characterPermissions[characterId] or {}
	record.characterName = GlobalStorageSiK.Permissions.getCharacterName(player)
	record.accountUsername = getPlayerUsername(player)
	record.steamId = getSteamIdForUsername(record.accountUsername, player)
	record.sqlId = getPersistentSqlId(player)
	-- Alias de lectura para consumidores/datos 1.3.x. Nunca son claves.
	record.name = record.characterName
	record.displayName = record.characterName
	record.username = record.accountUsername
	record.role = role or record.role or GlobalStorageSiK.Permissions.ROLE_MEMBER
	-- Auditoria (2026-08-21, diseño "herencia de red"): joinedAt se fija UNA
	-- sola vez (primera alta real de este UUID en esta red); lastSeenAt se
	-- refresca en cada bind (cualquier interaccion normal del personaje vivo
	-- pasa por aqui). diedAt NUNCA se toca aqui - solo lo escribe
	-- handleOwnerDeath cuando el personaje muere de verdad; un bind normal de
	-- un personaje vivo no debe borrar por accidente una muerte ya registrada
	-- de un UUID reciclado (no deberia pasar, pero mejor no asumir).
	record.joinedAt = record.joinedAt or nowMs()
	record.lastSeenAt = nowMs()
	net.characterPermissions[characterId] = record
	-- Un miembro de faccion puede haberse añadido estando desconectado. Mover
	-- sus excepciones nominales al ID del personaje sin perder ninguna.
	net.memberZoneDenials = net.memberZoneDenials or {}
	local legacyKeys = {
		zoneMemberKey(nil, record.name),
		zoneMemberKey(nil, player.getUsername and player:getUsername() or nil),
	}
	local target = net.memberZoneDenials[characterId]
	for i = 1, #legacyKeys do
		local legacyKey = legacyKeys[i]
		local legacy = legacyKey ~= "" and net.memberZoneDenials[legacyKey] or nil
		if legacy then
			target = target or {}
			for zoneId, denied in pairs(legacy) do
				if denied == true then target[zoneId] = true end
			end
			net.memberZoneDenials[legacyKey] = nil
		end
	end
	if target then net.memberZoneDenials[characterId] = target end
	-- FUENTE UNICA DE VERDAD para "quien es el dueño" (rediseño 2026-08-22,
	-- pedido explicito tras un bug real de propietario duplicado en
	-- produccion): role="owner" en ESTE registro es la unica condicion que
	-- importa, para cualquier consumidor, desde cualquier camino. bindCharacter
	-- es la funcion mas usada y mas probada de todo el fichero - se convierte
	-- aqui en el UNICO sitio que puede conceder role=owner, y automaticamente
	-- hace cumplir "como mucho un owner vivo por red": si esta ficha pasa a
	-- ser owner, cualquier OTRA ficha que todavia dijera owner baja a member
	-- (nunca se borra, nunca se pierde el historico - solo deja de decir algo
	-- que ya no es cierto). net.owner/ownerCharacterId/ownerAccountLogin/
	-- ownerSteamId pasan a ser una CACHE derivada de este registro, escrita
	-- SOLO aqui - ningun otro punto del fichero los asigna a mano nunca mas.
	if record.role == GlobalStorageSiK.Permissions.ROLE_OWNER then
		for otherId, otherRecord in pairs(net.characterPermissions) do
			if otherId ~= characterId and otherRecord and otherRecord.role == GlobalStorageSiK.Permissions.ROLE_OWNER then
				otherRecord.role = GlobalStorageSiK.Permissions.ROLE_MEMBER
			end
		end
		net.owner = record.characterName
		net.ownerCharacterId = characterId
		net.ownerAccountLogin = record.accountUsername
		net.ownerSteamId = record.steamId
	end
	return record
end

--- Version de bindCharacter para fichas SIN IsoPlayer vivo (panel de soporte:
--- adminSetOwner puede reasignar a alguien desconectado). Mismo invariante,
--- mismo unico escritor de la cache net.owner* - solo cambia de donde saca
--- los datos (la propia ficha ya almacenada, no un jugador en vivo).
---@param net table
---@param characterId string
---@param record table
local function applyOwnerRoleToRecord(net, characterId, record)
	record.role = GlobalStorageSiK.Permissions.ROLE_OWNER
	for otherId, otherRecord in pairs(net.characterPermissions or {}) do
		if otherId ~= characterId and otherRecord and otherRecord.role == GlobalStorageSiK.Permissions.ROLE_OWNER then
			otherRecord.role = GlobalStorageSiK.Permissions.ROLE_MEMBER
		end
	end
	net.owner = record.characterName or record.name or ""
	net.ownerCharacterId = characterId
	net.ownerAccountLogin = record.accountUsername or record.username or ""
	net.ownerSteamId = record.steamId or ""
end

--- Unico escritor de "muerte" de una ficha (handleOwnerDeath y la
--- reconciliacion automatica de propietario en canAccess). Mueve el rol
--- vigente a priorRole y deja role=ROLE_DEAD - ver comentario junto a la
--- constante para el porque. Idempotente: si ya estaba muerta no pisa un
--- priorRole ya guardado con "dead" otra vez.
---@param record table|nil
---@param whenMs number|nil
local function markRecordDead(record, whenMs)
	if not record or record.role == GlobalStorageSiK.Permissions.ROLE_DEAD then return end
	record.priorRole = record.role or GlobalStorageSiK.Permissions.ROLE_MEMBER
	record.role = GlobalStorageSiK.Permissions.ROLE_DEAD
	record.diedAt = whenMs or nowMs()
end

local function consumeLegacyMembership(net, name, username)
	local nameKey = normalizeName(name)
	local usernameKey = normalizeName(username)
	for _, field in ipairs({ "allowedUsers", "adminUsers" }) do
		local values = net[field] or {}
		for i = #values, 1, -1 do
			local stored = normalizeName(values[i])
			if (nameKey ~= "" and stored == nameKey)
				or (usernameKey ~= "" and stored == usernameKey) then
				table.remove(values, i)
			end
		end
	end
end

--- Migra un registro character:N únicamente si su cuenta y su permiso
--- nominal también coinciden. Esto evita convertir una colisión previa en un
--- permiso válido permanente.
local function migrateLegacyCharacterRecord(net, player)
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	if characterId == "" then return nil end
	net.characterPermissions = net.characterPermissions or {}
	if net.characterPermissions[characterId] then
		return net.characterPermissions[characterId]
	end
	local username = getPlayerUsername(player)
	local characterName = GlobalStorageSiK.Permissions.getCharacterName(player)
	local candidates = { getLegacyDescriptorId(player) }
	local dev4Ids = getDev4CharacterIds(net, player)
	for i = 1, #dev4Ids do candidates[#candidates + 1] = dev4Ids[i] end
	local legacyId = ""
	local legacy = nil
	for i = 1, #candidates do
		local candidateId = candidates[i]
		local candidate = candidateId ~= "" and net.characterPermissions[candidateId] or nil
		local accountMatches = candidate and normalizeName(candidate.username) ~= ""
			and normalizeName(candidate.username) == normalizeName(username)
		local dev4MatchesCharacter = candidate and (
			string.sub(candidateId, 1, 8) ~= "account:"
			or normalizeName(candidate.name) == normalizeName(characterName))
		if accountMatches and dev4MatchesCharacter
			and candidate.role ~= GlobalStorageSiK.Permissions.ROLE_OWNER
			and candidate.role ~= GlobalStorageSiK.Permissions.ROLE_DEAD then
			local nominallyAllowed = listContainsIdentity(net.allowedUsers, candidate.name, username)
				or listContainsIdentity(net.adminUsers, candidate.name, username)
			if nominallyAllowed then
				legacyId = candidateId
				legacy = candidate
				break
			end
		end
	end
	-- BUG REAL cerrado (2026-08-26, revision tecnica de Desarrollo tras
	-- probar en TEST): la version anterior de este bloque intentaba un
	-- respaldo via IsoPlayer:getSqlId() - metodo que NO EXISTE en B42.20.4
	-- (confirmado con javap sobre projectzomboid.jar: IsoPlayer solo expone
	-- el CAMPO publico "sqlId", sin getter), asi que ese respaldo nunca podia
	-- activarse - codigo muerto. Ademas, aunque se consiguiera leer, sqlId
	-- identifica una FILA de la base de datos de guardado, no una vida: la
	-- misma fila puede reasignarse a un personaje nuevo (cuenta+mundo+slot
	-- reciclados), asi que "mismo sqlId" nunca demuestra "misma vida" y no
	-- debe usarse para autorizar nada. Retirado sin sustituto - un candidato
	-- sin coincidencia de nombre/cuenta se queda sin migrar (el jugador
	-- necesitara que un admin lo reasigne a mano via el panel de soporte).
	if not legacy then return nil end
	net.characterPermissions[legacyId] = nil
	net.characterPermissions[characterId] = legacy
	mergeZoneDenials(net, legacyId, characterId)
	local role = legacy.role ~= GlobalStorageSiK.Permissions.ROLE_DEAD and legacy.role
		or (legacy.priorRole or GlobalStorageSiK.Permissions.ROLE_MEMBER)
	local record = bindCharacter(net, player, role)
	consumeLegacyMembership(net, record.name, record.username)
	logIdentityMigration(net, "member", legacyId, characterId, username)
	return record
end

--- Vincula al propietario usando la cuenta autoritativa. Si el dato procede
--- del esquema legacy, el nombre o el ID aislado nunca bastan cuando existe
--- ownerAccount: esa cuenta es el ancla que impide el cruce de propietarios.
local function bindOwnerIdentity(net, player)
	if not net or not player then return false end
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	if characterId == "" then return false end
	if net.ownerCharacterId == characterId then
		-- bindCharacter con ROLE_OWNER ya actualiza net.owner/ownerAccountLogin/
		-- ownerSteamId internamente (fuente unica de verdad) - no hace falta
		-- repetirlo aqui a mano.
		bindCharacter(net, player, GlobalStorageSiK.Permissions.ROLE_OWNER)
		return true
	end
	local storedId = tostring(net.ownerCharacterId or "")
	if isModernCharacterId(storedId) then return false end
	-- BUG REAL DE SEGURIDAD cerrado (2026-08-22, confirmado en pruebas
	-- reales: "tenemos acceso directamente... nos permite trabajar como
	-- propietario como si nada" nada mas conectar con el personaje nuevo,
	-- sin pasar por ningun terminal ni pulsar "Reclamar propiedad"):
	-- storedId=="" describe DOS situaciones que este camino legacy no
	-- distinguia - una red GENUINAMENTE nunca migrada (storedId siempre
	-- vacio Y ownerAccountLogin tambien vacio, caso legitimo de este bloque,
	-- pensado para mundos anteriores al sistema de cuentas/UUID) y una red
	-- VACANTE por el sistema moderno (ownerCharacterId limpiado a proposito
	-- tras una reconciliacion de propietario o una muerte - ver canAccess -
	-- pero ownerAccountLogin SI conservado a proposito, es el ancla de la
	-- cascada de herencia). El segundo caso NUNCA debe poder saltarse aqui
	-- la cascada de reclamo explicito (canClaimVacantOwnership/
	-- claimVacantOwnership) solo porque la cuenta coincida - es exactamente
	-- el atajo que el diseño "herencia de red" (dev21) queria cerrar, y que
	-- isOwnerPlayer() comparte por el mismo motivo (ver su propio comentario).
	if storedId == "" and displayText(net.ownerAccountLogin) ~= "" then
		return false
	end
	local username = getPlayerUsername(player)
	local accountMatches = normalizeName(net.ownerAccountLogin) ~= ""
		and normalizeName(net.ownerAccountLogin) == normalizeName(username)
	local currentSteamId = getSteamIdForUsername(username, player)
	if accountMatches and displayText(net.ownerSteamId) ~= ""
		and currentSteamId ~= "" and displayText(net.ownerSteamId) ~= currentSteamId then
		accountMatches = false
	end
	local isDescriptorLegacy = string.match(storedId, "^character:%d+$") ~= nil
	local isNameLegacy = storedId == "" or string.sub(storedId, 1, 12) == "legacy-name:"
	local isDev4Id = false
	local dev4Ids = getDev4CharacterIds(net, player)
	for i = 1, #dev4Ids do
		if storedId == dev4Ids[i] then isDev4Id = true; break end
	end
	if isDev4Id then
		local oldRecord = net.characterPermissions and net.characterPermissions[storedId] or nil
		accountMatches = accountMatches and oldRecord ~= nil
			and normalizeName(oldRecord.name) == normalizeName(
				GlobalStorageSiK.Permissions.getCharacterName(player))
	elseif not isDescriptorLegacy and not isNameLegacy then
		return false
	end
	if not accountMatches and normalizeName(net.ownerAccountLogin) == "" and isNameLegacy then
		local characterName = GlobalStorageSiK.Permissions.getCharacterName(player)
		accountMatches = not isCharacterNameAmbiguous(characterName)
			and GlobalStorageSiK.Permissions.identityMatches(player, net.owner)
	end
	if not accountMatches then return false end
	if storedId ~= "" and storedId ~= characterId then
		net.characterPermissions = net.characterPermissions or {}
		net.characterPermissions[storedId] = nil
		if net.memberZoneDenials then net.memberZoneDenials[storedId] = nil end
	end
	-- bindCharacter con ROLE_OWNER ya actualiza los 4 campos de red - no hace
	-- falta repetirlo aqui a mano (fuente unica de verdad).
	bindCharacter(net, player, GlobalStorageSiK.Permissions.ROLE_OWNER)
	logIdentityMigration(net, "owner", storedId, characterId, username)
	return true
end

isCharacterNameAmbiguous = function(name)
	local wanted = normalizeName(name)
	local count = 0
	local players = nil
	if getOnlinePlayers then
		local ok, value = pcall(getOnlinePlayers)
		if ok then players = value end
	end
	if not players and getActivePlayers then
		local ok, value = pcall(getActivePlayers)
		if ok then players = value end
	end
	if players and players.size then
		for i = 0, players:size() - 1 do
			if normalizeName(GlobalStorageSiK.Permissions.getCharacterName(players:get(i))) == wanted then
				count = count + 1
				if count > 1 then return true end
			end
		end
	end
	return false
end

--- Comparador exclusivamente legacy para migrar mundos sin ownerAccount/UUID.
--- Nunca debe participar en la autorización moderna normal.
---@param player IsoPlayer
---@param stored string
---@return boolean
function GlobalStorageSiK.Permissions.identityMatches(player, stored)
	stored = normalizeName(stored)
	if stored == "" then
		return false
	end
	if stored == normalizeName(GlobalStorageSiK.Permissions.getCharacterName(player)) then
		return true
	end
	if stored == normalizeName(GlobalStorageSiK.Permissions.getCharacterId(player)) then
		return true
	end
	if player.getUsername and stored == normalizeName(player:getUsername()) then
		return true
	end
	return false
end

--- Inicializa la estructura de permisos de una red (tablas vacías si no
--- existen todavia). NUNCA toca net.owner/ownerCharacterId/ownerAccountLogin/
--- ownerSteamId - esos 4 campos tienen un unico escritor atomico
--- (bindCharacter/applyOwnerRoleToRecord, ver su comentario) y nada mas debe
--- asignarlos nunca.
--- BUG REAL DE SEGURIDAD cerrado (2026-08-22, confirmado en pruebas reales:
--- panel de staff mostrando "Kava 4" como propietario con
--- ownerCharacterId=nil, "desconectado" pese a estar jugando en ese mismo
--- momento): el parametro ownerCharacter que tenia esta funcion escribia
--- net.owner en SOLITARIO (sin los otros 3 campos) cada vez que canAccess()
--- se llamaba sobre una red VACANTE (ownerAccountLogin conservado tras una
--- reconciliacion/muerte) - literalmente el nombre de personaje de QUIEN
--- FUERA que preguntara primero, contaminando el estado de la red sin pasar
--- nunca por bindCharacter ni por la cascada de reclamo. Bug de la misma
--- clase que el ya cerrado en isOwnerPlayer()/bindOwnerIdentity() esta misma
--- ronda - una tercera funcion con el mismo agujero. El parametro se
--- elimina por completo: una red genuinamente nueva ya se inicializa de
--- forma atomica via initializeOwner()/bindCharacter en su propio call site
--- (ver GS_TerminalRegistry.lua), esta funcion no necesita ni debe hacerlo.
---@param registry table
---@param networkId string
function GlobalStorageSiK.Permissions.ensure(registry, networkId)
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	net.allowedUsers = net.allowedUsers or {}
	net.allowedFactions = net.allowedFactions or {}
	net.adminUsers = net.adminUsers or {}
	net.characterPermissions = net.characterPermissions or {}
	net.memberZoneDenials = net.memberZoneDenials or {}
	net.factionOnly = net.factionOnly == true
end

--- Inicializa la propiedad de una red nueva en una sola operación. Evita que
--- exista una ventana en la que haya nombre/cuenta pero falte el ID seguro.
---@param net table
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.Permissions.initializeOwner(net, player)
	if not net or not player then return false end
	local username = getPlayerUsername(player)
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	if GlobalStorageSiK.Permissions.shouldEnforce()
		and (username == "" or characterId == "") then
		return false
	end
	-- bindCharacter con ROLE_OWNER ya actualiza los 4 campos de red - no hace
	-- falta repetirlo aqui a mano (fuente unica de verdad).
	bindCharacter(net, player, GlobalStorageSiK.Permissions.ROLE_OWNER)
	return net.ownerCharacterId ~= nil and net.ownerCharacterId ~= ""
end

--- Elimina referencias a zonas que ya no existen o pertenecen a otra red.
--- Las zonas nuevas no se añaden: ausencia significa acceso permitido.
function GlobalStorageSiK.Permissions.cleanupZoneDenials(networkId)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then return end
	net.memberZoneDenials = net.memberZoneDenials or {}
	local memberKeys = {}
	for memberKey in pairs(net.memberZoneDenials) do memberKeys[#memberKeys + 1] = memberKey end
	for i = 1, #memberKeys do
		local memberKey = memberKeys[i]
		local denied = net.memberZoneDenials[memberKey]
		local zoneKeys = {}
		for zoneId in pairs(denied or {}) do zoneKeys[#zoneKeys + 1] = zoneId end
		for j = 1, #zoneKeys do
			local zoneId = zoneKeys[j]
			local zone = registry.zones and registry.zones[zoneId]
			if not zone or zone.networkId ~= networkId then denied[zoneId] = nil end
		end
		if not tableHasEntries(denied) then net.memberZoneDenials[memberKey] = nil end
	end
end

--- Devuelve si el jugador puede usar los contenedores de una zona. Owner y
--- admins de LA RED conservan acceso total (el rango de staff del servidor ya
--- no concede bypass aqui, ver comentario de isServerStaff). En SP no se
--- aplican permisos.
function GlobalStorageSiK.Permissions.canAccessZone(player, networkId, zoneId)
	if not player then return false end
	if not GlobalStorageSiK.Permissions.shouldEnforce() then return true end
	if GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId)
		or GlobalStorageSiK.Permissions.isAdminPlayer(player, networkId) then
		return true
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then return false end
	local key = zoneMemberKey(
		GlobalStorageSiK.Permissions.getCharacterId(player),
		GlobalStorageSiK.Permissions.getCharacterName(player))
	local denied = net.memberZoneDenials and net.memberZoneDenials[key]
	return not (denied and denied[tostring(zoneId or "")] == true)
end

--- Filtra entradas de getLiveContainers conservando su estructura original.
function GlobalStorageSiK.Permissions.filterLiveContainers(player, networkId, live)
	if not player or not GlobalStorageSiK.Permissions.shouldEnforce() then return live or {} end
	local filtered = {}
	for i = 1, #(live or {}) do
		local row = live[i]
		local zoneId = row and row.entry and row.entry.zoneId
		if zoneId and GlobalStorageSiK.Permissions.canAccessZone(player, networkId, zoneId) then
			filtered[#filtered + 1] = row
		end
	end
	return filtered
end

--- Sustituye atómicamente las zonas denegadas de un miembro normal.
function GlobalStorageSiK.Permissions.setMemberZoneDenials(networkId, characterId, characterName, zoneIds)
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId)
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	local key = zoneMemberKey(characterId, characterName)
	if key == "" then return false, "invalid_member" end
	local role = nil
	if characterId and characterId ~= "" then
		local record = net.characterPermissions and net.characterPermissions[characterId]
		role = record and record.role or nil
	else
		local wanted = normalizeName(characterName)
		for i = 1, #(net.allowedUsers or {}) do
			if normalizeName(net.allowedUsers[i]) == wanted then role = GlobalStorageSiK.Permissions.ROLE_MEMBER; break end
		end
		for i = 1, #(net.adminUsers or {}) do
			if normalizeName(net.adminUsers[i]) == wanted then role = GlobalStorageSiK.Permissions.ROLE_ADMIN; break end
		end
	end
	if role ~= GlobalStorageSiK.Permissions.ROLE_MEMBER then return false, "invalid_role" end
	local denied = {}
	for i = 1, math.min(#(zoneIds or {}), 512) do
		local zoneId = tostring(zoneIds[i] or "")
		local zone = registry.zones and registry.zones[zoneId]
		if zoneId ~= "" and zone and zone.networkId == networkId then denied[zoneId] = true end
	end
	if tableHasEntries(denied) then net.memberZoneDenials[key] = denied
	else net.memberZoneDenials[key] = nil end
	return true
end

--- Indica si el personaje tiene rol admin O SUPERIOR (admin u owner) DENTRO
--- de esta red - pese al nombre "isAdminPlayer" (paralelo a isOwnerPlayer,
--- mismo patron is<Rol>Player), esto es un UMBRAL ("admin o superior"), no
--- una igualdad exacta de rol - igual que "requireAdminAccess" en
--- GS_Server.lua tambien deja pasar al propietario. No concede acceso por
--- rango global del servidor (ver comentario de isServerStaff).
--- Unificado 2026-08-22 (auditoria de naming): antes existian DOS nombres
--- para esta misma funcion (isAdminPlayer llamaba a hasNetworkAdminRole,
--- identicas) - se deja un unico nombre, canonico, en la familia is<Rol>Player.
---@param player IsoPlayer
---@param networkId string
---@return boolean
function GlobalStorageSiK.Permissions.isAdminPlayer(player, networkId)
	if GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId) then
		return true
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then return false end
	local charName = GlobalStorageSiK.Permissions.getCharacterName(player)
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	local record = net.characterPermissions and net.characterPermissions[characterId]
		or migrateLegacyCharacterRecord(net, player)
	if record then
		return record.role == GlobalStorageSiK.Permissions.ROLE_ADMIN
	end
	local usernameKey = normalizeName(getPlayerUsername(player))
	local characterKey = normalizeName(charName)
	local characterAmbiguous = isCharacterNameAmbiguous(charName)
	for i = 1, #(net.adminUsers or {}) do
		local stored = normalizeName(net.adminUsers[i])
		if (usernameKey ~= "" and stored == usernameKey)
			or (not characterAmbiguous and stored == characterKey) then
			local bound = bindCharacter(net, player, GlobalStorageSiK.Permissions.ROLE_ADMIN)
			consumeLegacyMembership(net, bound.name, bound.username)
			return true
		end
	end
	return false
end

--- Devuelve el rol del jugador en la red: "owner" | "admin" | "member".
---@param player IsoPlayer
---@param networkId string
---@return string
function GlobalStorageSiK.Permissions.getPlayerRole(player, networkId)
	if GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId) then
		return GlobalStorageSiK.Permissions.ROLE_OWNER
	end
	if GlobalStorageSiK.Permissions.isAdminPlayer(player, networkId) then
		return GlobalStorageSiK.Permissions.ROLE_ADMIN
	end
	return GlobalStorageSiK.Permissions.ROLE_MEMBER
end

--- Establece o quita el rol admin de un miembro.
---@param networkId string
---@param characterName string
---@param role string "admin" | "member"
---@return boolean ok
function GlobalStorageSiK.Permissions.setUserRole(networkId, characterName, role)
	local displayName = displayText(characterName)
	local characterKey = normalizeName(displayName)
	if characterKey == "" then return false end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId)
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if net.owner and normalizeName(net.owner) == characterKey then
		return false  -- no se puede cambiar el rol del owner
	end
	net.adminUsers = net.adminUsers or {}
	-- quitar de adminUsers primero
	for i = #net.adminUsers, 1, -1 do
		if normalizeName(net.adminUsers[i]) == characterKey then
			table.remove(net.adminUsers, i)
		end
	end
	if role == GlobalStorageSiK.Permissions.ROLE_ADMIN then
		-- asegurarse de que está en allowedUsers
		local inUsers = false
		for i = 1, #net.allowedUsers do
			if normalizeName(net.allowedUsers[i]) == characterKey then
				net.allowedUsers[i] = displayName
				inUsers = true; break
			end
		end
		if not inUsers then
			net.allowedUsers[#net.allowedUsers + 1] = displayName
		end
		net.adminUsers[#net.adminUsers + 1] = displayName
	end
	return true
end

--- Comprueba si dos cuentas comparten facción.
---@param usernameA string
---@param usernameB string
---@return boolean
function GlobalStorageSiK.Permissions.sameFaction(usernameA, usernameB)
	if not Faction or not Faction.getPlayerFaction then
		return false
	end
	local fa = Faction.getPlayerFaction(usernameA)
	local fb = Faction.getPlayerFaction(usernameB)
	if not fa or not fb then
		return false
	end
	return fa:getName() == fb:getName()
end

--- Obtiene facción del jugador.
---@param player IsoPlayer
---@return table|nil
function GlobalStorageSiK.Permissions.getPlayerFaction(player)
	if not player or not Faction or not Faction.getPlayerFaction then
		return nil
	end
	local ok, fac = pcall(function()
		return Faction.getPlayerFaction(player:getUsername())
	end)
	if ok then
		return fac
	end
	return nil
end

--- Devuelve las cuentas que vanilla conserva como miembros de la facción,
--- incluido el propietario. `Faction:getPlayers()` es precisamente la fuente
--- persistente que usa ISFactionUI y contiene también usuarios desconectados;
--- no intentar sustituirla por getOnlinePlayers().
---@param player IsoPlayer
---@return string[] usernames
---@return any faction
function GlobalStorageSiK.Permissions.getFactionUsernames(player)
	local faction = GlobalStorageSiK.Permissions.getPlayerFaction(player)
	local result = {}
	local seen = {}
	if not faction then
		return result, nil
	end
	local function add(username)
		local key = normalizeName(username)
		if key == "" or seen[key] then return end
		seen[key] = true
		result[#result + 1] = tostring(username)
	end
	if faction.getOwner then
		local ok, owner = pcall(function() return faction:getOwner() end)
		if ok then add(owner) end
	end
	if faction.getPlayers then
		local ok, players = pcall(function() return faction:getPlayers() end)
		if ok and players then
			if players.size then
				for i = 0, players:size() - 1 do
					add(players:get(i))
				end
			elseif type(players) == "table" then
				for i = 1, #players do
					add(players[i])
				end
			end
		end
	end
	table.sort(result, function(a, b) return normalizeName(a) < normalizeName(b) end)
	return result, faction
end

---@param player IsoPlayer
---@param username string
---@return boolean
function GlobalStorageSiK.Permissions.isFactionUsername(player, username)
	local wanted = normalizeName(username)
	if wanted == "" then return false end
	local usernames = GlobalStorageSiK.Permissions.getFactionUsernames(player)
	for i = 1, #usernames do
		if normalizeName(usernames[i]) == wanted then
			return true
		end
	end
	return false
end

--- Resuelve nombre de personaje desde cuenta (jugadores conectados).
---@param username string
---@return string
function GlobalStorageSiK.Permissions.resolveCharacterName(username)
	local exactUsername = displayText(username)
	local usernameKey = normalizeName(exactUsername)
	if usernameKey == "" then
		return ""
	end
	if getPlayerFromUsername then
		local ok, player = pcall(getPlayerFromUsername, exactUsername)
		if ok and player then
			return GlobalStorageSiK.Permissions.getCharacterName(player)
		end
	end
	if getActivePlayers then
		local ok, players = pcall(getActivePlayers)
		if ok and players and players.size then
			for i = 0, players:size() - 1 do
				local p = players:get(i)
				if p and p.getUsername and normalizeName(p:getUsername()) == usernameKey then
					return GlobalStorageSiK.Permissions.getCharacterName(p)
				end
			end
		end
	end
	return exactUsername
end

--- Resuelve cuenta desde nombre de personaje (jugadores conectados).
---@param characterName string
---@return string|nil
function GlobalStorageSiK.Permissions.resolveUsernameFromCharacter(characterName)
	local characterKey = normalizeName(characterName)
	if characterKey == "" then
		return nil
	end
	if getActivePlayers then
		local ok, players = pcall(getActivePlayers)
		if ok and players and players.size then
			for i = 0, players:size() - 1 do
				local p = players:get(i)
				if p and normalizeName(GlobalStorageSiK.Permissions.getCharacterName(p)) == characterKey then
					return p:getUsername()
				end
			end
		end
	end
	return nil
end

--- Comprueba acceso del jugador a la red.
---@param player IsoPlayer
---@param networkId string
---@return boolean allowed
---@return string|nil reason
function GlobalStorageSiK.Permissions.canAccess(player, networkId)
	if not player then
		return false, "no_player"
	end
	if not GlobalStorageSiK.Permissions.shouldEnforce() then
		return true
	end
	-- El rango de staff del servidor ya NO concede bypass aqui (deuda tecnica
	-- cerrada 2026-08-22, ver comentario de isServerStaff) - un admin del
	-- servidor sigue la misma logica de acceso/reclamacion que cualquier
	-- jugador dentro del sistema de permisos propio del mod.
	local characterName = GlobalStorageSiK.Permissions.getCharacterName(player)
	local username = player:getUsername()
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId)
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	-- BUG REAL cerrado (2026-08-23, encontrado revisando log real de
	-- servidor: "owner=Kava 4 ownerCharacterId=nil" con el propio dueño
	-- conectado y denegado): datos de una version anterior a la separacion
	-- de responsabilidades (2026-08-22) podian dejar net.owner con el
	-- nombre del propietario pero SIN net.ownerCharacterId enlazado -
	-- bindCharacter/applyOwnerRoleToRecord (unico escritor actual de ambos
	-- campos) siempre los escriben a la vez, pero nunca migraron datos ya
	-- guardados asi. Sin ese enlace ni isOwnerPlayer() reconoce al dueño
	-- real, ni la red se considera vacante (net.owner no esta vacio) - se
	-- queda atascada para siempre, ni el propio dueño puede reclamarla. El
	-- nombre por si solo no sirve para reparar esto con seguridad (PZ anade
	-- un sufijo de desambiguacion tipo "Kava 4" cuando hay/hubo varios
	-- personajes con el mismo nombre, que nunca coincide con el nombre
	-- actual sin sufijo) - se usa la cuenta (ownerAccountLogin), la unica
	-- señal estable que no depende del nombre de personaje.
	-- Acotado a "una sola vez por red" (2026-08-26, revision tecnica de
	-- Desarrollo): esta reparacion existe para migrar datos de un esquema
	-- LEGACY concreto (anterior a 2026-08-22, sin ownerCharacterId enlazado)
	-- - dejarla activa para siempre en canAccess() significa que CUALQUIER
	-- corrupcion parcial futura que deje ownerCharacterId vacio (por el
	-- motivo que sea, no solo el caso legacy original) otorgaria ownership
	-- automaticamente a la primera cuenta coincidente que se conecte, sin
	-- intervencion humana. net.ownerLinkRepairedOnce se fija tras la primera
	-- reparacion real y bloquea cualquier repeticion en esa misma red.
	if (not net.ownerCharacterId or net.ownerCharacterId == "") and net.owner and net.owner ~= ""
		and characterId ~= "" and not net.ownerLinkRepairedOnce then
		local ownerAccountKey = normalizeName(net.ownerAccountLogin)
		local myAccountKey = normalizeName(username)
		if ownerAccountKey ~= "" and ownerAccountKey == myAccountKey then
			if GlobalStorageSiK.Log then
				GlobalStorageSiK.Log.warn("Permissions", "ownerLinkRepaired",
					networkId .. ": " .. tostring(net.owner) .. " (cuenta " .. tostring(username)
						.. ") recuperado sin ownerCharacterId enlazado (datos de una version anterior) - "
						.. "re-enlazado a characterId=" .. characterId .. " (reparacion unica de esta red)")
			end
			recordNetworkHistoryEvent(networkId, "owner_link_repaired",
				tostring(net.owner) .. " (cuenta " .. tostring(username) .. ") re-enlazado como propietario: "
					.. "faltaba ownerCharacterId, datos de una version anterior")
			bindCharacter(net, player, GlobalStorageSiK.Permissions.ROLE_OWNER)
			net.ownerLinkRepairedOnce = true
		end
	end
	-- RECONCILIACION QUIRURGICA (2026-08-22): red de pruebas real confirmo
	-- que Events.OnPlayerDeath puede no dejar net.owner limpio (motivo exacto
	-- aun sin confirmar - ver traza siempre visible añadida en el propio
	-- handler de GS_Server.lua) - eso deja la red "atascada" para siempre,
	-- ni el propio dueño puede reclamarla porque canAccess nunca llega a la
	-- rama de red vacante. Se dispara SOLO cuando hay evidencia fuerte, no
	-- una suposicion: la CUENTA que aparece como dueña (ownerAccountLogin)
	-- esta accediendo ahora mismo con un characterId DISTINTO al guardado
	-- (`net.ownerCharacterId`) - como el UUID es por-vida-de-personaje y
	-- nunca se reutiliza, una cuenta con un UUID nuevo solo puede significar
	-- que su vida anterior termino (murio o fue reseteada), nunca que sigue
	-- viva en otro sitio. Deliberadamente NO se intenta detectar esto para
	-- CUALQUIER otro jugador que se acerque (sarini, etc.) - no hay señal
	-- fiable de que el dueño este muerto desde fuera de su propia cuenta, y
	-- adivinarlo (ej. por inactividad prolongada) seria especulativo. Ese
	-- caso (dueño que nunca vuelve, admin/member necesitan entrar) sigue
	-- dependiendo del panel de soporte GM/moderacion (accion humana
	-- explicita), a proposito - no hay forma segura de automatizarlo sin
	-- arriesgar un falso positivo que expulse a un dueño realmente activo.
	-- Motivo especifico para la UI (2026-08-26, revision tecnica de
	-- Desarrollo): "denied" generico hacia que el panel de bloqueo mostrara
	-- "Sin terminal cercano" para un caso que en realidad es "esta cuenta
	-- tiene otra vida en esta red, puede reclamarla" - mensaje enganoso, no
	-- un problema de deteccion de terminal. Si esta rama detecta el caso,
	-- se propaga hasta el return final SOLO si ninguna otra comprobacion
	-- posterior (rol propio ya vigente, etc.) concede acceso de otra forma.
	local rotationUnprovenReason = nil
	if net.owner and net.owner ~= "" and net.ownerCharacterId and net.ownerCharacterId ~= ""
		and net.ownerCharacterId ~= characterId then
		local ownerAccountKey = normalizeName(net.ownerAccountLogin)
		local myAccountKey = normalizeName(username)
		if ownerAccountKey ~= "" and ownerAccountKey == myAccountKey and characterId ~= "" then
			local staleRecord = net.characterPermissions and net.characterPermissions[net.ownerCharacterId]
			local confirmedDead = staleRecord and staleRecord.role == GlobalStorageSiK.Permissions.ROLE_DEAD
			if confirmedDead then
				-- Muerte YA confirmada por el camino normal (handleOwnerDeath /
				-- markRecordDead ya marco esta ficha ROLE_DEAD antes de que esta
				-- cuenta volviera a conectar) - aqui SI es seguro vaciar la red
				-- para reclamo explicito, la vida anterior termino de verdad.
				if GlobalStorageSiK.Log then
					GlobalStorageSiK.Log.warn("Permissions", "ownerReconciled",
						networkId .. ": cuenta " .. tostring(username) .. " vuelve con characterId nuevo ("
							.. characterId .. ", antes " .. tostring(net.ownerCharacterId)
							.. ") - muerte de " .. tostring(net.owner)
							.. " ya confirmada (ROLE_DEAD), red pasa a vacante para reclamo explicito")
				end
				recordNetworkHistoryEvent(networkId, "owner_reconciled",
					tostring(net.owner) .. " (cuenta " .. tostring(username) .. ") reconciliado: "
						.. "muerte ya confirmada, red pasa a vacante")
				net.owner = ""
				net.ownerCharacterId = nil
				GlobalStorageSiK.Permissions.requestTransmit()
			else
				-- BUG REAL cerrado (2026-08-26, revision tecnica de Desarrollo tras
				-- probar en TEST): la version anterior de esta rama daba por hecho
				-- que "misma cuenta, characterId distinto, sin ROLE_DEAD" solo podia
				-- significar "vida anterior terminada sin evento de muerte
				-- procesado" - inferencia NUNCA demostrada y ya refutada por casos
				-- reales (comunidad china, reportes de Kava): el UUID de modData
				-- puede perderse/regenerarse por una falla de persistencia del
				-- motor SIN que el personaje haya muerto. Vaciar la red y marcar
				-- la ficha anterior como fallecida en ese caso es destruir datos
				-- reales sobre una suposicion no probada. Ahora, sin una muerte YA
				-- confirmada (ROLE_DEAD) por el camino normal, NO se toca
				-- ownership/roles/estado de muerte - se deja constancia de la
				-- rotacion sin destruir nada, igual que ya se hace a proposito para
				-- cualquier rol que no sea owner (ver comentario mas arriba: "no
				-- hay señal fiable... sigue dependiendo del panel de soporte GM").
				-- Recuperacion sin intervencion automatica de canAccess: la propia
				-- cuenta puede reclamar explicitamente via canClaimVacantOwnership
				-- Nivel 0 (arreglado 2026-08-26, ya no exige vacante para el
				-- propietario original) - un clic deliberado, nunca un efecto
				-- secundario de conectar. Si tampoco reclama, Admin Dashboard
				-- ("Liberar propiedad") sigue disponible como via de soporte.
				rotationUnprovenReason = "identity_rotation_unproven"
				-- BUG REAL cerrado (2026-08-26, revision tecnica de Desarrollo:
				-- "271 identityRotationUnproven en una sola conexion" - el sondeo
				-- periodico de la ventana de bloqueo repite canAccess() cada pocos
				-- segundos, sin throttle esta linea se repetia sin parar mientras
				-- la ventana siguiera abierta). Mismo throttle ya usado para
				-- canAccessDenied (30s por combinacion characterId+networkId).
				if shouldLogDenied(characterId, networkId) then
					if GlobalStorageSiK.Log then
						GlobalStorageSiK.Log.warn("Permissions", "identityRotationUnproven",
							networkId .. ": cuenta " .. tostring(username) .. " vuelve con characterId nuevo ("
								.. characterId .. ", antes " .. tostring(net.ownerCharacterId)
								.. ") sin muerte confirmada de " .. tostring(net.owner)
								.. " - NO se toca ownership/roles/muerte automaticamente, reclamo propio disponible")
					end
					-- BUG REAL cerrado (2026-08-26, pedido explicito: "todo cambio debe
					-- guardarse tambien en el historial, que no habremos actualizado
					-- debidamente"): esta rama solo escribia en consola, nunca en el
					-- historial de auditoria visible desde el panel de soporte - a
					-- diferencia de la rama confirmedDead de arriba, que si lo hace.
					-- Mismo throttle que el log (30s) para no llenar los 40 huecos de
					-- HISTORY_MAX_ENTRIES con la misma reconexion repetida.
					recordNetworkHistoryEvent(networkId, "identity_rotation_unproven",
						tostring(username) .. " vuelve con un personaje nuevo (" .. tostring(characterName)
							.. ") sin muerte confirmada de " .. tostring(net.owner)
							.. " - reclamo propio disponible, sin cambios automaticos")
				end
			end
		end
	end
	-- REDISEÑO explicito (2026-08-23, feedback directo del usuario: "los
	-- miembros y administradores que queden en una red cuyo propietario
	-- muere, no deben perder el acceso... nadie lo ha solicitado, es una
	-- decision equivocada"): un admin/member YA vinculado bajo su
	-- characterId ACTUAL conserva su propio acceso sin importar si la red
	-- tiene dueño ahora mismo - la vacante de OTRO puesto (el owner) nunca
	-- debe expulsar a alguien que ya tiene su propio puesto vigente. Antes,
	-- el gate de "red vacante" (mas abajo) cortaba el paso a CUALQUIERA,
	-- admin/member incluido, antes de mirar siquiera si tenian su propia
	-- ficha viva - la pantalla de bloqueo/reclamo es correcta SOLO para
	-- quien no tiene puesto propio (personaje nuevo, o su propio personaje
	-- murio - ver canRecoverOwnRole mas abajo), nunca para quien ya lo tiene.
	local ownRecord = net.characterPermissions and net.characterPermissions[characterId]
	if ownRecord and ownRecord.role ~= GlobalStorageSiK.Permissions.ROLE_DEAD then
		bindCharacter(net, player, ownRecord.role)
		return true
	end
	if not net.owner or net.owner == "" then
		-- BUG REAL DE SEGURIDAD cerrado (2026-08-21, diseño "herencia de red"):
		-- esto concedia la propiedad al PRIMER jugador que se acercara/abriera
		-- este terminal, sin comprobar cuenta - en un servidor compartido,
		-- cualquiera que llegase antes que el heredero legitimo a una red
		-- vacante por muerte del dueño se la quedaba. Se distingue ahora entre
		-- dos casos reales, distintos:
		--   (a) Red NUEVA de verdad (nunca tuvo dueño - net.ownerAccountLogin
		--       vacio): mismo comportamiento de siempre, el primero que la usa
		--       la reclama - no romper el flujo de "primer terminal instalado".
		--   (b) Red VACANTE por muerte de un dueño anterior
		--       (net.ownerAccountLogin ya tiene algo guardado, ver
		--       handleOwnerDeath): NUNCA se auto-reclama aqui. Se deniega con
		--       un motivo especifico para que la UI ofrezca el boton de
		--       reclamo explicito (ver GlobalStorageSiK.Permissions.
		--       canClaimVacantOwnership/claimVacantOwnership) solo a quien
		--       corresponda segun la cascada admin vivo -> miembro vivo ->
		--       herencia por cuenta.
		if displayText(net.ownerAccountLogin) == "" then
			local initialized = GlobalStorageSiK.Permissions.initializeOwner(net, player)
			if initialized then
				GlobalStorageSiK.Permissions.requestTransmit()
			end
			return initialized, initialized and nil or "identity_unavailable"
		end
		return false, "network_vacant"
	end
	if bindOwnerIdentity(net, player) then
		return true
	end
	-- ownRecord aqui, si existe, solo puede estar ROLE_DEAD (el caso vivo ya
	-- devolvio true arriba) - conserva intacta la revivificacion "mismo
	-- characterId vuelve muerto" de mas abajo, sin repetir la busqueda.
	local characterRecord = ownRecord or migrateLegacyCharacterRecord(net, player)
	if characterRecord then
		if characterRecord.role == GlobalStorageSiK.Permissions.ROLE_DEAD then
			-- Evidencia dura de que sigue vivo: esta rama solo mira el propio
			-- characterId de QUIEN esta pidiendo acceso ahora mismo, nunca el de
			-- otro jugador. Como el UUID es por-vida-y-nunca-se-reutiliza esto no
			-- deberia poder pasar en juego normal, pero si pasara (bug, migracion
			-- rara) no debe quedar atascado en "dead" para siempre - se revive
			-- con su rol previo, igual de explicito y no especulativo que el
			-- resto de esta funcion.
			characterRecord.role = characterRecord.priorRole or GlobalStorageSiK.Permissions.ROLE_MEMBER
			characterRecord.priorRole = nil
			characterRecord.diedAt = nil
		end
		bindCharacter(net, player, characterRecord.role)
		return true
	end
	local usernameKey = normalizeName(username)
	local characterKey = normalizeName(characterName)
	local characterAmbiguous = isCharacterNameAmbiguous(characterName)
	for i = 1, #(net.allowedUsers or {}) do
		local storedKey = normalizeName(net.allowedUsers[i])
		if (usernameKey ~= "" and storedKey == usernameKey)
			or (not characterAmbiguous and storedKey == characterKey) then
			local legacyValue = net.allowedUsers[i]
			local role = GlobalStorageSiK.Permissions.ROLE_MEMBER
			for j = 1, #(net.adminUsers or {}) do
				if normalizeName(net.adminUsers[j]) == normalizeName(legacyValue) then
					role = GlobalStorageSiK.Permissions.ROLE_ADMIN
					net.adminUsers[j] = characterName
					break
				end
			end
			net.allowedUsers[i] = characterName
			local bound = bindCharacter(net, player, role)
			consumeLegacyMembership(net, bound.name, bound.username)
			return true
		end
	end
	local playerFaction = GlobalStorageSiK.Permissions.getPlayerFaction(player)
	if playerFaction and playerFaction.getName then
		-- BUG REAL encontrado (2026-08-16, mientras se investigaba por que
		-- el permiso de "toda la facción" no daba acceso real): addFaction
		-- guarda el nombre normalizado a minusculas (ver normalizeName), pero
		-- aqui se comparaba contra playerFaction:getName() SIN normalizar -
		-- "sik-gs" nunca coincidia con "SiK-GS". Este mecanismo ya no lo usa
		-- la UI (sustituido por addAllFactionMembers, que expande a acceso
		-- individual confirmado funcional), pero se deja corregido por si
		-- algo mas lo sigue leyendo.
		local fname = normalizeName(playerFaction:getName())
		for i = 1, #(net.allowedFactions or {}) do
			if net.allowedFactions[i] == fname then
				return true
			end
		end
	end
	if net.factionOnly then
		local ownerUser = net.ownerAccountLogin
		if not ownerUser or ownerUser == "" then
			ownerUser = GlobalStorageSiK.Permissions.resolveUsernameFromCharacter(net.owner or "")
		end
		if ownerUser and ownerUser ~= "" and GlobalStorageSiK.Permissions.sameFaction(username, ownerUser) then
			return true
		end
	end
	-- Traza dirigida (2026-08-22): un "denied" generico sin esto obligaba a
	-- reconstruir a ciegas por que fallo cada rama anterior (visto en pruebas
	-- reales del flujo de herencia). Vuelca el estado relevante de la red y
	-- del jugador en el momento exacto del rechazo final.
	if GlobalStorageSiK.Log and shouldLogDenied(characterId, networkId) then
		GlobalStorageSiK.Log.debug("Permissions", "canAccessDenied",
			"networkId=" .. tostring(networkId)
				.. " owner=" .. tostring(net.owner) .. " ownerCharacterId=" .. tostring(net.ownerCharacterId)
				.. " ownerAccountLogin=" .. tostring(net.ownerAccountLogin)
				.. " characterId=" .. tostring(characterId) .. " characterName=" .. tostring(characterName)
				.. " username=" .. tostring(username))
	end
	return false, rotationUnprovenReason or "denied"
end

local function collectOnlineCharacterRecords(requestingPlayer)
	local result = {}
	local seen = {}
	local players = nil
	if getOnlinePlayers then
		local ok, value = pcall(getOnlinePlayers)
		if ok then players = value end
	end
	if not players and getActivePlayers then
		local ok, value = pcall(getActivePlayers)
		if ok then players = value end
	end
	if players and players.size then
		for i = 0, players:size() - 1 do
			local player = players:get(i)
			local id = GlobalStorageSiK.Permissions.getCharacterId(player)
			if id ~= "" and not seen[id] then
				seen[id] = true
				result[#result + 1] = {
					id = id,
					characterId = id,
					name = GlobalStorageSiK.Permissions.getCharacterName(player),
					characterName = GlobalStorageSiK.Permissions.getCharacterName(player),
					displayName = GlobalStorageSiK.Permissions.getPlayerDisplayName(player),
					username = player.getUsername and player:getUsername() or "",
					source = "online",
					online = true,
					sameFaction = requestingPlayer and requestingPlayer.getUsername and player.getUsername
						and GlobalStorageSiK.Permissions.sameFaction(
							requestingPlayer:getUsername(), player:getUsername()) or false,
				}
			end
		end
	end
	table.sort(result, function(a, b)
		local aName = normalizeName(a.characterName or a.name)
		local bName = normalizeName(b.characterName or b.name)
		if aName ~= bName then return aName < bName end
		return tostring(a.characterId or a.id or "") < tostring(b.characterId or b.id or "")
	end)
	return result
end

--- Combina la membresía persistente de Faction con los IDs de los personajes
--- que estén conectados. Un miembro offline conserva username e id vacío; al
--- conectarse, canAccess migra ese permiso nominal al ID persistente.
---@param requestingPlayer IsoPlayer|nil
---@param onlineCharacters table[]
---@return table[]
local function collectFactionCharacterRecords(requestingPlayer, onlineCharacters)
	local result = {}
	if not requestingPlayer then return result end
	local onlineByUsername = {}
	for i = 1, #(onlineCharacters or {}) do
		local entry = onlineCharacters[i]
		local key = entry and normalizeName(entry.username) or ""
		if key ~= "" then
			onlineByUsername[key] = entry
		end
	end
	local usernames = GlobalStorageSiK.Permissions.getFactionUsernames(requestingPlayer)
	for i = 1, #usernames do
		local username = usernames[i]
		local online = onlineByUsername[normalizeName(username)]
		result[#result + 1] = {
			id = online and online.id or "",
			characterId = online and (online.characterId or online.id) or "",
			name = online and online.name or username,
			characterName = online and (online.characterName or online.name) or username,
			displayName = online and online.displayName or username,
			username = username,
			factionUsername = username,
			source = "faction",
			online = online ~= nil,
		}
	end
	table.sort(result, function(a, b)
		local aName = normalizeName(a.characterName or a.name)
		local bName = normalizeName(b.characterName or b.name)
		if aName ~= bName then return aName < bName end
		return tostring(a.characterId or a.id or a.username or "")
			< tostring(b.characterId or b.id or b.username or "")
	end)
	return result
end

--- Construye el único roster seleccionable que consume la UI. Facción tiene
--- precedencia de procedencia, pero conserva el UUID y nombre exactos de la
--- entrada online. Solo un UUID repetido se deduplica; homónimos con UUID
--- distintos permanecen como candidatos independientes.
---@param memberEntries table[]|nil
---@param onlineCharacters table[]|nil
---@param factionMembers table[]|nil
---@return table[]
function GlobalStorageSiK.Permissions.buildPickerCandidates(memberEntries, onlineCharacters, factionMembers)
	local memberIds = {}
	local legacyKeys = {}
	for i = 1, #(memberEntries or {}) do
		local member = memberEntries[i]
		local id = tostring(member and (member.characterId or member.id) or "")
		if id ~= "" then
			memberIds[id] = true
		else
			local nameKey = normalizeName(member and (member.characterName or member.name))
			local usernameKey = normalizeName(member and member.username)
			if nameKey ~= "" then legacyKeys[nameKey] = true end
			if usernameKey ~= "" then legacyKeys[usernameKey] = true end
		end
	end

	local result = {}
	local seenIds = {}
	local seenOffline = {}
	local function addCandidate(entry, source)
		if not entry then return end
		local id = tostring(entry.characterId or entry.id or "")
		local username = displayText(entry.factionUsername or entry.username)
		local characterName = displayText(entry.characterName or entry.name)
		if characterName == "" then characterName = username end
		if id ~= "" then
			if memberIds[id] or seenIds[id] then return end
			-- BUG REAL (reportado 2026-08-18, capturado en screenshot: "Omar
			-- Icon" seguia en el desplegable "Añadir acceso" pese a ya ser
			-- miembro): un permiso legacy (concedido por NOMBRE, antes del
			-- cambio a UUID) solo puebla legacyKeys, nunca memberIds - y esta
			-- rama (candidato CON UUID real, el caso normal de un jugador
			-- online) solo miraba memberIds, sin cruzar nunca contra
			-- legacyKeys. Resultado: cualquier miembro legado seguia
			-- ofreciendose para "añadir" en cuanto aparecia online con su
			-- UUID real, aunque ya tuviera acceso via el nombre. Se cruza
			-- tambien por nombre/usuario normalizado, igual que ya hacia la
			-- rama "sin UUID" de abajo para candidatos offline.
			local nameKey = normalizeName(characterName)
			local usernameKey = normalizeName(username)
			if (nameKey ~= "" and legacyKeys[nameKey]) or (usernameKey ~= "" and legacyKeys[usernameKey]) then
				return
			end
			seenIds[id] = true
		else
			local offlineKey = normalizeName(username)
			if offlineKey == "" then offlineKey = normalizeName(characterName) end
			if offlineKey == "" or legacyKeys[offlineKey] or seenOffline[offlineKey] then return end
			seenOffline[offlineKey] = true
		end
		result[#result + 1] = {
			id = id,
			characterId = id,
			name = characterName,
			characterName = characterName,
			displayName = displayText(entry.displayName) ~= ""
				and displayText(entry.displayName) or characterName,
			username = username,
			factionUsername = source == "faction" and username or "",
			source = source,
			online = entry.online == true or source == "online",
		}
	end

	-- Facción primero: una coincidencia faction+online conserva su UUID online
	-- y no vuelve a aparecer en la sección Servidor.
	for i = 1, #(factionMembers or {}) do addCandidate(factionMembers[i], "faction") end
	for i = 1, #(onlineCharacters or {}) do addCandidate(onlineCharacters[i], "online") end

	table.sort(result, function(a, b)
		local aName = normalizeName(a.characterName or a.name)
		local bName = normalizeName(b.characterName or b.name)
		if aName ~= bName then return aName < bName end
		local aId = tostring(a.characterId or a.username or "")
		local bId = tostring(b.characterId or b.username or "")
		if aId ~= bId then return aId < bId end
		return tostring(a.source or "") < tostring(b.source or "")
	end)
	return result
end

--- Comprueba el contrato que recibe la UI sin intentar reparar históricos.
--- La limpieza/fusión de identidades permanece fuera de DEV1.
---@param ownerCharacterId string|nil
---@param memberEntries table[]|nil
---@param pickerCandidates table[]|nil
---@return boolean ok
---@return string reason
function GlobalStorageSiK.Permissions.validatePermissionProjection(
	ownerCharacterId, memberEntries, pickerCandidates)
	ownerCharacterId = tostring(ownerCharacterId or "")
	local memberIds = {}
	local ownerRows = 0
	for i = 1, #(memberEntries or {}) do
		local entry = memberEntries[i]
		local id = tostring(entry and (entry.characterId or entry.id) or "")
		if entry and entry.role == GlobalStorageSiK.Permissions.ROLE_OWNER then
			ownerRows = ownerRows + 1
			if ownerCharacterId ~= "" and id ~= ownerCharacterId then
				return false, "owner_id_mismatch"
			end
		elseif ownerCharacterId ~= "" and id == ownerCharacterId then
			return false, "owner_repeated_as_member"
		end
		if id ~= "" then
			if memberIds[id] then return false, "duplicate_member_uuid" end
			memberIds[id] = true
		end
	end
	if ownerCharacterId ~= "" and ownerRows ~= 1 then
		return false, "owner_row_count_" .. tostring(ownerRows)
	end
	if ownerCharacterId == "" and ownerRows > 1 then
		return false, "owner_row_count_" .. tostring(ownerRows)
	end
	local candidateIds = {}
	for i = 1, #(pickerCandidates or {}) do
		local entry = pickerCandidates[i]
		local id = tostring(entry and (entry.characterId or entry.id) or "")
		if id ~= "" then
			if memberIds[id] then return false, "candidate_is_member" end
			if candidateIds[id] then return false, "duplicate_candidate_uuid" end
			candidateIds[id] = true
		end
	end
	return true, "ok"
end

--- Resuelve en el proceso autoritativo un ID seleccionado por el cliente.
---@param characterId string
---@return IsoPlayer|nil
function GlobalStorageSiK.Permissions.findOnlineCharacter(characterId)
	characterId = tostring(characterId or "")
	if characterId == "" then return nil end
	local players = getOnlinePlayers and getOnlinePlayers() or (getActivePlayers and getActivePlayers())
	if players and players.size then
		for i = 0, players:size() - 1 do
			local player = players:get(i)
			if GlobalStorageSiK.Permissions.getCharacterId(player) == characterId then
				return player
			end
		end
	end
	return nil
end

--- Añade un personaje ya resuelto por el servidor. Las altas modernas viven
--- solo en characterPermissions[UUID]; allowedUsers/adminUsers quedan como
--- cola offline y compatibilidad legacy, nunca como segunda fuente moderna.
function GlobalStorageSiK.Permissions.addCharacter(networkId, player)
	if not player then return false, false, "invalid_or_stale_identity" end
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	local name = GlobalStorageSiK.Permissions.getCharacterName(player)
	if characterId == "" or name == "" then
		return false, false, "invalid_or_stale_identity"
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId)
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if net.ownerCharacterId == characterId or net.characterPermissions[characterId] then
		return true, false, "already_member"
	end
	local record = bindCharacter(net, player, GlobalStorageSiK.Permissions.ROLE_MEMBER)
	consumeLegacyMembership(net, record.name, record.username)
	return true, true, "added"
end

function GlobalStorageSiK.Permissions.setCharacterRole(networkId, characterId, role)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	local record = net and net.characterPermissions and net.characterPermissions[characterId]
	if not record or characterId == net.ownerCharacterId then return false end
	-- Un miembro fallecido no se "revive" con un simple cambio de rol desde
	-- el panel de staff (ese boton ya no se ofrece para fichas con
	-- role=ROLE_DEAD, ver GS_AdminDashboard.lua) - se rechaza tambien aqui,
	-- nunca confiar solo en que el cliente oculte el boton.
	if record.role == GlobalStorageSiK.Permissions.ROLE_DEAD then return false end
	if role ~= GlobalStorageSiK.Permissions.ROLE_ADMIN then
		role = GlobalStorageSiK.Permissions.ROLE_MEMBER
	end
	record.role = role
	return true
end

function GlobalStorageSiK.Permissions.removeCharacter(networkId, characterId)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	local record = net and net.characterPermissions and net.characterPermissions[characterId]
	if not record or characterId == net.ownerCharacterId then return false end
	net.characterPermissions[characterId] = nil
	if net.memberZoneDenials then net.memberZoneDenials[characterId] = nil end
	local sameNameStillUsed = false
	for _, other in pairs(net.characterPermissions) do
		if other and normalizeName(other.name) == normalizeName(record.name) then
			sameNameStillUsed = true
			break
		end
	end
	if not sameNameStillUsed then
		GlobalStorageSiK.Permissions.removeUser(networkId, record.name)
		for i = #(net.adminUsers or {}), 1, -1 do
			if normalizeName(net.adminUsers[i]) == normalizeName(record.name) then
				table.remove(net.adminUsers, i)
			end
		end
	end
	return true
end

-- ============================================================================
-- Panel de soporte GM/moderacion (2026-08-22): gestion TECNICA de miembros,
-- roles y propietario de CUALQUIER red - nunca acceso al almacen/inventario
-- de la red. Estas funciones son pura mutacion de datos; la comprobacion de
-- isServerStaff(player) vive UNA sola vez en el dispatcher de comandos
-- (GS_Server.lua), nunca aqui, para que quede clara la frontera "quien puede
-- llamar esto" vs "que hace esto". Todas registran auditoria SIEMPRE VISIBLE
-- (Log.warn, no gateada por Modo depuracion) via el propio dispatcher.
-- ============================================================================

--- Resumen de TODAS las redes del registro, para el selector del panel.
---@return table[] { networkId, label, owner, ownerAccountLogin, memberCount, activeMemberCount, terminalCount, vacant }
function GlobalStorageSiK.Permissions.adminListNetworks()
	-- Cruce entre las dos ModData (operativa para nombre/terminales, propia
	-- de permisos para identidad/miembros - separacion de responsabilidades,
	-- 2026-08-22). BUG REAL cerrado aqui: este bucle leia net.characterPermissions/
	-- net.owner directamente del registro OPERATIVO, no lo capturo el
	-- reemplazo automatico del resto del fichero porque usa "for ... in
	-- pairs(registry.networks)" en vez de una unica asignacion "local net =".
	local registry = GlobalStorageSiK.Network.getRegistry()
	local out = {}
	for networkId, net in pairs(registry.networks or {}) do
		local permNet = GlobalStorageSiK.Permissions.getPermNet(networkId)
		-- BUG REAL COSMETICO cerrado (2026-08-26, hallazgo de Desarrollo -
		-- "la interfaz seguira mostrando N miembros contando tambien a los
		-- fallecidos"): memberCount (ahora recordsTotal, se mantiene el nombre
		-- de campo original memberCount por compatibilidad con cualquier
		-- consumidor existente) cuenta TODAS las fichas, incluidas ROLE_DEAD
		-- conservadas a proposito - activeMemberCount excluye esas para poder
		-- mostrar ambos numeros por separado en la UI.
		local memberCount, activeMemberCount = 0, 0
		for _, record in pairs((permNet and permNet.characterPermissions) or {}) do
			memberCount = memberCount + 1
			if not record or record.role ~= GlobalStorageSiK.Permissions.ROLE_DEAD then
				activeMemberCount = activeMemberCount + 1
			end
		end
		local terminalCount = 0
		if GlobalStorageSiK.TerminalRecord and GlobalStorageSiK.TerminalRecord.countActive then
			terminalCount = GlobalStorageSiK.TerminalRecord.countActive(net) or 0
		end
		local owner = (permNet and permNet.owner) or ""
		local ownerAccountLogin = (permNet and permNet.ownerAccountLogin) or ""
		local vacant = owner == ""
		-- Formato pedido explicito (2026-08-22): "nombre (cuenta del
		-- propietario)(id interno)" - la cuenta identifica sin ambiguedad a que
		-- jugador pertenece cada red en el desplegable, sin depender del
		-- nombre de personaje (puede repetirse/traducirse mal, ver
		-- IGUI_GS_AdminMarkDeceased).
		local baseName = (net.name and net.name ~= "") and net.name or networkId
		local accountTag = (ownerAccountLogin ~= "" and ownerAccountLogin) or GlobalStorageSiK.I18n.text("IGUI_GS_AdminNetworkVacantTag")
		out[#out + 1] = {
			networkId = networkId,
			label = baseName .. " (" .. accountTag .. ") (" .. string.sub(networkId, -8) .. ")",
			owner = owner,
			ownerAccountLogin = ownerAccountLogin,
			memberCount = memberCount,
			activeMemberCount = activeMemberCount,
			terminalCount = terminalCount,
			vacant = vacant,
		}
	end
	table.sort(out, function(a, b) return a.networkId < b.networkId end)
	return out
end

--- Lista de miembros de UNA red para el panel de soporte - mismo shape que
--- memberEntries de serialize(), reutilizado directamente mas abajo.
---@param networkId string
---@return table[]
function GlobalStorageSiK.Permissions.adminGetNetworkMembers(networkId)
	local serialized = GlobalStorageSiK.Permissions.serialize(networkId, nil)
	return serialized and serialized.memberEntries or {}
end

--- Jugadores CONECTADOS ahora mismo, para el desplegable "Añadir miembro"
--- del panel de soporte de staff - pedido explicito (2026-08-22): igual que
--- el desplegable de la pestaña normal de admin, pero SIN tener en cuenta
--- facción (el staff gestiona cualquier red, no solo la suya) - solo gente
--- conectada. Reutiliza collectOnlineCharacterRecords tal cual, ya usado
--- para el mismo fin en serialize().
---@return table[] { characterId, name, username }
function GlobalStorageSiK.Permissions.adminListOnlinePlayers()
	local online = collectOnlineCharacterRecords(nil)
	local out = {}
	for i = 1, #online do
		local entry = online[i]
		out[#out + 1] = {
			characterId = entry.characterId,
			name = entry.characterName or entry.name or "",
			username = entry.username or "",
		}
	end
	return out
end

--- Añade un jugador CONECTADO a una red como miembro, desde el panel de
--- soporte de staff. Nunca actua sobre facciones (a proposito, ver
--- adminListOnlinePlayers) ni sobre jugadores offline - el staff gestiona
--- identidades resueltas ahora mismo, no nombres nominales sin verificar.
---@param networkId string
---@param characterId string
---@return boolean ok
---@return string reason
function GlobalStorageSiK.Permissions.adminAddMember(networkId, characterId)
	local target = GlobalStorageSiK.Permissions.findOnlineCharacter(characterId or "")
	if not target then
		return false, "not_online"
	end
	local ok, changed, reason = GlobalStorageSiK.Permissions.addCharacter(networkId, target)
	if not ok then
		return false, reason or "failed"
	end
	return true, changed and "added" or "already_member"
end

--- Cambia el rol admin/member de un personaje YA existente en la red.
--- No actua sobre el propietario - usar adminSetOwner/adminReleaseOwnership.
---@param networkId string
---@param characterId string
---@param role string
---@return boolean
function GlobalStorageSiK.Permissions.adminSetMemberRole(networkId, characterId, role)
	return GlobalStorageSiK.Permissions.setCharacterRole(networkId, characterId, role)
end

--- Quita a un miembro/admin de la red. No actua sobre el propietario.
---@param networkId string
---@param characterId string
---@return boolean
function GlobalStorageSiK.Permissions.adminRemoveMember(networkId, characterId)
	return GlobalStorageSiK.Permissions.removeCharacter(networkId, characterId)
end

--- Fuerza al propietario de la red a ser un personaje YA presente en
--- characterPermissions (con o sin conexion). Uso: reasignar una red con
--- propietario fantasma/roto sin depender de que alguien la reclame por el
--- flujo normal de herencia.
---@param networkId string
---@param characterId string
---@return boolean ok
---@return string|nil reason
function GlobalStorageSiK.Permissions.adminSetOwner(networkId, characterId)
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then return false, "network_not_found" end
	local record = net.characterPermissions and net.characterPermissions[characterId]
	if not record then return false, "character_not_member" end
	record.diedAt = nil
	record.priorRole = nil
	applyOwnerRoleToRecord(net, characterId, record)
	return true, nil
end

--- Libera la propiedad de la red SIN asignar un nuevo dueño - mismo estado
--- final que handleOwnerDeath para el caso normal (owner/ownerCharacterId
--- vacios, ownerAccountLogin conservado), asi el flujo de reclamacion normal
--- sigue funcionando para quien corresponda despues.
---@param networkId string
---@return boolean
-- BUG REAL cerrado (2026-08-26, revision tecnica de Desarrollo tras probar
-- en TEST): esta funcion solo vaciaba la CACHE (net.owner/ownerCharacterId),
-- nunca tocaba la ficha del propietario en net.characterPermissions - se
-- quedaba con role="owner" internamente, contradiciendo la propia regla
-- documentada en bindCharacter ("esta ficha es la UNICA fuente de verdad").
-- Efecto real observado: al reclamar despues, bindCharacter degradaba esa
-- ficha huerfana a ROLE_MEMBER como efecto secundario silencioso de su
-- invariante "un solo owner vivo" - la vida antigua quedaba viva-como-
-- miembro, con acceso a la red, en vez de fallecida como corresponde a esta
-- herramienta de recuperacion. Ahora se marca ROLE_DEAD de forma explicita y
-- atomica AQUI MISMO, antes de vaciar la cache - nunca existe un estado
-- intermedio "cache vacante + ficha todavia diciendo owner". Desarrollo
-- propuso separar esto en 3 operaciones distintas (liberar conservando
-- acceso / confirmar muerte y liberar / transferir) - "Liberar propiedad"
-- es la herramienta de soporte para una red atascada sin muerte confirmada,
-- asi que "confirmar muerte y liberar" es el comportamiento correcto para
-- ESTA accion; las otras 2 variantes quedan para una ronda futura si hace
-- falta.
---@param networkId string
---@return boolean
function GlobalStorageSiK.Permissions.adminReleaseOwnership(networkId)
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then return false end
	local oldOwnerId = net.ownerCharacterId
	local oldOwnerRecord = oldOwnerId and net.characterPermissions and net.characterPermissions[oldOwnerId]
	if oldOwnerRecord then
		markRecordDead(oldOwnerRecord)
	end
	net.owner = ""
	net.ownerCharacterId = nil
	return true
end

--- Borra la red del registro por completo (permisos, miembros, zonas propias)
--- - NUNCA toca objetos fisicos del mundo. Cualquier GS_TerminalUnit que
--- apuntara a este networkId queda "desvinculado" (mismo estado ya soportado
--- hoy, motivo "terminal_unlinked": el jugador ve el panel de bloqueo con la
--- tarjeta de "instalar aqui" para re-vincularlo a una red nueva o existente,
--- sin perder el mueble). No es una accion reversible.
---@param networkId string
---@return boolean
function GlobalStorageSiK.Permissions.adminDeleteNetwork(networkId)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local existsOperational = registry.networks and registry.networks[networkId] ~= nil
	local existsPerms = getPermissionsStore()[networkId] ~= nil
	if not existsOperational and not existsPerms then return false end
	if existsOperational then registry.networks[networkId] = nil end
	GlobalStorageSiK.Permissions.deletePermNet(networkId)
	for zoneId, zone in pairs(registry.zones or {}) do
		if zone and zone.networkId == networkId then
			registry.zones[zoneId] = nil
			for nodeId, node in pairs(registry.nodes or {}) do
				if node and node.zoneId == zoneId then
					registry.nodes[nodeId] = nil
				end
			end
		end
	end
	return true
end

--- Serializa permisos para el cliente.
---@param networkId string
---@return table
function GlobalStorageSiK.Permissions.serialize(networkId, requestingPlayer)
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId)
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	GlobalStorageSiK.Permissions.cleanupZoneDenials(networkId)
	local function deniedZoneIds(characterId, name)
		local key = zoneMemberKey(characterId, name)
		local denied = key ~= "" and net.memberZoneDenials[key] or nil
		local result = {}
		for zoneId, value in pairs(denied or {}) do
			if value == true then result[#result + 1] = zoneId end
		end
		table.sort(result)
		return result
	end
	-- Resolver jugador: parámetro explícito (server) o jugador local (client/SP)
	local resolvedPlayer = requestingPlayer
	if not resolvedPlayer and isClient and isClient() and GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer then
		resolvedPlayer = GlobalStorageSiK.NetClient.getPlayer()
	end
	local playerFaction = nil
	local playerFactionName = ""
	if resolvedPlayer then
		playerFaction = GlobalStorageSiK.Permissions.getPlayerFaction(resolvedPlayer)
		if playerFaction and playerFaction.getName then
			playerFactionName = playerFaction:getName() or ""
		end
	end
	local playerRole = GlobalStorageSiK.Permissions.ROLE_MEMBER
	if resolvedPlayer then
		playerRole = GlobalStorageSiK.Permissions.getPlayerRole(resolvedPlayer, networkId)
	end
	-- Calculado antes de construir memberEntries (en vez de mas abajo, donde
	-- ya se usaba solo para el combo de "Añadir acceso") para poder anotar
	-- online=true/false por miembro - pedido explicito 2026-08-22: "Conectado"
	-- en verde en vez de "hace 28s" para quien sigue en linea ahora mismo.
	local onlineCharacters = collectOnlineCharacterRecords(resolvedPlayer)
	local onlineIds = {}
	for i = 1, #onlineCharacters do
		local oc = onlineCharacters[i]
		if oc.characterId and oc.characterId ~= "" then onlineIds[oc.characterId] = true end
	end
	local memberEntries = {}
	local seenNames = {}
	local seenMemberIds = {}
	if net.owner and net.owner ~= "" then
		local ownerRecord = net.characterPermissions
			and net.ownerCharacterId and net.characterPermissions[net.ownerCharacterId] or nil
		memberEntries[#memberEntries + 1] = {
			id = net.ownerCharacterId or "",
			characterId = net.ownerCharacterId or "",
			name = net.owner,
			characterName = net.owner,
			displayName = ownerRecord and ownerRecord.displayName or net.owner,
			username = ownerRecord and ownerRecord.username or net.ownerAccountLogin or "",
			role = GlobalStorageSiK.Permissions.ROLE_OWNER,
			source = "member",
			deniedZoneIds = {},
			diedAt = ownerRecord and ownerRecord.diedAt or nil,
			lastSeenAt = ownerRecord and ownerRecord.lastSeenAt or nil,
			online = net.ownerCharacterId ~= nil and onlineIds[net.ownerCharacterId] or false,
		}
		if net.ownerCharacterId and net.ownerCharacterId ~= "" then
			seenMemberIds[net.ownerCharacterId] = true
		end
		seenNames[normalizeName(net.owner)] = true
	end
	for id, record in pairs(net.characterPermissions or {}) do
		if id ~= net.ownerCharacterId and not seenMemberIds[id]
			and record and record.name and record.name ~= "" then
			seenMemberIds[id] = true
			memberEntries[#memberEntries + 1] = {
				id = id,
				characterId = id,
				name = record.name,
				characterName = record.name,
				displayName = record.displayName or record.name,
				username = record.username or "",
				role = record.role or GlobalStorageSiK.Permissions.ROLE_MEMBER,
				source = "member",
				deniedZoneIds = deniedZoneIds(id, record.name),
				diedAt = record.diedAt,
				lastSeenAt = record.lastSeenAt,
				online = onlineIds[id] or false,
			}
			seenNames[normalizeName(record.name)] = true
		end
	end
	for i = 1, #(net.allowedUsers or {}) do
		local name = net.allowedUsers[i]
		if name and name ~= "" and not seenNames[normalizeName(name)] then
			local role = GlobalStorageSiK.Permissions.ROLE_MEMBER
			for j = 1, #(net.adminUsers or {}) do
				if normalizeName(net.adminUsers[j]) == normalizeName(name) then
					role = GlobalStorageSiK.Permissions.ROLE_ADMIN
					break
				end
			end
			local legacyUsername = ""
			if resolvedPlayer and GlobalStorageSiK.Permissions.isFactionUsername(resolvedPlayer, name) then
				legacyUsername = name
			end
			memberEntries[#memberEntries + 1] = {
				id = "", characterId = "", name = name, characterName = name,
				displayName = name, username = legacyUsername,
				role = role, legacy = true,
				source = "legacy",
				deniedZoneIds = deniedZoneIds(nil, name),
			}
		end
	end
	table.sort(memberEntries, function(a, b)
		local aOwner = a.role == GlobalStorageSiK.Permissions.ROLE_OWNER
		local bOwner = b.role == GlobalStorageSiK.Permissions.ROLE_OWNER
		if aOwner ~= bOwner then return aOwner end
		local aName = normalizeName(a.characterName or a.name)
		local bName = normalizeName(b.characterName or b.name)
		if aName ~= bName then return aName < bName end
		return tostring(a.characterId or a.id or a.username or "")
			< tostring(b.characterId or b.id or b.username or "")
	end)
	-- onlineCharacters ya se calculo arriba (antes de construir memberEntries).
	local factionMembers = collectFactionCharacterRecords(resolvedPlayer, onlineCharacters)
	local pickerCandidates = GlobalStorageSiK.Permissions.buildPickerCandidates(
		memberEntries, onlineCharacters, factionMembers)
	local projectionOk, projectionReason = GlobalStorageSiK.Permissions.validatePermissionProjection(
		net.ownerCharacterId, memberEntries, pickerCandidates)

	-- Diagnóstico acotado: solo imprime cuando cambia el roster lógico. Una
	-- cuenta/nombre compartidos por UUID distintos son una posible rotación,
	-- nunca una deduplicación ni una migración automática.
	local rosterParts = {}
	local identityGroups = {}
	for i = 1, #memberEntries do
		local entry = memberEntries[i]
		local id = tostring(entry.characterId or entry.id or "")
		rosterParts[#rosterParts + 1] = "m:" .. id .. ":" .. tostring(entry.role or "")
			.. ":" .. tostring(entry.username or "")
			.. ":" .. tostring(entry.characterName or entry.name or "")
		-- BUG REAL cerrado (2026-08-26, revision tecnica de Desarrollo tras
		-- probar en TEST): una red con historial real (vidas anteriores ya
		-- marcadas ROLE_DEAD, esperado y normal con el tiempo) contaba esas
		-- fichas fallecidas en el mismo grupo que la vida VIVA actual, asi
		-- que cualquier cuenta con unas pocas muertes en su historial
		-- disparaba possibleIdentityRotation en CADA sincronizacion aunque
		-- solo hubiera una vida realmente activa - ruido constante, sin
		-- valor diagnostico. Una ficha muerta es historial esperado, nunca
		-- evidencia de rotacion - se excluye de la deteccion.
		if id ~= "" and entry.role ~= GlobalStorageSiK.Permissions.ROLE_DEAD then
			local groupKey = normalizeName(entry.username) .. "\31"
				.. normalizeName(entry.characterName or entry.name)
			if groupKey ~= "\31" then
				local group = identityGroups[groupKey]
				if not group then group = {}; identityGroups[groupKey] = group end
				group[#group + 1] = id
			end
		end
	end
	for i = 1, #pickerCandidates do
		local entry = pickerCandidates[i]
		rosterParts[#rosterParts + 1] = "p:" .. tostring(entry.characterId or "")
			.. ":" .. tostring(entry.source or "")
			.. ":" .. tostring(entry.username or "")
			.. ":" .. tostring(entry.characterName or entry.name or "")
			.. ":" .. tostring(entry.online == true)
		local id = tostring(entry.characterId or "")
		if id ~= "" then
			local groupKey = normalizeName(entry.username) .. "\31"
				.. normalizeName(entry.characterName or entry.name)
			if groupKey ~= "\31" then
				local group = identityGroups[groupKey]
				if not group then group = {}; identityGroups[groupKey] = group end
				local alreadySeen = false
				for j = 1, #group do
					if group[j] == id then alreadySeen = true; break end
				end
				if not alreadySeen then group[#group + 1] = id end
			end
		end
	end
	local rosterSignature = table.concat(rosterParts, "|")
	if permissionRosterLogSignatures[networkId] ~= rosterSignature then
		permissionRosterLogSignatures[networkId] = rosterSignature
		-- BUG REAL cerrado (2026-08-26, hallazgo de Desarrollo sobre dev13 -
		-- "contadores enganosos"): "members=" contaba TODO memberEntries,
		-- incluidas las fichas ROLE_DEAD de vidas anteriores conservadas a
		-- proposito (una red con historial real de muertes daba "10 miembros"
		-- cuando solo 1-2 seguian realmente activos). Desglosado en campos
		-- separados sin ambiguedad - "members=" se conserva tal cual para no
		-- romper ningun parser externo que ya lo lea, pero ahora
		-- recordsTotal/activeMembers/deadRecords/ownerCount dejan claro que
		-- parte de ese numero es historial, no gente con acceso real hoy.
		local deadRecords, ownerCount = 0, 0
		for i = 1, #memberEntries do
			local role = memberEntries[i].role
			if role == GlobalStorageSiK.Permissions.ROLE_DEAD then
				deadRecords = deadRecords + 1
			elseif role == GlobalStorageSiK.Permissions.ROLE_OWNER then
				ownerCount = ownerCount + 1
			end
		end
		GlobalStorageSiK.Log.info("Permissions", "permissionRoster",
			"network=" .. tostring(networkId)
				.. " members=" .. tostring(#memberEntries)
				.. " recordsTotal=" .. tostring(#memberEntries)
				.. " activeMembers=" .. tostring(#memberEntries - deadRecords)
				.. " deadRecords=" .. tostring(deadRecords)
				.. " ownerCount=" .. tostring(ownerCount)
				.. " online=" .. tostring(#onlineCharacters)
				.. " faction=" .. tostring(#factionMembers)
				.. " candidates=" .. tostring(#pickerCandidates)
				.. " invariantsOk=" .. tostring(projectionOk)
				.. " invariantReason=" .. tostring(projectionReason))
		for groupKey, ids in pairs(identityGroups) do
			if #ids > 1 then
				table.sort(ids)
				GlobalStorageSiK.Log.info("Identity", "possibleIdentityRotation",
					"network=" .. tostring(networkId)
						.. " identityKey=" .. permissionLogText(string.gsub(groupKey, "\31", "/"), 160)
						.. " characterIds=" .. table.concat(ids, ","))
			end
		end
	end
	return {
		owner = net.owner or "",
		ownerCharacterId = net.ownerCharacterId or "",
		allowedUsers = net.allowedUsers or {},
		allowedFactions = net.allowedFactions or {},
		adminUsers = net.adminUsers or {},
		factionOnly = net.factionOnly == true,
		enforce = GlobalStorageSiK.Permissions.shouldEnforce(),
		playerFactionName = playerFactionName,
		playerRole = playerRole,
		canAutoSort = resolvedPlayer ~= nil
			and GlobalStorageSiK.Permissions.isAdminPlayer(resolvedPlayer, networkId) or false,
		-- Boton "Reclamar propiedad" en la propia pestaña de admin (2026-08-23,
		-- ver GlobalStorageSiK.Permissions.canAdminClaimOwnership): calculado
		-- SIEMPRE en servidor, igual que canAutoSort de arriba - el cliente
		-- solo pinta el boton segun lo que se le diga.
		canClaimAsAdmin = resolvedPlayer ~= nil
			and GlobalStorageSiK.Permissions.canAdminClaimOwnership(resolvedPlayer, networkId) or false,
		memberEntries = memberEntries,
		onlineCharacters = onlineCharacters,
		factionMembers = factionMembers,
		pickerCandidates = pickerCandidates,
	}
end

local function removeIdentityFromList(values, name, username)
	local nameKey = normalizeName(name)
	local usernameKey = normalizeName(username)
	for i = #(values or {}), 1, -1 do
		local stored = normalizeName(values[i])
		if (nameKey ~= "" and stored == nameKey)
			or (usernameKey ~= "" and stored == usernameKey) then
			table.remove(values, i)
		end
	end
end

local function findTransferMember(net, targetName, targetUsername, targetCharacterId)
	targetName = displayText(targetName)
	targetUsername = displayText(targetUsername)
	targetCharacterId = tostring(targetCharacterId or "")
	if targetCharacterId ~= "" then
		local record = net.characterPermissions and net.characterPermissions[targetCharacterId]
		if not record then return nil end
		local recordUsername = displayText(record.username)
		if targetUsername ~= "" and recordUsername ~= ""
			and normalizeName(targetUsername) ~= normalizeName(recordUsername) then
			return nil
		end
		return {
			id = targetCharacterId,
			name = displayText(record.name),
			displayName = displayText(record.displayName),
			username = recordUsername,
			record = record,
		}
	end
	-- Un miembro desconectado no tiene IsoPlayer ni ID resoluble. Solo se puede
	-- transferir usando la cuenta exacta que ya figura en los permisos de la red;
	-- un nombre visible aislado no es una identidad suficiente.
	if targetUsername == "" then return nil end
	if not listContainsIdentity(net.allowedUsers, targetName, targetUsername)
		and not listContainsIdentity(net.adminUsers, targetName, targetUsername) then
		return nil
	end
	return {
		id = "",
		name = targetName ~= "" and targetName or targetUsername,
		displayName = targetName ~= "" and targetName or targetUsername,
		username = targetUsername,
		record = nil,
	}
end

local function applyOwnerTransfer(networkId, net, player, target, keepFormerOwner)
	local oldId = GlobalStorageSiK.Permissions.getCharacterId(player)
	local formerName = GlobalStorageSiK.Permissions.getCharacterName(player)
	local formerRecord = oldId ~= "" and net.characterPermissions[oldId] or nil
	local targetId = tostring(target.id or "")
	local targetName = displayText(target.name)
	local targetUsername = displayText(target.username)
	if targetName == "" or targetUsername == "" then return false end

	if keepFormerOwner then
		if formerRecord then
			formerRecord.role = GlobalStorageSiK.Permissions.ROLE_MEMBER
		end
		GlobalStorageSiK.Permissions.addUser(networkId, formerName)
	else
		if oldId ~= "" and oldId ~= targetId then
			net.characterPermissions[oldId] = nil
			if net.memberZoneDenials then net.memberZoneDenials[oldId] = nil end
		end
		removeIdentityFromList(net.allowedUsers, formerName, getPlayerUsername(player))
		removeIdentityFromList(net.adminUsers, formerName, getPlayerUsername(player))
	end

	removeIdentityFromList(net.allowedUsers, targetName, targetUsername)
	removeIdentityFromList(net.adminUsers, targetName, targetUsername)
	if net.memberZoneDenials then
		net.memberZoneDenials[zoneMemberKey(targetId, targetName)] = nil
		net.memberZoneDenials[zoneMemberKey(nil, targetUsername)] = nil
	end
	if target.record then
		target.record.characterName = targetName
		target.record.accountUsername = targetUsername
		target.record.name = targetName
		target.record.displayName = targetName
		target.record.username = targetUsername
		net.characterPermissions[targetId] = target.record
		applyOwnerRoleToRecord(net, targetId, target.record)
	else
		-- Legacy sin ficha moderna (personaje nunca visto, solo nombre/cuenta) -
		-- se vinculara a una ficha real la proxima vez que conecte (ver
		-- bindOwnerIdentity). Sin ficha que usar, se asignan los 4 campos de
		-- red directamente - unico sitio fuera de bindCharacter/
		-- applyOwnerRoleToRecord donde esto sigue pasando, por falta de datos.
		net.owner = targetName
		net.ownerAccountLogin = targetUsername
		net.ownerSteamId = getSteamIdForUsername(targetUsername, nil)
		net.ownerCharacterId = targetId
	end
	return true
end

--- Transfiere la propiedad a un miembro ya autorizado, incluso si está
--- desconectado. La cuenta enviada por el cliente se contrasta siempre con el
--- registro/permiso persistente que ya existe en el servidor.
---@param networkId string
---@param player IsoPlayer
---@param toCharacterName string
---@param keepFormerOwner boolean|nil
---@param targetUsername string|nil
---@param targetCharacterId string|nil
---@return boolean ok
---@return string message
function GlobalStorageSiK.Permissions.transferOwner(networkId, player, toCharacterName, keepFormerOwner,
	targetUsername, targetCharacterId)
	local targetName = displayText(toCharacterName)
	if normalizeName(targetName) == "" then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId)
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_NetworkNotFoundMsg")
	end
	if not GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermOnlyOwnerTransferMsg")
	end
	local target = findTransferMember(net, targetName, targetUsername, targetCharacterId)
	if not target then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
	end
	local ownerId = GlobalStorageSiK.Permissions.getCharacterId(player)
	if (target.id ~= "" and target.id == ownerId)
		or normalizeName(target.username) == normalizeName(getPlayerUsername(player)) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermAlreadyOwnerMsg")
	end
	if not applyOwnerTransfer(networkId, net, player, target, keepFormerOwner) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
	end
	return true, GlobalStorageSiK.I18n.remote("IGUI_GS_PermOwnershipTransferredMsg", target.name)
end

function GlobalStorageSiK.Permissions.transferOwnerToCharacter(networkId, player, targetPlayer, keepFormerOwner)
	if not targetPlayer then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
	end
	local targetName = GlobalStorageSiK.Permissions.getCharacterName(targetPlayer)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net or not GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermOnlyOwnerTransferMsg")
	end
	local targetId = GlobalStorageSiK.Permissions.getCharacterId(targetPlayer)
	local targetUsername = getPlayerUsername(targetPlayer)
	if targetId == "" or targetUsername == "" then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
	end
	if targetId == GlobalStorageSiK.Permissions.getCharacterId(player)
		or normalizeName(targetUsername) == normalizeName(getPlayerUsername(player)) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermAlreadyOwnerMsg")
	end
	local target = {
		id = targetId,
		name = targetName,
		displayName = GlobalStorageSiK.Permissions.getPlayerDisplayName(targetPlayer),
		username = targetUsername,
		record = net.characterPermissions[targetId] or {},
	}
	if not applyOwnerTransfer(networkId, net, player, target, keepFormerOwner) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
	end
	net.ownerSteamId = getSteamIdForUsername(targetUsername, targetPlayer)
	return true, GlobalStorageSiK.I18n.remote("IGUI_GS_PermOwnershipTransferredMsg", targetName)
end

--- Indica si el jugador es propietario de la red.
--- BUG REAL DE SEGURIDAD cerrado (2026-08-22, confirmado en pruebas reales:
--- "tenemos acceso directamente... nos permite trabajar como propietario
--- como si nada", nada mas conectar con un personaje nuevo, sin pasar por
--- ningun terminal ni pulsar "Reclamar propiedad"): esta funcion llamaba a
--- bindOwnerIdentity()/initializeOwner() - funciones que ESCRIBEN (migran
--- fichas legacy, inicializan redes) - desde lo que deberia ser una simple
--- CONSULTA de solo lectura. Cualquier sitio que llamara a isOwnerPlayer
--- (listar botones de la UI, comprobar permisos de admin, etc.) podia acabar
--- asignando la propiedad como efecto secundario de preguntar, saltandose
--- por completo la cascada de reclamo explicito (canClaimVacantOwnership/
--- claimVacantOwnership) para una red vacante por muerte/reconciliacion.
--- Decision final (pedido explicito): isOwnerPlayer() es cierto SI Y SOLO SI
--- el jugador es owner en la fuente unica de verdad (net.ownerCharacterId,
--- la cache que bindCharacter/applyOwnerRoleToRecord mantienen sincronizada
--- con characterPermissions[id].role=="owner", ver comentario en
--- bindCharacter) - nunca vuelve a escribir nada, nunca migra nada, nunca
--- inicializa nada por su cuenta. La migracion de fichas legacy y la
--- inicializacion de redes nuevas siguen ocurriendo, pero SOLO a traves de
--- canAccess()/bindOwnerIdentity() cuando corresponde - no como efecto
--- colateral de una simple pregunta "¿eres el dueño?".
---@param player IsoPlayer
---@param networkId string
---@return boolean
function GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId)
	if not player then return false end
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net or not net.ownerCharacterId or net.ownerCharacterId == "" then return false end
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	return characterId ~= "" and characterId == net.ownerCharacterId
end

---@param networkId string
---@param characterName string
---@return boolean
function GlobalStorageSiK.Permissions.addUser(networkId, characterName)
	local displayName = displayText(characterName)
	local characterKey = normalizeName(displayName)
	if characterKey == "" then
		return false
	end
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	local list = net.allowedUsers
	for i = 1, #list do
		if normalizeName(list[i]) == characterKey then
			list[i] = displayName
			return false
		end
	end
	table.insert(list, displayName)
	return true
end

--- Añade un miembro desconectado de la facción mediante la cuenta que vanilla
--- persiste. El servidor vuelve a comprobar la membresía; el cliente no puede
--- convertir un nombre arbitrario en permiso usando este camino. Si está
--- conectado se vincula ya al ID de personaje; si no, canAccess lo migrará al
--- conectarse por primera vez.
---@param networkId string
---@param requestingPlayer IsoPlayer
---@param username string
---@return boolean
function GlobalStorageSiK.Permissions.addFactionUsername(networkId, requestingPlayer, username)
	if not GlobalStorageSiK.Permissions.isFactionUsername(requestingPlayer, username) then
		return false, false, "invalid_or_stale_identity"
	end
	local onlinePlayer = nil
	if getPlayerFromUsername then
		local ok, value = pcall(getPlayerFromUsername, username)
		if ok then onlinePlayer = value end
	end
	if onlinePlayer then
		return GlobalStorageSiK.Permissions.addCharacter(networkId, onlinePlayer)
	end
	if GlobalStorageSiK.Permissions.addUser(networkId, username) then
		return true, true, "added_offline"
	end
	return true, false, "already_member"
end

--- Quita personaje permitido.
---@param networkId string
---@param characterName string
---@return boolean
function GlobalStorageSiK.Permissions.removeUser(networkId, characterName)
	characterName = normalizeName(characterName)
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	local list = net and net.allowedUsers
	if not list then
		return false
	end
	for i = #list, 1, -1 do
		if normalizeName(list[i]) == characterName then
			table.remove(list, i)
			if net.memberZoneDenials then
				net.memberZoneDenials[zoneMemberKey(nil, characterName)] = nil
			end
			return true
		end
	end
	return false
end

--- Añade facción autorizada por nombre.
---@param networkId string
---@param factionName string
---@return boolean
function GlobalStorageSiK.Permissions.addFaction(networkId, factionName)
	factionName = normalizeName(factionName)
	if factionName == "" then
		return false
	end
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	local list = net.allowedFactions
	for i = 1, #list do
		if list[i] == factionName then
			return false
		end
	end
	table.insert(list, factionName)
	return true
end

--- Quita facción autorizada.
---@param networkId string
---@param factionName string
---@return boolean
function GlobalStorageSiK.Permissions.removeFaction(networkId, factionName)
	factionName = normalizeName(factionName)
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	local list = net and net.allowedFactions
	if not list then
		return false
	end
	for i = #list, 1, -1 do
		if list[i] == factionName then
			table.remove(list, i)
			return true
		end
	end
	return false
end

--- Añade todos los miembros de la facción del jugador, conectados o no.
---@param networkId string
---@param player IsoPlayer
---@return boolean ok
---@return string message
---@return boolean changed
function GlobalStorageSiK.Permissions.addAllFactionMembers(networkId, player)
	local faction = GlobalStorageSiK.Permissions.getPlayerFaction(player)
	if not faction then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermNoFaction"), false
	end
	local added = 0
	local seen = {}

	local function tryAddUsername(username)
		if not username or username == "" or seen[username] then
			return
		end
		seen[username] = true
		local onlinePlayer = nil
		if getPlayerFromUsername then
			local ok, value = pcall(getPlayerFromUsername, username)
			if ok then onlinePlayer = value end
		end
		if onlinePlayer then
			local ok, changed = GlobalStorageSiK.Permissions.addCharacter(networkId, onlinePlayer)
			if ok and changed then
				added = added + 1
			end
			-- Si ya era owner/miembro no degradarlo a una entrada nominal.
			return
		end
		local charName = GlobalStorageSiK.Permissions.resolveCharacterName(username)
		if charName ~= "" and GlobalStorageSiK.Permissions.addUser(networkId, charName) then
			added = added + 1
		end
	end

	local factionUsernames = GlobalStorageSiK.Permissions.getFactionUsernames(player)
	for i = 1, #factionUsernames do
		tryAddUsername(factionUsernames[i])
	end

	if added == 0 and (getOnlinePlayers or getActivePlayers) then
		local fname = faction.getName and faction:getName() or ""
		local ok, players = pcall(function()
			return getOnlinePlayers and getOnlinePlayers() or getActivePlayers()
		end)
		if ok and players and players.size and fname ~= "" then
			for i = 0, players:size() - 1 do
				local p = players:get(i)
				if p and p.getUsername then
					local uname = p:getUsername()
					if GlobalStorageSiK.Permissions.sameFaction(uname, player:getUsername()) then
					local charName = GlobalStorageSiK.Permissions.getCharacterName(p)
					local addOk, changed = GlobalStorageSiK.Permissions.addCharacter(networkId, p)
					if charName ~= "" and addOk and changed then
							added = added + 1
						end
					end
				end
			end
		end
	end

	if added == 0 then
		return true, GlobalStorageSiK.I18n.remote("IGUI_GS_FactionMembersAddedNone"), false
	end
	return true, GlobalStorageSiK.I18n.remote("IGUI_GS_FactionMembersAddedMsg", added), true
end

--- Cuenta miembros de respaldo (admins + usuarios normales) de una red, sin
--- contar al propio owner. Usado para el aviso de "sin admin de respaldo" en
--- la UI y para decidir el destino de la sucesión al morir el propietario.
---@param networkId string
---@return number
function GlobalStorageSiK.Permissions.countBackupMembers(networkId)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then return 0 end
	local count = 0
	local seen = {}
	for characterId, record in pairs(net.characterPermissions or {}) do
		if isModernCharacterId(characterId) and characterId ~= net.ownerCharacterId and record
			and record.role ~= GlobalStorageSiK.Permissions.ROLE_DEAD then
			count = count + 1
			seen[normalizeName(record.name)] = true
			seen[normalizeName(record.username)] = true
		end
	end
	for _, field in ipairs({ "allowedUsers", "adminUsers" }) do
		for i = 1, #(net[field] or {}) do
			local key = normalizeName(net[field][i])
			if key ~= "" and not seen[key] then
				seen[key] = true
				count = count + 1
			end
		end
	end
	return count
end

--- Promueve al primer admin (o si no hay, al primer miembro normal) como
--- nuevo owner de UNA red concreta, o la deja sin dueño si no hay nadie con
--- quien suceder. Extraido de handleOwnerDeath para poder reutilizarlo tanto
--- en la sucesion por muerte (todas las redes de un personaje) como en un
--- abandono voluntario de una sola red (leaveNetwork).
---@param networkId string
---@param net table
---@param leavingCharacterName string
local function promoteOrClearOwner(networkId, net, leavingCharacterName, leavingCharacterId)
	local promoted = nil
	local promotedId = nil
	local promotedRecord = nil
	for characterId, record in pairs(net.characterPermissions or {}) do
		if isModernCharacterId(characterId)
			and characterId ~= leavingCharacterId and record
			and record.role == GlobalStorageSiK.Permissions.ROLE_ADMIN then
			promotedId = characterId
			promoted = record.name
			promotedRecord = record
			break
		end
	end
	if not promoted then
		for characterId, record in pairs(net.characterPermissions or {}) do
			if isModernCharacterId(characterId)
				and characterId ~= leavingCharacterId and record
				and record.role == GlobalStorageSiK.Permissions.ROLE_MEMBER then
				promotedId = characterId
				promoted = record.name
				promotedRecord = record
				break
			end
		end
	end
	if not promoted and net.adminUsers and #net.adminUsers > 0 then
		promoted = net.adminUsers[1]
	elseif not promoted and net.allowedUsers and #net.allowedUsers > 0 then
		promoted = net.allowedUsers[1]
	end
	if promoted and promoted ~= "" then
		if promotedId and net.characterPermissions[promotedId] then
			applyOwnerRoleToRecord(net, promotedId, net.characterPermissions[promotedId])
		else
			-- Fallback nominal (sin ficha moderna, solo nombre en las listas
			-- legacy allowedUsers/adminUsers) - se vinculara a una ficha real la
			-- proxima vez que ese personaje conecte (ver bindOwnerIdentity).
			net.owner = promoted
			net.ownerCharacterId = promotedId or ""
			net.ownerAccountLogin = displayText(promoted)
			net.ownerSteamId = getSteamIdForUsername(net.ownerAccountLogin)
		end
		local promotedNorm = normalizeName(promoted)
		if net.adminUsers then
			for i = #net.adminUsers, 1, -1 do
				if normalizeName(net.adminUsers[i]) == promotedNorm then
					table.remove(net.adminUsers, i)
				end
			end
		end
		if net.allowedUsers then
			for i = #net.allowedUsers, 1, -1 do
				if normalizeName(net.allowedUsers[i]) == promotedNorm then
					table.remove(net.allowedUsers, i)
				end
			end
		end
		if GlobalStorageSiK.Log then
			GlobalStorageSiK.Log.info("Permissions", "ownerSuccession",
				networkId .. ": " .. leavingCharacterName .. " -> " .. promoted)
		end
	else
		net.owner = ""
		net.ownerCharacterId = nil
		net.ownerAccountLogin = nil
		net.ownerSteamId = nil
		if GlobalStorageSiK.Log then
			GlobalStorageSiK.Log.info("Permissions", "ownerSuccession",
				networkId .. ": " .. leavingCharacterName .. " -> (sin miembros, red sin dueño)")
		end
	end
	if leavingCharacterId and net.characterPermissions then
		net.characterPermissions[leavingCharacterId] = nil
	end
end

--- Abandona voluntariamente UNA red concreta (a diferencia de
--- handleOwnerDeath, que actua sobre TODAS las redes que poseia el
--- personaje - aqui el jugador puede seguir siendo owner de otras redes
--- suyas sin verse afectado). Si es el owner, sucede exactamente igual que
--- al morir (promociona admin/miembro o deja la red sin dueño); si es
--- admin/miembro normal, simplemente se quita de las listas.
---@param networkId string
---@param characterName string
---@return boolean ok
---@return string message
function GlobalStorageSiK.Permissions.leaveNetwork(networkId, characterName)
	local exactName = displayText(characterName)
	local characterKey = normalizeName(exactName)
	if characterKey == "" then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_NetworkNotFoundMsg")
	end
	if net.owner and normalizeName(net.owner) == characterKey then
		promoteOrClearOwner(networkId, net, exactName)
		return true, GlobalStorageSiK.I18n.remote("IGUI_GS_LeftNetworkMsg")
	end
	local removedAdmin = false
	if net.adminUsers then
		for i = #net.adminUsers, 1, -1 do
			if normalizeName(net.adminUsers[i]) == characterKey then
				table.remove(net.adminUsers, i)
				removedAdmin = true
			end
		end
	end
	local removedUser = GlobalStorageSiK.Permissions.removeUser(networkId, exactName)
	if not removedUser and not removedAdmin then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_UserNotFoundToRemoveMsg")
	end
	return true, GlobalStorageSiK.I18n.remote("IGUI_GS_LeftNetworkMsg")
end

function GlobalStorageSiK.Permissions.leaveNetworkPlayer(networkId, player)
	if not player then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_NetworkNotFoundMsg")
	end
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	local characterName = GlobalStorageSiK.Permissions.getCharacterName(player)
	if bindOwnerIdentity(net, player) then
		promoteOrClearOwner(networkId, net, characterName, characterId)
		return true, GlobalStorageSiK.I18n.remote("IGUI_GS_LeftNetworkMsg")
	end
	local record = net.characterPermissions and net.characterPermissions[characterId]
		or migrateLegacyCharacterRecord(net, player)
	if record then
		local ok = GlobalStorageSiK.Permissions.removeCharacter(networkId, characterId)
		return ok, GlobalStorageSiK.I18n.remote(ok and "IGUI_GS_LeftNetworkMsg" or "IGUI_GS_UserNotFoundToRemoveMsg")
	end
	return GlobalStorageSiK.Permissions.leaveNetwork(networkId, characterName)
end

--- Sucesión de propiedad al morir un personaje (rediseñado 2026-08-21,
--- "herencia de red" — reporte comunidad china: dueño muere, personaje
--- nuevo sin permisos, sin forma de recuperar la base). YA NO promociona a
--- nadie automáticamente: la vieja promoteOrClearOwner() decidía por
--- pairs() (orden NO garantizado en Lua, contradice "el admin más antiguo
--- hereda") y además podía asignar la propiedad a alguien desconectado que
--- quizá nunca vuelva. En su lugar:
---   1. Marca `diedAt` en la ficha de este personaje en TODAS las redes
---      donde tuviera cualquier rol (no solo donde era dueño) — necesario
---      para que la cascada de reclamo (canClaimVacantOwnership) y el modo
---      herencia sepan que ya no puede volver con ESE UUID.
---   2. Si era el dueño, la red pasa a VACANTE (`ownerCharacterId=nil`,
---      `owner=""`) — sin asignar a nadie. `ownerAccountLogin`/`ownerSteamId`
--- NUNCA se tocan aquí: son el ancla de herencia, deben sobrevivir a la
--- muerte indefinidamente (antes se borraban justo aquí, el hueco real que
--- impedía cualquier recuperación posterior).
--- El reclamo real (quién se queda la red) es una acción explícita y
--- posterior de quien aparezca (ver canClaimVacantOwnership/
--- claimVacantOwnership más abajo), nunca una decisión tomada en ausencia
--- de nadie. promoteOrClearOwner() sigue existiendo tal cual para el
--- abandono VOLUNTARIO (leaveNetwork/leaveNetworkPlayer) — ahí sí tiene
--- sentido promocionar de inmediato, es un caso distinto (decisión activa
--- de alguien presente, no una muerte).
--- Debe llamarse solo en el proceso autoritativo (servidor dedicado, host o
--- SP real) - GS_Server.lua la engancha a Events.OnPlayerDeath gateado por
--- GlobalStorageSiK.isAuthoritative().
---@param deadPlayerOrName IsoPlayer|string
function GlobalStorageSiK.Permissions.handleOwnerDeath(deadPlayerOrName)
	local deadPlayer = type(deadPlayerOrName) == "string" and nil or deadPlayerOrName
	local deadCharacterName = deadPlayer and GlobalStorageSiK.Permissions.getCharacterName(deadPlayer)
		or displayText(deadPlayerOrName)
	local deadCharacterId = deadPlayer and GlobalStorageSiK.Permissions.getCharacterId(deadPlayer) or ""
	local deadCharacterKey = normalizeName(deadCharacterName)
	-- BUG REAL cerrado (2026-08-26, revision tecnica de Desarrollo): esta
	-- guarda exigia un NOMBRE no vacio para procesar la muerte, mezclando
	-- presentacion con identidad - un descriptor de personaje defectuoso o
	-- un nombre Unicode temporalmente irresoluble (mismo problema ya
	-- documentado con SurvivorDesc y nombres chinos) bloqueaba la vacante
	-- entera aunque el UUID (la identidad real) fuera perfectamente valido.
	-- Ahora solo se abandona si NO hay forma de identificar al personaje de
	-- NINGUNA manera (ni UUID ni nombre) - el nombre pasa a ser solo una
	-- etiqueta de auditoria en los logs/historial, nunca una condicion para
	-- marcar la vida como terminada.
	if deadCharacterId == "" and deadCharacterKey == "" then
		-- Log SIEMPRE visible (no gateado por Modo depuracion) para poder
		-- confirmar si esto llega a pasar de verdad.
		if GlobalStorageSiK.Log then
			GlobalStorageSiK.Log.error("Permissions", "handleOwnerDeath",
				"ni UUID ni nombre disponibles al morir - vacante NO procesada para ninguna red")
		end
		return
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local networks = registry and registry.networks
	if not networks then
		return
	end
	local deathTimestamp = nowMs()
	-- Se enumeran los IDs desde el registro OPERATIVO (es quien sabe que
	-- redes existen) pero TODA mutacion de aqui en adelante es sobre la
	-- ModData de permisos propia (getPermNet) - BUG CRITICO cerrado
	-- (2026-08-22, separacion de responsabilidades): esta funcion escribia
	-- directamente sobre el objeto operativo, que ya no contiene
	-- characterPermissions/owner* desde la separacion - la muerte de un
	-- personaje dejaba de vaciar ninguna red de verdad, silenciosamente.
	for networkId in pairs(networks) do
		local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
		if deadPlayer then bindOwnerIdentity(net, deadPlayer) end
		if deadCharacterId ~= "" and net.characterPermissions and net.characterPermissions[deadCharacterId] then
			markRecordDead(net.characterPermissions[deadCharacterId], deathTimestamp)
		end
		local ownsById = deadCharacterId ~= "" and net.ownerCharacterId == deadCharacterId
		local ownsLegacy = (not net.ownerCharacterId or net.ownerCharacterId == "")
			and net.owner and net.owner ~= "" and normalizeName(net.owner) == deadCharacterKey
		if ownsById or ownsLegacy then
			net.ownerCharacterId = nil
			net.owner = ""
			if GlobalStorageSiK.Log then
				GlobalStorageSiK.Log.info("Permissions", "networkVacant",
					networkId .. ": " .. deadCharacterName
						.. " murio, red vacante (reclamo pendiente, ownerAccountLogin conservado="
						.. tostring(net.ownerAccountLogin or "") .. ")")
			end
			recordNetworkHistoryEvent(networkId, "owner_died",
				deadCharacterName .. " murio - red vacante, ownerAccountLogin conservado="
					.. tostring(net.ownerAccountLogin or ""))
		end
		-- NUNCA se borra la ficha al morir (decision final 2026-08-22, tras
		-- discutir "el miembro que ha muerto, ¿desaparece o lo mantienes?" y
		-- llegar a la conclusion correcta): el campo role de
		-- characterPermissions es la UNICA fuente de verdad para cualquier
		-- rango de cualquier miembro, para cualquier consumidor - y eso incluye
		-- ahora tambien "esta muerto" (ROLE_DEAD, ver markRecordDead arriba):
		-- reutilizar el mismo campo, en vez de un diedAt aislado que cada
		-- consumidor tenia que acordarse de comprobar aparte, es lo que vacia
		-- el acceso/escalada de reclamo automaticamente en todo el fichero sin
		-- tocar cada punto de codigo. record.priorRole conserva el rol de antes
		-- de morir para el Nivel 3 de canClaimVacantOwnership (herencia por
		-- cuenta). Conservar la ficha tal cual es el registro
		-- reutilizable/consultable pedido explicitamente ("mantener registro
		-- que debamos reutilizar... marcar como muerto, guardamos el
		-- historico, podemos consultarlo si se requiere"). El riesgo de
		-- "propietario duplicado" que motivo borrar en un intento anterior ya
		-- esta cerrado en el ORIGEN por bindCharacter/applyOwnerRoleToRecord
		-- (unico escritor de role=owner, demota automaticamente a cualquier
		-- otra ficha que lo dijera) - no hace falta borrar nada aqui para
		-- evitarlo.
	end
	GlobalStorageSiK.Permissions.requestTransmit()
end

--- Umbral de inactividad (ms) para dejar de "bloquear" la escalada a un
--- reclamo de rango inferior o al modo herencia. Un admin/miembro que nunca
--- muere pero deja de jugar bloquearia una red vacante para siempre sin
--- esto (caso real señalado: "red huerfana en el aire" con un miembro que
--- abandono el juego sin que su personaje llegara a morir). Sandbox
--- GS_NetworkInactivityDays (GS_Sandbox.lua) - fallback de 14 dias si la
--- opcion todavia no esta cableada, para que esta funcion nunca falle
--- aunque se despliegue antes que el resto del sandbox.
---@return number ms
local function inactivityThresholdMs()
	local days = 14
	if GlobalStorageSiK.Sandbox and GlobalStorageSiK.Sandbox.getNetworkInactivityDays then
		local ok, value = pcall(GlobalStorageSiK.Sandbox.getNetworkInactivityDays)
		if ok and type(value) == "number" and value > 0 then days = value end
	end
	return days * 24 * 60 * 60 * 1000
end

--- Indica si una ficha de personaje sigue "bloqueando" la escalada de nivel
--- de reclamo: vivo (sin diedAt) Y visto recientemente (dentro del umbral de
--- inactividad). Confirmado muerto, o inactivo mas alla del umbral, deja de
--- bloquear - pero SIN perder su rol real si vuelve antes de que otro reclame.
---@param record table
---@param nowTs number
---@return boolean
local function recordBlocksEscalation(record, nowTs)
	if not record then return false end
	if record.diedAt and record.diedAt > 0 then return false end
	local lastSeen = record.lastSeenAt
	if lastSeen and lastSeen > 0 and (nowTs - lastSeen) > inactivityThresholdMs() then
		return false
	end
	return true
end

--- Evalua si ESTE jugador puede reclamar la propiedad de una red VACANTE
--- (dueño muerto, sin dueño vivo desde entonces). Cascada explicita, nunca
--- decidida en ausencia de nadie (diseño "herencia de red", 2026-08-21;
--- nivel 0 añadido 2026-08-22 tras revisar en pruebas reales que un member
--- con custodia temporal dejaba fuera al propio dueño original sin motivo).
---
--- IMPORTANTE - "admin" aqui SIEMPRE significa ROLE_ADMIN, el rol DENTRO de
--- ESTA red (member vs admin vs owner, ver GlobalStorageSiK.Permissions.
--- ROLE_ADMIN), NUNCA el rango de staff del servidor (isServerStaff:
--- admin/moderator/overseer/gm). Son dos conceptos deliberadamente separados
--- desde que se cerro esa confusion como deuda tecnica (ver comentario de
--- isServerStaff, mas arriba en este fichero) - esta funcion NO llama a
--- isServerStaff en ningun punto, un rango de servidor no adelanta a nadie
--- aqui ni pinta nada en esta cascada.
---
---   Nivel 0 (dueño original DE LA RED, SIEMPRE, sin esperar a nadie): si la
---     cuenta de login de quien pregunta coincide con `ownerAccountLogin`,
---     reclama de inmediato - es SU red, ningun admin/member DE RED con
---     custodia temporal puede retenerla ni un instante, no hace falta que
---     nadie deje de "bloquear" primero.
---   Nivel 1 (admin DE RED vivo, cualquier OTRA cuenta): si el propio
---     personaje VIVO del jugador ya tiene ROLE_ADMIN registrado en esta
---     red, puede reclamar.
---   Nivel 2 (member DE RED vivo, cualquier OTRA cuenta): se abre SOLO si
---     ningun admin DE RED registrado sigue "bloqueando"
---     (recordBlocksEscalation) - entonces cualquier member vivo, incluido
---     este jugador si lo es, puede reclamar.
---   Nivel 3 (herencia por cuenta de un antiguo admin DE RED): se abre SOLO
---     si NADIE con rol DE RED (admin o member) sigue bloqueando - entonces
---     la cuenta de cualquier antiguo admin DE RED puede reclamar con un
---     personaje nuevo, aunque su UUID anterior haya desaparecido con la
---     muerte. El propietario original ya no pasa por aqui, se resuelve en
---     el nivel 0.
---@param player IsoPlayer
---@param networkId string
---@return boolean canClaim
---@return string|nil tier "owner"|"admin"|"member"|"heir"|nil
function GlobalStorageSiK.Permissions.canClaimVacantOwnership(player, networkId)
	if not player then return false, nil end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then return false, nil end
	if displayText(net.ownerAccountLogin) == "" then return false, nil end
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	local myRecord = characterId ~= "" and net.characterPermissions and net.characterPermissions[characterId] or nil
	local nowTs = nowMs()
	-- Nivel 0 (prioridad maxima, SIN esperar a que nadie deje de bloquear,
	-- y SIN exigir vacante): la cuenta que era propietaria ORIGINAL DE LA
	-- RED siempre puede reclamar su propia red, la tenga quien la tenga en
	-- custodia temporal. Decision explicita (2026-08-22): un member DE RED
	-- (o incluso un admin DE RED) con custodia temporal NO deberia poder
	-- dejar fuera para siempre - o durante un umbral de inactividad
	-- arbitrario - al dueño real solo por seguir "activo". Los niveles 1-3
	-- de abajo son para CUALQUIER OTRA cuenta (antiguos admins DE RED,
	-- nadie), nunca para el propietario original, que ya queda resuelto
	-- aqui. Mismo anti-suplantacion que bindOwnerIdentity: si hay steamId
	-- guardado, debe coincidir con el actual, el username solo no basta.
	--
	-- BUG REAL DE REGRESION cerrado (2026-08-26, encontrado en pruebas
	-- reales tras dev6/dev9: "esto si funcionaba antes, alguna guarda
	-- retirada nos habilitaba el acceso y ahora no"): este Nivel 0 quedaba
	-- SIEMPRE inalcanzable porque el chequeo de vacante (net.ownerCharacterId
	-- ~= "") se hacia ANTES, incondicional para TODOS los niveles. Desde que
	-- dev6 dejo de vaciar la red automaticamente sobre una rotacion de UUID
	-- no confirmada (identityRotationUnproven, correcto - evita declarar
	-- muertes falsas), la red YA NUNCA vuelve a quedar vacante sola, asi que
	-- la propia cuenta original - el caso MEJOR verificado de todos, con
	-- comprobacion de SteamID incluida - se quedaba bloqueada para siempre
	-- salvo intervencion manual de staff. Movido el chequeo de vacante
	-- DESPUES de este bloque: el Nivel 0 ya no exige vacante (la propia
	-- cuenta puede reclamar lo suyo este quien este puesto ahora mismo),
	-- los niveles 1-3 (para CUALQUIER OTRA cuenta) siguen exigiendola sin
	-- cambios - no se abre ningun hueco de seguridad nuevo, solo se repara
	-- el caso que ya estaba pensado para funcionar asi desde el principio.
	local myAccount = normalizeName(getPlayerUsername(player))
	if myAccount ~= "" and myAccount == normalizeName(net.ownerAccountLogin) then
		local currentSteamId = getSteamIdForUsername(getPlayerUsername(player))
		local steamOk = displayText(net.ownerSteamId) == "" or currentSteamId == ""
			or displayText(net.ownerSteamId) == currentSteamId
		if steamOk then
			return true, "owner"
		end
	end
	if net.ownerCharacterId and net.ownerCharacterId ~= "" then return false, nil end
	local blockingAdminExists = false
	local blockingMemberExists = false
	for _, record in pairs(net.characterPermissions or {}) do
		if record and recordBlocksEscalation(record, nowTs) then
			if record.role == GlobalStorageSiK.Permissions.ROLE_ADMIN then
				blockingAdminExists = true
			elseif record.role == GlobalStorageSiK.Permissions.ROLE_MEMBER then
				blockingMemberExists = true
			end
		end
	end
	-- Nivel 1: este jugador YA tiene ROLE_ADMIN (rol DE RED) vivo registrado.
	if myRecord and myRecord.role == GlobalStorageSiK.Permissions.ROLE_ADMIN
		and recordBlocksEscalation(myRecord, nowTs) then
		return true, "admin"
	end
	if blockingAdminExists then
		-- Hay OTRO admin DE RED que todavia podria volver - no se abre nada mas.
		return false, nil
	end
	-- Nivel 2: sin admin DE RED vivo que bloquee, cualquier member vivo puede.
	if myRecord and myRecord.role == GlobalStorageSiK.Permissions.ROLE_MEMBER
		and recordBlocksEscalation(myRecord, nowTs) then
		return true, "member"
	end
	if blockingMemberExists then
		return false, nil
	end
	-- Nivel 3: nadie con rol DE RED sigue bloqueando - herencia por cuenta
	-- de un antiguo admin DE RED (el propietario original ya se resolvio
	-- con prioridad maxima al principio de esta funcion, sin esperar a este
	-- punto). Si ningun admin/member DE RED activo bloquea, la cuenta de un
	-- antiguo admin DE RED de confianza tampoco debe quedar bloqueada para
	-- siempre. Un antiguo admin normalmente llega aqui ya con role=ROLE_DEAD
	-- (markRecordDead) - se comprueba priorRole en ese caso, que es donde
	-- queda guardado el rol que tenia justo antes de morir.
	if myAccount ~= "" then
		for _, record in pairs(net.characterPermissions or {}) do
			local effectiveRole = record and record.role
			if effectiveRole == GlobalStorageSiK.Permissions.ROLE_DEAD then
				effectiveRole = record.priorRole
			end
			if record and effectiveRole == GlobalStorageSiK.Permissions.ROLE_ADMIN
				and normalizeName(record.accountUsername) == myAccount then
				return true, "heir"
			end
		end
	end
	return false, nil
end

--- Ejecuta el reclamo de una red vacante, REVALIDANDO en servidor la misma
--- condicion que canClaimVacantOwnership (nunca confiar en que un boton
--- mostrado antes siga siendo valido en el momento de pulsarlo). Vincula al
--- jugador como nuevo dueño con su UUID actual; nunca toca
--- ownerAccountLogin (sigue siendo el ancla real, se sobreescribe solo con
--- la cuenta de quien reclama, coherente con quien es el dueño ahora).
---@param player IsoPlayer
---@param networkId string
---@return boolean ok
---@return string message
function GlobalStorageSiK.Permissions.claimVacantOwnership(player, networkId)
	if not player then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
	end
	local canClaim, tier = GlobalStorageSiK.Permissions.canClaimVacantOwnership(player, networkId)
	if not canClaim then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCannotClaimMsg")
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_NetworkNotFoundMsg")
	end
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	if characterId == "" then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
	end
	-- bindCharacter con ROLE_OWNER es AHORA el unico escritor de
	-- net.owner/ownerCharacterId/ownerAccountLogin/ownerSteamId (fuente unica
	-- de verdad, ver comentario en bindCharacter) - hace cumplir solo tambien
	-- que ninguna otra ficha se quede diciendo "owner" por error.
	bindCharacter(net, player, GlobalStorageSiK.Permissions.ROLE_OWNER)
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.info("Permissions", "ownershipClaimed",
			networkId .. ": " .. net.owner .. " reclamo la red (nivel=" .. tostring(tier) .. ")")
	end
	recordNetworkHistoryEvent(networkId, "claimed",
		net.owner .. " (cuenta " .. tostring(net.ownerAccountLogin) .. ") reclamo la red - nivel=" .. tostring(tier))
	GlobalStorageSiK.Permissions.requestTransmit()
	return true, GlobalStorageSiK.I18n.remote("IGUI_GS_PermOwnershipClaimedMsg")
end

--- Evalua si ESTE jugador puede recuperar su PROPIO rol anterior (admin o
--- member - NUNCA owner, que ya tiene su propia cascada completa arriba,
--- Nivel 0-3) en una red donde su CUENTA tuvo una ficha marcada muerta.
--- Decision de diseño explicita (2026-08-23, feedback directo del usuario:
--- "los miembros y administradores que queden en una red cuyo propietario
--- muere, no deben perder el acceso... el miembro tambien debe poder
--- recuperar, eran huecos existentes que obligaban a volver a invitar a los
--- jugadores que ya eran miembros"): a diferencia de canClaimVacantOwnership
--- (que decide QUIEN se convierte en el nuevo propietario de una red SIN
--- dueño, con prioridad entre varios candidatos posibles compitiendo por un
--- puesto vacante), esto no es una cascada ni una competicion - es
--- simplemente "esta cuenta ya tenia acceso aqui, con este rol, antes de que
--- su personaje muriera, se lo devolvemos a su personaje nuevo". Por eso NO
--- depende de que la red este vacante (net.owner=="") en absoluto: un admin
--- vivo puede seguir accediendo con normalidad aunque el propietario haya
--- muerto (ver reordenacion de canAccess, mas abajo en este fichero) - el
--- unico motivo por el que alguien llega a necesitar ESTO es que su PROPIO
--- personaje murio, sea cual sea el estado del resto de la red.
---@param player IsoPlayer
---@param networkId string
---@return boolean canRecover
---@return string|nil role rol a recuperar (admin/member), o nil si no aplica
function GlobalStorageSiK.Permissions.canRecoverOwnRole(player, networkId)
	if not player then return false, nil end
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then return false, nil end
	local myAccount = normalizeName(getPlayerUsername(player))
	if myAccount == "" then return false, nil end
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	-- Si el characterId ACTUAL ya tiene ficha propia (viva o muerta bajo este
	-- mismo UUID), este no es el caso de "personaje nuevo" que cubre esta
	-- funcion - canAccess ya resuelve esos casos por su cuenta (acceso normal
	-- o revivido, ver mas abajo).
	if characterId ~= "" and net.characterPermissions and net.characterPermissions[characterId] then
		return false, nil
	end
	local bestRole, bestDiedAt = nil, -1
	for _, record in pairs(net.characterPermissions or {}) do
		if record and record.role == GlobalStorageSiK.Permissions.ROLE_DEAD
			and (record.priorRole == GlobalStorageSiK.Permissions.ROLE_ADMIN
				or record.priorRole == GlobalStorageSiK.Permissions.ROLE_MEMBER)
			and normalizeName(record.accountUsername) == myAccount then
			local diedAt = record.diedAt or 0
			if diedAt >= bestDiedAt then
				bestDiedAt = diedAt
				bestRole = record.priorRole
			end
		end
	end
	if bestRole then return true, bestRole end
	return false, nil
end

--- Ejecuta la recuperacion (ver canRecoverOwnRole) - revalida en servidor,
--- nunca confia en que el boton mostrado antes siga siendo valido. Vincula
--- el characterId ACTUAL con el rol recuperado; la ficha muerta antigua se
--- queda tal cual, como historico (mismo criterio que el resto del fichero:
--- nunca se borra nada al morir).
---@param player IsoPlayer
---@param networkId string
---@return boolean ok
---@return string message
function GlobalStorageSiK.Permissions.recoverOwnRole(player, networkId)
	if not player then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
	end
	local canRecover, role = GlobalStorageSiK.Permissions.canRecoverOwnRole(player, networkId)
	if not canRecover then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCannotClaimMsg")
	end
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_NetworkNotFoundMsg")
	end
	local record = bindCharacter(net, player, role)
	if not record then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
	end
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.info("Permissions", "roleRecovered",
			networkId .. ": " .. tostring(record.characterName) .. " recupero su rol anterior (" .. tostring(role) .. ")")
	end
	recordNetworkHistoryEvent(networkId, "role_recovered",
		tostring(record.characterName) .. " (cuenta " .. tostring(record.accountUsername)
			.. ") recupero su rol anterior: " .. tostring(role))
	GlobalStorageSiK.Permissions.requestTransmit()
	return true, GlobalStorageSiK.I18n.remote("IGUI_GS_PermRoleRecoveredMsg")
end

--- Umbral de inactividad del PROPIETARIO antes de que un admin VIVO de la
--- red pueda reclamar la propiedad el mismo (auto-promocion) - sandbox
--- configurable, DISTINTO de inactivityThresholdMs() de arriba a proposito
--- (dos decisiones de politica de servidor separadas, ver comentario de
--- GS_Sandbox.getOwnerInactivityClaimDays). Pedido explicito (2026-08-23):
--- "el admin... debe poder reclamar la propiedad si hace mas de 3 dias que
--- el viejo propietario no se conecta".
---@return number ms
local function ownerInactivityThresholdMs()
	local days = 3
	if GlobalStorageSiK.Sandbox and GlobalStorageSiK.Sandbox.getOwnerInactivityClaimDays then
		local ok, value = pcall(GlobalStorageSiK.Sandbox.getOwnerInactivityClaimDays)
		if ok and type(value) == "number" and value > 0 then days = value end
	end
	return days * 24 * 60 * 60 * 1000
end

--- Evalua si un admin VIVO de esta red puede reclamar la propiedad EL MISMO,
--- sin pasar nunca por la pantalla de bloqueo - a diferencia de
--- canClaimVacantOwnership/canRecoverOwnRole (pensadas para alguien que
--- ACTUALMENTE no tiene acceso), un admin vivo ya tiene acceso normal
--- (ver reordenacion de canAccess: la vacante de owner nunca se lo quita) y
--- esta accion vive en su propia pestaña de administracion. Dos motivos
--- validos, cualquiera de los dos:
---   (a) La red esta genuinamente vacante (net.owner=="") - propietario
---       muerto o red que nunca tuvo uno con este admin ya vinculado.
---   (b) La red SI tiene un propietario registrado, pero su propia ficha
---       lleva mas de ownerInactivityThresholdMs() sin conectarse
---       (lastSeenAt) - "propietario en paradero desconocido", distinto de
---       "propietario muerto" (eso ya vacia net.owner via handleOwnerDeath,
---       cae en el caso (a) de todos modos).
---@param player IsoPlayer
---@param networkId string
---@return boolean canClaim
function GlobalStorageSiK.Permissions.canAdminClaimOwnership(player, networkId)
	if not player then return false end
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then return false end
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	if characterId == "" then return false end
	local myRecord = net.characterPermissions and net.characterPermissions[characterId]
	if not myRecord or myRecord.role ~= GlobalStorageSiK.Permissions.ROLE_ADMIN then
		return false
	end
	if not net.owner or net.owner == "" then
		return true
	end
	if net.ownerCharacterId == characterId then
		return false
	end
	local ownerRecord = net.ownerCharacterId ~= "" and net.characterPermissions
		and net.characterPermissions[net.ownerCharacterId]
	local ownerLastSeen = ownerRecord and ownerRecord.lastSeenAt
	if not ownerLastSeen or ownerLastSeen <= 0 then
		-- Sin dato de actividad del propietario (ficha antigua/migrada): no
		-- asumir inactividad sin evidencia, mejor no ofrecer el reclamo.
		return false
	end
	return (nowMs() - ownerLastSeen) > ownerInactivityThresholdMs()
end

--- Ejecuta la auto-promocion de un admin VIVO a propietario por inactividad
--- del dueño (ver canAdminClaimOwnership) - revalida en servidor, nunca
--- confia en que el boton mostrado antes siga siendo valido.
---@param player IsoPlayer
---@param networkId string
---@return boolean ok
---@return string message
function GlobalStorageSiK.Permissions.adminClaimOwnership(player, networkId)
	if not player then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
	end
	if not GlobalStorageSiK.Permissions.canAdminClaimOwnership(player, networkId) then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_PermCannotClaimMsg")
	end
	local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
	if not net then
		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_NetworkNotFoundMsg")
	end
	local previousOwner = net.owner
	bindCharacter(net, player, GlobalStorageSiK.Permissions.ROLE_OWNER)
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.info("Permissions", "ownershipClaimedByAdmin",
			networkId .. ": " .. tostring(net.owner)
				.. " reclamo la propiedad como admin activo (dueño anterior inactivo: "
				.. tostring(previousOwner) .. ")")
	end
	recordNetworkHistoryEvent(networkId, "claimed_by_admin",
		tostring(net.owner) .. " (cuenta " .. tostring(net.ownerAccountLogin)
			.. ") reclamo la propiedad como admin activo - dueño anterior inactivo: " .. tostring(previousOwner))
	GlobalStorageSiK.Permissions.requestTransmit()
	return true, GlobalStorageSiK.I18n.remote("IGUI_GS_PermOwnershipClaimedMsg")
end

--- Pedido explicito (2026-08-26, revision tecnica de Desarrollo tras el
--- banco CJK de DEV15): "un reinicio sin ningun jugador puede no generar
--- actividad de permisos hasta la siguiente conexion" - para demostrar de
--- forma inequivoca que una red sobrevivio intacta a un reinicio SIN
--- clientes conectados (no solo que estaba correcta cuando por fin conecto
--- alguien), se vuelca el estado de cada red nada mas arrancar el proceso,
--- ANTES de que ningun jugador haya podido tocar nada. Log SIEMPRE visible
--- (no gateado por Modo depuracion, mismo criterio que identityBootstrap y
--- el resto de trazas "captura el instante" de esta ronda) - una linea por
--- red, formato de campos separados para grep/diff facil entre reinicios.
function GlobalStorageSiK.Permissions.logSessionStart()
	if not GlobalStorageSiK.isAuthoritative() or not GlobalStorageSiK.Log then
		return
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local networks = registry and registry.networks
	if not networks then
		return
	end
	local sessionId = tostring(nowMs())
	for networkId in pairs(networks) do
		local net = GlobalStorageSiK.Permissions.getPermNet(networkId)
		local recordsTotal = 0
		for _ in pairs((net and net.characterPermissions) or {}) do
			recordsTotal = recordsTotal + 1
		end
		GlobalStorageSiK.Log.warn("Permissions", "SESSION_START",
			"build=" .. tostring(GlobalStorageSiK.Config and GlobalStorageSiK.Config.MOD_VERSION or "?")
				.. " sessionId=" .. sessionId
				.. " network=" .. tostring(networkId)
				.. " ownerCharacterId=" .. tostring(net and net.ownerCharacterId or "")
				.. " ownerAccountLogin=" .. tostring(net and net.ownerAccountLogin or "")
				.. " networkVacant=" .. tostring(not (net and net.ownerCharacterId and net.ownerCharacterId ~= ""))
				.. " characterRecordsTotal=" .. tostring(recordsTotal))
	end
end

if Events and Events.OnInitGlobalModData then
	Events.OnInitGlobalModData.Add(function()
		GlobalStorageSiK.Permissions.logSessionStart()
	end)
end

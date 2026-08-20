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

--- Indica si deben aplicarse permisos (no en SP solo).
---@return boolean
function GlobalStorageSiK.Permissions.shouldEnforce()
	return GlobalStorageSiK.isMultiplayerActive()
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

local function getSteamIdForUsername(username, player)
	username = displayText(username)
	if username ~= "" and getSteamIDFromUsername then
		local ok, value = pcall(getSteamIDFromUsername, username)
		value = ok and displayText(value) or ""
		if value ~= "" and value ~= "0" and value ~= "-1" then return value end
	end
	if player and player.getSteamID then
		local ok, value = pcall(function() return player:getSteamID() end)
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
local identityUuidSeen = {}
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
	return " characterName=" .. permissionLogText(
		GlobalStorageSiK.Permissions.getCharacterName(player), 128)
		.. " username=" .. permissionLogText(getPlayerUsername(player), 128)
		.. " steamId=" .. permissionLogText(getSteamIdForUsername(
			getPlayerUsername(player), player), 64)
		.. " sqlId=" .. tostring(getPersistentSqlId(player) or "")
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
	-- DIAGNOSTICO DIRIGIDO (2026-08-20): traza SIEMPRE visible de CADA
	-- llamada a esta funcion, antes de cualquier logica - las trazas
	-- characterUuidReused/Generated de mas abajo NO aparecieron ni una vez
	-- en un log real de servidor donde el admin claramente se conecto y
	-- abrio el terminal con exito (accessCheck ok=true), lo que sugiere que
	-- esta funcion no se esta llamando en absoluto en ese flujo, no que el
	-- UUID se regenere. Esta linea confirma o descarta eso de un vistazo.
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.warn("Identity", "getOrCreateCharacterUuid CALLED reason=" .. tostring(reason or "?")
			.. " hasPlayer=" .. tostring(player ~= nil) .. " hasGetModData=" .. tostring(player and player.getModData ~= nil))
	end
	if not player or not player.getModData then return "" end
	local okData, data = pcall(function() return player:getModData() end)
	if not okData or not data then return "" end
	local existing = tostring(data[CHARACTER_UUID_KEY] or "")
	if validCharacterUuid(existing) then
		if not identityUuidSeen[existing] then
			identityUuidSeen[existing] = true
			if GlobalStorageSiK.Log then
				GlobalStorageSiK.Log.info("Identity", "characterUuidReused",
					"reason=" .. tostring(reason or "lookup")
						.. " characterId=character:" .. existing
						.. identityDiagnosticFields(player))
			end
		end
		return existing
	end
	if not GlobalStorageSiK.isAuthoritative() then return "" end
	local value = generateCharacterUuid()
	data[CHARACTER_UUID_KEY] = value
	identityUuidSeen[value] = true
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
	return getOrCreateCharacterUuid(player, "identity_lookup_fallback")
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
	return record
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
			and candidate.role ~= GlobalStorageSiK.Permissions.ROLE_OWNER then
			local nominallyAllowed = listContainsIdentity(net.allowedUsers, candidate.name, username)
				or listContainsIdentity(net.adminUsers, candidate.name, username)
			if nominallyAllowed then
				legacyId = candidateId
				legacy = candidate
				break
			end
		end
	end
	if not legacy then return nil end
	net.characterPermissions[legacyId] = nil
	net.characterPermissions[characterId] = legacy
	mergeZoneDenials(net, legacyId, characterId)
	local role = legacy.role
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
		net.owner = GlobalStorageSiK.Permissions.getCharacterName(player)
		net.ownerAccount = getPlayerUsername(player)
		net.ownerSteamId = getSteamIdForUsername(net.ownerAccount, player)
		bindCharacter(net, player, GlobalStorageSiK.Permissions.ROLE_OWNER)
		return true
	end
	local storedId = tostring(net.ownerCharacterId or "")
	if isModernCharacterId(storedId) then return false end
	local username = getPlayerUsername(player)
	local accountMatches = normalizeName(net.ownerAccount) ~= ""
		and normalizeName(net.ownerAccount) == normalizeName(username)
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
	if not accountMatches and normalizeName(net.ownerAccount) == "" and isNameLegacy then
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
	net.owner = GlobalStorageSiK.Permissions.getCharacterName(player)
	net.ownerAccount = username
	net.ownerSteamId = currentSteamId
	net.ownerCharacterId = characterId
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

--- Inicializa permisos de red.
---@param registry table
---@param networkId string
---@param ownerCharacter string|nil
function GlobalStorageSiK.Permissions.ensure(registry, networkId, ownerCharacter)
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local net = registry.networks[networkId]
	net.allowedUsers = net.allowedUsers or {}
	net.allowedFactions = net.allowedFactions or {}
	net.adminUsers = net.adminUsers or {}
	net.characterPermissions = net.characterPermissions or {}
	net.memberZoneDenials = net.memberZoneDenials or {}
	net.factionOnly = net.factionOnly == true
	if ownerCharacter and ownerCharacter ~= "" and (not net.owner or net.owner == "") then
		net.owner = ownerCharacter
	end
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
	net.owner = GlobalStorageSiK.Permissions.getCharacterName(player)
	net.ownerAccount = username
	net.ownerSteamId = getSteamIdForUsername(username, player)
	net.ownerCharacterId = characterId
	bindCharacter(net, player, GlobalStorageSiK.Permissions.ROLE_OWNER)
	return net.ownerCharacterId ~= ""
end

--- Elimina referencias a zonas que ya no existen o pertenecen a otra red.
--- Las zonas nuevas no se añaden: ausencia significa acceso permitido.
function GlobalStorageSiK.Permissions.cleanupZoneDenials(networkId)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = registry.networks and registry.networks[networkId]
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

--- Devuelve si el jugador puede usar los contenedores de una zona. Owner,
--- admins de red y staff conservan acceso total. En SP no se aplican permisos.
function GlobalStorageSiK.Permissions.canAccessZone(player, networkId, zoneId)
	if not player then return false end
	if not GlobalStorageSiK.Permissions.shouldEnforce() then return true end
	if GlobalStorageSiK.Permissions.isServerStaff(player)
		or GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId)
		or GlobalStorageSiK.Permissions.isAdminPlayer(player, networkId) then
		return true
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = registry.networks and registry.networks[networkId]
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
	local net = registry.networks[networkId]
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

--- Indica si el personaje tiene rol propietario o administrador DENTRO de
--- esta red. No concede acceso por rango global del servidor.
---@param player IsoPlayer
---@param networkId string
---@return boolean
function GlobalStorageSiK.Permissions.hasNetworkAdminRole(player, networkId)
	if GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId) then
		return true
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = registry.networks and registry.networks[networkId]
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

--- Indica si el jugador puede administrar la red. Conserva el override de
--- staff global para las herramientas generales de moderación.
---@param player IsoPlayer
---@param networkId string
---@return boolean
function GlobalStorageSiK.Permissions.isAdminPlayer(player, networkId)
	if GlobalStorageSiK.Permissions.isServerStaff(player) then
		return true
	end
	return GlobalStorageSiK.Permissions.hasNetworkAdminRole(player, networkId)
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
	local net = registry.networks[networkId]
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
	if GlobalStorageSiK.Permissions.isServerStaff(player) then
		return true
	end
	local characterName = GlobalStorageSiK.Permissions.getCharacterName(player)
	local username = player:getUsername()
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId, characterName)
	local net = registry.networks[networkId]
	if not net.owner or net.owner == "" then
		local initialized = GlobalStorageSiK.Permissions.initializeOwner(net, player)
		if initialized and ModData and ModData.transmit then
			ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		end
		return initialized, initialized and nil or "identity_unavailable"
	end
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	if bindOwnerIdentity(net, player) then
		return true
	end
	local characterRecord = net.characterPermissions and net.characterPermissions[characterId]
		or migrateLegacyCharacterRecord(net, player)
	if characterRecord then
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
		local ownerUser = net.ownerAccount
		if not ownerUser or ownerUser == "" then
			ownerUser = GlobalStorageSiK.Permissions.resolveUsernameFromCharacter(net.owner or "")
		end
		if ownerUser and ownerUser ~= "" and GlobalStorageSiK.Permissions.sameFaction(username, ownerUser) then
			return true
		end
	end
	return false, "denied"
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
	local net = registry.networks[networkId]
	if net.ownerCharacterId == characterId or net.characterPermissions[characterId] then
		return true, false, "already_member"
	end
	local record = bindCharacter(net, player, GlobalStorageSiK.Permissions.ROLE_MEMBER)
	consumeLegacyMembership(net, record.name, record.username)
	return true, true, "added"
end

function GlobalStorageSiK.Permissions.setCharacterRole(networkId, characterId, role)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = registry.networks and registry.networks[networkId]
	local record = net and net.characterPermissions and net.characterPermissions[characterId]
	if not record or characterId == net.ownerCharacterId then return false end
	if role ~= GlobalStorageSiK.Permissions.ROLE_ADMIN then
		role = GlobalStorageSiK.Permissions.ROLE_MEMBER
	end
	record.role = role
	return true
end

function GlobalStorageSiK.Permissions.removeCharacter(networkId, characterId)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = registry.networks and registry.networks[networkId]
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

--- Serializa permisos para el cliente.
---@param networkId string
---@return table
function GlobalStorageSiK.Permissions.serialize(networkId, requestingPlayer)
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId)
	local net = registry.networks[networkId]
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
			username = ownerRecord and ownerRecord.username or net.ownerAccount or "",
			role = GlobalStorageSiK.Permissions.ROLE_OWNER,
			source = "member",
			deniedZoneIds = {},
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
	local onlineCharacters = collectOnlineCharacterRecords(resolvedPlayer)
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
		if id ~= "" then
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
		GlobalStorageSiK.Log.info("Permissions", "permissionRoster",
			"network=" .. tostring(networkId)
				.. " members=" .. tostring(#memberEntries)
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
			and GlobalStorageSiK.Permissions.hasNetworkAdminRole(resolvedPlayer, networkId) or false,
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
	net.owner = targetName
	net.ownerAccount = targetUsername
	net.ownerSteamId = getSteamIdForUsername(targetUsername, nil)
	net.ownerCharacterId = targetId
	if target.record then
		target.record.characterName = targetName
		target.record.accountUsername = targetUsername
		target.record.name = targetName
		target.record.displayName = targetName
		target.record.username = targetUsername
		target.record.role = GlobalStorageSiK.Permissions.ROLE_OWNER
		net.characterPermissions[targetId] = target.record
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
	local net = registry.networks[networkId]
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
	local net = registry.networks[networkId]
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
---@param player IsoPlayer
---@param networkId string
---@return boolean
function GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = registry.networks and registry.networks[networkId]
	if not net then return false end
	if not net.owner or net.owner == "" then
		return player ~= nil and GlobalStorageSiK.Permissions.initializeOwner(net, player) or false
	end
	return bindOwnerIdentity(net, player)
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
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId)
	local list = registry.networks[networkId].allowedUsers
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
	local registry = GlobalStorageSiK.Network.getRegistry()
	local list = registry.networks[networkId] and registry.networks[networkId].allowedUsers
	if not list then
		return false
	end
	for i = #list, 1, -1 do
		if normalizeName(list[i]) == characterName then
			table.remove(list, i)
			local net = registry.networks[networkId]
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
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId)
	local list = registry.networks[networkId].allowedFactions
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
	local registry = GlobalStorageSiK.Network.getRegistry()
	local list = registry.networks[networkId] and registry.networks[networkId].allowedFactions
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
	local net = registry.networks and registry.networks[networkId]
	if not net then return 0 end
	local count = 0
	local seen = {}
	for characterId, record in pairs(net.characterPermissions or {}) do
		if isModernCharacterId(characterId) and characterId ~= net.ownerCharacterId and record then
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
		net.owner = promoted
		net.ownerCharacterId = promotedId or ""
		if promotedId and net.characterPermissions[promotedId] then
			net.characterPermissions[promotedId].role = GlobalStorageSiK.Permissions.ROLE_OWNER
		end
		-- Un registro persistente ya contiene la cuenta autoritativa exacta. Los
		-- fallbacks nominales solo pueden conservar el valor existente y quedan
		-- pendientes de vinculación; nunca se resuelven por un nombre ajeno.
		net.ownerAccount = promotedRecord and displayText(promotedRecord.username)
			or displayText(promoted)
		net.ownerSteamId = getSteamIdForUsername(net.ownerAccount)
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
		net.ownerAccount = nil
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
	local net = registry.networks and registry.networks[networkId]
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
	local net = registry.networks and registry.networks[networkId]
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

--- Sucesión de propiedad al morir un personaje: si era propietario de
--- alguna red, promociona automáticamente al primer admin disponible (o, si
--- no hay ningún admin, al primer miembro normal) para que la red nunca
--- quede con miembros pero sin dueño. Si era el único miembro, revierte al
--- mismo fallback que ya existía para una red recién creada (owner vacío =
--- cualquiera es owner). Debe llamarse solo en el proceso autoritativo
--- (servidor dedicado, host o SP real) - GS_Server.lua la engancha a
--- Events.OnPlayerDeath gateado por GlobalStorageSiK.isAuthoritative().
---@param deadPlayerOrName IsoPlayer|string
function GlobalStorageSiK.Permissions.handleOwnerDeath(deadPlayerOrName)
	local deadPlayer = type(deadPlayerOrName) == "string" and nil or deadPlayerOrName
	local deadCharacterName = deadPlayer and GlobalStorageSiK.Permissions.getCharacterName(deadPlayer)
		or displayText(deadPlayerOrName)
	local deadCharacterId = deadPlayer and GlobalStorageSiK.Permissions.getCharacterId(deadPlayer) or ""
	local deadCharacterKey = normalizeName(deadCharacterName)
	if deadCharacterKey == "" then
		return
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local networks = registry and registry.networks
	if not networks then
		return
	end
	for networkId, net in pairs(networks) do
		if deadPlayer then bindOwnerIdentity(net, deadPlayer) end
		local ownsById = deadCharacterId ~= "" and net.ownerCharacterId == deadCharacterId
		local ownsLegacy = (not net.ownerCharacterId or net.ownerCharacterId == "")
			and net.owner and net.owner ~= "" and normalizeName(net.owner) == deadCharacterKey
		if ownsById or ownsLegacy then
			promoteOrClearOwner(networkId, net, deadCharacterName, deadCharacterId)
		end
	end
	if ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
end

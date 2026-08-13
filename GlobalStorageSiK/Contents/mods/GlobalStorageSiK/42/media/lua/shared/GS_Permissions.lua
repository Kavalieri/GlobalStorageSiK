--[[
	GlobalStorageSiK - Permisos de acceso a la red (MP)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Permisos por nombre de personaje (forename + surname), no por cuenta.
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

--- Nombre visible del personaje (forename + surname).
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
				local full = normalizeName((desc:getForename() or "") .. " " .. (desc:getSurname() or ""))
				if full ~= "" then
					return full
				end
			end
		end
		if player.getForename and player.getSurname then
			local full = normalizeName((player:getForename() or "") .. " " .. (player:getSurname() or ""))
			if full ~= "" then
				return full
			end
		end
		if player.getForname and player.getSurname then
			local full = normalizeName((player:getForname() or "") .. " " .. (player:getSurname() or ""))
			if full ~= "" then
				return full
			end
		end
		return player:getUsername() or ""
	end)
	if ok and name and name ~= "" then
		return name
	end
	if player.getUsername then
		return player:getUsername() or ""
	end
	return ""
end

--- Comprueba si un valor almacenado coincide con el jugador (personaje o cuenta legacy).
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
	net.factionOnly = net.factionOnly == true
	if ownerCharacter and ownerCharacter ~= "" and (not net.owner or net.owner == "") then
		net.owner = ownerCharacter
	end
end

--- Indica si el jugador tiene rol admin o superior.
---@param player IsoPlayer
---@param networkId string
---@return boolean
function GlobalStorageSiK.Permissions.isAdminPlayer(player, networkId)
	if GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId) then
		return true
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = registry.networks and registry.networks[networkId]
	if not net then return false end
	local charName = GlobalStorageSiK.Permissions.getCharacterName(player)
	for i = 1, #(net.adminUsers or {}) do
		if normalizeName(net.adminUsers[i]) == normalizeName(charName) then
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
	characterName = normalizeName(characterName)
	if characterName == "" then return false end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId)
	local net = registry.networks[networkId]
	if net.owner and normalizeName(net.owner) == characterName then
		return false  -- no se puede cambiar el rol del owner
	end
	net.adminUsers = net.adminUsers or {}
	-- quitar de adminUsers primero
	for i = #net.adminUsers, 1, -1 do
		if normalizeName(net.adminUsers[i]) == characterName then
			table.remove(net.adminUsers, i)
		end
	end
	if role == GlobalStorageSiK.Permissions.ROLE_ADMIN then
		-- asegurarse de que está en allowedUsers
		local inUsers = false
		for i = 1, #net.allowedUsers do
			if normalizeName(net.allowedUsers[i]) == characterName then
				inUsers = true; break
			end
		end
		if not inUsers then
			net.allowedUsers[#net.allowedUsers + 1] = characterName
		end
		net.adminUsers[#net.adminUsers + 1] = characterName
	end
	return true
end

--- Registra cuenta del propietario al fijar propiedad.
---@param net table
---@param player IsoPlayer
local function touchOwnerAccount(net, player)
	if not net or not player or not player.getUsername then
		return
	end
	local charName = GlobalStorageSiK.Permissions.getCharacterName(player)
	if net.owner == charName or not net.owner or net.owner == "" then
		net.owner = charName
		net.ownerAccount = player:getUsername()
	end
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

--- Resuelve nombre de personaje desde cuenta (jugadores conectados).
---@param username string
---@return string
function GlobalStorageSiK.Permissions.resolveCharacterName(username)
	username = normalizeName(username)
	if username == "" then
		return ""
	end
	if getPlayerFromUsername then
		local ok, player = pcall(getPlayerFromUsername, username)
		if ok and player then
			return GlobalStorageSiK.Permissions.getCharacterName(player)
		end
	end
	if getActivePlayers then
		local ok, players = pcall(getActivePlayers)
		if ok and players and players.size then
			for i = 0, players:size() - 1 do
				local p = players:get(i)
				if p and p.getUsername and p:getUsername() == username then
					return GlobalStorageSiK.Permissions.getCharacterName(p)
				end
			end
		end
	end
	return username
end

--- Resuelve cuenta desde nombre de personaje (jugadores conectados).
---@param characterName string
---@return string|nil
function GlobalStorageSiK.Permissions.resolveUsernameFromCharacter(characterName)
	characterName = normalizeName(characterName)
	if characterName == "" then
		return nil
	end
	if getActivePlayers then
		local ok, players = pcall(getActivePlayers)
		if ok and players and players.size then
			for i = 0, players:size() - 1 do
				local p = players:get(i)
				if p and GlobalStorageSiK.Permissions.getCharacterName(p) == characterName then
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
	if player:isAccessLevel("admin") then
		return true
	end
	local characterName = GlobalStorageSiK.Permissions.getCharacterName(player)
	local username = player:getUsername()
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId, characterName)
	local net = registry.networks[networkId]
	if not net.owner or net.owner == "" then
		touchOwnerAccount(net, player)
		if ModData and ModData.transmit then
			ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		end
		return true
	end
	if GlobalStorageSiK.Permissions.identityMatches(player, net.owner) then
		touchOwnerAccount(net, player)
		return true
	end
	for i = 1, #(net.allowedUsers or {}) do
		if GlobalStorageSiK.Permissions.identityMatches(player, net.allowedUsers[i]) then
			return true
		end
	end
	local playerFaction = GlobalStorageSiK.Permissions.getPlayerFaction(player)
	if playerFaction and playerFaction.getName then
		local fname = playerFaction:getName()
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

--- Serializa permisos para el cliente.
---@param networkId string
---@return table
function GlobalStorageSiK.Permissions.serialize(networkId, requestingPlayer)
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId)
	local net = registry.networks[networkId]
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
	return {
		owner = net.owner or "",
		allowedUsers = net.allowedUsers or {},
		allowedFactions = net.allowedFactions or {},
		adminUsers = net.adminUsers or {},
		factionOnly = net.factionOnly == true,
		enforce = GlobalStorageSiK.Permissions.shouldEnforce(),
		playerFactionName = playerFactionName,
		playerRole = playerRole,
	}
end

--- Transfiere la propiedad a otro personaje.
---@param networkId string
---@param player IsoPlayer
---@param toCharacterName string
---@param keepFormerOwner boolean|nil
---@return boolean ok
---@return string message
function GlobalStorageSiK.Permissions.transferOwner(networkId, player, toCharacterName, keepFormerOwner)
	toCharacterName = normalizeName(toCharacterName)
	if toCharacterName == "" then
		return false, "Nombre de personaje vacío"
	end
	local fromCharacter = GlobalStorageSiK.Permissions.getCharacterName(player)
	if toCharacterName == fromCharacter then
		return false, "Ya eres el propietario"
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId)
	local net = registry.networks[networkId]
	if not net then
		return false, "Red no encontrada"
	end
	if not GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId) then
		return false, "Solo el propietario puede transferir la red"
	end
	local former = net.owner or fromCharacter
	net.owner = toCharacterName
	net.ownerAccount = GlobalStorageSiK.Permissions.resolveUsernameFromCharacter(toCharacterName)
	net.allowedUsers = net.allowedUsers or {}
	if keepFormerOwner and former and former ~= "" and former ~= toCharacterName then
		GlobalStorageSiK.Permissions.addUser(networkId, former)
	else
		for i = #net.allowedUsers, 1, -1 do
			if normalizeName(net.allowedUsers[i]) == toCharacterName then
				table.remove(net.allowedUsers, i)
			end
		end
	end
	return true, "Propiedad transferida a " .. toCharacterName
end

--- Indica si el jugador es propietario de la red.
---@param player IsoPlayer
---@param networkId string
---@return boolean
function GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = registry.networks and registry.networks[networkId]
	if not net or not net.owner or net.owner == "" then
		return true
	end
	return GlobalStorageSiK.Permissions.identityMatches(player, net.owner)
end

---@param networkId string
---@param characterName string
---@return boolean
function GlobalStorageSiK.Permissions.addUser(networkId, characterName)
	characterName = normalizeName(characterName)
	if characterName == "" then
		return false
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Permissions.ensure(registry, networkId)
	local list = registry.networks[networkId].allowedUsers
	for i = 1, #list do
		if normalizeName(list[i]) == characterName then
			return false
		end
	end
	table.insert(list, characterName)
	return true
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

--- Añade todos los miembros conectados de la facción del jugador (por personaje).
---@param networkId string
---@param player IsoPlayer
---@return boolean ok
---@return string message
function GlobalStorageSiK.Permissions.addAllFactionMembers(networkId, player)
	local faction = GlobalStorageSiK.Permissions.getPlayerFaction(player)
	if not faction then
		return false, "No perteneces a una facción"
	end
	local added = 0
	local seen = {}

	local function tryAddUsername(username)
		if not username or username == "" or seen[username] then
			return
		end
		seen[username] = true
		local charName = GlobalStorageSiK.Permissions.resolveCharacterName(username)
		if charName ~= "" and GlobalStorageSiK.Permissions.addUser(networkId, charName) then
			added = added + 1
		end
	end

	if faction.getPlayers then
		local ok, players = pcall(function()
			return faction:getPlayers()
		end)
		if ok and players then
			if players.size then
				for i = 0, players:size() - 1 do
					tryAddUsername(players:get(i))
				end
			elseif type(players) == "table" then
				for i = 1, #players do
					tryAddUsername(players[i])
				end
			end
		end
	end

	if added == 0 and getActivePlayers then
		local fname = faction.getName and faction:getName() or ""
		local ok, players = pcall(getActivePlayers)
		if ok and players and players.size and fname ~= "" then
			for i = 0, players:size() - 1 do
				local p = players:get(i)
				if p and p.getUsername then
					local uname = p:getUsername()
					if GlobalStorageSiK.Permissions.sameFaction(uname, player:getUsername()) then
						local charName = GlobalStorageSiK.Permissions.getCharacterName(p)
						if charName ~= "" and GlobalStorageSiK.Permissions.addUser(networkId, charName) then
							added = added + 1
						end
					end
				end
			end
		end
	end

	if added == 0 then
		return false, "No se añadió ningún miembro (¿nadie conectado?)"
	end
	return true, string.format("%d personajes añadidos", added)
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
	return #(net.allowedUsers or {})
end

--- Sucesión de propiedad al morir un personaje: si era propietario de
--- alguna red, promociona automáticamente al primer admin disponible (o, si
--- no hay ningún admin, al primer miembro normal) para que la red nunca
--- quede con miembros pero sin dueño. Si era el único miembro, revierte al
--- mismo fallback que ya existía para una red recién creada (owner vacío =
--- cualquiera es owner). Debe llamarse solo en el proceso autoritativo
--- (servidor dedicado, host o SP real) - GS_Server.lua la engancha a
--- Events.OnPlayerDeath gateado por GlobalStorageSiK.isAuthoritative().
---@param deadCharacterName string
function GlobalStorageSiK.Permissions.handleOwnerDeath(deadCharacterName)
	deadCharacterName = normalizeName(deadCharacterName)
	if deadCharacterName == "" then
		return
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local networks = registry and registry.networks
	if not networks then
		return
	end
	for networkId, net in pairs(networks) do
		if net.owner and net.owner ~= "" and normalizeName(net.owner) == deadCharacterName then
			local promoted = nil
			if net.adminUsers and #net.adminUsers > 0 then
				promoted = net.adminUsers[1]
			elseif net.allowedUsers and #net.allowedUsers > 0 then
				promoted = net.allowedUsers[1]
			end
			if promoted and promoted ~= "" then
				net.owner = promoted
				net.ownerAccount = GlobalStorageSiK.Permissions.resolveUsernameFromCharacter(promoted)
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
						networkId .. ": " .. deadCharacterName .. " -> " .. promoted)
				end
			else
				net.owner = ""
				net.ownerAccount = nil
				if GlobalStorageSiK.Log then
					GlobalStorageSiK.Log.info("Permissions", "ownerSuccession",
						networkId .. ": " .. deadCharacterName .. " -> (sin miembros, red sin dueño)")
				end
			end
		end
	end
	if ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
end

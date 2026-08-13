--[[
	GlobalStorageSiK - Registro de red
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Gestión del índice global de contenedores marcados.
]]

require "GS_Config"
require "GS_Utils"
require "GS_Zones"
require "GS_ZoneRefresh"

GlobalStorageSiK.Network = {}

local LEGACY_MAIN_ID = "main"

--- Inicializa la estructura si no existe.
---@param registry table
function GlobalStorageSiK.Network.ensureRegistry(registry)
	registry.networks = registry.networks or {}
	registry.zones = registry.zones or {}
	registry.nodes = registry.nodes or {}
	registry._nextNetworkSeq = registry._nextNetworkSeq or 0
	if registry.networks[LEGACY_MAIN_ID] and not registry.defaultNetworkId then
		registry.defaultNetworkId = LEGACY_MAIN_ID
	end
	for nid, net in pairs(registry.networks) do
		net.addonInstalls = net.addonInstalls or {}
		net.floppyDriveInstalls = net.floppyDriveInstalls or {}
		net.id = net.id or nid
		net.containers = net.containers or {}
		net.terminals = net.terminals or {}
	end
	-- isAuthoritative(), no isServer() a pelo: en SP real isServer() da false
	-- y las migraciones de esquema del registro nunca se aplicaban.
	if GlobalStorageSiK.isAuthoritative() and not registry._migrating then
		if not GlobalStorageSiK.NetworkMigrate then
			require "GS_NetworkMigrate"
		end
		if not registry._migrateV1060 and GlobalStorageSiK.NetworkMigrate.run then
			GlobalStorageSiK.NetworkMigrate.run(registry)
		end
		if not registry._migrateV1070 and GlobalStorageSiK.NetworkMigrate.runV1070 then
			GlobalStorageSiK.NetworkMigrate.runV1070(registry)
		end
		if not registry._migrateV1080 and GlobalStorageSiK.NetworkMigrate.runV1080 then
			GlobalStorageSiK.NetworkMigrate.runV1080(registry)
		end
	end
end

--- Resuelve alias legacy (p. ej. main → gsn_*) y comprueba que la red exista.
---@param networkId string|nil
---@return string|nil
function GlobalStorageSiK.Network.resolveNetworkId(networkId)
	if not networkId or networkId == "" then
		return nil
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	if registry._legacyNetworkAliases and registry._legacyNetworkAliases[networkId] then
		networkId = registry._legacyNetworkAliases[networkId]
	end
	if registry.networks and registry.networks[networkId] then
		return networkId
	end
	return nil
end

--- ID legacy para partidas antiguas (no usar en terminales nuevos).
---@return string|nil
function GlobalStorageSiK.Network.getDefaultNetworkId()
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	if registry.defaultNetworkId and registry.networks[registry.defaultNetworkId] then
		return registry.defaultNetworkId
	end
	if registry._legacyNetworkAliases and registry._legacyNetworkAliases[LEGACY_MAIN_ID] then
		local migrated = registry._legacyNetworkAliases[LEGACY_MAIN_ID]
		if registry.networks[migrated] then
			return migrated
		end
	end
	if registry.networks[LEGACY_MAIN_ID] then
		return LEGACY_MAIN_ID
	end
	for nid, _ in pairs(registry.networks) do
		return nid
	end
	return nil
end

--- Indica si la red exige que los contenedores esten cerca de un terminal
--- para poder ser detectados por un escaneo de zona. Por red, sobreescribe
--- el sandbox global (GlobalStorageSiK.Sandbox.requireContainerRange()) si
--- el admin de esa red concreta lo ha activado/desactivado desde la pestaña Red.
---@param networkId string|nil
---@return boolean
function GlobalStorageSiK.Network.containerRangeEnabled(networkId)
	if not GlobalStorageSiK.Sandbox then
		require "GS_Sandbox"
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = networkId and registry.networks and registry.networks[networkId]
	if net and net.requireContainerRange ~= nil then
		return net.requireContainerRange == true
	end
	return GlobalStorageSiK.Sandbox.requireContainerRange()
end

--- Distancia (en baldosas, métrica Chebyshev — igual que el resto de rangos
--- del mod) desde un punto hasta el terminal ACTIVO más cercano de una red.
--- nil si la red no tiene ningún terminal activo (no se puede medir distancia).
---@param networkId string
---@param x number
---@param y number
---@param z number|nil
---@return number|nil
function GlobalStorageSiK.Network.nearestTerminalDistance(networkId, x, y, z)
	if not networkId or x == nil or y == nil then
		return nil
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local net = registry.networks and registry.networks[networkId]
	if not net then
		return nil
	end
	if not GlobalStorageSiK.TerminalRecord then
		require "GS_TerminalRecord"
	end
	local best = nil
	local function consider(tx, ty)
		if tx == nil or ty == nil then
			return
		end
		local d = math.max(math.abs(x - tx), math.abs(y - ty))
		if not best or d < best then
			best = d
		end
	end
	if net.terminals then
		for i = 1, #net.terminals do
			local t = net.terminals[i]
			if t and GlobalStorageSiK.TerminalRecord.isActive(t) then
				consider(t.x, t.y)
			end
		end
	end
	if net.controller then
		consider(net.controller.x, net.controller.y)
	end
	return best
end

--- Busca la red que contiene un terminal en coordenadas exactas.
---@param x number
---@param y number
---@param z number
---@param opts table|nil { activeOnly = boolean }
---@return string|nil networkId
function GlobalStorageSiK.Network.findNetworkIdAtTerminal(x, y, z, opts)
	if x == nil or y == nil or z == nil then
		return nil
	end
	opts = opts or {}
	local activeOnly = opts.activeOnly == true
	if not GlobalStorageSiK.TerminalRecord then
		require "GS_TerminalRecord"
	end
	local fx = math.floor(x)
	local fy = math.floor(y)
	local fz = math.floor(z)
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	for nid, net in pairs(registry.networks) do
		if net.terminals then
			for i = 1, #net.terminals do
				local t = net.terminals[i]
				if t and math.floor(t.x) == fx and math.floor(t.y) == fy and math.floor(t.z or 0) == fz then
					if activeOnly and not GlobalStorageSiK.TerminalRecord.isActive(t) then
						-- omitir suspendidos para vinculación / acceso
					else
						return nid
					end
				end
			end
		end
		local c = net.controller
		if c and math.floor(c.x) == fx and math.floor(c.y) == fy and math.floor(c.z or 0) == fz then
			if not activeOnly then
				return nid
			end
			local entry = GlobalStorageSiK.TerminalRecord.findAt(net, fx, fy, fz)
			if entry and GlobalStorageSiK.TerminalRecord.isActive(entry) then
				return nid
			end
		end
	end
	return nil
end

--- Crea una red nueva con ID único al colocar un terminal.
---@param player IsoPlayer|nil
---@return string|nil networkId
function GlobalStorageSiK.Network.createNetwork(player)
	if not GlobalStorageSiK.NetworkId then
		require "GS_NetworkId"
	end
	if not GlobalStorageSiK.Permissions then
		require "GS_Permissions"
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local id = GlobalStorageSiK.NetworkId.generate(registry)
	local owner = player and GlobalStorageSiK.Permissions.getCharacterName(player) or ""
	local ownerAccount = player and player.getUsername and player:getUsername() or ""
	local suffix = string.sub(id, -6)
	registry.networks[id] = {
		id = id,
		name = "Red " .. suffix,
		owner = owner,
		ownerAccount = ownerAccount,
		terminals = {},
		containers = {},
		addonInstalls = {},
		createdMs = (getTimestampMs and getTimestampMs()) or 0,
	}
	GlobalStorageSiK.Permissions.ensure(registry, id, owner)
	if ModData and ModData.transmit then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	if GlobalStorageSiK.RegistryStore and GlobalStorageSiK.RegistryStore.notifyChanged then
		GlobalStorageSiK.RegistryStore.notifyChanged()
	end
	return id
end

--- Resuelve networkId para comandos del cliente (sesión, args, terminal cercano).
---@param player IsoPlayer|nil
---@param args table|nil
---@param command string|nil
---@return string|nil
function GlobalStorageSiK.Network.resolveCommandNetworkId(player, args, command)
	if not GlobalStorageSiK.NetworkResolve then
		require "GS_NetworkResolve"
	end
	if GlobalStorageSiK.NetworkResolve.isSessionExempt(command) then
		return nil
	end
	return GlobalStorageSiK.NetworkResolve.resolveCommandNetworkId(player, args)
end

--- Obtiene la tabla global de redes (solo servidor en MP).
---@return table
function GlobalStorageSiK.Network.getRegistry()
	return ModData.getOrCreate(GlobalStorageSiK.MODDATA_KEY)
end

--- Nombre visible de la red (no cambia el id interno).
---@param networkId string|nil
---@return string
function GlobalStorageSiK.Network.getDisplayName(networkId)
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local nid = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	local net = registry.networks[nid]
	if net and net.name and net.name ~= "" then
		return net.name
	end
	return nid
end

--- Renombra la red visible (solo propietario; id interno fijo).
---@param networkId string
---@param ownerUsername string
---@param newName string
---@return boolean ok
---@return string message
function GlobalStorageSiK.Network.renameDisplayName(networkId, ownerUsername, newName)
	newName = newName and string.gsub(newName, "^%s*(.-)%s*$", "%1") or ""
	if #newName < 2 or #newName > 32 then
		return false, "Nombre entre 2 y 32 caracteres"
	end
	if not newName:match("^[%w%s%-%_%.]+$") then
		return false, "Caracteres no validos en el nombre"
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local net = registry.networks[networkId]
	if not net then
		return false, "Red no encontrada"
	end
	-- La comprobacion de propietario ya la hace el llamador (GS_Server.lua,
	-- via Permissions.isOwnerPlayer) ANTES de invocar esta funcion. Los
	-- permisos de esta red van por NOMBRE DE PERSONAJE (net.owner), no por
	-- nombre de cuenta — comparar aqui contra un username de cuenta (como se
	-- hacia antes) rechazaba siempre al propio propietario cuando su cuenta y
	-- su personaje no se llaman igual.
	net.name = newName
	if ModData and ModData.transmit then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	return true, newName
end

--- Busca un contenedor en el mundo por coordenadas.
---@param entry table
---@return IsoObject|nil
function GlobalStorageSiK.Network.findWorldObject(entry)
	if not entry then
		return nil
	end

	local square = nil
	local cell = getCell and getCell() or nil
	if cell then
		square = cell:getGridSquare(entry.x, entry.y, entry.z)
	end
	if not square and getWorld then
		local world = getWorld()
		if world and world.getCell then
			local worldCell = world:getCell()
			if worldCell then
				square = worldCell:getGridSquare(entry.x, entry.y, entry.z)
			end
		end
	end
	if not square then
		return nil
	end

	for i = 0, square:getObjects():size() - 1 do
		local obj = square:getObjects():get(i)
		if GlobalStorageSiK.Utils.getContainerId(obj, entry.containerIndex) == entry.id then
			return obj
		end
	end

	return nil
end

--- Devuelve contenedores vivos de la red (nodos de zona o legacy).
---@param networkId string|nil
---@return table
--- Diagnostico opcional (DebugMode): por que un nodo concreto no resolvio a
--- contenedor "vivo" - reportado un caso real donde Craft/Build veian 0
--- contenedores con la zona visiblemente cargada para el jugador (el
--- Almacen SI los mostraba, via snapshot persistido, sin pasar por esta
--- resolucion). Sin esto no habia forma de saber si fallaba la cuadricula
--- (getGridSquare nil), el objeto (no encontrado en la cuadricula) o el
--- contenedor (indice invalido) - los tres dan el mismo resultado final
--- (0 contenedores) pero apuntan a causas muy distintas.
---@param nid string
---@param entry table
---@param obj table|nil
---@param container table|nil
local function logLiveContainerMiss(nid, entry, obj, container)
	if not (GlobalStorageSiK.Sandbox and GlobalStorageSiK.Sandbox.debugMode and GlobalStorageSiK.Sandbox.debugMode()) then
		return
	end
	if container then
		return
	end
	local cell = getCell and getCell() or nil
	local square = cell and entry.x and cell:getGridSquare(entry.x, entry.y, entry.z)
	local reason
	if not square then
		reason = "square_not_loaded"
	elseif not obj then
		reason = "object_not_found_in_square"
	else
		reason = "container_index_invalid"
	end
	local line = string.format(
		"getLiveContainers MISS nid=%s id=%s pos=%s,%s,%s containerIndex=%s reason=%s",
		tostring(nid), tostring(entry.id), tostring(entry.x), tostring(entry.y), tostring(entry.z),
		tostring(entry.containerIndex), reason)
	if GlobalStorageSiK.Debug and GlobalStorageSiK.Debug.log then
		GlobalStorageSiK.Debug.log("Network", "getLiveContainers", line)
	else
		print("[GlobalStorageSiK] " .. line)
	end
end

function GlobalStorageSiK.Network.getLiveContainers(networkId)
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local live = {}
	local nid = networkId
	if not nid then
		nid = GlobalStorageSiK.Network.getDefaultNetworkId()
	end
	if not nid then
		return live
	end

	if GlobalStorageSiK.ZoneRefresh and GlobalStorageSiK.ZoneRefresh.getActiveNodes then
		local nodes = GlobalStorageSiK.ZoneRefresh.getActiveNodes(nid)
		-- BUG REAL encontrado (reportado: "0 contenedores" sin NINGUNA linea
		-- de diagnostico, ni siquiera un MISS): si nodes esta vacio, el bucle
		-- de abajo no itera nada, asi que logLiveContainerMiss nunca se
		-- llamaba - el problema real (registro LOCAL vacio, sin importar lo
		-- que diga terminalState del servidor) quedaba completamente mudo.
		-- Esta linea deja constancia SIEMPRE del tamaño de ambas fuentes
		-- (nodos activos y contenedores de red en el registro local), se
		-- resuelva o no despues algun contenedor.
		if GlobalStorageSiK.Sandbox and GlobalStorageSiK.Sandbox.debugMode and GlobalStorageSiK.Sandbox.debugMode() then
			local netContainersCount = registry.networks[nid] and registry.networks[nid].containers and #registry.networks[nid].containers or 0
			local line = string.format(
				"getLiveContainers SOURCES nid=%s activeNodes=%d networkContainers=%d",
				tostring(nid), #nodes, netContainersCount)
			if GlobalStorageSiK.Debug and GlobalStorageSiK.Debug.log then
				GlobalStorageSiK.Debug.log("Network", "getLiveContainers", line)
			else
				print("[GlobalStorageSiK] " .. line)
			end
		end
		for _, node in ipairs(nodes) do
			local obj = GlobalStorageSiK.Network.findWorldObject(node)
			local container = GlobalStorageSiK.Utils.getObjectContainer(obj, node.containerIndex)
			if container then
				table.insert(live, {
					entry = node,
					object = obj,
					container = container,
				})
			else
				logLiveContainerMiss(nid, node, obj, container)
			end
		end
		if #live > 0 then
			return live
		end
	end

	-- BUG REAL confirmado (dedicado, log 2026-08-12): en cliente MP puro,
	-- ZoneRefresh.getActiveNodes()/registry.networks[nid].containers leen el
	-- ModData "GlobalStorageSiK_Network" local, que puede no sincronizarse
	-- nunca via ModData.transmit en ese cliente (activeNodes=0 siempre,
	-- aunque el servidor vea 9) - de ahi "0 contenedores" en Craft/Build al
	-- abrir, pese a que el terminal SI mostraba los 32 items un momento
	-- antes (ese dato llega por el canal de comandos terminalState, que SI
	-- es fiable). Respaldo: en cliente no autoritativo, si lo anterior no
	-- resolvio nada, se reintenta con los nodos del ultimo terminalState
	-- cacheado para esta red (misma resolucion IsoObject, solo cambia de
	-- donde sale la lista de candidatos).
	if not GlobalStorageSiK.isAuthoritative() and #live == 0 then
		local cached = GlobalStorageSiK.Client and GlobalStorageSiK.Client.cachedTerminalState
		if cached and cached.networkId == nid and cached.nodes then
			for _, node in ipairs(cached.nodes) do
				local obj = GlobalStorageSiK.Network.findWorldObject(node)
				local container = GlobalStorageSiK.Utils.getObjectContainer(obj, node.containerIndex)
				if container then
					table.insert(live, {
						entry = node,
						object = obj,
						container = container,
					})
				else
					logLiveContainerMiss(nid, node, obj, container)
				end
			end
			if #live > 0 then
				return live
			end
		end
	end

	local network = registry.networks[nid]
	if not network or not network.containers then
		return live
	end

	for _, entry in ipairs(network.containers) do
		local obj = GlobalStorageSiK.Network.findWorldObject(entry)
		local container = GlobalStorageSiK.Utils.getObjectContainer(obj, entry.containerIndex)
		if container then
			table.insert(live, {
				entry = entry,
				object = obj,
				container = container,
			})
		else
			logLiveContainerMiss(nid, entry, obj, container)
		end
	end

	return live
end

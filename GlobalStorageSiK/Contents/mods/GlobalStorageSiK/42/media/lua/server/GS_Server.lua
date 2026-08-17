--[[

	GlobalStorageSiK - Lógica servidor (fase 1)

	Autor: SiK

	Fecha: 2025-06-23

	Descripción: Zonas, terminal, bulk, extracción, reescaneo.

]]



require "GS_Config"

require "GS_I18n"

require "GS_Utils"

require "GS_Sandbox"

require "GS_Zones"

require "GS_ZoneScanner"

require "GS_ZoneRefresh"

require "GS_Network"

require "GS_Index"

require "GS_NetworkCapacity"

require "GS_Power"

require "GS_Transfer"
require "GS_InventorySync"

require "GS_TransferLock"

require "GS_Redistribute"
require "GS_RedistributeJob"
require "GS_ZoneScanJob"

require "GS_Bulk"

require "GS_Deposit"

require "GS_Categories"
require "GS_CraftCatalog"

require "GS_Permissions"

require "GS_TerminalAccess"

require "GS_TerminalManifest"

require "GS_TerminalRegistry"
require "GS_TerminalRecovery"
require "GS_TerminalPlace"
require "GS_TerminalPlacementIntent"
require "GS_TerminalRecord"
require "GS_NetworkResolve"
require "GS_NetworkManager"

require "GS_NodeNaming"

require "GS_TerminalRecipes"
require "GS_CraftUtils"
require "GS_PCAcquire"
require "GS_ReaderAcquire"
require "GS_DiskProgramming"
require "GS_AddonRecipes"

require "GS_ItemSnapshot"

require "GS_FuelConsumption"

require "GS_Log"

require "GS_Debug"

require "GS_NetTrace"

GlobalStorageSiK.Server = GlobalStorageSiK.Server or {}

--- En SP real (no anfitrion), isClient()/isServer() son ambos false - cliente
--- y "servidor" comparten el mismo proceso y el mismo tick.
---@return boolean
local function isTrueSingleplayer()
	return not (isClient and isClient()) and not (isServer and isServer())
end

--- BUG REAL confirmado con traza de red completa en los dos entornos
--- (v1.2.113-115): en SP real, sendServerCommand() devuelve exito (pcall
--- ok=true, sin excepcion) pero Events.OnServerCommand del lado cliente
--- JAMAS se dispara - confirmado con un print incondicional (sin pasar por
--- nuestro propio sistema de trazas) que no aparecio ni una sola vez para
--- NINGUN comando, ni siquiera debugEcho. En un dedicado real, cada envio SI
--- llega, siempre, confirmado linea a linea. No es un problema de timing
--- (diferir el envio un tick, probado antes, no cambio nada) - el canal de
--- red en si no entrega en SP real, el mismo motivo de fondo que el crash
--- de getAccessLevel() en SiKCorpseLootGuard (GameClient.connection es null
--- en SP real, y las APIs de red vanilla que dependen de esa conexion no
--- funcionan ahi, con excepcion o en silencio segun la API).
--- Solucion: en SP real NO usar sendServerCommand en absoluto - llamar
--- directamente, en el mismo proceso, a la funcion que GS_Client.lua
--- expone para esto (GlobalStorageSiK.Client.dispatchServerCommand, el
--- mismo onServerCommand que Events.OnServerCommand llamaria si el canal
--- de red funcionara). Cliente y servidor comparten la misma tabla global
--- en SP real, asi que esto es una llamada normal a funcion, no una
--- reimplementacion de nada.

--- El reenvio de diagnostico ya no vive en este dispatcher. GS_DebugRelay
--- conserva el origen, agrupa lineas y limita trafico sin referencias Java
--- persistentes; los addons publican en la misma API neutral.
-- characterId/username -> networkId de la terminal que ese cliente tiene realmente
-- abierta. Los permisos de red NO equivalen a estar mirando la terminal:
-- enviar el indice completo a todos los miembros tras cada lote de deposito
-- multiplicaba el trafico por el numero de jugadores conectados.
local terminalWatchNetworkByPlayer = {}
local pendingTerminalRefreshes = {}
local flushPendingTerminalRefreshes

-- networkId -> { dueMs, forceMs, username }. Tras una transferencia no se
-- reconstruye el snapshot en un único tick: al vencer esta cola se inicia el
-- mismo escaneo incremental y presupuestado usado al abrir el terminal.
local pendingSnapshotSync = {}
local SNAPSHOT_QUIET_MS = 2000
local SNAPSHOT_FORCE_MS = 10000

local function scheduleSnapshotSync(networkId, player, revision)
	if not networkId then
		return
	end
	local now = getTimestampMs and getTimestampMs() or 0
	local pending = pendingSnapshotSync[networkId]
	if pending then
		pending.dueMs = now + SNAPSHOT_QUIET_MS
		-- Una transferencia incremental activa no debe disparar una captura
		-- completa a mitad del trabajo. El limite vuelve a contar desde el ultimo
		-- bloque confirmado; cuando cesa la actividad, dueMs la ejecuta en 2 s.
		pending.forceMs = now + SNAPSHOT_FORCE_MS
		pending.revision = math.max(pending.revision or 0, revision or 0)
		if player and player.getUsername then pending.username = player:getUsername() end
	else
		pendingSnapshotSync[networkId] = {
			dueMs = now + SNAPSHOT_QUIET_MS,
			forceMs = now + SNAPSHOT_FORCE_MS,
			revision = revision or 0,
			username = player and player.getUsername and player:getUsername() or nil,
		}
	end
end

local function flushPendingSnapshotSync()
	local now = getTimestampMs and getTimestampMs() or 0
	local selectedId = nil
	for networkId, pending in pairs(pendingSnapshotSync) do
		if now >= pending.dueMs or now >= pending.forceMs then
			selectedId = networkId
			break
		end
	end
	if not selectedId then
		return
	end
	local pending = pendingSnapshotSync[selectedId]
	if GlobalStorageSiK.ZoneScanJob.isActive(selectedId) then
		pending.dueMs = now + 500
		return
	end
	local player = GlobalStorageSiK.PlayerUtils.resolveByUsername(pending.username)
	if not player then
		-- No conservar para siempre un trabajo sin consumidor. La próxima
		-- apertura de la red ya inicia su propio scan incremental fresco.
		pendingSnapshotSync[selectedId] = nil
		GlobalStorageSiK.Log.detail("Server", "snapshotSync cancelled no_player network="
			.. tostring(selectedId))
		return
	end
	local started, reason = GlobalStorageSiK.ZoneScanJob.start(player, selectedId, {
		background = true,
	})
	if started then
		-- Quitar fuera del recorrido. Si otra transferencia ocurre durante el
		-- job, scheduleSnapshotSync creará una nueva pasada posterior.
		pendingSnapshotSync[selectedId] = nil
	elseif reason == "active" or reason == "redistribute_active" then
		pending.dueMs = now + 500
	else
		pending.dueMs = now + 1000
		GlobalStorageSiK.Log.warn("Server", "snapshotSync deferred network="
			.. tostring(selectedId) .. " reason=" .. tostring(reason))
	end
end

--- Marca una red como modificada sin difundir el Global ModData completo.
--- Expuesto solo para jobs server (p. ej. auto-ordenar), no es API de addons.
---@param networkId string|nil
function GlobalStorageSiK.Server.markInventoryDirty(networkId, player)
	if not networkId then
		return
	end
	local ok, revision = pcall(GlobalStorageSiK.Index.bumpInventoryRevision, networkId, false)
	if not ok then
		GlobalStorageSiK.Log.error("Server", "inventoryRevision", tostring(revision))
		revision = 0
	end
	scheduleSnapshotSync(networkId, player, revision)
end

local function terminalWatcherKey(player)
	if not player then
		return nil
	end
	local characterId = GlobalStorageSiK.Permissions.getCharacterId(player)
	if characterId and characterId ~= "" then
		return "character:" .. characterId
	end
	local ok, username = pcall(function() return player:getUsername() end)
	if ok and username and username ~= "" then
		return "account:" .. tostring(username)
	end
	return nil
end

local function setTerminalWatcher(player, networkId)
	local key = terminalWatcherKey(player)
	if key and networkId then
		terminalWatchNetworkByPlayer[key] = networkId
	end
end

local function clearTerminalWatcher(player)
	local key = terminalWatcherKey(player)
	if key then
		terminalWatchNetworkByPlayer[key] = nil
		pendingTerminalRefreshes[key] = nil
	end
end

local function isTerminalWatcher(player, networkId)
	local key = terminalWatcherKey(player)
	return key ~= nil and networkId ~= nil
		and terminalWatchNetworkByPlayer[key] == networkId
end

local function queueTerminalRefresh(player, networkId, searchQuery, fullState)
	local key = terminalWatcherKey(player)
	if not key or not networkId then
		return false
	end
	local existing = pendingTerminalRefreshes[key]
	pendingTerminalRefreshes[key] = {
		player = player,
		networkId = networkId,
		searchQuery = searchQuery or "",
		-- Un estado completo pendiente nunca se degrada a sync de inventario.
		fullState = fullState == true or (existing and existing.fullState == true),
	}
	return true
end

--- playerNum -> ultimo operationId de crafteo/construccion conocido para ese
--- jugador (ver craftAttemptStart/craftClaimItem mas abajo) - permite que
--- installCraftDiagnostics() (performRecipe, que NO tiene forma de llevar
--- nuestro operationId propio a traves de la accion nativa) correlacione su
--- resultado con el intento concreto que lo causo, sin inventar un sistema
--- de paso de datos custom a traves de ISHandcraftAction.
local lastOperationByPlayer = {}

--- playerNum -> ultimo networkId conocido para el intento de crafteo en
--- curso - mismo motivo que lastOperationByPlayer, para poder loguear el
--- total de items en red DESPUES del crafteo (diagnostico de dupeo,
--- 2026-08-16) sin tener que llevar el networkId a traves de la accion
--- nativa de PZ.
local lastNetworkIdByPlayer = {}

--- Envía comando al cliente con traza debug opcional.
---@param player IsoPlayer|nil
---@param command string
---@param payload table|nil
local function gsSendServerCommand(player, command, payload)
	if GlobalStorageSiK.NetTrace and GlobalStorageSiK.NetTrace.logServerSend then
		GlobalStorageSiK.NetTrace.logServerSend(player, command, payload)
	end
	if isTrueSingleplayer() then
		if GlobalStorageSiK.Client and GlobalStorageSiK.Client.dispatchServerCommand then
			local ok, err = pcall(GlobalStorageSiK.Client.dispatchServerCommand, GlobalStorageSiK.MOD_ID, command, payload)
			if not ok and GlobalStorageSiK.Sandbox.debugMode() then
				GlobalStorageSiK.Log.debug("Server", "dispatchServerCommand (SP directo) fallo: " .. tostring(err))
			end
		end
		return
	end
	sendServerCommand(player, GlobalStorageSiK.MOD_ID, command, payload)
end



local function getDefaultNetworkId()

	return GlobalStorageSiK.Network.getDefaultNetworkId()

end



--- Cuenta tipos en snapshot de nodo.
---@param snapshot table|nil
---@return number
local function countSnapshotTypes(snapshot)
	local n = 0
	for _ in pairs(snapshot or {}) do
		n = n + 1
	end
	return n
end



--- Serializa nodos activos para el cliente.

---@param networkId string

---@return table

local function serializeNodes(networkId, player)
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local list = {}

	for _, n in pairs(registry.nodes or {}) do
		local zone = registry.zones and registry.zones[n.zoneId]
		if zone and zone.networkId == networkId
			and (not player or GlobalStorageSiK.Permissions.canAccessZone(player, networkId, n.zoneId)) then
			table.insert(list, {
				id = n.id,
				displayName = n.displayName or n.name,
				name = n.name,
				vanillaName = n.name,
				zoneId = n.zoneId,
				zoneName = zone.name,
				zonePriority = tonumber(zone.priority) or 50,
				categories = n.categories or {},
				filters = n.filters or {},
				membership = n.membership or "auto",
				offline = n.offline == true,
				enabled = n.enabled ~= false,
				priority = n.priority or 50,
				itemTypeCount = countSnapshotTypes(n.itemSnapshot),
				x = n.x,
				y = n.y,
				z = n.z,
				containerIndex = n.containerIndex,
			})
		end
	end

	table.sort(list, function(a, b)
		return (a.displayName or a.name or "") < (b.displayName or b.name or "")
	end)

	return list
end



--- Serializa zonas para el cliente.

---@param networkId string

---@return table

local function serializeZones(networkId)

	local registry = GlobalStorageSiK.Zones.getRegistry()

	local list = {}

	for _, zone in pairs(registry.zones or {}) do

		if zone.networkId == networkId then
			local nodeCount = 0
			for _, node in pairs(registry.nodes or {}) do
				if node.zoneId == zone.id then
					nodeCount = nodeCount + 1
				end
			end

			table.insert(list, {

				id = zone.id,

				name = zone.name,

				source = zone.source,

				enabled = zone.enabled ~= false,

				priority = zone.priority,

				nodeCount = nodeCount,

				neverLoaded = zone.everScanLoaded ~= true,

			})

		end

	end

	require "GS_ZonePriority"
	GlobalStorageSiK.ZonePriority.ensurePriorities(registry, networkId)
	GlobalStorageSiK.ZonePriority.sortSerialized(list)

	return list

end



--- Serializa terminales registrados con estado físico presente/ausente/sin verificar.
---@param networkId string
---@return table[]
local function serializeTerminals(networkId)
	if not networkId or not GlobalStorageSiK.Network then
		return {}
	end
	if GlobalStorageSiK.TerminalCatalog and GlobalStorageSiK.TerminalCatalog.serializeRows then
		return GlobalStorageSiK.TerminalCatalog.serializeRows(networkId)
	end
	return {}
end



--- Construye estado completo del terminal.

---@param networkId string

---@param scanSummary table|nil

---@param searchQuery string|nil
---@param craftProbe table|nil
---@return table
local function buildTerminalState(networkId, scanSummary, searchQuery, craftProbe, player)

	local freshSnapshotScope = scanSummary and scanSummary._freshSnapshotScope or nil
	local rows = GlobalStorageSiK.Index.buildRows(networkId, player, freshSnapshotScope)
	-- Los campos con prefijo "_" coordinan servidor/indice y no forman parte
	-- del contrato MP. No mutar scanSummary: el mismo resultado se reutiliza
	-- para todos los observadores de la red al completar un job incremental.
	local scanPayload = {}
	for key, value in pairs(scanSummary or {}) do
		if string.sub(tostring(key), 1, 1) ~= "_" then scanPayload[key] = value end
	end

	if GlobalStorageSiK.Sandbox.debugMode() then
		for i = 1, #rows do
			local row = rows[i]
			if row.category == "food" or row.category == "Food" then
				GlobalStorageSiK.Log.debug("Server", "buildTerminalState | PRE-SEND fullType=" .. tostring(row.fullType)
					.. " gsSubKeysStr=" .. tostring(row.gsSubKeysStr) .. " (type=" .. type(row.gsSubKeysStr) .. ")"
					.. " gsSubKeys=" .. tostring(row.gsSubKeys) .. " nodeId=" .. tostring(row.nodeId))
			end
		end
	end

	-- El filtrado por búsqueda se aplica en el cliente (idioma del jugador).

	local nodesList = serializeNodes(networkId, player)

	return {

		networkId = networkId,

		networkName = GlobalStorageSiK.Network.getDisplayName(networkId),

		powered = GlobalStorageSiK.Power.networkPowered(networkId),

		fuelConsumption = GlobalStorageSiK.Power.serializeConsumption(#nodesList),

		scan = scanPayload,

		scanActive = GlobalStorageSiK.ZoneScanJob.isActive(networkId),

		zones = serializeZones(networkId),

		terminals = serializeTerminals(networkId),

		nodes = nodesList,

		itemTypeCount = #rows,

		items = rows,

		searchQuery = searchQuery or "",

		categories = GlobalStorageSiK.Categories.serialize(networkId),

		permissions = GlobalStorageSiK.Permissions.serialize(networkId, player),

		redistributeActive = GlobalStorageSiK.RedistributeJob.isActive(networkId),

		craftProbe = craftProbe,

		capacity = GlobalStorageSiK.NetworkCapacity.serialize(
			GlobalStorageSiK.NetworkCapacity.compute(networkId)
		),

		proximityRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange(),

		wirelessRange = GlobalStorageSiK.Sandbox.getWirelessRange(),


		inventoryRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId),
		snapshotRevision = GlobalStorageSiK.Index.getSnapshotRevision(networkId),

	}
end



--- Intenta obtener bounds de la habitación actual del jugador.

---@param player IsoPlayer

---@return table|nil

local function boundsFromPlayerRoom(player)

	local square = player:getSquare()

	if not square then

		return nil

	end



	local room = square:getRoom()

	if room and room.getRoomDef then

		local def = room:getRoomDef()

		if def then

			return {

				x1 = def:getX(),

				y1 = def:getY(),

				x2 = def:getX2(),

				y2 = def:getY2(),

				z = square:getZ(),

				zMax = square:getZ(),

			}

		end

	end



	local px, py, pz = square:getX(), square:getY(), square:getZ()

	return {

		x1 = px - 8,

		y1 = py - 8,

		x2 = px + 8,

		y2 = py + 8,

		z = pz,

		zMax = pz,

	}

end



--- Registra posición del controlador (jugador al abrir terminal).

---@param player IsoPlayer

---@param networkId string

local function touchController(player, networkId)

	local registry = GlobalStorageSiK.Network.getRegistry()

	GlobalStorageSiK.Network.ensureRegistry(registry)

	local network = registry.networks[networkId]

	if not network then

		return

	end

	local sq = player:getSquare()

	if sq then

		network.controller = {

			x = sq:getX(),

			y = sq:getY(),

			z = sq:getZ(),

		}

	end

end



--- Registra posición del controlador en coordenadas del terminal.

---@param networkId string

---@param x number

---@param y number

---@param z number

--- No mueve la ancla en acceso (solo registro explícito al colocar).
---@param networkId string
---@param x number
---@param y number
---@param z number
---@param player IsoPlayer|nil
---@return string|nil
local function touchControllerAt(networkId, x, y, z, player)
	return networkId
end

--- Registra posición del terminal al colocar (no en ping/apertura).
---@param networkId string|nil
---@param x number
---@param y number
---@param z number
---@param player IsoPlayer|nil
---@param placementMode string|nil
---@return string|nil
---@return string|nil
local function registerTerminalAt(networkId, x, y, z, player, placementMode)
	if GlobalStorageSiK.TerminalRegistry and GlobalStorageSiK.TerminalRegistry.register then
		local nid, err = GlobalStorageSiK.TerminalRegistry.register(networkId, x, y, z, player, {
			createIfMissing = true,
			placementMode = placementMode or "auto",
		})
		return nid or networkId, err
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local network = networkId and registry.networks[networkId]
	if network then
		network.controller = { x = x, y = y, z = z }
	end
	return networkId
end

--- Quita la identidad GS de cualquier objeto terminal encontrado en una
--- baldosa (usado por removeTerminal, uninstallTerminalReader y la baja
--- automatica al abrir con el ordenador ausente). Un unico punto para esta
--- limpieza evita que se repita el error de olvidar un campo de ModData
--- en alguno de los sitios que la necesitan.
---@param x number
---@param y number
---@param z number
local function clearTerminalObjectsAt(x, y, z)
	local cell = getCell and getCell() or nil
	if not cell then
		return
	end
	local sq = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z))
	if not sq or not sq.getObjects then
		return
	end
	local objs = sq:getObjects()
	for i = 0, objs:size() - 1 do
		local obj = objs:get(i)
		if obj and GlobalStorageSiK.TerminalAccess.isTerminalObject(obj) then
			GlobalStorageSiK.TerminalAccess.unregisterComputerAsTerminal(obj)
		end
	end
end

--- Aplica hints de acceso (cliente + escaneo servidor) antes de evaluar distancia.
---@param player IsoPlayer
---@param args table|nil
local function applyAccessHints(player, args)
	args = args or {}
	local proxRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	if args.terminalHint and GlobalStorageSiK.TerminalRegistry.applyPlayerTerminalHint then
		GlobalStorageSiK.TerminalRegistry.applyPlayerTerminalHint(player, args.terminalHint, proxRange)
	end
end



--- Crea zona en el registro.

---@param zone table

---@return boolean, string

local function addZone(zone)

	local registry = GlobalStorageSiK.Zones.getRegistry()

	local maxZones = GlobalStorageSiK.Sandbox.getMaxZonesPerNetwork()



	local count = 0

	for _, z in pairs(registry.zones or {}) do

		if z.networkId == zone.networkId then

			count = count + 1

		end

	end

	if count >= maxZones then

		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_ZoneLimitReached")

	end

	if zone.priority == nil then
		-- Escala libre 1-100 (1=maxima), igual que contenedores - ya no es
		-- una posicion secuencial (ver GS_Zones.setPriority). 50 = "Normal",
		-- mismo valor por defecto que usan los contenedores nuevos.
		zone.priority = 50
	end

	registry.zones[zone.id] = zone

	ModData.transmit(GlobalStorageSiK.MODDATA_KEY)

	return true, GlobalStorageSiK.I18n.remote("IGUI_GS_ZoneCreatedMsg", zone.name)

end



--- Registra un contenedor (legacy).

---@param entry table

---@param networkId string|nil

---@return boolean, string

local function registerContainer(entry, networkId)

	if not entry or not entry.id then

		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_InvalidEntry")

	end



	local registry = GlobalStorageSiK.Network.getRegistry()

	GlobalStorageSiK.Network.ensureRegistry(registry)



	local netId = networkId or registry.defaultNetworkId

	local network = registry.networks[netId]

	local containers = network.containers



	for _, existing in ipairs(containers) do

		if existing.id == entry.id then

			return false, GlobalStorageSiK.I18n.remote("IGUI_GS_AlreadyMarked")

		end

	end



	if #containers >= GlobalStorageSiK.Config.MAX_CONTAINERS_PER_NETWORK then

		return false, GlobalStorageSiK.I18n.remote("IGUI_GS_ContainerLimitReached")

	end



	table.insert(containers, entry)

	ModData.transmit(GlobalStorageSiK.MODDATA_KEY)

	return true, GlobalStorageSiK.I18n.remote("IGUI_GS_ContainerMarkedMsg")

end



--- Elimina un contenedor legacy.

---@param containerId string

---@param networkId string|nil

---@return boolean, string

local function unregisterContainer(containerId, networkId)

	local registry = GlobalStorageSiK.Network.getRegistry()

	GlobalStorageSiK.Network.ensureRegistry(registry)



	local netId = networkId or registry.defaultNetworkId

	local network = registry.networks[netId]

	local containers = network.containers



	for index, existing in ipairs(containers) do

		if existing.id == containerId then

			table.remove(containers, index)

			ModData.transmit(GlobalStorageSiK.MODDATA_KEY)

			return true, GlobalStorageSiK.I18n.remote("IGUI_GS_ContainerUnmarkedMsg")

		end

	end



	return false, GlobalStorageSiK.I18n.remote("IGUI_GS_ContainerNotInNetworkMsg")

end



local playerCraftProbe = {}

local ACCESS_MESSAGES = {
	no_terminal = GlobalStorageSiK.I18n.remote("IGUI_GS_BlockedTitle"),
	terminal_unlinked = GlobalStorageSiK.I18n.remote("IGUI_GS_AccessTerminalUnlinked"),
	tablet_out_of_range = GlobalStorageSiK.I18n.remote("IGUI_GS_AccessTabletOutOfRange"),
	tablet_addon_required = GlobalStorageSiK.I18n.remote("IGUI_GS_AccessTabletAddonRequired"),
	no_player = GlobalStorageSiK.I18n.remote("IGUI_GS_AccessInvalidPlayer"),
}

local function sendTerminalBlocked(player, reason)
	clearTerminalWatcher(player)
	GlobalStorageSiK.TerminalAccess.clearSession(player)
	if GlobalStorageSiK.Server.pushTerminalManifest then
		GlobalStorageSiK.Server.pushTerminalManifest(player)
	end
	gsSendServerCommand(player, "terminalBlocked", {
		reason = reason,
		wirelessRange = GlobalStorageSiK.Sandbox.getWirelessRange(),
		proximityRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange(),
		serverMinimal = true,
	})
end

--- Si el jugador esta cerca de un terminal CONOCIDO por el registro
--- (activo o suspendido) pero no se ha encontrado ningun ordenador fisico
--- ahi, se considera que el terminal ha desaparecido: se suspende
--- automaticamente (si aun figuraba activo) y se devuelve un motivo
--- especifico para que el cliente lo explique claramente, en vez de un
--- generico "no hay terminal cerca" que no dice nada de por que. No borra
--- nada, no se pierde ningun contenedor de la red - solo se deja de
--- reconocer esa posicion como terminal hasta que se reinstale ahi mismo
--- o en otra parte dentro del rango de la red.
---@param player IsoPlayer
---@return string|nil reason "terminal_missing_here" o nil si no aplica
local function checkMissingTerminalHere(player)
	if not GlobalStorageSiK.TerminalRegistry or not GlobalStorageSiK.TerminalRegistry.findNearestKnownAnchor then
		return nil
	end
	local proxRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	local known = GlobalStorageSiK.TerminalRegistry.findNearestKnownAnchor(player, proxRange)
	if not known then
		return nil
	end
	if known.active then
		clearTerminalObjectsAt(known.x, known.y, known.z)
		GlobalStorageSiK.TerminalRegistry.suspendTerminalAt(known.networkId, known.x, known.y, known.z)
		GlobalStorageSiK.Log.warn("Server", "autoSuspendMissingTerminal",
			string.format("%d,%d,%d network=%s user=%s",
				known.x, known.y, known.z, tostring(known.networkId), player:getUsername()))
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	return "terminal_missing_here"
end

--- Envía al cliente la lista de terminales de sus redes (proximidad sin escaneo).
---@param player IsoPlayer
function GlobalStorageSiK.Server.pushTerminalManifest(player)
	if not player or not GlobalStorageSiK.TerminalManifest or not GlobalStorageSiK.TerminalManifest.buildForPlayer then
		return
	end
	local ok, manifest = pcall(GlobalStorageSiK.TerminalManifest.buildForPlayer, player)
	if not ok or not manifest then
		return
	end
	gsSendServerCommand(player, "terminalManifest", manifest)
end

--- Comprueba permisos de red; envía actionResult si falla.
---@param player IsoPlayer
---@param networkId string
---@param resultMeta table|nil Campos opcionales para correlacionar el rechazo.
---@return boolean
local function requireNetworkPermission(player, networkId, resultMeta)
	local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(player, networkId))
	if allowed then
		return true
	end
	gsSendServerCommand(player, "actionResult", {
		ok = false,
		message = GlobalStorageSiK.I18n.remote("IGUI_GS_NoAccess"),
		jobType = resultMeta and resultMeta.jobType or nil,
		jobState = resultMeta and resultMeta.jobState or nil,
		queueId = resultMeta and resultMeta.queueId or nil,
		withdrawId = resultMeta and resultMeta.withdrawId or nil,
		transferOp = resultMeta and resultMeta.transferOp or nil,
	})
	return false
end

--- Comprueba que el jugador tiene rol admin o superior; envía actionResult si falla.
---@param player IsoPlayer
---@param networkId string
---@param resultMeta table|nil Campos opcionales para correlacionar el rechazo.
---@return boolean
local function requireAdminAccess(player, networkId, resultMeta)
	if not requireNetworkPermission(player, networkId, resultMeta) then
		return false
	end
	if GlobalStorageSiK.Permissions.isServerStaff(player) then
		GlobalStorageSiK.Log.info("Permissions", "serverStaffOverride",
			tostring(player:getUsername()) .. " networkId=" .. tostring(networkId))
		return true
	end
	if GlobalStorageSiK.Permissions.isAdminPlayer(player, networkId) then
		return true
	end
	gsSendServerCommand(player, "actionResult", {
		ok = false,
		message = GlobalStorageSiK.I18n.remote("IGUI_GS_RequireAdminRole"),
		jobType = resultMeta and resultMeta.jobType or nil,
		jobState = resultMeta and resultMeta.jobState or nil,
	})
	return false
end

--- Gate exclusivo de Auto Sort: solo roles persistentes owner/admin de ESTA
--- red. Deliberadamente no aplica el override global de staff usado por las
--- demás herramientas administrativas.
---@param player IsoPlayer
---@param networkId string
---@param resultMeta table|nil
---@return boolean
local function requireAutoSortAccess(player, networkId, resultMeta)
	if not requireNetworkPermission(player, networkId, resultMeta) then
		return false
	end
	if GlobalStorageSiK.Permissions.hasNetworkAdminRole(player, networkId) then
		return true
	end
	gsSendServerCommand(player, "actionResult", {
		ok = false,
		message = GlobalStorageSiK.I18n.remote("IGUI_GS_RedistributeAdminOnly"),
		jobType = resultMeta and resultMeta.jobType or nil,
		jobState = resultMeta and resultMeta.jobState or nil,
	})
	return false
end

--- Mantiene estable el contrato de nodos/zonas que Auto Sort capturó. No
--- bloquea depósitos ni retiros: solo cambios estructurales que alterarían los
--- candidatos o sus reglas a mitad del job.
local function requireNetworkConfigIdle(player, networkId)
	if GlobalStorageSiK.ZoneScanJob.isActive(networkId) then
		gsSendServerCommand(player, "actionResult", {
			ok = false,
			message = GlobalStorageSiK.I18n.remote("IGUI_GS_ScanConfigLocked"),
			jobType = "zoneScan",
			jobState = "running",
		})
		return false
	end
	if not GlobalStorageSiK.RedistributeJob.isActive(networkId) then return true end
	gsSendServerCommand(player, "actionResult", {
		ok = false,
		message = GlobalStorageSiK.I18n.remote("IGUI_GS_RedistributeConfigLocked"),
		jobType = "redistribute",
		jobState = "running",
	})
	return false
end

--- Comprueba permisos y proximidad al terminal.
---@param player IsoPlayer
---@param networkId string
---@param resultMeta table|nil
---@return boolean
local function requireTerminalAccess(player, networkId, resultMeta)
	if not requireNetworkPermission(player, networkId, resultMeta) then
		return false
	end
	local anchor = GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
	local sessionLock = anchor ~= nil
	local accessOk, _, _, accessReason = GlobalStorageSiK.TerminalAccess.evaluate(
		player, networkId, anchor, { sessionLock = sessionLock, strictDistance = true }
	)
	if accessOk then
		return true
	end
	local msg = ACCESS_MESSAGES[accessReason] or GlobalStorageSiK.I18n.remote("IGUI_GS_NoTerminalAccessMsg")
	gsSendServerCommand(player, "actionResult", {
		ok = false,
		message = msg,
		queueId = resultMeta and resultMeta.queueId or nil,
		withdrawId = resultMeta and resultMeta.withdrawId or nil,
		transferOp = resultMeta and resultMeta.transferOp or nil,
	})
	GlobalStorageSiK.TerminalAccess.clearSession(player)
	return false
end

--- Sugiere categoría dominante desde filas de contenido (rows, ya resueltas
--- con GS_ItemSnapshot.toRows - mismo formato que collectMainFilters/
--- collectSubFilters usan en el cliente).
--- BUG REAL (2026-08-17, "Comida 2 con rules=Food no acepta nada, deuda
--- tecnica en chips NUEVOS no antiguos"): esta funcion devolvia row.category
--- SIN PROCESAR (la DisplayCategory cruda del ScriptItem, ej. "Food",
--- "FoodSnack", "MaterialWeapon" segun el mod de categorias extendidas
--- instalado) y el boton "Categoria sugerida -> Aplicar" del cliente
--- (GS_TerminalUI_Config.lua:renderNodeContentsBlock) la guardaba TAL CUAL
--- como entry.categories, sin el prefijo GS_ItemTaxonomy.EXT_GROUP_PREFIX
--- que TODO el resto del sistema (matchSpecificity, collectMainFilters, el
--- editor de 3 desplegables) usa para reconocer "esto es una familia de
--- Nivel 1 completa, compara por groupLabel". El resultado: un chip que
--- parece de Nivel 1 pero que matchSpecificity nunca reconoce como tal (cae
--- al ultimo "else" que compara la clave cruda letra por letra), rechazando
--- SIEMPRE. Fix: resolver cada fila con ItemTaxonomy.resolve() (misma fuente
--- unica que collectMainFilters) y agrupar por tax.groupKey canonica, devolviendo
--- la clave YA prefijada - exactamente lo que el editor moderno guardaria si
--- el jugador hubiera elegido esa misma familia a mano.
---@param rows table[]
---@return string|nil
local function suggestCategoryFromSnapshot(rows)
	local counts = {}
	local EXT = GlobalStorageSiK.ItemTaxonomy.EXT_GROUP_PREFIX
	for _, row in ipairs(rows or {}) do
		local ok, tax = pcall(GlobalStorageSiK.ItemTaxonomy.resolve, row.fullType, row)
		local groupKey = ok and tax and tax.groupKey
		if groupKey and groupKey ~= "" then
			counts[groupKey] = (counts[groupKey] or 0) + (row.count or 1)
		end
	end
	local best, bestCount = nil, 0
	for groupKey, total in pairs(counts) do
		if total > bestCount then
			best = groupKey
			bestCount = total
		end
	end
	return best and (EXT .. best) or nil
end

--- Obtiene filas de inventario de un nodo (vivo o snapshot).
---@param node table
---@param networkId string
---@return table[] rows
---@return string source live|snapshot|empty
local function resolveNodeContents(node, networkId)
	if not node then
		return {}, "empty"
	end
	local obj = GlobalStorageSiK.Network.findWorldObject(node)
	local container = obj and GlobalStorageSiK.Utils.getObjectContainer(obj, node.containerIndex) or nil
	if container then
		return GlobalStorageSiK.ItemSnapshot.toRows(GlobalStorageSiK.ItemSnapshot.fromContainer(container)), "live"
	end
	if node.itemSnapshot then
		return GlobalStorageSiK.ItemSnapshot.toRows(node.itemSnapshot), "snapshot"
	end
	return {}, "empty"
end

local TRANSFER_BUSY_MSG = "Red ocupada: otra transferencia en curso. Reintenta."

--- Itera jugadores conectados (servidor dedicado o anfitrión).
---@param fn function
local function forEachOnlinePlayer(fn)
	if not fn then
		return
	end
	if getOnlinePlayers then
		local ok, list = pcall(getOnlinePlayers)
		if ok and list and list.size then
			for i = 0, list:size() - 1 do
				local p = list:get(i)
				if p then
					fn(p)
				end
			end
			return
		end
	end
	if getNumActivePlayers and getSpecificPlayer then
		local n = getNumActivePlayers()
		for i = 0, n - 1 do
			local p = getSpecificPlayer(i)
			if p then
				fn(p)
			end
		end
	end
end

--- Busca un ítem por ID dentro de los contenedores vivos de una red - usado
--- por craftClaimItem para mover el ítem EXACTO que el cliente ya seleccionó
--- como input de receta (no uno cualquiera del mismo tipo), autoritativo en
--- servidor.
---@param networkId string|nil
---@param itemId number
---@return InventoryItem|nil item
---@return ItemContainer|nil container
local function findNetworkItemById(networkId, itemId, player)
	local live = GlobalStorageSiK.Permissions.filterLiveContainers(
		player, networkId, GlobalStorageSiK.Network.getLiveContainers(networkId))
	for i = 1, #live do
		local container = live[i].container
		if container and container.getItems then
			local items = container:getItems()
			if items then
				for j = 0, items:size() - 1 do
					local item = items:get(j)
					if item and item.getID and item:getID() == itemId then
						return item, container
					end
				end
			end
		end
	end
	return nil, nil
end

--- Cuenta el total de items (sumando cantidades apiladas, ver getItems():
--- size() ya usado igual en el resto del fichero) en todos los contenedores
--- en vivo de una red - diagnostico pedido (2026-08-16, "posible dupeo, añade
--- trazas de items antes y despues en el almacenamiento") para poder
--- comparar a ojo el total ANTES de reclamar (craftAttemptStart) contra el
--- total DESPUES de que la receta termine (craftAttempt RESULT) y confirmar
--- que la diferencia es exactamente lo esperado (materiales consumidos
--- menos, resultado craftado si se deposito) - nunca mas de lo esperado.
---@param networkId string|nil
---@return number
local function countNetworkItems(networkId)
	local total = 0
	local live = GlobalStorageSiK.Network.getLiveContainers(networkId)
	for i = 1, #live do
		local container = live[i].container
		if container and container.getItems then
			local items = container:getItems()
			if items and items.size then
				total = total + items:size()
			end
		end
	end
	return total
end

--- Ejecuta una transferencia con bloqueo exclusivo por red.
---@param player IsoPlayer
---@param networkId string|nil
---@param op string
---@param fn function
---@param resultMeta table|nil
---@return boolean ran
local function runLockedTransfer(player, networkId, op, fn, resultMeta)
	if not fn then
		return false
	end
	local acquired, lockReason = GlobalStorageSiK.TransferLock.acquire(networkId, player, op)
	if not acquired then
		gsSendServerCommand(player, "actionResult", {
			ok = false,
			message = TRANSFER_BUSY_MSG,
			reason = lockReason or "network_busy",
			transferOp = op,
			queueId = resultMeta and resultMeta.queueId or nil,
			withdrawId = resultMeta and resultMeta.withdrawId or nil,
		})
		return false
	end
	local ok, err = pcall(fn)
	GlobalStorageSiK.TransferLock.release(networkId, player)
	if not ok then
		if GlobalStorageSiK.Log then
			GlobalStorageSiK.Log.error("Server", "runLockedTransfer:" .. tostring(op), tostring(err))
		end
		gsSendServerCommand(player, "actionResult", {
			ok = false,
			message = GlobalStorageSiK.I18n.remote("IGUI_GS_InternalTransferError"),
			reason = "transfer_error",
			transferOp = op,
			queueId = resultMeta and resultMeta.queueId or nil,
			withdrawId = resultMeta and resultMeta.withdrawId or nil,
		})
		return false
	end
	return true
end

--- Cuenta tipos por nodo accesible a partir del snapshot persistido. No lee
--- InventoryItem: el GS_ZoneScanJob actualiza la captura con presupuesto y
--- después se envía el estado dirigido. Usado para que la columna "Tipos" del
--- listado de nodos se actualice tras depositar/retirar (BUG REAL reportado
--- 2026-08-16: "la lista
--- de nodos no actualiza su cantidad de tipos distintos... retiré los items,
--- debería poner 0 pero no actualiza si no cierro y abro o cambio de
--- pestaña" - pushTerminalInventorySync solo mandaba agregados de red, nunca
--- por-nodo, y el cliente (refreshFromState) no tocaba terminalState.nodes
--- en absoluto en la rama inventorySync).
---@param networkId string
---@return table<string, number>
local function buildLiveNodeTypeCounts(networkId, player)
	local counts = {}
	local registry = GlobalStorageSiK.Zones.getRegistry()
	if not registry or not registry.nodes then
		return counts
	end
	local live = GlobalStorageSiK.Permissions.filterLiveContainers(
		player, networkId, GlobalStorageSiK.Network.getLiveContainers(networkId))
	for i = 1, #live do
		local entry = live[i].entry
		if entry and entry.id and registry.nodes[entry.id] then
			counts[entry.id] = countSnapshotTypes(registry.nodes[entry.id].itemSnapshot)
		end
	end
	return counts
end

--- Refresca inventario del terminal a otros jugadores con acceso a la red.
---@param player IsoPlayer|nil
---@param networkId string|nil
---@param searchQuery string|nil
local function pushTerminalInventorySync(player, networkId, searchQuery)
	if not player or not networkId then
		return
	end
	local ok, err = pcall(function()
		local rows = GlobalStorageSiK.Index.buildRows(networkId, player)
		local payload = {
			networkId = networkId,
			items = rows,
			searchQuery = searchQuery or "",
			inventoryRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId),
			snapshotRevision = GlobalStorageSiK.Index.getSnapshotRevision(networkId),
			redistributeActive = GlobalStorageSiK.RedistributeJob.isActive(networkId),
			itemTypeCount = #rows,
			nodeTypeCounts = buildLiveNodeTypeCounts(networkId, player),
			capacity = GlobalStorageSiK.NetworkCapacity.serialize(
				GlobalStorageSiK.NetworkCapacity.compute(networkId)
			),
			inventorySync = true,
			openUi = false,
		}
		gsSendServerCommand(player, "terminalState", payload)
	end)
	if not ok and GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.error("Server", "pushTerminalInventorySync", tostring(err))
	end
end

local function pushTerminalStateToNetworkWatchers(actor, networkId, searchQuery)
	if not networkId then
		return 0
	end
	local pushed = 0
	forEachOnlinePlayer(function(p)
		if actor and p == actor then
			return
		end
		if not isTerminalWatcher(p, networkId) then
			return
		end
		local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(p, networkId))
		if not allowed then
			clearTerminalWatcher(p)
			return
		end
		if queueTerminalRefresh(p, networkId, searchQuery, false) then
			pushed = pushed + 1
		end
	end)
	return pushed
end

--- Avisa con un payload mínimo a quienes ya tienen abierta esa red y los
--- registra para progreso/final. Evita reconstruir/enviar el catálogo completo
--- solo para comunicar el bloqueo temporal de configuración.
local function notifyRedistributeStartedToWatchers(actor, networkId)
	forEachOnlinePlayer(function(player)
		if player ~= actor and isTerminalWatcher(player, networkId) then
			GlobalStorageSiK.RedistributeJob.addWatcher(player, networkId)
			gsSendServerCommand(player, "actionResult", {
				ok = true,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_RedistributeConfigLocked"),
				jobType = "redistribute",
				jobState = "running",
			})
		end
	end)
end

-- Forward-declarada aqui (asignada mas abajo, justo tras definir
-- pushTerminalState, del que depende) para poder usarla en el handler de
-- "updateNode" sin importar el orden de declaracion en el fichero.
local pushNodeChangeToNetworkWatchers

--- Sincroniza estado del terminal tras una transferencia exitosa.
---@param actor IsoPlayer
---@param networkId string|nil
---@param searchQuery string|nil
---@param options table|nil { suppressUi = boolean }
local function afterTransferSync(actor, networkId, searchQuery, options)
	if not networkId then
		return
	end
	options = options or {}
	-- La revision se aplica ahora y los snapshots se consolidan por la cola
	-- diferida; ambos permanecen en el proceso autoritativo,
	-- pero NO se transmite aqui el Global ModData completo. Ese registro puede
	-- contener snapshots de todos los nodos y, al depositar cientos de items,
	-- se estaba difundiendo una vez por cada lote ademas de los mensajes
	-- vanilla por objeto. El terminal se actualiza por terminalState, debajo.
	GlobalStorageSiK.Server.markInventoryDirty(networkId, actor)
	if options.suppressUi == true then
		-- Una linea por microlote solo resulta util al diagnosticar la
		-- consolidacion interna. El resumen funcional ya llega por actionResult.
		GlobalStorageSiK.Log.detail("Server", "afterTransferSync",
			"network=" .. tostring(networkId) .. " ui=suppressed")
		return
	end
	-- El resultado de la operación ya se informa por actionResult. El catálogo
	-- completo se enviará una sola vez al terminar el snapshot incremental de
	-- fondo; reconstruirlo aquí recorría de nuevo miles de instancias y repetía
	-- el mismo payload para cada lote.
	GlobalStorageSiK.Log.detail("Server", "afterTransferSync",
		"network=" .. tostring(networkId)
			.. " refresh=deferred_incremental")
end

--- Envía estado del terminal al cliente.
---@param openUi boolean|nil true solo tras openTerminal exitoso
---@param accessMode string|nil physical|wireless|bypass
---@param terminalAnchor table|nil { x, y, z } terminal usado en el servidor
---@param meta table|nil { openSeq = number }
local function pushTerminalState(player, networkId, scanSummary, searchQuery, craftProbe, openUi, accessMode, terminalAnchor, meta)
	if player and GlobalStorageSiK.RedistributeJob.isActive(networkId) then
		GlobalStorageSiK.RedistributeJob.addWatcher(player, networkId)
	end
	if player and craftProbe then
		playerCraftProbe[player:getUsername()] = craftProbe
	end
	local probe = craftProbe
	if not probe and player then
		probe = playerCraftProbe[player:getUsername()]
	end
	-- BUG REAL encontrado (reportado 2026-08-16, "al editar un nodo/
	-- contenedor desde su modal desaparecen las pestañas de addon"): decenas
	-- de sitios de este fichero llaman pushTerminalState SIN pasar
	-- terminalAnchor (ver mas abajo, el edit/rename/setPriority de
	-- nodos/zonas y muchos mas). Sin anchor, installedAddons/
	-- craftTabEnabled/buildTabEnabled quedan fuera del payload (ver mas
	-- abajo) y el cliente interpreta su ausencia como "ocultar pestaña" -
	-- exactamente el mismo bug ya confirmado y arreglado una vez para
	-- GS_RedistributeJob.lua (pasando el anchor a mano en ESE fichero).
	-- En vez de tocar cada uno de los ~30 sitios de este fichero que no lo
	-- pasan, se resuelve aqui mismo con el mismo fallback ya usado alli
	-- (GlobalStorageSiK.TerminalAccess.getSessionAnchor) - corrige todos los
	-- sitios a la vez, de una vez por todas.
	if not terminalAnchor and player and GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.getSessionAnchor then
		terminalAnchor = GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
	end
	local payload = buildTerminalState(networkId, scanSummary, searchQuery, probe, player)
	payload.openUi = openUi == true
	if meta and meta.openSeq then
		payload.openSeq = meta.openSeq
	end
	if player and accessMode then
		accessMode = GlobalStorageSiK.TerminalAccess.refineWirelessMode(player, accessMode)
		payload.accessMode = accessMode
	elseif accessMode then
		payload.accessMode = accessMode
	end
	if terminalAnchor and terminalAnchor.x and terminalAnchor.y then
		payload.terminalAnchor = {
			x = terminalAnchor.x,
			y = terminalAnchor.y,
			z = terminalAnchor.z or 0,
		}
		if GlobalStorageSiK.Addons and GlobalStorageSiK.Addons.serializeForTerminal then
			-- El Lector (antes floppyDriveInstalled aparte) ya sale aqui como
			-- installedAddons["Reader"] - ver GS_ReaderAddon.lua.
			payload.installedAddons = GlobalStorageSiK.Addons.serializeForTerminal(networkId, payload.terminalAnchor)
		end
	end
	if player then
		payload.wirelessRange = GlobalStorageSiK.TerminalAccess.getWirelessRangeForPlayer(player)
		payload.craftTabEnabled = GlobalStorageSiK.Addons.canShowTerminalCraftTab(
			networkId,
			payload.terminalAnchor,
			payload.accessMode,
			player
		)
		-- BUG REAL encontrado (reportado: "todos instalados, pero Constructor
		-- no tiene pestaña propia"): craftTabEnabled SI se calculaba y enviaba
		-- server-side (autoritativo), pero buildTabEnabled nunca se calculaba
		-- aqui - el cliente (syncBuildTabVisibility) caia siempre al fallback
		-- local canShowTerminalBuildTab(), sujeto al mismo retraso de mirror
		-- ModData ya documentado y arreglado una vez para canUseAddon. Mismo
		-- arreglo que Craft: calcularlo tambien server-side y enviarlo ya
		-- resuelto, para que el cliente no dependa de su copia local.
		payload.buildTabEnabled = GlobalStorageSiK.Addons.canShowTerminalBuildTab(
			networkId,
			payload.terminalAnchor,
			payload.accessMode,
			player
		)
		if openUi == true and GlobalStorageSiK.NetworkManager then
			payload.networks = GlobalStorageSiK.NetworkManager.listForPlayer(player)
			payload.activeNetworkId = GlobalStorageSiK.NetworkManager.getPlayerSessionNetwork(player)
		end
	end
	GlobalStorageSiK.Debug.log("Server", "terminalState", "zones=" .. tostring(payload.zones and #payload.zones or 0))
	gsSendServerCommand(player, "terminalState", payload)
end

-- Alias namespaced para que otros ficheros server (p.ej. GS_RedistributeJob)
-- puedan empujar el estado tras terminar un job en segundo plano, sin mover
-- la funcion ni tocar sus muchas llamadas locales ya existentes en este fichero.
GlobalStorageSiK.Server = GlobalStorageSiK.Server or {}
GlobalStorageSiK.Server.pushTerminalState = pushTerminalState
GlobalStorageSiK.Server.sendCommand = gsSendServerCommand

--- Inicia/reengancha un reescaneo incremental. El estado inicial se sirve
--- desde snapshots ya persistidos; el job enviara el resultado fresco solo a
--- quienes observen esta red cuando termine.
local function startIncrementalScan(player, networkId, searchQuery, zoneId)
	local started, reason = GlobalStorageSiK.ZoneScanJob.start(player, networkId, {
		zoneId = zoneId,
		searchQuery = searchQuery or "",
	})
	if not started and reason ~= "active" then
		local key = reason == "zone_not_found" and "IGUI_GS_ZoneNotFoundMsg"
			or (reason == "redistribute_active" and "IGUI_GS_RedistributeConfigLocked")
			or "IGUI_GS_ScanFailed"
		gsSendServerCommand(player, "actionResult", {
			ok = false,
			message = GlobalStorageSiK.I18n.remote(key),
			jobType = "zoneScan",
			jobState = "finished",
		})
		return false, reason
	end
	gsSendServerCommand(player, "actionResult", {
		ok = true,
		message = GlobalStorageSiK.I18n.remote(reason == "active"
			and "IGUI_GS_ScanAlreadyRunning" or "IGUI_GS_ScanStarted"),
		jobType = "zoneScan",
		jobState = "running",
	})
	return true, reason
end

--- Callback del job: un unico resumen y un terminalState dirigido por cliente.
--- No hay ModData.transmit; clientes sin esta red abierta no reciben snapshots.
function GlobalStorageSiK.Server.onNetworkScanComplete(networkId, summary, requestedWatchers)
	local startRevision = summary._startRevision or 0
	local currentRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId)
	if currentRevision ~= startRevision then
		-- El job recorrió la red mientras una transferencia seguía mutándola. Sus
		-- nodos pueden pertenecer a instantes distintos: no publicar esa mezcla ni
		-- certificarla como snapshot fresco. Programamos una pasada tras la pausa.
		local retryPlayer = nil
		for username in pairs(requestedWatchers or {}) do
			retryPlayer = GlobalStorageSiK.PlayerUtils.resolveByUsername(username)
			if retryPlayer then break end
		end
		if not retryPlayer then
			forEachOnlinePlayer(function(player)
				if not retryPlayer and isTerminalWatcher(player, networkId) then
					retryPlayer = player
				end
			end)
		end
		scheduleSnapshotSync(networkId, retryPlayer, currentRevision)
		GlobalStorageSiK.Log.warn("ZoneScanJob", "discard unstable network="
			.. tostring(networkId) .. " startRevision=" .. tostring(startRevision)
			.. " currentRevision=" .. tostring(currentRevision))
		return
	end
	if summary._freshSnapshotScope == "network" then
		GlobalStorageSiK.Index.setSnapshotRevision(networkId, currentRevision)
	end
	local pending = pendingSnapshotSync[networkId]
	if pending and (pending.revision or 0) <= (summary._startRevision or -1) then
		-- Este scan comenzó después del último cambio conocido y ya lo cubre.
		-- Evitar una segunda pasada idéntica al vencer la cola de snapshots.
		pendingSnapshotSync[networkId] = nil
	end
	forEachOnlinePlayer(function(player)
		local username = player.getUsername and player:getUsername() or ""
		local explicitlyRequested = requestedWatchers and requestedWatchers[username] ~= nil
		-- Si el solicitante cerró o cambió de red durante el job, ya no debe
		-- recibir un catálogo grande de la red anterior.
		if isTerminalWatcher(player, networkId) then
			local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(player, networkId))
			if allowed then
				local query = explicitlyRequested and requestedWatchers[username] or ""
				pushTerminalState(player, networkId, summary, query)
				if summary._background ~= true then
					gsSendServerCommand(player, "actionResult", {
						ok = true,
						message = GlobalStorageSiK.I18n.remote("IGUI_GS_ScanCompleteMetrics",
							summary.durationMs or 0, summary.nodesScanned or 0,
							summary.itemInstances or 0, summary.distinctTypes or 0,
							summary.snapshotRows or 0),
						jobType = "zoneScan",
						jobState = "finished",
					})
				end
			end
		end
	end)
end

function GlobalStorageSiK.Server.onNetworkScanFailed(networkId, requestedWatchers, errorText)
	forEachOnlinePlayer(function(player)
		if isTerminalWatcher(player, networkId) then
			gsSendServerCommand(player, "actionResult", {
				ok = false,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_ScanFailed"),
				jobType = "zoneScan",
				jobState = "finished",
			})
		end
	end)
	GlobalStorageSiK.Log.error("Server", "zoneScan callback network=" .. tostring(networkId)
		.. " error=" .. tostring(errorText))
end

local function clearDeletedNetworkReferences(networkId)
	pendingSnapshotSync[networkId] = nil
	local watcherKeys = {}
	for key, watchedId in pairs(terminalWatchNetworkByPlayer) do
		if watchedId == networkId then watcherKeys[#watcherKeys + 1] = key end
	end
	for i = 1, #watcherKeys do
		local key = watcherKeys[i]
		terminalWatchNetworkByPlayer[key] = nil
		pendingTerminalRefreshes[key] = nil
	end
	forEachOnlinePlayer(function(player)
		if GlobalStorageSiK.NetworkManager.getPlayerSessionNetwork(player) == networkId then
			GlobalStorageSiK.NetworkManager.setPlayerSessionNetwork(player, nil)
		end
		if GlobalStorageSiK.TerminalAccess.getSessionNetworkId(player) == networkId then
			GlobalStorageSiK.TerminalAccess.clearSession(player)
		end
	end)
end

local function broadcastNetworkLists()
	forEachOnlinePlayer(function(player)
		-- El manifiesto dirigido elimina inmediatamente terminales/redes borradas
		-- de la caché del cliente; personajes offline se autorreparan al entrar.
		GlobalStorageSiK.Server.pushTerminalManifest(player)
		gsSendServerCommand(player, "networkList", {
			networks = GlobalStorageSiK.NetworkManager.listForPlayer(player),
			activeNetworkId = GlobalStorageSiK.NetworkManager.getPlayerSessionNetwork(player),
		})
		gsSendServerCommand(player, "recoveryNetworks", {
			networks = GlobalStorageSiK.TerminalRecovery.buildNetworksForPlayer(player),
		})
	end)
end

-- Despacha como maximo un indice/estado completo a un espectador por tick.
-- La tabla por clave de personaje deduplica multiples cambios de la misma red
-- mientras ese cliente espera su turno.
flushPendingTerminalRefreshes = function()
	local selectedKey = nil
	local job = nil
	for key, candidate in pairs(pendingTerminalRefreshes) do
		selectedKey = key
		job = candidate
		break
	end
	if not selectedKey or not job then
		return
	end
	pendingTerminalRefreshes[selectedKey] = nil
	local player = job.player
	if not isTerminalWatcher(player, job.networkId) then
		return
	end
	local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(player, job.networkId))
	if not allowed then
		clearTerminalWatcher(player)
		return
	end
	if job.fullState then
		pushTerminalState(player, job.networkId, nil, job.searchQuery)
	else
		pushTerminalInventorySync(player, job.networkId, job.searchQuery)
	end
end

--- Difunde el estado COMPLETO del terminal (zonas, nodos: nombre, categorias,
--- prioridad...) a los demas miembros online con acceso. Distinto de
--- pushTerminalStateToNetworkWatchers, que solo empuja el inventario de
--- items (usado tras depositar/retirar); esta se usa tras editar un nodo,
--- para que el cambio de un jugador se vea en el terminal de los demas
--- cuanto antes, sin esperar a que hagan otra accion que lo refresque.
---@param actor IsoPlayer
---@param networkId string|nil
---@param searchQuery string|nil
pushNodeChangeToNetworkWatchers = function(actor, networkId, searchQuery)
	if not networkId then
		return
	end
	forEachOnlinePlayer(function(p)
		if actor and p == actor then
			return
		end
		if not isTerminalWatcher(p, networkId) then
			return
		end
		local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(p, networkId))
		if not allowed then
			clearTerminalWatcher(p)
			return
		end
		queueTerminalRefresh(p, networkId, searchQuery, true)
	end)
end



--- Extraido de onClientCommand: Kahlua (compilador Lua de B42) tiene un
--- limite duro de 200 variables locales POR FUNCION, y no reutiliza slots
--- entre ramas if/elseif hermanas - onClientCommand es un dispatcher gigante
--- con 70+ ramas que ya lo habia superado (crash real "Index 200 out of
--- bounds" reportado en carga de partida, v1.2.69). Sacar las ramas mas
--- pesadas en locales a funciones propias libera slots sin cambiar ningun
--- comportamiento.
---@param player IsoPlayer
---@param args table
---@param networkId string|nil
---@param searchQuery string|nil
local function handleOpenTerminal(player, args, networkId, searchQuery)
	GlobalStorageSiK.Log.info("Server", "openTerminal", player:getUsername())
	-- Corrige el bug vanilla de "manual leido bloquea recetas nuevas para
	-- siempre" (ver comentario en GS_CraftUtils.ensureManualRecipesGranted)
	-- cada vez que el jugador abre el terminal, no solo al leer un manual -
	-- asi cualquier jugador que ya lo hubiera leido con una version anterior
	-- del mod se pone al dia sin tener que hacer nada.
	GlobalStorageSiK.CraftUtils.ensureManualRecipesGranted(player)
	if GlobalStorageSiK.TerminalManifest and GlobalStorageSiK.TerminalManifest.pruneLocalTerminalCache then
		GlobalStorageSiK.TerminalManifest.pruneLocalTerminalCache(player, { transmit = false })
	end
	local openSeq = args.openSeq
	applyAccessHints(player, args)
	GlobalStorageSiK.Server.pushTerminalManifest(player)

	local resolvedNet, nearbyProbe, blockReason = GlobalStorageSiK.NetworkResolve.resolveOpenTerminal(player, args)
	if blockReason == "terminal_unlinked" then
		GlobalStorageSiK.Log.warn("Server", "openTerminal blocked", "terminal_unlinked")
		sendTerminalBlocked(player, "terminal_unlinked")
		return
	end
	networkId = resolvedNet

	local hintAnchor = args.terminalHint or nearbyProbe
	if not hintAnchor and nearbyProbe then
		hintAnchor = nearbyProbe
	end

	local accessOk, accessMode, terminal, accessReason = GlobalStorageSiK.TerminalAccess.evaluate(
		player, networkId, hintAnchor, { ignoreSession = true, strictDistance = true }
	)
	if terminal and terminal.networkId then
		networkId = terminal.networkId
	elseif terminal and terminal.x then
		local at = GlobalStorageSiK.Network.findNetworkIdAtTerminal(terminal.x, terminal.y, terminal.z or 0, {
			activeOnly = true,
		})
		if at then
			networkId = at
		end
	end
	if not networkId then
		networkId = GlobalStorageSiK.Network.getDefaultNetworkId()
		local registry = GlobalStorageSiK.Network.getRegistry()
		local net = registry and registry.networks and networkId and registry.networks[networkId]
		if not net or not GlobalStorageSiK.TerminalRecord.getPrimaryAnchor(net) then
			sendTerminalBlocked(player, checkMissingTerminalHere(player) or blockReason or "no_terminal")
			return
		end
	end

	local allowed, reason = GlobalStorageSiK.Permissions.canAccess(player, networkId)
	if not allowed then
		GlobalStorageSiK.Log.warn("Server", "openTerminal denied", "permissions:" .. tostring(reason))
		gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_NoAccess") })
		return
	end

	local hasTablet = GlobalStorageSiK.TerminalAccess.hasTablet(player)
	GlobalStorageSiK.Log.info("Server", "accessCheck",
		string.format("user=%s ok=%s mode=%s reason=%s tablet=%s terminal=%s",
			tostring(player:getUsername()),
			tostring(accessOk),
			tostring(accessMode),
			tostring(accessReason),
			tostring(hasTablet),
			terminal and string.format("%d,%d,%d", terminal.x, terminal.y, terminal.z) or "none"
		)
	)
	if not accessOk then
		GlobalStorageSiK.TerminalAccess.clearSession(player)
		sendTerminalBlocked(player, accessReason)
		return
	end
	if GlobalStorageSiK.Sandbox.requireTerminalAccess() and accessMode ~= "bypass" and not terminal then
		GlobalStorageSiK.TerminalAccess.clearSession(player)
		sendTerminalBlocked(player, checkMissingTerminalHere(player) or "no_terminal")
		return
	end

	if terminal then
		GlobalStorageSiK.TerminalAccess.setSessionAnchor(player, terminal, accessMode, networkId)
	end
	setTerminalWatcher(player, networkId)
	if GlobalStorageSiK.NetworkManager then
		GlobalStorageSiK.NetworkManager.setPlayerSessionNetwork(player, networkId)
	end

	-- Abrir inmediatamente desde la ultima captura persistida. El barrido real
	-- continua por ticks y refresca esta misma UI al terminar; una red con miles
	-- de objetos ya no bloquea el handler de apertura ni duplica el recorrido.
	local scanSummary = { running = false, _freshSnapshotScope = "network" }
	if GlobalStorageSiK.Sandbox.rescanOnTerminalOpen()
		and not GlobalStorageSiK.RedistributeJob.isActive(networkId) then
		local accepted = startIncrementalScan(player, networkId, searchQuery)
		scanSummary.running = accepted == true
	end

	pushTerminalState(player, networkId, scanSummary, searchQuery, nil, true, accessMode, terminal, { openSeq = openSeq })
end

---@param player IsoPlayer
---@param args table
local function handleInstallTerminalReader(player, args)
	if not (args.x and args.y and args.z) then
		return
	end
	local x, y, z = math.floor(args.x), math.floor(args.y), math.floor(args.z)
	local proxRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	local dx, dy = player:getX() - x, player:getY() - y
	local near = math.sqrt(dx * dx + dy * dy) <= proxRange + 0.5
	if not near then
		gsSendServerCommand(player, "terminalRegisterFailed", { reason = "terminal_too_far", x = x, y = y, z = z })
		return
	end
	local inv = player:getInventory()
	-- El lector debe estar en el inventario PRINCIPAL, no en una
	-- mochila (getItemCount, no getItemCountRecurse) - autoridad de
	-- servidor, no basta con lo que ya valido el cliente.
	local hasReader = inv and (inv:getItemCount(GlobalStorageSiK.Config.ITEM_TERMINAL_READER) or 0) > 0
	local hasFloppy = inv and (inv:getItemCountRecurse("GlobalStorageSiK.GS_FloppyDisk") or 0) > 0
	if not hasReader or not hasFloppy then
		gsSendServerCommand(player, "terminalRegisterFailed", { reason = "missing_items", x = x, y = y, z = z })
		return
	end
	local targetObj = nil
	local cell = getCell and getCell() or nil
	if cell then
		local sq = cell:getGridSquare(x, y, z)
		if sq and sq.getObjects then
			local objs = sq:getObjects()
			for i = 0, objs:size() - 1 do
				local obj = objs:get(i)
				if GlobalStorageSiK.TerminalAccess.isKnownComputerObject(obj) then
					targetObj = obj
					break
				end
			end
		end
	end
	if not targetObj then
		gsSendServerCommand(player, "terminalRegisterFailed", { reason = "not_a_computer", x = x, y = y, z = z })
		return
	end
	if GlobalStorageSiK.TerminalAccess.isTerminalObject(targetObj) then
		gsSendServerCommand(player, "terminalRegisterFailed", { reason = "already_installed", x = x, y = y, z = z })
		return
	end
	local mode = args.mode or "link"
	local targetNet = args.networkId
	if mode == "link" and (not targetNet or not requireNetworkPermission(player, targetNet)) then
		gsSendServerCommand(player, "terminalRegisterFailed", { reason = "denied", x = x, y = y, z = z })
		return
	end
	-- Autoridad de servidor: no basta con que el dialogo del cliente ya filtre
	-- por cobertura (GS_TerminalRecovery.buildNetworksForPlayer) - "No tiene
	-- sentido poder vincularnos a una red a la que no estamos en su radio de
	-- acceso" (feedback directo). Se comprueba aqui contra el ancla real de la
	-- red (terminal principal), con las coordenadas del terminal candidato.
	if mode == "link" and GlobalStorageSiK.TerminalRecord and GlobalStorageSiK.Network then
		local registry = GlobalStorageSiK.Network.getRegistry()
		local resolvedNet = GlobalStorageSiK.Network.resolveNetworkId(targetNet)
		local net = registry and registry.networks and resolvedNet and registry.networks[resolvedNet]
		local anchor = net and GlobalStorageSiK.TerminalRecord.getPrimaryAnchor(net)
		if anchor and not GlobalStorageSiK.Sandbox.isWithinNetworkRange(anchor, x, y, z) then
			gsSendServerCommand(player, "terminalRegisterFailed", { reason = "out_of_network_range", x = x, y = y, z = z })
			return
		end
	end
	local nid, regErr = registerTerminalAt(mode == "new" and nil or targetNet, x, y, z, player, mode)
	if not nid then
		gsSendServerCommand(player, "terminalRegisterFailed", { reason = regErr or "error", x = x, y = y, z = z })
		return
	end
	if mode == "new" and args.networkName and args.networkName ~= "" then
		local owner = GlobalStorageSiK.Permissions.getCharacterName(player)
		GlobalStorageSiK.Network.renameDisplayName(nid, owner, args.networkName)
	end
	-- NO se marca ModData en el ordenador: la fuente de verdad es la
	-- coordenada ya registrada por registerTerminalAt de arriba.
	-- isTerminalObject() reconoce este terminal comprobando esa
	-- coordenada directamente (ver GS_TerminalAccess.lua) - nada que
	-- marcar aqui, nada que limpiar al desinstalar.
	GlobalStorageSiK.Log.info("Server", "installTerminalReader",
		string.format("%d,%d,%d network=%s user=%s mode=%s",
			x, y, z, tostring(nid), player:getUsername(), tostring(mode)))
	if GlobalStorageSiK.NetworkManager then
		GlobalStorageSiK.NetworkManager.setPlayerSessionNetwork(player, nid)
	end
	ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	-- IMPORTANTE: el manifiesto se envia ANTES que "terminalRegistered". El
	-- cliente reacciona a "terminalRegistered" abriendo la ventana al vuelo
	-- (TerminalUI.requestOpen) - en MP real (latencia de red de verdad, a
	-- diferencia de SP donde todo es sincrono en el mismo proceso) esto podia
	-- llegar ANTES que el manifiesto actualizado, asi que la ventana
	-- comprobaba acceso contra el manifiesto VIEJO (sin la red recien unida)
	-- y decia "sin acceso" pese a que el join acababa de tener exito -
	-- reportado por un jugador al unir un segundo terminal en un servidor
	-- dedicado. Los mensajes de un mismo canal se procesan en el orden en que
	-- se envian, asi que basta con enviar el manifiesto primero.
	GlobalStorageSiK.Server.pushTerminalManifest(player)
	gsSendServerCommand(player, "terminalRegistered", {
		ok = true, networkId = nid, mode = mode, x = x, y = y, z = z,
	})
end

--- Normaliza un filtro de nodo recibido por red. Se usa tanto al anadir una
--- regla como al pegar una plantilla completa, para que ambos caminos tengan
--- exactamente los mismos limites y nunca confien en tablas del cliente.
---@param filter table|nil
---@return table|nil
local function sanitizeNodeFilter(filter)
	if type(filter) ~= "table" then return nil end
	if filter.type == "name" and filter.value and tostring(filter.value) ~= "" then
		local mode = filter.mode
		if mode ~= "exact" and mode ~= "startsWith" and mode ~= "endsWith" then mode = "contains" end
		return { type = "name", mode = mode, value = tostring(filter.value):sub(1, 60) }
	end
	if filter.type == "weight" and tonumber(filter.value) then
		local mode = filter.mode
		local allowed = { gt = true, lt = true, gte = true, lte = true, between = true, eq = true }
		if not allowed[mode] then mode = "eq" end
		local clean = { type = "weight", mode = mode, value = tonumber(filter.value) }
		if mode == "between" and tonumber(filter.value2) then clean.value2 = tonumber(filter.value2) end
		return clean
	end
	if filter.type == "tag" and filter.value and tostring(filter.value) ~= "" then
		return { type = "tag", value = tostring(filter.value):sub(1, 60) }
	end
	if filter.type == "item" and filter.itemType and tostring(filter.itemType) ~= "" then
		return {
			type = "item",
			itemType = tostring(filter.itemType):sub(1, 120),
			itemDisplay = filter.itemDisplay and tostring(filter.itemDisplay):sub(1, 60) or nil,
		}
	end
	return nil
end

local function sanitizeNodeCategories(categories)
	local result, seen = {}, {}
	if type(categories) ~= "table" then return result end
	for i = 1, math.min(#categories, 20) do
		local category = tostring(categories[i] or ""):sub(1, 160)
		if category ~= "" then
			local signature = string.lower(category)
			if not seen[signature] then
				seen[signature] = true
				result[#result + 1] = category
			end
		end
	end
	return result
end

local function cloneNodeFilters(filters)
	local result = {}
	for i = 1, #(filters or {}) do
		local copy = {}
		for key, value in pairs(filters[i]) do copy[key] = value end
		result[i] = copy
	end
	return result
end

local function onClientCommand(module, command, player, args)

	if module ~= GlobalStorageSiK.MOD_ID or not player then

		return

	end



	args = args or {}

	if GlobalStorageSiK.NetTrace and GlobalStorageSiK.NetTrace.logServerRecv then
		GlobalStorageSiK.NetTrace.logServerRecv(player, command, args)
	end

	local networkId = GlobalStorageSiK.Network.resolveCommandNetworkId(player, args, command)

	local searchQuery = args.searchQuery



	if command == "openTerminal" then
		handleOpenTerminal(player, args, networkId, searchQuery)

	elseif command == "closeTerminal" then
		clearTerminalWatcher(player)
		GlobalStorageSiK.TerminalAccess.clearSession(player)

	elseif command == "pingTerminalAccess" then
		local sessionNet = GlobalStorageSiK.TerminalAccess.getSessionNetworkId(player)
		if sessionNet then
			networkId = sessionNet
		end
		local allowed, reason = GlobalStorageSiK.Permissions.canAccess(player, networkId)
		if not allowed then
			GlobalStorageSiK.TerminalAccess.clearSession(player)
			sendTerminalBlocked(player, reason or "no_permission")
			return
		end
		local proxRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
		applyAccessHints(player, args)
		local accessOk, accessMode, terminal, accessReason = GlobalStorageSiK.TerminalAccess.evaluate(
			player, networkId, GlobalStorageSiK.TerminalAccess.getSessionAnchor(player),
			{ sessionLock = sessionNet ~= nil, strictDistance = true }
		)
		if not accessOk then
			GlobalStorageSiK.TerminalAccess.clearSession(player)
			sendTerminalBlocked(player, accessReason)
			return
		end
		if args.reopen and accessOk then
			if terminal then
				GlobalStorageSiK.TerminalAccess.setSessionAnchor(player, terminal, accessMode, networkId)
			end
			setTerminalWatcher(player, networkId)
			local scanSummary = { running = false, _freshSnapshotScope = "network" }
			if GlobalStorageSiK.Sandbox.rescanOnTerminalOpen()
				and not GlobalStorageSiK.RedistributeJob.isActive(networkId) then
				local accepted = startIncrementalScan(player, networkId, searchQuery)
				scanSummary.running = accepted == true
			end
			pushTerminalState(
				player, networkId, scanSummary, searchQuery, nil, true, accessMode, terminal,
				{ openSeq = args.openSeq }
			)
		end

	elseif command == "rescanNetwork" then
		if not requireTerminalAccess(player, networkId) then
			return
		end
		if GlobalStorageSiK.RedistributeJob.isActive(networkId) then
			requireNetworkConfigIdle(player, networkId)
			return
		end
		startIncrementalScan(player, networkId, searchQuery)

	elseif command == "getNodeContents" then
		if not requireTerminalAccess(player, networkId) then
			return
		end
		local registry = GlobalStorageSiK.Zones.getRegistry()
		local node = registry.nodes and registry.nodes[args.nodeId]
		if not node then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_ContainerNotFoundMsg") })
			return
		end
		local rows, source = resolveNodeContents(node, networkId)
		gsSendServerCommand(player, "nodeContents", {
			nodeId = args.nodeId,
			rows = rows,
			source = source,
			suggestedCategory = suggestCategoryFromSnapshot(rows),
		})

	elseif command == "craftTerminalRecipe" then
		local craftOpts = nil
		if args.recipeId == "terminal_install" then
			if not args.desktopItemId then
				gsSendServerCommand(player, "actionResult", {
					ok = false,
					message = GlobalStorageSiK.I18n.remote("IGUI_GS_CraftDesktopFail"),
					recipeId = args.recipeId,
				})
				return
			end
			local desktopItem = GlobalStorageSiK.TerminalRecipes.findInventoryItemById(player, args.desktopItemId)
			if not desktopItem or not GlobalStorageSiK.TerminalAccess.isVanillaDesktopItem(desktopItem) then
				gsSendServerCommand(player, "actionResult", {
					ok = false,
					message = GlobalStorageSiK.I18n.remote("IGUI_GS_CraftDesktopFail"),
					recipeId = args.recipeId,
				})
				return
			end
			craftOpts = { desktopItem = desktopItem }
		elseif args.desktopItemId then
			local desktopItem = GlobalStorageSiK.TerminalRecipes.findInventoryItemById(player, args.desktopItemId)
			if desktopItem then
				craftOpts = { desktopItem = desktopItem }
			end
		end
		local ok, message = GlobalStorageSiK.TerminalRecipes.craft(player, args.recipeId, craftOpts)
		gsSendServerCommand(player, "actionResult", {
			ok = ok,
			message = message,
			recipeId = args.recipeId,
		})

	elseif command == "acquirePC" then
		-- Ventana propia "Conseguir PC" (no receta vanilla) - ver GS_PCAcquire.lua.
		-- Nunca confía en lo que dijo el cliente: revalida manual + piezas aquí.
		local ok, reason = GlobalStorageSiK.PCAcquire.craft(player)
		local msg
		if ok then
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_PCAcquireSuccess")
		elseif reason == "book" then
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_PCAcquireFailBook")
		elseif reason == "skill" then
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_AcquireFailSkill")
		elseif reason == "tools" then
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_AcquireFailTools")
		elseif reason == "materials" then
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_PCAcquireFailMaterials")
		else
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_CraftFail")
		end
		gsSendServerCommand(player, "actionResult", { ok = ok, message = msg })

	elseif command == "acquireReader" then
		-- Ventana propia "Fabricar lector" (no receta vanilla) - ver
		-- GS_ReaderAcquire.lua. Nunca confía en lo que dijo el cliente:
		-- revalida manual + piezas aquí.
		local ok, reason = GlobalStorageSiK.ReaderAcquire.craft(player)
		local msg
		if ok then
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_ReaderAcquireSuccess")
		elseif reason == "book" then
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_ReaderAcquireFailBook")
		elseif reason == "tools" then
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_AcquireFailTools")
		elseif reason == "materials" then
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_ReaderAcquireFailMaterials")
		else
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_CraftFail")
		end
		gsSendServerCommand(player, "actionResult", { ok = ok, message = msg })

	elseif command == "programDisk" then
		-- Mecánica de "programar" disquetes (clic derecho en el disquete en
		-- blanco) - ver GS_DiskProgramming.lua. Nunca confía en lo que dijo
		-- el cliente: revalida receta aprendida + terminal cerca + disquete
		-- en blanco aquí.
		local ok, reason = GlobalStorageSiK.DiskProgramming.program(player, args.programId)
		local msg
		if ok then
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_ProgramDiskSuccess")
		elseif reason == "book" then
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_ProgramDiskFailBook")
		elseif reason == "terminal" then
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_ProgramDiskFailTerminal")
		elseif reason == "materials" then
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_ProgramDiskFailMaterials")
		else
			msg = GlobalStorageSiK.I18n.remote("IGUI_GS_CraftFail")
		end
		gsSendServerCommand(player, "actionResult", { ok = ok, message = msg })

	elseif command == "craftAddonModule" then
		local ok, message = GlobalStorageSiK.AddonRecipes.craftModule(player, args.addonId)
		gsSendServerCommand(player, "actionResult", {
			ok = ok,
			message = message,
			recipeId = GlobalStorageSiK.AddonRecipes.recipeCardId(args.addonId),
		})

	elseif command == "getNetworkList" then
		local list = {}
		if GlobalStorageSiK.NetworkManager then
			list = GlobalStorageSiK.NetworkManager.listForPlayer(player)
		end
		gsSendServerCommand(player, "networkList", {
			networks = list,
			activeNetworkId = GlobalStorageSiK.NetworkManager
				and GlobalStorageSiK.NetworkManager.getPlayerSessionNetwork(player),
		})

	elseif command == "deleteSuspendedNetwork" then
		-- `networkId` sigue siendo la red del terminal desde el que se administra;
		-- targetNetworkId es la red suspendida a eliminar. Asi se conserva la
		-- validacion de acceso fisico/tableta a una red activa sin pretender abrir
		-- una sesion contra una red que, por definicion, no tiene terminal activo.
		if not requireTerminalAccess(player, networkId) then return end
		local targetId = args.targetNetworkId
		if type(targetId) ~= "string" or targetId == "" or #targetId > 128 then
			gsSendServerCommand(player, "actionResult", { ok = false,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_NetworkNotFoundMsg") })
			return
		end
		local acquired = GlobalStorageSiK.TransferLock.acquire(targetId, player, "deleteNetwork")
		if not acquired then
			gsSendServerCommand(player, "actionResult", { ok = false,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_NetworkDeleteBusy") })
			return
		end
		local callOk, ok, reason, deleted = pcall(
			GlobalStorageSiK.NetworkManager.deleteSuspendedNetwork, player, targetId)
		GlobalStorageSiK.TransferLock.release(targetId, player)
		if not callOk then
			GlobalStorageSiK.Log.error("Server", "deleteSuspendedNetwork", tostring(ok))
			gsSendServerCommand(player, "actionResult", { ok = false,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_InternalTransferError") })
			return
		end
		if not ok then
			local key = reason == "owner_only" and "IGUI_GS_NetworkDeleteOwnerOnly"
				or (reason == "active_terminals" and "IGUI_GS_NetworkDeleteActive")
				or (reason == "network_busy" and "IGUI_GS_NetworkDeleteBusy")
				or "IGUI_GS_NetworkNotFoundMsg"
			gsSendServerCommand(player, "actionResult", {
				ok = false, message = GlobalStorageSiK.I18n.remote(key),
			})
			return
		end
		clearDeletedNetworkReferences(targetId)
		broadcastNetworkLists()
		gsSendServerCommand(player, "actionResult", {
			ok = true,
			message = GlobalStorageSiK.I18n.remote("IGUI_GS_NetworkDeleted",
				deleted and deleted.name or targetId,
				deleted and deleted.zones or 0, deleted and deleted.nodes or 0),
		})

	elseif command == "setActiveNetwork" then
		local ok, reason = false, "error"
		local requestedId = GlobalStorageSiK.Network.resolveNetworkId(args.networkId)
		local requestedRegistry = GlobalStorageSiK.Network.getRegistry()
		local requestedNet = requestedId and requestedRegistry.networks
			and requestedRegistry.networks[requestedId] or nil
		if requestedNet and GlobalStorageSiK.TerminalRecord.countActive(requestedNet) == 0 then
			reason = "network_suspended"
			gsSendServerCommand(player, "actionResult", {
				ok = false,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_NetReactivateViaTerminal"),
			})
		elseif GlobalStorageSiK.NetworkManager then
			ok, reason = GlobalStorageSiK.NetworkManager.setPlayerSessionNetwork(player, args.networkId)
		end
		gsSendServerCommand(player, "activeNetworkSet", {
			ok = ok,
			networkId = args.networkId,
			reason = reason,
		})

	elseif command == "createNetwork" then
		local nid, err = nil, "error"
		if GlobalStorageSiK.NetworkManager then
			nid, err = GlobalStorageSiK.NetworkManager.createNetworkForPlayer(player, args.name)
		end
		if nid and ModData and ModData.transmit then
			ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		end
		gsSendServerCommand(player, "networkCreated", {
			ok = nid ~= nil,
			networkId = nid,
			message = err,
		})
		if nid then
			GlobalStorageSiK.Server.pushTerminalManifest(player)
		end

	elseif command == "getRecoveryNetworks" then
		local networks = {}
		if GlobalStorageSiK.TerminalRecovery and GlobalStorageSiK.TerminalRecovery.buildNetworksForPlayer then
			networks = GlobalStorageSiK.TerminalRecovery.buildNetworksForPlayer(player)
		end
		gsSendServerCommand(player, "recoveryNetworks", {
			networks = networks,
		})

	elseif command == "installTerminalReader" then
		handleInstallTerminalReader(player, args)

	elseif command == "suspendTerminal" then
		if args.x and args.y and args.z and GlobalStorageSiK.TerminalRegistry then
			local nid = args.gsnNetworkId
				or GlobalStorageSiK.Network.findNetworkIdAtTerminal(args.x, args.y, args.z)
			nid = GlobalStorageSiK.TerminalRegistry.suspendTerminalAt(nid, args.x, args.y, args.z)
			GlobalStorageSiK.Log.info("Server", "suspendTerminal",
				string.format("%d,%d,%d network=%s user=%s",
					args.x, args.y, args.z, tostring(nid), player:getUsername()))
			ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
			GlobalStorageSiK.Server.pushTerminalManifest(player)
			if nid then
				gsSendServerCommand(player, "terminalRelocated", {
					networkId = nid,
					action = "suspended",
				})
			end
		end

	elseif command == "uninstallTerminalReader" then
		-- Desinstalar (metodo nuevo): el ordenador se queda exactamente
		-- donde esta, solo dejamos de reconocerlo como terminal. A
		-- diferencia de "removeTerminal" (borrado definitivo, solo admin),
		-- esto SUSPENDE la entrada del registro (se conserva la posicion,
		-- por si se reinstala ahi mismo mas adelante) - accesible a
		-- cualquier miembro con acceso a la red, no solo administradores,
		-- porque es reversible.
		if args.x and args.y and args.z then
			local x, y, z = math.floor(args.x), math.floor(args.y), math.floor(args.z)
			local nid = args.gsnNetworkId or GlobalStorageSiK.Network.findNetworkIdAtTerminal(x, y, z)
			if not nid or not requireNetworkPermission(player, nid) then
				return
			end
			clearTerminalObjectsAt(x, y, z)
			GlobalStorageSiK.TerminalRegistry.suspendTerminalAt(nid, x, y, z)
			GlobalStorageSiK.Log.info("Server", "uninstallTerminalReader",
				string.format("%d,%d,%d network=%s user=%s", x, y, z, tostring(nid), player:getUsername()))
			ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
			GlobalStorageSiK.Server.pushTerminalManifest(player)
			-- BUG REAL encontrado (feedback directo): a diferencia de
			-- "removeTerminal" (mas abajo), esta rama nunca reenviaba
			-- pushTerminalState - el panel de Red del jugador se quedaba
			-- mostrando el terminal como "presente" hasta el siguiente
			-- refresco natural (o hasta volver a abrir el terminal), aunque
			-- el servidor ya lo hubiera desinstalado correctamente.
			pushTerminalState(player, nid, nil, searchQuery)
		end

	elseif command == "unregisterTerminal" then
		if args.x and args.y and args.z and GlobalStorageSiK.TerminalRegistry then
			local nid = args.gsnNetworkId
				or GlobalStorageSiK.Network.findNetworkIdAtTerminal(args.x, args.y, args.z)
			GlobalStorageSiK.TerminalRegistry.suspendTerminalAt(nid, args.x, args.y, args.z)
			ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
			GlobalStorageSiK.Server.pushTerminalManifest(player)
		end

	elseif command == "removeTerminal" then
		if args.x and args.y and args.z and GlobalStorageSiK.TerminalRegistry then
			local nid = args.gsnNetworkId
				or GlobalStorageSiK.Network.findNetworkIdAtTerminal(args.x, args.y, args.z)
			if not nid or not requireAdminAccess(player, nid) then
				return
			end
			GlobalStorageSiK.TerminalRegistry.unregister(nid, args.x, args.y, args.z)
			-- Limpiar moddata del objeto físico: impide que onObjectAboutToBeRemoved
			-- re-suspenda la entrada, e impide que findNearestTerminal siga dando acceso.
			clearTerminalObjectsAt(args.x, args.y, args.z)
			-- Cerrar sesión del jugador que hizo la petición
			if GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.clearSession then
				GlobalStorageSiK.TerminalAccess.clearSession(player)
			end
			ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
			GlobalStorageSiK.Server.pushTerminalManifest(player)
			-- Enviar estado actualizado para refrescar la UI en tiempo real
			pushTerminalState(player, nid, nil, searchQuery)
		end

	elseif command == "renameTerminal" then
		if args.x and args.y and args.z and GlobalStorageSiK.TerminalRegistry then
			local x, y, z = math.floor(args.x), math.floor(args.y), math.floor(args.z)
			local nid = args.gsnNetworkId or GlobalStorageSiK.Network.findNetworkIdAtTerminal(x, y, z)
			if not nid or not requireNetworkPermission(player, nid) then
				return
			end
			local ok = GlobalStorageSiK.TerminalRegistry.renameTerminalAt(nid, x, y, z, args.name)
			if ok then
				GlobalStorageSiK.Log.info("Server", "renameTerminal",
					string.format("%d,%d,%d network=%s user=%s name=%s", x, y, z, tostring(nid), player:getUsername(), tostring(args.name)))
				pushTerminalState(player, nid, nil, searchQuery)
			end
		end

	elseif command == "setTerminalController" then
		if args.x and args.y and args.z and GlobalStorageSiK.TerminalRegistry then
			local x, y, z = math.floor(args.x), math.floor(args.y), math.floor(args.z)
			local nid = args.gsnNetworkId or GlobalStorageSiK.Network.findNetworkIdAtTerminal(x, y, z)
			if not nid or not requireAdminAccess(player, nid) then
				return
			end
			local ok, reason = GlobalStorageSiK.TerminalRegistry.setControllerAt(nid, x, y, z)
			if ok then
				GlobalStorageSiK.Log.info("Server", "setTerminalController",
					string.format("%d,%d,%d network=%s user=%s", x, y, z, tostring(nid), player:getUsername()))
				pushTerminalState(player, nid, nil, searchQuery)
			else
				gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_MarkMainFailed", tostring(reason)) })
			end
		end

	elseif command == "searchItems" then
		if not requireTerminalAccess(player, networkId) then
			return
		end
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "bulkDeposit" then
		if not requireTerminalAccess(player, networkId) then
			return
		end
		runLockedTransfer(player, networkId, "bulkDeposit", function()
			local summary = GlobalStorageSiK.Bulk.depositFromPlayer(player, networkId, args.sourceIndex)
			local msg = string.format("Guardados: %s | Omitidos: %s", tostring(summary.moved), tostring(summary.skipped))
			afterTransferSync(player, networkId, searchQuery, {
				suppressUi = summary.reason == "limit",
			})
			gsSendServerCommand(player, "actionResult", {
				ok = summary.moved > 0,
				message = msg,
				bulk = summary,
				transfer = {
					op = "bulkDeposit",
					networkId = networkId,
					moved = summary.moved or 0,
					skipped = summary.skipped or 0,
					failed = summary.failed or 0,
					inventoryRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId),
				},
			})
		end)

	elseif command == "depositItems" then
		local depositMeta = {
			queueId = type(args.queueId) == "string" and string.sub(args.queueId, 1, 96) or nil,
			transferOp = "depositItems",
		}
		if not requireTerminalAccess(player, networkId, depositMeta) then
			return
		end

		runLockedTransfer(player, networkId, "depositItems", function()
			local allowedOrigins = {
				player = true,
				player_queue = true,
				operation_abort_return = true,
				operation_complete_return = true,
				operation_result_deposit = true,
				operation_timeout_return = true,
			}
			local origin = type(args.origin) == "string" and args.origin or "player"
			if not allowedOrigins[origin] then
				origin = "player"
			end
			local operationId = type(args.operationId) == "string"
				and string.sub(args.operationId, 1, 96) or nil
			local queueId = type(args.queueId) == "string"
				and string.sub(args.queueId, 1, 96) or nil
			local requested = 0
			if args.mode == "partial" then
				requested = tonumber(args.count) or 0
			elseif args.mode == "container" then
				requested = 1
			elseif type(args.itemIds) == "table" then
				requested = #args.itemIds
			end
			local summary = GlobalStorageSiK.InventorySync.withBatch(function()
				if args.mode == "container" and args.referenceItemId then
					return GlobalStorageSiK.Deposit.depositFromContainer(player, networkId, args.referenceItemId)
				elseif args.mode == "partial" and args.referenceItemId and args.count then
					return GlobalStorageSiK.Deposit.depositPartialCount(player, networkId, args.referenceItemId, args.count)
				end
				return GlobalStorageSiK.Deposit.depositByIds(player, networkId, args.itemIds or {})
			end)

			local msg = GlobalStorageSiK.Deposit.formatSummaryMessage(summary)
			local logFn = summary.reason == "limit" and GlobalStorageSiK.Log.detail
				or GlobalStorageSiK.Log.info
			logFn("Deposit", "depositItems origin=" .. tostring(origin)
				.. " operationId=" .. tostring(operationId)
				.. " queueId=" .. tostring(queueId)
				.. " requested=" .. tostring(requested)
				.. " moved=" .. tostring(summary.moved or 0)
				.. " skipped=" .. tostring(summary.skipped or 0)
				.. " failed=" .. tostring(summary.failed or 0)
				.. " reason=" .. tostring(summary.reason))
			afterTransferSync(player, networkId, searchQuery, {
				suppressUi = summary.reason == "limit",
			})
			gsSendServerCommand(player, "actionResult", {
				ok = (summary.moved or 0) > 0,
				message = msg,
				queueId = queueId,
				deposit = summary,
				transfer = {
					op = "deposit",
					networkId = networkId,
					moved = summary.moved or 0,
					skipped = summary.skipped or 0,
					failed = summary.failed or 0,
					origin = origin,
					operationId = operationId,
					inventoryRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId),
					reason = summary.reason,
				},
			})
		end, depositMeta)

	elseif command == "withdrawItem" then
		local withdrawId = type(args.withdrawId) == "string"
			and string.sub(args.withdrawId, 1, 96) or nil
		local withdrawMeta = {
			withdrawId = withdrawId,
			transferOp = "withdrawItem",
		}
		if not requireTerminalAccess(player, networkId, withdrawMeta) then
			return
		end
		runLockedTransfer(player, networkId, "withdrawItem", function()
			local dest = nil
			if args.targetKey and args.targetKey ~= "" then
				dest = GlobalStorageSiK.DepositSources.resolveContainerKey(player, args.targetKey)
				if dest and (GlobalStorageSiK.DepositSources.isNetworkNodeContainer(dest)
					or not GlobalStorageSiK.DepositSources.canPlayerAccessContainer(player, dest)) then
					dest = nil
				end
			end

			local fullType = type(args.fullType) == "string"
				and string.sub(args.fullType, 1, 160) or nil
			local requested = math.floor(tonumber(args.amount) or 1)
			if requested <= 0 then requested = GlobalStorageSiK.Sandbox.getMaxItemsPerBulkTick() end
			requested = math.min(requested, GlobalStorageSiK.Sandbox.getMaxItemsPerBulkTick())
			-- El conteo completo previo duplicaba el escaneo de toda la red. Cada
			-- petición ya es un micro-lote acotado; movemos y replicamos ese lote
			-- antes de confirmar al cliente, que decide si queda otro.
			local ok, reason, moved = GlobalStorageSiK.InventorySync.withBatch(function()
				return GlobalStorageSiK.Transfer.withdrawType(
					player, fullType, networkId, requested, dest
				)
			end)

			-- Texto vía I18n (nunca literales con acentos incrustados en el
			-- .lua: se han visto mostrar "?" en vez de la tilde en cliente).
			local msg
			if ok then
				if moved and moved > 0 and requested > 0 and moved < requested then
					msg = GlobalStorageSiK.I18n.remote("IGUI_GS_WithdrawnPartial", tostring(moved), tostring(requested))
				else
					msg = GlobalStorageSiK.I18n.remote("IGUI_GS_WithdrawnCount", tostring(moved or 0))
				end
			else
				msg = GlobalStorageSiK.I18n.remote("IGUI_GS_WithdrawErrorReason", tostring(reason or "?"))
			end

			if (moved or 0) > 0 then
				afterTransferSync(player, networkId, searchQuery)
			end
			gsSendServerCommand(player, "actionResult", {
				ok = ok,
				message = msg,
				withdrawId = withdrawId,
				transfer = {
					op = "withdraw",
					networkId = networkId,
					fullType = fullType,
					requested = requested,
					moved = moved or 0,
					inventoryRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId),
					reason = reason,
				},
			})
		end, withdrawMeta)

	elseif command == "craftAttemptStart" then
		-- Solo diagnostico (ver newOperationId en GS_NetworkCraftSession.lua) -
		-- no valida acceso ni cambia nada, unicamente registra el operationId
		-- de este intento para correlacionar craftClaimItem/CraftDiag.
		lastOperationByPlayer[player:getPlayerNum()] = args.operationId
		lastNetworkIdByPlayer[player:getPlayerNum()] = args.networkId
		-- itemsRedAntes: diagnostico de dupeo (2026-08-16) - total de items en
		-- TODOS los contenedores de la red ANTES de que empiece este intento
		-- de crafteo, para comparar contra itemsRedDespues en craftAttempt
		-- RESULT y confirmar que la diferencia es exactamente la esperada.
		GlobalStorageSiK.Log.info("CraftDiag", string.format(
			"craftAttempt START operationId=%s addonId=%s recipe=%s networkId=%s isCanBeDoneFromFloor=%s containersCliente=%s itemsRedAntes=%s",
			tostring(args.operationId), tostring(args.addonId), tostring(args.recipe),
			tostring(args.networkId), tostring(args.isCanBeDoneFromFloor), tostring(args.containersCliente),
			tostring(countNetworkItems(args.networkId))))

	elseif command == "craftClaimItem" then
		-- Mueve al inventario del jugador, DE FORMA AUTORITATIVA EN SERVIDOR,
		-- un ítem concreto (por ID) de un contenedor de la red - usado por
		-- GS_NetworkCraftSession.lua (Craft/Build) para que un ingrediente/
		-- herramienta de red sea utilizable sin caminar. CRITICO: antes esa
		-- sesion llamaba a GS_InventorySync.moveBetween directamente desde
		-- codigo CLIENTE - en servidor dedicado (isServer()==false en ese
		-- cliente) eso solo movia el item en la vista LOCAL del cliente, sin
		-- tocar el estado real del servidor, y la comprobacion de consumo
		-- (HandcraftLogic/ISBuildIsoEntity.ConsumeBuildEntityItems, ambas
		-- corren en servidor) nunca encontraba el item -> "consume failed" /
		-- receta completa la barra pero no produce nada. Este comando hace el
		-- movimiento real donde de verdad importa.
		if not requireTerminalAccess(player, networkId) then
			return
		end
		runLockedTransfer(player, networkId, "craftClaimItem", function()
			local itemId = args.itemId
			local item, container = findNetworkItemById(networkId, itemId, player)
			local fullType = item and item.getFullType and item:getFullType() or "?"
			local ok = false
			if item and container then
				ok = GlobalStorageSiK.InventorySync.moveBetween(container, player:getInventory(), item, player)
			end
			GlobalStorageSiK.Log.info("CraftDiag", string.format(
				"claimReceive operationId=%s itemId=%s fullType=%s claimResult=%s",
				tostring(args.operationId), tostring(itemId), tostring(fullType), ok and "ok" or "failed"))
			-- Cada claim ya recibe un actionResult pequeno. Reconstruir y enviar
			-- el indice entero por ingrediente/herramienta multiplicaba el trafico
			-- en recetas de varias unidades; el refresco visual llega al cierre de
			-- la operacion o en la siguiente peticion explicita del terminal.
			afterTransferSync(player, networkId, searchQuery, { suppressUi = true })
			gsSendServerCommand(player, "actionResult", {
				ok = ok,
				message = ok and GlobalStorageSiK.I18n.remote("IGUI_GS_CraftClaimOk") or GlobalStorageSiK.I18n.remote("IGUI_GS_CraftClaimFail"),
				craftClaim = { itemId = itemId, ok = ok },
			})
		end)

	elseif command == "rescanZone" then
		if not requireTerminalAccess(player, networkId) then
			return
		end
		if GlobalStorageSiK.RedistributeJob.isActive(networkId) then
			requireNetworkConfigIdle(player, networkId)
			return
		end
		local zoneId = args.zoneId
		if not zoneId or zoneId == "" then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_InvalidZone") })
			return
		end
		startIncrementalScan(player, networkId, searchQuery, zoneId)

	elseif command == "redistributeNetwork" then
		if not requireAutoSortAccess(player, networkId, {
			jobType = "redistribute",
			jobState = "finished",
		}) then
			return
		end
		-- Un solo clic: el job conserva captura/cursor y ejecuta pasos acotados
		-- hasta terminar, sin volver a escanear toda la red en cada tick.
		if GlobalStorageSiK.RedistributeJob.isActive(networkId) then
			GlobalStorageSiK.RedistributeJob.addWatcher(player, networkId)
			gsSendServerCommand(player, "actionResult", {
				ok = true,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_RedistributeInProgress"),
				jobType = "redistribute",
				jobState = "running",
			})
		else
			GlobalStorageSiK.RedistributeJob.start(player, networkId)
			notifyRedistributeStartedToWatchers(player, networkId)
			gsSendServerCommand(player, "actionResult", {
				ok = true,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_RedistributingNetwork"),
				jobType = "redistribute",
				jobState = "running",
			})
		end

	elseif command == "renameZone" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		if not requireNetworkConfigIdle(player, networkId) then return end
		local registry = GlobalStorageSiK.Zones.getRegistry()
		local zone = registry.zones and registry.zones[args.zoneId]
		if not zone or not args.name or args.name == "" then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_InvalidZone") })
			return
		end
		zone.name = args.name
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", { ok = true, message = GlobalStorageSiK.I18n.remote("IGUI_GS_ZoneRenamedMsg") })
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "deleteZone" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		if not requireNetworkConfigIdle(player, networkId) then return end
		local registry = GlobalStorageSiK.Zones.getRegistry()
		local zone = registry.zones and registry.zones[args.zoneId]
		if not zone then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_ZoneNotFoundMsg") })
			return
		end
		local zoneName = zone.name or args.zoneId
		local ok = GlobalStorageSiK.Zones.removeZone(args.zoneId)
		if not ok then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_ZoneDeleteFailedMsg") })
			return
		end
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", { ok = true, message = GlobalStorageSiK.I18n.remote("IGUI_GS_ZoneDeletedMsg", zoneName) })
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "updateNode" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		if not requireNetworkConfigIdle(player, networkId) then return end
		local registry = GlobalStorageSiK.Zones.getRegistry()
		local node = registry.nodes and registry.nodes[args.nodeId]
		if not node then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_ContainerNotFoundMsg") })
			return
		end
		if args.membership == "excluded" then
			node.membership = "excluded"
			node.enabled = false
		elseif args.membership == "active" then
			node.membership = "active"
			node.enabled = true
		end
		if args.displayName and args.displayName ~= "" then
			node.displayName = args.displayName
		end
		if args.category ~= nil then
			local cat = args.category
			if cat == "" or cat == "*" then
				node.categories = {}
			else
				node.categories = { cat }
			end
		elseif args.categoriesText ~= nil then
			node.categories = {}
			for part in string.gmatch(tostring(args.categoriesText), "[^,]+") do
				local trimmed = part:match("^%s*(.-)%s*$")
				if trimmed and trimmed ~= "" then
					table.insert(node.categories, trimmed)
				end
			end
		elseif args.categories ~= nil then
			node.categories = sanitizeNodeCategories(args.categories)
		end
		if args.enabled ~= nil then
			node.enabled = args.enabled == true
		end
		if args.priority ~= nil then
			-- Escala 1-100, 1 = maxima prioridad (coherente con zone.priority).
			local p = tonumber(args.priority)
			if p then
				p = math.floor(p + 0.5)
				if p < 1 then p = 1 elseif p > 100 then p = 100 end
			end
			node.priority = p
		end
		if args.notes ~= nil then
			local notes = tostring(args.notes):gsub("^%s*(.-)%s*$", "%1")
			node.notes = (notes ~= "") and notes:sub(1, 120) or nil
		end
		if args.filters ~= nil then
			-- Pegado de plantilla: reemplazo completo, acotado y validado. Un
			-- payload malformado no conserva referencias del cliente ni supera el
			-- mismo maximo de 20 reglas que el editor individual.
			node.filters = {}
			if type(args.filters) == "table" then
				for i = 1, math.min(#args.filters, 20) do
					local clean = sanitizeNodeFilter(args.filters[i])
					if clean then node.filters[#node.filters + 1] = clean end
				end
			end
		elseif args.addFilter ~= nil then
			-- Añade UN filtro (validado aquí, nunca se confía en la forma
			-- exacta que mandó el cliente). Límite razonable por nodo para
			-- que la lista de filtros no crezca sin control.
			local clean = sanitizeNodeFilter(args.addFilter)
			if clean then
				node.filters = node.filters or {}
				if #node.filters < 20 then
					table.insert(node.filters, clean)
				end
			end
		end
		if args.removeFilterIndex ~= nil then
			local idx = tonumber(args.removeFilterIndex)
			if idx and node.filters and node.filters[idx] then
				table.remove(node.filters, idx)
			end
		end
		if GlobalStorageSiK.NodeNaming and GlobalStorageSiK.NodeNaming.applyToNode then
			GlobalStorageSiK.NodeNaming.applyToNode(node)
		end
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", {
			ok = true,
			message = GlobalStorageSiK.I18n.remote("IGUI_GS_ContainerUpdatedMsg"),
			containerUpdated = true,
			nodeId = args.nodeId,
			displayName = node.displayName,
		})
		pushTerminalState(player, networkId, nil, searchQuery)
		-- Difundir a los demas miembros online con acceso: sin esto, un cambio
		-- de nombre/categoria/prioridad de OTRO jugador no se veia hasta que
		-- el resto tocara algo que disparase su propio refresco.
		pushNodeChangeToNetworkWatchers(player, networkId, searchQuery)

	elseif command == "applyNodeTemplateToZone" then
		if not requireAdminAccess(player, networkId) then return end
		if not requireNetworkConfigIdle(player, networkId) then return end
		local registry = GlobalStorageSiK.Zones.getRegistry()
		local zone = registry.zones and registry.zones[args.zoneId]
		if not zone or zone.networkId ~= networkId then
			gsSendServerCommand(player, "actionResult", {
				ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_ZoneNotFoundMsg"),
			})
			return
		end
		local categories = sanitizeNodeCategories(args.categories)
		local filters = {}
		if type(args.filters) == "table" then
			for i = 1, math.min(#args.filters, 20) do
				local clean = sanitizeNodeFilter(args.filters[i])
				if clean then filters[#filters + 1] = clean end
			end
		end
		local priority = tonumber(args.priority)
		if not priority then
			gsSendServerCommand(player, "actionResult", {
				ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_PriorityChangeFailedMsg"),
			})
			return
		end
		priority = math.floor(priority + 0.5)
		if priority < 1 then priority = 1 elseif priority > 100 then priority = 100 end
		local updated = 0
		for _, target in pairs(registry.nodes or {}) do
			if target.zoneId == zone.id then
				target.categories = {}
				for i = 1, #categories do target.categories[i] = categories[i] end
				target.filters = cloneNodeFilters(filters)
				target.priority = priority
				updated = updated + 1
			end
		end
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", {
			ok = true,
			message = GlobalStorageSiK.I18n.remote("IGUI_GS_ZoneTemplateAppliedMsg", updated, zone.name or zone.id),
		})
		pushTerminalState(player, networkId, nil, searchQuery)
		pushNodeChangeToNetworkWatchers(player, networkId, searchQuery)

	elseif command == "createZoneRoom" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		if not requireNetworkConfigIdle(player, networkId) then return end
		local bounds = boundsFromPlayerRoom(player)

		if not bounds then

			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_NoRoom") })

			return

		end

		local zone = GlobalStorageSiK.Zones.createZone(GlobalStorageSiK.I18n.text("IGUI_GS_ZoneSourceRoom"), GlobalStorageSiK.Zones.SOURCE.ROOM, bounds, networkId)

		local ok, message = addZone(zone)

		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })

		if ok then
			startIncrementalScan(player, networkId, searchQuery, zone.id)
			pushTerminalState(player, networkId, { running = true, _freshSnapshotScope = "network" }, searchQuery)
		end

	elseif command == "moveZonePriority" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		if not requireNetworkConfigIdle(player, networkId) then return end
		local ok = GlobalStorageSiK.Zones.moveZonePriority(networkId, args.zoneId, args.direction)
		if ok then
			-- Cambiar prioridad no altera el inventario ni exige volver a recorrerlo.
			pushTerminalState(player, networkId, { _freshSnapshotScope = "network" }, searchQuery)
		else
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_PriorityChangeFailedMsg") })
		end

	elseif command == "setZonePriority" then
		-- Escala libre 1-100 (ver GS_Zones.setPriority), sustituye al sistema
		-- de posicion secuencial - usado por el modal de edicion de zona.
		if not requireAdminAccess(player, networkId) then
			return
		end
		if not requireNetworkConfigIdle(player, networkId) then return end
		local ok = GlobalStorageSiK.Zones.setPriority(networkId, args.zoneId, args.priority)
		if ok then
			ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
			pushTerminalState(player, networkId, nil, searchQuery)
		else
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_InvalidZone") })
		end

	elseif command == "createZoneStructure" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		if not requireNetworkConfigIdle(player, networkId) then return end
		local bounds, zoneName, source = GlobalStorageSiK.Zones.boundsFromStructure(player)
		if not bounds then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_NoBuildingOrSafehouse") })
			return
		end
		local zone = GlobalStorageSiK.Zones.createZone(zoneName or GlobalStorageSiK.I18n.text("IGUI_GS_ZoneSourceStructure"), source, bounds, networkId)
		if source == GlobalStorageSiK.Zones.SOURCE.SAFEHOUSE and bounds.safehouseId then
			zone.safehouseId = bounds.safehouseId
		end
		local ok, message = addZone(zone)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })
		if ok then
			startIncrementalScan(player, networkId, searchQuery, zone.id)
			pushTerminalState(player, networkId, { running = true, _freshSnapshotScope = "network" }, searchQuery)
		end

	elseif command == "createZoneBuilding" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		if not requireNetworkConfigIdle(player, networkId) then return end
		local bounds, buildingTitle = GlobalStorageSiK.Zones.boundsFromPlayerBuilding(player)
		if not bounds then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_NoBuilding") })
			return
		end
		local zoneName = buildingTitle or GlobalStorageSiK.I18n.text("IGUI_GS_ZoneSourceBuilding")
		local zone = GlobalStorageSiK.Zones.createZone(zoneName, GlobalStorageSiK.Zones.SOURCE.BUILDING, bounds, networkId)
		local ok, message = addZone(zone)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })
		if ok then
			startIncrementalScan(player, networkId, searchQuery, zone.id)
			pushTerminalState(player, networkId, { running = true, _freshSnapshotScope = "network" }, searchQuery)
		end

	elseif command == "createZoneSafehouse" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		if not requireNetworkConfigIdle(player, networkId) then return end
		if not GlobalStorageSiK.Sandbox.allowSafehouseImport() then

			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_SafehouseImportDisabledMsg") })

			return

		end

		local bounds = GlobalStorageSiK.Zones.boundsFromSafehouse(player:getSquare(), player)

		if not bounds then

			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_NoSafehouseMsg") })

			return

		end

		local name = bounds.title or GlobalStorageSiK.I18n.text("IGUI_GS_ZoneSourceSafehouse")

		local zone = GlobalStorageSiK.Zones.createZone(name, GlobalStorageSiK.Zones.SOURCE.SAFEHOUSE, bounds, networkId)

		zone.safehouseId = bounds.safehouseId

		local ok, message = addZone(zone)

		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })

		if ok then
			startIncrementalScan(player, networkId, searchQuery, zone.id)
			pushTerminalState(player, networkId, { running = true, _freshSnapshotScope = "network" }, searchQuery)
		end

	elseif command == "createZoneSelection" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		if not requireNetworkConfigIdle(player, networkId) then return end
		local b = args.bounds
		if not b or b.x1 == nil or b.y1 == nil or b.x2 == nil or b.y2 == nil then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_InvalidArea") })
			return
		end
		local bounds = {
			x1 = math.min(tonumber(b.x1) or 0, tonumber(b.x2) or 0),
			y1 = math.min(tonumber(b.y1) or 0, tonumber(b.y2) or 0),
			x2 = math.max(tonumber(b.x1) or 0, tonumber(b.x2) or 0),
			y2 = math.max(tonumber(b.y1) or 0, tonumber(b.y2) or 0),
			z = tonumber(b.z) or 0,
			zMax = tonumber(b.zMax) or tonumber(b.z) or 0,
		}
		local w = bounds.x2 - bounds.x1 + 1
		local h = bounds.y2 - bounds.y1 + 1
		if w < 1 or h < 1 or w > 200 or h > 200 then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_AreaSizeInvalid") })
			return
		end
		local zone = GlobalStorageSiK.Zones.createZone(GlobalStorageSiK.I18n.text("IGUI_GS_ZoneSourceSelection"), GlobalStorageSiK.Zones.SOURCE.SELECTION, bounds, networkId)
		local ok, message = addZone(zone)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })
		if ok then
			startIncrementalScan(player, networkId, searchQuery, zone.id)
			pushTerminalState(player, networkId, { running = true, _freshSnapshotScope = "network" }, searchQuery)
		end

	elseif command == "probeCraft" then
		local allowed, reason = GlobalStorageSiK.Permissions.canAccess(player, networkId)
		if not allowed then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_NoAccess") })
			return
		end
		local accessOk, _, _, accessReason = GlobalStorageSiK.TerminalAccess.evaluate(player, networkId)
		if not accessOk then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_NoTerminalAccessMsg") })
			return
		end
		local okProbe, probe = pcall(GlobalStorageSiK.CraftCatalog.probe, player, networkId)
		if not okProbe then
			probe = { error = tostring(probe), total = 0, validPlayer = 0, validNetwork = 0, validTerminalTags = 0 }
		end
		GlobalStorageSiK.Log.info("Server", "probeCraft",
			string.format("total=%d player=%d network=%d terminal=%d",
				probe.total or 0, probe.validPlayer or 0, probe.validNetwork or 0, probe.validTerminalTags or 0))
		gsSendServerCommand(player, "actionResult", { ok = true, message = GlobalStorageSiK.I18n.remote("IGUI_GS_RecipeAnalysisDone") })
		pushTerminalState(player, networkId, nil, searchQuery, probe)

	elseif command == "transferOwnership" then
		if not requireTerminalAccess(player, networkId) then
			return
		end
		local newOwner = args.newOwner and string.gsub(args.newOwner, "^%s*(.-)%s*$", "%1") or ""
		if newOwner == "" then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_EmptyUsername") })
			return
		end
		local targetPlayer = GlobalStorageSiK.Permissions.findOnlineCharacter(args.characterId or "")
		local ok, message
		if targetPlayer then
			ok, message = GlobalStorageSiK.Permissions.transferOwnerToCharacter(
				networkId, player, targetPlayer, args.keepFormerOwner == true)
		elseif args.characterId and args.characterId ~= "" then
			ok = false
			message = GlobalStorageSiK.I18n.remote("IGUI_GS_PermCharacterNameEmptyMsg")
		else
			ok, message = GlobalStorageSiK.Permissions.transferOwner(
				networkId, player, newOwner, args.keepFormerOwner == true)
		end
		if ok then
			ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
			GlobalStorageSiK.Log.info("Server", "transferOwnership", player:getUsername() .. " -> " .. newOwner)
		end
		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })
		if ok then
			pushTerminalState(player, networkId, nil, searchQuery)
		end

	elseif command == "addFactionMembers" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		local ok, message = GlobalStorageSiK.Permissions.addAllFactionMembers(networkId, player)
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })
		if ok then
			pushTerminalState(player, networkId, nil, searchQuery)
		end

	elseif command == "addCategory" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		if not requireNetworkConfigIdle(player, networkId) then return end
		local ok = GlobalStorageSiK.Categories.add(networkId, args.name)
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = ok and GlobalStorageSiK.I18n.remote("IGUI_GS_CategoryAdded") or GlobalStorageSiK.I18n.remote("IGUI_GS_CategoryDuplicate") })
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "addPermissionUser" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		local target = GlobalStorageSiK.Permissions.findOnlineCharacter(args.characterId or "")
		local ok = false
		local failureMessage = GlobalStorageSiK.I18n.remote("IGUI_GS_UserAlreadyExists")
		local permissionSource = "legacy_name"
		if target then
			permissionSource = "online_character"
			ok = GlobalStorageSiK.Permissions.addCharacter(networkId, target)
		elseif args.factionUsername and args.factionUsername ~= "" then
			permissionSource = "offline_faction_member"
			-- Miembro offline: Faction persiste usernames, no objetos IsoPlayer.
			-- El servidor valida que siga perteneciendo a la facción del actor;
			-- canAccess lo vinculará al ID del personaje al conectarse.
			ok = GlobalStorageSiK.Permissions.addFactionUsername(
				networkId, player, string.sub(tostring(args.factionUsername), 1, 64))
		elseif args.characterId and args.characterId ~= "" then
			-- Un selector moderno nunca degrada un ID caducado o manipulado a una
			-- coincidencia por nombre. El roster debe refrescarse y elegirse de
			-- nuevo; así dos nombres Unicode iguales no pueden cruzar permisos.
			permissionSource = "invalid_character_id"
			failureMessage = GlobalStorageSiK.I18n.remote("IGUI_GS_PermSelectionStale")
		elseif not args.characterId or args.characterId == "" then
			-- Compatibilidad con clientes anteriores durante la transición.
			ok = GlobalStorageSiK.Permissions.addUser(networkId, args.characterName or args.username)
		end
		local loggedTarget = string.sub(tostring(
			args.factionUsername or args.characterName or args.username or ""), 1, 64)
		loggedTarget = string.gsub(loggedTarget, "[\r\n]", " ")
		local loggedCharacterId = string.sub(tostring(args.characterId or ""), 1, 96)
		loggedCharacterId = string.gsub(loggedCharacterId, "[\r\n]", " ")
		GlobalStorageSiK.Log.info("Permissions", "addPermissionUser",
			"source=" .. permissionSource
				.. " target=" .. loggedTarget
				.. " characterId=" .. loggedCharacterId
				.. " ok=" .. tostring(ok))
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = ok and GlobalStorageSiK.I18n.remote("IGUI_GS_UserAdded") or failureMessage })
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "leaveNetwork" then
		-- Abandonar la propia fila esta siempre permitido sin importar el
		-- rol (member/admin/owner) - solo hace falta pertenecer a la red,
		-- nunca requireAdminAccess. Si es el owner, GS_Permissions.leaveNetwork
		-- dispara la misma sucesion automatica que al morir.
		if not requireNetworkPermission(player, networkId) then
			return
		end
		local ok, message = GlobalStorageSiK.Permissions.leaveNetworkPlayer(networkId, player)
		if ok then
			ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		end
		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })
		if ok then
			pushTerminalState(player, networkId, nil, searchQuery)
		end

	elseif command == "removePermissionUser" then
		if not requireNetworkPermission(player, networkId) then
			return
		end
		-- Admin puede eliminar miembros; solo owner puede eliminar admins
		local target = args.username or ""
		local targetId = args.characterId or ""
		local registry = GlobalStorageSiK.Network.getRegistry()
		local net = registry.networks and registry.networks[networkId]
		local targetIsAdmin = false
		if net then
			local record = targetId ~= "" and net.characterPermissions and net.characterPermissions[targetId]
			if record then
				targetIsAdmin = record.role == GlobalStorageSiK.Permissions.ROLE_ADMIN
			else
				for i = 1, #(net.adminUsers or {}) do
					if net.adminUsers[i] == target then targetIsAdmin = true; break end
				end
			end
		end
		if targetIsAdmin and not GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId) then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_OnlyOwnerRemoveAdminsMsg") })
			return
		end
		if not GlobalStorageSiK.Permissions.isAdminPlayer(player, networkId) then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_RequireAdminRole") })
			return
		end
		-- Limpiar también de adminUsers si era admin
		if net then
			for i = #(net.adminUsers or {}), 1, -1 do
				if net.adminUsers[i] == target then table.remove(net.adminUsers, i) end
			end
		end
		local ok
		if targetId ~= "" then
			ok = GlobalStorageSiK.Permissions.removeCharacter(networkId, targetId)
		else
			ok = GlobalStorageSiK.Permissions.removeUser(networkId, target)
		end
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = ok and GlobalStorageSiK.I18n.remote("IGUI_GS_UserRemovedMsg") or GlobalStorageSiK.I18n.remote("IGUI_GS_UserNotFoundToRemoveMsg") })
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "setMemberRole" then
		if not GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId) then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_OnlyOwnerChangeRolesMsg") })
			return
		end
		local ok
		if args.characterId and args.characterId ~= "" then
			ok = GlobalStorageSiK.Permissions.setCharacterRole(networkId, args.characterId, args.role or "member")
		else
			ok = GlobalStorageSiK.Permissions.setUserRole(networkId, args.username or "", args.role or "member")
		end
		if ok then ModData.transmit(GlobalStorageSiK.MODDATA_KEY) end
		gsSendServerCommand(player, "actionResult", { ok = ok, message = ok and GlobalStorageSiK.I18n.remote("IGUI_GS_RoleUpdatedMsg") or GlobalStorageSiK.I18n.remote("IGUI_GS_RoleUpdateFailedMsg") })
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "setMemberZoneAccess" then
		if not requireAdminAccess(player, networkId) then return end
		local deniedZoneIds = type(args.deniedZoneIds) == "table" and args.deniedZoneIds or {}
		if #deniedZoneIds > 512 then
			gsSendServerCommand(player, "actionResult", {
				ok = false,
				message = GlobalStorageSiK.I18n.remote("IGUI_GS_MemberZoneAccessFailed"),
			})
			return
		end
		local ok = GlobalStorageSiK.Permissions.setMemberZoneDenials(
			networkId,
			tostring(args.characterId or ""),
			tostring(args.username or ""),
			deniedZoneIds)
		if ok then ModData.transmit(GlobalStorageSiK.MODDATA_KEY) end
		gsSendServerCommand(player, "actionResult", {
			ok = ok,
			message = GlobalStorageSiK.I18n.remote(ok
				and "IGUI_GS_MemberZoneAccessUpdated"
				or "IGUI_GS_MemberZoneAccessFailed"),
		})
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "setFactionOnly" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		local registry = GlobalStorageSiK.Zones.getRegistry()
		GlobalStorageSiK.Permissions.ensure(registry, networkId)
		registry.networks[networkId].factionOnly = args.enabled == true
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", { ok = true, message = GlobalStorageSiK.I18n.remote("IGUI_GS_PermissionsUpdatedMsg") })
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "renameNetwork" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		if not GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId) then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_OnlyOwnerRenameNetworkMsg") })
			return
		end
		local ok, message = GlobalStorageSiK.Network.renameDisplayName(networkId, player:getUsername(), args.name)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })
		if ok then
			pushTerminalState(player, networkId, nil, searchQuery)
		end

	elseif command == "addPermissionFaction" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		-- BUG REAL encontrado (reportado 2026-08-16, "el permiso facción es
		-- incorrecto, debería añadir a todos los miembros de forma
		-- individual, el acceso nominal SI funciona"): esto llamaba a
		-- GlobalStorageSiK.Permissions.addFaction, que guarda un permiso de
		-- facción APARTE (net.allowedFactions) - un mecanismo distinto del
		-- acceso individual (net.allowedUsers) ya confirmado como el unico
		-- que de verdad funciona. Ademas tenia un bug propio: comparaba el
		-- nombre de facción guardado (normalizado a minusculas por
		-- addFaction) contra playerFaction:getName() SIN normalizar en
		-- canAccess - "sik-gs" nunca era igual a "SiK-GS", asi que el acceso
		-- por facción no concedia nada en la practica. En vez de arreglar
		-- ese mecanismo, se sustituye por el que ya existia y SI funciona:
		-- addAllFactionMembers expande la facción del jugador que pulsa
		-- "Añadir" a un acceso individual (net.allowedUsers) por cada
		-- miembro, mismo mecanismo ya confirmado.
		local ok, message = GlobalStorageSiK.Permissions.addAllFactionMembers(networkId, player)
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "removePermissionFaction" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		local ok = GlobalStorageSiK.Permissions.removeFaction(networkId, args.factionName)
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = ok and GlobalStorageSiK.I18n.remote("IGUI_GS_FactionRemovedMsg") or GlobalStorageSiK.I18n.remote("IGUI_GS_FactionNotFoundMsg") })
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "installAddon" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		local anchor = GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
		if not anchor or not anchor.x then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_OpenTerminalInstallAddonsMsg") })
			return
		end
		local ok, message = GlobalStorageSiK.Addons.install(player, networkId, anchor, args.addonId)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })
		if ok then
			pushTerminalState(player, networkId, nil, searchQuery, nil, false, nil, anchor)
		end

	elseif command == "uninstallAddon" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		local anchor = GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
		if not anchor or not anchor.x then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_OpenTerminalRemoveAddonsMsg") })
			return
		end
		local ok, message = GlobalStorageSiK.Addons.uninstall(player, networkId, anchor, args.addonId)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })
		if ok then
			pushTerminalState(player, networkId, nil, searchQuery, nil, false, nil, anchor)
		end

	elseif command == "installFloppyDrive" then
		-- DEPRECADO: el Lector ahora es un addon mas (ver GS_ReaderAddon.lua),
		-- se instala via "installAddon" addonId=Reader igual que los demas -
		-- este comando se mantiene solo por si algun cliente desactualizado
		-- (bloque de UI ya retirado en la version actual) todavia lo envia.
		if not requireAdminAccess(player, networkId) then
			return
		end
		local anchor = GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
		if not anchor or not anchor.x then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_OpenTerminalInstallReaderMsg") })
			return
		end
		local ok, message = GlobalStorageSiK.Addons.install(player, networkId, anchor, "Reader")
		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })
		if ok then
			pushTerminalState(player, networkId, nil, searchQuery, nil, false, nil, anchor)
		end

	elseif command == "uninstallFloppyDrive" then
		-- DEPRECADO: ver nota en "installFloppyDrive" arriba.
		if not requireAdminAccess(player, networkId) then
			return
		end
		local anchor = GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
		if not anchor or not anchor.x then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_OpenTerminalRemoveReaderMsg") })
			return
		end
		local ok, message = GlobalStorageSiK.Addons.uninstall(player, networkId, anchor, "Reader")
		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })
		if ok then
			pushTerminalState(player, networkId, nil, searchQuery, nil, false, nil, anchor)
		end

	elseif command == "registerContainer" then

		local targetNetworkId = args.networkId or networkId
		if not requireNetworkConfigIdle(player, targetNetworkId) then return end

		local ok, message = registerContainer(args.entry, targetNetworkId)

		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })

	elseif command == "unregisterContainer" then

		local targetNetworkId = args.networkId or networkId
		if not requireNetworkConfigIdle(player, targetNetworkId) then return end

		local ok, message = unregisterContainer(args.containerId, targetNetworkId)

		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })

	elseif command == "requestItemIndex" then

		if not requireTerminalAccess(player, networkId) then
			return
		end

		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "getItemNetworkCounts" then
		local fullType = args.fullType
		local networks = {}
		local hasAnyNetwork = false
		if fullType and GlobalStorageSiK.Index and GlobalStorageSiK.Index.getNetworkCountsForItem then
			networks, hasAnyNetwork = GlobalStorageSiK.Index.getNetworkCountsForItem(player, fullType)
		end
		gsSendServerCommand(player, "itemNetworkCounts", {
			fullType = fullType,
			networks = networks,
			hasAnyNetwork = hasAnyNetwork,
		})

	end

end



Events.OnClientCommand.Add(onClientCommand)

-- Un unico flush de snapshots como maximo por tick, compartido por todas las
-- redes. Cuando no hay transferencias pendientes el coste es solo recorrer
-- una tabla vacia.
if Events and Events.OnTick then
	Events.OnTick.Add(function()
		flushPendingSnapshotSync()
		if flushPendingTerminalRefreshes then
			local ok, err = pcall(flushPendingTerminalRefreshes)
			if not ok then
				GlobalStorageSiK.Log.error("Server", "terminalRefreshQueue", tostring(err))
			end
		end
	end)
end

if Events and Events.OnCreatePlayer then
	Events.OnCreatePlayer.Add(function(playerIndexOrPlayer, eventPlayer)
		-- B42 normalmente entrega (playerIndex, player), pero conservar la
		-- forma de un solo IsoPlayer hace el hook tolerante a otros contextos.
		local player = eventPlayer
		if not player and type(playerIndexOrPlayer) ~= "number"
			and playerIndexOrPlayer and playerIndexOrPlayer.getUsername then
			player = playerIndexOrPlayer
		elseif not player and type(playerIndexOrPlayer) == "number" and getSpecificPlayer then
			player = getSpecificPlayer(playerIndexOrPlayer)
		end
		-- isAuthoritative(), no isServer() a pelo: en SP real isServer() da
		-- false y este handler entero (manifest + regalo retroactivo de
		-- recetas de manual) nunca corria al entrar a la partida. Este era
		-- el motivo real de que ensureManualRecipesGranted (llamada tambien
		-- desde handleOpenTerminal, pero eso exige abrir NUESTRA interfaz)
		-- nunca se ejecutara para un jugador que solo abre el menu de
		-- crafteo VANILLA sin haber abierto antes el terminal - cero lineas
		-- de log con DebugMode porque la funcion jamas llegaba a correr.
		if not player or not GlobalStorageSiK.isAuthoritative() then
			return
		end
		-- Un personaje que acaba de entrar nunca hereda la suscripcion visual
		-- que pudiera quedar de una conexion anterior interrumpida.
		clearTerminalWatcher(player)
		if GlobalStorageSiK.Server.pushTerminalManifest then
			GlobalStorageSiK.Server.pushTerminalManifest(player)
		end
		if GlobalStorageSiK.CraftUtils and GlobalStorageSiK.CraftUtils.ensureManualRecipesGranted then
			GlobalStorageSiK.CraftUtils.ensureManualRecipesGranted(player)
		end
	end)
end

if Events and Events.OnPlayerDeath then
	Events.OnPlayerDeath.Add(function(player)
		-- Sucesion de propietario: sin esto, si el dueño de una red moria y
		-- no quedaba forma de recuperar el rol (net.owner deja de coincidir
		-- con cualquier personaje vivo), los admins/miembros restantes
		-- perdian para siempre las acciones exclusivas de owner (transferir,
		-- cambiar roles). isAuthoritative(), no isServer() a pelo: mismo
		-- gotcha de SP real que el resto de handlers de este fichero.
		if not player or not GlobalStorageSiK.isAuthoritative() then
			return
		end
		local charName = GlobalStorageSiK.Permissions.getCharacterName(player)
		if charName ~= "" and GlobalStorageSiK.Permissions.handleOwnerDeath then
			GlobalStorageSiK.Permissions.handleOwnerDeath(player)
		end
	end)
end

--- Diagnostico temporal (reporte 2026-08-13: crafteo remoto no consume
--- materiales ni entrega el objeto fabricado, INCLUSO con el ingrediente ya
--- confirmado en el inventario del jugador via craftClaimItem) - envuelve el
--- metodo que de verdad ejecuta el consumo/creacion en servidor
--- (ISHandcraftAction.performRecipe, codigo base del juego, ver
--- shared/Entity/TimedActions/ISHandcraftAction.lua) para registrar cuantos
--- contenedores via self.containers y cuantos items de salida crea de
--- verdad HandcraftLogic, en vez de seguir diagnosticando por logs
--- indirectos (craftClaimItem/actionResult no dicen nada del resultado real
--- del crafteo). Solo activo con DebugMode (sandbox), no toca el flujo real
--- (llama al original UNA sola vez, solo inspecciona el resultado despues).
--- Instalado dentro de OnInitGlobalModData (no a nivel de fichero) para que
--- el sandbox ya este disponible cuando se consulta debugMode().
local function installCraftDiagnostics()
	if not GlobalStorageSiK.Sandbox.debugMode() then
		return
	end
	if not ISHandcraftAction or not ISHandcraftAction.performRecipe or ISHandcraftAction._gsDiagInstalled then
		return
	end
	ISHandcraftAction._gsDiagInstalled = true
	local originalPerformRecipe = ISHandcraftAction.performRecipe
	ISHandcraftAction.performRecipe = function(self)
		local recipeName = "?"
		local okName, name = pcall(function() return self.craftRecipe and self.craftRecipe:getName() end)
		if okName and name then recipeName = name end
		local containersCount = 0
		local okCon, cnt = pcall(function() return self.containers and self.containers.size and self.containers:size() end)
		if okCon and cnt then containersCount = cnt end
		-- operationId: mejor esfuerzo (ver lastOperationByPlayer) - no hay
		-- forma de llevar nuestro propio operationId A TRAVES de la accion
		-- nativa, asi que se usa el ultimo conocido para este jugador; para
		-- un jugador crafteando de uno en uno (caso normal) coincide siempre.
		local operationId = "?"
		local networkId = nil
		local okPlayer, playerNum = pcall(function() return self.character and self.character:getPlayerNum() end)
		if okPlayer and playerNum and lastOperationByPlayer[playerNum] then
			operationId = lastOperationByPlayer[playerNum]
			networkId = lastNetworkIdByPlayer[playerNum]
		end
		originalPerformRecipe(self)
		local outCount = 0
		local okOut, list = pcall(function()
			local l = ArrayList.new()
			self.logic:getCreatedOutputItems(l)
			return l
		end)
		if okOut and list then outCount = list:size() end
		-- itemsRedDespues: comparar contra itemsRedAntes (craftAttempt START)
		-- - la diferencia esperada es "materiales consumidos de la red" menos
		-- (nunca mas), sin contar aun el resultado craftado (ese se deposita
		-- despues, via sweepPendingReturns/checkbox de deposito, no aqui).
		GlobalStorageSiK.Log.info("CraftDiag", string.format(
			"craftAttempt RESULT operationId=%s recipe=%s containers=%s resultCreated=%s itemsCreados=%s itemsRedDespues=%s",
			tostring(operationId), tostring(recipeName), tostring(containersCount),
			tostring(outCount > 0), tostring(outCount), tostring(countNetworkItems(networkId))))
	end
end

Events.OnInitGlobalModData.Add(function(isNewGame)
	-- ensureRegistry() normaliza networks/zones/nodes Y ya dispara las
	-- migraciones pendientes (NetworkMigrate.run/runV1070) internamente si
	-- es servidor; llamarla PRIMERO evita que la migracion se ejecute sobre
	-- un registro recien creado sin esas tablas (crash "attempted index:
	-- main of non-table: null" en una partida nueva). La llamada explicita
	-- a NetworkMigrate.run() de aqui era redundante y corria antes de la
	-- normalizacion.
	GlobalStorageSiK.Network.ensureRegistry(GlobalStorageSiK.Network.getRegistry())
	-- isAuthoritative(), no isServer() a pelo: en SP real isServer() da false
	-- y la reconciliacion de redes nunca corria al iniciar partida.
	if GlobalStorageSiK.isAuthoritative() then
		GlobalStorageSiK.Log.info("Server", "init", GlobalStorageSiK.Config.MOD_VERSION or "?")
		if GlobalStorageSiK.TerminalRegistry and GlobalStorageSiK.TerminalRegistry.reconcileAllNetworks then
			GlobalStorageSiK.TerminalRegistry.reconcileAllNetworks()
		end
		installCraftDiagnostics()
	end
end)


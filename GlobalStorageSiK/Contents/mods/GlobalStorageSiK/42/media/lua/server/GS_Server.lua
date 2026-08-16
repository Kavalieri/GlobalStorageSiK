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

--- playerNum -> IsoPlayer para jugadores que han enviado al menos un
--- comando con DebugMode activo - BUG REAL encontrado (reportado: "el log
--- CraftDiag del servidor no llega marcado [SRV] al cliente como el resto"):
--- el echo hook antiguo solo se instalaba DENTRO de onClientCommand, valido
--- solo mientras se procesaba ESE comando concreto - cualquier log que
--- ocurriera despues (ej. CraftDiag, que se dispara cuando termina la accion
--- de crafteo varios segundos mas tarde, fuera de cualquier comando) nunca
--- tenia el hook activo y se perdia sin marca [SRV]. Ahora se registra a
--- cada jugador que hable con DebugMode activo, y el hook (instalado UNA
--- vez, no por comando) reenvia a todos los registrados, sin importar
--- cuando se dispare el log.
local debugEchoPlayers = {}
local debugEchoHookInstalled = false

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

local function installDebugEchoHook()
	if debugEchoHookInstalled then
		return
	end
	debugEchoHookInstalled = true
	GlobalStorageSiK.Log._echoHook = function(line)
		for _, p in pairs(debugEchoPlayers) do
			sendServerCommand(p, GlobalStorageSiK.MOD_ID, "debugEcho", { line = line })
		end
	end
end

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



--- Cuenta tipos de ítem en contenedores vivos.

---@param networkId string

---@return number

local function countItemTypes(networkId)

	local rows = GlobalStorageSiK.Index.buildRows(networkId)

	return #rows

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

local function serializeNodes(networkId)
	local registry = GlobalStorageSiK.Zones.getRegistry()
	local list = {}

	for _, n in pairs(registry.nodes or {}) do
		local zone = registry.zones and registry.zones[n.zoneId]
		if zone and zone.networkId == networkId then
			table.insert(list, {
				id = n.id,
				displayName = n.displayName or n.name,
				name = n.name,
				vanillaName = n.name,
				zoneId = n.zoneId,
				zoneName = zone.name,
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

	local rows = GlobalStorageSiK.Index.buildRows(networkId)

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

	local nodesList = serializeNodes(networkId)

	return {

		networkId = networkId,

		networkName = GlobalStorageSiK.Network.getDisplayName(networkId),

		powered = GlobalStorageSiK.Power.networkPowered(networkId),

		fuelConsumption = GlobalStorageSiK.Power.serializeConsumption(#nodesList),

		scan = scanSummary or {},

		zones = serializeZones(networkId),

		terminals = serializeTerminals(networkId),

		nodes = nodesList,

		itemTypeCount = countItemTypes(networkId),

		items = rows,

		searchQuery = searchQuery or "",

		categories = GlobalStorageSiK.Categories.serialize(networkId),

		permissions = GlobalStorageSiK.Permissions.serialize(networkId, player),

		craftProbe = craftProbe,

		capacity = GlobalStorageSiK.NetworkCapacity.serialize(
			GlobalStorageSiK.NetworkCapacity.compute(networkId)
		),

		proximityRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange(),

		wirelessRange = GlobalStorageSiK.Sandbox.getWirelessRange(),


		inventoryRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId),

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
---@return boolean
local function requireNetworkPermission(player, networkId)
	local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(player, networkId))
	if allowed then
		return true
	end
	gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_NoAccess") })
	return false
end

--- Comprueba que el jugador tiene rol admin o superior; envía actionResult si falla.
---@param player IsoPlayer
---@param networkId string
---@return boolean
local function requireAdminAccess(player, networkId)
	if not requireNetworkPermission(player, networkId) then
		return false
	end
	if GlobalStorageSiK.Permissions.isAdminPlayer(player, networkId) then
		return true
	end
	gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_RequireAdminRole") })
	return false
end

--- Comprueba permisos y proximidad al terminal.
---@param player IsoPlayer
---@param networkId string
---@return boolean
local function requireTerminalAccess(player, networkId)
	if not requireNetworkPermission(player, networkId) then
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
	gsSendServerCommand(player, "actionResult", { ok = false, message = msg })
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
local function findNetworkItemById(networkId, itemId)
	local live = GlobalStorageSiK.Network.getLiveContainers(networkId)
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
---@return boolean ran
local function runLockedTransfer(player, networkId, op, fn)
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
		})
		return false
	end
	return true
end

--- Cuenta tipos por nodo VIVO (contenedor cargado) de una red, a partir de
--- registry.nodes[id].itemSnapshot - ya refrescado por
--- GlobalStorageSiK.Index.syncLiveSnapshots() justo antes en
--- afterTransferSync(). Usado para que la columna "Tipos" del listado de
--- nodos se actualice en el sync ligero tras depositar/retirar, sin esperar
--- a un pushTerminalState completo (BUG REAL reportado 2026-08-16: "la lista
--- de nodos no actualiza su cantidad de tipos distintos... retiré los items,
--- debería poner 0 pero no actualiza si no cierro y abro o cambio de
--- pestaña" - pushTerminalInventorySync solo mandaba agregados de red, nunca
--- por-nodo, y el cliente (refreshFromState) no tocaba terminalState.nodes
--- en absoluto en la rama inventorySync).
---@param networkId string
---@return table<string, number>
local function buildLiveNodeTypeCounts(networkId)
	local counts = {}
	local registry = GlobalStorageSiK.Zones.getRegistry()
	if not registry or not registry.nodes then
		return counts
	end
	local live = GlobalStorageSiK.Network.getLiveContainers(networkId)
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
		local payload = {
			networkId = networkId,
			items = GlobalStorageSiK.Index.buildRows(networkId),
			searchQuery = searchQuery or "",
			inventoryRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId),
			itemTypeCount = countItemTypes(networkId),
			nodeTypeCounts = buildLiveNodeTypeCounts(networkId),
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
		return
	end
	forEachOnlinePlayer(function(p)
		if actor and p == actor then
			return
		end
		local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(p, networkId))
		if not allowed then
			return
		end
		pushTerminalInventorySync(p, networkId, searchQuery)
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
local function afterTransferSync(actor, networkId, searchQuery)
	if not networkId then
		return
	end
	pcall(function()
		GlobalStorageSiK.Index.syncLiveSnapshots(networkId)
	end)
	pcall(function()
		GlobalStorageSiK.Index.bumpInventoryRevision(networkId, true)
	end)
	if actor then
		pushTerminalInventorySync(actor, networkId, searchQuery)
	end
	pushTerminalStateToNetworkWatchers(actor, networkId, searchQuery)
end

--- Envía estado del terminal al cliente.
---@param openUi boolean|nil true solo tras openTerminal exitoso
---@param accessMode string|nil physical|wireless|bypass
---@param terminalAnchor table|nil { x, y, z } terminal usado en el servidor
---@param meta table|nil { openSeq = number }
local function pushTerminalState(player, networkId, scanSummary, searchQuery, craftProbe, openUi, accessMode, terminalAnchor, meta)
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
		local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(p, networkId))
		if not allowed then
			return
		end
		pushTerminalState(p, networkId, nil, searchQuery)
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
	if GlobalStorageSiK.NetworkManager then
		GlobalStorageSiK.NetworkManager.setPlayerSessionNetwork(player, networkId)
	end

	local scanSummary = { added = 0, updated = 0, offline = 0, zones = 0 }

	if GlobalStorageSiK.Sandbox.rescanOnTerminalOpen() then
		scanSummary = GlobalStorageSiK.ZoneRefresh.refreshNetworkOnTerminalOpen(networkId)
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

local function onClientCommand(module, command, player, args)

	if module ~= GlobalStorageSiK.MOD_ID or not player then

		return

	end



	args = args or {}

	if GlobalStorageSiK.NetTrace and GlobalStorageSiK.NetTrace.logServerRecv then
		GlobalStorageSiK.NetTrace.logServerRecv(player, command, args)
	end

	-- Cuando debug activo, redirigir trazas del servidor a la consola del
	-- cliente - hook PERSISTENTE (ver installDebugEchoHook), no solo durante
	-- este comando, para que trazas asincronas (CraftDiag al terminar una
	-- accion de crafteo, varios segundos despues) tambien lleguen marcadas
	-- [SRV]. En SP real NUNCA se instala: cliente y servidor comparten la
	-- misma consola/print, asi que cada linea ya se ve una vez sola.
	if GlobalStorageSiK.Sandbox.debugMode() and not isTrueSingleplayer() then
		debugEchoPlayers[player:getPlayerNum()] = player
		installDebugEchoHook()
	end

	local networkId = GlobalStorageSiK.Network.resolveCommandNetworkId(player, args, command)

	local searchQuery = args.searchQuery



	if command == "openTerminal" then
		handleOpenTerminal(player, args, networkId, searchQuery)

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
			local scanSummary = { added = 0, updated = 0, offline = 0, zones = 0 }
			if GlobalStorageSiK.Sandbox.rescanOnTerminalOpen() then
				scanSummary = GlobalStorageSiK.ZoneRefresh.refreshNetworkOnTerminalOpen(networkId)
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
		local scanSummary = GlobalStorageSiK.ZoneRefresh.refreshNetworkOnTerminalOpen(networkId)
		local anchor = GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
		pushTerminalState(player, networkId, scanSummary, searchQuery, nil, false, nil, anchor)

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

	elseif command == "setActiveNetwork" then
		local ok, reason = false, "error"
		if GlobalStorageSiK.NetworkManager then
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
			afterTransferSync(player, networkId, searchQuery)
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
		if not requireTerminalAccess(player, networkId) then
			return
		end

		runLockedTransfer(player, networkId, "depositItems", function()
			local summary
			if args.mode == "container" and args.referenceItemId then
				summary = GlobalStorageSiK.Deposit.depositFromContainer(player, networkId, args.referenceItemId)
			elseif args.mode == "partial" and args.referenceItemId and args.count then
				summary = GlobalStorageSiK.Deposit.depositPartialCount(player, networkId, args.referenceItemId, args.count)
			else
				summary = GlobalStorageSiK.Deposit.depositByIds(player, networkId, args.itemIds or {})
			end

			local msg = GlobalStorageSiK.Deposit.formatSummaryMessage(summary)
			afterTransferSync(player, networkId, searchQuery)
			gsSendServerCommand(player, "actionResult", {
				ok = (summary.moved or 0) > 0,
				message = msg,
				deposit = summary,
				transfer = {
					op = "deposit",
					networkId = networkId,
					moved = summary.moved or 0,
					skipped = summary.skipped or 0,
					failed = summary.failed or 0,
					inventoryRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId),
					reason = summary.reason,
				},
			})
		end)

	elseif command == "withdrawItem" then
		if not requireTerminalAccess(player, networkId) then
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

			local fullType = args.fullType
			local requested = args.amount or 1
			local availableBefore = GlobalStorageSiK.Transfer.countAvailableUnits(networkId, fullType)

			local ok, reason, moved = GlobalStorageSiK.Transfer.withdrawType(
				player, fullType, networkId, requested, dest
			)

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

			afterTransferSync(player, networkId, searchQuery)
			gsSendServerCommand(player, "actionResult", {
				ok = ok,
				message = msg,
				transfer = {
					op = "withdraw",
					networkId = networkId,
					fullType = fullType,
					requested = requested,
					moved = moved or 0,
					available = availableBefore,
					inventoryRevision = GlobalStorageSiK.Index.getInventoryRevision(networkId),
					reason = reason,
				},
			})
		end)

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
			local item, container = findNetworkItemById(networkId, itemId)
			local fullType = item and item.getFullType and item:getFullType() or "?"
			local ok = false
			if item and container then
				ok = GlobalStorageSiK.InventorySync.moveBetween(container, player:getInventory(), item, player)
			end
			GlobalStorageSiK.Log.info("CraftDiag", string.format(
				"claimReceive operationId=%s itemId=%s fullType=%s claimResult=%s",
				tostring(args.operationId), tostring(itemId), tostring(fullType), ok and "ok" or "failed"))
			afterTransferSync(player, networkId, searchQuery)
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
		local zoneId = args.zoneId
		if not zoneId or zoneId == "" then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_InvalidZone") })
			return
		end
		local summary = GlobalStorageSiK.ZoneRefresh.refreshZone(networkId, zoneId)
		if not summary then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_ZoneNotFoundMsg") })
			return
		end
		local msg = GlobalStorageSiK.I18n.remote("IGUI_GS_ZoneRescannedMsg", summary.added or 0, summary.offline or 0, summary.outOfRange or 0)
		gsSendServerCommand(player, "actionResult", { ok = true, message = msg })
		pushTerminalState(player, networkId, summary, searchQuery)

	elseif command == "redistributeNetwork" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		-- Un solo click: RedistributeJob se relanza solo cada pocos segundos
		-- hasta terminar toda la red (respetando MaxItemsPerBulkTick por lote).
		if GlobalStorageSiK.RedistributeJob.isActive(networkId) then
			gsSendServerCommand(player, "actionResult", { ok = true, message = GlobalStorageSiK.I18n.remote("IGUI_GS_RedistributeInProgress") })
		else
			GlobalStorageSiK.RedistributeJob.start(player, networkId)
			gsSendServerCommand(player, "actionResult", { ok = true, message = GlobalStorageSiK.I18n.remote("IGUI_GS_RedistributingNetwork") })
		end

	elseif command == "renameZone" then
		if not requireAdminAccess(player, networkId) then
			return
		end
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
			node.categories = {}
			for i = 1, #args.categories do
				local cat = args.categories[i]
				if cat and cat ~= "" then
					table.insert(node.categories, cat)
				end
			end
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
		if args.addFilter ~= nil then
			-- Añade UN filtro (validado aquí, nunca se confía en la forma
			-- exacta que mandó el cliente). Límite razonable por nodo para
			-- que la lista de filtros no crezca sin control.
			local f = args.addFilter
			local clean = nil
			if f and f.type == "name" and f.value and tostring(f.value) ~= "" then
				local mode = f.mode
				if mode ~= "exact" and mode ~= "startsWith" and mode ~= "endsWith" then mode = "contains" end
				clean = { type = "name", mode = mode, value = tostring(f.value):sub(1, 60) }
			elseif f and f.type == "weight" and tonumber(f.value) then
				local mode = f.mode
				local allowed = { gt = true, lt = true, gte = true, lte = true, between = true, eq = true }
				if not allowed[mode] then mode = "eq" end
				clean = { type = "weight", mode = mode, value = tonumber(f.value) }
				if mode == "between" and tonumber(f.value2) then
					clean.value2 = tonumber(f.value2)
				end
			elseif f and f.type == "tag" and f.value and tostring(f.value) ~= "" then
				clean = { type = "tag", value = tostring(f.value):sub(1, 60) }
			elseif f and f.type == "item" and f.itemType and tostring(f.itemType) ~= "" then
				clean = { type = "item", itemType = tostring(f.itemType), itemDisplay = f.itemDisplay and tostring(f.itemDisplay):sub(1, 60) or nil }
			end
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

	elseif command == "createZoneRoom" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		local bounds = boundsFromPlayerRoom(player)

		if not bounds then

			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_NoRoom") })

			return

		end

		local zone = GlobalStorageSiK.Zones.createZone(GlobalStorageSiK.I18n.text("IGUI_GS_ZoneSourceRoom"), GlobalStorageSiK.Zones.SOURCE.ROOM, bounds, networkId)

		local ok, message = addZone(zone)

		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })

		if ok then

			local scan = GlobalStorageSiK.ZoneRefresh.refreshNetworkOnTerminalOpen(networkId)

			pushTerminalState(player, networkId, scan, searchQuery)

		end

	elseif command == "moveZonePriority" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		local ok = GlobalStorageSiK.Zones.moveZonePriority(networkId, args.zoneId, args.direction)
		if ok then
			local scan = GlobalStorageSiK.ZoneRefresh.refreshNetworkOnTerminalOpen(networkId)
			pushTerminalState(player, networkId, scan, searchQuery)
		else
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_PriorityChangeFailedMsg") })
		end

	elseif command == "setZonePriority" then
		-- Escala libre 1-100 (ver GS_Zones.setPriority), sustituye al sistema
		-- de posicion secuencial - usado por el modal de edicion de zona.
		if not requireAdminAccess(player, networkId) then
			return
		end
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
			local scan = GlobalStorageSiK.ZoneRefresh.refreshNetworkOnTerminalOpen(networkId)
			pushTerminalState(player, networkId, scan, searchQuery)
		end

	elseif command == "createZoneBuilding" then
		if not requireAdminAccess(player, networkId) then
			return
		end
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
			local scan = GlobalStorageSiK.ZoneRefresh.refreshNetworkOnTerminalOpen(networkId)
			pushTerminalState(player, networkId, scan, searchQuery)
		end

	elseif command == "createZoneSafehouse" then
		if not requireAdminAccess(player, networkId) then
			return
		end
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

			local scan = GlobalStorageSiK.ZoneRefresh.refreshNetworkOnTerminalOpen(networkId)

			pushTerminalState(player, networkId, scan, searchQuery)

		end

	elseif command == "createZoneSelection" then
		if not requireAdminAccess(player, networkId) then
			return
		end
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
			local scan = GlobalStorageSiK.ZoneRefresh.refreshNetworkOnTerminalOpen(networkId)
			pushTerminalState(player, networkId, scan, searchQuery)
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
		local ok, message = GlobalStorageSiK.Permissions.transferOwner(networkId, player, newOwner, args.keepFormerOwner == true)
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
		local ok = GlobalStorageSiK.Categories.add(networkId, args.name)
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = ok and GlobalStorageSiK.I18n.remote("IGUI_GS_CategoryAdded") or GlobalStorageSiK.I18n.remote("IGUI_GS_CategoryDuplicate") })
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "addPermissionUser" then
		if not requireAdminAccess(player, networkId) then
			return
		end
		local ok = GlobalStorageSiK.Permissions.addUser(networkId, args.characterName or args.username)
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = ok and GlobalStorageSiK.I18n.remote("IGUI_GS_UserAdded") or GlobalStorageSiK.I18n.remote("IGUI_GS_UserAlreadyExists") })
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "leaveNetwork" then
		-- Abandonar la propia fila esta siempre permitido sin importar el
		-- rol (member/admin/owner) - solo hace falta pertenecer a la red,
		-- nunca requireAdminAccess. Si es el owner, GS_Permissions.leaveNetwork
		-- dispara la misma sucesion automatica que al morir.
		if not requireNetworkPermission(player, networkId) then
			return
		end
		local myName = GlobalStorageSiK.Permissions.getCharacterName(player)
		local ok, message = GlobalStorageSiK.Permissions.leaveNetwork(networkId, myName)
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
		local registry = GlobalStorageSiK.Network.getRegistry()
		local net = registry.networks and registry.networks[networkId]
		local targetIsAdmin = false
		if net then
			for i = 1, #(net.adminUsers or {}) do
				if net.adminUsers[i] == target then targetIsAdmin = true; break end
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
		local ok = GlobalStorageSiK.Permissions.removeUser(networkId, target)
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
		gsSendServerCommand(player, "actionResult", { ok = ok, message = ok and GlobalStorageSiK.I18n.remote("IGUI_GS_UserRemovedMsg") or GlobalStorageSiK.I18n.remote("IGUI_GS_UserNotFoundToRemoveMsg") })
		pushTerminalState(player, networkId, nil, searchQuery)

	elseif command == "setMemberRole" then
		if not GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId) then
			gsSendServerCommand(player, "actionResult", { ok = false, message = GlobalStorageSiK.I18n.remote("IGUI_GS_OnlyOwnerChangeRolesMsg") })
			return
		end
		local ok = GlobalStorageSiK.Permissions.setUserRole(networkId, args.username or "", args.role or "member")
		if ok then ModData.transmit(GlobalStorageSiK.MODDATA_KEY) end
		gsSendServerCommand(player, "actionResult", { ok = ok, message = ok and GlobalStorageSiK.I18n.remote("IGUI_GS_RoleUpdatedMsg") or GlobalStorageSiK.I18n.remote("IGUI_GS_RoleUpdateFailedMsg") })
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

		local ok, message = registerContainer(args.entry, args.networkId)

		gsSendServerCommand(player, "actionResult", { ok = ok, message = message })

	elseif command == "unregisterContainer" then

		local ok, message = unregisterContainer(args.containerId, args.networkId)

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

if Events and Events.OnCreatePlayer then
	Events.OnCreatePlayer.Add(function(player)
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
			GlobalStorageSiK.Permissions.handleOwnerDeath(charName)
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


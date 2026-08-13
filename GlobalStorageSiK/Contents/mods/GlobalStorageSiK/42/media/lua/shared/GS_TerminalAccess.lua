--[[
	GlobalStorageSiK - Acceso al terminal (físico / tableta inalámbrica)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Valida proximidad al mueble terminal o tableta en inventario.
]]

require "GS_Config"
require "GS_Sandbox"
require "GS_Network"
-- GS_TerminalRegistry NO se requiere aqui a nivel de modulo: tambien requiere
-- GS_TerminalAccess (dependencia mutua real, ambos se llaman entre si dentro
-- de funciones, nunca a nivel de carga), y eso formaba un require recursivo.
-- Los dos puntos de uso real (getRegistryAnchor, findNearestRegisteredTerminal)
-- ya hacen su propio require perezoso si GlobalStorageSiK.TerminalRegistry
-- no existe todavia.

require "GS_TerminalManifest"
require "GS_Permissions"
require "GS_Debug"

GlobalStorageSiK.TerminalAccess = {}

require "GS_Addons"

--- Log de diagnóstico de acceso (sandbox DebugMode).
---@param step string
---@param detail any|nil
local function dbgAccess(step, detail)
	if GlobalStorageSiK.Debug and GlobalStorageSiK.Debug.log then
		GlobalStorageSiK.Debug.log("TerminalAccess", step, detail)
	end
end

GlobalStorageSiK.TerminalAccess.ITEM_UNIT = "GlobalStorageSiK.GS_TerminalUnit"
GlobalStorageSiK.TerminalAccess.MODDATA_FLAG = "gsTerminal"
GlobalStorageSiK.TerminalAccess.ITEM_TYPE_MODDATA = "gsItemType"
GlobalStorageSiK.TerminalAccess.VANILLA_SPRITE = "appliances_com_01_73"
-- El "Desktop Computer" vanilla (WorldObjectSprite base = appliances_com_01_72,
-- ver moveable.txt) se puede rotar en las 4 orientaciones N/S/E/W al
-- colocarlo, cada una con su propio sprite consecutivo en la misma hoja
-- (72/73/74/75). Solo teniamos 3 de las 4 (faltaba la 75) - reportado por un
-- jugador: el ordenador "mirando hacia arriba" (esa 4a rotacion) no se
-- detectaba como instalable, aunque las otras 3 orientaciones si funcionaban.
GlobalStorageSiK.TerminalAccess.VANILLA_DESKTOP_SPRITES = {
	"appliances_com_01_72",
	"appliances_com_01_73",
	"appliances_com_01_74",
	"appliances_com_01_75",
}

--- Nombres de objeto (getName()) aceptados como "ordenador instalable", además
--- del sprite. Método nuevo de instalación (lector + disquete sobre PC ya
--- colocado en el mapa): la única variante vanilla real en B42.20 es el
--- "Desktop Computer" (item Mov_DesktopComputer, un solo sprite base con 3
--- orientaciones). Se deja como lista para poder aceptar otros ordenadores
--- (de otros mods, o si vanilla añade variantes) sin tocar código, solo
--- añadiendo el nombre aquí.
GlobalStorageSiK.TerminalAccess.KNOWN_COMPUTER_NAMES = {
	"Desktop Computer",
}

--- True si el nombre visible del objeto está en la lista de ordenadores
--- conocidos (comparación case-insensitive, ignora mayúsculas del traductor).
---@param obj IsoObject|nil
---@return boolean
function GlobalStorageSiK.TerminalAccess.isKnownComputerName(obj)
	if not obj or not obj.getName then
		return false
	end
	local ok, name = pcall(function() return obj:getName() end)
	if not ok or not name or name == "" then
		return false
	end
	local lowerName = tostring(name):lower()
	local names = GlobalStorageSiK.TerminalAccess.KNOWN_COMPUTER_NAMES
	for i = 1, #names do
		if lowerName == names[i]:lower() then
			return true
		end
	end
	return false
end

--- True si el objeto es un ordenador instalable: sprite vanilla conocido O
--- nombre visible conocido (cualquiera de los dos vale). No exige que ya
--- tenga identidad GS - al contrario, isKnownComputerObject encuentra
--- candidatos para instalar por primera vez.
---@param obj IsoObject|nil
---@return boolean
function GlobalStorageSiK.TerminalAccess.isKnownComputerObject(obj)
	if not obj then
		return false
	end
	if GlobalStorageSiK.TerminalAccess.isVanillaTerminalSprite(obj) then
		return true
	end
	return GlobalStorageSiK.TerminalAccess.isKnownComputerName(obj)
end

--- True si el nombre de sprite corresponde a un PC vanilla (orientación 72/73/74).
---@param sprite string|nil
---@return boolean
function GlobalStorageSiK.TerminalAccess.isVanillaDesktopSprite(sprite)
	if not sprite or sprite == "" then
		return false
	end
	local sprites = GlobalStorageSiK.TerminalAccess.VANILLA_DESKTOP_SPRITES
	for i = 1, #sprites do
		if sprite == sprites[i] then
			return true
		end
	end
	return false
end

--- Obtiene celda del mundo para escaneo.
---@return IsoCell|nil
local function getWorldCell()
	if getCell then
		local cell = getCell()
		if cell then
			return cell
		end
	end
	if getWorld then
		local world = getWorld()
		if world and world.getCell then
			return world:getCell()
		end
	end
	return nil
end

--- Comprueba si el sprite del objeto coincide con el terminal vanilla GS.
---@param obj IsoObject|nil
---@return boolean
function GlobalStorageSiK.TerminalAccess.isVanillaTerminalSprite(obj)
	if not obj then
		return false
	end
	local spriteName = nil
	if obj.getSprite then
		local spr = obj:getSprite()
		if spr and spr.getName then
			spriteName = spr:getName()
		end
	end
	if (not spriteName or spriteName == "") and obj.getTextureName then
		spriteName = obj:getTextureName()
	end
	return GlobalStorageSiK.TerminalAccess.isVanillaDesktopSprite(spriteName)
end

--- Lee el sprite de mundo de un ítem moveable (B42: varias fuentes).
---@param item InventoryItem|nil
---@return string|nil
function GlobalStorageSiK.TerminalAccess.readItemWorldSprite(item)
	if not item then
		return nil
	end
	local sprite = nil
	if item.getWorldSprite then
		sprite = item:getWorldSprite()
	end
	if (not sprite or sprite == "") and item.getModData then
		local md = item:getModData()
		sprite = md and (md.WorldObjectSprite or md.worldObjectSprite or md.worldSprite or md.sprite)
	end
	if (not sprite or sprite == "") and item.getFullType then
		local ft = tostring(item:getFullType() or "")
		for i = 1, #GlobalStorageSiK.TerminalAccess.VANILLA_DESKTOP_SPRITES do
			local token = GlobalStorageSiK.TerminalAccess.VANILLA_DESKTOP_SPRITES[i]
			if string.find(ft, token, 1, true) then
				sprite = token
				break
			end
		end
	end
	if (not sprite or sprite == "") and item.getType then
		local t = tostring(item:getType() or "")
		for i = 1, #GlobalStorageSiK.TerminalAccess.VANILLA_DESKTOP_SPRITES do
			local token = GlobalStorageSiK.TerminalAccess.VANILLA_DESKTOP_SPRITES[i]
			if string.find(t, token, 1, true) then
				sprite = token
				break
			end
		end
	end
	if sprite and sprite ~= "" then
		return sprite
	end
	return nil
end

--- True si el ítem moveable usa sprite de PC vanilla (73/74; solo pista visual).
---@param item InventoryItem|nil
---@return boolean
function GlobalStorageSiK.TerminalAccess.isTerminalSpriteItem(item)
	local sprite = GlobalStorageSiK.TerminalAccess.readItemWorldSprite(item)
	return GlobalStorageSiK.TerminalAccess.isVanillaDesktopSprite(sprite)
end

--- True si el ítem es un ordenador de sobremesa vanilla (moveable genérico).
---@param item InventoryItem|nil
---@return boolean
function GlobalStorageSiK.TerminalAccess.isVanillaDesktopItem(item)
	if not item then
		return false
	end
	return GlobalStorageSiK.TerminalAccess.isTerminalSpriteItem(item)
end

--- Cuenta ordenadores vanilla en inventario del jugador.
---@param player IsoPlayer|nil
---@return number
function GlobalStorageSiK.TerminalAccess.countVanillaDesktopItems(player)
	if not player or not player.getInventory then
		return 0
	end
	local inv = player:getInventory()
	if not inv or not inv.getItems then
		return 0
	end
	local all = inv:getItems()
	local count = 0
	for i = 0, all:size() - 1 do
		local item = all:get(i)
		if GlobalStorageSiK.TerminalAccess.isVanillaDesktopItem(item) then
			count = count + 1
		end
	end
	return count
end

--- Primer ordenador vanilla en inventario (para consumir al instalar terminal GS).
---@param player IsoPlayer|nil
---@return InventoryItem|nil
function GlobalStorageSiK.TerminalAccess.findVanillaDesktopItem(player)
	if not player or not player.getInventory then
		return nil
	end
	local inv = player:getInventory()
	if not inv or not inv.getItems then
		return nil
	end
	local all = inv:getItems()
	for i = 0, all:size() - 1 do
		local item = all:get(i)
		if GlobalStorageSiK.TerminalAccess.isVanillaDesktopItem(item) then
			return item
		end
	end
	return nil
end

--- Comprueba si un objeto del mundo es un terminal GS.
--- Deteccion PURAMENTE por coordenadas (unico metodo soportado: lector +
--- disquete sobre un PC ya en el mapa) - no se marca ni se lee ModData de
--- identidad en el objeto para nada. La fuente de verdad es el registro de
--- red (net.terminals, por coordenada exacta); si esta baldosa tiene una
--- entrada activa Y hay un ordenador reconocible ahi, es un terminal, sea
--- cual sea el objeto fisico concreto. (El viejo metodo de mueble propio
--- GS_TerminalUnit con ModData se retiro por completo - partidas que aun
--- tuvieran uno colocado deben reinstalar con el metodo actual.)
---@param obj IsoObject|nil
---@return boolean
function GlobalStorageSiK.TerminalAccess.isTerminalObject(obj)
	if not obj then
		return false
	end
	if GlobalStorageSiK.TerminalAccess.isKnownComputerObject(obj) and obj.getSquare and GlobalStorageSiK.Network then
		local sq = obj:getSquare()
		if sq then
			local nid = GlobalStorageSiK.Network.findNetworkIdAtTerminal(sq:getX(), sq:getY(), sq:getZ(), { activeOnly = true })
			if nid then
				return true
			end
		end
	end
	return false
end

--- Punto de extensión para addons: un "proveedor inalámbrico" es cualquier
--- addon con su propio ítem de tableta (o equivalente) que da acceso remoto
--- al terminal. El Core no conoce ni menciona addons concretos por nombre;
--- cada addon se registra a sí mismo una vez, en su propio fichero de
--- cliente, con:
---   GlobalStorageSiK.TerminalAccess.registerWirelessProvider({
---     hasAccess = function(player) ... end,        -- obligatorio
---     hasCraft = function(player) ... end,         -- opcional
---     hasBuilder = function(player) ... end,       -- opcional
---     getRange = function(player) ... end,         -- obligatorio si hasAccess puede dar true
---     getRangeForNetwork = function(player, networkId, anchor) ... end, -- opcional
---   })
--- getRange(player) es el techo teorico usado SOLO para decidir el radio de
--- ESCANEO (aun no sabemos a que red nos conectaremos). getRangeForNetwork,
--- si el addon lo define, es el rango REAL ya resuelto para una red
--- concreta (p.ej. segun que tier de periferico este instalado ahi) y es lo
--- que se usa para la comprobacion final de admision - si un addon no lo
--- define, se cae a getRange(player) (comportamiento antiguo, compatible).
--- Varios addons pueden registrar su propio proveedor sin pisarse entre
--- ellos ni tocar este fichero.
GlobalStorageSiK.TerminalAccess._wirelessProviders = GlobalStorageSiK.TerminalAccess._wirelessProviders or {}

---@param provider table { hasAccess, hasCraft?, hasBuilder?, getRange }
function GlobalStorageSiK.TerminalAccess.registerWirelessProvider(provider)
	if not provider or not provider.hasAccess then
		return
	end
	table.insert(GlobalStorageSiK.TerminalAccess._wirelessProviders, provider)
end

--- Indica si el jugador lleva tableta de acceso remoto (cualquier addon
--- registrado como proveedor inalámbrico).
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.TerminalAccess.hasAccessTablet(player)
	for _, provider in ipairs(GlobalStorageSiK.TerminalAccess._wirelessProviders) do
		if provider.hasAccess and provider.hasAccess(player) then
			return true
		end
	end
	return false
end

--- Indica si el jugador lleva tableta de crafteo remoto, según lo que
--- reporte cualquier proveedor inalámbrico registrado.
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.TerminalAccess.hasCraftTablet(player)
	for _, provider in ipairs(GlobalStorageSiK.TerminalAccess._wirelessProviders) do
		if provider.hasCraft and provider.hasCraft(player) then
			return true
		end
	end
	return false
end

--- Indica si el jugador lleva tableta de construcción remota, según lo que
--- reporte cualquier proveedor inalámbrico registrado.
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.TerminalAccess.hasBuilderTablet(player)
	for _, provider in ipairs(GlobalStorageSiK.TerminalAccess._wirelessProviders) do
		if provider.hasBuilder and provider.hasBuilder(player) then
			return true
		end
	end
	return false
end

--- Tipo de tableta activa (craft tiene prioridad si lleva ambas).
---@param player IsoPlayer|nil
---@return string|nil "access"|"craft"|"builder"|"master"
function GlobalStorageSiK.TerminalAccess.getTabletKind(player)
	local craft = GlobalStorageSiK.TerminalAccess.hasCraftTablet(player)
	local builder = GlobalStorageSiK.TerminalAccess.hasBuilderTablet(player)
	if craft and builder then
		return "master"
	end
	if craft then
		return "craft"
	end
	if builder then
		return "builder"
	end
	if GlobalStorageSiK.TerminalAccess.hasAccessTablet(player) then
		return "access"
	end
	return nil
end

--- Indica si el jugador lleva alguna tableta remota.
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.TerminalAccess.hasTablet(player)
	return GlobalStorageSiK.TerminalAccess.getTabletKind(player) ~= nil
end

--- Rango inalámbrico según tableta equipada. Fuente única: el addon Tablet
--- decide el rango segun el tier mas alto que el jugador lleve encima.
---@param player IsoPlayer|nil
---@return number
function GlobalStorageSiK.TerminalAccess.getWirelessRangeForPlayer(player)
	local best = nil
	for _, provider in ipairs(GlobalStorageSiK.TerminalAccess._wirelessProviders) do
		if provider.hasAccess and provider.hasAccess(player) and provider.getRange then
			local range = provider.getRange(player)
			if range and (not best or range > best) then
				best = range
			end
		end
	end
	return best or GlobalStorageSiK.Sandbox.getWirelessRange()
end

--- Rango inalámbrico REAL para una red concreta ya resuelta - a diferencia
--- de getWirelessRangeForPlayer (techo teorico usado solo para el radio de
--- escaneo inicial, antes de saber a que red nos conectamos), esto
--- pregunta a cada proveedor cual es el rango de verdad para ESA red (p.ej.
--- que tier de antena tiene instalado). Si un proveedor no implementa
--- getRangeForNetwork, se usa su getRange(player) de siempre (compatible
--- con addons antiguos). Sin ningun proveedor con acceso, devuelve 0 -
--- nunca se debe admitir a nadie por rango inalambrico sin un addon que lo
--- respalde de verdad.
---@param player IsoPlayer|nil
---@param networkId string|nil
---@param anchor table|nil
---@return number
function GlobalStorageSiK.TerminalAccess.getWirelessRangeForNetwork(player, networkId, anchor)
	local best = nil
	for _, provider in ipairs(GlobalStorageSiK.TerminalAccess._wirelessProviders) do
		if provider.hasAccess and provider.hasAccess(player) then
			local range
			if provider.getRangeForNetwork then
				range = provider.getRangeForNetwork(player, networkId, anchor)
			elseif provider.getRange then
				range = provider.getRange(player)
			end
			if range and (not best or range > best) then
				best = range
			end
		end
	end
	return best or 0
end

--- Distancia planar jugador → punto del mapa.
---@param player IsoPlayer
---@param x number
---@param y number
---@return number
local function planarDistance(player, x, y)
	local dx = player:getX() - x
	local dy = player:getY() - y
	return math.sqrt(dx * dx + dy * dy)
end

--- Planta del jugador (entera).
---@param player IsoPlayer
---@return number
local function playerFloorZ(player)
	return math.floor(player:getZ())
end

--- Sesiones de terminal ancladas por jugador (SP cliente / servidor).
---@type table<string, table>
GlobalStorageSiK.TerminalAccess._sessions = GlobalStorageSiK.TerminalAccess._sessions or {}

--- Clave estable del jugador para sesión.
---@param player IsoPlayer|nil
---@return string|nil
function GlobalStorageSiK.TerminalAccess.getPlayerKey(player)
	if not player or not player.getUsername then
		return nil
	end
	return player:getUsername()
end

--- Resuelve networkId de un objeto terminal colocado.
---@param obj IsoObject|nil
---@return string|nil
function GlobalStorageSiK.TerminalAccess.resolveObjectNetworkId(obj)
	if not obj then
		return nil
	end
	if obj.getSquare and GlobalStorageSiK.Network and GlobalStorageSiK.Network.findNetworkIdAtTerminal then
		local sq = obj:getSquare()
		if sq then
			return GlobalStorageSiK.Network.findNetworkIdAtTerminal(sq:getX(), sq:getY(), sq:getZ())
		end
	end
	return nil
end

--- Construye hint de acceso desde un terminal concreto del mundo.
---@param player IsoPlayer|nil
---@param obj IsoObject|nil
---@return table|nil
function GlobalStorageSiK.TerminalAccess.buildHintFromObject(player, obj)
	if not player or not obj or not GlobalStorageSiK.TerminalAccess.isTerminalObject(obj) then
		return nil
	end
	local sq = obj.getSquare and obj:getSquare() or nil
	if not sq then
		return nil
	end
	local networkId = GlobalStorageSiK.TerminalAccess.resolveObjectNetworkId(obj)
	return {
		x = math.floor(sq:getX()),
		y = math.floor(sq:getY()),
		z = math.floor(sq:getZ()),
		networkId = networkId,
		object = obj,
	}
end

--- Devuelve la ancla fija del registro ModData para una red.
---@param networkId string|nil
---@return table|nil
function GlobalStorageSiK.TerminalAccess.getRegistryAnchor(networkId)
	if not networkId or not GlobalStorageSiK.Network then
		return nil
	end
	if not GlobalStorageSiK.TerminalRegistry then
		require "GS_TerminalRegistry"
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	if not registry or not registry.networks then
		return nil
	end
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local network = registry.networks[networkId]
	if not network or not GlobalStorageSiK.TerminalRegistry.getActiveAnchor then
		return nil
	end
	local anchor = GlobalStorageSiK.TerminalRegistry.getActiveAnchor(network)
	if not anchor or not anchor.x or not anchor.y then
		return nil
	end
	return {
		x = anchor.x,
		y = anchor.y,
		z = anchor.z or 0,
		networkId = networkId,
	}
end

--- Histéresis de cierre (baldosas extra antes de bloquear).
---@return number
function GlobalStorageSiK.TerminalAccess.getAccessHysteresis()
	if not SandboxVars.GlobalStorageSiK then
		return 1
	end
	local h = SandboxVars.GlobalStorageSiK.AccessHysteresisTiles
	if h == nil then
		return 1
	end
	return math.max(0, tonumber(h) or 1)
end

--- Fija el terminal de la sesión UI abierta.
---@param player IsoPlayer
---@param anchor table|nil
---@param accessMode string|nil
---@param networkId string|nil
function GlobalStorageSiK.TerminalAccess.setSessionAnchor(player, anchor, accessMode, networkId)
	local key = GlobalStorageSiK.TerminalAccess.getPlayerKey(player)
	if not key or not anchor or not anchor.x or not anchor.y then
		return
	end
	if not networkId and anchor.x and GlobalStorageSiK.Network and GlobalStorageSiK.Network.findNetworkIdAtTerminal then
		networkId = GlobalStorageSiK.Network.findNetworkIdAtTerminal(anchor.x, anchor.y, anchor.z or 0)
	end
	GlobalStorageSiK.TerminalAccess._sessions[key] = {
		anchor = {
			x = anchor.x,
			y = anchor.y,
			z = anchor.z or 0,
		},
		accessMode = accessMode,
		networkId = networkId,
		wasInRange = true,
	}
end

--- Devuelve networkId de la sesión UI activa.
---@param player IsoPlayer|nil
---@return string|nil
function GlobalStorageSiK.TerminalAccess.getSessionNetworkId(player)
	local key = GlobalStorageSiK.TerminalAccess.getPlayerKey(player)
	local session = key and GlobalStorageSiK.TerminalAccess._sessions[key]
	return session and session.networkId or nil
end

--- Devuelve ancla de sesión activa.
---@param player IsoPlayer|nil
---@return table|nil
function GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
	local key = GlobalStorageSiK.TerminalAccess.getPlayerKey(player)
	local session = key and GlobalStorageSiK.TerminalAccess._sessions[key]
	return session and session.anchor or nil
end

--- Limpia sesión de terminal (cierre UI o bloqueo).
---@param player IsoPlayer|nil
function GlobalStorageSiK.TerminalAccess.clearSession(player)
	local key = GlobalStorageSiK.TerminalAccess.getPlayerKey(player)
	if key then
		GlobalStorageSiK.TerminalAccess._sessions[key] = nil
	end
end

--- Evalúa distancia contra un ancla con histéresis de sesión.
---@param player IsoPlayer
---@param anchor table
---@param proxRange number
---@param wirelessRange number
---@param session table|nil
---@param strictDistance boolean|nil true = sin histéresis (servidor / autoridad)
---@return boolean allowed
---@return string|nil mode physical|wireless
---@return string|nil reason
local function evaluateAnchorDistance(player, anchor, proxRange, wirelessRange, session, strictDistance)
	local sz = math.floor(anchor.z or 0)
	if playerFloorZ(player) ~= sz then
		if session then
			session.wasInRange = false
		end
		if GlobalStorageSiK.TerminalAccess.hasTablet(player) then
			return false, nil, "tablet_out_of_range"
		end
		return false, nil, "terminal_out_of_range"
	end

	local dist = planarDistance(player, anchor.x, anchor.y)
	local hysteresis = strictDistance and 0 or GlobalStorageSiK.TerminalAccess.getAccessHysteresis()
	local inRange = not strictDistance and session and session.wasInRange == true
	local proxLimit = proxRange + (inRange and hysteresis or 0)
	local wirelessLimit = wirelessRange + (inRange and hysteresis or 0)

	if dist <= proxLimit then
		if session then
			session.wasInRange = true
		end
		return true, "physical", nil
	end
	if GlobalStorageSiK.TerminalAccess.hasTablet(player) and dist <= wirelessLimit then
		if session then
			session.wasInRange = true
		end
		return true, "wireless", nil
	end

	if session then
		session.wasInRange = false
	end
	if GlobalStorageSiK.TerminalAccess.hasTablet(player) then
		return false, nil, "tablet_out_of_range"
	end
	return false, nil, "terminal_out_of_range"
end

--- Añade candidato si está más cerca que el actual.
---@param best table|nil
---@param bestDist number
---@param x number
---@param y number
---@param z number
---@param maxRange number
---@param z number
---@param maxRange number
---@param networkId string|nil
---@return table|nil, number
local function considerTerminalCandidate(best, bestDist, x, y, z, maxRange, player, networkId)
	if not player or playerFloorZ(player) ~= math.floor(z) then
		return best, bestDist
	end
	local dist = planarDistance(player, x, y)
	if dist <= maxRange and dist < bestDist then
		return {
			x = x,
			y = y,
			z = z,
			distance = dist,
			networkId = networkId,
		}, dist
	end
	return best, bestDist
end

--- Busca terminales registrados en ModData (fiable en servidor dedicado).
---@param player IsoPlayer
---@param networkId string|nil nil = todas las redes accesibles del jugador
---@param maxRange number
---@return table|nil
function GlobalStorageSiK.TerminalAccess.findNearestRegisteredTerminal(player, networkId, maxRange)
	if not player or not maxRange or maxRange <= 0 then
		return nil
	end
	if not GlobalStorageSiK.TerminalRegistry then
		require "GS_TerminalRegistry"
	end
	if not GlobalStorageSiK.Network then
		return nil
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	if not registry or not registry.networks then
		return nil
	end
	GlobalStorageSiK.Network.ensureRegistry(registry)

	local best = nil
	local bestDist = maxRange + 1

	local function scanNetwork(nid, network)
		if not network then
			return
		end
		local list = GlobalStorageSiK.TerminalRegistry.getAllTerminals
			and GlobalStorageSiK.TerminalRegistry.getAllTerminals(network)
			or {}
		if #list == 0 and GlobalStorageSiK.TerminalRegistry.getActiveAnchor then
			local anchor = GlobalStorageSiK.TerminalRegistry.getActiveAnchor(network)
			if anchor and anchor.x and anchor.y then
				list = { { x = anchor.x, y = anchor.y, z = anchor.z or 0 } }
			end
		end
		for i = 1, #list do
			local t = list[i]
			if t and t.x and t.y then
				best, bestDist = considerTerminalCandidate(
					best, bestDist, t.x, t.y, t.z or 0, maxRange, player, nid
				)
			end
		end
	end

	if networkId and registry.networks[networkId] then
		scanNetwork(networkId, registry.networks[networkId])
	else
		for nid, network in pairs(registry.networks) do
			if not GlobalStorageSiK.Permissions
				or select(1, GlobalStorageSiK.Permissions.canAccess(player, nid)) then
				scanNetwork(nid, network)
			end
		end
	end

	return best
end

--- True si hay un terminal GS en la casilla indicada (chunk cargado).
---@param x number
---@param y number
---@param z number
---@return boolean
local function terminalObjectAtSquare(x, y, z)
	local cell = getWorldCell()
	if not cell or not x or not y then
		return false
	end
	local sq = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
	if not sq then
		return false
	end
	for i = 0, sq:getObjects():size() - 1 do
		if GlobalStorageSiK.TerminalAccess.isTerminalObject(sq:getObjects():get(i)) then
			return true
		end
	end
	return false
end

--- Elige el terminal más cercano entre escaneo de mundo y registro ModData.
---@param player IsoPlayer
---@param networkId string|nil
---@param maxRange number
---@return table|nil
function GlobalStorageSiK.TerminalAccess.findNearestTerminalAny(player, networkId, maxRange)
	if not player or not maxRange or maxRange <= 0 then
		dbgAccess("findNearestAny", "invalid args")
		return nil
	end
	-- Escaneo de mundo primero (posición real del mueble); ModData como respaldo.
	local world = GlobalStorageSiK.TerminalAccess.findNearestTerminal(player, maxRange, networkId)
	local registered = GlobalStorageSiK.TerminalAccess.findNearestRegisteredTerminal(player, networkId, maxRange)
	dbgAccess("findNearestAny", string.format(
		"net=%s range=%.1f reg=%s scan=%s",
		tostring(networkId),
		maxRange,
		registered and string.format("%.1f@%d,%d", registered.distance or -1, registered.x or 0, registered.y or 0) or "nil",
		world and string.format("%.1f@%d,%d", world.distance or -1, world.x or 0, world.y or 0) or "nil"
	))
	if world and registered then
		if not terminalObjectAtSquare(registered.x, registered.y, registered.z or 0) then
			return world
		end
		if (world.distance or 99) + 0.01 < (registered.distance or 99) then
			return world
		end
		if registered.distance < world.distance then
			return registered
		end
		return world
	end
	return world or registered
end

--- Busca el terminal GS más cercano dentro del rango indicado.
---@param player IsoPlayer
---@param maxRange number
---@param networkId string|nil si se indica, solo terminales de esa red
---@return table|nil entry { x, y, z, distance, networkId?, object? }
function GlobalStorageSiK.TerminalAccess.findNearestTerminal(player, maxRange, networkId)
	if not player or not maxRange or maxRange <= 0 then
		return nil
	end
	local cell = getWorldCell()
	if not cell then
		return nil
	end
	local px = math.floor(player:getX())
	local py = math.floor(player:getY())
	local pz = playerFloorZ(player)
	local best = nil
	local bestDist = maxRange + 1

	for dx = -maxRange, maxRange do
		for dy = -maxRange, maxRange do
			local sq = cell:getGridSquare(px + dx, py + dy, pz)
			if sq then
				for i = 0, sq:getObjects():size() - 1 do
					local obj = sq:getObjects():get(i)
					if GlobalStorageSiK.TerminalAccess.isTerminalObject(obj) then
						local nid = GlobalStorageSiK.TerminalAccess.resolveObjectNetworkId(obj)
						if networkId and nid and nid ~= networkId then
							-- omitir terminales de otra red
						else
							local dist = planarDistance(player, sq:getX(), sq:getY())
							if dist <= maxRange and dist < bestDist then
								bestDist = dist
								best = {
									x = sq:getX(),
									y = sq:getY(),
									z = sq:getZ(),
									distance = dist,
									networkId = nid,
									object = obj,
								}
							end
						end
					end
				end
			end
		end
	end
	return best
end

--- Busca el ordenador instalable (sin terminal GS todavía) más cercano
--- dentro del rango indicado. Mismo patrón de escaneo que findNearestTerminal,
--- pero busca lo contrario: candidatos SIN identidad GS aún.
---@param player IsoPlayer
---@param maxRange number
---@return table|nil entry { x, y, z, distance, object }
function GlobalStorageSiK.TerminalAccess.findNearestUninstalledComputer(player, maxRange)
	if not player or not maxRange or maxRange <= 0 then
		return nil
	end
	local cell = getWorldCell()
	if not cell then
		return nil
	end
	local px = math.floor(player:getX())
	local py = math.floor(player:getY())
	local pz = playerFloorZ(player)
	local best = nil
	local bestDist = maxRange + 1

	for dx = -maxRange, maxRange do
		for dy = -maxRange, maxRange do
			local sq = cell:getGridSquare(px + dx, py + dy, pz)
			if sq then
				for i = 0, sq:getObjects():size() - 1 do
					local obj = sq:getObjects():get(i)
					if GlobalStorageSiK.TerminalAccess.isKnownComputerObject(obj)
						and not GlobalStorageSiK.TerminalAccess.isTerminalObject(obj) then
						local dist = planarDistance(player, sq:getX(), sq:getY())
						if dist <= maxRange and dist < bestDist then
							bestDist = dist
							best = {
								x = sq:getX(),
								y = sq:getY(),
								z = sq:getZ(),
								distance = dist,
								object = obj,
							}
						end
					end
				end
			end
		end
	end
	return best
end

--- Busca el ordenador CONOCIDO mas cercano dentro del rango, este ya
--- instalado o no. A diferencia de findNearestUninstalledComputer, esta no
--- filtra por si ya tiene terminal - sirve para poder avisar claramente
--- "ya hay un terminal instalado aqui" en vez de ocultar la opcion del menu
--- sin explicacion cuando el PC mas cercano ya esta en uso.
---@param player IsoPlayer
---@param maxRange number
---@return table|nil entry { x, y, z, distance, object, alreadyInstalled }
function GlobalStorageSiK.TerminalAccess.findNearestKnownComputer(player, maxRange)
	if not player or not maxRange or maxRange <= 0 then
		return nil
	end
	local cell = getWorldCell()
	if not cell then
		return nil
	end
	local px = math.floor(player:getX())
	local py = math.floor(player:getY())
	local pz = playerFloorZ(player)
	local best = nil
	local bestDist = maxRange + 1

	for dx = -maxRange, maxRange do
		for dy = -maxRange, maxRange do
			local sq = cell:getGridSquare(px + dx, py + dy, pz)
			if sq then
				for i = 0, sq:getObjects():size() - 1 do
					local obj = sq:getObjects():get(i)
					if GlobalStorageSiK.TerminalAccess.isKnownComputerObject(obj) then
						local dist = planarDistance(player, sq:getX(), sq:getY())
						if dist <= maxRange and dist < bestDist then
							bestDist = dist
							best = {
								x = sq:getX(),
								y = sq:getY(),
								z = sq:getZ(),
								distance = dist,
								object = obj,
								alreadyInstalled = GlobalStorageSiK.TerminalAccess.isTerminalObject(obj),
							}
						end
					end
				end
			end
		end
	end
	return best
end

--- Limpieza defensiva de ModData en un ordenador del metodo NUEVO (lector +
--- disquete). Ya NO se marca ModData al instalar (ver installTerminalReader
--- en GS_Server.lua: la fuente de verdad es la coordenada registrada,
--- isTerminalObject la comprueba directamente) - esta funcion se conserva
--- solo por dos motivos: (1) limpiar de forma segura cualquier ordenador
--- marcado por una version anterior (v1.2.40) que SI llegó a tocar ModData
--- antes de este cambio, y (2) por si algun dia coincidiera con un objeto
--- que llevara ModData de otro origen. Llamarla sobre un objeto sin ModData
--- GS es un no-op inofensivo.
---@param obj IsoObject|nil
---@return boolean
function GlobalStorageSiK.TerminalAccess.unregisterComputerAsTerminal(obj)
	if not obj or not obj.getModData then
		return false
	end
	local md = obj:getModData()
	md[GlobalStorageSiK.TerminalAccess.MODDATA_FLAG] = nil
	md[GlobalStorageSiK.TerminalAccess.ITEM_TYPE_MODDATA] = nil
	md.gsTerminalPlaced = nil
	md.gsnNetworkId = nil
	if obj.transmitModData then
		obj:transmitModData()
	end
	return true
end

--- Sonda el terminal GS más cercano e incluye networkId del objeto si existe.
---@param player IsoPlayer|nil
---@param maxRange number|nil
---@param filterNetworkId string|nil
---@return table|nil { x, y, z, distance, networkId, object }
function GlobalStorageSiK.TerminalAccess.probeNearbyTerminal(player, maxRange, filterNetworkId)
	if not player or not maxRange or maxRange <= 0 then
		return nil
	end
	local world = GlobalStorageSiK.TerminalAccess.findNearestTerminal(player, maxRange, filterNetworkId)
	if not world or not world.x or not world.y then
		return nil
	end
	local networkId = world.networkId
	if (not networkId or networkId == "") and world.object then
		networkId = GlobalStorageSiK.TerminalAccess.resolveObjectNetworkId(world.object)
	end
	if (not networkId or networkId == "") and GlobalStorageSiK.Network then
		networkId = GlobalStorageSiK.Network.findNetworkIdAtTerminal(world.x, world.y, world.z or 0)
	end
	world.networkId = networkId
	return world
end

--- Construye hint de terminal para comandos al servidor (MP / recuperación).
---@param player IsoPlayer|nil
---@param networkId string|nil
---@return table|nil
function GlobalStorageSiK.TerminalAccess.buildTerminalHint(player, networkId)
	if not player then
		return nil
	end
	local sessionAnchor = GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
	local sessionNet = GlobalStorageSiK.TerminalAccess.getSessionNetworkId(player)
	if sessionAnchor and sessionAnchor.x and sessionAnchor.y then
		return {
			x = math.floor(sessionAnchor.x),
			y = math.floor(sessionAnchor.y),
			z = math.floor(sessionAnchor.z or 0),
			networkId = networkId or sessionNet,
		}
	end
	local prox = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	local wireless = GlobalStorageSiK.TerminalAccess.getWirelessRangeForPlayer(player)
	local range = math.max(prox, wireless)
	local near = GlobalStorageSiK.TerminalAccess.probeNearbyTerminal(player, range, networkId)
	if not near then
		return nil
	end
	local nid = networkId or near.networkId
	return {
		x = math.floor(near.x),
		y = math.floor(near.y),
		z = math.floor(near.z or 0),
		networkId = nid,
	}
end

--- Añade terminalHint y networkId al payload de comando (cliente).
---@param player IsoPlayer|nil
---@param payload table|nil
---@param networkId string|nil
---@return table
function GlobalStorageSiK.TerminalAccess.enrichCommandPayload(player, payload, networkId)
	payload = payload or {}
	if not player or not GlobalStorageSiK.TerminalAccess.buildTerminalHint then
		return payload
	end
	local hint = GlobalStorageSiK.TerminalAccess.buildTerminalHint(player, networkId or payload.networkId)
	if hint then
		payload.terminalHint = hint
		if hint.networkId and not payload.networkId then
			payload.networkId = hint.networkId
		end
	end
	return payload
end

--- Refina modo inalámbrico según tableta equipada.
---@param player IsoPlayer|nil
---@param mode string|nil
---@return string|nil
function GlobalStorageSiK.TerminalAccess.refineWirelessMode(player, mode)
	if mode ~= "wireless" then
		return mode
	end
	local craft = GlobalStorageSiK.TerminalAccess.hasCraftTablet(player)
	local builder = GlobalStorageSiK.TerminalAccess.hasBuilderTablet(player)
	if craft and builder then
		return "wireless_master"
	end
	if craft then
		return "wireless_craft"
	end
	if builder then
		return "wireless_builder"
	end
	return "wireless_access"
end

--- Ultima firma de log registrada por jugador (ver comentario dentro de
--- evaluate()) - evita repetir la misma linea de debug en cada sondeo
--- periodico mientras el terminal sigue abierto sin cambios reales.
local lastAnchorLogSig = {}

--- Evalúa si el jugador puede abrir el terminal completo.
---@param player IsoPlayer|nil
---@param networkId string|nil
---@param serverAnchor table|nil coords del terminal validadas por el servidor
---@param opts table|nil { sessionLock = boolean, ignoreSession = boolean, strictDistance = boolean }
---@return boolean allowed
---@return string|nil mode physical|wireless|bypass
---@return table|nil terminal
---@return string|nil reason
function GlobalStorageSiK.TerminalAccess.evaluate(player, networkId, serverAnchor, opts)
	if not player then
		return false, nil, nil, "no_player"
	end
	if not GlobalStorageSiK.Sandbox.requireTerminalAccess() then
		return true, "bypass", nil, nil
	end

	opts = opts or {}
	local proxRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	local wirelessRange = GlobalStorageSiK.TerminalAccess.getWirelessRangeForPlayer(player)
	local scanRange = math.max(proxRange, wirelessRange)
	local strictDistance = opts.strictDistance == true

	local key = GlobalStorageSiK.TerminalAccess.getPlayerKey(player)
	local session = key and GlobalStorageSiK.TerminalAccess._sessions[key] or nil
	local anchor = serverAnchor
	if not opts.ignoreSession then
		if opts.sessionLock and session then
			local net = networkId or session.networkId
			local regAnchor = GlobalStorageSiK.TerminalAccess.getRegistryAnchor(net)
			anchor = regAnchor or session.anchor
			if not anchor then
				session.wasInRange = false
				return false, nil, nil, "no_terminal"
			end
		elseif opts.sessionLock and session and session.anchor then
			anchor = session.anchor
		elseif not anchor and session and session.anchor then
			anchor = session.anchor
		end
	end

	if anchor and anchor.x and anchor.y then
		-- Rango final real: no el techo teorico de escaneo, sino el que de
		-- verdad da la antena/periferico instalado en ESTA red concreta.
		local anchorNet = networkId or (session and session.networkId)
		local anchorRange = GlobalStorageSiK.TerminalAccess.getWirelessRangeForNetwork(player, anchorNet, anchor)
		local ok, mode, reason = evaluateAnchorDistance(
			player, anchor, proxRange, anchorRange, session, strictDistance
		)
		local hint = {
			x = anchor.x,
			y = anchor.y,
			z = anchor.z or 0,
			distance = planarDistance(player, anchor.x, anchor.y),
		}
		if GlobalStorageSiK.Sandbox.debugMode and GlobalStorageSiK.Sandbox.debugMode() and GlobalStorageSiK.Debug then
			-- Este evaluate() se llama en cada sondeo periodico
			-- (pingTerminalAccess) mientras la ventana del terminal sigue
			-- abierta - sin filtro, imprimia la MISMA linea decenas de veces
			-- por minuto solo por seguir de pie en el mismo sitio. Se
			-- registra solo cuando el resultado (redondeado a 1 decimal de
			-- distancia, para no repetir por temblores de subpixel) cambia
			-- de verdad respecto al ultimo log de este jugador.
			local sig = string.format("%s|%s|%.1f|%s|%s",
				tostring(opts.sessionLock), tostring(strictDistance),
				hint.distance, tostring(ok), tostring(reason))
			local lastKey = key or tostring(player)
			if lastAnchorLogSig[lastKey] ~= sig then
				lastAnchorLogSig[lastKey] = sig
				GlobalStorageSiK.Debug.log("Access", "anchor",
					string.format(
						"lock=%s strict=%s dist=%.2f ok=%s reason=%s z=%d ply=%.1f,%.1f anc=%.1f,%.1f",
						tostring(opts.sessionLock), tostring(strictDistance),
						hint.distance, tostring(ok), tostring(reason), hint.z,
						player:getX(), player:getY(), anchor.x, anchor.y
					))
			end
		end
		if ok then
			if mode == "wireless" and GlobalStorageSiK.Addons and not GlobalStorageSiK.Addons.canUseTabletWireless(networkId, hint) then
				return false, nil, hint, "tablet_addon_required"
			end
			if mode == "wireless" then
				mode = GlobalStorageSiK.TerminalAccess.refineWirelessMode(player, mode)
			end
			return true, mode, hint, nil
		end
		if opts.sessionLock or (session and session.anchor) then
			-- BUG REAL encontrado (reportado: "de vez en cuando, desde el
			-- segundo terminal, da un ping y pierde el acceso"): esta rama
			-- solo comprobaba distancia al ancla de SESION/CONTROLADOR de la
			-- red (ver getRegistryAnchor -> TerminalRecord.getPrimaryAnchor),
			-- nunca si el jugador esta cerca de OTRO terminal activo de esa
			-- MISMA red - en una red con mas de un terminal, moverse hacia el
			-- segundo terminal podia perder el acceso de forma intermitente
			-- (pingTerminalAccess corre con sessionLock=true casi siempre)
			-- aunque hubiera un terminal valido justo al lado. Antes de
			-- rendirse, probamos si hay CUALQUIER terminal activo de ESTA
			-- red al alcance ahora mismo (findNearestTerminalAny ya filtra
			-- por networkId, no salta a otra red sin querer).
			local altNet = (session and session.networkId) or networkId
			local altNearest = GlobalStorageSiK.TerminalAccess.findNearestTerminalAny(player, altNet, scanRange)
			if altNearest and altNearest.distance <= proxRange then
				dbgAccess("evaluate", string.format("sessionLock alt physical dist=%.2f", altNearest.distance))
				return true, "physical", altNearest, nil
			end
			if altNearest and GlobalStorageSiK.TerminalAccess.hasTablet(player) then
				local altRange = GlobalStorageSiK.TerminalAccess.getWirelessRangeForNetwork(player, altNet, altNearest)
				if altNearest.distance <= altRange then
					local tabletOk = not (GlobalStorageSiK.Addons and not GlobalStorageSiK.Addons.canUseTabletWireless(altNet, altNearest))
					if tabletOk then
						dbgAccess("evaluate", string.format("sessionLock alt wireless dist=%.2f", altNearest.distance))
						return true, GlobalStorageSiK.TerminalAccess.refineWirelessMode(player, "wireless"), altNearest, nil
					end
				elseif altNearest.distance <= wirelessRange then
					-- Detectado dentro del techo teorico pero fuera del rango
					-- real de la antena instalada (o sin antena instalada) -
					-- razon especifica para poder avisar al jugador de verdad.
					return false, nil, altNearest, "antenna_out_of_range"
				end
			end
			return false, nil, hint, reason
		end
	end

	local nearest = GlobalStorageSiK.TerminalAccess.findNearestTerminalAny(player, networkId, scanRange)
	if nearest and not nearest.networkId and nearest.x and GlobalStorageSiK.Network then
		nearest.networkId = GlobalStorageSiK.Network.findNetworkIdAtTerminal(
			nearest.x, nearest.y, nearest.z or 0
		)
	end
	local resolvedNet = nearest and nearest.networkId or networkId

	if nearest and nearest.distance <= proxRange then
		dbgAccess("evaluate", string.format("physical dist=%.2f", nearest.distance))
		return true, "physical", nearest, nil
	end

	if GlobalStorageSiK.TerminalAccess.hasTablet(player) then
		if nearest then
			local netRange = GlobalStorageSiK.TerminalAccess.getWirelessRangeForNetwork(player, resolvedNet, nearest)
			if nearest.distance <= netRange then
				if GlobalStorageSiK.Addons and not GlobalStorageSiK.Addons.canUseTabletWireless(resolvedNet, nearest) then
					dbgAccess("evaluate", "tablet_addon_required")
					return false, nil, nearest, "tablet_addon_required"
				end
				dbgAccess("evaluate", string.format("wireless dist=%.2f", nearest.distance))
				return true, GlobalStorageSiK.TerminalAccess.refineWirelessMode(player, "wireless"), nearest, nil
			end
			if nearest.distance <= wirelessRange then
				-- Terminal detectado dentro del techo teorico de escaneo, pero
				-- fuera del rango real que da la antena instalada en esa red
				-- (o sin antena instalada ahi) - razon especifica, no el
				-- generico "tablet_out_of_range" de antes.
				dbgAccess("evaluate", string.format("antenna_out_of_range dist=%.2f netRange=%.1f", nearest.distance, netRange))
				return false, nil, nearest, "antenna_out_of_range"
			end
			dbgAccess("evaluate", string.format("tablet_out_of_range dist=%.2f", nearest.distance))
			return false, nil, nearest, "tablet_out_of_range"
		end
	end

	-- Proximidad por coordenadas conocidas (manifiesto / ModData), sin escaneo de chunks.
	local manifest = opts.manifest
	if not manifest then
		if GlobalStorageSiK.TerminalManifest and GlobalStorageSiK.TerminalManifest.getEffectiveManifest then
			manifest = GlobalStorageSiK.TerminalManifest.getEffectiveManifest(player)
		elseif GlobalStorageSiK.Client and GlobalStorageSiK.Client.terminalManifest then
			manifest = GlobalStorageSiK.Client.terminalManifest
		elseif GlobalStorageSiK.TerminalManifest and GlobalStorageSiK.TerminalManifest.buildForPlayer then
			local okBuild, built = pcall(GlobalStorageSiK.TerminalManifest.buildForPlayer, player)
			if okBuild then
				manifest = built
			end
		end
	end
	if manifest and GlobalStorageSiK.TerminalManifest.evaluateProximity then
		local proxOk, nearestM, modeM, reasonM = GlobalStorageSiK.TerminalManifest.evaluateProximity(player, manifest, networkId)
		dbgAccess("manifestProx", string.format(
			"ok=%s mode=%s reason=%s count=%d nearest=%s",
			tostring(proxOk), tostring(modeM), tostring(reasonM),
			manifest.terminals and #manifest.terminals or 0,
			nearestM and string.format("%.1f@%d,%d", nearestM.distance or -1, nearestM.x or 0, nearestM.y or 0) or "nil"
		))
		if proxOk then
			local mode = modeM
			if mode == "wireless" then
				mode = GlobalStorageSiK.TerminalAccess.refineWirelessMode(player, mode)
			end
			local resolvedId = nearestM and nearestM.networkId or networkId
			if nearestM and not nearestM.networkId and nearestM.x then
				resolvedId = GlobalStorageSiK.Network.findNetworkIdAtTerminal(nearestM.x, nearestM.y, nearestM.z or 0)
			end
			if nearestM and resolvedId then
				nearestM.networkId = resolvedId
			end
			return true, mode, nearestM, nil
		end
		if reasonM == "tablet_addon_required" then
			return false, nil, nearestM, reasonM
		end
	end

	if nearest then
		dbgAccess("evaluate", string.format("terminal_out_of_range dist=%.2f", nearest.distance))
		if GlobalStorageSiK.TerminalRegistry and GlobalStorageSiK.TerminalRegistry.snapAnchorFromWorldIfNear then
			local snapNet = resolvedNet or networkId
			local probeNet = GlobalStorageSiK.TerminalRegistry.snapAnchorFromWorldIfNear(player, snapNet, proxRange)
			if probeNet and probeNet ~= "" then
				snapNet = probeNet
				local retry = GlobalStorageSiK.TerminalAccess.findNearestRegisteredTerminal(player, snapNet, scanRange)
				if retry and retry.distance <= proxRange then
					dbgAccess("evaluate", string.format("physical probe dist=%.2f", retry.distance))
					return true, "physical", retry, nil
				end
				local worldRetry = GlobalStorageSiK.TerminalAccess.findNearestTerminal(player, proxRange, snapNet)
				if worldRetry and worldRetry.distance <= proxRange then
					worldRetry.networkId = snapNet
					dbgAccess("evaluate", string.format("physical probeWorld dist=%.2f", worldRetry.distance))
					return true, "physical", worldRetry, nil
				end
			end
		end
		return false, nil, nearest, "terminal_out_of_range"
	end

	dbgAccess("evaluate", "no_terminal")
	return false, nil, nearest, "no_terminal"
end

--- Evalúa apertura en cliente: registradas → manifiesto → escaneo; persiste hallazgos.
---@param player IsoPlayer|nil
---@param networkId string|nil
---@return boolean allowed
---@return string|nil mode
---@return table|nil terminal
---@return string|nil reason
function GlobalStorageSiK.TerminalAccess.evaluateClientOpen(player, networkId)
	dbgAccess("evaluateClientOpen", string.format("net=%s", tostring(networkId)))
	local ok, mode, terminal, reason = GlobalStorageSiK.TerminalAccess.evaluate(player, networkId, nil, {})
	dbgAccess("evaluateClientOpen.result", string.format(
		"ok=%s mode=%s reason=%s term=%s",
		tostring(ok), tostring(mode), tostring(reason),
		terminal and string.format("%d,%d", terminal.x or 0, terminal.y or 0) or "nil"
	))
	if ok and terminal and terminal.x and GlobalStorageSiK.TerminalManifest and GlobalStorageSiK.TerminalManifest.rememberTerminal then
		GlobalStorageSiK.TerminalManifest.rememberTerminal(player, terminal, { transmit = false })
	end
	return ok, mode, terminal, reason
end

--- Valida apertura con ancla enviada por el servidor (distancia en cliente).
---@param player IsoPlayer|nil
---@param networkId string|nil
---@param payload table|nil
---@return boolean allowed
---@return string|nil mode
---@return table|nil terminal
---@return string|nil reason
function GlobalStorageSiK.TerminalAccess.validateServerOpen(player, networkId, payload)
	if not player then
		return false, nil, nil, "no_player"
	end
	if not GlobalStorageSiK.Sandbox.requireTerminalAccess() then
		return true, "bypass", nil, nil
	end
	payload = payload or {}
	if payload.accessMode == "bypass" then
		return false, nil, nil, "no_terminal"
	end

	local strictOpen = payload.openUi == true
	if strictOpen and payload.terminalAnchor and payload.accessMode then
		if GlobalStorageSiK.TerminalAccess.trustServerForOpen() then
			return true, payload.accessMode, payload.terminalAnchor, nil
		end
	end
	local anchor = payload.terminalAnchor or GlobalStorageSiK.TerminalAccess.getSessionAnchor(player)
	if strictOpen then
		if not payload.terminalAnchor or not payload.accessMode then
			return false, nil, nil, "terminal_out_of_range"
		end
		anchor = payload.terminalAnchor
	elseif not anchor then
		return true, payload.accessMode, nil, nil
	end

	return GlobalStorageSiK.TerminalAccess.evaluate(
		player, networkId, anchor, { sessionLock = true, strictDistance = true }
	)
end

--- True en cliente multijugador puro (sin lógica de servidor local).
---@return boolean
function GlobalStorageSiK.TerminalAccess.isMultiplayerClient()
	return isClient ~= nil and isClient() and isServer ~= nil and not isServer()
end

--- En MP el servidor es autoridad de acceso; el cliente no revalida distancia en bucle.
--- BUG REAL encontrado (trazas de un jugador instalando un segundo terminal
--- en SP real): esta funcion solo confiaba en isClient(), que en SP real da
--- SIEMPRE false (el mismo caso ya documentado en todo el mod - ver
--- GlobalStorageSiK.isAuthoritative()) - asi que en SP el cliente SIEMPRE
--- volvia a revalidar el acceso por su cuenta (validateServerOpen en
--- GS_TerminalUI_Api.lua) en vez de confiar en el resultado ya confirmado
--- por el servidor (terminalAnchor/accessMode en el payload), aunque el log
--- del servidor mostrara accessCheck ok=true sin ambiguedad. Esa revalidacion
--- redundante podia fallar con datos locales desactualizados justo tras
--- vincular un terminal nuevo, dejando la pantalla de bloqueo abierta pese
--- al exito real. En SP real cliente y "servidor" son el MISMO proceso Lua,
--- sin red de por medio, asi que el resultado ya calculado es tan fiable
--- como cualquier chequeo que pudieramos repetir aqui.
---@return boolean
function GlobalStorageSiK.TerminalAccess.trustServerForOpen()
	if isClient ~= nil and isClient() then
		return true
	end
	if not (isClient and isClient()) and not (isServer and isServer()) then
		return true
	end
	return false
end

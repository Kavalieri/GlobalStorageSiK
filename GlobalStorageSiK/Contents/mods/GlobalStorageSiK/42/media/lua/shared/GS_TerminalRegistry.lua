--[[
	GlobalStorageSiK - Registro de terminales físicos en ModData
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Registra posiciones al colocar; cada terminal nuevo crea red con ID único.
]]

require "GS_Network"
require "GS_TerminalAccess"
require "GS_Sandbox"
require "GS_Zones"
require "GS_TerminalCatalog"
require "GS_TerminalRecord"

GlobalStorageSiK.TerminalRegistry = {}

--- Obtiene celda del mundo.
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

--- Comprueba si hay un terminal GS en una baldosa.
---@param x number
---@param y number
---@param z number
---@return boolean|nil
function GlobalStorageSiK.TerminalRegistry.squareHasTerminal(x, y, z)
	local cell = getWorldCell()
	if not cell or not cell.getGridSquare then
		return nil
	end
	local sq = cell:getGridSquare(x, y, z)
	if not sq or not sq.getObjects then
		return nil
	end
	local ok, result = pcall(function()
		local objects = sq:getObjects()
		if not objects then
			return false
		end
		for i = 0, objects:size() - 1 do
			if GlobalStorageSiK.TerminalAccess.isTerminalObject(objects:get(i)) then
				return true
			end
		end
		return false
	end)
	return ok and result == true
end

--- Distancia planar entre dos puntos.
---@param ax number
---@param ay number
---@param bx number
---@param by number
---@return number
local function planarDistance(ax, ay, bx, by)
	local dx = ax - bx
	local dy = ay - by
	return math.sqrt(dx * dx + dy * dy)
end

--- True si ya existe terminal en esas coordenadas.
---@param network table|nil
---@param x number
---@param y number
---@param z number
---@return boolean
local function networkHasTerminalAt(network, x, y, z)
	if not network or not network.terminals then
		return false
	end
	for i = 1, #network.terminals do
		local t = network.terminals[i]
		if t and t.x == x and t.y == y and (t.z or 0) == z then
			return true
		end
	end
	return false
end

--- Devuelve todos los terminales registrados de una red (catálogo ModData).
---@param network table|nil
---@return table[]
function GlobalStorageSiK.TerminalRegistry.getAllTerminals(network)
	if GlobalStorageSiK.TerminalCatalog and GlobalStorageSiK.TerminalCatalog.collectEntries then
		return GlobalStorageSiK.TerminalCatalog.collectEntries(network)
	end
	if not network or not network.terminals then
		return {}
	end
	local out = {}
	for i = 1, #network.terminals do
		local t = network.terminals[i]
		if t and t.x and t.y then
			out[#out + 1] = {
				x = t.x,
				y = t.y,
				z = t.z or 0,
				controller = network.controller
					and network.controller.x == t.x
					and network.controller.y == t.y
					and (network.controller.z or 0) == (t.z or 0),
				status = t.status,
				suspended = t.status == GlobalStorageSiK.TerminalRecord.STATUS_SUSPENDED,
			}
		end
	end
	return out
end

--- Cuenta terminales activos registrados.
---@param network table|nil
---@return number
function GlobalStorageSiK.TerminalRegistry.countTerminals(network)
	return GlobalStorageSiK.TerminalRecord.countActive(network)
end

--- Punto de referencia de la red (terminales, zonas o nodos).
---@param networkId string
---@param network table|nil
---@return table[] refs { x, y, z }
local function collectNetworkReferencePoints(networkId, network)
	local refs = {}
	if network and network.terminals then
		for i = 1, #network.terminals do
			local t = network.terminals[i]
			if t and t.x and t.y then
				refs[#refs + 1] = { x = t.x, y = t.y, z = t.z or 0 }
			end
		end
	end
	if GlobalStorageSiK.Zones and GlobalStorageSiK.Zones.getRegistry then
		local reg = GlobalStorageSiK.Zones.getRegistry()
		for _, zone in pairs(reg.zones or {}) do
			if zone.networkId == networkId and zone.bounds then
				local b = zone.bounds
				if b.x1 and b.y1 and b.x2 and b.y2 then
					refs[#refs + 1] = {
						x = math.floor((b.x1 + b.x2) / 2),
						y = math.floor((b.y1 + b.y2) / 2),
						z = b.z or 0,
					}
				end
			end
		end
	end
	if network and network.containers then
		for i = 1, #network.containers do
			local c = network.containers[i]
			if c and c.x and c.y then
				refs[#refs + 1] = { x = c.x, y = c.y, z = c.z or 0 }
			end
		end
	end
	return refs
end

--- Valida distancia del nuevo terminal respecto al almacén (chunks accesibles).
---@param networkId string
---@param x number
---@param y number
---@param z number
---@return boolean ok
---@return string|nil reason
function GlobalStorageSiK.TerminalRegistry.validateLinkDistance(networkId, x, y, z)
	if not networkId or not GlobalStorageSiK.Network then
		return false, "missing_network"
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local network = registry and registry.networks and registry.networks[networkId]
	if not network then
		return false, "network_not_found"
	end
	local refs = collectNetworkReferencePoints(networkId, network)
	if #refs == 0 then
		return true, nil
	end
	local maxDist = GlobalStorageSiK.Sandbox.getTerminalLinkMaxDistance()
	local nearest = maxDist + 1
	for i = 1, #refs do
		local ref = refs[i]
		if math.floor(z) == math.floor(ref.z or 0) then
			local dist = planarDistance(x, y, ref.x, ref.y)
			if dist < nearest then
				nearest = dist
			end
		end
	end
	if nearest > maxDist then
		return false, "terminal_too_far"
	end
	return true, nil
end

--- Valida límite de terminales por red.
---@param network table|nil
---@return boolean ok
---@return string|nil reason
function GlobalStorageSiK.TerminalRegistry.validateTerminalCapacity(network)
	if not network then
		return false, "network_not_found"
	end
	local maxT = GlobalStorageSiK.Sandbox.getMaxTerminalsPerNetwork()
	if GlobalStorageSiK.TerminalRegistry.countTerminals(network) >= maxT then
		return false, "terminal_limit"
	end
	return true, nil
end

--- Añade terminal a una red (sin reemplazar otros).
---@param networkId string
---@param x number
---@param y number
---@param z number
---@param opts table|nil { setController = boolean }
---@return string|nil
function GlobalStorageSiK.TerminalRegistry.appendTerminal(networkId, x, y, z, opts)
	opts = opts or {}
	if not networkId or not x or not y or z == nil or not GlobalStorageSiK.Network then
		return nil
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local network = registry.networks[networkId]
	if not network then
		return nil
	end
	if networkHasTerminalAt(network, x, y, z) then
		local existing = GlobalStorageSiK.TerminalRecord.findAt(network, x, y, z)
		if existing and not GlobalStorageSiK.TerminalRecord.isActive(existing) then
			GlobalStorageSiK.TerminalRecord.markActive(existing)
		end
		network.relocation = { status = "active" }
		return networkId
	end
	local okCap, capReason = GlobalStorageSiK.TerminalRegistry.validateTerminalCapacity(network)
	if not okCap then
		return nil, capReason
	end
	local okDist, distReason = GlobalStorageSiK.TerminalRegistry.validateLinkDistance(networkId, x, y, z)
	if not okDist then
		return nil, distReason
	end
	network.terminals = network.terminals or {}
	local entry = GlobalStorageSiK.TerminalRecord.create(x, y, z, network)
	network.terminals[#network.terminals + 1] = entry
	if opts.setController == true or not network.controller then
		network.controller = { x = x, y = y, z = z }
	end
	network.relocation = { status = "active" }
	if ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	if GlobalStorageSiK.RegistryStore and GlobalStorageSiK.RegistryStore.notifyChanged then
		GlobalStorageSiK.RegistryStore.notifyChanged()
	end
	return networkId
end

--- Resuelve o crea networkId para un terminal en coordenadas.
---@param player IsoPlayer|nil
---@param x number
---@param y number
---@param z number
---@return string|nil
local function resolveNetworkForTerminal(player, x, y, z)
	local existing = GlobalStorageSiK.Network.findNetworkIdAtTerminal(x, y, z)
	if existing then
		return existing
	end
	return GlobalStorageSiK.Network.createNetwork(player)
end

--- Elimina entradas huérfanas del registro (mueble recogido / destruido).
---@param networkId string|nil nil = todas las redes
---@return boolean changed
function GlobalStorageSiK.TerminalRegistry.pruneInvalid(networkId)
	if not GlobalStorageSiK.Network then
		return false
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	if not registry or not registry.networks then
		return false
	end
	GlobalStorageSiK.Network.ensureRegistry(registry)

	local changed = false
	local function pruneOne(nid, network)
		if not network then
			return
		end
		local localChanged = false
		local kept = {}
		if network.terminals then
			for i = 1, #network.terminals do
				local terminal = network.terminals[i]
				if terminal and terminal.x and terminal.y and terminal.z then
					local verified = GlobalStorageSiK.TerminalRegistry.squareHasTerminal(terminal.x, terminal.y, terminal.z)
					if verified == false then
						localChanged = true
					else
						kept[#kept + 1] = terminal
					end
				end
			end
		end
		network.terminals = kept
		if network.controller and network.controller.x then
			local c = network.controller
			local verified = GlobalStorageSiK.TerminalRegistry.squareHasTerminal(c.x, c.y, c.z)
			if verified == false then
				network.controller = network.terminals and network.terminals[#network.terminals] or nil
				localChanged = true
			end
		end
		if localChanged then
			changed = true
		end
	end

	if networkId and registry.networks[networkId] then
		pruneOne(networkId, registry.networks[networkId])
	else
		for nid, network in pairs(registry.networks) do
			pruneOne(nid, network)
		end
	end

	if changed and ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	return changed
end

--- Suspende terminal al recogerlo (conserva entrada en registro con estado suspended).
---@param networkId string|nil
---@param x number
---@param y number
---@param z number
---@return string|nil networkId suspendido
function GlobalStorageSiK.TerminalRegistry.suspendTerminalAt(networkId, x, y, z)
	if not x or not y or z == nil or not GlobalStorageSiK.Network then
		return nil
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local nid = networkId or GlobalStorageSiK.Network.findNetworkIdAtTerminal(x, y, z)
	if not nid then
		return nil
	end
	local network = registry.networks[nid]
	if not network then
		return nil
	end

	local changed = false
	local entry = GlobalStorageSiK.TerminalRecord.findAt(network, x, y, z)
	if entry then
		GlobalStorageSiK.TerminalRecord.markSuspended(entry)
		changed = true
	else
		entry = GlobalStorageSiK.TerminalRecord.create(x, y, z, network)
		GlobalStorageSiK.TerminalRecord.markSuspended(entry)
		network.terminals = network.terminals or {}
		network.terminals[#network.terminals + 1] = entry
		changed = true
	end

	if network.controller
		and network.controller.x == x
		and network.controller.y == y
		and network.controller.z == z then
		network.controller = nil
		local anchors = GlobalStorageSiK.TerminalRecord.collectActiveAnchors(network)
		if anchors[1] then
			network.controller = {
				x = anchors[1].x,
				y = anchors[1].y,
				z = anchors[1].z or 0,
			}
		end
		changed = true
	end

	network.relocation = {
		status = "displaced",
		lastX = x,
		lastY = y,
		lastZ = z,
		displacedAt = (getTimestampMs and getTimestampMs()) or 0,
	}
	changed = true

	if changed and ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	if changed and GlobalStorageSiK.RegistryStore and GlobalStorageSiK.RegistryStore.notifyChanged then
		GlobalStorageSiK.RegistryStore.notifyChanged()
	end
	return nid
end

--- Renombra un terminal concreto (etiqueta propia, independiente del nombre
--- de la red). nil o "" borra la etiqueta (vuelve a mostrarse por coordenadas).
---@param networkId string|nil
---@param x number
---@param y number
---@param z number
---@param label string|nil
---@return boolean ok
function GlobalStorageSiK.TerminalRegistry.renameTerminalAt(networkId, x, y, z, label)
	if not x or not y or z == nil or not GlobalStorageSiK.Network then
		return false
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local nid = networkId or GlobalStorageSiK.Network.findNetworkIdAtTerminal(x, y, z)
	if not nid then
		return false
	end
	local network = registry.networks[nid]
	if not network then
		return false
	end
	local entry = GlobalStorageSiK.TerminalRecord.findAt(network, x, y, z)
	if not entry then
		return false
	end
	entry.label = (label and label ~= "") and label or nil
	if ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	if GlobalStorageSiK.RegistryStore and GlobalStorageSiK.RegistryStore.notifyChanged then
		GlobalStorageSiK.RegistryStore.notifyChanged()
	end
	return true
end

--- Marca un terminal ACTIVO de la red como "principal" (controller): el que
--- define desde donde se mide la cobertura de red (ver
--- GS_Sandbox.isWithinNetworkRange/GS_TerminalRecord.getPrimaryAnchor).
--- "en principio no cambia el rango de la red, el primer terminal colocado
--- decide" ya no es una limitacion fija: el jugador puede reasignarlo aqui.
---@param networkId string|nil
---@param x number
---@param y number
---@param z number
---@return boolean ok
---@return string|nil reason
function GlobalStorageSiK.TerminalRegistry.setControllerAt(networkId, x, y, z)
	if not x or not y or z == nil or not GlobalStorageSiK.Network then
		return false, "invalid_coords"
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local nid = networkId or GlobalStorageSiK.Network.findNetworkIdAtTerminal(x, y, z)
	if not nid then
		return false, "network_not_found"
	end
	local network = registry.networks[nid]
	if not network then
		return false, "network_not_found"
	end
	local entry = GlobalStorageSiK.TerminalRecord.findAt(network, x, y, z)
	if not entry or not GlobalStorageSiK.TerminalRecord.isActive(entry) then
		return false, "terminal_not_active"
	end
	network.controller = { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
	if ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	if GlobalStorageSiK.RegistryStore and GlobalStorageSiK.RegistryStore.notifyChanged then
		GlobalStorageSiK.RegistryStore.notifyChanged()
	end
	return true
end

--- Busca, entre TODAS las redes registradas, el terminal (activo o
--- suspendido) mas cercano al jugador segun el REGISTRO, exista o no ya el
--- ordenador fisico. Distinto de TerminalAccess.findNearestTerminal, que
--- solo ve objetos vivos del mundo - esto encuentra tambien posiciones ya
--- dadas de baja, para poder avisar "aqui HABIA un terminal" en vez de un
--- generico "no hay terminal cerca".
---@param player IsoPlayer
---@param maxRange number
---@return table|nil { x, y, z, networkId, active, distance }
function GlobalStorageSiK.TerminalRegistry.findNearestKnownAnchor(player, maxRange)
	if not player or not maxRange or maxRange <= 0 then
		return nil
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local px, py = player:getX(), player:getY()
	local best, bestDist = nil, maxRange + 1
	for networkId, net in pairs(registry.networks or {}) do
		for _, t in ipairs(net.terminals or {}) do
			if t and t.x and t.y then
				local dx, dy = px - t.x, py - t.y
				local dist = math.sqrt(dx * dx + dy * dy)
				if dist <= maxRange and dist < bestDist then
					bestDist = dist
					best = {
						x = t.x, y = t.y, z = t.z or 0,
						networkId = networkId,
						active = GlobalStorageSiK.TerminalRecord.isActive(t),
						distance = dist,
					}
				end
			end
		end
	end
	return best
end

--- Devuelve ancla activa principal (sin fantasmas de relocation).
---@param network table|nil
---@return table|nil
function GlobalStorageSiK.TerminalRegistry.getActiveAnchor(network)
	local anchor = GlobalStorageSiK.TerminalRecord.getPrimaryAnchor(network)
	if not anchor then
		return nil
	end
	return {
		x = anchor.x,
		y = anchor.y,
		z = anchor.z or 0,
	}
end

--- Colapsa historial de posiciones a una sola ancla activa por red.
---@param network table|nil
---@return boolean changed
function GlobalStorageSiK.TerminalRegistry.compactTerminals(network)
	if not network then
		return false
	end
	local anchor = GlobalStorageSiK.TerminalRegistry.getActiveAnchor(network)
	if not anchor then
		local had = network.terminals and #network.terminals > 0
		network.terminals = {}
		network.controller = nil
		return had == true
	end
	local prevCount = network.terminals and #network.terminals or 0
	local prev = network.controller
	local changed = prevCount ~= 1
	if prev and (prev.x ~= anchor.x or prev.y ~= anchor.y or (prev.z or 0) ~= anchor.z) then
		changed = true
	end
	if network.terminals and #network.terminals == 1 then
		local t = network.terminals[1]
		if t and (t.x ~= anchor.x or t.y ~= anchor.y or (t.z or 0) ~= anchor.z) then
			changed = true
		end
	elseif prevCount > 1 then
		changed = true
	end
	network.terminals = { anchor }
	network.controller = anchor
	return changed
end

--- Compacta terminales de todas las redes (migración saves con historial).
---@return boolean changed
function GlobalStorageSiK.TerminalRegistry.compactAllNetworks()
	if not GlobalStorageSiK.Network then
		return false
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	if not registry or not registry.networks then
		return false
	end
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local changed = false
	for _, network in pairs(registry.networks) do
		if GlobalStorageSiK.TerminalRegistry.compactTerminals(network) then
			changed = true
		end
	end
	if changed and ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	return changed
end

--- Reconcilia anclas al arrancar: compacta y marca terminales desplazados.
---@return boolean changed
function GlobalStorageSiK.TerminalRegistry.reconcileAllNetworks()
	if not GlobalStorageSiK.Network then
		return false
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	if not registry or not registry.networks then
		return false
	end
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local changed = false
	for nid, network in pairs(registry.networks) do
		-- Guarda para terminales instalados antes de que existiera el
		-- nombre por defecto ("Terminal N"): rellena SOLO las etiquetas que
		-- siguen en blanco (nunca pisa un nombre puesto a mano). Corre en
		-- cada carga de partida en vez de detras de un flag de migracion de
		-- una sola vez, para que alcance tambien a mundos donde la
		-- migracion antigua ya se ejecuto antes de que esto existiera.
		if GlobalStorageSiK.TerminalRecord and GlobalStorageSiK.TerminalRecord.normalizeAll then
			if GlobalStorageSiK.TerminalRecord.normalizeAll(network) then
				changed = true
			end
		end
		local anchor = GlobalStorageSiK.TerminalRegistry.getActiveAnchor(network)
		if anchor then
			local verified = GlobalStorageSiK.TerminalRegistry.squareHasTerminal(anchor.x, anchor.y, anchor.z or 0)
			if verified == false then
				network.relocation = {
					status = "displaced",
					lastX = anchor.x,
					lastY = anchor.y,
					lastZ = anchor.z or 0,
				}
				changed = true
			elseif verified == true and network.relocation and network.relocation.status == "displaced" then
				network.relocation = { status = "active" }
				changed = true
			end
		elseif network.relocation == nil then
			network.relocation = { status = "needs_recovery" }
			changed = true
		end
	end
	if changed and ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	if changed and GlobalStorageSiK.Debug and GlobalStorageSiK.Debug.log then
		GlobalStorageSiK.Debug.log("TerminalRegistry", "reconcileAll", "done")
	end
	return changed
end

--- Aplica hint del cliente: solo etiqueta objeto, no mueve anclas del registro.
---@param player IsoPlayer|nil
---@param hint table|nil { x, y, z, networkId }
---@param proxRange number|nil
---@return boolean tagged
function GlobalStorageSiK.TerminalRegistry.applyPlayerTerminalHint(player, hint, proxRange)
	if not player or not hint or not hint.x or not hint.y or not proxRange or proxRange <= 0 then
		return false
	end
	local dx = player:getX() - hint.x
	local dy = player:getY() - hint.y
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist > proxRange + 0.5 then
		return false
	end
	if math.floor(player:getZ()) ~= math.floor(hint.z or 0) then
		return false
	end
	local nid = hint.networkId
	if (not nid or nid == "") and GlobalStorageSiK.Network then
		nid = GlobalStorageSiK.Network.findNetworkIdAtTerminal(hint.x, hint.y, hint.z or 0, {
			activeOnly = true,
		})
	end
	if not nid or nid == "" then
		return false
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	if not registry.networks or not registry.networks[nid] then
		return false
	end
	if GlobalStorageSiK.Permissions then
		local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(player, nid))
		if not allowed then
			return false
		end
	end
	if GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.tryTagSquare then
		GlobalStorageSiK.TerminalAccess.tryTagSquare(
			math.floor(hint.x), math.floor(hint.y), math.floor(hint.z or 0), nid
		)
	end
	if GlobalStorageSiK.Debug and GlobalStorageSiK.Debug.log then
		GlobalStorageSiK.Debug.log("TerminalRegistry", "applyHint", string.format(
			"net=%s hint=%d,%d,%d dist=%.2f tagOnly",
			tostring(nid), math.floor(hint.x), math.floor(hint.y), math.floor(hint.z or 0), dist
		))
	end
	return true
end

--- Resuelve red del terminal físico cercano sin mutar el registro.
---@param player IsoPlayer|nil
---@param networkId string|nil
---@param proxRange number|nil
---@return string|nil resolvedNetworkId
function GlobalStorageSiK.TerminalRegistry.snapAnchorFromWorldIfNear(player, networkId, proxRange)
	if not player or not proxRange or proxRange <= 0 then
		return nil
	end
	if not GlobalStorageSiK.TerminalAccess or not GlobalStorageSiK.TerminalAccess.findNearestTerminal then
		return nil
	end
	local world = GlobalStorageSiK.TerminalAccess.findNearestTerminal(player, proxRange)
	if not world or not world.x or not world.y or (world.distance or 99) > proxRange then
		return nil
	end
	local verified = GlobalStorageSiK.TerminalRegistry.squareHasTerminal(world.x, world.y, world.z or 0)
	if verified == false then
		return nil
	end
	local nid = networkId
	if world.object and GlobalStorageSiK.TerminalAccess.resolveObjectNetworkId then
		local objNet = GlobalStorageSiK.TerminalAccess.resolveObjectNetworkId(world.object)
		if objNet and objNet ~= "" then
			nid = objNet
		end
	end
	if (not nid or nid == "") and GlobalStorageSiK.Network then
		nid = GlobalStorageSiK.Network.findNetworkIdAtTerminal(world.x, world.y, world.z or 0, {
			activeOnly = true,
		})
	end
	if GlobalStorageSiK.Debug and GlobalStorageSiK.Debug.log and nid then
		GlobalStorageSiK.Debug.log("TerminalRegistry", "probeWorld", string.format(
			"net=%s world=%d,%d,%d",
			tostring(nid), world.x, world.y, world.z or 0
		))
	end
	return nid
end

--- Registra o reactiva terminal en coordenadas (multi-terminal; no colapsa otras entradas).
---@param networkId string
---@param x number
---@param y number
---@param z number
---@param opts table|nil { setController = boolean }
---@return string|nil
function GlobalStorageSiK.TerminalRegistry.rebindTerminal(networkId, x, y, z, opts)
	opts = opts or {}
	if not networkId or not x or not y or z == nil or not GlobalStorageSiK.Network then
		return nil
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local network = registry.networks[networkId]
	if not network then
		return nil
	end
	x, y, z = math.floor(x), math.floor(y), math.floor(z)
	local entry = GlobalStorageSiK.TerminalRecord.findAt(network, x, y, z)
	if entry then
		GlobalStorageSiK.TerminalRecord.markActive(entry)
		if opts.setController == true then
			network.controller = { x = x, y = y, z = z }
		end
		network.relocation = { status = "active" }
	else
		return GlobalStorageSiK.TerminalRegistry.appendTerminal(networkId, x, y, z, {
			setController = opts.setController == true,
		})
	end
	if ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	return networkId
end

--- Registra un terminal colocado (nueva red, vincular o reubicar).
---@param networkId string|nil gsnNetworkId del ítem o red conocida
---@param x number
---@param y number
---@param z number
---@param player IsoPlayer|nil creador de red nueva
---@param opts table|nil { createIfMissing = boolean, placementMode = string }
---@return string|nil networkId usado
---@return string|nil errorReason
function GlobalStorageSiK.TerminalRegistry.register(networkId, x, y, z, player, opts)
	opts = opts or {}
	if not x or not y or z == nil or not GlobalStorageSiK.Network then
		return nil, "invalid_coords"
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local mode = opts.placementMode or "auto"
	x, y, z = math.floor(x), math.floor(y), math.floor(z)

	if mode == "new" or (mode == "auto" and (not networkId or networkId == "")) then
		-- Purgar entradas suspendidas en otras redes para estas coordenadas.
		-- Evita que la nueva red coexista con entradas zombie de redes antiguas.
		local purgeReg = GlobalStorageSiK.Network.getRegistry()
		if purgeReg and purgeReg.networks then
			for purgeNid, purgeNet in pairs(purgeReg.networks) do
				if purgeNet.terminals then
					local kept = {}
					for i = 1, #purgeNet.terminals do
						local t = purgeNet.terminals[i]
						if t and math.floor(t.x) == x and math.floor(t.y) == y and math.floor(t.z or 0) == z
							and not GlobalStorageSiK.TerminalRecord.isActive(t) then
							-- Eliminar entrada suspendida en coords destino
						else
							kept[#kept + 1] = t
						end
					end
					purgeNet.terminals = kept
				end
			end
		end
		local nid = GlobalStorageSiK.Network.createNetwork(player)
		if not nid then
			return nil, "create_failed"
		end
		return GlobalStorageSiK.TerminalRegistry.appendTerminal(nid, x, y, z, { setController = true })
	end

	if networkId and registry.networks[networkId] then
		local net = registry.networks[networkId]
		if networkHasTerminalAt(net, x, y, z) then
			local existing = GlobalStorageSiK.TerminalRecord.findAt(net, x, y, z)
			if existing and not GlobalStorageSiK.TerminalRecord.isActive(existing) then
				GlobalStorageSiK.TerminalRecord.markActive(existing)
			end
			net.relocation = { status = "active" }
			return networkId, nil
		end
		local appended, reason = GlobalStorageSiK.TerminalRegistry.appendTerminal(networkId, x, y, z, { setController = false })
		return appended, reason
	end

	local atCoords = GlobalStorageSiK.Network.findNetworkIdAtTerminal(x, y, z)
	if atCoords and registry.networks[atCoords] then
		if networkHasTerminalAt(registry.networks[atCoords], x, y, z) then
			return atCoords, nil
		end
		local appended, reason = GlobalStorageSiK.TerminalRegistry.appendTerminal(atCoords, x, y, z, { setController = false })
		return appended, reason
	end

	if networkId and networkId ~= "" and not registry.networks[networkId] and opts.createIfMissing then
		registry.networks[networkId] = {
			id = networkId,
			name = "Red " .. string.sub(networkId, -6),
			owner = player and GlobalStorageSiK.Permissions and GlobalStorageSiK.Permissions.getCharacterName(player) or "",
			ownerAccount = player and player.getUsername and player:getUsername() or "",
			terminals = {},
			containers = {},
			addonInstalls = {},
			createdMs = (getTimestampMs and getTimestampMs()) or 0,
		}
		if GlobalStorageSiK.Permissions and player then
			GlobalStorageSiK.Permissions.ensure(registry, networkId, GlobalStorageSiK.Permissions.getCharacterName(player))
		end
		return GlobalStorageSiK.TerminalRegistry.appendTerminal(networkId, x, y, z, { setController = true }), nil
	end

	local nid = resolveNetworkForTerminal(player, x, y, z)
	if not nid then
		return nil, "resolve_failed"
	end
	return GlobalStorageSiK.TerminalRegistry.appendTerminal(nid, x, y, z, { setController = true }), nil
end

--- Elimina terminal del registro (destruido sin recoger; no conserva red).
---@param networkId string|nil
---@param x number
---@param y number
---@param z number
---@return boolean
function GlobalStorageSiK.TerminalRegistry.unregister(networkId, x, y, z)
	if not x or not y or z == nil or not GlobalStorageSiK.Network then
		return false
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	if not registry or not registry.networks then
		return false
	end
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local nid = networkId or GlobalStorageSiK.Network.findNetworkIdAtTerminal(x, y, z)
	if not nid then
		return false
	end
	local network = registry.networks[nid]
	if not network then
		return false
	end

	local changed = false
	if network.terminals then
		local kept = {}
		for i = 1, #network.terminals do
			local terminal = network.terminals[i]
			if terminal and terminal.x == x and terminal.y == y and terminal.z == z then
				changed = true
			elseif terminal then
				kept[#kept + 1] = terminal
			end
		end
		network.terminals = kept
	end

	if network.controller and network.controller.x == x and network.controller.y == y and network.controller.z == z then
		network.controller = network.terminals and network.terminals[#network.terminals] or nil
		changed = true
	end

	if changed and ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	return changed
end

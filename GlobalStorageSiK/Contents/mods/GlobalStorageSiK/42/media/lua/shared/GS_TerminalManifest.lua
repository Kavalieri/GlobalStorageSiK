--[[
	GlobalStorageSiK - Manifiesto de terminales (proximidad por coordenadas)
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: Lista de terminales conocidas por red; gate de proximidad sin escaneo de chunks.
]]

require "GS_Config"
require "GS_Sandbox"
require "GS_Network"
require "GS_TerminalRecord"
require "GS_Permissions"
require "GS_Debug"

GlobalStorageSiK.TerminalManifest = {}

--- Rango inalámbrico del jugador (lazy; evita require circular).
---@param player IsoPlayer|nil
---@return number
local function wirelessRangeFor(player)
	if GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.getWirelessRangeForPlayer then
		return GlobalStorageSiK.TerminalAccess.getWirelessRangeForPlayer(player)
	end
	return GlobalStorageSiK.Sandbox.getWirelessRange()
end

--- Tableta en inventario (lazy).
---@param player IsoPlayer|nil
---@return boolean
local function playerHasTablet(player)
	if GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.hasTablet then
		return GlobalStorageSiK.TerminalAccess.hasTablet(player)
	end
	return false
end

--- Distancia planar jugador → punto.
---@param player IsoPlayer
---@param x number
---@param y number
---@return number
local function planarDistance(player, x, y)
	local dx = player:getX() - x
	local dy = player:getY() - y
	return math.sqrt(dx * dx + dy * dy)
end

--- Planta del jugador.
---@param player IsoPlayer
---@return number
local function playerFloorZ(player)
	return math.floor(player:getZ())
end

--- Añade candidato si está más cerca.
---@param best table|nil
---@param bestDist number
---@param entry table
---@param player IsoPlayer
---@param maxRange number
---@return table|nil, number
local function considerEntry(best, bestDist, entry, player, maxRange)
	if not entry or not entry.x or not entry.y then
		return best, bestDist
	end
	local z = math.floor(entry.z or 0)
	if playerFloorZ(player) ~= z then
		return best, bestDist
	end
	local dist = planarDistance(player, entry.x, entry.y)
	if dist <= maxRange and dist < bestDist then
		return {
			x = entry.x,
			y = entry.y,
			z = z,
			networkId = entry.networkId,
			distance = dist,
			controller = entry.controller == true,
		}, dist
	end
	return best, bestDist
end

--- Recopila terminales de redes a las que el jugador tiene acceso (servidor / SP).
---@param player IsoPlayer
---@return table manifest
function GlobalStorageSiK.TerminalManifest.buildForPlayer(player)
	if not GlobalStorageSiK.TerminalRegistry then
		require "GS_TerminalRegistry"
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local terminals = {}

	for networkId, _ in pairs(registry.networks or {}) do
		local allowed = select(1, GlobalStorageSiK.Permissions.canAccess(player, networkId))
		if allowed then
			local net = registry.networks[networkId]
			if net and GlobalStorageSiK.TerminalRegistry and GlobalStorageSiK.TerminalRegistry.getAllTerminals then
				local all = GlobalStorageSiK.TerminalRegistry.getAllTerminals(net)
				for i = 1, #all do
					local t = all[i]
					if not t.suspended and t.status ~= GlobalStorageSiK.TerminalRecord.STATUS_SUSPENDED then
						terminals[#terminals + 1] = {
							x = t.x,
							y = t.y,
							z = t.z or 0,
							networkId = networkId,
							controller = t.controller == true,
						}
					end
				end
			elseif net and GlobalStorageSiK.TerminalRegistry and GlobalStorageSiK.TerminalRegistry.getActiveAnchor then
				local anchor = GlobalStorageSiK.TerminalRegistry.getActiveAnchor(net)
				if anchor then
					terminals[#terminals + 1] = {
						x = anchor.x,
						y = anchor.y,
						z = anchor.z or 0,
						networkId = networkId,
						controller = true,
					}
				end
			end
		end
	end

	return {
		terminals = terminals,
		proxRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange(),
		wirelessRange = wirelessRangeFor(player),
	}
end

local CACHE_MD_KEY = "gsKnownTerminals"

--- Lee terminales recordadas en el jugador (cliente).
---@param player IsoPlayer|nil
---@return table[]
function GlobalStorageSiK.TerminalManifest.getLocalTerminals(player)
	if not player or not player.getModData then
		return {}
	end
	local md = player:getModData()
	local list = md and md[CACHE_MD_KEY]
	if type(list) ~= "table" then
		return {}
	end
	local out = {}
	for i = 1, #list do
		local t = list[i]
		if t and t.x and t.y then
			out[#out + 1] = {
				x = t.x,
				y = t.y,
				z = t.z or 0,
				networkId = t.networkId,
			}
		end
	end
	return out
end

--- Persiste un terminal descubierto (sesión / confirmación servidor).
---@param player IsoPlayer|nil
---@param entry table|nil
---@param opts table|nil { transmit = boolean|nil }
function GlobalStorageSiK.TerminalManifest.rememberTerminal(player, entry, opts)
	if not player or not entry or not entry.x or not entry.y or not player.getModData then
		return
	end
	opts = opts or {}
	local networkId = entry.networkId
	if not networkId and entry.x and GlobalStorageSiK.Network and GlobalStorageSiK.Network.findNetworkIdAtTerminal then
		networkId = GlobalStorageSiK.Network.findNetworkIdAtTerminal(entry.x, entry.y, entry.z or 0)
	end
	local rec = {
		x = entry.x,
		y = entry.y,
		z = entry.z or 0,
		networkId = networkId,
	}
	local md = player:getModData()
	local list = md[CACHE_MD_KEY]
	if type(list) ~= "table" then
		list = {}
		md[CACHE_MD_KEY] = list
	end
	local replaced = false
	local unchanged = false
	for i = 1, #list do
		local t = list[i]
		if t and (
			(networkId and networkId ~= "" and t.networkId == networkId)
			or (math.floor(t.x) == math.floor(rec.x) and math.floor(t.y) == math.floor(rec.y) and math.floor(t.z or 0) == math.floor(rec.z))
		) then
			unchanged = math.floor(t.x) == math.floor(rec.x)
				and math.floor(t.y) == math.floor(rec.y)
				and math.floor(t.z or 0) == math.floor(rec.z)
				and tostring(t.networkId or "") == tostring(networkId or "")
			list[i] = rec
			replaced = true
			break
		end
	end
	if not replaced then
		list[#list + 1] = rec
	end
	if GlobalStorageSiK.Debug and GlobalStorageSiK.Debug.log and not unchanged then
		GlobalStorageSiK.Debug.log("TerminalManifest", "remember", string.format(
			"%d,%d,%d net=%s replaced=%s total=%d",
			rec.x, rec.y, rec.z, tostring(networkId), tostring(replaced), #list
		))
	end
	if opts.transmit ~= false and not unchanged and player.transmitModData then
		player:transmitModData()
	end
end

--- Deja como máximo una entrada por red en la caché local del jugador.
---@param player IsoPlayer|nil
---@param opts table|nil { transmit = boolean|nil }
---@return table[]
function GlobalStorageSiK.TerminalManifest.pruneLocalTerminalCache(player, opts)
	opts = opts or {}
	if not player or not player.getModData then
		return {}
	end
	local md = player:getModData()
	local list = md[CACHE_MD_KEY]
	if type(list) ~= "table" or #list == 0 then
		return {}
	end
	local byNet = {}
	local orphans = {}
	for i = 1, #list do
		local t = list[i]
		if t and t.x and t.y then
			local nid = t.networkId
			if nid and nid ~= "" then
				byNet[nid] = t
			else
				orphans[#orphans + 1] = t
			end
		end
	end
	local newList = {}
	for _, t in pairs(byNet) do
		newList[#newList + 1] = t
	end
	if #orphans > 0 then
		newList[#newList + 1] = orphans[#orphans]
	end
	if #newList ~= #list then
		md[CACHE_MD_KEY] = newList
		if opts.transmit ~= false and player.transmitModData then
			player:transmitModData()
		end
		if GlobalStorageSiK.Debug and GlobalStorageSiK.Debug.log then
			GlobalStorageSiK.Debug.log("TerminalManifest", "pruneLocal", string.format(
				"%d -> %d entries", #list, #newList
			))
		end
	end
	return newList
end

--- Fusiona caché local, manifiesto del servidor y registro ModData (sin escaneo de mundo).
---@param player IsoPlayer|nil
---@return table manifest
function GlobalStorageSiK.TerminalManifest.getEffectiveManifest(player)
	-- isAuthoritative() PRIMERO, antes de mirar la cache de cliente: en SP
	-- real, cliente y servidor comparten la MISMA VM de Lua, asi que
	-- GlobalStorageSiK.Client.terminalManifest (poblada por el ultimo
	-- "terminalManifest" push recibido - ej. al cargar la partida, cuando
	-- aun no habia ningun terminal) es visible aqui TAMBIEN, y si se
	-- consultara antes de esta rama, una evaluacion autoritativa (llamada
	-- desde TerminalAccess.evaluate en el propio servidor) devolveria ese
	-- snapshot obsoleto para siempre, sin importar cuantos terminales se
	-- instalen despues - confirmado como la causa real de "instalar
	-- terminal + abrir la interfaz no detecta nada" en SP real. Igual que
	-- isServer() (que YA estaba mal aqui: daba false en SP real y esta
	-- rama nunca se tomaba), pero aplicado a una cache en vez de a un gate.
	if GlobalStorageSiK.isAuthoritative() and player and GlobalStorageSiK.TerminalManifest.buildForPlayer then
		if GlobalStorageSiK.TerminalManifest.pruneLocalTerminalCache then
			GlobalStorageSiK.TerminalManifest.pruneLocalTerminalCache(player, { transmit = false })
		end
		local ok, built = pcall(GlobalStorageSiK.TerminalManifest.buildForPlayer, player)
		if ok and built then
			if GlobalStorageSiK.Debug and GlobalStorageSiK.Debug.log then
				GlobalStorageSiK.Debug.log("TerminalManifest", "getEffective", string.format(
					"terminals=%d prox=%s wireless=%s (server)",
					#(built.terminals or {}),
					tostring(built.proxRange),
					tostring(built.wirelessRange)
				))
			end
			return built
		end
	end

	-- Cliente MP puro (isAuthoritative() false): sin acceso directo al
	-- registro, usar el ultimo manifiesto que el servidor nos envio.
	if GlobalStorageSiK.Client and GlobalStorageSiK.Client.terminalManifest then
		local server = GlobalStorageSiK.Client.terminalManifest
		return {
			terminals = server.terminals or {},
			proxRange = server.proxRange or GlobalStorageSiK.Sandbox.getTerminalProximityRange(),
			wirelessRange = server.wirelessRange or wirelessRangeFor(player),
		}
	end

	local terminals = {}
	local seen = {}
	local function add(entry)
		if not entry or not entry.x or not entry.y then
			return
		end
		local key = string.format(
			"%s:%d:%d:%d",
			tostring(entry.networkId or ""),
			math.floor(entry.x),
			math.floor(entry.y),
			math.floor(entry.z or 0)
		)
		if seen[key] then
			return
		end
		seen[key] = true
		terminals[#terminals + 1] = {
			x = entry.x,
			y = entry.y,
			z = entry.z or 0,
			networkId = entry.networkId,
			controller = entry.controller == true,
		}
	end

	for _, t in ipairs(GlobalStorageSiK.TerminalManifest.getLocalTerminals(player)) do
		add(t)
	end
	if player and GlobalStorageSiK.TerminalManifest.buildForPlayer then
		local ok, built = pcall(GlobalStorageSiK.TerminalManifest.buildForPlayer, player)
		if ok and built then
			for _, t in ipairs(built.terminals or {}) do
				add(t)
			end
		end
	end

	local manifest = {
		terminals = terminals,
		proxRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange(),
		wirelessRange = wirelessRangeFor(player),
	}
	if GlobalStorageSiK.Debug and GlobalStorageSiK.Debug.log then
		GlobalStorageSiK.Debug.log("TerminalManifest", "getEffective", string.format(
			"terminals=%d prox=%s wireless=%s",
			#terminals,
			tostring(manifest.proxRange),
			tostring(manifest.wirelessRange)
		))
	end
	return manifest
end

--- Aplica manifiesto enviado por el servidor y fusiona con caché local.
---@param player IsoPlayer|nil
---@param manifest table|nil
function GlobalStorageSiK.TerminalManifest.applyFromServer(player, manifest)
	if not manifest then
		return
	end
	if GlobalStorageSiK.Client then
		GlobalStorageSiK.Client.terminalManifest = manifest
	end
	if player and player.getModData and manifest.terminals then
		local md = player:getModData()
		local list = {}
		for i = 1, #(manifest.terminals) do
			local t = manifest.terminals[i]
			if t and t.x and t.y then
				list[#list + 1] = {
					x = t.x,
					y = t.y,
					z = t.z or 0,
					networkId = t.networkId,
				}
			end
		end
		md[CACHE_MD_KEY] = list
	end
end

--- Evalúa proximidad solo con coordenadas del manifiesto (sin escaneo de mundo).
---@param player IsoPlayer|nil
---@param manifest table|nil
---@param filterNetworkId string|nil
---@return boolean allowed
---@return table|nil nearest
---@return string|nil mode physical|wireless
---@return string|nil reason
function GlobalStorageSiK.TerminalManifest.evaluateProximity(player, manifest, filterNetworkId)
	if not player then
		return false, nil, nil, "no_player"
	end
	if not GlobalStorageSiK.Sandbox.requireTerminalAccess() then
		return true, nil, "bypass", nil
	end
	manifest = manifest or {}
	local proxRange = manifest.proxRange or GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	local wirelessRange = manifest.wirelessRange or wirelessRangeFor(player)
	local scanRange = math.max(proxRange, wirelessRange)

	local best = nil
	local bestDist = scanRange + 1
	for i = 1, #(manifest.terminals or {}) do
		local entry = manifest.terminals[i]
		if entry and entry.x and entry.y then
			local nid = entry.networkId
			if not filterNetworkId or not nid or nid == filterNetworkId then
				best, bestDist = considerEntry(best, bestDist, entry, player, scanRange)
			end
		end
	end

	if not best then
		if GlobalStorageSiK.Debug and GlobalStorageSiK.Debug.log then
			GlobalStorageSiK.Debug.log("TerminalManifest", "evaluateProximity", "no_terminal in manifest")
		end
		return false, nil, nil, "no_terminal"
	end
	if GlobalStorageSiK.Debug and GlobalStorageSiK.Debug.log then
		GlobalStorageSiK.Debug.log("TerminalManifest", "evaluateProximity", string.format(
			"nearest=%.2f@%d,%d prox=%.1f wireless=%.1f",
			best.distance or -1, best.x or 0, best.y or 0, proxRange, wirelessRange
		))
	end
	if best.distance <= proxRange then
		return true, best, "physical", nil
	end
	if playerHasTablet(player) then
		local networkId = best.networkId
		if not networkId and best.x then
			networkId = GlobalStorageSiK.Network.findNetworkIdAtTerminal(best.x, best.y, best.z or 0)
		end
		local netRange = GlobalStorageSiK.TerminalAccess and GlobalStorageSiK.TerminalAccess.getWirelessRangeForNetwork
			and GlobalStorageSiK.TerminalAccess.getWirelessRangeForNetwork(player, networkId, best)
			or wirelessRange
		if best.distance <= netRange then
			if GlobalStorageSiK.Addons and not GlobalStorageSiK.Addons.canUseTabletWireless(networkId, best) then
				return false, best, nil, "tablet_addon_required"
			end
			return true, best, "wireless", nil
		end
		if best.distance <= wirelessRange then
			return false, best, nil, "antenna_out_of_range"
		end
		return false, best, nil, "tablet_out_of_range"
	end
	return false, best, nil, "terminal_out_of_range"
end

--- True si el jugador está fuera de rango de todas las terminales del manifiesto.
---@param player IsoPlayer|nil
---@param manifest table|nil
---@return boolean
function GlobalStorageSiK.TerminalManifest.isFarFromAll(player, manifest)
	local ok = GlobalStorageSiK.TerminalManifest.evaluateProximity(player, manifest)
	return ok ~= true
end

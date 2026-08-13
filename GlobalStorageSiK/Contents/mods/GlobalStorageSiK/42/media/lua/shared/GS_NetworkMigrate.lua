--[[
	GlobalStorageSiK - Migración de redes legacy
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: Convierte la red «main» a ID gsn_* sin perder zonas, nodos ni permisos.
]]

require "GS_NetworkId"
require "GS_TerminalRegistry"
require "GS_TerminalRecord"
require "GS_Config"

GlobalStorageSiK.NetworkMigrate = {}

local LEGACY_MAIN_ID = "main"
local MIGRATE_FLAG = "_migrateV1060"
local MIGRATE_V1070 = "_migrateV1070"
local MIGRATE_V1080 = "_migrateV1080"

--- Sincroniza controller → lista terminals (partidas antiguas).
---@param net table
local function syncTerminalsFromController(net)
	if not net then
		return
	end
	net.terminals = net.terminals or {}
	if not net.controller or not net.controller.x then
		return
	end
	local c = net.controller
	for i = 1, #net.terminals do
		local t = net.terminals[i]
		if t and t.x == c.x and t.y == c.y and t.z == c.z then
			return
		end
	end
	net.terminals[#net.terminals + 1] = { x = c.x, y = c.y, z = c.z }
end

--- True si hay zonas apuntando a un networkId.
---@param registry table
---@param networkId string
---@return boolean
local function hasZonesFor(registry, networkId)
	for _, zone in pairs(registry.zones or {}) do
		if zone and zone.networkId == networkId then
			return true
		end
	end
	return false
end

--- Reasigna networkId en zonas.
---@param registry table
---@param fromId string
---@param toId string
local function retargetZones(registry, fromId, toId)
	for _, zone in pairs(registry.zones or {}) do
		if zone and zone.networkId == fromId then
			zone.networkId = toId
		end
	end
end

--- Migra registry.networks[main] → gsn_* (una sola vez por partida, solo servidor).
---@param registry table
---@return boolean changed
function GlobalStorageSiK.NetworkMigrate.run(registry)
	if not registry or registry[MIGRATE_FLAG] then
		return false
	end
	if not isServer or not isServer() then
		return false
	end

	registry._migrating = true
	local changed = false

	-- Auto-suficiente: no se puede llamar a Network.ensureRegistry() aqui
	-- (ella misma llama de vuelta a run(), formaria recursion), asi que la
	-- migracion normaliza estas tablas por su cuenta. Valida tipo, no solo
	-- nil: una partida vieja o guardado corrupto podria traer otra cosa.
	if type(registry.networks) ~= "table" then
		registry.networks = {}
	end
	if type(registry.zones) ~= "table" then
		registry.zones = {}
	end
	if type(registry.nodes) ~= "table" then
		registry.nodes = {}
	end
	if type(registry._legacyNetworkAliases) ~= "table" then
		registry._legacyNetworkAliases = {}
	end

	if not registry.networks[LEGACY_MAIN_ID] and hasZonesFor(registry, LEGACY_MAIN_ID) then
		registry.networks[LEGACY_MAIN_ID] = {
			id = LEGACY_MAIN_ID,
			name = "Almacén global",
			terminals = {},
			containers = {},
			addonInstalls = {},
			createdMs = 0,
		}
		changed = true
	end

	if registry.networks[LEGACY_MAIN_ID] then
		local net = registry.networks[LEGACY_MAIN_ID]
		syncTerminalsFromController(net)

		local newId = GlobalStorageSiK.NetworkId.generate(registry)
		net.id = newId
		net.migratedFrom = LEGACY_MAIN_ID
		if not net.createdMs or net.createdMs == 0 then
			net.createdMs = (getTimestampMs and getTimestampMs()) or 0
		end
		if not net.name or net.name == "" then
			net.name = "Red " .. string.sub(newId, -6)
		end

		registry.networks[newId] = net
		registry.networks[LEGACY_MAIN_ID] = nil
		registry._legacyNetworkAliases[LEGACY_MAIN_ID] = newId
		retargetZones(registry, LEGACY_MAIN_ID, newId)

		if registry.defaultNetworkId == LEGACY_MAIN_ID or not registry.defaultNetworkId then
			registry.defaultNetworkId = newId
		end
		changed = true

		if GlobalStorageSiK.Log and GlobalStorageSiK.Log.info then
			GlobalStorageSiK.Log.info(
				"NetworkMigrate",
				"legacy main migrated",
				string.format("%s → %s", LEGACY_MAIN_ID, newId)
			)
		end
	end

	for nid, net in pairs(registry.networks or {}) do
		net.id = net.id or nid
		syncTerminalsFromController(net)
	end

	registry[MIGRATE_FLAG] = true
	registry._migrating = nil

	if changed and ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	return changed
end

--- Migra a registros multi-terminal con estado (v1070); no colapsa anclas.
---@param registry table
---@return boolean changed
function GlobalStorageSiK.NetworkMigrate.runV1070(registry)
	if not registry or registry[MIGRATE_V1070] then
		return false
	end
	if not isServer or not isServer() then
		return false
	end
	local changed = false
	for nid, net in pairs(registry.networks or {}) do
		net.id = net.id or nid
		if GlobalStorageSiK.TerminalRecord.normalizeAll(net) then
			changed = true
		end
		if net.relocation and net.relocation.lastX and net.relocation.lastY then
			local lx = math.floor(net.relocation.lastX)
			local ly = math.floor(net.relocation.lastY)
			local lz = math.floor(net.relocation.lastZ or 0)
			local entry = GlobalStorageSiK.TerminalRecord.findAt(net, lx, ly, lz)
			if not entry then
				local ghost = GlobalStorageSiK.TerminalRecord.create(lx, ly, lz, net)
				if net.relocation.status == "displaced" then
					GlobalStorageSiK.TerminalRecord.markSuspended(ghost)
				end
				net.terminals = net.terminals or {}
				net.terminals[#net.terminals + 1] = ghost
				changed = true
			elseif net.relocation.status == "displaced"
				and entry.status ~= GlobalStorageSiK.TerminalRecord.STATUS_SUSPENDED then
				GlobalStorageSiK.TerminalRecord.markSuspended(entry)
				changed = true
			end
		end
	end
	registry[MIGRATE_V1070] = true
	if changed and ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	if changed and GlobalStorageSiK.Log and GlobalStorageSiK.Log.info then
		GlobalStorageSiK.Log.info("NetworkMigrate", "v1070 multi-terminal records", "ok")
	end
	return changed
end

--- Migra el Lector (antes GS_FloppyDriveNetwork, tabla propia
--- net.floppyDriveInstalls) al mismo net.addonInstalls[key]["Reader"] que ya
--- usa GS_Addons.install/uninstall para el resto de addons (ver GS_ReaderAddon.lua) -
--- sin esto, un lector ya instalado antes de esta version desaparecia de la
--- UI (y de canInstallModule) al pasar a leer solo la tabla nueva, aunque
--- fisicamente el jugador ya lo hubiera instalado y no lo tuviera en el
--- inventario para "reinstalarlo". Usa isAuthoritative(), no isServer() a
--- pelo (mismo gotcha SP real ya documentado en el resto de este fichero:
--- runV1070 usa isServer() directo y por eso NUNCA migra en SP real - no se
--- toca aqui para no mezclar este arreglo con uno ya existente y separado).
---@param registry table
---@return boolean changed
function GlobalStorageSiK.NetworkMigrate.runV1080(registry)
	if not registry or registry[MIGRATE_V1080] then
		return false
	end
	if not GlobalStorageSiK.isAuthoritative() then
		return false
	end
	local changed = false
	local readerItemType = GlobalStorageSiK.Config and GlobalStorageSiK.Config.ITEM_TERMINAL_READER
	for _, net in pairs(registry.networks or {}) do
		if net.floppyDriveInstalls then
			for key, entry in pairs(net.floppyDriveInstalls) do
				net.addonInstalls = net.addonInstalls or {}
				net.addonInstalls[key] = net.addonInstalls[key] or {}
				if not net.addonInstalls[key]["Reader"] then
					net.addonInstalls[key]["Reader"] = {
						by = entry and entry.by,
						at = entry and entry.at,
						itemType = readerItemType,
					}
					changed = true
				end
			end
		end
	end
	registry[MIGRATE_V1080] = true
	if changed and ModData and ModData.transmit and GlobalStorageSiK.MODDATA_KEY then
		ModData.transmit(GlobalStorageSiK.MODDATA_KEY)
	end
	if changed and GlobalStorageSiK.Log and GlobalStorageSiK.Log.info then
		GlobalStorageSiK.Log.info("NetworkMigrate", "v1080 reader addon migration", "ok")
	end
	return changed
end

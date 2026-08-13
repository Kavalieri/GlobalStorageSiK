--[[
	GlobalStorageSiK - Catálogo de terminales (independiente de chunks)
	Autor: SiK
	Fecha: 2026-06-28
	Descripción: Lista terminales desde ModData sin podar; verificación física en 3 estados.
]]

require "GS_Network"
-- GS_TerminalRegistry NO se requiere aqui a nivel de modulo: tambien requiere
-- GS_TerminalCatalog (dependencia mutua real), formando el mismo require
-- recursivo ya corregido en GS_TerminalAccess. El unico punto de uso
-- (verifyPhysical) ya tiene su propio guard nil-safe si aun no esta cargado.
require "GS_TerminalRecord"

GlobalStorageSiK.TerminalCatalog = GlobalStorageSiK.TerminalCatalog or {}

--- Estado físico en mundo: true=presente, false=ausente confirmado, nil=chunk no cargado.
---@param x number
---@param y number
---@param z number
---@return boolean|nil
function GlobalStorageSiK.TerminalCatalog.verifyPhysical(x, y, z)
	if not GlobalStorageSiK.TerminalRegistry or not GlobalStorageSiK.TerminalRegistry.squareHasTerminal then
		return nil
	end
	return GlobalStorageSiK.TerminalRegistry.squareHasTerminal(x, y, z)
end

--- Filas del catálogo de una red (sin podar entradas por chunk descargado).
---@param network table|nil
---@return table[]
function GlobalStorageSiK.TerminalCatalog.collectEntries(network)
	if not network then
		return {}
	end
	local out = {}
	if network.terminals then
		for i = 1, #network.terminals do
			local t = network.terminals[i]
			if t and t.x and t.y then
				local isController = GlobalStorageSiK.TerminalRecord.isController(network, t)
				local suspended = t.status == GlobalStorageSiK.TerminalRecord.STATUS_SUSPENDED
				out[#out + 1] = {
					x = t.x,
					y = t.y,
					z = t.z or 0,
					terminalId = t.id,
					controller = isController,
					catalogStatus = suspended and "suspended" or "registered",
					suspended = suspended,
					label = t.label,
				}
			end
		end
	end
	return out
end

--- Serializa filas para UI/servidor con present/missing/unknown.
---@param networkId string|nil
---@param network table|nil
---@return table[]
function GlobalStorageSiK.TerminalCatalog.serializeRows(networkId, network)
	if not network and networkId and GlobalStorageSiK.Network then
		local registry = GlobalStorageSiK.Network.getRegistry()
		network = registry and registry.networks and registry.networks[networkId]
	end
	local entries = GlobalStorageSiK.TerminalCatalog.collectEntries(network)
	local rows = {}
	for i = 1, #entries do
		local entry = entries[i]
		local verified = GlobalStorageSiK.TerminalCatalog.verifyPhysical(entry.x, entry.y, entry.z)
		rows[#rows + 1] = {
			x = entry.x,
			y = entry.y,
			z = entry.z or 0,
			controller = entry.controller == true,
			catalogStatus = entry.catalogStatus,
			suspended = entry.suspended == true,
			present = verified == true,
			missing = verified == false,
			unknown = verified == nil,
			label = entry.label,
		}
	end
	return rows
end

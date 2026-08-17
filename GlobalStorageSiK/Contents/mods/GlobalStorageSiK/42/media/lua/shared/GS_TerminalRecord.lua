--[[
	GlobalStorageSiK - Registro normalizado de terminales por red
	Autor: SiK
	Fecha: 2026-06-28
	Descripción: Entradas con id, estado y rol; base del modelo multi-terminal (B→C).
]]

GlobalStorageSiK.TerminalRecord = GlobalStorageSiK.TerminalRecord or {}

GlobalStorageSiK.TerminalRecord.STATUS_ACTIVE = "active"
GlobalStorageSiK.TerminalRecord.STATUS_SUSPENDED = "suspended"

---@param network table|nil
---@return number
local function nextTerminalSeq(network)
	network._nextTerminalSeq = (network._nextTerminalSeq or 0) + 1
	return network._nextTerminalSeq
end

--- Genera id estable dentro de la red.
---@param network table
---@return string
function GlobalStorageSiK.TerminalRecord.generateId(network)
	local seq = nextTerminalSeq(network)
	local nid = network.id or "net"
	return string.format("%s_t%04d", nid, seq)
end

--- Numero de secuencia embebido en un id "net_tNNNN" (para reutilizarlo
--- como nombre por defecto legible, "Terminal N", sin depender de la
--- posicion en el array que puede tener huecos si se borraron terminales).
---@param id string|nil
---@return number|nil
local function seqFromId(id)
	if not id then
		return nil
	end
	local digits = tostring(id):match("_t(%d+)$")
	return digits and tonumber(digits) or nil
end

--- Normaliza entrada legacy {x,y,z} → registro completo.
---@param entry table|nil
---@param network table|nil
---@return table|nil
function GlobalStorageSiK.TerminalRecord.normalize(entry, network)
	if not entry or entry.x == nil or entry.y == nil then
		return nil
	end
	entry.z = entry.z or 0
	if not entry.id or entry.id == "" then
		entry.id = GlobalStorageSiK.TerminalRecord.generateId(network or {})
	end
	if not entry.status or entry.status == "" then
		entry.status = GlobalStorageSiK.TerminalRecord.STATUS_ACTIVE
	end
	-- Guarda para terminales ya instalados antes de que create() empezara a
	-- asignar nombre por defecto: rellena SOLO si sigue en blanco, nunca
	-- pisa un nombre que el jugador ya haya puesto a mano.
	if not entry.label or entry.label == "" then
		local seq = seqFromId(entry.id)
		if seq then
			entry.label = GlobalStorageSiK.I18n.text("IGUI_GS_TerminalDefaultNameFmt", seq)
		end
	end
	entry.x = math.floor(entry.x)
	entry.y = math.floor(entry.y)
	entry.z = math.floor(entry.z)
	return entry
end

--- Normaliza todas las entradas de una red.
---@param network table|nil
---@return boolean changed
function GlobalStorageSiK.TerminalRecord.normalizeAll(network)
	if not network or not network.terminals then
		return false
	end
	local changed = false
	for i = 1, #network.terminals do
		local entry = network.terminals[i]
		-- normalize() muta la MISMA tabla in-place, asi que hay que capturar
		-- el estado ANTES de llamarla - comprobar los campos despues (bug
		-- previo) siempre sale "ya estaba puesto" porque normalize acaba de
		-- ponerlos.
		local hadId = entry.id ~= nil and entry.id ~= ""
		local hadStatus = entry.status ~= nil and entry.status ~= ""
		local hadLabel = entry.label ~= nil and entry.label ~= ""
		local after = GlobalStorageSiK.TerminalRecord.normalize(entry, network)
		if after and (not hadId or not hadStatus or (not hadLabel and after.label)) then
			changed = true
		end
	end
	return changed
end

---@param entry table|nil
---@return boolean
function GlobalStorageSiK.TerminalRecord.isActive(entry)
	return entry ~= nil and entry.status ~= GlobalStorageSiK.TerminalRecord.STATUS_SUSPENDED
end

---@param network table|nil
---@param entry table|nil
---@return boolean
function GlobalStorageSiK.TerminalRecord.isController(network, entry)
	if not network or not entry or not entry.x then
		return false
	end
	local c = network.controller
	if not c or not c.x then
		return false
	end
	return math.floor(c.x) == math.floor(entry.x)
		and math.floor(c.y) == math.floor(entry.y)
		and math.floor(c.z or 0) == math.floor(entry.z or 0)
end

--- Crea entrada nueva activa.
---@param x number
---@param y number
---@param z number
---@param network table
---@return table
function GlobalStorageSiK.TerminalRecord.create(x, y, z, network)
	local entry = {
		x = math.floor(x),
		y = math.floor(y),
		z = math.floor(z or 0),
		status = GlobalStorageSiK.TerminalRecord.STATUS_ACTIVE,
		placedAt = (getTimestampMs and getTimestampMs()) or 0,
	}
	entry.id = GlobalStorageSiK.TerminalRecord.generateId(network)
	-- Nombre por defecto identificable ("Terminal N") en vez de dejarlo en
	-- blanco hasta que el jugador lo renombre a mano - reutiliza el mismo
	-- numero de secuencia que el id para que ambos coincidan. El jugador
	-- puede renombrarlo despues con renameTerminalAt; eso simplemente
	-- sobrescribe entry.label como ya hacia.
	local seq = seqFromId(entry.id)
	if seq then
		entry.label = GlobalStorageSiK.I18n.text("IGUI_GS_TerminalDefaultNameFmt", seq)
	end
	return entry
end

--- Marca entrada como suspendida (terminal en inventario).
---@param entry table|nil
function GlobalStorageSiK.TerminalRecord.markSuspended(entry)
	if not entry then
		return
	end
	entry.status = GlobalStorageSiK.TerminalRecord.STATUS_SUSPENDED
	entry.suspendedAt = (getTimestampMs and getTimestampMs()) or 0
end

--- Reactiva entrada suspendida en mismas coordenadas.
---@param entry table|nil
function GlobalStorageSiK.TerminalRecord.markActive(entry)
	if not entry then
		return
	end
	entry.status = GlobalStorageSiK.TerminalRecord.STATUS_ACTIVE
	entry.suspendedAt = nil
end

--- Busca entrada por coordenadas exactas.
---@param network table|nil
---@param x number
---@param y number
---@param z number
---@return table|nil entry
---@return number|nil index
function GlobalStorageSiK.TerminalRecord.findAt(network, x, y, z)
	if not network or not network.terminals then
		return nil, nil
	end
	local fx, fy, fz = math.floor(x), math.floor(y), math.floor(z or 0)
	for i = 1, #network.terminals do
		local t = network.terminals[i]
		if t and math.floor(t.x) == fx and math.floor(t.y) == fy and math.floor(t.z or 0) == fz then
			return t, i
		end
	end
	return nil, nil
end

--- Cuenta terminales activos.
---@param network table|nil
---@return number
function GlobalStorageSiK.TerminalRecord.countActive(network)
	if not network or not network.terminals then
		return 0
	end
	local n = 0
	for i = 1, #network.terminals do
		if GlobalStorageSiK.TerminalRecord.isActive(network.terminals[i]) then
			n = n + 1
		end
	end
	return n
end

--- Devuelve anclas activas (acceso físico / wireless).
---@param network table|nil
---@return table[]
function GlobalStorageSiK.TerminalRecord.collectActiveAnchors(network)
	local out = {}
	if not network or not network.terminals then
		return out
	end
	for i = 1, #network.terminals do
		local t = network.terminals[i]
		if GlobalStorageSiK.TerminalRecord.isActive(t) then
			out[#out + 1] = {
				x = t.x,
				y = t.y,
				z = t.z or 0,
				terminalId = t.id,
				controller = GlobalStorageSiK.TerminalRecord.isController(network, t),
			}
		end
	end
	return out
end

--- Elige ancla principal para UI (controlador activo o primera activa).
---@param network table|nil
---@return table|nil
function GlobalStorageSiK.TerminalRecord.getPrimaryAnchor(network)
	local anchors = GlobalStorageSiK.TerminalRecord.collectActiveAnchors(network)
	for i = 1, #anchors do
		if anchors[i].controller then
			return anchors[i]
		end
	end
	return anchors[1]
end

--- Última ubicación conocida para recuperación/UI. Prioriza un terminal
--- activo, después el registro explícito de reubicación y por último los
--- terminales suspendidos históricos. No inspecciona el mundo.
---@param network table|nil
---@return table|nil
function GlobalStorageSiK.TerminalRecord.getLastKnownLocation(network)
	if not network then return nil end
	local active = GlobalStorageSiK.TerminalRecord.getPrimaryAnchor(network)
	if active then return { x = active.x, y = active.y, z = active.z or 0 } end
	local reloc = network.relocation
	if reloc and reloc.lastX ~= nil and reloc.lastY ~= nil then
		return { x = reloc.lastX, y = reloc.lastY, z = reloc.lastZ or 0 }
	end
	for i = #(network.terminals or {}), 1, -1 do
		local terminal = network.terminals[i]
		if terminal and terminal.x ~= nil and terminal.y ~= nil then
			return { x = terminal.x, y = terminal.y, z = terminal.z or 0 }
		end
	end
	local controller = network.controller
	if controller and controller.x ~= nil and controller.y ~= nil then
		return { x = controller.x, y = controller.y, z = controller.z or 0 }
	end
	return nil
end

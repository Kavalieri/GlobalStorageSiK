--[[
	GlobalStorageSiK - Resaltado físico de contenedores en el mundo
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Ilumina contenedores desde la pestaña Contenedores (zona o nodo).
]]

require "GS_Network"
require "GS_I18n"
require "GS_WorldHighlight"

GlobalStorageSiK.NodeHighlight = {}

local T = GlobalStorageSiK.I18n.text

---@type table
local state = {
	mode = nil,
	zoneId = nil,
	zoneName = nil,
	nodeId = nil,
	allNodes = nil,
	objects = {},
}

local tickAcc = 0
-- Subido de 45 a 400 (2026-08-14, reporte de jugador: parpadeo residual del
-- borde blanco 1-2 veces/segundo tras el fix de reapplyAfterRefresh): este
-- refresco periodico solo existe como red de seguridad por si el motor
-- "olvida" el resaltado (ej. tras descargar/recargar el chunk) - no hace
-- falta que corra a casi 1Hz para cumplir ese papel, y como reaplica
-- incondicionalmente (no hay API de Lua para consultar "sigue resaltado?"),
-- cada ciclo reinicia la animacion de brillo del motor igual que el bug ya
-- corregido en reapplyAfterRefresh, solo que a ritmo mas lento. Cada ~6-13s
-- (segun fps) sigue siendo de sobra para recuperarse de una perdida real,
-- sin que se note como parpadeo visible.
local REFRESH_TICKS = 400

--- Comprueba si un nodo pertenece a la zona indicada.
---@param node table
---@param zoneId string|nil
---@return boolean
local function nodeMatchesZone(node, zoneId)
	if not node then
		return false
	end
	if zoneId == nil or zoneId == "" then
		return not node.zoneId or node.zoneId == ""
	end
	return node.zoneId == zoneId
end

--- Muestra nota halo al jugador.
---@param text string
---@param r number
---@param g number
---@param b number
local function showHalo(text, r, g, b)
	local player = getPlayer and getPlayer() or nil
	if not player and GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer then
		player = GlobalStorageSiK.NetClient.getPlayer()
	end
	if player and player.setHaloNote and text and text ~= "" then
		player:setHaloNote(text, r or 200, g or 220, b or 160, 480)
	end
end

--- Limpia objetos resaltados sin tocar el estado lógico.
local function clearTrackedObjects()
	if GlobalStorageSiK.WorldHighlight and GlobalStorageSiK.WorldHighlight.clearAll then
		GlobalStorageSiK.WorldHighlight.clearAll()
	end
	state.objects = {}
end

--- Resuelve nodos activos según el estado actual.
---@return table[]
local function resolveActiveNodes()
	if state.mode == "zone" and state.allNodes then
		local list = {}
		for i = 1, #state.allNodes do
			local node = state.allNodes[i]
			if nodeMatchesZone(node, state.zoneId) then
				list[#list + 1] = node
			end
		end
		return list
	end
	if state.mode == "node" and state.allNodes and state.nodeId then
		for i = 1, #state.allNodes do
			local node = state.allNodes[i]
			if node.id == state.nodeId then
				return { node }
			end
		end
	end
	return {}
end

--- Resuelve objetos del mundo para los nodos dados.
---@param nodes table[]
---@return IsoObject[]
local function resolveWorldObjects(nodes)
	local list = {}
	nodes = nodes or {}
	for i = 1, #nodes do
		local node = nodes[i]
		if node and node.offline ~= true then
			local obj = GlobalStorageSiK.Network.findWorldObject(node)
			if obj then
				list[#list + 1] = obj
			end
		end
	end
	return list
end

--- Aplica resaltado a una lista de nodos.
---@param nodes table[]
---@param silent boolean|nil
---@return number found
---@return number total
local function applyToNodes(nodes, silent)
	clearTrackedObjects()
	nodes = nodes or {}
	local found = 0
	for i = 1, #nodes do
		local node = nodes[i]
		if node and node.offline ~= true then
			local obj = GlobalStorageSiK.Network.findWorldObject(node)
			if obj and GlobalStorageSiK.WorldHighlight
				and GlobalStorageSiK.WorldHighlight.highlightObject(obj, 0.35, 0.88, 0.42) then
				state.objects[#state.objects + 1] = obj
				found = found + 1
			end
		end
	end
	if not silent then
		if found == 0 then
			showHalo(T("IGUI_GS_NodeHighlightNone"), 220, 140, 120)
		elseif state.mode == "zone" then
			local zoneLabel = state.zoneName or state.zoneId or "—"
			if found < #nodes then
				showHalo(T("IGUI_GS_NodeHighlightZonePartial", found, #nodes, zoneLabel), 240, 210, 120)
			else
				showHalo(T("IGUI_GS_NodeHighlightZone", found, zoneLabel), 240, 210, 120)
			end
		elseif state.mode == "node" and nodes[1] then
			local name = nodes[1].displayName or nodes[1].name or "?"
			showHalo(T("IGUI_GS_NodeHighlightOne", name), 140, 230, 170)
		end
	end
	return found, #nodes
end

--- Indica si hay un resaltado activo.
---@return boolean
function GlobalStorageSiK.NodeHighlight.isActive()
	return state.mode ~= nil
end

--- Devuelve copia del estado lógico (sin objetos Iso).
---@return table
function GlobalStorageSiK.NodeHighlight.getState()
	return {
		mode = state.mode,
		zoneId = state.zoneId,
		nodeId = state.nodeId,
	}
end

--- Quita todo resaltado del mundo y el estado.
function GlobalStorageSiK.NodeHighlight.clear()
	clearTrackedObjects()
	state.mode = nil
	state.zoneId = nil
	state.zoneName = nil
	state.nodeId = nil
	state.allNodes = nil
end

--- Actualiza lista de nodos tras refresco del terminal.
--- No limpia antes de re-aplicar para evitar parpadeo de 1 frame.
--- IDEMPOTENTE (corregido 2026-08-14, reportado por jugador: parpadeo a alta
--- frecuencia del color de contenedor + caida de FPS solo cerca de zonas con
--- muchos contenedores en red, ej. 7x9 tiles con cajas militares apiladas):
--- el terminal sincroniza su estado varias veces por segundo mientras se
--- interactua (depositos/retiros/busquedas), y refreshFromState llama a esto
--- CADA VEZ - antes se re-aplicaba WorldHighlight.highlightObject (que
--- reinicia la animacion de brillo Y re-registra el objeto en el FBO de
--- resaltado) sobre los MISMOS contenedores ya resaltados en cada refresco,
--- sin comprobar si hacia falta. Eso explicaba las dos cosas a la vez: el
--- reinicio constante de la animacion de brillo = parpadeo visible, y el
--- registro FBO repetido muchas veces por segundo por cada contenedor de la
--- zona = coste real de render que solo se paga estando cerca (mas refrescos,
--- terminal en uso). Ahora solo se resaltan los contenedores NUEVOS respecto
--- al ultimo refresco; los que ya estaban resaltados se dejan tal cual.
---@param nodes table[]|nil
function GlobalStorageSiK.NodeHighlight.reapplyAfterRefresh(nodes)
	if not state.mode then
		return
	end
	if nodes then
		state.allNodes = nodes
	end
	local activeNodes = resolveActiveNodes()
	local previouslyHighlighted = {}
	for i = 1, #state.objects do
		previouslyHighlighted[state.objects[i]] = true
	end
	local newObjects = {}
	for i = 1, #activeNodes do
		local node = activeNodes[i]
		if node and node.offline ~= true then
			local obj = GlobalStorageSiK.Network.findWorldObject(node)
			if obj then
				newObjects[#newObjects + 1] = obj
				if not previouslyHighlighted[obj] and GlobalStorageSiK.WorldHighlight
					and GlobalStorageSiK.WorldHighlight.highlightObject then
					GlobalStorageSiK.WorldHighlight.highlightObject(obj, 0.35, 0.88, 0.42)
				end
			end
		end
	end
	state.objects = newObjects
end

--- Mantiene resaltado si el motor lo pierde.
function GlobalStorageSiK.NodeHighlight.refreshTracked()
	if not state.mode or #state.objects == 0 then
		return
	end
	for i = 1, #state.objects do
		local obj = state.objects[i]
		if obj and obj.isExistInTheWorld and obj:isExistInTheWorld() then
			if GlobalStorageSiK.WorldHighlight and GlobalStorageSiK.WorldHighlight.highlightObject then
				GlobalStorageSiK.WorldHighlight.highlightObject(obj, 0.35, 0.88, 0.42)
			end
		end
	end
end

--- Ilumina todos los contenedores de una zona.
---@param zoneId string|nil
---@param zoneName string|nil
---@param allNodes table[]
function GlobalStorageSiK.NodeHighlight.highlightZone(zoneId, zoneName, allNodes)
	allNodes = allNodes or {}
	state.mode = "zone"
	state.zoneId = zoneId
	state.zoneName = zoneName
	state.nodeId = nil
	state.allNodes = allNodes
	applyToNodes(resolveActiveNodes(), false)
end

--- Ilumina un único contenedor.
---@param node table
---@param allNodes table[]|nil
function GlobalStorageSiK.NodeHighlight.highlightNode(node, allNodes)
	if not node then
		return
	end
	state.mode = "node"
	state.zoneId = nil
	state.zoneName = nil
	state.nodeId = node.id
	state.allNodes = allNodes or state.allNodes or { node }
	applyToNodes({ node }, false)
end

Events.OnTick.Add(function()
	if not GlobalStorageSiK.NodeHighlight.isActive() then
		tickAcc = 0
		return
	end
	tickAcc = tickAcc + 1
	if tickAcc >= REFRESH_TICKS then
		tickAcc = 0
		GlobalStorageSiK.NodeHighlight.refreshTracked()
	end
end)

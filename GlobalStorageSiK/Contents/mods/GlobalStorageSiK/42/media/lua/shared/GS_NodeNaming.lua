--[[
	GlobalStorageSiK - Nombre visible de contenedores en el mundo
	Autor: SiK
	Fecha: 2026-06-23
	Descripción: Aplica displayName del nodo al contenedor físico (menú contextual / inventario).
]]

require "GS_Network"
require "GS_Utils"
require "GS_Debug"

GlobalStorageSiK.NodeNaming = {}

--- Aplica el nombre visible de un nodo a su objeto en el mundo.
---@param node table|nil
---@return boolean applied
function GlobalStorageSiK.NodeNaming.applyToNode(node)
	if not node then
		return false
	end
	local name = node.displayName
	if not name or name == "" then
		return false
	end

	local obj = GlobalStorageSiK.Network.findWorldObject(node)
	if not obj then
		GlobalStorageSiK.Debug.log("NodeNaming", "obj no encontrado", tostring(node.id))
		return false
	end

	local applied = false
	local container = GlobalStorageSiK.Utils.getObjectContainer(obj, node.containerIndex)
	if container and container.setCustomName then
		local ok = pcall(function()
			container:setCustomName(name)
		end)
		if ok then
			applied = true
		end
	end
	if obj.setName then
		local ok = pcall(function()
			obj:setName(name)
		end)
		if ok then
			applied = true
		end
	end

	if obj.getModData then
		local md = obj:getModData()
		if md then
			md.gsDisplayName = name
			if obj.transmitModData then
				obj:transmitModData()
			end
		end
	end

	GlobalStorageSiK.Debug.log("NodeNaming", "apply", string.format(
		"id=%s name=%s applied=%s", tostring(node.id), tostring(name), tostring(applied)
	))
	return applied
end

--- Sincroniza nombres de todos los nodos de una red (servidor / host).
---@param networkId string|nil
function GlobalStorageSiK.NodeNaming.syncNetworkNodes(networkId)
	if not networkId or not GlobalStorageSiK.ZoneRefresh or not GlobalStorageSiK.ZoneRefresh.getActiveNodes then
		return
	end
	local nodes = GlobalStorageSiK.ZoneRefresh.getActiveNodes(networkId)
	for i = 1, #nodes do
		GlobalStorageSiK.NodeNaming.applyToNode(nodes[i])
	end
end

--[[
	GlobalStorageSiK - Puente de contenedores (stub core)
	Autor: SiK
	Fecha: 2025-06-27
	Descripción: Sin addon Craft solo devuelve inventario base; el addon amplía la sesión.
]]

require "GS_Network"
require "GS_AddonRegistry"

GlobalStorageSiK.CraftingBridge = GlobalStorageSiK.CraftingBridge or {}

---@param networkId string|nil
---@return table[]
function GlobalStorageSiK.CraftingBridge.collectNetworkContainers(networkId)
	local rows = GlobalStorageSiK.Network.getLiveContainers(networkId)
	local containers = {}
	for i = 1, #rows do
		if rows[i].container then
			containers[#containers + 1] = rows[i].container
		end
	end
	return containers
end

--- Cuantos contenedores de la red estan REGISTRADOS en total frente a
--- cuantos son ahora mismo "vivos" (getLiveContainers exige un IsoObject
--- cargado en el cliente - ver findWorldObject en GS_Network.lua). En bases
--- muy dispersas, un contenedor lejos del JUGADOR (no del terminal) puede
--- estar registrado en la red pero no resolverse hasta que esa zona cargue -
--- antes esto fallaba en silencio (el contenedor simplemente no aparecia en
--- crafteo/construccion remotos, sin ninguna pista de por que). Solo lectura,
--- no cambia que contenedores se inyectan.
---@param networkId string|nil
---@return number liveCount, number totalCount
function GlobalStorageSiK.CraftingBridge.getContainerAvailability(networkId)
	local liveCount = #GlobalStorageSiK.CraftingBridge.collectNetworkContainers(networkId)
	local registry = GlobalStorageSiK.Network.getRegistry()
	GlobalStorageSiK.Network.ensureRegistry(registry)
	local nid = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	local net = nid and registry.networks[nid]
	local totalCount = (net and net.containers) and #net.containers or liveCount
	return liveCount, totalCount
end

---@param base table
---@param networkId string|nil
---@return table
function GlobalStorageSiK.CraftingBridge.mergeContainerLists(base, networkId)
	local merged = {}
	for i = 1, #(base or {}) do
		merged[#merged + 1] = base[i]
	end
	if not GlobalStorageSiK.AddonRegistry.isModActive("Craft") then
		return merged
	end
	local extras = GlobalStorageSiK.CraftingBridge.collectNetworkContainers(networkId)
	for i = 1, #extras do
		merged[#merged + 1] = extras[i]
	end
	return merged
end

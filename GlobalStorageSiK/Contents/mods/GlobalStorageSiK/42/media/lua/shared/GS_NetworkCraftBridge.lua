--[[
	GlobalStorageSiK - Puente de contenedores para crafteo/construcción con
	inventario de red.
	Autor: SiK
	Fecha: 2026-08-04
	Descripción: Movido desde GSSiK_Addon_Craft_Bridge.lua al Core (ya era
	genérico, sin nada específico de Craft) para que Builder y cualquier
	futuro addon lo reutilicen sin duplicar código. Mismo nombre público
	GlobalStorageSiK.CraftingBridge para no romper nada que ya lo llame.
]]

require "GS_Network"

GlobalStorageSiK.CraftingBridge = GlobalStorageSiK.CraftingBridge or {}

---@param networkId string|nil
---@return table[]
function GlobalStorageSiK.CraftingBridge.collectNetworkContainers(networkId)
	local rows = GlobalStorageSiK.Network.getLiveContainers(networkId)
	local containers = {}
	for i = 1, #rows do
		local row = rows[i]
		if row.container then
			containers[#containers + 1] = row.container
		end
	end
	return containers
end

---@param base table
---@param networkId string|nil
---@return table
function GlobalStorageSiK.CraftingBridge.mergeContainerLists(base, networkId)
	local merged = {}
	for i = 1, #(base or {}) do
		merged[#merged + 1] = base[i]
	end
	local extras = GlobalStorageSiK.CraftingBridge.collectNetworkContainers(networkId)
	for i = 1, #extras do
		merged[#merged + 1] = extras[i]
	end
	return merged
end

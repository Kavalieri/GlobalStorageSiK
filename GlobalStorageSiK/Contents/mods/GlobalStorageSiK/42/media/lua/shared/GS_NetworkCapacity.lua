--[[
	GlobalStorageSiK - Capacidad de peso de la red
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Calcula peso usado y capacidad total de contenedores de la red.
]]

require "GS_Config"
require "GS_Network"
require "GS_Zones"
require "GS_ItemSnapshot"

GlobalStorageSiK.NetworkCapacity = {}

--- Obtiene peso y capacidad de un contenedor vivo.
---@param container ItemContainer
---@return number used
---@return number|nil capacity
local function readContainerWeights(container)
	if not container then
		return 0, nil
	end
	local used = 0
	local capacity = nil
	if container.getWeight then
		local ok, w = pcall(function()
			return container:getWeight()
		end)
		if ok and w then
			used = w
		end
	end
	if used <= 0 and container.getContentsWeight then
		local okAlt, wAlt = pcall(function()
			return container:getContentsWeight()
		end)
		if okAlt and wAlt and wAlt > 0 then
			used = wAlt
		end
	end
	if used <= 0 and container.getItems then
		local okItems, items = pcall(function()
			return container:getItems()
		end)
		if okItems and items and items:size() > 0 then
			used = GlobalStorageSiK.NetworkCapacity.estimateSnapshotWeight(
				GlobalStorageSiK.ItemSnapshot.fromContainer(container)
			)
		end
	end
	if container.getCapacity then
		local okCap, cap = pcall(function()
			return container:getCapacity()
		end)
		if okCap and cap and cap > 0 then
			capacity = cap
		end
	end
	return used, capacity
end

--- Estima el peso de un snapshot por tipo de ítem.
---@param snapshot table<string, table>|nil
---@return number
function GlobalStorageSiK.NetworkCapacity.estimateSnapshotWeight(snapshot)
	if not snapshot then
		return 0
	end
	local total = 0
	for fullType, row in pairs(snapshot) do
		local count = row.count or 1
		local unit = 0.1
		if getScriptManager then
			local ok, w = pcall(function()
				local script = getScriptManager():getItem(fullType)
				if script and script.getActualWeight then
					return script:getActualWeight()
				end
				if script and script.getWeight then
					return script:getWeight()
				end
				return 0.1
			end)
			if ok and w then
				unit = w
			end
		end
		total = total + unit * count
	end
	return total
end

--- Acumula peso/capacidad de un nodo (vivo, offline o sin chunk).
---@param totals table
---@param node table
---@param liveEntry table|nil
local function accumulateNode(totals, node, liveEntry)
	if liveEntry and liveEntry.container then
		local used, capacity = readContainerWeights(liveEntry.container)
		totals.usedWeight = totals.usedWeight + used
		if capacity then
			totals.totalCapacity = totals.totalCapacity + capacity
		else
			totals.partialEstimate = true
		end
		totals.liveNodes = totals.liveNodes + 1
		return
	end

	if node.offline == true then
		totals.offlineNodes = totals.offlineNodes + 1
	else
		totals.unloadedNodes = totals.unloadedNodes + 1
	end

	if node.itemSnapshot then
		totals.usedWeight = totals.usedWeight + GlobalStorageSiK.NetworkCapacity.estimateSnapshotWeight(node.itemSnapshot)
		totals.partialEstimate = true
	else
		totals.partialEstimate = true
	end

	if node.storedCapacity and node.storedCapacity > 0 then
		totals.totalCapacity = totals.totalCapacity + node.storedCapacity
	else
		totals.partialEstimate = true
	end
end

--- Calcula estadísticas de capacidad de una red.
---@param networkId string|nil
---@return table
function GlobalStorageSiK.NetworkCapacity.compute(networkId)
	networkId = networkId or GlobalStorageSiK.Network.getDefaultNetworkId()
	local totals = {
		usedWeight = 0,
		totalCapacity = 0,
		liveNodes = 0,
		offlineNodes = 0,
		unloadedNodes = 0,
		partialEstimate = false,
	}

	local liveById = {}
	local live = GlobalStorageSiK.Network.getLiveContainers(networkId)
	for i = 1, #live do
		local entry = live[i].entry
		if entry and entry.id then
			liveById[entry.id] = live[i]
		end
	end

	local counted = {}
	local registry = GlobalStorageSiK.Zones.getRegistry()

	for _, node in pairs(registry.nodes or {}) do
		if node.enabled ~= false and node.membership ~= "excluded" and node.id then
			local zone = registry.zones and registry.zones[node.zoneId]
			if zone and zone.networkId == networkId and zone.enabled ~= false then
				counted[node.id] = true
				accumulateNode(totals, node, liveById[node.id])
			end
		end
	end

	local netRegistry = GlobalStorageSiK.Network.getRegistry()
	local network = netRegistry.networks and netRegistry.networks[networkId]
	if network and network.containers then
		for i = 1, #network.containers do
			local entry = network.containers[i]
			if entry and entry.id and not counted[entry.id] then
				counted[entry.id] = true
				accumulateNode(totals, entry, liveById[entry.id])
			end
		end
	end

	local percent = 0
	if totals.totalCapacity > 0 then
		percent = math.min(100, math.floor((totals.usedWeight / totals.totalCapacity) * 100 + 0.5))
	end

	local warnPct = GlobalStorageSiK.Config.WEIGHT_WARN_PERCENT or 80
	local critPct = GlobalStorageSiK.Config.WEIGHT_CRITICAL_PERCENT or 95
	local status = "ok"
	if totals.totalCapacity > 0 then
		if totals.usedWeight >= totals.totalCapacity or percent >= 100 then
			status = "full"
		elseif percent >= critPct then
			status = "critical"
		elseif percent >= warnPct then
			status = "warning"
		end
	end

	totals.percent = percent
	totals.status = status
	return totals
end

--- Redondea y serializa para envío al cliente.
---@param stats table|nil
---@return table
function GlobalStorageSiK.NetworkCapacity.serialize(stats)
	stats = stats or {}
	return {
		usedWeight = math.floor((stats.usedWeight or 0) * 10 + 0.5) / 10,
		totalCapacity = math.floor((stats.totalCapacity or 0) * 10 + 0.5) / 10,
		percent = stats.percent or 0,
		status = stats.status or "ok",
		liveNodes = stats.liveNodes or 0,
		offlineNodes = stats.offlineNodes or 0,
		unloadedNodes = stats.unloadedNodes or 0,
		partialEstimate = stats.partialEstimate == true,
	}
end

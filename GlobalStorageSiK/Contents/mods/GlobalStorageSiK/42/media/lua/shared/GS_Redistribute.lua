--[[
	GlobalStorageSiK - Auto-ordenar (antes "Redistribución por categoría")
	Autor: SiK
	Fecha: 2025-06-25
	Descripción: Mueve ítems mal ubicados por categoría, afinidad exacta o
	afinidad taxonómica canónica; fallback controlado a «cualquiera».
]]

require "GS_RoutingProtocol"
require "GS_Network"
require "GS_Router"
require "GS_RoutingPlan"
require "GS_InventorySync"
require "GS_Sandbox"
require "GS_Power"
require "GS_Zones"
require "GS_ZonePriority"
require "GS_I18n"
require "GS_CategoryResolution"
require "GS_OperationPacing"
require "GS_Permissions"

GlobalStorageSiK.Redistribute = {}

-- Presupuesto por paso del job. El límite interno acota MOVIMIENTOS en
-- depósitos normales, pero Auto Sort también debe limitar ítems INSPECCIONADOS:
-- una red ya ordenada podía recorrer miles de ítems contra todos los nodos en
-- un único tick porque moved seguía en cero. Dos movimientos por paso reducen
-- además los pares remove/add que el servidor debe replicar a los clientes.
local function nowMs()
	return getTimestampMs and getTimestampMs() or 0
end

local function timeBudgetExceeded(startedAt, inspected, pacing)
	if inspected <= 0 or startedAt <= 0 then return false end
	local current = nowMs()
	return current > 0 and current - startedAt >= (pacing.cpuBudgetMs or 5)
end

--- Construye tabla zoneId -> zone.priority (1 = zona principal) para la red.
---@param registry table
---@param networkId string
---@return table<string, number>
local function buildZonePriorityLookup(registry, networkId)
	GlobalStorageSiK.ZonePriority.ensurePriorities(registry, networkId)
	local lookup = {}
	for zoneId, zone in pairs(registry.zones or {}) do
		if zone.networkId == networkId then
			lookup[zoneId] = tonumber(zone.priority) or math.huge
		end
	end
	return lookup
end

-- Validate only candidates needed to prove the winner in this slice.
local function validateNode(session, player, live)
    session.nodeValidations = (session.nodeValidations or 0) + 1
    local registry = GlobalStorageSiK.Zones.getRegistry()
    local entry = live.entry and registry.nodes and registry.nodes[live.entry.id]
    local zone = entry and registry.zones and registry.zones[entry.zoneId]
    local allowed = entry and zone and zone.networkId == session.networkId
        and entry.enabled ~= false and entry.membership ~= "excluded" and zone.enabled ~= false
        and GlobalStorageSiK.Permissions.canAccessZone(player, session.networkId, entry.zoneId)
    if allowed then
        local object = GlobalStorageSiK.Network.findWorldObject(entry)
        allowed = object and GlobalStorageSiK.Utils.getObjectContainer(object, entry.containerIndex) == live.container
            and GlobalStorageSiK.Utils.isNetworkStorageContainer(object, entry.containerIndex)
    end
    return allowed == true
end

local function pickRedistributeTarget(item, fromIndex, session, player)
    local from = session.liveNodes[fromIndex]
    local live, index, tier, reason = GlobalStorageSiK.RoutingPlan.pick(session.plan,
        session.liveNodes, item, player, {
            sourceContainer = from.container, excludeSource = session.sourceNodeId ~= nil,
            validate = function(candidate) return validateNode(session, player, candidate) end,
        })
    if live and live.container == from.container then return nil, nil, nil, "origin_optimal" end
    return live, index, tier, reason
end

local function incrementSummaryCount(counts, key)
	if not counts or key == nil then return end
	key = tostring(key)
	counts[key] = (counts[key] or 0) + 1
end

---@param player IsoPlayer
---@param networkId string
---@return table|nil session
---@return table summary
local function beginSession(player, networkId)
	local summary = { moved = 0, failed = 0, skipped = 0, checked = 0, total = 0, reason = nil }
	if not player then summary.reason = "no_player"; return nil, summary end
	if not GlobalStorageSiK.Sandbox.remoteTransferEnabled() then
		summary.reason = "remote_disabled"; return nil, summary
	end
	if not GlobalStorageSiK.Power.networkPowered(networkId) then
		summary.reason = "no_power"; return nil, summary
	end
	local liveNodes = GlobalStorageSiK.Network.getLiveContainers(networkId)
	if #liveNodes == 0 then summary.reason = "no_nodes"; return nil, summary end

	local total = 0
	for i = 1, #liveNodes do
		local container = liveNodes[i].container
		local items = container and container.getItems and container:getItems() or nil
		if items and items.size then total = total + items:size() end
	end
	local registry = GlobalStorageSiK.Zones.getRegistry()
    local priorities = buildZonePriorityLookup(registry, networkId)
    for i = 1, #liveNodes do
        local live = liveNodes[i]
        live.zonePriority = priorities[(live.entry or {}).zoneId] or live.zonePriority
    end
	return {
		networkId = networkId,
		routingRevision = GlobalStorageSiK.RoutingProtocol.revision(networkId),
		liveNodes = liveNodes,
		plan = GlobalStorageSiK.RoutingPlan.new(liveNodes),
		phase = "index",
		nodeIndex = 1,
		itemIndex = 0,
		itemRefsByNode = {},
		indexed = 0,
		processed = 0,
		total = total,
	}, summary
end

-- A job yields between batches. Re-resolve membership, permissions, rules and
-- physical identity before using its captured item references again.
local function revalidateSession(session, player)
	if session.routingRevision ~= GlobalStorageSiK.RoutingProtocol.revision(session.networkId) then
		return "routing_changed"
	end
	if not GlobalStorageSiK.Permissions.canAccess(player, session.networkId) then return "no_permission" end
	if GlobalStorageSiK.Permissions.shouldEnforce()
		and not GlobalStorageSiK.Permissions.isAdminPlayer(player, session.networkId) then return "no_permission" end
    GlobalStorageSiK.RoutingPlan.beginSlice(session.plan)
    if session.sourceNodeId then
        local found = false
        for i = 1, #session.liveNodes do
            local live = session.liveNodes[i]
            if live.entry and live.entry.id == session.sourceNodeId then
                found = validateNode(session, player, live); break
            end
        end
        if not found then return "source_unavailable" end
    end
	return nil
end

local function stepIndex(session, player, startedAt, pacing)
	local inspected = 0
	while session.nodeIndex <= #session.liveNodes
		and inspected < (pacing.indexItemsPerStep or 50)
		and not timeBudgetExceeded(startedAt, inspected, pacing) do
		local nodeIndex = session.nodeIndex
		local live = session.liveNodes[nodeIndex]
		local container = live and live.container
		if session.itemIndex == 0 and not validateNode(session, player, live) then container = nil end
		local items = container and container.getItems and container:getItems() or nil
		local size = items and items.size and items:size() or 0
		if session.itemIndex >= size then
			session.nodeIndex = nodeIndex + 1
			session.itemIndex = 0
		else
			local item = items:get(session.itemIndex)
			session.itemIndex = session.itemIndex + 1
			inspected = inspected + 1
			session.indexed = session.indexed + 1
			if item then
				session.itemRefsByNode[nodeIndex] = session.itemRefsByNode[nodeIndex] or {}
				local refs = session.itemRefsByNode[nodeIndex]
				refs[#refs + 1] = item

			end
		end
	end
	if session.nodeIndex > #session.liveNodes then
		session.phase = "move"
		session.nodeIndex = 1
		session.itemIndex = 1
	end
	return inspected, timeBudgetExceeded(startedAt, inspected, pacing)
end

local function stepMoves(session, player, summary, startedAt, pacing)
	local touched = {}
	local inspected = 0
	local sourceValid = {}
	local maxMoves = pacing.maxMovesPerStep or 2
	while session.nodeIndex <= #session.liveNodes
		and inspected < (pacing.inspectedPerStep or 25)
		and summary.moved < maxMoves
		and not timeBudgetExceeded(startedAt, inspected, pacing) do
		local nodeIndex = session.nodeIndex
		local refs = session.itemRefsByNode[nodeIndex] or {}
		if session.liveNodes[nodeIndex].unavailable or (session.sourceNodeId
			and (not session.liveNodes[nodeIndex].entry
			or session.liveNodes[nodeIndex].entry.id ~= session.sourceNodeId)) then refs = {} end
		if session.itemIndex > #refs then
			session.nodeIndex = nodeIndex + 1
			session.itemIndex = 1
		else
			local item = refs[session.itemIndex]
			session.itemIndex = session.itemIndex + 1
			inspected = inspected + 1
			session.processed = session.processed + 1
			local fromLive = session.liveNodes[nodeIndex]
			local container = fromLive and fromLive.container
			local fullType = item and item.getFullType and item:getFullType() or nil
			if sourceValid[nodeIndex] == nil then sourceValid[nodeIndex] = validateNode(session, player, fromLive) end
            local present = item and container and (item.getContainer and item:getContainer() == container
                or (not item.getContainer and container:contains(item)))
            if present and sourceValid[nodeIndex] then
				local target, targetIndex, targetTier, targetReason = pickRedistributeTarget(item, nodeIndex, session, player)
				if target and target.container and target.container ~= container then
                    local moved = GlobalStorageSiK.InventorySync.moveBetween(container, target.container, item, player)
                    GlobalStorageSiK.RoutingPlan.afterMove(session.plan)
                    sourceValid = {}
                    if moved then
						touched[fromLive.entry.id] = fromLive
						touched[target.entry.id] = target
						summary.moved = summary.moved + 1
						summary.movedByTier = summary.movedByTier or {}
						summary.movedByType = summary.movedByType or {}
						incrementSummaryCount(summary.movedByTier, targetTier or "?")
						incrementSummaryCount(summary.movedByType, fullType or "?")
						if session.onMutation and session.onMutation(fromLive.entry.id, target.entry.id, fullType, targetTier) == false then
							summary.reason = "publication_failed"
							break
						end

					else
						summary.failed = summary.failed + 1
					end
				else
					summary.skipped = summary.skipped + 1
					summary.skipReasons[targetReason or "no_compatible_destination"] = (summary.skipReasons[targetReason or "no_compatible_destination"] or 0) + 1
					if session.sourceNodeId then
						summary.blockedReason = targetReason
						summary.blocked = (summary.blocked or 0) + 1
					end
				end
			else
				-- El mundo puede cambiar mientras el job cede tiempo a otros procesos.
				-- La referencia deja de procesarse y la caché se corrige sin perseguirla.
				summary.skipped = summary.skipped + 1
				local skipReason = sourceValid[nodeIndex] and "reference_absent" or "source_unavailable"
                summary.skipReasons[skipReason] = (summary.skipReasons[skipReason] or 0) + 1
			end
		end
	end
	summary.snapshotsUpdated, summary.touchedNodeIds = true, {}
	for id, live in pairs(touched) do
		summary.touchedNodeIds[#summary.touchedNodeIds + 1] = id
		if session.deferSnapshots then
			summary.snapshotsUpdated = false
		elseif GlobalStorageSiK.Index.syncNodeSnapshot(live.entry, live.container) ~= true then
			summary.snapshotsUpdated = false
			if GlobalStorageSiK.CatalogReconciler then GlobalStorageSiK.CatalogReconciler.markDirty(id, "autosort_capture_failed") end
		end
	end
	return inspected, timeBudgetExceeded(startedAt, inspected, pacing)
end

--- Redistribuye una porción acotada de la red y conserva el cursor/cachés en
--- session. El job servidor debe devolver la misma session en la llamada
--- siguiente; así ninguna llamada vuelve a escanear la red desde el principio.
---@param player IsoPlayer
---@param networkId string|nil
---@param session table|nil
---@return table summary
---@return table|nil session
function GlobalStorageSiK.Redistribute.redistributeNetwork(player, networkId, session, pacing, options)
	local startedAt = nowMs()
	local summary = { moved = 0, failed = 0, skipped = 0, checked = 0, total = 0, reason = nil, skipReasons = {} }
	if session and session.networkId ~= networkId then session = nil end
	if not session then
		local initial
		session, initial = beginSession(player, networkId)
		if not session then return initial, nil end
		session.pacing = pacing or GlobalStorageSiK.OperationPacing.resolve({ operationType = "autosort" })
		session.sourceNodeId = options and options.sourceNodeId or nil
		session.deferSnapshots = options and options.deferSnapshots == true
	end
	session.onMutation = options and options.onMutation
	local effectivePacing = session.pacing
		or pacing or GlobalStorageSiK.OperationPacing.resolve({ operationType = "autosort" })
	session.pacing = effectivePacing
	if options and options.deadline then
		local stepPacing = {}
		for key, value in pairs(effectivePacing) do stepPacing[key] = value end
		stepPacing.cpuBudgetMs = math.max(0, math.min(effectivePacing.cpuBudgetMs or 5, options.deadline - startedAt))
		effectivePacing = stepPacing
	end
	if not GlobalStorageSiK.Sandbox.remoteTransferEnabled() then
		summary.reason = "remote_disabled"; return summary, session
	end
	if not GlobalStorageSiK.Power.networkPowered(networkId) then
		summary.reason = "no_power"; return summary, session
	end
	local invalid = revalidateSession(session, player)
	if invalid then summary.reason = invalid; return summary, session end

	local inspected, budgetExhausted
	if session.phase == "index" then
		inspected, budgetExhausted = stepIndex(session, player, startedAt, effectivePacing)
	else
		inspected, budgetExhausted = stepMoves(session, player, summary, startedAt, effectivePacing)
	end
	summary.activeMs = math.max(0, nowMs() - startedAt)
	summary.inspected = inspected or 0
	summary.budgetExhaustions = budgetExhausted and 1 or 0
	summary.phase = session.phase
	summary.checked = session.phase == "index" and session.indexed or session.processed
	summary.total = session.total
	if not summary.reason and (session.phase == "index" or session.nodeIndex <= #session.liveNodes) then
		summary.reason = "limit"
	end
	return summary, session
end

--- Mensaje legible del resumen de redistribución.
---@param summary table|nil
---@return string
function GlobalStorageSiK.Redistribute.formatSummaryMessage(summary)
	summary = summary or {}
	-- Solo se llama desde codigo servidor (GS_RedistributeJob.lua) para
	-- construir el mensaje de un actionResult - I18n.remote (no .text) para
	-- que cada cliente lo resuelva en su propio idioma, ver GS_I18n.lua.
	local T = GlobalStorageSiK.I18n.remote
	if summary.reason == "remote_disabled" then
		return T("IGUI_GS_RedistributeFailRemoteDisabled")
	end
	if summary.reason == "no_power" then
		return T("IGUI_GS_RedistributeFailNoPower")
	end
	if summary.reason == "no_nodes" then
		return T("IGUI_GS_RedistributeFailNoNodes")
	end
	local moved = summary.moved or 0
	local failed = summary.failed or 0
	if summary.reason == "limit" then
		return T("IGUI_GS_RedistributeSummaryLimit", tostring(moved))
	end
	if moved == 0 and failed == 0 then
		return T("IGUI_GS_RedistributeSummaryNothing")
	end
	return T("IGUI_GS_RedistributeSummary", tostring(moved), tostring(failed))
end

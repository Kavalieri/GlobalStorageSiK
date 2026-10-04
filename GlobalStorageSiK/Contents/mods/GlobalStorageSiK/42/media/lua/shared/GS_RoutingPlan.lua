-- Internal ordered routing plans. No final destination or capacity is cached.
require "GS_Router"
require "GS_CategoryResolution"

GlobalStorageSiK.RoutingPlan = {}
local Plan = GlobalStorageSiK.RoutingPlan
local MAX_PLANS = 256

local function priority(live)
	local entry = live.entry or {}
	return tonumber(live.zonePriority) or tonumber(entry.zonePriority) or 50,
		tonumber(entry.priority) or 50
end

local function instanceRules(live)
	local entry = live.entry or {}
	for _, rules in ipairs({ entry.filters or {}, entry.rules or {}, live.zoneRules or {} }) do
		for i = 1, #rules do
			local condition = rules[i].condition or rules[i]
			if condition.type ~= "category" and condition.type ~= "item" then return true end
		end
	end
	return false
end

function Plan.new(liveNodes)
	local order, dynamic = {}, {}
	local dynamicCount = 0
	for i = 1, #liveNodes do
		order[i] = i
		if instanceRules(liveNodes[i]) then dynamic[i] = true; dynamicCount = dynamicCount + 1 end
	end
	table.sort(order, function(a, b)
		local za, pa = priority(liveNodes[a])
		local zb, pb = priority(liveNodes[b])
		if za ~= zb then return za < zb end
		if pa ~= pb then return pa < pb end
		return tostring((liveNodes[a].entry or {}).id or "") < tostring((liveNodes[b].entry or {}).id or "")
	end)
	local rank = {}
	for k = 1, #order do rank[order[k]] = k end
	return { order = order, rank = rank, dynamic = dynamic, dynamicCount = dynamicCount, plans = {}, count = 0,
		stats = { builds = 0, hits = 0, visits = 0, matches = 0, affinityReads = 0, validations = 0 } }
end

-- Freshness is scoped to one synchronous slice. Never carry physical results
-- across a yield or move callbacks. Static match/order plans can survive both.
function Plan.beginSlice(plan)
	plan.validated, plan.affinity = {}, {}
end

function Plan.afterMove(plan)
	plan.validated, plan.affinity = {}, {}
end

local function candidates(plan, liveNodes, item)
	local fullType = item.getFullType and item:getFullType() or ""
	local resolution = GlobalStorageSiK.CategoryResolution.resolve(fullType, nil, item)
	local stamp = GlobalStorageSiK.Index and GlobalStorageSiK.Index.getClassificationStamp
		and GlobalStorageSiK.Index.getClassificationStamp() or ""
	if plan.stamp ~= stamp then plan.plans, plan.count, plan.stamp = {}, 0, stamp end
	local key = fullType .. "\t" .. tostring(resolution and resolution.routingIdentity)
		.. "\t" .. tostring(resolution and resolution.vanillaKey) .. "\t" .. tostring(resolution and resolution.effective)
	local cacheable = resolution and resolution.nativeStatus ~= "pending"
	local cached = cacheable and plan.plans[key]
	if cached then
		plan.stats.hits = plan.stats.hits + 1
	else
		cached = { {}, {}, {}, {} }
		for k = 1, #plan.order do
			local i = plan.order[k]
			if not plan.dynamic[i] then
				local live = liveNodes[i]
				local tier = GlobalStorageSiK.Router.matchWithZoneGate(live.entry or {}, live.zoneRules, live.zoneEnabled, item)
				plan.stats.matches = plan.stats.matches + 1
				if tier then cached[math.min(4, tier)][#cached[math.min(4, tier)] + 1] = i end
			end
		end
		plan.stats.builds = plan.stats.builds + 1
		if cacheable then
			if plan.count >= MAX_PLANS then plan.plans, plan.count = {}, 0 end
			plan.plans[key], plan.count = cached, plan.count + 1
		end
	end
	if plan.dynamicCount == 0 then return cached end
	local result = { {}, {}, {}, {} }
	for tier = 1, 4 do
		for k = 1, #cached[tier] do result[tier][k] = cached[tier][k] end
	end
	for i in pairs(plan.dynamic) do
		local live = liveNodes[i]
		local tier = GlobalStorageSiK.Router.matchWithZoneGate(live.entry or {}, live.zoneRules, live.zoneEnabled, item)
		plan.stats.matches = plan.stats.matches + 1
		if tier then
			local row = result[math.min(4, tier)]
			local position = #row + 1
			while position > 1 and plan.rank[row[position - 1]] > plan.rank[i] do position = position - 1 end
			table.insert(row, position, i)
		end
	end
	return result
end

local function valid(plan, liveNodes, i, options)
	local cached = plan.validated[i]
	if cached ~= nil then return cached end
	local live = liveNodes[i]
	plan.stats.validations = plan.stats.validations + 1
	local allowed = not live.unavailable and (not options.validate or options.validate(live, i) == true)
	plan.validated[i] = allowed == true
	return allowed
end

-- Query only presence, stop at the first decisive exact match. Equal-size
-- external swaps are seen because the physical list is read afresh each slice.
local function affinity(plan, live, i, item, self)
	local fullType = item.getFullType and item:getFullType() or nil
	local resolved = GlobalStorageSiK.CategoryResolution.resolve(fullType, nil, item)
	local identity = resolved and resolved.routingIdentity
	local key = tostring(i) .. "\t" .. tostring(fullType) .. "\t" .. tostring(identity) .. "\t" .. tostring(self)
	local cached = plan.affinity[key]
	if cached then return cached end
	local taxonomy = false
	local items = live.container and live.container.getItems and live.container:getItems() or nil
	local size = items and items.size and items:size() or 0
	for j = 0, size - 1 do
		local existing = items:get(j)
		plan.stats.affinityReads = plan.stats.affinityReads + 1
		if existing and (not self or existing ~= item) and existing.getFullType then
			local ft = existing:getFullType()
			if fullType and ft == fullType then plan.affinity[key] = 4; return 4 end
			if not taxonomy and identity then
				local other = GlobalStorageSiK.CategoryResolution.resolve(ft, nil, existing)
				taxonomy = other and other.routingIdentity == identity or false
			end
		end
	end
	local tier = taxonomy and 5 or 6
	plan.affinity[key] = tier
	return tier
end

-- Returns live,index,tier,reason; includes the source as a candidate for global
-- AutoSort, with guaranteed self capacity and its own affinity subtracted.
function Plan.pick(plan, liveNodes, item, character, options)
	options = options or {}
	if not plan.validated then Plan.beginSlice(plan) end
	local rows = candidates(plan, liveNodes, item)
	local source = options.sourceContainer
	local compatible = false
	local strict = GlobalStorageSiK.Sandbox.rejectDepositIfNoMatch
		and GlobalStorageSiK.Sandbox.rejectDepositIfNoMatch()
	local function usable(i)
		plan.stats.visits = plan.stats.visits + 1
		local live = liveNodes[i]
		return not (options.excludeSource and live.container == source) and valid(plan, liveNodes, i, options)
	end
	local function space(i)
		return liveNodes[i].container == source or GlobalStorageSiK.Router.containerHasSpace(liveNodes[i].container, item, character)
	end
	for tier = 1, 3 do
		for k = 1, #rows[tier] do
			local i = rows[tier][k]
			if usable(i) then
				compatible = true
				if space(i) then return liveNodes[i], i, tier end
			end
		end
	end
	local unrestricted, cursor = rows[4], 1
	while cursor <= #unrestricted do
		local first = cursor
		local z, p = priority(liveNodes[unrestricted[first]])
		cursor = cursor + 1
		while cursor <= #unrestricted do
			local nz, np = priority(liveNodes[unrestricted[cursor]])
			if nz ~= z or np ~= p then break end
			cursor = cursor + 1
		end
		local best, bestTier
		local priorityOnly = cursor - first == 1 and not strict
		for k = first, cursor - 1 do
			local i = unrestricted[k]
			if usable(i) then
				local live = liveNodes[i]
				-- With no priority tie and unrestricted fallback, content cannot
				-- change the winner. In particular optimal sources cost O(1).
				local tier = priorityOnly and 6
					or affinity(plan, live, i, item, live.container == source)
				if tier < 6 or not strict then
					compatible = true
					if space(i) and (not bestTier or tier < bestTier) then best, bestTier = i, tier end
					if bestTier == 4 then break end
				end
			end
		end
		if best then return liveNodes[best], best, priorityOnly and "priority" or bestTier end
	end
	return nil, nil, nil, compatible and "destination_full" or "no_compatible_destination"
end

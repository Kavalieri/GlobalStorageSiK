-- Internal ordered routing plans. No final destination or capacity is cached.
require "GS_Router"
require "GS_CategoryResolution"
require "GS_RoutingProtocol"

GlobalStorageSiK.RoutingPlan = {}
local Plan = GlobalStorageSiK.RoutingPlan
local MAX_PLANS = 256
local MAX_WITNESS_KEYS = 4096

local function configuration(live)
	local entry = live.entry or {}
	local protocol = GlobalStorageSiK.RoutingProtocol
	if not protocol or not protocol.copy then return nil end
	local _, identity = protocol.copy({ id = entry.id, zoneId = entry.zoneId,
		priority = entry.priority, zonePriority = live.zonePriority,
		entryZonePriority = entry.zonePriority, enabled = entry.enabled,
		membership = entry.membership, rules = entry.rules, filters = entry.filters,
		categories = entry.categories, zoneRules = live.zoneRules, zoneEnabled = live.zoneEnabled })
	return identity
end

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
	local order, dynamic, configurations, containers = {}, {}, {}, {}
	local dynamicCount = 0
	for i = 1, #liveNodes do
		order[i] = i
		configurations[i], containers[i] = configuration(liveNodes[i]), liveNodes[i].container
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
		configurations = configurations, containers = containers, witnesses = {}, witnessCount = 0,
		stats = { builds = 0, hits = 0, visits = 0, matches = 0, affinityReads = 0, validations = 0,
			witnessHits = 0, witnessMisses = 0, witnessSeeds = 0, witnessResets = 0,
			capacityPrunes = 0, listRebuilds = 0, listHits = 0 } }
end

-- Re-resolved candidates can reuse static work only with the same complete
-- configuration and physical identities. Contents are deliberately not compared.
function Plan.rebind(plan, liveNodes)
	local same = plan and #plan.order == #liveNodes
	for i = 1, #liveNodes do
		if not same then break end
		local signature = configuration(liveNodes[i])
		same = signature ~= nil and signature == plan.configurations[i]
			and liveNodes[i].container == plan.containers[i]
	end
	if same then plan.stats.listHits = plan.stats.listHits + 1; return plan end
	local fresh = Plan.new(liveNodes)
	if plan then fresh.stats = plan.stats end
	fresh.stats.listRebuilds = fresh.stats.listRebuilds + 1
	return fresh
end

-- At most two physical witnesses per node/type and a fixed total key bound.
-- A witness is a hint until membership and fullType are verified at each use.
function Plan.remember(plan, i, item)
	local fullType = item and item.getFullType and item:getFullType()
	if not fullType then return end
	local byType = plan.witnesses[i]
	local refs = byType and byType[fullType]
	if not refs then
		if plan.witnessCount >= MAX_WITNESS_KEYS then
			plan.witnesses, plan.witnessCount = {}, 0
			plan.stats.witnessResets = plan.stats.witnessResets + 1
			byType = nil
		end
		byType = byType or {}; plan.witnesses[i] = byType
		refs = {}; byType[fullType] = refs
		plan.witnessCount = plan.witnessCount + 1
	end
	for k = 1, #refs do if refs[k] == item then return end end
	if #refs < 2 then refs[#refs + 1] = item; plan.stats.witnessSeeds = plan.stats.witnessSeeds + 1 end
end

-- Freshness is scoped to one synchronous slice. Never carry physical results
-- across a yield or move callbacks. Static match/order plans can survive both.
function Plan.beginSlice(plan)
	plan.validated, plan.affinity = {}, {}
	plan.queryItem, plan.queryResolution = nil, nil
end

function Plan.afterMove(plan)
	plan.validated, plan.affinity = {}, {}
end

local function candidates(plan, liveNodes, item)
	local fullType = item.getFullType and item:getFullType() or ""
	local resolution = GlobalStorageSiK.CategoryResolution.resolve(fullType, nil, item)
	plan.queryItem, plan.queryResolution = item, resolution
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
	local refs = plan.witnesses[i] and plan.witnesses[i][fullType]
	if refs and live.container and live.container.contains then
		local kept, exact = {}, false
		for k = 1, #refs do
			local witness = refs[k]
			if witness.getFullType and witness:getFullType() == fullType and live.container:contains(witness) then
				kept[#kept + 1] = witness
				if not self or witness ~= item then exact = true end
			else plan.stats.witnessMisses = plan.stats.witnessMisses + 1 end
		end
		plan.witnesses[i][fullType] = kept
		if exact then plan.stats.witnessHits = plan.stats.witnessHits + 1; return 4 end
	end
	local resolved = plan.queryItem == item and plan.queryResolution
		or GlobalStorageSiK.CategoryResolution.resolve(fullType, nil, item)
	plan.queryItem, plan.queryResolution = item, resolved
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
			if fullType and ft == fullType then
				Plan.remember(plan, i, existing)
				plan.affinity[key] = 4; return 4
			end
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
	local compatible, fullUnrestricted = false, {}
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
				if not space(i) then
					plan.stats.capacityPrunes = plan.stats.capacityPrunes + 1
					if strict then fullUnrestricted[#fullUnrestricted + 1] = i else compatible = true end
				else
				local tier = priorityOnly and 6 or affinity(plan, live, i, item, live.container == source)
				if tier < 6 or not strict then
					compatible = true
					if not bestTier or tier < bestTier then best, bestTier = i, tier end
					if bestTier == 4 then break end
				end
				end
			end
		end
		if best then return liveNodes[best], best, priorityOnly and "priority" or bestTier end
	end
	-- Full candidates do not participate in choosing a destination. Only resolve
	-- their affinity when needed to distinguish strict no-match from capacity.
	if strict and not compatible then
		for k = 1, #fullUnrestricted do
			local i = fullUnrestricted[k]
			if affinity(plan, liveNodes[i], i, item, liveNodes[i].container == source) < 6 then
				compatible = true; break
			end
		end
	end
	return nil, nil, nil, compatible and "destination_full" or "no_compatible_destination"
end

-- Preserve disabled-routing order: exact affinity, taxonomy, then generic,
-- each in caller order. Strict mode never admits the generic tier.
function Plan.pickLegacy(plan, liveNodes, item, character, options)
	options = options or {}
	if not plan.validated then Plan.beginSlice(plan) end
	local best, bestTier, compatible, full = nil, nil, false, {}
	for i = 1, #liveNodes do
		local live, entry = liveNodes[i], liveNodes[i].entry or {}
		local unrestricted = live.zoneEnabled ~= false and #(entry.rules or {}) == 0
			and #(entry.categories or {}) == 0 and #(live.zoneRules or {}) == 0
		if unrestricted and valid(plan, liveNodes, i, options) then
			plan.stats.visits = plan.stats.visits + 1
			if GlobalStorageSiK.Router.containerHasSpace(live.container, item, character) then
				local tier = affinity(plan, live, i, item, false)
				local strict = GlobalStorageSiK.Sandbox.rejectDepositIfNoMatch()
				if tier < 6 or not strict then
					compatible = true
					if not bestTier or tier < bestTier then best, bestTier = i, tier end
					if tier == 4 then break end
				end
			else full[#full + 1] = i; plan.stats.capacityPrunes = plan.stats.capacityPrunes + 1 end
		end
	end
	if best then return liveNodes[best], best, bestTier end
	if GlobalStorageSiK.Sandbox.rejectDepositIfNoMatch() then
		for k = 1, #full do
			local i = full[k]
			if affinity(plan, liveNodes[i], i, item, false) < 6 then compatible = true; break end
		end
	else compatible = #full > 0 end
	return nil, nil, nil, compatible and "destination_full" or "no_compatible_destination"
end

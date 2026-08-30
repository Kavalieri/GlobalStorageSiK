-- Deterministic author matrix for deposit and Auto Sort destination routing.
-- Pure Lua 5.1: real Router/Redistribute orchestration with small PZ leaf mocks.

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"

for _, moduleName in ipairs({
	"GS_Sandbox", "GS_NativeProduct", "GS_RuleCoverage", "GS_CategoryResolution",
	"GS_RuleSanitizer", "GS_Log", "GS_NodeFilters", "GS_InventorySync",
	"GS_Network", "GS_Router", "GS_Power", "GS_Zones", "GS_ZonePriority", "GS_I18n",
	"GS_OperationPacing",
}) do
	package.loaded[moduleName] = true
end

local strictNoMatch = false
local activeLiveNodes = {}
local activeRegistry = { networks = {}, zones = {}, nodes = {} }

local routeByType = {
	["Base.Apple"] = "native:food/perishable/fruit",
	["Base.Pear"] = "native:food/perishable/fruit",
	["Base.Hammer"] = "native:materials/tools/hammer",
	["Base.Nails"] = "native:materials/components/fasteners",
}

local function decodePath(value)
	if type(value) ~= "string" or value:sub(1, 7) ~= "native:" then return nil end
	local parts = {}
	for part in value:sub(8):gmatch("[^/]+") do parts[#parts + 1] = part end
	if #parts < 1 or #parts > 3 then return nil end
	return { l1 = parts[1], l2 = parts[2], l3 = parts[3] }
end

local function pathMatches(rule, encoded)
	local actual = decodePath(encoded)
	if not actual then return false end
	return (not rule.l1 or rule.l1 == actual.l1)
		and (not rule.l2 or rule.l2 == actual.l2)
		and (not rule.l3 or rule.l3 == actual.l3)
end

local function item(fullType, identity)
	return {
		_contractIdentity = identity or fullType,
		getFullType = function() return fullType end,
		getDisplayName = function() return fullType end,
	}
end

local function removeIdentity(values, expected)
	for i = 1, #values do
		if values[i] == expected then
			table.remove(values, i)
			return true
		end
	end
	return false
end

local function container(name, values, capacity)
	values = values or {}
	local value = { name = name, items = values, capacity = capacity == nil and 100 or capacity }
	function value:getItems()
		local owner = self
		return {
			size = function() return #owner.items end,
			get = function(_, index) return owner.items[index + 1] end,
		}
	end
	function value:contains(candidate)
		for i = 1, #self.items do if self.items[i] == candidate then return true end end
		return false
	end
	return value
end

GlobalStorageSiK = {
	Sandbox = {
		autoSortEnabled = function() return true end,
		rejectDepositIfNoMatch = function() return strictNoMatch end,
		debugMode = function() return false end,
		debugDetailEnabled = function() return false end,
		remoteTransferEnabled = function() return true end,
		getMaxItemsPerBulkTick = function() return 25 end,
	},
	NativeProduct = {
		decodePath = decodePath,
		pathMatches = pathMatches,
	},
	CategoryResolution = {
		legacyAliasNativePath = function(value) return value end,
		classifyStoredRule = function() return "ACTIVE" end,
		resolve = function(fullType)
			local nativePath = routeByType[fullType] or "native:misc/other/unknown"
			return {
				effective = "native", nativePath = nativePath,
				routingIdentity = nativePath,
				vanillaKey = nativePath:find("native:food/", 1, true) and "Food" or "Misc",
				nativeStatus = "classified",
			}
		end,
	},
	RuleSanitizer = { isJunkCategoryCondition = function() return false end },
	NodeFilters = {
		matchesOne = function(condition, candidate)
			if not condition or not candidate then return false end
			if condition.type == "item" then return condition.value == candidate:getFullType() end
			if condition.type == "name" then return condition.value == candidate:getDisplayName() end
			return false
		end,
		matchesAny = function(filters, candidate)
			for i = 1, #(filters or {}) do
				if GlobalStorageSiK.NodeFilters.matchesOne(filters[i], candidate) then return true end
			end
			return false
		end,
	},
	InventorySync = {
		containerHasRoom = function(target)
			return target and #target.items < target.capacity or false
		end,
		moveBetween = function(source, destination, moving)
			if not source or not destination or not removeIdentity(source.items, moving) then return false end
			destination.items[#destination.items + 1] = moving
			return true
		end,
	},
	Log = { debug = function() end, detail = function() end },
	Power = { networkPowered = function() return true end },
	Network = { getLiveContainers = function() return activeLiveNodes end },
	Zones = { getRegistry = function() return activeRegistry end },
	ZonePriority = { ensurePriorities = function() end },
	I18n = { remote = function(key) return key end },
	OperationPacing = { resolve = function()
		return { batchUnits = 10, batchDelayMs = 400, maxMovesPerStep = 2,
			moveDelayMs = 1000, inspectedPerStep = 25, indexItemsPerStep = 50,
			cpuBudgetMs = 5 }
	end },
}

dofile(shared .. "GS_Router.lua")
package.loaded["GS_Router"] = true
dofile(shared .. "GS_Redistribute.lua")

local function categoryRule(op, nativePath)
	return { op = op, condition = { type = "category", nativePath = nativePath } }
end

local function itemRule(op, fullType)
	return { op = op, condition = { type = "item", value = fullType } }
end

local function createLive(spec)
	local contents = {}
	for i = 1, #(spec.contents or {}) do
		contents[#contents + 1] = item(spec.contents[i], spec.id .. ":existing:" .. tostring(i))
	end
	local live = {
		entry = {
			id = spec.id, zoneId = "zone_" .. spec.id,
			priority = spec.priority, rules = spec.rules,
		},
		container = container(spec.id, contents, spec.capacity),
		zoneRules = spec.zoneRules,
		zoneEnabled = spec.zoneEnabled,
		zonePriority = spec.zonePriority,
	}
	return live
end

local function makeCandidates(specs)
	local liveNodes = {}
	for i = 1, #specs do liveNodes[#liveNodes + 1] = createLive(specs[i]) end
	return liveNodes
end

local function idOf(live)
	return live and live.entry and live.entry.id or nil
end

local function depositDestination(case)
	strictNoMatch = case.strict == true
	local probe = item(case.fullType or "Base.Apple", case.name .. ":deposit")
	local liveNodes = makeCandidates(case.nodes)
	local target, reason = GlobalStorageSiK.Router.pickDepositTarget(probe, liveNodes, {}, {
		affinityIndex = GlobalStorageSiK.Router.buildAffinityIndex(liveNodes),
	})
	return idOf(target), reason
end

local function autoSortDestination(case)
	strictNoMatch = case.strict == true
	local probe = item(case.fullType or "Base.Apple", case.name .. ":autosort")
	local source = {
		entry = { id = "source", zoneId = "zone_source", priority = 50 },
		container = container("source", { probe }, 100),
		zoneEnabled = false,
		zonePriority = 50,
	}
	activeLiveNodes = { source }
	local candidates = makeCandidates(case.nodes)
	for i = 1, #candidates do activeLiveNodes[#activeLiveNodes + 1] = candidates[i] end
	activeRegistry = { networks = { net = { id = "net" } }, zones = {}, nodes = {} }
	activeRegistry.zones.zone_source = { id = "zone_source", networkId = "net", priority = 50 }
	for i = 1, #candidates do
		local live = candidates[i]
		activeRegistry.zones[live.entry.zoneId] = {
			id = live.entry.zoneId, networkId = "net", priority = live.zonePriority or 50,
		}
	end

	local session = nil
	local completed = false
	for _ = 1, 20 do
		local summary
		summary, session = GlobalStorageSiK.Redistribute.redistributeNetwork({}, "net", session)
		if summary.reason ~= "limit" then completed = true; break end
	end
	assert(completed, case.name .. ": Auto Sort did not finish within deterministic budget")
	for i = 2, #activeLiveNodes do
		if activeLiveNodes[i].container:contains(probe) then return idOf(activeLiveNodes[i]) end
	end
	assert(source.container:contains(probe), case.name .. ": Auto Sort lost the probe item")
	return nil
end

local cases = {
	{
		name = "OR accepts one matching branch", expected = "rule_or",
		nodes = {
			{ id = "rule_or", priority = 90, rules = {
				categoryRule("OR", "native:materials/tools/hammer"),
				categoryRule("OR", "native:food/perishable/fruit"),
			} },
			{ id = "global", priority = 1 },
		},
	},
	{
		name = "AND requires every condition", expected = "and_ok",
		nodes = {
			{ id = "and_failed", priority = 1, rules = {
				categoryRule("AND", "native:food/perishable/fruit"), itemRule("AND", "Base.Hammer"),
			} },
			{ id = "and_ok", priority = 90, rules = {
				categoryRule("AND", "native:food/perishable/fruit"), itemRule("AND", "Base.Apple"),
			} },
			{ id = "global", priority = 1 },
		},
	},
	{
		name = "NOT excludes an otherwise matching node", expected = "other_rule",
		nodes = {
			{ id = "excluded", priority = 1, rules = {
				categoryRule("OR", "native:food/perishable/fruit"), itemRule("NOT", "Base.Apple"),
			} },
			{ id = "other_rule", priority = 90, rules = {
				categoryRule("OR", "native:food"),
			} },
		},
	},
	{
		name = "direct exact-item rule beats broader category", expected = "exact",
		nodes = {
			{ id = "broad", priority = 1, rules = { categoryRule("OR", "native:food") } },
			{ id = "exact", priority = 100, rules = { itemRule("OR", "Base.Apple") } },
		},
	},
	{
		name = "lower container priority wins inside one tier", expected = "priority_5",
		nodes = {
			{ id = "priority_20", priority = 20, rules = { categoryRule("OR", "native:food/perishable/fruit") } },
			{ id = "priority_5", priority = 5, rules = { categoryRule("OR", "native:food/perishable/fruit") } },
		},
	},
	{
		name = "lower zone priority precedes container priority", expected = "zone_5",
		nodes = {
			{ id = "zone_10", zonePriority = 10, priority = 1, rules = { itemRule("OR", "Base.Apple") } },
			{ id = "zone_5", zonePriority = 5, priority = 100, rules = { itemRule("OR", "Base.Apple") } },
		},
	},
	{
		name = "stable id breaks a complete tie", expected = "a_node",
		nodes = {
			{ id = "b_node", priority = 50, rules = { itemRule("OR", "Base.Apple") } },
			{ id = "a_node", priority = 50, rules = { itemRule("OR", "Base.Apple") } },
		},
	},
	{
		name = "exact-item affinity beats category and empty", expected = "z_exact",
		nodes = {
			{ id = "a_empty", priority = 50 },
			{ id = "b_similar", priority = 50, contents = { "Base.Pear" } },
			{ id = "z_exact", priority = 50, contents = { "Base.Apple" } },
		},
	},
	{
		name = "taxonomy affinity beats empty", expected = "z_similar",
		nodes = {
			{ id = "a_empty", priority = 50 },
			{ id = "z_similar", priority = 50, contents = { "Base.Pear" } },
		},
	},
	{
		name = "unrelated contents grant no affinity", expected = "a_empty",
		nodes = {
			{ id = "b_unrelated", priority = 50, contents = { "Base.Hammer" } },
			{ id = "a_empty", priority = 50 },
		},
	},
	{
		name = "unrestricted priority overrides affinity", expected = "a_empty_high_priority",
		nodes = {
			{ id = "z_exact_low_priority", priority = 50, contents = { "Base.Apple" } },
			{ id = "a_empty_high_priority", priority = 1 },
		},
	},
	{
		name = "configured rule overrides higher-priority affinity", expected = "z_rule",
		nodes = {
			{ id = "a_exact_affinity", priority = 1, contents = { "Base.Apple" } },
			{ id = "z_rule", priority = 100, rules = { categoryRule("OR", "native:food") } },
		},
	},
	{
		name = "full specific target falls through to broader rule", expected = "broad",
		nodes = {
			{ id = "full_exact", capacity = 0, rules = { itemRule("OR", "Base.Apple") } },
			{ id = "broad", rules = { categoryRule("OR", "native:food") } },
		},
	},
	{
		name = "single empty global container is operational", expected = "empty",
		nodes = { { id = "empty" } },
	},
	{
		name = "zone NOT gate excludes node", expected = "allowed",
		nodes = {
			{ id = "zone_blocked", priority = 1, zoneRules = { itemRule("NOT", "Base.Apple") } },
			{ id = "allowed", priority = 50 },
		},
	},
	{
		name = "no valid destination", expected = nil, expectedReason = "no_match", strict = true,
		nodes = {
			{ id = "not_rule", rules = { itemRule("NOT", "Base.Apple") } },
			{ id = "wrong_rule", rules = { itemRule("OR", "Base.Hammer") } },
		},
	},
}

for i = 1, #cases do
	local case = cases[i]
	local depositId, reason = depositDestination(case)
	assert(depositId == case.expected,
		case.name .. ": deposit expected=" .. tostring(case.expected) .. " actual=" .. tostring(depositId))
	if case.expectedReason then
		assert(reason == case.expectedReason,
			case.name .. ": deposit reason expected=" .. case.expectedReason .. " actual=" .. tostring(reason))
	end
	local autoSortId = autoSortDestination(case)
	assert(autoSortId == case.expected,
		case.name .. ": Auto Sort expected=" .. tostring(case.expected) .. " actual=" .. tostring(autoSortId))
end

local function read(path)
	local handle = assert(io.open(path, "rb"), "cannot read routing caller: " .. path)
	local text = handle:read("*a")
	handle:close()
	return text
end
local transferSource = read(shared .. "GS_Transfer.lua")
assert(transferSource:find("GlobalStorageSiK.Router.pickDepositTarget(item, live, character", 1, true),
	"deposit caller bypasses the shared Router destination selector")
local redistributeSource = read(shared .. "GS_Redistribute.lua")
assert(redistributeSource:find("GlobalStorageSiK.Router.matchWithZoneGate", 1, true)
	and redistributeSource:find("GlobalStorageSiK.Router.unrestrictedAffinityTier", 1, true),
	"Auto Sort bypasses shared rule/affinity contracts")

print("routing_destination_matrix_regression: OK cases=" .. tostring(#cases))

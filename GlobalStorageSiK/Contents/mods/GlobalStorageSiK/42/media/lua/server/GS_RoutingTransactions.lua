require "GS_RoutingProtocol"
require "GS_RuleIdentity"
GlobalStorageSiK.RoutingTransactions = {}
local Transactions = GlobalStorageSiK.RoutingTransactions
local Protocol = GlobalStorageSiK.RoutingProtocol
local sessions, serial = {}, 0
local MAX_RESULTS = 64
local MAX_PLAYERS = 128
local MAX_SESSION_BYTES = 65536
local context

local function validInteger(value, maximum)
	return type(value) == "number" and value == value and value >= 1
		and value <= maximum and value == math.floor(value)
end

local function sessionFor(player)
	if sessions[player] then return sessions[player] end
	local live, count, retired = { [player] = true }, 0, {}
	if context and context.visitPlayers then context.visitPlayers(function(p) live[p] = true end) end
	for p in pairs(sessions) do
		if not live[p] then retired[#retired + 1] = p else count = count + 1 end
	end
	for i = 1, #retired do sessions[retired[i]] = nil end
	if count >= MAX_PLAYERS then return nil end
	serial = serial + 1
	local state = { epoch = tostring(getTimestampMs and getTimestampMs() or 0) .. ":" .. serial,
		high = 0, results = {}, order = {}, bytes = 0 }
	sessions[player] = state
	return state
end

function Transactions.configure(value) context = value end
function Transactions.epoch(player)
	local state = sessionFor(player)
	return state and state.epoch
end

local function reply(player, args, networkId, ok, reason, revision)
	local result = { routingResult = true,
		requestId = type(args.requestId) == "string" and args.requestId:sub(1, 128) or nil,
		configEpoch = type(args.configEpoch) == "string" and args.configEpoch:sub(1, 96) or nil,
		requestSeq = validInteger(args.requestSeq, 2147483647) and args.requestSeq or nil,
		networkId = networkId, ok = ok, reason = reason, routingRevision = revision,
		message = GlobalStorageSiK.I18n.remote(ok and "IGUI_GS_RoutingSaved" or "IGUI_GS_RoutingRejected", reason or "") }
	context.send(player, "actionResult", result)
	return result
end

local function remember(state, sequence, signature, result)
	local _, resultSignature = Protocol.copy(result)
	local bytes = #signature + #(resultSignature or "") + 1024
	state.results[sequence] = { signature = signature, result = result, bytes = bytes }
	state.order[#state.order + 1] = sequence
	state.bytes = state.bytes + bytes
	while #state.order > MAX_RESULTS or state.bytes > MAX_SESSION_BYTES do
		local oldest = table.remove(state.order, 1)
		state.bytes = state.bytes - state.results[oldest].bytes
		state.results[oldest] = nil
	end
end

local function prepareRules(registry, kind, target, args)
	local actions = (args.rules ~= nil and 1 or 0) + (args.addRule ~= nil and 1 or 0)
		+ (args.removeRuleIndex ~= nil and 1 or 0)
	if actions == 0 then return target.rules, nil, false end
	if actions ~= 1 then return nil, "conflicting_rule_actions" end
	if args.rules ~= nil then
		local rules = context.sanitizeRules(args.rules)
		if not rules then return nil, "invalid_rules" end
		return rules, nil, true
	end
	local rules = Protocol.copy(target.rules or {})
	if not rules then return nil, "invalid_stored_rules" end
	if args.addRule ~= nil then
		if #rules >= 20 then return nil, "rule_limit" end
		local rule = context.sanitizeRule(args.addRule)
		if not rule then return nil, "invalid_rule" end
		if not context.prepareCoverage(registry, kind, target, rule) then return nil, "coverage_unavailable" end
		rules[#rules + 1] = rule
	else
		if not GlobalStorageSiK.RuleIdentity.matches(rules, args.removeRuleIndex, args.expectedRule) then
			return nil, "rule_changed"
		end
		table.remove(rules, args.removeRuleIndex)
	end
	return rules, nil, true
end

local function prepareNode(registry, target, args)
	local patch = {}
	local rules, reason, changed = prepareRules(registry, "node", target, args)
	if reason then return nil, reason end
	if changed then patch.rules = rules end
	if args.membership ~= nil then
		if args.membership ~= "active" and args.membership ~= "excluded" then return nil, "invalid_membership" end
		patch.membership, patch.enabled = args.membership, args.membership == "active"
	end
	if args.enabled ~= nil then
		if type(args.enabled) ~= "boolean" then return nil, "invalid_enabled" end
		if patch.enabled ~= nil and patch.enabled ~= args.enabled then return nil, "conflicting_membership" end
		patch.enabled = args.enabled
	end
	for _, key in ipairs({ "displayName", "notes" }) do
		if args[key] ~= nil then
			if type(args[key]) ~= "string" or #args[key] > 120 then return nil, "invalid_" .. key end
			patch[key] = args[key]:match("^%s*(.-)%s*$")
		end
	end
	if args.priority ~= nil then
		if not validInteger(args.priority, 100) then return nil, "invalid_priority" end
		patch.priority = args.priority
	end
	local categoryModes = (args.category ~= nil and 1 or 0) + (args.categories ~= nil and 1 or 0)
		+ (args.categoriesText ~= nil and 1 or 0)
	if categoryModes > 1 then return nil, "conflicting_categories" end
	if categoryModes == 1 then
		local categories = args.categories
		if args.category ~= nil then
			if type(args.category) ~= "string" then return nil, "invalid_categories" end
			categories = args.category ~= "" and args.category ~= "*" and { args.category } or {}
		elseif args.categoriesText ~= nil then
			if type(args.categoriesText) ~= "string" then return nil, "invalid_categories" end
			categories = {}
			for part in args.categoriesText:gmatch("[^,]+") do categories[#categories + 1] = part:match("^%s*(.-)%s*$") end
		end
		if type(categories) ~= "table" or #categories > 20 then return nil, "invalid_categories" end
		patch.categories = context.sanitizeCategories(categories)
		if #patch.categories ~= #categories then return nil, "invalid_categories" end
	end
	local filterModes = (args.filters ~= nil and 1 or 0) + (args.addFilter ~= nil and 1 or 0)
		+ (args.removeFilterIndex ~= nil and 1 or 0)
	if filterModes > 1 then return nil, "conflicting_filters" end
	if filterModes == 1 then
		local source = args.filters or target.filters or {}
		if type(source) ~= "table" or #source > 20 then return nil, "invalid_filters" end
		patch.filters = {}
		for i = 1, #source do
			local clean = context.sanitizeFilter(source[i])
			if not clean then return nil, "invalid_filter" end
			patch.filters[i] = clean
		end
		if args.addFilter ~= nil then
			local clean = context.sanitizeFilter(args.addFilter)
			if not clean or #patch.filters >= 20 then return nil, "invalid_filter" end
			patch.filters[#patch.filters + 1] = clean
		elseif args.removeFilterIndex ~= nil then
			if not validInteger(args.removeFilterIndex, #patch.filters) then return nil, "invalid_filter_index" end
			table.remove(patch.filters, args.removeFilterIndex)
		end
	end
	for _ in pairs(patch) do return { { target = target, patch = patch } } end
	return nil, "empty_intent"
end

local function prepare(registry, networkId, command, args)
	local node = command == "updateNode" and registry.nodes and registry.nodes[args.nodeId]
	local zone = registry.zones and registry.zones[node and node.zoneId or args.zoneId]
	if not zone or zone.networkId ~= networkId or (command == "updateNode" and not node) then
		return nil, "target_not_in_network"
	end
	if node then return prepareNode(registry, node, args) end
	if command == "renameZone" or command == "updateZoneConfig" then
		local patch = {}
		if args.name ~= nil then
			if type(args.name) ~= "string" or #args.name > 120 or args.name:match("^%s*$") then return nil, "invalid_name" end
			patch.name = args.name
		end
		if args.priority ~= nil then
			if not validInteger(args.priority, 100) then return nil, "invalid_priority" end
			patch.priority = args.priority
		end
		if not patch.name and not patch.priority then return nil, "empty_intent" end
		return { { target = zone, patch = patch } }
	end
	if command == "updateZoneRules" then
		local rules, reason, changed = prepareRules(registry, "zone", zone, args)
		if reason then return nil, reason end
		if not changed then return nil, "empty_intent" end
		return { { target = zone, patch = { rules = rules } } }
	elseif command == "applyNodeTemplateToZone" then
		local rules = context.sanitizeRules(args.rules)
		if not rules then return nil, "invalid_rules" end
		local changes = {}
		for _, target in pairs(registry.nodes or {}) do
			if target.zoneId == zone.id then
				if #changes >= 8192 then return nil, "node_limit" end
				changes[#changes + 1] = { target = target, patch = { rules = Protocol.copy(rules) } }
			end
		end
		return changes
	elseif command == "setZoneEnabled" then
		if type(args.enabled) ~= "boolean" then return nil, "invalid_enabled" end
		return { { target = zone, patch = { enabled = args.enabled } } }
	elseif command == "setZonePriority" then
		if not validInteger(args.priority, 100) then return nil, "invalid_priority" end
		return { { target = zone, patch = { priority = args.priority } } }
	end
	if args.direction ~= "up" and args.direction ~= "down" then return nil, "invalid_direction" end
	local sorted = {}
	for _, candidate in pairs(registry.zones or {}) do
		if candidate.networkId == networkId and candidate.enabled ~= false then sorted[#sorted + 1] = candidate end
	end
	table.sort(sorted, function(a, b)
		local pa, pb = tonumber(a.priority) or 50, tonumber(b.priority) or 50
		if pa ~= pb then return pa < pb end
		local na, nb = tostring(a.name or a.id):lower(), tostring(b.name or b.id):lower()
		if na ~= nb then return na < nb end
		return tostring(a.id) < tostring(b.id)
	end)
	for i = 1, #sorted do
		if sorted[i] == zone then
			local other = sorted[args.direction == "up" and i - 1 or i + 1]
			if not other then return nil, "priority_boundary" end
			return { { target = zone, patch = { priority = other.priority or 50 } },
				{ target = other, patch = { priority = zone.priority or 50 } } }
		end
	end
	return nil, "priority_target_unavailable"
end

function Transactions.dispatch(command, player, args, networkId)
	if not Protocol.commands[command] then return false end
	local state = sessionFor(player)
	local registry = GlobalStorageSiK.Network.getRegistry()
	local network = registry.networks and registry.networks[networkId]
	local revision = Protocol.revision(networkId)
	local clean, signature = Protocol.copy(args)
	if not state or not clean or not network or not validInteger(args.requestSeq, 2147483647)
		or args.configEpoch ~= state.epoch or args.requestId ~= state.epoch .. ":" .. tostring(args.requestSeq) then
		reply(player, args, networkId, false, "invalid_request", revision)
		return true
	end
	signature = command .. ":" .. signature
	-- Revalidate access even for a replay; a cached ACK is not an access grant.
	local allowed, reason = context.authorize(player, networkId)
	if not allowed then
		local result = reply(player, args, networkId, false, reason or "no_access", nil)
		if args.requestSeq > state.high then
			state.high = args.requestSeq
			remember(state, args.requestSeq, signature, result)
		end
		return true
	end
	local previous = state.results[args.requestSeq]
	if previous then
		if previous.signature ~= signature then reply(player, args, networkId, false, "request_id_reused", revision)
		else context.send(player, "actionResult", Protocol.copy(previous.result)) end
		return true
	end
	if args.requestSeq <= state.high then
		reply(player, args, networkId, false, "request_retired", revision) return true
	end
	state.high = args.requestSeq
	local changes
	if args.expectedRoutingRevision ~= revision then reason = "routing_revision_conflict"
	else changes, reason = prepare(registry, networkId, command, clean) end
	-- Return the persisted representation, including server-added identity fields.
	-- Only the affected target's bounded rules travel with its correlated ACK.
	local confirmedRules
	if changes and (command == "updateNode" or command == "updateZoneRules")
		and changes[1] and changes[1].patch.rules then
		confirmedRules = Protocol.copy(changes[1].patch.rules)
		if not confirmedRules then changes, reason = nil, "invalid_stored_rules" end
	end
	local result = { routingResult = true, requestId = args.requestId, requestSeq = args.requestSeq,
		configEpoch = state.epoch, networkId = networkId, ok = changes ~= nil,
		confirmedRules = confirmedRules,
		reason = reason or "committed", routingRevision = changes and revision + 1 or revision,
		message = GlobalStorageSiK.I18n.remote(changes and "IGUI_GS_RoutingSaved" or "IGUI_GS_RoutingRejected", reason or "") }
	-- Validate the whole ACK before mutation: normalization adds fields and the
	-- correlated envelope shares the same wire budget as the confirmed rules.
	local wireResult = Protocol.copy(result)
	if not wireResult and changes then
		changes, reason = nil, "invalid_stored_rules"
		result.ok, result.confirmedRules = false, nil
		result.reason, result.routingRevision = reason, revision
		result.message = GlobalStorageSiK.I18n.remote("IGUI_GS_RoutingRejected", reason)
		wireResult = Protocol.copy(result)
	end
	if changes then
		-- Lua dispatch is synchronous: all validation precedes these plain-table
		-- writes. No callbacks or Java operations occur inside this commit.
		for i = 1, #changes do
			for key, value in pairs(changes[i].patch) do changes[i].target[key] = value end
		end
		network.routingRevision = revision + 1
		revision = network.routingRevision
	end
	-- Record before any send/notification (SP may dispatch back synchronously).
	remember(state, args.requestSeq, signature, result)
	context.send(player, "actionResult", wireResult)
	if changes then context.committed(player, networkId, command, clean) end
	return true
end

return Transactions

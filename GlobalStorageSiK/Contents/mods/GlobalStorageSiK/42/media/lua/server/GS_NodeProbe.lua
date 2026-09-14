-- Bounded loaded-node probes with backoff; independent of terminal watchers.
require "GS_ItemSnapshot"
GlobalStorageSiK.NodeProbe = {}
local Probe = GlobalStorageSiK.NodeProbe
local states, order, cursor, active = {}, {}, 0, nil
local context, rebuildAt = nil, 0
local byObject, byContainer, bySquare = {}, {}, {}
local MIN_DELAY, MAX_DELAY, MAX_NODES = 1000, 10000, 8192
local function now() return getTimestampMs and getTimestampMs() or 0 end

function Probe.configure(value)
	context = value; states = {}; order = {}; active = nil; rebuildAt = 0
	byObject = {}; byContainer = {}; bySquare = {}
end
function Probe.forgetBaseline(nodeId)
	local state = states[nodeId]
	if state then state.signature = nil; state.due = 0; state.delay = MIN_DELAY end
end

local function rebuild()
	local registry = GlobalStorageSiK.Network.getRegistry()
	local previousId = order[cursor]
	local present, fresh = {}, {}
	for id, node in pairs(registry.nodes or {}) do
		local zone = registry.zones and registry.zones[node.zoneId]
		if zone and registry.networks[zone.networkId] and node.membership ~= "excluded"
			and node.enabled ~= false and zone.enabled ~= false then
			if #fresh >= MAX_NODES then break end
			present[id] = true; fresh[#fresh + 1] = id
			local state = states[id]
			if not state or state.node ~= node then states[id] = { node = node, due = 0, delay = MIN_DELAY } end
		end
	end
	local retired = {}
	for id in pairs(states) do if not present[id] then retired[#retired + 1] = id end end
	for i = 1, #retired do states[retired[i]] = nil end
	table.sort(fresh, function(a,b) return tostring(a)<tostring(b) end)
	order = fresh; cursor = 0; byObject = {}; byContainer = {}; bySquare = {}
	for i = 1, #order do
		local id, state = order[i], states[order[i]]
		if id == previousId then cursor = i end
		if state.object then byObject[state.object] = id end
		if state.container then byContainer[state.container] = id end
		local node = state.node
		local key = tostring(node.x) .. ":" .. tostring(node.y) .. ":" .. tostring(node.z)
		bySquare[key] = bySquare[key] or {}; bySquare[key][#bySquare[key] + 1] = id
	end
	rebuildAt = now() + 5000
end

local function finish(changed, signature)
	local state = active.state
	state.signature = signature
	state.delay = changed and MIN_DELAY or math.min(MAX_DELAY, state.delay * 2)
	state.due = now() + state.delay
	if changed then context.dirty(active.id, "physical_probe") end
	active = nil
end

local function availability(state, value)
	if state.node.snapshotAvailability == value then return end
	state.node.snapshotAvailability = value
	if context.availability then context.availability(state.node) end
end

local function step()
	if not active then
		if #order == 0 then return end
		cursor = cursor % #order + 1
		local id = order[cursor]
		local state = states[id]
		if not state or now() < state.due then return end
		local object, container, items = context.resolve(state.node)
		if not items then
			availability(state, "unloaded_or_missing")
			state.container = nil; state.signature = nil
			state.delay = math.min(MAX_DELAY, state.delay * 2); state.due = now() + state.delay
			return
		end
		availability(state, "loaded")
		state.object = object; byObject[object] = id; byContainer[container] = id
		local count = items:size()
		if count > 32768 then state.due = now() + MAX_DELAY; context.dirty(id, "probe_limit"); return end
		active = { id = id, state = state, node = state.node, old = state.node.itemSnapshot,
			object = object, container = container, items = items, count = count, index = 0, a = 1, b = 7 }
		return
	end
	if active.items:size() ~= active.count or active.node.itemSnapshot ~= active.old then finish(true, nil); return end
	if active.index >= active.count then
		local _, container, items = context.resolve(active.node)
		local signature = active.count .. ":" .. active.a .. ":" .. active.b
		local changed = container ~= active.container or not items or items:size() ~= active.count
			or active.state.container ~= container or active.state.signature ~= signature
		active.state.container = container
		finish(changed, signature)
		return
	end
	local item = active.items:get(active.index)
	local value = GlobalStorageSiK.ItemSnapshot.probeItem(item)
	if not value or #value > 8192 then finish(true, nil); return end
	for i = 1, #value do
		local byte = string.byte(value, i)
		active.a = (active.a * 31 + byte) % 2147483629
		active.b = (active.b * 33 + byte) % 2147483587
	end
	active.index = active.index + 1
end

function Probe.update()
	if not context then return end
	if now() >= rebuildAt and not active then rebuild() end
	local started = now()
	for i = 1, 16 do
		if now() - started >= 1 then break end
		local ok = pcall(step)
		if not ok then
			if active then finish(true, nil) end
			break
		end
	end
end

function Probe.signal(value)
	if not context or (type(value) ~= "table" and type(value) ~= "userdata") then return end
	local id = byContainer[value]
	if id then context.dirty(id, "container_event"); return end
	-- One IsoObject may own multiple ItemContainers. Resolve its known nodes,
	-- rather than selecting one container from the object map arbitrarily.
	-- Object events include the affected object. OnContainerUpdate often has
	-- no argument; that form deliberately cannot dirty all registered nodes.
	if value.getSquare then
		local square = value:getSquare()
		if square then
			local key = tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
			for _, nodeId in ipairs(bySquare[key] or {}) do
				local state=states[nodeId]
				if state and (state.object==value or context.resolve(state.node)==value) then
					context.dirty(nodeId, "object_event")
				end
			end
		end
	end
end

if Events then
	for _, name in ipairs({"OnObjectAdded", "OnObjectAboutToBeRemoved", "OnContainerUpdate"}) do
		if Events[name] then Events[name].Add(Probe.signal) end
	end
end

return Probe

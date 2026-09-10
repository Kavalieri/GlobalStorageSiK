-- Discovery-only boundary. No adapter is installed or activated in this release.
-- Deliberately not required by the classifier or exposed through GSSiK.API.
GlobalStorageSiK = GlobalStorageSiK or {}
local Registry = {}
GlobalStorageSiK.TaxonomyAdapterRegistry = Registry
local definitions, generation, busy = {}, 0, false

local function identifier(value)
	return type(value) == "string" and #value > 0 and #value <= 128
		and not value:find("[%c%s]")
end

function Registry.register(definition)
	if busy then return false, "ERR_BUSY" end
	if type(definition) ~= "table" or getmetatable(definition) ~= nil then return false, "ERR_SCHEMA" end
	local priority = definition.priority or 0
	if not identifier(definition.id) or not identifier(definition.targetModId)
		or type(priority) ~= "number" or priority ~= priority or math.abs(priority) > 1000
		or priority ~= math.floor(priority) or type(definition.detect) ~= "function"
		or type(definition.fingerprint) ~= "function" or type(definition.collectEvidence) ~= "function" then
		return false, "ERR_SCHEMA"
	end
	local allowed = { id = true, targetModId = true, priority = true, detect = true,
		fingerprint = true, collectEvidence = true }
	for key in pairs(definition) do if not allowed[key] then return false, "ERR_SCHEMA" end end
	local count = 0
	for _ in pairs(definitions) do count = count + 1 end
	if not definitions[definition.id] and count >= 16 then return false, "ERR_CAPACITY" end
	generation = generation + 1
	local entry = { id = definition.id, targetModId = definition.targetModId, priority = priority,
		detect = definition.detect, fingerprint = definition.fingerprint,
		collectEvidence = definition.collectEvidence, generation = generation }
	definitions[entry.id] = entry
	local handle = { id = entry.id }
	function handle:dispose()
		if busy or definitions[entry.id] ~= entry then return false end
		definitions[entry.id] = nil
		return true
	end
	return true, "OK", handle
end

-- Explicit diagnostic call only. Never executes collectEvidence, modifies native
-- paths, or enables a provider. A tied top priority has no selected candidate.
function Registry.discover(activeModIds)
	if busy then return nil, "ERR_BUSY" end
	if type(activeModIds) ~= "table" or getmetatable(activeModIds) ~= nil then return nil, "ERR_SCHEMA" end
	local active, count = {}, 0
	for key, id in pairs(activeModIds) do
		if type(key) ~= "number" or key ~= math.floor(key) or key < 1 or key > 4096
			or not identifier(id) then return nil, "ERR_SCHEMA" end
		count = count + 1
		active[id] = true
	end
	if count ~= #activeModIds then return nil, "ERR_SCHEMA" end
	local ordered, rows, targets = {}, {}, {}
	for _, entry in pairs(definitions) do ordered[#ordered + 1] = entry end
	table.sort(ordered, function(a, b)
		if a.priority ~= b.priority then return a.priority > b.priority end
		return a.id < b.id
	end)
	busy = true
	for index = 1, #ordered do
		local entry = ordered[index]
		local row = { id = entry.id, targetModId = entry.targetModId, priority = entry.priority,
			active = false, status = "ABSENT" }
		if active[entry.targetModId] then
			local ok, detected = pcall(entry.detect, { targetModId = entry.targetModId })
			row.status = "NOT_DETECTED"
			if not ok or type(detected) ~= "boolean" then row.status = "FAILED"
			elseif detected then
				local valid, fingerprint = pcall(entry.fingerprint, { targetModId = entry.targetModId })
				if not valid or type(fingerprint) ~= "string" or #fingerprint == 0
					or #fingerprint > 256 or fingerprint:find("%c") then row.status = "FAILED"
				else
					row.fingerprint, row.status = fingerprint, "DISCOVERED_INACTIVE"
					local target = targets[entry.targetModId]
					if not target then targets[entry.targetModId] = { row }
					elseif target[1].priority == row.priority then target[#target + 1] = row
					else row.status = "SHADOWED_INACTIVE" end
				end
			end
		end
		rows[#rows + 1] = row
	end
	busy = false
	for _, candidates in pairs(targets) do
		if #candidates > 1 then
			for index = 1, #candidates do candidates[index].status = "CONFLICT_INACTIVE" end
		end
	end
	return rows, "OK"
end

return Registry

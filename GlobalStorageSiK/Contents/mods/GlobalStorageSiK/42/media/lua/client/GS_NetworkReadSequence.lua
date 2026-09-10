-- Client orchestration only. Every step uses the existing individual loan and
-- waits for its final return result; this module never moves or creates items.
GlobalStorageSiK = GlobalStorageSiK or {}
local Sequence = {}
GlobalStorageSiK.NetworkReadSequence = Sequence
local active = {}

local function validId(value)
	return type(value) == "number" and value >= 0 and value < math.huge
		and value == math.floor(value)
end

local function representative(row)
	local id = row.representativeItemId or row.itemId
	if not validId(id) then id = nil end
	for i = 1, #(row.itemIds or {}) do
		local candidate = row.itemIds[i]
		if validId(candidate) and (not id or candidate < id) then id = candidate end
	end
	return id
end

function Sequence.plan(rows, describe, player)
	if type(rows) ~= "table" or #rows == 0 then return nil, "empty_selection" end
	local byIdentity = {}
	local function include(row)
		if type(row) ~= "table" or type(row.fullType) ~= "string" then return false end
		local spec = describe(row, player)
		if not spec or not spec.available then return false end
		local id = representative(row)
		if not id then return false end
		local title = row.literatureTitle
		if title ~= nil and type(title) ~= "string" then return false end
		local identity = row.fullType .. "\31" .. tostring(title or "")
		local previous = byIdentity[identity]
		if not previous or id < previous.itemIds[1] then
			byIdentity[identity] = {
				fullType = row.fullType, literatureTitle = title,
				itemIds = { id }, selectionMode = "exact_ids", count = 1,
				_gsReadIdentity = true,
			}
		end
		return true
	end
	for i = 1, #rows do
		local row = rows[i]
		local variants = type(row) == "table" and row.variantSummary or nil
		if type(variants) == "table" and #variants > 0 then
			for j = 1, #variants do
				if variants[j].detailKind ~= "literature" or not include(variants[j]) then
					return nil, "unreadable_selection"
				end
			end
		elseif not include(row) then return nil, "unreadable_selection" end
	end
	local keys, plan = {}, {}
	for key in pairs(byIdentity) do keys[#keys + 1] = key end
	table.sort(keys)
	for i = 1, #keys do plan[i] = byIdentity[keys[i]] end
	return plan
end

local function dispatch(state)
	if active[state.playerNum] ~= state or state.cancelled then return end
	local row = state.plan[state.index]
	if not row then active[state.playerNum] = nil; return end
	state.ready = false
	local settled = false
	local function onSettled(ok)
		if settled then return end
		settled = true
		if active[state.playerNum] ~= state then return end
		if not ok or state.cancelled then active[state.playerNum] = nil; return end
		state.index = state.index + 1
		if state.index > #state.plan then active[state.playerNum] = nil
		else state.ready = true end
	end
	local ok, sent = pcall(state.read, row, onSettled, function() return state.cancelled end)
	if not ok or sent ~= true then onSettled(false) end
end

function Sequence.start(playerNum, plan, read)
	if active[playerNum] or type(plan) ~= "table" or #plan == 0
		or type(read) ~= "function" then return false end
	local state = { playerNum = playerNum, plan = plan, read = read, index = 1 }
	active[playerNum] = state
	dispatch(state)
	return true
end

function Sequence.cancel(playerNum)
	local state = active[playerNum]
	if not state then return end
	state.cancelled = true
	-- An in-flight exact loan still owns this slot until it settles. A ready
	-- step has not borrowed anything and can be discarded immediately.
	if state.ready then active[playerNum] = nil end
end

function Sequence.hasPending()
	for _, state in pairs(active) do if state.ready then return true end end
	return false
end

function Sequence.cancelAll()
	for _, state in pairs(active) do state.cancelled = true end
	active = {}
end

function Sequence.update()
	local ready = {}
	for _, state in pairs(active) do
		if state.ready then ready[#ready + 1] = state end
	end
	for i = 1, #ready do dispatch(ready[i]) end
end

return Sequence

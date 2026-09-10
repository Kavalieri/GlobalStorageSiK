-- Bounded transfer of a complete playback selection. No item is borrowed until
-- the final commit. Replayed chunks are compared, never appended twice.
local Queue = {}
local drafts, serial = setmetatable({}, { __mode = "k" }), 0
local LIMIT, CHUNK, TTL, ACTORS = 16384, 64, 60000, 8

local function integer(value, low, high)
	return type(value) == "number" and value >= low and value <= high and value == math.floor(value)
end
local function text(value, maximum)
	return type(value) == "string" and #value > 0 and #value <= maximum
end
local function sameScope(draft, args)
	local a, b = draft.anchor, args.anchor
	return draft.networkId == args.networkId and type(b) == "table"
		and a.x == b.x and a.y == b.y and a.z == b.z
end
local function expire(now)
	local expired = {}
	for actor, draft in pairs(drafts) do
		if now - draft.touched >= TTL then expired[#expired + 1] = actor end
	end
	for i = 1, #expired do drafts[expired[i]] = nil end
end
local function status(draft)
	return { queueToken = draft.token, nextOffset = #draft.items + 1,
		queuedCount = #draft.items, queueTotal = draft.total }
end

function Queue.cancel(actor) drafts[actor] = nil end
function Queue.status(actor, now)
	expire(now)
	return drafts[actor] and status(drafts[actor]) or nil
end
function Queue.prepare(actor, args, now)
	expire(now)
	if not actor or type(args) ~= "table" or not integer(args.total, 1, LIMIT)
		or not integer(args.sequence, 1, 2147483600) or not text(args.networkId, 160)
		or type(args.anchor) ~= "table" or not integer(args.anchor.x, 0, 1000000)
		or not integer(args.anchor.y, 0, 1000000) or not integer(args.anchor.z, -32, 32) then
		return false, "invalid_queue"
	end
	local prior = drafts[actor]
	if prior and prior.sequence == args.sequence and prior.total == args.total and sameScope(prior, args) then
		prior.touched = now; return true, "replayed", status(prior)
	end
	local count = 0
	for _ in pairs(drafts) do count = count + 1 end
	if not prior and count >= ACTORS then return false, "queue_capacity" end
	serial = serial + 1
	local draft = { token = tostring(now) .. ":" .. tostring(serial), sequence = args.sequence,
		networkId = args.networkId, anchor = { x = args.anchor.x, y = args.anchor.y, z = args.anchor.z },
		total = args.total, items = {}, seen = {}, touched = now }
	drafts[actor] = draft
	return true, "OK", status(draft)
end
function Queue.append(actor, args, now)
	expire(now)
	local draft = drafts[actor]
	if not draft or type(args) ~= "table" or args.token ~= draft.token or not sameScope(draft, args) then
		return false, "queue_expired"
	end
	if not integer(args.offset, 1, LIMIT) or type(args.items) ~= "table"
		or #args.items < 1 or #args.items > CHUNK or args.offset > #draft.items + 1
		or args.offset + #args.items - 1 > draft.total then return false, "invalid_chunk" end
	local entries, seen = {}, {}
	for i = 1, #args.items do
		local row, position = args.items[i], args.offset + i - 1
		if type(row) ~= "table" or not integer(row.itemId, 0, 9007199254740991)
			or not text(row.fullType, 160) or not text(row.sourceNodeId, 240) then return false, "invalid_selection" end
		local key, old = tostring(row.itemId), draft.items[position]
		if old then
			if old.itemId ~= row.itemId or old.fullType ~= row.fullType or old.sourceNodeId ~= row.sourceNodeId then
				return false, "chunk_conflict"
			end
		elseif draft.seen[key] or seen[key] then return false, "duplicate_selection" end
		seen[key] = true
		entries[i] = { itemId = row.itemId, fullType = row.fullType, sourceNodeId = row.sourceNodeId }
	end
	-- Validate the complete chunk before touching the accepted prefix.
	for i = 1, #entries do
		local position = args.offset + i - 1
		if not draft.items[position] then
			draft.items[position] = entries[i]; draft.seen[tostring(entries[i].itemId)] = true
		end
	end
	draft.touched = now
	return true, "OK", status(draft)
end
function Queue.take(actor, args, now)
	expire(now)
	local draft = drafts[actor]
	if not draft or type(args) ~= "table" or args.token ~= draft.token
		or args.sequence ~= draft.sequence or not sameScope(draft, args) then return false, "queue_expired" end
	if #draft.items ~= draft.total then return false, "queue_incomplete" end
	drafts[actor] = nil
	return true, "OK", draft.items
end
return Queue

-- Bounded assembly of one explicitly requested public taxonomy snapshot.
-- No hooks: the existing client lifecycle supplies requests, messages and time.
require "GS_NativeWorldOverrides"
GlobalStorageSiK.NativeWorldProjection = {}
local Projection = GlobalStorageSiK.NativeWorldProjection
local World = GlobalStorageSiK.NativeWorldOverrides
Projection.PAGE_SIZE = World.PROJECTION_PAGE_SIZE
Projection.MAX_PAGES = math.ceil(World.MAX_ENTRIES / Projection.PAGE_SIZE)
Projection.TIMEOUT_MS = 10000
local pending

function Projection.cancel(requestId)
	if not requestId or (pending and pending.requestId == requestId) then pending = nil end
end

local function finiteTime(value)
	return type(value) == "number" and value >= 0 and value < math.huge
end

function Projection.clear()
	pending = nil
	return World.clearProjection()
end

function Projection.begin(requestId, now)
	if not World.validRevision(requestId) or requestId == 0 or not finiteTime(now) then return false end
	if pending and now >= pending.startedAt and now - pending.startedAt < Projection.TIMEOUT_MS then
		return false, "pending"
	end
	pending = { requestId = requestId, startedAt = now, pages = {}, received = 0 }
	return true
end

function Projection.isPending(now)
	if pending and finiteTime(now) and (now < pending.startedAt or now - pending.startedAt >= Projection.TIMEOUT_MS) then
		pending = nil
	end
	return pending ~= nil
end

local function copyArray(values, count, validate)
	if type(values) ~= "table" then return nil end
	local out, actual = {}, 0
	for key, value in pairs(values) do
		actual = actual + 1
		if actual > count or type(key) ~= "number" or key ~= math.floor(key)
			or key < 1 or key > count or not validate(value) then return nil end
		out[key] = value
	end
	if actual ~= count then return nil end
	return out
end

function Projection.accept(args, now)
	if not finiteTime(now) or not Projection.isPending(now) or type(args) ~= "table"
		or args.requestId ~= pending.requestId then return false, "unrequested" end
	if not World.validRevision(args.revision) or not World.validRevision(args.totalEntries)
		or args.totalEntries > World.MAX_ENTRIES then return false, "invalid_page" end
	local totalPages = math.max(1, math.ceil(args.totalEntries / Projection.PAGE_SIZE))
	if args.totalPages ~= totalPages or totalPages > Projection.MAX_PAGES
		or type(args.page) ~= "number" or args.page ~= math.floor(args.page)
		or args.page < 1 or args.page > totalPages then return false, "invalid_page" end
	if pending.revision and (pending.revision ~= args.revision or pending.totalEntries ~= args.totalEntries) then
		pending = nil
		return false, "snapshot_conflict"
	end
	local count = math.min(Projection.PAGE_SIZE, args.totalEntries - (args.page - 1) * Projection.PAGE_SIZE)
	local types = copyArray(args.types, count, World.validFullType)
	local paths = copyArray(args.paths, count, World.decodePath)
	if not types or not paths then return false, "invalid_page" end
	local previous = pending.pages[args.page]
	if previous then
		for i = 1, count do
			if previous.types[i] ~= types[i] or previous.paths[i] ~= paths[i] then
				pending = nil
				return false, "page_conflict"
			end
		end
		return true, "duplicate"
	end
	pending.revision, pending.totalEntries = args.revision, args.totalEntries
	pending.pages[args.page] = { types = types, paths = paths }
	pending.received = pending.received + 1
	if pending.received ~= totalPages then return true, "incomplete" end
	local entries = {}
	for page = 1, totalPages do
		local values = pending.pages[page]
		for i = 1, #values.types do
			local fullType = values.types[i]
			if entries[fullType] then
				pending = nil
				return false, "duplicate_type"
			end
			entries[fullType] = { nativePath = values.paths[i] }
		end
	end
	local revision = pending.revision
	pending = nil
	local ok, changed = World.acceptProjection(revision, entries)
	return ok, ok and "complete" or changed, ok and changed or nil
end

return Projection

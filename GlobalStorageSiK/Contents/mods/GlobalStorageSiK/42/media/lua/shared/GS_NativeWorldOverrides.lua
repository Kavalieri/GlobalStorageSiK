-- One authoritative world store; clients hold only a public in-memory projection.
-- No polling, networking or persistence access at load time.
require "GS_CatalogManager"
require "GS_NativeTaxonomyRegistry"

GlobalStorageSiK.NativeWorldOverrides = {}
local World = GlobalStorageSiK.NativeWorldOverrides
World.SCHEMA = 1
World.MAX_ENTRIES = 4096
World.PROJECTION_PAGE_SIZE = 64
World.MODDATA_KEY = "GlobalStorageSiK_TaxonomyWorld"
local publicEntries, publicRevision = {}, nil

function World.validRevision(value)
	return type(value) == "number" and value >= 0 and value <= 2147483647
		and value == math.floor(value)
end

function World.validFullType(value)
	return type(value) == "string" and #value <= 160
		and value:match("^[^%.%s%c]+%.[^%s%c]+$") ~= nil
end

local function pathParts(value)
	if type(value) ~= "string" or #value > 250 or value:sub(1, 7) ~= "native:" then return nil end
	local parts = {}
	for part in value:sub(8):gmatch("[^/]+") do
		if #parts == 3 or #part > 80 or not part:match("^[a-z0-9_]+$") then return nil end
		parts[#parts + 1] = part
	end
	if #parts == 0 or "native:" .. table.concat(parts, "/") ~= value then return nil end
	return parts
end

function World.validStoredPath(value)
	return pathParts(value) ~= nil
end

function World.decodePath(value)
	local parts = pathParts(value)
	if not parts then return nil end
	local registry = GlobalStorageSiK.NativeTaxonomyRegistry
	if not registry.hasL1(parts[1]) or (#parts > 1 and not registry.hasL2(parts[1], parts[2]))
		or (#parts > 2 and not registry.hasL3(parts[1], parts[2], parts[3])) then return nil end
	return { l1 = parts[1], l2 = parts[2], l3 = parts[3] }
end

function World.getStorage()
	if not GlobalStorageSiK.isAuthoritative or not GlobalStorageSiK.isAuthoritative() then return nil end
	if not ModData or not ModData.getOrCreate then return nil end
	-- Dedicated persistent bucket, never transmitted. The operational network
	-- registry is broadcast by other workflows and must not contain this audit.
	return ModData.getOrCreate(World.MODDATA_KEY)
end

function World.getAuthoritativeStore()
	local registry = World.getStorage()
	local store = registry and registry.taxonomyWorldOverrides
	if type(store) ~= "table" or store.schema ~= World.SCHEMA or type(store.entries) ~= "table"
		or not World.validRevision(store.revision) then return nil end
	return store
end

function World.getRevision()
	if GlobalStorageSiK.isAuthoritative and GlobalStorageSiK.isAuthoritative() then
		local store = World.getAuthoritativeStore()
		return store and store.revision or 0
	end
	return publicRevision
end

function World.resolve(fullType, scriptItem)
	if not scriptItem or not World.validFullType(fullType) then return nil end
	local entry
	if GlobalStorageSiK.isAuthoritative and GlobalStorageSiK.isAuthoritative() then
		local store = World.getAuthoritativeStore()
		entry = store and store.entries[fullType]
	else
		entry = publicEntries[fullType]
	end
	local path = type(entry) == "table" and World.decodePath(entry.nativePath)
	if not path then return nil end
	return path, {
		primary = { source = "world_fulltype_override", kind = "exact", scope = "world",
			confidence = 100, revision = World.getRevision() },
		supporting = {}, conflicting = {},
	}
end

-- Called only after the transport has assembled a complete, correlated snapshot.
-- Validate every row before replacing anything. Never retain incoming tables.
function World.acceptProjection(revision, entries)
	if GlobalStorageSiK.isAuthoritative and GlobalStorageSiK.isAuthoritative() then return false, "not_client" end
	if not World.validRevision(revision) or type(entries) ~= "table" then return false, "invalid_projection" end
	if publicRevision and revision < publicRevision then return false, "stale_projection" end
	local captured, changed, count = {}, {}, 0
	for fullType, entry in pairs(entries) do
		count = count + 1
		if count > World.MAX_ENTRIES or not World.validFullType(fullType) or type(entry) ~= "table"
			or not World.decodePath(entry.nativePath) then return false, "invalid_projection" end
		captured[fullType] = { nativePath = entry.nativePath }
		if not publicEntries[fullType] or publicEntries[fullType].nativePath ~= entry.nativePath then
			changed[#changed + 1] = fullType
		end
	end
	for fullType in pairs(publicEntries) do
		if not captured[fullType] then changed[#changed + 1] = fullType end
	end
	if publicRevision == revision and #changed > 0 then return false, "projection_conflict" end
	-- A replacement can remove 4096 and add 4096 distinct types. Invalidate in
	-- bounded slices without changing the script epoch or unrelated type caches.
	for first = 1, #changed, World.MAX_ENTRIES do
		local slice = {}
		for i = first, math.min(#changed, first + World.MAX_ENTRIES - 1) do slice[#slice + 1] = changed[i] end
		local ok = GlobalStorageSiK.CatalogManager.invalidateFullTypes(slice)
		if not ok then return false, "invalidation_failed" end
	end
	publicEntries, publicRevision = captured, revision
	return true, changed
end

function World.acceptDelta(revision, fullType, nativePath)
	if not World.validRevision(revision) or not World.validFullType(fullType)
		or (nativePath ~= false and not World.decodePath(nativePath)) then return false, "invalid_delta" end
	if publicRevision == nil or revision > publicRevision + 1 then return false, "projection_required" end
	if revision < publicRevision then return false, "stale_projection" end
	local captured = {}
	for key, value in pairs(publicEntries) do captured[key] = value end
	captured[fullType] = nativePath ~= false and { nativePath = nativePath } or nil
	return World.acceptProjection(revision, captured)
end

function World.clearProjection()
	if GlobalStorageSiK.isAuthoritative and GlobalStorageSiK.isAuthoritative() then return false end
	local changed = {}
	for fullType in pairs(publicEntries) do changed[#changed + 1] = fullType end
	if not GlobalStorageSiK.CatalogManager.invalidateFullTypes(changed) then return false end
	publicEntries, publicRevision = {}, nil
	return true
end

return World

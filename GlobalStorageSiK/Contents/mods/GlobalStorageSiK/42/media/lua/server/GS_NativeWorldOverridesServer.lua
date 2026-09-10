-- Authoritative world choices. Transport/permission callbacks stay in GS_Server.
require "GS_NativeWorldOverrides"
require "GS_NativeClassifier"

GlobalStorageSiK.NativeWorldOverridesServer = {}
local Server = GlobalStorageSiK.NativeWorldOverridesServer
local World = GlobalStorageSiK.NativeWorldOverrides

local function safeText(value, maximum)
	return type(value) == "string" and #value > 0 and #value <= maximum
		and not value:find("%c") and value:find("%S") ~= nil
end

local function getStore()
	local registry = World.getStorage()
	if type(registry) ~= "table" then return nil, nil, "storage_unavailable" end
	local store = registry.taxonomyWorldOverrides
	if store == nil then return registry, { schema = World.SCHEMA, revision = 0, entries = {} } end
	if type(store) ~= "table" or store.schema ~= World.SCHEMA
		or not World.validRevision(store.revision) or type(store.entries) ~= "table" then
		return nil, nil, "invalid_store"
	end
	local count = 0
	for fullType, entry in pairs(store.entries) do
		count = count + 1
		if count > World.MAX_ENTRIES or not World.validFullType(fullType) or type(entry) ~= "table"
			or not World.validStoredPath(entry.nativePath) then return nil, nil, "invalid_store" end
	end
	return registry, store
end

local function encodePath(path)
	if type(path) ~= "table" or type(path.l1) ~= "string" then return nil end
	local value = "native:" .. path.l1
	if path.l2 then value = value .. "/" .. path.l2 end
	if path.l3 then value = value .. "/" .. path.l3 end
	return World.decodePath(value) and value or nil
end

-- No response or retry is hidden here. Caller publishes the new revision and
-- invalidates affected network projections only after a successful mutation.
function Server.change(player, args, requireStaff)
	if not GlobalStorageSiK.isAuthoritative() then return false, "not_authoritative" end
	-- Singleplayer owns the whole save and has no Staff role by default.
	-- Hosted/dedicated MP still requires server Staff, never a network role:
	-- this store changes the classification of the entire world.
	local singleplayer = player ~= nil and not (isClient and isClient()) and not (isServer and isServer())
	if not singleplayer and (type(requireStaff) ~= "function" or not requireStaff(player, "changeTaxonomyOverride", nil)) then
		return false, "no_permission"
	end
	if type(args) ~= "table" or not World.validFullType(args.fullType)
		or not World.validRevision(args.expectedRevision)
		or (args.operation ~= "apply" and args.operation ~= "restore") then return false, "invalid_request" end
	local registry, store, err = getStore()
	if not registry then return false, err end
	if store.revision ~= args.expectedRevision then return false, "revision_conflict", store.revision end
	if store.revision == 2147483647 then return false, "revision_exhausted" end
	if not safeText(args.reason, 512) then return false, "invalid_reason" end
	local author = player and player.getUsername and player:getUsername()
	if not safeText(author, 128) then return false, "invalid_author" end
	local changedAtMs = getTimestampMs and getTimestampMs()
	if type(changedAtMs) ~= "number" or changedAtMs < 0 or changedAtMs >= math.huge
		or changedAtMs ~= math.floor(changedAtMs) then return false, "invalid_time" end
	local previous = store.entries[args.fullType]
	local replacement
	if args.operation == "apply" then
		if not World.decodePath(args.nativePath) then return false, "invalid_choice" end
		if args.expectedClassifierSchema ~= GlobalStorageSiK.CatalogManager.getClassifierSchema()
			or args.expectedCatalogFingerprint ~= GlobalStorageSiK.CatalogManager.getCatalogFingerprintDigest() then
			return false, "catalog_conflict"
		end
		local script = GlobalStorageSiK.I18n.getScriptItem(args.fullType)
		if not script then return false, "source_missing" end
		local baseline = GlobalStorageSiK.NativeClassifier.classifyDefault(args.fullType)
		if not baseline or baseline.pending then return false, "catalog_not_ready" end
		if baseline.evidence and baseline.evidence.primary
			and baseline.evidence.primary.source == "script_is_debug_only" then return false, "debug_excluded" end
		local nativePath = encodePath(baseline.primaryPath)
		if not nativePath then return false, "invalid_default" end
		local count = 0
		for _ in pairs(store.entries) do
			count = count + 1
			if count > World.MAX_ENTRIES then return false, "override_limit" end
		end
		if count > World.MAX_ENTRIES or (previous == nil and count == World.MAX_ENTRIES) then return false, "override_limit" end
		replacement = {
			schema = World.SCHEMA, revision = store.revision + 1,
			nativePath = args.nativePath, author = author, reason = args.reason,
			changedAtMs = changedAtMs,
			previous = { nativePath = type(previous) == "table" and previous.nativePath or nativePath,
				defaultNativePath = nativePath,
				source = baseline.evidence and baseline.evidence.primary and baseline.evidence.primary.source or "unknown",
				classifierSchema = GlobalStorageSiK.CatalogManager.getClassifierSchema(),
				catalogFingerprint = GlobalStorageSiK.CatalogManager.getCatalogFingerprintDigest() },
			originStatus = "unknown",
		}
	elseif previous == nil then
		return false, "override_missing"
	end
	-- Validate all inputs before touching the store. This also clears cached
	-- negative results and leaves unrelated fullTypes and script epochs intact.
	if not GlobalStorageSiK.CatalogManager.invalidateFullTypes({ args.fullType }) then return false, "invalidation_failed" end
	store.entries[args.fullType] = replacement
	store.revision = store.revision + 1
	store.lastChange = { fullType = args.fullType, operation = args.operation,
		author = author, reason = args.reason, changedAtMs = changedAtMs,
		revision = store.revision, schema = World.SCHEMA,
		beforePath = type(previous) == "table" and previous.nativePath or nil,
		afterPath = replacement and replacement.nativePath or nil }
	registry.taxonomyWorldOverrides = store
	return true, nil, store.revision, args.fullType
end

-- Public routes only. Inactive paths remain persisted but are not projected.
-- Build the whole bounded snapshot before sending the first page.
function Server.publicPages(requestId)
	if not GlobalStorageSiK.isAuthoritative() then return nil, "not_authoritative" end
	if not World.validRevision(requestId) or requestId == 0 then return nil, "invalid_request" end
	local registry, store, err = getStore()
	if not registry then return nil, err end
	local types, count = {}, 0
	for fullType, entry in pairs(store.entries) do
		count = count + 1
		if count > World.MAX_ENTRIES or not World.validFullType(fullType) or type(entry) ~= "table" then
			return nil, "invalid_store"
		end
		if World.decodePath(entry.nativePath) then types[#types + 1] = fullType end
	end
	table.sort(types)
	local totalPages = math.max(1, math.ceil(#types / World.PROJECTION_PAGE_SIZE))
	local pages = {}
	for page = 1, totalPages do
		local payload = { requestId = requestId, revision = store.revision, page = page,
			totalPages = totalPages, totalEntries = #types, types = {}, paths = {} }
		local first = (page - 1) * World.PROJECTION_PAGE_SIZE + 1
		for i = first, math.min(#types, first + World.PROJECTION_PAGE_SIZE - 1) do
			local fullType = types[i]
			payload.types[#payload.types + 1] = fullType
			payload.paths[#payload.paths + 1] = store.entries[fullType].nativePath
		end
		pages[#pages + 1] = payload
	end
	return pages
end

return Server

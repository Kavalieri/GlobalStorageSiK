-- Contract for revision-aware terminal inventory reuse.  This remains a source
-- test because physical container reconciliation requires the PZ runtime.

local ROOT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/"

local function read(path)
	local handle = assert(io.open(ROOT .. path, "rb"), path)
	local value = assert(handle:read("*a"))
	handle:close()
	return value
end

local function contains(source, needle, label)
	assert(source:find(needle, 1, true), label .. ": " .. needle)
end

local client = read("client/GS_Client.lua")
local server = read("server/GS_Server.lua")
local index = read("shared/GS_Index.lua")
local detail = read("client/GS_TerminalUI_Items.lua")

-- Closing UI may destroy widgets and physical references, but the aggregate
-- catalog is retained independently for each local player and network.
contains(client, "inventoryCatalogByPlayerNetwork", "aggregate cache missing")
contains(client, "inventoryCatalogKey(playerNum, networkId)", "cache is not player/network scoped")
contains(client, "payload.knownInventoryRevision = entry.inventoryRevision",
	"reopen does not send the known revision")
contains(client, "payload.knownCatalogScope = entry.catalogScope",
	"reopen does not send the authorized scope")
contains(client, "incoming.items = cached.items", "notModified does not restore aggregate rows")
contains(client, "GlobalStorageSiK.Client.itemDetailsCache = {}",
	"ephemeral item details are not cleared")

-- The server only omits the aggregate rows after matching both revision and
-- the freshly computed access scope.  Opening still reaches the ordinary
-- terminal/access validation path first.
local accessAt = assert(server:find("local accessOk, accessMode, terminal, accessReason =", 1, true),
	"open access validation missing")
local pushAt = assert(server:find("knownInventoryRevision = args.knownInventoryRevision", accessAt, true),
	"open request token is not forwarded")
assert(accessAt < pushAt, "notModified metadata is consumed before access validation")
contains(server, "knownScope == scopeSignature", "notModified ignores authorized scope")
contains(server, "math.floor(knownRevision) == inventoryRevision",
	"notModified ignores exact inventory revision")
contains(server, "if not notModified then rows = getCatalogRows",
	"server rebuilds rows even when the catalog is unchanged")

-- A physical rescan is required for missing/incomplete, suspect or expired
-- snapshots, while a recent stable snapshot can serve the opening immediately.
contains(server, 'return true, "incomplete_snapshot"', "incomplete snapshot is trusted")
contains(server, 'return true, "unknown_age"', "unknown snapshot age is trusted")
contains(server, 'return true, "potentially_stale"', "suspect snapshot is trusted")
contains(server, 'return true, "max_age"', "expired snapshot is trusted")
contains(server, 'return false, "recent"', "recent snapshot still forces a scan")
contains(server, "SNAPSHOT_MAX_AGE_MS", "authoritative maximum age is missing")
contains(server, "scheduleSnapshotSync", "known external mutations do not schedule reconciliation")

-- Revision invalidation reflects normalized content changes, not every scan.
contains(index, "function GlobalStorageSiK.Index.contentSignature(networkId)",
	"normalized content signature missing")
contains(server, "local contentChanged = finalContentSignature ~= summary._startContentSignature",
	"scan completion does not compare normalized content")
contains(server, "if contentChanged then", "revision change is unconditional")
contains(server, "GlobalStorageSiK.Index.bumpInventoryRevision(networkId, false)",
	"real changes do not advance inventory revision")

-- Expanded group details remain demand-driven and bound to the aggregate
-- revision so stale children cannot be acted upon.
contains(detail, "detailPage.inventoryRevision", "detail pages are not revision-bound")
contains(detail, "pageStale", "stale detail state is not represented")
contains(detail, "disabled = pending or pageStale", "stale pager remains actionable")

print("inventory_snapshot_cache_contract: OK")
return true

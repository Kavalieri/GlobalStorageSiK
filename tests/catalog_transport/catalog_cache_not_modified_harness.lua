-- Semantic harness for the real GS_Server notModified predicate.
-- The predicate is extracted from production source; no decision logic is
-- reproduced here. This does not load the complete server.
local function check(value, message) if not value then error(message, 2) end end
local sourcePath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_Server.lua"
local source = assert(io.open(sourcePath, "r")):read("*a")
local start = assert(source:find("\tlocal knownRevision = requestMeta", 1, true))
local finish = assert(source:find("\n\tlocal rows = nil", start, true))
local predicate = source:sub(start, finish - 1)
GlobalStorageSiK = {
  Index = {
    getSnapshotRevision = function(networkId) return _snapshot[networkId] end,
    getInventoryRevision = function(networkId) return _inventory[networkId] end,
  },
  ZoneScanJob = {isActive = function(networkId) return _active[networkId] == true end},
}
local extracted = assert(loadstring("return function(requestMeta, networkId, inventoryRevision, scopeSignature, scanNeeded, pendingSnapshotSync)\n"
  .. "local shouldScanOnOpen = function() return scanNeeded end\n"
  .. "local pendingSnapshotSync = pendingSnapshotSync or {}\n"
  .. predicate .. "\nreturn notModified\nend"))()
_snapshot, _inventory, _active = {}, {}, {}
local function evaluate(requestMeta, networkId, revision, scope, options)
  options = options or {}; _inventory[networkId] = revision; _snapshot[networkId] = options.snapshot or revision
  _active[networkId] = options.active == true
  return extracted(requestMeta, networkId, revision, scope, options.scan == true, options.pending)
end
local function token(networkId, revision, scope)
  return {allowNotModified=true, knownCatalogNetworkId=networkId,
    knownInventoryRevision=revision, knownCatalogScope=scope}
end

check(evaluate(token("net-a", 10, "scope-a"), "net-a", 10, "scope-a") == true,
  "same network/revision/scope was not reusable")
check(evaluate(token(nil, 10, "scope-a"), "net-a", 10, "scope-a") == true,
  "legacy nil network was not reusable")
check(evaluate(token("net-a", 10, "scope-a"), "net-b", 10, "scope-a") == false,
  "different network reused matching revision/scope")
check(evaluate(token("net-a", 10, "scope-a"), "net-a", 10, "scope-b") == false,
  "different scope reused snapshot")
check(evaluate(token("net-a", 9, "scope-a"), "net-a", 10, "scope-a") == false,
  "different known revision reused snapshot")
check(evaluate(token("net-a", 10, "scope-a"), "net-a", 10, "scope-a", {snapshot=9}) == false,
  "stale snapshot revision reused snapshot")
check(evaluate(token("net-a", 10, "scope-a"), "net-a", 10, "scope-a", {scan=true}) == false,
  "pending scan was treated as unchanged")
check(evaluate(token("net-a", 10, "scope-a"), "net-a", 10, "scope-a", {active=true}) == false,
  "active scan job was treated as unchanged")
check(evaluate(token("net-a", 10, "scope-a"), "net-a", 10, "scope-a", {pending={ ["net-a"] = true }}) == false,
  "pending snapshot sync was treated as unchanged")
check(evaluate({knownInventoryRevision=10, knownCatalogScope="scope-a"}, "net-a", 10, "scope-a") == false,
  "missing allowNotModified flag was accepted")

print("catalog_cache_not_modified_harness: PASS network identity, legacy nil, revision/scope, scan/pending/snapshot fences")

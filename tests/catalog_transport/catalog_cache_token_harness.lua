-- Runtime semantic harness for the real GS_Client cache-token function.
-- Extracts only the function from production source; no implementation copy.
local function check(value, message) if not value then error(message, 2) end end
local sourceFile = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_Client.lua"
local source = assert(io.open(sourceFile, "r")):read("*a")
local now = 1000
getTimestampMs = function() return now end
local start = assert(source:find("function GlobalStorageSiK.Client.addInventoryCatalogToken", 1, true))
local finish = assert(source:find("\n\nfunction GlobalStorageSiK.Client.clearInventoryCatalog", start, true))
local functionSource = source:sub(start, finish - 1)
GlobalStorageSiK = {Client = {}}
local function inventoryCatalogKey(playerNum, networkId)
  return tostring(tonumber(playerNum) or 0) .. string.char(30) .. tostring(networkId or "")
end
_G.inventoryCatalogKey = inventoryCatalogKey
assert(loadstring(functionSource))()
local Client = GlobalStorageSiK.Client
Client.inventoryCatalogByPlayerNetwork = {}
local function cache(playerNum, networkId, revision, scope)
  Client.inventoryCatalogByPlayerNetwork[inventoryCatalogKey(playerNum, networkId)] = {
    playerNum=playerNum, networkId=networkId, inventoryRevision=revision, catalogScope=scope,
  }
end
local function clean(payload)
  payload.knownCatalogNetworkId = nil
  payload.knownInventoryRevision = nil
  payload.knownCatalogScope = nil
  return payload
end

-- Explicit argument wins over both payload and per-player active fallback.
Client.activeNetworkIdByPlayer = {[0]="active-0", [1]="active-1"}
cache(0, "explicit", 17, "scope-explicit")
local explicit = clean({networkId="payload-network", terminalHint={networkId="hint"}})
Client.addInventoryCatalogToken(explicit, 0, "explicit")
check(explicit.knownCatalogNetworkId == "explicit" and explicit.knownInventoryRevision == 17
  and explicit.knownCatalogScope == "scope-explicit", "explicit network token mismatch")
check(explicit.networkId == "payload-network" and explicit.terminalHint.networkId == "hint",
  "token helper rewrote opening target fields")

-- Without a target, fallback is restricted to the active network of that player.
cache(0, "active-0", 23, "scope-active")
local fallback = clean({terminalHint={x=1}})
Client.addInventoryCatalogToken(fallback, 0)
check(fallback.knownCatalogNetworkId == "active-0" and fallback.knownInventoryRevision == 23
  and fallback.knownCatalogScope == "scope-active", "active fallback token missing")
check(fallback.networkId == nil and fallback.terminalHint.x == 1,
  "fallback filled networkId or terminalHint")

-- A cache entry from another player never contaminates the current player.
cache(1, "active-1", 31, "scope-other")
local isolated = clean({})
Client.addInventoryCatalogToken(isolated, 0)
check(isolated.knownCatalogNetworkId == "active-0", "player fallback unexpectedly changed")
local other = clean({})
Client.addInventoryCatalogToken(other, 1)
check(other.knownCatalogNetworkId == "active-1", "other-player token not independently resolved")
local noEntry = clean({})
Client.activeNetworkIdByPlayer[2] = "uncached"
Client.addInventoryCatalogToken(noEntry, 2)
check(noEntry.knownCatalogNetworkId == nil and noEntry.networkId == nil,
  "uncached active network produced a token or target")

-- A known entry for a different explicit network is ignored.
local wrongNetwork = clean({networkId="missing"})
Client.addInventoryCatalogToken(wrongNetwork, 0)
check(wrongNetwork.knownCatalogNetworkId == nil and wrongNetwork.knownInventoryRevision == nil,
  "different network reused a cache token")

-- Execute the real catalog storage/clear functions to verify one catalog per
-- player, full row retention, cachedAt stamping, TTL expiry and clock rollback.
local clearStart = assert(source:find("function GlobalStorageSiK.Client.clearInventoryCatalog", 1, true))
local clearFinish = assert(source:find("\n\nfunction GlobalStorageSiK.Client.getInventoryCatalogPreview", clearStart, true))
assert(loadstring(source:sub(clearStart, clearFinish - 1)))()
local applyStart = assert(source:find("local function applyInventoryCatalog", 1, true))
local applyFinish = assert(source:find("\n\nlocal function safeRequire", applyStart, true))
local applyCatalog = assert(loadstring("local function applyInventoryCatalog" .. source:sub(applyStart + #"local function applyInventoryCatalog", applyFinish - 1)
  .. "\nreturn applyInventoryCatalog"))()
now = 5000
local firstCatalog = {networkId="net-a", inventoryRevision=4, catalogScope="all", items={}}
for i = 1, 1200 do firstCatalog.items[i] = {id=i, name="full-row-" .. i} end
applyCatalog(firstCatalog, 0)
check(Client.inventoryCatalogByPlayerNetwork[inventoryCatalogKey(0, "net-a")] ~= nil,
  "initial catalog was not stored")
local secondCatalog = {networkId="net-b", inventoryRevision=5, catalogScope="all", items=firstCatalog.items}
applyCatalog(secondCatalog, 0)
check(Client.inventoryCatalogByPlayerNetwork[inventoryCatalogKey(0, "net-a")] == nil,
  "replacement retained a second network catalog for one player")
local stored = Client.inventoryCatalogByPlayerNetwork[inventoryCatalogKey(0, "net-b")]
check(stored and stored.cachedAt == now and #stored.items == 1200, "catalog storage truncated rows or missed cachedAt")
local within = clean({})
Client.activeNetworkIdByPlayer[0] = "net-b"; Client.addInventoryCatalogToken(within, 0)
check(within.knownInventoryRevision == 5, "fresh cached catalog token missing")
now = 305001
local expired = clean({})
Client.addInventoryCatalogToken(expired, 0)
check(expired.knownCatalogNetworkId == nil and Client.inventoryCatalogByPlayerNetwork[inventoryCatalogKey(0, "net-b")] == nil,
  "expired cache token was reused")
applyCatalog({networkId="net-c", inventoryRevision=6, catalogScope="all", items={{id="clock"}}}, 0)
now = 304000
local rollback = clean({})
Client.addInventoryCatalogToken(rollback, 0)
check(rollback.knownCatalogNetworkId == nil, "clock rollback reused cache token")

print("catalog_cache_token_harness: PASS explicit precedence, per-player fallback/isolation, no target injection, cache miss")

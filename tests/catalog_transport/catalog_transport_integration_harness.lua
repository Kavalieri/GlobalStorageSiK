-- Core 1.5.3-dev1: edge harness for CatalogServer/CatalogClient.
-- Loads the real modules and supplies only transport/UI boundary callbacks.
local function check(v, m) if not v then error(m, 2) end end
local CODEC_PATH = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_CatalogCodec.lua"
local SERVER_PATH = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_CatalogServer.lua"
local CLIENT_PATH = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_CatalogClient.lua"
GlobalStorageSiK = {}
local Codec = assert(dofile(CODEC_PATH))
package.preload.GS_CatalogCodec = function() return Codec end
local now = 1000
getTimestampMs = function() return now end

local sent, stale = {}, 0
local serverContext = {
  visit = function(fn) fn("p0") end,
  valid = function() return true end,
  stale = function() stale = stale + 1 end,
  send = function(player, command, payload) sent[#sent + 1] = { player=player, command=command, payload=payload } end,
}
local Server = assert(dofile(SERVER_PATH))
Server.configure(serverContext)
local confirmation = { playerNum=0, openSeq=7, networkId="net", accessMode="local", terminalAnchor={x=1,y=2,z=0}, confirmedProximityRange=10, confirmedWirelessRange=0 }
check(Server.begin("p0", confirmation) == true, "server begin")
local payload = { networkId="net", inventoryRevision=4, catalogScope="all", itemTypeCount=1,
  items={{id="long", name=string.rep("東京🚀", 700)}} }
check(Server.queue("p0", payload) == true, "server queue")
Server.update()
check(#sent >= 2 and sent[#sent].command == "terminalCatalogChunk", "server did not dispatch open ack and chunk")
local frame = sent[#sent].payload
check(frame.part == 1 and frame.total >= 1 and frame.tokenCount > 0, "server frame envelope")
local receiptBefore = #sent
Server.receipt("p0", {openSeq=7, networkId="net", batchId=frame.batchId, inventoryRevision=4, catalogScope="all"})
check(#sent == receiptBefore, "receipt must not send a response")
Server.clear("p0")
check(Server.isOpening("p0") == nil, "server clear released session")

local failures, applied, receipts = {}, {}, 0
local currentOpen, pendingOpen = true, true
local clientContext = {
  current = function(player, seq) return currentOpen and player == 0 and seq == 7 end,
  pending = function() return pendingOpen end,
  allowed = function() return true end,
  confirm = function() return true end,
  apply = function(value) applied[#applied + 1] = value; return true end,
  receipt = function() receipts = receipts + 1 end,
  failure = function(player, seq, reason) failures[#failures + 1] = reason end,
  hasCache = function() return true end,
}
local Client = assert(dofile(CLIENT_PATH))
local function metadata(batchId, revision, encoded)
  return {protocol=1, playerNum=0, openSeq=7, networkId="net", batchId=batchId,
    inventoryRevision=revision, catalogScope="all", total=#encoded.chunks,
    tokenCount=encoded.tokenCount, totalBytes=encoded.totalBytes}
end
local function makeFrames(batchId, revision, encoded)
  local result, meta = {}, metadata(batchId, revision, encoded)
  for i = 1, #encoded.chunks do
    local frameCopy = {}
    for k, v in pairs(meta) do frameCopy[k] = v end
    frameCopy.part, frameCopy.data = i, encoded.chunks[i]
    result[i] = frameCopy
  end
  return result
end
local function startAndAck()
  Client.clear(); Client.configure(clientContext); Client.start(0, 7)
  Client.ack({playerNum=0, openSeq=7, networkId="net", inventoryRevision=4, catalogScope="all", accessMode="local"})
end
local clientValue = {playerNum=0, openSeq=7, networkId="net", inventoryRevision=4, catalogScope="all", itemTypeCount=1,
  items={{id="long", name=string.rep("中文🚀", 700)}}}
local encoded = assert(Codec.encode(clientValue, 4200))
check(#encoded.chunks > 1, "client fixture must produce multiple chunks")
local frames = makeFrames(1, 4, encoded)
startAndAck()
for i = #frames, 1, -1 do Client.receive(frames[i]) end
check(#applied == 1 and receipts == 1, "reordered chunks did not complete once")

-- Progress refreshes the idle deadline; the same batch then times out only
-- after a full idle interval. The timeout callback is an observable boundary.
startAndAck(); Client.receive(frames[1]); now = now + 9000; Client.update(now)
Client.receive(frames[2]); now = now + 9000; Client.update(now)
check(failures[#failures] ~= "catalog_timeout", "progress incorrectly triggered idle timeout")
now = now + 10001; Client.update(now)
check(failures[#failures] == "catalog_timeout", "idle timeout did not fire after progress")

-- Exact duplicates are idempotent; conflicting duplicates fence the slot.
startAndAck(); Client.receive(frames[1]); Client.receive(frames[1])
local conflict = {}; for k, v in pairs(frames[1]) do conflict[k] = v end
conflict.data = {}; for i, v in pairs(frames[1].data) do conflict.data[i] = v end
conflict.data[1] = conflict.data[1] == "t" and "n" or "t"
Client.receive(conflict)
check(failures[#failures] == "catalog_duplicate", "conflicting duplicate was not rejected")

-- A newer batch supersedes an unfinished same-revision batch. Older revisions
-- cannot replace a newer unfinished batch.
local newerValue = {playerNum=0, openSeq=7, networkId="net", inventoryRevision=5, catalogScope="all", itemTypeCount=1, items={{id="new"}}}
local newer = makeFrames(2, 5, assert(Codec.encode(newerValue, 4200)))
local olderValue = {playerNum=0, openSeq=7, networkId="net", inventoryRevision=3, catalogScope="all", itemTypeCount=1, items={{id="old"}}}
local older = makeFrames(3, 3, assert(Codec.encode(olderValue, 4200)))
startAndAck(); Client.receive(frames[1]); Client.receive(newer[1]); Client.receive(older[1])
for i = 2, #newer do Client.receive(newer[i]) end
check(applied[#applied].items[1].id == "new", "newer revision did not supersede pending batch")

-- Per-player close and timeout release the slot and invoke the boundary once.
Client.clear(0); startAndAck(); now = now + 60001; Client.update(now)
check(failures[#failures] == "catalog_timeout", "timeout did not release player slot")
Client.clear(0); check(Client.update(now) == false, "cleared player remained active")

-- Closing the UI/connection removes the player slot without a stale callback.
startAndAck(); currentOpen = false; pendingOpen = false
local failuresBeforeClose = #failures
check(Client.update(now) == false, "disconnected player remained active")
check(#failures == failuresBeforeClose, "disconnect emitted a spurious failure callback")
currentOpen = true

-- A delayed targeted close must not discard a newer active reassembly.
pendingOpen = true
startAndAck(); Client.receive(frames[1]); Client.clear(0, 6)
local beforeTargeted = #applied
for i = 2, #frames do Client.receive(frames[i]) end
check(#applied == beforeTargeted + 1, "older targeted close discarded active batch")
startAndAck(); Client.receive(frames[1]); Client.clear(0, 7)
beforeTargeted = #applied
for i = 2, #frames do Client.receive(frames[i]) end
check(#applied == beforeTargeted, "matching targeted close retained batch")

-- A consumer can replace the request before returning failure. The old
-- completion must leave that new slot and its deadline intact.
startAndAck()
local failuresBeforeReopen, receiptsBeforeReopen = #failures, receipts
local originalApply = clientContext.apply
clientContext.apply = function(value) Client.start(0, 7); return false end
for i = 1, #frames do Client.receive(frames[i]) end
check(#failures == failuresBeforeReopen and receipts == receiptsBeforeReopen,
  "old apply completion affected replacement request")
clientContext.apply = originalApply
Client.ack({playerNum=0, openSeq=7, networkId="net", inventoryRevision=4, catalogScope="all"})
local beforeReopen = #applied
for i = 1, #frames do Client.receive(frames[i]) end
check(#applied == beforeReopen + 1, "replacement request was lost after old apply failed")

print("catalog_transport_integration_harness: PASS server envelope, client reorder/dedup/supersession/timeout/reentry")

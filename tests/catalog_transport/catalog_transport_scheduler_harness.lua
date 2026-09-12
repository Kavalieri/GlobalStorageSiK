-- Scheduler regression harness. Loads the real GS_CatalogServer.lua and uses
-- only its configure boundary; no scheduler algorithm is copied here.
local function check(value, message) if not value then error(message, 2) end end
local ROOT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/"
GlobalStorageSiK = {}
local Codec = assert(dofile(ROOT .. "shared/GS_CatalogCodec.lua"))
package.preload["GS_CatalogCodec"] = function() return Codec end
local now = 1000
getTimestampMs = function() return now end

local live = {"p0", "p1", "p2", "p3", "p4", "p5"}
local sent, aborted, stale = {}, {}, 0
local Server
local context = {
  visit = function(fn) for i = 1, #live do fn(live[i]) end end,
  valid = function() return true end,
  stale = function() stale = stale + 1 end,
  abort = function(player) aborted[player] = (aborted[player] or 0) + 1 end,
  send = function(player, command, payload)
    sent[#sent + 1] = {player=player, command=command, payload=payload}
    if command == "terminalCatalogChunk" and payload.part == payload.total then
      -- Exercise synchronous SP completion after the server advances nextPart.
      Server.receipt(player, payload)
    end
  end,
}
Server = assert(dofile(ROOT .. "server/GS_CatalogServer.lua"))
Server.configure(context)

local function confirmation(player)
  return {playerNum=tonumber(player:sub(2)), openSeq=1, networkId="net-" .. player,
    accessMode="local", terminalAnchor={x=1,y=2,z=0}, confirmedProximityRange=10,
    confirmedWirelessRange=0}
end
local function payload(player)
  return {networkId="net-" .. player, inventoryRevision=1, catalogScope="all",
    itemTypeCount=1, items={{id="long-" .. player, name=string.rep("scheduler-", 20000)}}}
end
local function beginAndQueue(player)
  check(Server.begin(player, confirmation(player)), "begin " .. player)
  check(Server.queue(player, payload(player)), "queue " .. player)
end
local function clearSent() sent = {} end
local function chunksFor(player)
  local result = {}
  for i = 1, #sent do
    if sent[i].player == player and sent[i].command == "terminalCatalogChunk" then
      result[#result + 1] = sent[i]
    end
  end
  return result
end

-- One busy recipient must consume the complete four-frame global allowance.
beginAndQueue("p0")
clearSent(); Server.update()
local first = chunksFor("p0")
check(#first == 4, "single busy player did not receive exactly four frames per update: " .. #first)
for i = 1, #first do
  check(first[i].payload.part == i, "single-player frame order")
  local wireSize, wireReason = Codec.size(first[i].payload)
  check(wireSize and wireSize + 128 <= Codec.FRAME_BYTES,
    "wire cap exceeded: " .. tostring(wireReason or wireSize))
end
Server.clear("p0")

-- Two busy recipients share the allowance fairly, two frames each.
beginAndQueue("p0"); beginAndQueue("p1")
clearSent(); Server.update()
check(#chunksFor("p0") == 2 and #chunksFor("p1") == 2, "two-player fairness was not two frames each")
Server.clear("p0"); Server.clear("p1")

-- More recipients eventually all make progress, with no recipient starved.
for i = 1, #live do beginAndQueue(live[i]) end
clearSent()
for tick = 1, 4 do Server.update() end
for i = 1, #live do check(#chunksFor(live[i]) > 0, "starved recipient " .. live[i]) end
for i = 1, #live do Server.clear(live[i]) end

-- An idle session contributes no sends or spin, while a queued peer progresses.
beginAndQueue("p0")
check(Server.begin("p1", confirmation("p1")), "idle begin")
clearSent(); Server.update()
check(#chunksFor("p0") == 4 and #chunksFor("p1") == 0, "idle session consumed scheduler work")
Server.clear("p0"); Server.clear("p1")

-- Reentrant clear from send must release the job and remove the recipient safely.
beginAndQueue("p0")
local originalSend = context.send
context.send = function(player, command, frame)
  originalSend(player, command, frame)
  if command == "terminalCatalogChunk" then Server.clear(player) end
end
clearSent(); Server.update(); local afterClear = #sent
Server.update()
check(#sent == afterClear and Server.isOpening("p0") == nil, "reentrant clear left a scheduled job")
context.send = originalSend

-- Restore a fresh recipient and verify synchronous receipt releases memory/job.
beginAndQueue("p0")
clearSent()
for i = 1, 20 do Server.update() end
check(#chunksFor("p0") > 0, "fresh recipient made no progress")
check(Server.isOpening("p0") == false, "last-part synchronous receipt did not close opening")
check(stale == 0, "unexpected stale callback")

print("catalog_transport_scheduler_harness: PASS four-frame allowance, fairness, idle, reentrant clear, synchronous receipt")

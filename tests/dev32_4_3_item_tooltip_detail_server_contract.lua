-- Core 1.4.3-dev32.4.3: bounded exact tooltip detail server.
for _, name in ipairs({ "GS_Index", "GS_ItemSnapshot", "GS_Network", "GS_Permissions",
	"GS_Utils", "GS_Zones", "GS_Log" }) do
	package.loaded[name] = true
end

local now = 100
local revision = 7
local worldLookups = 0
local directLookups = 0
local getLiveCalls = 0
local sent = {}
local item = { marker = "physical" }
local container = {
	getItemWithID = function(_, itemId)
		directLookups = directLookups + 1
		return itemId >= 1 and item or nil
	end,
}
local object = { container = container }
local registry = {
	zones = { zone = { id = "zone", networkId = "net" } },
	nodes = { node = { id = "node", zoneId = "zone", containerIndex = 0 } },
}

getTimestampMs = function() return now end
GlobalStorageSiK = {
	Index = { getInventoryRevision = function() return revision end },
	ItemSnapshot = {
		tooltipDetailFromItem = function(value)
			assert(value == item, "server must inspect the physical item")
			return { fullType = "Base.PetrolCan", fluidType = "petrol" }
		end,
	},
	Network = {
		findWorldObject = function(node)
			assert(node == registry.nodes.node, "only the requested known node may resolve")
			worldLookups = worldLookups + 1
			return object
		end,
		getLiveContainers = function()
			getLiveCalls = getLiveCalls + 1
			error("tooltip detail must never scan live containers")
		end,
	},
	Permissions = { canAccessZone = function() return true end },
	Utils = { getObjectContainer = function(obj, index)
		assert(obj == object and index == 0)
		return obj.container
	end },
	Zones = { getRegistry = function() return registry end },
	Log = { debug = function() end },
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/server/GS_ItemTooltipDetailServer.lua")

local function request(player, id, requestedRevision, nodeId)
	GlobalStorageSiK.ItemTooltipDetailServer.handle(player, {
		requestId = "request-" .. tostring(id), nodeId = nodeId or "node",
		itemId = id, inventoryRevision = requestedRevision,
	}, "net", function() return true end, function(_, command, payload)
		assert(command == "itemTooltipDetail")
		sent[#sent + 1] = payload
	end)
	return sent[#sent]
end

local player = {}
local first = request(player, 42, 7)
assert(first.ok and first.cache == "miss" and first.fluidType == "petrol")
assert(worldLookups == 1 and directLookups == 1, "first request inspects one node/item")
local second = request(player, 42, 7)
assert(second.ok and second.cache == "hit")
assert(worldLookups == 1 and directLookups == 1,
	"same revision and itemId must hit cache without world/container lookup")

revision = 8
local stale = request(player, 42, 7)
assert(not stale.ok and stale.reason == "stale_revision",
	"stale client revision must receive an explicit stale response")
assert(worldLookups == 1, "stale requests must not inspect a node")
local refreshed = request(player, 42, 8)
assert(refreshed.ok and refreshed.cache == "miss")
assert(worldLookups == 2 and directLookups == 2,
	"revision change must invalidate the old exact-item cache")

local unknown = request({}, 42, 8, "unknown")
assert(not unknown.ok and unknown.reason == "invalid_node")
assert(worldLookups == 2, "unknown node must stop before world lookup")

local ratePlayer = {}
local last = nil
for id = 1, 13 do last = request(ratePlayer, id, 8) end
assert(last and not last.ok and last.reason == "rate_limited",
	"thirteenth request in one second must be rate limited")
assert(getLiveCalls == 0, "exact tooltip detail must never call getLiveContainers")

print("dev32_4_3_item_tooltip_detail_server_contract: OK")

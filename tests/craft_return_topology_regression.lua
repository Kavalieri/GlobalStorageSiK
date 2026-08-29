-- DEV32.3 regression harness. Run from GlobalStorageSiK-Repo:
-- lua51.exe tests/craft_return_topology_regression.lua
--
-- This is static/contract evidence, not an in-game test. It proves one craft
-- return sweep creates one topology snapshot per player, even with many
-- pending borrowed items.

local tickHandlers = {}
local snapshotCalls = 0
local deposits = 0

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected=" .. tostring(expected)
			.. " actual=" .. tostring(actual), 2)
	end
end

getTimestampMs = function() return 1000 end
getSpecificPlayer = function() return _G.harnessPlayer end
Events = { OnTick = { Add = function(fn) tickHandlers[#tickHandlers + 1] = fn end } }
ISInventoryPaneContextMenu = { getContainers = function() return {} end }

local required = {
	"GS_NetworkCraftBridge", "GS_TerminalAccess", "GS_NetClient", "GS_Network", "GS_Libs",
	"GS_Log", "GS_InventorySync", "GS_Deposit", "GS_Transfer",
}
for i = 1, #required do package.loaded[required[i]] = true end

local inventory = { items = {} }
local source = { items = {} }
local function remove(container, item)
	for i = 1, #container.items do
		if container.items[i] == item then table.remove(container.items, i); return true end
	end
	return false
end
local function item(id)
	return { getID = function() return id end, getFullType = function() return "Base.Hammer" end }
end

harnessPlayer = {
	getPlayerNum = function() return 0 end,
	getInventory = function() return inventory end,
}

GlobalStorageSiK = {
	isAuthoritative = function() return true end,
	Log = { debug = function() end, warn = function() end, error = function() end },
	AddonRegistry = { isModActive = function() return true end },
	Addons = { canUseAddon = function() return true end },
	InventorySync = {
		moveBetween = function(_, destination, moving)
			if remove(source, moving) then destination.items[#destination.items + 1] = moving; return true end
			return false
		end,
	},
	Deposit = {
		createSearchSnapshot = function()
			snapshotCalls = snapshotCalls + 1
			return { player = harnessPlayer }
		end,
		findItemByIdInSnapshot = function(_, wantedId, snapshot)
			assertEqual(snapshot.player, harnessPlayer, "snapshot belongs to the same player")
			for i = 1, #inventory.items do
				if inventory.items[i]:getID() == wantedId then return inventory.items[i], inventory end
			end
			return nil, nil
		end,
	},
	Transfer = { depositItem = function() deposits = deposits + 1; return true end },
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_NetworkCraftSession.lua")

assertEqual(GlobalStorageSiK.CraftSession.begin({
	player = harnessPlayer, networkId = "net_a", addonId = "Craft", knownInstalled = true,
}), true, "harness session starts")

for id = 1, 20 do
	local borrowed = item(id)
	source.items[#source.items + 1] = borrowed
	assertEqual(GlobalStorageSiK.CraftSession.claimNetworkItem(harnessPlayer, borrowed, source, "net_a", "op_a"), true,
		"borrowed item must be registered")
end
GlobalStorageSiK.CraftSession.markOperationComplete("op_a")

for i = 1, #tickHandlers do tickHandlers[i]() end
assertEqual(snapshotCalls, 1, "twenty pending returns must share one player topology snapshot")
assertEqual(deposits, 20, "all completed borrowed items must be returned")

print("craft_return_topology_regression: OK")

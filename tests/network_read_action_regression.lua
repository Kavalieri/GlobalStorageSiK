-- Regression test for network literature loans. Run from repository root:
-- lua51.exe tests/network_read_action_regression.lua

package.loaded["ISUI/ISInventoryPaneContextMenu"] = true
package.loaded["TimedActions/ISReadABook"] = true
package.loaded["TimedActions/ISTimedActionQueue"] = true
package.loaded["GS_DepositClient"] = true
package.loaded["GS_I18n"] = true
package.loaded["GS_Log"] = true
package.loaded["GS_WithdrawClient"] = true

local now = 1000
local queuedAction = nil
local withdrawCall = nil
local depositCall = nil

getTimestampMs = function() return now end
ItemTag = {
	PICTURE = "Picture",
	PICTUREBOOK = "PictureBook",
	UNINTERESTING = "Uninteresting",
}
CharacterTrait = { ILLITERATE = "Illiterate" }
SkillBook = {}

Events = {
	OnTick = {
		Add = function() end,
		Remove = function() end,
	},
}

local inventoryItems = {}
local inventory = {
	getItemWithID = function(_, itemId) return inventoryItems[itemId] end,
}
local player = {
	getPlayerNum = function() return 0 end,
	getInventory = function() return inventory end,
	hasTrait = function(self) return self.illiterate == true end,
	tooDarkToRead = function(self) return self.tooDark == true end,
	isAsleep = function() return false end,
	isLiteratureRead = function() return false end,
	getPerkLevel = function() return 0 end,
	setHaloNote = function() end,
}
getSpecificPlayer = function() return player end

local probe = {
	category = "Literature",
	writable = false,
	tags = {},
	getCategory = function(self) return self.category end,
	canBeWrite = function(self) return self.writable end,
	getModData = function() return {} end,
	hasTag = function(self, tag) return self.tags[tag] == true end,
	getSkillTrained = function() return nil end,
	getLvlSkillTrained = function() return -1 end,
	getMaxLevelTrained = function() return -1 end,
}
instanceItem = function() return probe end
getText = function(key) return key end

ISInventoryPaneContextMenu = {
	addToolTip = function() return {} end,
}
ISReadABook = {
	new = function(_, character, item)
		return {
			character = character,
			item = item,
			perform = function(self) self.didPerform = true end,
			stop = function(self) self.didStop = true end,
		}
	end,
}
ISTimedActionQueue = {
	add = function(action) queuedAction = action end,
}

GlobalStorageSiK = {
	I18n = {
		text = function(key, value)
			if key == "IGUI_GS_ReadAndReturn" then
				return tostring(value) .. " + return"
			end
			return key
		end,
	},
	Log = {
		info = function() end,
		error = function() end,
	},
	WithdrawClient = {
		sendWithdraw = function(rowData, amount, targetKey, searchQuery, opts)
			withdrawCall = {
				rowData = rowData,
				amount = amount,
				targetKey = targetKey,
				searchQuery = searchQuery,
				opts = opts,
			}
			return true
		end,
	},
	DepositClient = {
		sendDepositItems = function(itemIds, targetPlayer, opts)
			depositCall = { itemIds = itemIds, player = targetPlayer, opts = opts }
			return true
		end,
	},
}

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected=" .. tostring(expected)
			.. " actual=" .. tostring(actual), 2)
	end
end

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_NetworkReadAction.lua")

local row = { fullType = "Base.BookCarpentry1", count = 1 }
local spec = GlobalStorageSiK.NetworkReadAction.describe(row, player)
assertEqual(spec ~= nil, true, "literature must expose a context action")
assertEqual(spec.available, true, "readable literature must be available")
assertEqual(spec.label, "Read + return", "label must preserve vanilla action")

probe.writable = true
assertEqual(GlobalStorageSiK.NetworkReadAction.describe(row, player), nil,
	"writable notes must keep their separate vanilla workflow")
probe.writable = false
probe.category = "Food"
assertEqual(GlobalStorageSiK.NetworkReadAction.describe(row, player), nil,
	"non-literature must not expose the action")
probe.category = "Literature"
player.tooDark = true
assertEqual(GlobalStorageSiK.NetworkReadAction.describe(row, player).available, false,
	"vanilla darkness restriction must be preserved")
player.tooDark = false

assertEqual(GlobalStorageSiK.NetworkReadAction.request(row, player, "network-A", "book"), true,
	"loan request must be queued")
assertEqual(withdrawCall.amount, 1, "loan must withdraw one instance")
assertEqual(withdrawCall.targetKey, "player:main", "loan must use the main inventory")
assertEqual(withdrawCall.opts.networkId, "network-A", "loan must retain its source network")
assertEqual(withdrawCall.opts.returnItemIds, true, "loan must request the physical item ID")

local physicalItem = {
	getID = function() return 4242 end,
	getFullType = function() return row.fullType end,
}
inventoryItems[4242] = physicalItem
withdrawCall.opts.onComplete(true, {
	moved = 1,
	itemIds = { 4242 },
	networkId = "network-A",
})
GlobalStorageSiK.NetworkReadAction.onTick()
assertEqual(queuedAction ~= nil, true, "vanilla read action must wait for the physical item")
assertEqual(queuedAction.item, physicalItem, "vanilla action must receive the withdrawn instance")

queuedAction:perform()
GlobalStorageSiK.NetworkReadAction.onTick()
assertEqual(depositCall ~= nil, true, "completion must queue the return")
assertEqual(depositCall.itemIds[1], 4242, "return must target the exact borrowed item")
assertEqual(depositCall.opts.networkId, "network-A", "return must target the original network")
assertEqual(depositCall.opts.origin, "network_read_return", "return must be distinguishable from manual deposits")
assertEqual(string.sub(depositCall.opts.operationId, 1, 5), "Read-", "loan must keep one operation ID")

withdrawCall = nil
depositCall = nil
queuedAction = nil
local cancelledItem = {
	getID = function() return 4343 end,
	getFullType = function() return row.fullType end,
}
inventoryItems[4343] = cancelledItem
assertEqual(GlobalStorageSiK.NetworkReadAction.request(row, player, "network-B", nil), true,
	"second loan must be queued")
withdrawCall.opts.onComplete(true, { moved = 1, itemIds = { 4343 }, networkId = "network-B" })
GlobalStorageSiK.NetworkReadAction.onTick()
queuedAction:stop()
GlobalStorageSiK.NetworkReadAction.onTick()
assertEqual(depositCall.itemIds[1], 4343, "cancellation must return the exact borrowed item")
assertEqual(depositCall.opts.networkId, "network-B", "cancellation must retain the source network")

print("network_read_action_regression: ok")

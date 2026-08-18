-- Regression test for shared modal ingredient sources and atomic replacement.
-- Run from repository root: lua51.exe tests/craft_requirements_regression.lua

package.loaded["GS_Sandbox"] = true
package.loaded["GS_Log"] = true
package.loaded["GS_DepositSources"] = true
package.loaded["GS_InventorySync"] = true
package.loaded["GS_Config"] = true
package.loaded["GS_CraftUtils"] = true

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected=" .. tostring(expected)
			.. " actual=" .. tostring(actual), 2)
	end
end

local function javaList(values)
	return {
		size = function() return #values end,
		get = function(_, index) return values[index + 1] end,
	}
end

local function makeContainer(name)
	local container = { name = name, items = {} }
	function container:getItemCountRecurse(fullType)
		local count = 0
		for i = 1, #self.items do
			if self.items[i]:getFullType() == fullType then count = count + 1 end
		end
		return count
	end
	function container:FindAndReturn(fullType)
		for i = 1, #self.items do
			if self.items[i]:getFullType() == fullType then return self.items[i] end
		end
		return nil
	end
	function container:getFirstTypeRecurse(fullType)
		return self:FindAndReturn(fullType)
	end
	function container:getAllEvalRecurse()
		return javaList(self.items)
	end
	function container:contains(item)
		for i = 1, #self.items do
			if self.items[i] == item then return true end
		end
		return false
	end
	function container:add(item)
		self.items[#self.items + 1] = item
		item.container = self
	end
	function container:remove(item)
		for i = 1, #self.items do
			if self.items[i] == item then
				table.remove(self.items, i)
				item.container = nil
				return true
			end
		end
		return false
	end
	return container
end

local function makeItem(fullType)
	return {
		fullType = fullType,
		getFullType = function(self) return self.fullType end,
		getContainer = function(self) return self.container end,
	}
end

local main = makeContainer("main")
local bag = makeContainer("bag")
local nearby = makeContainer("nearby")
local outputItems = {}
local player = {
	getInventory = function() return main end,
}

local soldering = makeItem("GlobalStorageSiK.GS_SolderingIron")
local casing = makeItem("GlobalStorageSiK.GS_ReaderCasing")
local circuit = makeItem("GlobalStorageSiK.GS_ReaderCircuit")
local antenna = makeItem("GlobalStorageSiK.GS_ReaderAntenna")
local screwdriver = makeItem("Base.Screwdriver")
main:add(soldering)
bag:add(casing)
nearby:add(circuit)
nearby:add(antenna)
nearby:add(screwdriver)

local playerScans = 0
local nearbyScans = 0
GlobalStorageSiK = {
	Sandbox = {
		requireRecipeBooks = function() return true end,
	},
	Log = {},
	DepositSources = {
		collectPlayerContainers = function()
			playerScans = playerScans + 1
			return { main, bag }
		end,
		collectNearbyContainers = function()
			nearbyScans = nearbyScans + 1
			-- Repetir main demuestra que el snapshot deduplica referencias.
			return { nearby, main }
		end,
	},
	InventorySync = {
		beginBatch = function() end,
		endBatch = function() end,
		removeItem = function(container, item) return container:remove(item) end,
		addToContainer = function(container, item) container:add(item); return true end,
		addToPlayer = function(_, item)
			outputItems[#outputItems + 1] = item
			main:add(item)
			return true
		end,
	},
}

ItemTag = { get = function(value) return value end }
ResourceLocation = { of = function(value) return value end }
getScriptManager = function()
	return {
		getItemsTag = function()
			return javaList({
				{ getFullName = function() return "Base.Screwdriver" end },
			})
		end,
	}
end
instanceItem = function(fullType) return makeItem(fullType) end

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_CraftUtils.lua")
GlobalStorageSiK.CraftUtils.knowsRecipe = function() return true end
GlobalStorageSiK.CraftUtils.getElectricityLevel = function() return 3 end
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_ReaderAcquire.lua")

local containers = GlobalStorageSiK.CraftUtils.collectIngredientContainers(player)
assertEqual(#containers, 3, "ingredient sources must deduplicate player and nearby containers")
assertEqual(GlobalStorageSiK.CraftUtils.hasItemType(player,
	"GlobalStorageSiK.GS_ReaderCircuit", containers), true,
	"nearby physical containers must be visible to the shared requirement source")

playerScans = 0
nearbyScans = 0
local ok, reason = GlobalStorageSiK.ReaderAcquire.craft(player)
assertEqual(ok, true, "reader must craft from mixed player/bag/nearby sources")
assertEqual(reason, nil, "successful reader craft must not return a reason")
assertEqual(playerScans, 1, "reader craft must collect player sources once")
assertEqual(nearbyScans, 1, "reader craft must collect nearby sources once")
assertEqual(#outputItems, 1, "reader craft must create exactly one output")
assertEqual(outputItems[1]:getFullType(), "GlobalStorageSiK.GS_TerminalReader",
	"reader output type must remain stable")
assertEqual(main:contains(soldering), true, "reusable soldering iron must not be consumed")
assertEqual(nearby:contains(screwdriver), true, "reusable screwdriver must not be consumed")
assertEqual(bag:contains(casing), false, "casing must be consumed from its real source")
assertEqual(nearby:contains(circuit), false, "circuit must be consumed from its real source")
assertEqual(nearby:contains(antenna), false, "antenna must be consumed from its real source")

local rollbackSource = makeContainer("rollback")
local rollbackItem = makeItem("Base.TestInput")
rollbackSource:add(rollbackItem)
local originalAddToPlayer = GlobalStorageSiK.InventorySync.addToPlayer
GlobalStorageSiK.InventorySync.addToPlayer = function() return false end
local rollbackOk = GlobalStorageSiK.CraftUtils.replaceItemsWithOutput(player,
	{ rollbackItem }, "Base.TestOutput")
assertEqual(rollbackOk, false, "failed output delivery must fail the transaction")
assertEqual(rollbackSource:contains(rollbackItem), true,
	"failed output delivery must restore the original input")
GlobalStorageSiK.InventorySync.addToPlayer = originalAddToPlayer

local recipeFile = assert(io.open(
	"GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/scripts/globalstoragesik_recipes.txt", "r"))
local recipes = recipeFile:read("*a")
recipeFile:close()
assertEqual(recipes:find("craftRecipe Build GS Terminal Reader", 1, true) ~= nil, true,
	"reader recipe must still exist")
assertEqual(recipes:find("SkillRequired = Electricity:3", recipes:find("craftRecipe Build GS Terminal Reader", 1, true), true) ~= nil, true,
	"reader assembly must use the new early-game skill requirement")

print("craft_requirements_regression: OK")

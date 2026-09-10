-- Contextual identity only. Vanilla owns suitability, consumption and output.
local Target = {}
local bindings = setmetatable({}, { __mode = "k" })

local function find(player, itemId)
	local inventory = player and player:getInventory()
	if not inventory then return nil end
	-- getItemWithID only searches the top-level inventory in B42. The vanilla
	-- recursive lookup preserves an explicit target inside the player's bags.
	if inventory.getItemById then return inventory:getItemById(itemId) end
	return inventory.getItemWithID and inventory:getItemWithID(itemId) or nil
end

local function activeInventory(player)
	local inventory = player and player:getInventory()
	if not inventory or not getPlayerInventory then return inventory end
	local page = getPlayerInventory(player:getPlayerNum())
	local selected = page and page.inventoryPane and page.inventoryPane.inventory
	if selected == inventory then return inventory end
	local bag = selected and selected.getContainingItem and selected:getContainingItem()
	if bag and bag.getID and find(player, bag:getID()) == bag then return selected end
	return nil
end

function Target.select(player, requestedId)
	if requestedId ~= nil then
		local item = find(player, requestedId)
		return item and item:getFullType() == "Base.BlowTorch" and requestedId or nil
	end
	-- An aggregate warehouse row has no physical itemId. The target still comes
	-- from the player's active inventory; choose a stable representative, never
	-- a row ID or an item in another player's/world container.
	local inventory = activeInventory(player)
	local items = inventory and inventory:getItems()
	local selected = nil
	for index = 0, items and items:size() - 1 or -1 do
		local item = items:get(index)
		if item:getFullType() == "Base.BlowTorch" and item:getCurrentUsesFloat() < 1 then
			local id = item:getID()
			if selected == nil or id < selected then selected = id end
		end
	end
	return selected
end

function Target.bind(player, logic, itemId)
	if not logic or not itemId then return false end
	local target = { itemId = itemId, playerNum = player:getPlayerNum() }
	if not Target.apply(player, logic, target) then return false end
	bindings[logic] = target
	return true
end

function Target.take(logic)
	local target = bindings[logic]
	bindings[logic] = nil
	return target
end

function Target.clear()
	bindings = setmetatable({}, { __mode = "k" })
end

function Target.apply(player, logic, target)
	if not target then return true end
	if not player or player:getPlayerNum() ~= target.playerNum or not logic then return false end
	local recipe = logic:getRecipe()
	if not recipe or recipe:getName() ~= "RefillBlowTorch" then return false end
	local item = find(player, target.itemId)
	if not item or item:getFullType() ~= "Base.BlowTorch" or not logic.setRecipeFromContextClick then return false end
	logic:setRecipeFromContextClick(recipe, item)
	local data = logic:getRecipeData()
	if target.tankId then
		local tank = find(player, target.tankId)
		if not tank or tank:getFullType() ~= "Base.PropaneTank" then return false end
		data:offerAndReplaceInputItem(tank)
	end
	local items, found = data:getAllInputItems(), false
	for index = 0, items:size() - 1 do
		local input = items:get(index)
		if input:getFullType() == "Base.BlowTorch" then
			if input:getID() ~= target.itemId then return false end
			found = true
		elseif input:getFullType() == "Base.PropaneTank" and target.tankId
			and input:getID() ~= target.tankId then return false end
	end
	return found and logic:canPerformCurrentRecipe() == true
end

function Target.captureTank(target, items)
	if not target then return end
	for index = 0, items:size() - 1 do
		local item = items:get(index)
		if item:getFullType() == "Base.PropaneTank" then target.tankId = item:getID(); return end
	end
end

return Target

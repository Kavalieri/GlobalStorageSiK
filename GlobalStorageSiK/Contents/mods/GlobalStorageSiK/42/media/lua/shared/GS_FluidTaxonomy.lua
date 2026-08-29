-- Clasificación dinámica de contenedores de fluido B42.
-- La forma vacía se conserva como Contenedores > Líquidos; un fluido real
-- decide la ruta efectiva de esa instancia sin persistir texto localizado.

GlobalStorageSiK.FluidTaxonomy = GlobalStorageSiK.FluidTaxonomy or {}
local FluidTaxonomy = GlobalStorageSiK.FluidTaxonomy

local function safeCall(fn)
	local ok, value = pcall(fn)
	if ok then return value end
	return nil
end

local function fluidContainer(item)
	if not item or not item.getFluidContainer then return nil end
	return safeCall(function() return item:getFluidContainer() end)
end

local function hasCategory(fluid, category)
	return fluid and category and fluid.isCategory
		and safeCall(function() return fluid:isCategory(category) end) == true
end

function FluidTaxonomy.stateKey(item)
	local fluid = fluidContainer(item)
	if not fluid or not fluid.isEmpty then return nil end
	local empty = safeCall(function() return fluid:isEmpty() end)
	if empty == true then return "empty" end
	if empty ~= false then return "unknown" end
	if fluid.isMixture and safeCall(function() return fluid:isMixture() end) == true then
		return "mixture"
	end
	local primary = fluid.getPrimaryFluid and safeCall(function() return fluid:getPrimaryFluid() end) or nil
	local fluidType = primary and primary.getFluidTypeString
		and safeCall(function() return primary:getFluidTypeString() end) or nil
	return fluidType and ("fluid:" .. tostring(fluidType)) or "other_fluid"
end

function FluidTaxonomy.fillPercent(item)
	local fluid = fluidContainer(item)
	if not fluid or not fluid.getAmount or not fluid.getCapacity then return nil end
	local amount = safeCall(function() return fluid:getAmount() end)
	local capacity = safeCall(function() return fluid:getCapacity() end)
	if type(amount) ~= "number" or type(capacity) ~= "number" or capacity <= 0 then return nil end
	return math.max(0, math.min(100, math.floor((amount / capacity) * 100 + 0.5)))
end

---@param item InventoryItem|nil
---@return table|nil nativePath
---@return string|nil signature
function FluidTaxonomy.resolve(item)
	local fluid = fluidContainer(item)
	if not fluid or not fluid.isEmpty then return nil, nil end
	local empty = safeCall(function() return fluid:isEmpty() end)
	if empty == true then
		return { l1 = "containers", l2 = "liquid", l3 = "empty" }, "empty"
	end
	if empty ~= false then return nil, "unknown" end
	local amount = fluid.getAmount and safeCall(function() return fluid:getAmount() end) or nil
	local primary = fluid.getPrimaryFluid and safeCall(function() return fluid:getPrimaryFluid() end) or nil
	local fluidType = primary and primary.getFluidTypeString and safeCall(function() return primary:getFluidTypeString() end) or nil
	local signature = "fluid=" .. tostring(fluidType) .. " amount=" .. tostring(amount)
	if fluid.isMixture and safeCall(function() return fluid:isMixture() end) == true then
		return { l1 = "containers", l2 = "liquid", l3 = "mixture" }, signature
	end
	if not primary then
		return { l1 = "containers", l2 = "liquid", l3 = "other_fluid" }, signature
	end
	if FluidCategory and hasCategory(fluid, FluidCategory.Fuel) then
		return { l1 = "vehicles", l2 = "consumable", l3 = "fuel" }, signature
	end
	if FluidCategory and hasCategory(fluid, FluidCategory.Water) then
		return { l1 = "food_drink", l2 = "non_perishable", l3 = "water" }, signature
	end
	if FluidCategory and hasCategory(fluid, FluidCategory.Beverage) then
		return { l1 = "food_drink", l2 = "non_perishable", l3 = "beverage" }, signature
	end
	return { l1 = "containers", l2 = "liquid", l3 = "other_fluid" }, signature
end

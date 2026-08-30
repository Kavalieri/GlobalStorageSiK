-- DEV32.4: un mismo envase conserva forma vacío y adopta ruta por contenido.
local function assertPath(path, l1, l2, l3, note)
	if not path or path.l1 ~= l1 or path.l2 ~= l2 or path.l3 ~= l3 then
		error((note or "path") .. " expected=" .. l1 .. "/" .. l2 .. "/" .. tostring(l3), 2)
	end
end

FluidCategory = { Fuel = "fuel", Beverage = "beverage", Water = "water" }
GlobalStorageSiK = {}
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_FluidTaxonomy.lua")

local function item(amount, capacity, category, fluidType)
	local fluid = {
		isEmpty = function() return amount <= 0 end,
		isCategory = function(_, value) return value == category end,
		getAmount = function() return amount end,
		getCapacity = function() return capacity end,
		getPrimaryFluid = function()
			return amount <= 0 and nil or { getFluidTypeString = function() return fluidType end }
		end,
		isMixture = function() return false end,
	}
	return { getFluidContainer = function() return fluid end }
end

local path, signature = GlobalStorageSiK.FluidTaxonomy.resolve(item(0, 10, nil, nil))
assertPath(path, "containers", "liquid", "empty", "empty")
path, signature = GlobalStorageSiK.FluidTaxonomy.resolve(item(0.1, 10, nil, "Petrol"))
assertPath(path, "vehicles", "consumable", "fuel", "fuel")
assert(signature and signature:find("fluid:petrol;", 1, true) == 1,
	"real fluidType classifies without FluidCategory")
local _, sameSignature = GlobalStorageSiK.FluidTaxonomy.resolve(item(19, 20, FluidCategory.Fuel, "Petrol"))
assert(sameSignature == signature, "amount and capacity do not alter aggregate identity")
path = GlobalStorageSiK.FluidTaxonomy.resolve(item(0.01, 8, nil, "Water"))
assertPath(path, "food_drink", "non_perishable", "water", "water")
print("fluid_taxonomy_regression: OK")

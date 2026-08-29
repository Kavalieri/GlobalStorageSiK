-- DEV32.4: un mismo envase conserva forma vacío y adopta ruta por contenido.
local function assertPath(path, l1, l2, l3, note)
	if not path or path.l1 ~= l1 or path.l2 ~= l2 or path.l3 ~= l3 then
		error((note or "path") .. " expected=" .. l1 .. "/" .. l2 .. "/" .. tostring(l3), 2)
	end
end

FluidCategory = { Fuel = "fuel", Beverage = "beverage", Water = "water" }
GlobalStorageSiK = {}
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_FluidTaxonomy.lua")

local function item(empty, category, fluidType)
	local fluid = {
		isEmpty = function() return empty end,
		isCategory = function(_, value) return value == category end,
		getAmount = function() return empty and 0 or 1 end,
		getPrimaryFluid = function()
			return empty and nil or { getFluidTypeString = function() return fluidType end }
		end,
		isMixture = function() return false end,
	}
	return { getFluidContainer = function() return fluid end }
end

local path = GlobalStorageSiK.FluidTaxonomy.resolve(item(true, nil, nil))
assertPath(path, "containers", "liquid", "empty", "empty")
path = GlobalStorageSiK.FluidTaxonomy.resolve(item(false, FluidCategory.Fuel, "Gasoline"))
assertPath(path, "vehicles", "consumable", "fuel", "fuel")
path = GlobalStorageSiK.FluidTaxonomy.resolve(item(false, FluidCategory.Water, "Water"))
assertPath(path, "food_drink", "non_perishable", "water", "water")
print("fluid_taxonomy_regression: OK")

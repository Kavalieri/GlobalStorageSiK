-- Author regression for fluid form, content, namespace and hazard identity.
-- Pure Lua 5.1: no Project Zomboid runtime is opened.

for _, name in ipairs({ "GS_Router", "GS_I18n", "GS_NativeProduct", "GS_CategoryResolution" }) do
	package.loaded[name] = true
end
package.loaded["GS_FluidTaxonomy"] = nil
package.loaded["GS_ItemSnapshot"] = nil

FluidCategory = { Fuel = "fuel", Beverage = "beverage", Water = "water" }
local fluidDefs = {}
for _, id in ipairs({ "Base:Water", "Base:Petrol", "Base:Juice", "Base:Bleach", "ModA:Coolant", "ModB:Coolant" }) do
	fluidDefs[#fluidDefs + 1] = { id = id, getFluidTypeString = function(self) return self.id end }
end
local fluidList = {
	size = function() return #fluidDefs end,
	get = function(_, index) return fluidDefs[index + 1] end,
}
Fluid = { getAllFluids = function() return fluidList end }
GlobalStorageSiK = {
	Router = {
		getItemCategory = function() return "Container" end,
		getItemSubCategory = function() return nil end,
	},
	I18n = {
		nameFromItemInstance = function(item) return item:getDisplayName() end,
		isLowQualityDisplayName = function() return false end,
		typeDisplayName = function(fullType) return fullType end,
	},
	NativeProduct = {
		tracePathSample = function() end,
		encodePath = function(path)
			return path and ("native:" .. path.l1 .. "/" .. path.l2 .. "/" .. path.l3) or nil
		end,
	},
	isAuthoritative = function() return true end,
}

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(shared .. "GS_FluidTaxonomy.lua")
package.loaded["GS_FluidTaxonomy"] = true
GlobalStorageSiK.CategoryResolution = {
	resolve = function(fullType, row, item)
		local path = GlobalStorageSiK.FluidTaxonomy.resolve(item)
		local encoded = GlobalStorageSiK.NativeProduct.encodePath(path)
		return {
			nativePath = encoded,
			nativeStatus = encoded and "classified" or "unclassified",
			vanillaKey = "Container",
			effective = encoded and "native" or "vanilla",
			routingIdentity = encoded or "vanilla:Container",
			categorySource = "VANILLA",
		}
	end,
}
dofile(shared .. "GS_ItemSnapshot.lua")

local nextId = 0
local function fluidItem(fullType, opts)
	opts = opts or {}
	nextId = nextId + 1
	local fluid = {
		isEmpty = function() return (opts.amount or 0) <= 0 end,
		isMixture = function() return opts.mixture == true end,
		isTainted = function() return opts.tainted == true end,
		isPoisonous = function() return opts.poisonous == true end,
		getPoisonRatio = function() return opts.poisonRatio end,
		getAmount = function() return opts.amount or 0 end,
		getCapacity = function() return opts.capacity or 1 end,
		getContainerName = function() return opts.containerName or "" end,
		getPrimaryFluidAmount = function() return opts.primaryAmount or opts.amount or 0 end,
		getSpecificFluidAmount = function(_, fluidDef)
			return opts.components and (opts.components[fluidDef.id] or 0) or 0
		end,
		isCategory = function(_, category) return category == opts.category end,
		getPrimaryFluid = function()
			if (opts.amount or 0) <= 0 or not opts.fluidId then return nil end
			return { getFluidTypeString = function() return opts.fluidId end }
		end,
	}
	local value = { id = nextId }
	function value:getFullType() return fullType end
	function value:getID() return self.id end
	function value:getDisplayName() return opts.name or fullType end
	function value:getName() return self:getDisplayName() end
	function value:getWorldSprite() return nil end
	function value:getRecordedMediaIndex() return -1 end
	function value:getFluidContainer() return fluid end
	function value:getActualWeight() return 1 end
	return value
end

local function rowsFor(items)
	local snapshot = {}
	for i = 1, #items do
		assert(GlobalStorageSiK.ItemSnapshot.addItem(snapshot, items[i]), "fluid add " .. tostring(i))
	end
	return snapshot
end

local function rowCount(snapshot)
	local count = 0
	for _ in pairs(snapshot) do count = count + 1 end
	return count
end

local function onlyRow(snapshot)
	local result = nil
	for _, row in pairs(snapshot) do
		assert(result == nil, "expected one row")
		result = row
	end
	return result
end

local modA = fluidItem("Base.Bottle", { amount = 1, capacity = 1, fluidId = "ModA:Coolant" })
local modB = fluidItem("Base.Bottle", { amount = 1, capacity = 1, fluidId = "ModB:Coolant" })
assert(GlobalStorageSiK.FluidTaxonomy.canonicalType(modA) == "moda:coolant", "namespace A was discarded")
assert(GlobalStorageSiK.FluidTaxonomy.canonicalType(modB) == "modb:coolant", "namespace B was discarded")
assert(GlobalStorageSiK.FluidTaxonomy.stateKey(modA) ~= GlobalStorageSiK.FluidTaxonomy.stateKey(modB),
	"different fluid namespaces collided")
assert(rowCount(rowsFor({ modA, modB })) == 2, "namespaced fluids collapsed in snapshot")

local clean = fluidItem("Base.Bottle", { amount = 1, fluidId = "Base:Water" })
local mixed = fluidItem("Base.Bottle", {
	amount = 1, fluidId = "Base:Water", mixture = true, primaryAmount = 0.75,
	components = { ["Base:Water"] = 0.75, ["Base:Juice"] = 0.25 },
})
local tainted = fluidItem("Base.Bottle", { amount = 1, fluidId = "Base:Water", tainted = true })
local poison = fluidItem("Base.Bottle", {
	amount = 1, fluidId = "Base:Water", poisonous = true, poisonRatio = 0.25,
})
local hazardKeys = {}
for _, item in ipairs({ clean, mixed, tainted, poison }) do
	local key = GlobalStorageSiK.FluidTaxonomy.stateKey(item)
	assert(not hazardKeys[key], "mixture/tainted/poison fluid identity collided: " .. tostring(key))
	hazardKeys[key] = true
end
assert(rowCount(rowsFor({ clean, mixed, tainted, poison })) == 4,
	"mixture or hazardous contents collapsed")
local otherMixed = fluidItem("Base.Bottle", {
	amount = 1, fluidId = "Base:Water", mixture = true, primaryAmount = 0.75,
	components = { ["Base:Water"] = 0.75, ["Base:Bleach"] = 0.25 },
})
assert(GlobalStorageSiK.FluidTaxonomy.stateKey(mixed)
	~= GlobalStorageSiK.FluidTaxonomy.stateKey(otherMixed),
	"mixtures with equal primary ratio but different secondary fluid collided")
assert(GlobalStorageSiK.FluidTaxonomy.detail(mixed).compositionExact == true,
	"complete mixture composition was not published")

local shapes = rowsFor({
	fluidItem("Base.Bag_HydrationBackpack", { amount = 1, capacity = 2, containerName = "HydrationPack", fluidId = "Base:Water" }),
	fluidItem("Base.WaterBottle", { amount = 1, capacity = 1, containerName = "BottlePlastic", fluidId = "Base:Water" }),
	fluidItem("Base.PetrolCan", { amount = 1, capacity = 10, containerName = "GasCan", fluidId = "Base:Water" }),
})
assert(rowCount(shapes) == 3, "different container forms collapsed by equal content/amount")

local petrol25 = fluidItem("Base.PetrolCan", {
	amount = 2.5, capacity = 10, fluidId = "Base:Petrol", category = FluidCategory.Fuel,
})
local petrol75 = fluidItem("Base.PetrolCan", {
	amount = 7.5, capacity = 10, fluidId = "Base:Petrol", category = FluidCategory.Fuel,
})
local petrolFilled = onlyRow(rowsFor({ petrol25, petrol75 }))
assert(petrolFilled and petrolFilled.count == 2, "petrol 25/75 percent did not group by content")
assert(petrolFilled.nativePath == "native:vehicles/consumable/fuel", "filled petrol path")
assert(petrolFilled.unitDetails[petrol25.id].dynamicPercent == 25
	and petrolFilled.unitDetails[petrol75.id].dynamicPercent == 75,
	"petrol per-item percentage was lost")
assert(petrolFilled.unitDetails[petrol25.id].fluidState.amount == 2.5
	and petrolFilled.unitDetails[petrol75.id].fluidState.capacity == 10,
	"petrol per-item amount/capacity was lost")

local petrolAll = rowsFor({ petrol25, petrol75,
	fluidItem("Base.PetrolCan", { amount = 0, capacity = 10 }) })
assert(rowCount(petrolAll) == 2, "empty petrol can collapsed with fuel")
local emptyPetrol = nil
for _, row in pairs(petrolAll) do
	if row.dynamicStateKey == "empty" then emptyPetrol = row end
end
assert(emptyPetrol and emptyPetrol.nativePath == "native:containers/liquid/empty",
	"empty petrol can retained fuel taxonomy")

local waterFull = fluidItem("Base.WaterBottle", {
	amount = 1, capacity = 1, fluidId = "Base:Water", category = FluidCategory.Water,
})
local waterPartial = fluidItem("Base.WaterBottle", {
	amount = 0.25, capacity = 1, fluidId = "Base:Water", category = FluidCategory.Water,
})
local waterEmpty = fluidItem("Base.WaterBottle", { amount = 0, capacity = 1 })
local waterRows = rowsFor({ waterFull, waterPartial, waterEmpty })
assert(rowCount(waterRows) == 2, "water bottle full/partial/empty grouping")
local waterFilled = nil
for _, row in pairs(waterRows) do
	if row.dynamicStateKey ~= "empty" then waterFilled = row end
end
assert(waterFilled and waterFilled.count == 2
	and waterFilled.unitDetails[waterFull.id].dynamicPercent == 100
	and waterFilled.unitDetails[waterPartial.id].dynamicPercent == 25,
	"water bottle exact unit state was lost")

local can10 = fluidItem("Base.PetrolCan", {
	amount = 5, capacity = 10, containerName = "GasCan", fluidId = "Base:Petrol", category = FluidCategory.Fuel,
})
local can20 = fluidItem("Base.JerryCan", {
	amount = 10, capacity = 20, containerName = "Jerrycan", fluidId = "Base:Petrol", category = FluidCategory.Fuel,
})
local capacityFamily = rowsFor({ can10, can20 })
assert(rowCount(capacityFamily) == 2, "10L/20L exact shapes collapsed")
local familyCount = 0
for _, row in pairs(capacityFamily) do
	assert(row.productFamilyKey == "fuel_can", "10L/20L petrol cans left their common product family")
	assert(row.unitDetails[row.itemIds[1]].fluidState.capacity == (row.fullType == "Base.PetrolCan" and 10 or 20),
		"10L/20L exact capacity was lost")
	familyCount = familyCount + 1
end
assert(familyCount == 2, "10L/20L family fixture incomplete")

print("fluid_dynamic_identity_regression: OK")

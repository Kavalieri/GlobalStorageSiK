-- Binding six-state fluid contract: B42 FluidContainer and legacy Drainable.
-- Mocks expose only stable engine-facing methods; no UI or PZ world is opened.

GlobalStorageSiK = { FluidTaxonomy = {} }
FluidCategory = { Fuel = "fuel", Water = "water", Beverage = "beverage" }
ItemTag = { PETROL = "PETROL" }

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(shared .. "GS_FluidTaxonomy.lua")

local function petrolFluid(amount, capacity)
	return {
		getAmount = function() return amount end,
		getCapacity = function() return capacity end,
		isEmpty = function() return amount <= 0 end,
		isMixture = function() return false end,
		isTainted = function() return false end,
		isPoisonous = function() return false end,
		getContainerName = function() return "GasCan" end,
		getPrimaryFluidAmount = function() return amount end,
		getPrimaryFluid = function()
			if amount <= 0 then return nil end
			return { getFluidTypeString = function() return "Base:Petrol" end }
		end,
		isCategory = function(_, category) return category == FluidCategory.Fuel end,
	}
end

local function b42(amount)
	local value = {}
	function value:getFullType() return "Base.PetrolCan" end
	function value:getFluidContainer() return petrolFluid(amount, 10) end
	return value
end

-- DrainableComboItem-compatible legacy surface. The adapter owns any known
-- fullType capacity mapping; the harness does not invent a Java fluid API.
local function legacy(usedDelta, petrolTagged)
	if petrolTagged == nil then petrolTagged = true end
	local value = {}
	function value:getFullType() return "Base.JerryCan" end
	function value:getUsedDelta() return usedDelta end
	function value:getUseDelta() return 0.05 end
	function value:getDrainableUsesInt() return math.floor(usedDelta / 0.05 + 0.5) end
	function value:isDrainable() return true end
	function value:getReplaceOnDeplete() return "Base.EmptyJerryCan" end
	function value:hasTag(tag) return petrolTagged and tag == ItemTag.PETROL end
	return value
end

local cases = {
	{ name = "b42-empty", item = b42(0), empty = true, percent = 0 },
	{ name = "b42-partial", item = b42(5), empty = false, percent = 50 },
	{ name = "b42-full", item = b42(10), empty = false, percent = 100 },
	{ name = "legacy-empty", item = legacy(0), empty = true, percent = 0 },
	{ name = "legacy-partial", item = legacy(0.5), empty = false, percent = 50 },
	{ name = "legacy-full", item = legacy(1), empty = false, percent = 100 },
}

for i = 1, #cases do
	local case = cases[i]
	local info = GlobalStorageSiK.FluidTaxonomy.inspect(case.item)
	assert(info, case.name .. " produced no normalized descriptor")
	assert(type(info.amount) == "number" and type(info.capacity) == "number"
		and info.capacity > 0, case.name .. " lost amount/capacity")
	assert(info.fillPercent == case.percent, case.name .. " wrong percentage")
	assert(info.detail and info.detail.amount == info.amount
		and info.detail.capacity == info.capacity, case.name .. " detail diverges")
	if case.empty then
		assert(info.contentStateKey == "empty", case.name .. " wrong empty content state")
		assert(type(info.stateKey) == "string" and info.stateKey:find("empty", 1, true),
			case.name .. " lost shape-qualified empty identity")
		assert(info.path and info.path.l1 == "containers" and info.path.l2 == "liquid"
			and info.path.l3 == "empty", case.name .. " retained fuel path")
	else
		assert(info.canonicalType and info.canonicalType:find("petrol", 1, true),
			case.name .. " lost canonical fuel type")
		assert(info.path and info.path.l1 == "vehicles" and info.path.l2 == "consumable"
			and info.path.l3 == "fuel", case.name .. " did not route by content")
	end
end

local fallbackItem = {
	getFullType = function() return "Base.PetrolCan" end,
	getFluidContainerFromSelfOrWorldItem = function() return petrolFluid(5, 10) end,
}
local fallbackInfo = GlobalStorageSiK.FluidTaxonomy.inspect(fallbackItem)
assert(fallbackInfo and fallbackInfo.fillPercent == 50,
	"B42 self/world FluidContainer fallback was not inspected")

local untagged = GlobalStorageSiK.FluidTaxonomy.inspect(legacy(0.5, false))
assert(not untagged or (not tostring(untagged.canonicalType or ""):find("petrol", 1, true)
	and not (untagged.path and untagged.path.l3 == "fuel")),
	"untagged JerryCan was guessed as petrol from its fullType/replacement")

assert(GlobalStorageSiK.FluidTaxonomy.inspect(cases[2].item).stateKey
	== GlobalStorageSiK.FluidTaxonomy.inspect(cases[3].item).stateKey,
	"B42 amount incorrectly changed fungible content identity")
assert(GlobalStorageSiK.FluidTaxonomy.inspect(cases[5].item).stateKey
	== GlobalStorageSiK.FluidTaxonomy.inspect(cases[6].item).stateKey,
	"legacy amount incorrectly changed fungible content identity")

print("fluid_b42_legacy_six_state_contract: OK")

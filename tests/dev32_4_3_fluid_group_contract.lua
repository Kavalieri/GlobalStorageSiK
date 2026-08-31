-- Core 1.4.3-dev32.4.3: fluid content identity and exact mixed children.
package.loaded["GS_Router"] = true
package.loaded["GS_I18n"] = true
package.loaded["GS_Network"] = true
package.loaded["GS_Zones"] = true
package.loaded["GS_ZoneRefresh"] = true
package.loaded["GS_NativeProduct"] = true
package.loaded["GS_CategoryResolution"] = true
package.loaded["GS_Permissions"] = true
package.loaded["GS_ItemSnapshot"] = nil

FluidCategory = { Fuel = "fuel", Beverage = "beverage", Water = "water" }
GlobalStorageSiK = {
	Router = { getItemCategory = function() return "Misc" end,
		getItemSubCategory = function() return nil end },
	I18n = {
		nameFromItemInstance = function(item) return item:getDisplayName() end,
		isLowQualityDisplayName = function() return false end,
		typeDisplayName = function(fullType) return fullType end,
		getScriptItem = function() return nil end,
	},
	NativeProduct = {
		tracePathSample = function() end,
		encodePath = function(path)
			return "native:" .. path.l1 .. "/" .. path.l2 .. "/" .. path.l3
		end,
	},
	CategoryResolution = {
		resolve = function(fullType, row, item, dynamicPath)
			local path = dynamicPath or (item and GlobalStorageSiK.FluidTaxonomy.resolve(item) or nil)
			local encoded = row and row.nativePath
				or (path and GlobalStorageSiK.NativeProduct.encodePath(path))
			return { nativePath = encoded, nativeStatus = "classified", vanillaKey = "Container",
				effective = "native", routingIdentity = encoded, categorySource = "VANILLA" }
		end,
	},
	isAuthoritative = function() return true end,
}

local ROOT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(ROOT .. "GS_FluidTaxonomy.lua")
package.loaded["GS_FluidTaxonomy"] = true
dofile(ROOT .. "GS_ItemSnapshot.lua")
package.loaded["GS_ItemSnapshot"] = true

local function fluidItem(id, amount, capacity, fluidType, opts)
	opts = opts or {}
	return {
		getFullType = function() return "Base.PetrolCan" end,
		getID = function() return id end,
		getDisplayName = function() return "Gas Can" end,
		getName = function() return "Gas Can" end,
		getWorldSprite = function() return nil end,
		getRecordedMediaIndex = function() return -1 end,
		getFluidContainer = function()
			return {
				isEmpty = function() return opts.flagEmpty == true end,
				isMixture = function() return opts.mixture == true end,
				isCategory = function(_, category) return category == opts.category end,
				getAmount = function() return amount end,
				getCapacity = function() return capacity end,
				getPrimaryFluid = function()
					if amount <= 0 then return nil end
					return { getFluidTypeString = function() return fluidType end }
				end,
			}
		end,
	}
end

local low = fluidItem(101, 0.01, 8, "Base:Petrol", { flagEmpty = true })
local high = fluidItem(102, 19, 20, "Base:Petrol", { category = FluidCategory.Water })
local empty = fluidItem(103, 0, 50, nil, { category = FluidCategory.Fuel })

local lowPath, lowSignature = GlobalStorageSiK.FluidTaxonomy.resolve(low)
local highPath, highSignature = GlobalStorageSiK.FluidTaxonomy.resolve(high)
local emptyPath, emptySignature = GlobalStorageSiK.FluidTaxonomy.resolve(empty)
assert(lowPath.l1 == "vehicles" and lowPath.l3 == "fuel",
	"positive real amount must beat an empty flag and missing FluidCategory")
assert(highPath.l1 == "vehicles" and highPath.l3 == "fuel",
	"real fluidType must beat a contradictory Java category")
assert(lowSignature == highSignature and lowSignature:find("fluid:base:petrol;", 1, true) == 1,
	"litres and capacity must not change aggregate identity")
assert(emptyPath.l1 == "containers" and emptyPath.l2 == "liquid"
	and emptyPath.l3 == "empty" and emptySignature == "empty",
	"empty must retain a distinct liquid-container identity")

local snapshot = {}
assert(GlobalStorageSiK.ItemSnapshot.addItem(snapshot, low))
assert(GlobalStorageSiK.ItemSnapshot.addItem(snapshot, high))
assert(GlobalStorageSiK.ItemSnapshot.addItem(snapshot, empty))

local registry = {
	networks = { net = { id = "net" } },
	zones = { zone = { id = "zone", networkId = "net" } },
	nodes = { node = { id = "node", zoneId = "zone", itemSnapshot = snapshot } },
}
GlobalStorageSiK.Network = {
	getDefaultNetworkId = function() return "net" end,
	getDisplayName = function() return "Network" end,
	getLiveContainers = function() return {} end,
	getRegistry = function() return registry end,
	ensureRegistry = function() end,
}
GlobalStorageSiK.Zones = { getRegistry = function() return registry end }
GlobalStorageSiK.Permissions = {
	filterLiveContainers = function() return {} end,
	canAccessZone = function() return true end,
	canAccess = function() return true end,
}
GlobalStorageSiK.ZoneRefresh = {}

dofile(ROOT .. "GS_Index.lua")
local rows = GlobalStorageSiK.Index.buildRows("net", {})
assert(#rows == 3, "different fluid shapes/content must expose distinct parent rows")
local fuelParents, emptyParent = {}, nil
local rowPaths = {}
for i = 1, #rows do
	local parent = rows[i]
	rowPaths[#rowPaths + 1] = tostring(parent.nativePath)
	if parent.nativePath == "native:vehicles/consumable/fuel" then
		fuelParents[#fuelParents + 1] = parent
	end
	if parent.nativePath == "native:containers/liquid/empty" then emptyParent = parent end
end
assert(#fuelParents == 2 and fuelParents[1].rowKey ~= fuelParents[2].rowKey,
	"different container capacities/forms must remain distinct fuel groups: count="
		.. tostring(#fuelParents)
		.. " paths=" .. table.concat(rowPaths, ",")
		.. " keys=" .. tostring(fuelParents[1] and fuelParents[1].rowKey)
		.. "/" .. tostring(fuelParents[2] and fuelParents[2].rowKey))
assert(fuelParents[1].count == 1 and fuelParents[2].count == 1
	and not fuelParents[1].mixedVariants and not fuelParents[2].mixedVariants,
	"each fuel shape must retain only its canonical identity")
assert(emptyParent and emptyParent.count == 1 and not emptyParent.mixedVariants
	and emptyParent.rowKey ~= fuelParents[1].rowKey
	and emptyParent.rowKey ~= fuelParents[2].rowKey,
	"empty container identity must remain separate from fuel")
local emptyPage = GlobalStorageSiK.Index.buildDetailPage("net", {}, emptyParent.rowKey, 1, 15)
assert(emptyPage.total == 1 and #emptyPage.items == 1,
	"empty group must preserve its exact physical unit")
local ids = {}
local pages = { emptyPage }
for i = 1, #fuelParents do
	local page = GlobalStorageSiK.Index.buildDetailPage("net", {}, fuelParents[i].rowKey, 1, 15)
	assert(page.total == 1 and #page.items == 1,
		"each fuel-shape group must preserve its exact physical unit")
	pages[#pages + 1] = page
end
for _, page in ipairs(pages) do
	for i = 1, #page.items do
		local child = page.items[i]
		for j = 1, #(child.itemIds or {}) do ids[child.itemIds[j]] = true end
	end
end
assert(ids[101] and ids[102] and ids[103], "children must preserve exact item IDs")

print("dev32_4_3_fluid_group_contract: OK")

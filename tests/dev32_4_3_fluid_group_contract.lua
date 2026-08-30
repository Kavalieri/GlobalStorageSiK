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
		resolve = function(fullType, row, item)
			local path = item and GlobalStorageSiK.FluidTaxonomy.resolve(item) or nil
			local encoded = path and GlobalStorageSiK.NativeProduct.encodePath(path)
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
assert(#rows == 1, "same container form must remain one parent row")
local parent = rows[1]
assert(parent.count == 3 and parent.expandable and parent.mixedVariants,
	"mixed fluid parent must expose all exact units")
assert(parent.nativePath == nil,
	"mixed fluid parent must never invent a representative category")
local page = GlobalStorageSiK.Index.buildDetailPage("net", {}, parent.rowKey, 1, 15)
assert(page.total == 3 and #page.items == 3, "all fluid children must be returned")
local ids, paths = {}, {}
for i = 1, #page.items do
	local child = page.items[i]
	for j = 1, #(child.itemIds or {}) do ids[child.itemIds[j]] = true end
	paths[child.nativePath] = true
end
assert(ids[101] and ids[102] and ids[103], "children must preserve exact item IDs")
assert(paths["native:vehicles/consumable/fuel"]
	and paths["native:containers/liquid/empty"],
	"children must preserve their exact content/empty categories")

print("dev32_4_3_fluid_group_contract: OK")

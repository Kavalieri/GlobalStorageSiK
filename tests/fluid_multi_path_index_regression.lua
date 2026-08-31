-- Author regression for mixed-fluid parent paths, projection and filtering.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

for _, name in ipairs({
	"GS_CatalogManager", "GS_NativeClassifier", "GS_NativeTaxonomyRegistry",
	"GS_Router", "GS_I18n", "GS_FluidTaxonomy", "GS_NativeProduct",
	"GS_CategoryResolution", "GS_Permissions", "GS_Network", "GS_Zones",
	"GS_ZoneRefresh",
}) do
	package.loaded[name] = true
end

FluidCategory = { Fuel = "fuel", Beverage = "beverage", Water = "water" }
local tree = {
	vehicles = { consumable = { fuel = true } },
	containers = { liquid = { empty = true } },
}

GlobalStorageSiK = {
	CatalogManager = {
		createEpochCache = function() return {} end,
		onEpochChanged = function() end,
	},
	NativeClassifier = { classify = function() return nil end },
	NativeTaxonomyRegistry = {
		hasL1 = function(l1) return tree[l1] ~= nil end,
		hasL2 = function(l1, l2) return tree[l1] and tree[l1][l2] ~= nil end,
		hasL3 = function(l1, l2, l3)
			return tree[l1] and tree[l1][l2] and tree[l1][l2][l3] == true
		end,
		getTree = function() return tree end,
	},
	Router = { getItemCategory = function() return "Container" end,
		getItemSubCategory = function() return nil end },
	I18n = {
		text = function(key) return key end,
		nameFromItemInstance = function(item) return item:getDisplayName() end,
		isLowQualityDisplayName = function() return false end,
		typeDisplayName = function(fullType) return fullType end,
		getScriptItem = function() return nil end,
	},
	isAuthoritative = function() return true end,
}

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
dofile(shared .. "GS_NativeProduct.lua")
package.loaded["GS_NativeProduct"] = true
dofile(shared .. "GS_FluidTaxonomy.lua")
package.loaded["GS_FluidTaxonomy"] = true

GlobalStorageSiK.CategoryResolution = {
	resolve = function(fullType, row, liveItem)
		if row and (row.mixedVariants or row.effective == "variants") then
			return { effective = "variants", categoryEffective = "variants",
				routingIdentity = row.routingIdentity or ("variants:" .. tostring(row.rowKey)),
				nativePaths = row.nativePaths }
		end
		local path = liveItem and GlobalStorageSiK.FluidTaxonomy.resolve(liveItem) or nil
		local encoded = path and GlobalStorageSiK.NativeProduct.encodePath(path)
			or row and row.nativePath or nil
		return { nativePath = encoded, nativeStatus = encoded and "classified" or "fallback",
			effective = encoded and "native" or "vanilla", categoryEffective = encoded and "native" or "vanilla",
			routingIdentity = encoded or "vanilla:Container", vanillaKey = "Container" }
	end,
	presentation = function(fullType, row, liveItem, knownInstancePath)
		local resolution = GlobalStorageSiK.CategoryResolution.resolve(fullType, row, liveItem,
			knownInstancePath)
		return { resolution = resolution, nativePath = resolution.nativePath,
			labels = { full = GlobalStorageSiK.CategoryResolution.label(resolution) }, color = nil }
	end,
	label = function(resolution)
		return resolution and resolution.effective == "variants" and "Varias categorías"
			or tostring(resolution and resolution.nativePath or "Container")
	end,
	color = function() return nil end,
}
package.loaded["GS_CategoryResolution"] = true

dofile(shared .. "GS_ItemSnapshot.lua")
package.loaded["GS_ItemSnapshot"] = true

local function fluidItem(id, amount, capacity, fluidType)
	return {
		getFullType = function() return "Base.PetrolCan" end,
		getID = function() return id end,
		getDisplayName = function() return "Gas Can" end,
		getName = function() return "Gas Can" end,
		getWorldSprite = function() return nil end,
		getRecordedMediaIndex = function() return -1 end,
		getFluidContainer = function()
			return {
				isEmpty = function() return amount <= 0 end,
				isMixture = function() return false end,
				isCategory = function() return false end,
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

local snapshot = {}
assert(GlobalStorageSiK.ItemSnapshot.addItem(snapshot, fluidItem(1, 5, 10, "Petrol")))
assert(GlobalStorageSiK.ItemSnapshot.addItem(snapshot, fluidItem(2, 0, 10, nil)))

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

dofile(shared .. "GS_Index.lua")
local rows = GlobalStorageSiK.Index.buildRows("net", {})
local fuel = "native:vehicles/consumable/fuel"
local empty = "native:containers/liquid/empty"
assert(#rows == 2, "fluid form+content identities must serialize as separate parents")
local byPath = {}
for i = 1, #rows do
	local row = rows[i]
	assert(not row.mixedVariants and row.nativePath,
		"a canonical fluid identity was collapsed into mixed variants")
	byPath[row.nativePath] = row
end
assert(byPath[fuel] and byPath[empty], "fluid identity lost its canonical route")

local index = GlobalStorageSiK.NativeProduct.buildIndex(rows)
assert(#GlobalStorageSiK.NativeProduct.rowsForPath(index, fuel) == 1,
	"parent is absent or duplicated under the fuel route")
assert(#GlobalStorageSiK.NativeProduct.rowsForPath(index, empty) == 1,
	"parent is absent or duplicated under the empty route")

-- A repeated route in a serialized payload must still not duplicate the row
-- in the shared inverse index.
local repeated = GlobalStorageSiK.NativeProduct.copyRow(byPath[fuel])
repeated.nativePaths = { fuel, fuel }
index = GlobalStorageSiK.NativeProduct.buildIndex({ repeated })
assert(#GlobalStorageSiK.NativeProduct.rowsForPath(index, fuel) == 1,
	"shared index duplicated a fluid parent for a repeated nativePath")

-- El payload de una fila sin variantes puede contener `nativePaths = {}` por
-- compatibilidad de serialización. El filtro L1/L2/L3 debe indexar entonces
-- su única `nativePath`, igual que la fila presentada en la tabla.
local singular = {
	fullType = "Base.WaterBottleFull",
	nativePath = "native:containers/liquid/water",
	nativePaths = {},
}
index = GlobalStorageSiK.NativeProduct.buildIndex({ singular })
assert(#GlobalStorageSiK.NativeProduct.rowsForPath(index, singular.nativePath) == 1,
	"empty nativePaths hid a unique native route from category filters")

-- Load only the public filtering surface with lightweight UI dependencies.
for _, name in ipairs({
	"ISUI/ISPanel", "ISUI/ISLabel", "ISUI/ISContextMenu", "GS_Libs", "GS_BulkFilters",
	"GS_DepositSources", "GS_TerminalWithdrawDrag", "GS_WithdrawMenu", "GS_QuantityPrompt",
	"GS_Log", "GS_ContextMenuUi", "GS_NodeHighlight", "GS_ContainerTargets",
	"GS_TerminalUI_Scroll", "GS_SiK_UI_Table", "GS_SiK_UI_Core", "GS_ItemNetworkTooltip",
	"GS_NetworkReadAction", "GS_NetClient", "GS_RemoteItemDetail", "GS_UIDebug",
}) do
	package.loaded[name] = true
end
UIFont = { Small = "Small" }
function getTextManager()
	return { getFontHeight = function() return 12 end,
		MeasureStringX = function(_, _, value) return #tostring(value or "") * 6 end }
end
GlobalStorageSiK.SiK_UI = {
	Table = { metrics = function() return { rowHeight = 24, headerHeight = 24 } end },
	truncateText = function(value) return value end,
}
GlobalStorageSiK.TerminalWithdrawDrag = { isActive = function() return false end }

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_TerminalUI_Items.lua")
assert(#GlobalStorageSiK.TerminalItems.filterByMainCategory(rows, fuel) == 1,
	"terminal filter hid the fuel parent from its route")
assert(#GlobalStorageSiK.TerminalItems.filterByMainCategory(rows, empty) == 1,
	"terminal filter hid the empty parent from its route")

print("fluid_multi_path_index_regression: OK")

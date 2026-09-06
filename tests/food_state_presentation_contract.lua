-- Dynamic food-state presentation and snapshot identity contract.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

Events = { OnGameBoot = { Add = function() end } }
local locale = "EN"
local labels = {
    EN = { Fresh = "Fresh", Stale = "Stale", Rotten = "Rotten", Cooked = "Cooked", Burnt = "Burnt", Frozen = "Frozen" },
    ES = { Fresh = "Fresco", Stale = "Pasado", Rotten = "Podrido", Cooked = "Cocinado", Burnt = "Quemado", Frozen = "Congelado" },
    CJK = { Fresh = "新鮮", Stale = "不新鮮", Rotten = "腐敗", Cooked = "調理済み", Burnt = "焦げ", Frozen = "冷凍" },
}
getText = function(key, ...)
    local state = key:match("Tooltip_food_(.+)$")
    if state and labels[locale][state] then return labels[locale][state] end
    return key
end

GlobalStorageSiK = {
    Router = { getItemCategory = function() return "Food" end, getItemSubCategory = function() return "Prepared" end },
    I18n = { nameFromItemInstance = function(item) return item:getDisplayName() end,
        isLowQualityDisplayName = function() return false end, typeDisplayName = function(t) return t end },
    FluidTaxonomy = { inspect = function() return nil end },
    NativeProduct = {},
    CategoryResolution = { resolve = function() return { effective = "mixed", vanillaKey = "Food" } end,
        label = function() return "Food" end },
}
package.loaded["GS_CatalogManager"] = true
package.loaded["GS_RecordedMedia"] = true
package.loaded["GS_I18n"] = true
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_I18n.lua")
package.loaded["GS_I18n"] = true
package.loaded["GS_Router"] = true
package.loaded["GS_FluidTaxonomy"] = true
package.loaded["GS_NativeProduct"] = true
package.loaded["GS_DisplayCategoryPublisher"] = true
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_ItemSnapshot.lua")

local function item(state, id)
    local value = {
        getFullType = function() return "Base.Apple" end,
        getID = function() return id end,
        getDisplayName = function() return "Apple" end,
        getName = function() return "Apple" end,
        isFood = function() return true end,
        isFresh = function() return state.fresh end,
        isCooked = function() return state.cooked end,
        isBurnt = function() return state.burnt end,
        isFrozen = function() return state.frozen end,
        isRotten = function() return state.rotten end,
        getWorldSprite = function() return nil end,
    }
    return value
end

local fresh = item({ fresh = true, cooked = false, burnt = false, frozen = false, rotten = false }, 1)
local rottenBurnt = item({ fresh = true, cooked = true, burnt = true, frozen = true, rotten = true }, 2)
local missing = item({ cooked = false, burnt = false, frozen = false, rotten = false }, 3)

local freshDetail = GlobalStorageSiK.ItemSnapshot.tooltipDetailFromItem(fresh)
assert(freshDetail.foodState.fresh == true and freshDetail.foodState.rotten == false,
    "snapshot must capture fresh state explicitly")
local rottenDetail = GlobalStorageSiK.ItemSnapshot.tooltipDetailFromItem(rottenBurnt)
assert(rottenDetail.foodState.rotten == true and rottenDetail.foodState.burnt == true,
    "snapshot must capture rotten and burnt state")
assert(string.find(rottenDetail.dynamicStateKey, "fresh=1", 1, true),
    "food signature must include fresh state")
local missingDetail = GlobalStorageSiK.ItemSnapshot.tooltipDetailFromItem(missing)
assert(missingDetail.foodState.fresh == false, "snapshot must capture the unavailable freshness predicate safely")

local row = { foodState = { fresh = true, cooked = true }, variantSummary = {
    { foodState = { fresh = false, cooked = true } },
    { foodState = { fresh = true, rotten = true, cooked = true, burnt = true, frozen = true } },
}}
locale = "EN"
local parentLabel = GlobalStorageSiK.I18n.foodStateLabel(row)
assert(parentLabel == "Fresh / Cooked / Stale / Rotten / Burnt / Frozen",
    "mixed parent must summarize physical states without a false fresh-only claim: " .. parentLabel)
assert(not string.find(parentLabel, "Fresh / Fresh", 1, true))
local mixedSummaryLabel = GlobalStorageSiK.I18n.foodStateLabel({ foodSummary = {
    Fresh = true, Rotten = true, Cooked = true, Burnt = true, Frozen = true,
} })
assert(mixedSummaryLabel == "Fresh / Rotten / Cooked / Burnt / Frozen",
    "aggregate foodSummary labels are not presented in canonical order")
assert(GlobalStorageSiK.I18n.foodStateLabel({ foodState = rottenDetail.foodState }) == "Rotten / Burnt / Frozen",
    "rotten and burnt take precedence over fresh and cooked")
assert(GlobalStorageSiK.I18n.foodStateLabel({ foodState = {} }) == "",
    "unknown food state must not invent Fresh")

local function localized(expected, lang)
    locale = lang
    local value = GlobalStorageSiK.I18n.foodStateLabel({ foodState = { fresh = true, cooked = true } })
    assert(value == expected, lang .. " food state label mismatch: " .. value)
end
localized("Fresco / Cocinado", "ES")
localized("新鮮 / 調理済み", "CJK")

locale = "EN"
local searchRow = { fullType = "Base.Apple", displayName = "Apple", category = "Food",
    foodState = { fresh = true }, variantSummary = {} }
local freshHaystack = GlobalStorageSiK.I18n.itemSearchHaystack(searchRow)
assert(string.find(freshHaystack, "fresh", 1, true), "search haystack must include current food label")
searchRow.foodState = { rotten = true }
local rottenHaystack = GlobalStorageSiK.I18n.itemSearchHaystack(searchRow)
assert(string.find(rottenHaystack, "rotten", 1, true) and rottenHaystack ~= freshHaystack,
    "food-state change must invalidate search cache")

local grouped = {}
assert(GlobalStorageSiK.ItemSnapshot.addItem(grouped, fresh))
assert(GlobalStorageSiK.ItemSnapshot.addItem(grouped, rottenBurnt))
local physicalCount, rowCount = 0, 0
for _, candidate in pairs(grouped) do
    rowCount = rowCount + 1
    physicalCount = physicalCount + (candidate.count or 0)
end
assert(rowCount == 2, "distinct food signatures remain separate physical rows")
assert(physicalCount == 2, "food state presentation must not alter physical count")

return true

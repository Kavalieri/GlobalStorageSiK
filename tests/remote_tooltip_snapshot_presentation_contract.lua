-- Dynamic snapshot-only remote tooltip presentation contract.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

local locale = "EN"
local translated = {
    EN = { Loading = "Loading", Unavailable = "Unavailable", Total = "Total: %s", Weight = "Weight", Amount = "Amount", Fluids = "Fluids", Tainted = "Tainted", Rotten = "Rotten" },
    ES = { Loading = "Cargando", Unavailable = "No disponible", Total = "Total: %s", Weight = "Peso", Amount = "Cantidad", Fluids = "Fluidos", Tainted = "Contaminado", Rotten = "Podrido" },
}
local function format(template, ...)
    local values = { ... }
    local i = 0
    return (template:gsub("%%s", function() i = i + 1; return tostring(values[i] or "") end))
end
getText = function(key, ...)
    local map = translated[locale] or translated.EN
    local suffix = key:match("Tooltip_food_(.+)$")
    if suffix == "Rotten" then return map.Rotten end
    if key == "Tooltip_item_Weight" then return map.Weight end
    if key == "Fluid_Amount" then return map.Amount end
    if key == "Fluid_Fluids" then return map.Fluids end
    if key == "Fluid_Tainted" then return map.Tainted end
    return key
end
GlobalStorageSiK = { I18n = {
    text = function(key, ...) local map = translated[locale] or translated.EN
        if key == "IGUI_GS_RemoteDetailLoading" then return map.Loading end
        if key == "IGUI_GS_RemoteDetailUnavailable" then return map.Unavailable end
        if key == "IGUI_GS_RemoteGroupTotal" then return format(map.Total, ...) end
        return key
    end,
    foodStateLabel = function(row)
        return row.foodState and row.foodState.rotten and translated[locale].Rotten or ""
    end,
} }
package.loaded["GS_I18n"] = true
package.loaded["GS_RemoteTooltipPresentation"] = nil
local Presentation = dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_RemoteTooltipPresentation.lua")

local function onlyLines(context)
    local blocks = Presentation.blocks(context)
    assert(#blocks == 1 and type(blocks[1].lines) == "table")
    return blocks[1].lines
end
local function has(lines, needle)
    for _, line in ipairs(lines) do if string.find(line, needle, 1, true) then return true end end
    return false
end

for _, fixture in ipairs({
    { amount = 0, capacity = 20, expected = "0 / 20 L · 0%" },
    { amount = 8, capacity = 20, expected = "8 / 20 L · 40%" },
    { amount = 12, capacity = 20, expected = "12 / 20 L · 60%" },
    { amount = 20, capacity = 20, expected = "20 / 20 L · 100%" },
}) do
    local row = { fluidAmount = fixture.amount, fluidCapacity = fixture.capacity }
    assert(Presentation.fluidQuantity(row, false) == fixture.expected, "exact fluid quantity mismatch")
end
assert(Presentation.fluidQuantity({ fluidAmount = 20, fluidCapacity = 20 }, false) == "20 / 20 L · 100%")
assert(Presentation.fluidQuantity({ totalFluidAmount = 8, totalFluidCapacity = 20, fluidAmount = 1, fluidCapacity = 1 }, true) == "8 / 20 L · 40%",
    "aggregate quantity must use group totals, not one child")
assert(Presentation.fluidQuantity({ fluidAmount = 1 }, false) == nil, "missing capacity must remain absent")

local group = onlyLines({ row = { displayName = "Water group", count = 4,
    totalFluidAmount = 12, totalFluidCapacity = 20, fluidState = { rawType = "water" } } })
assert(has(group, "Total: 4") and has(group, "12 / 20 L · 60%"), "group must show total and aggregate quantity")
assert(not has(group, "Total: 1"), "group must not present itself as one physical unit")

local loading = onlyLines({ loading = true, row = { _gsRowKind = "child", displayName = "Apple", fresh = true,
    fullType = "Base.Apple", foodState = { rotten = true }, fluidAmount = 1, fluidCapacity = 2 },
    detail = { ok = false, fullType = "Base.Fabricated" } })
assert(has(loading, "Loading") and not has(loading, "Fresh") and not has(loading, "Rotten")
    and not has(loading, "1 / 2"), "loading child must not use fabricated/base values")
local failed = onlyLines({ row = { _gsRowKind = "child", displayName = "Apple", foodState = { rotten = true }, fullType = "Base.Apple" },
    detail = { ok = false } })
assert(has(failed, "Unavailable") and #failed == 2, "failed child must show only title and unavailable")

locale = "ES"
local food = onlyLines({ row = { _gsRowKind = "child", displayName = "Manzana", foodState = { rotten = true } },
    detail = { ok = true, displayName = "Manzana", foodState = { rotten = true }, weight = 0.5 } })
assert(has(food, "Podrido") and has(food, "Peso: 0.5"), "food and weight use localized snapshot fields")

local sourceFile = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_ItemNetworkTooltip.lua"
local sourceHandle = assert(io.open(sourceFile, "r"))
local source = sourceHandle:read("*a")
sourceHandle:close()
local captured = assert(source:find("if remoteContext then return renderCapturedTooltip(self, remoteContext) end", 1, true),
    "remote context must render captured presentation before original")
local original = assert(source:find("pcall(original, self", captured, true), "local chain must preserve original renderer")
assert(captured < original, "remote captured branch must precede local original chain")
assert(source:find("self.item:DoTooltip(self.tooltip)", 1, true), "local vanilla tooltip path must remain")
assert(source:find("TooltipLib.registerProvider", 1, true), "TooltipLib provider path must remain available")

return true

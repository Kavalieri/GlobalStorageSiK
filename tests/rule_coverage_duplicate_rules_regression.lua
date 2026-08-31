-- lua51.exe tests/rule_coverage_duplicate_rules_regression.lua
-- Rules are not exclusive reservations: equal categories/items can target
-- different containers and the Router resolves their destination later.

package.loaded["GS_NativeProduct"] = true
package.loaded["GS_NativeTaxonomyRegistry"] = true

GlobalStorageSiK = {
        NativeProduct = {
                decodePath = function(path)
                        if type(path) ~= "string" or path:sub(1, 7) ~= "native:" then return nil end
                        local parts = {}
                        for part in path:sub(8):gmatch("[^/]+") do parts[#parts + 1] = part end
                        if #parts < 1 or #parts > 3 then return nil end
                        return { l1 = parts[1], l2 = parts[2], l3 = parts[3] }
                end,
                encodePath = function(path)
                        if not path or not path.l1 then return nil end
                        return "native:" .. path.l1
                                .. (path.l2 and "/" .. path.l2 or "")
                                .. (path.l3 and "/" .. path.l3 or "")
                end,
                pathMatches = function(rule, actual)
                        return rule == actual
                end,
        },
        NativeTaxonomyRegistry = { getTree = function()
                return { food = { perishable = { "fruit" } } }
        end },
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_RuleCoverage.lua")

local first = { op = "OR", condition = { type = "category", nativePath = "native:food/perishable" } }
local second = { op = "OR", condition = { type = "category", nativePath = "native:food/perishable" } }
assert(GlobalStorageSiK.RuleCoverage.prepareNewRule(first, {}), "first category rule must be accepted")
assert(GlobalStorageSiK.RuleCoverage.prepareNewRule(second, { first }),
        "same category must be accepted for a second destination")

local exact = { op = "OR", condition = { type = "item", itemType = "Base.Apple" } }
assert(GlobalStorageSiK.RuleCoverage.prepareNewRule(exact, {
        { op = "OR", condition = { type = "item", itemType = "Base.Apple" } },
}), "same exact item must be accepted for a second destination")

local legacy = { op = "OR", condition = {
        type = "category", nativePath = "native:food/perishable", coverageExclusions = { "native:food/perishable/fruit" },
} }
assert(GlobalStorageSiK.RuleCoverage.prepareNewRule(legacy, {}), "legacy category rule must remain valid")
assert(legacy.condition.coverageExclusions == nil, "legacy reservation data must be cleared")

print("rule_coverage_duplicate_rules_regression: OK")

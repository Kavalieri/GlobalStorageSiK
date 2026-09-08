-- Curated original ScriptItem keys only. Never translated text or fuzzy names.
require "GS_NativeSourceCategory"
GlobalStorageSiK.NativeSourceCategoryBridge = GlobalStorageSiK.NativeSourceCategoryBridge or {}
local RULES = {
    Electronics = { l1 = 'electronics_power', id = 'electronics' },
    Ammo = { l1 = 'combat', id = 'ammo' },
    WeaponPart = { l1 = 'combat', id = 'weapon_part' },
}
local counts = { electronics = 0, ammo = 0, weapon_part = 0 }
function GlobalStorageSiK.NativeSourceCategoryBridge.resolve(fullType, scriptItem)
    local category = GlobalStorageSiK.NativeSourceCategory.get(scriptItem)
    if type(category) ~= 'string' then return nil end
    local rule = RULES[category]
    if not rule then return nil end
    return { l1 = rule.l1 }, {}, {}, {
        primary = { source = 'source_category_bridge', scope = 'script',
            confidence = 70, l1Kind = 'source_category', sourceCategory = category,
            mappingId = rule.id }, supporting = {}, conflicting = {},
    }
end
function GlobalStorageSiK.NativeSourceCategoryBridge.record(evidence)
    local id = evidence.primary.mappingId
    if counts[id] ~= nil then counts[id] = counts[id] + 1 end
end
function GlobalStorageSiK.NativeSourceCategoryBridge.resetMetrics()
    counts.electronics, counts.ammo, counts.weapon_part = 0, 0, 0
end
function GlobalStorageSiK.NativeSourceCategoryBridge.getMetrics()
    return { electronics = counts.electronics, ammo = counts.ammo, weapon_part = counts.weapon_part }
end

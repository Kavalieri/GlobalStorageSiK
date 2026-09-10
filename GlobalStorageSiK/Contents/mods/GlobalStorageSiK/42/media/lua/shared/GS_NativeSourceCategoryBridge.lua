-- Curated original ScriptItem keys only. Never translated text or fuzzy names.
require "GS_NativeSourceCategory"
GlobalStorageSiK.NativeSourceCategoryBridge = GlobalStorageSiK.NativeSourceCategoryBridge or {}
-- The engine and loaded mods already expose a broad, language-independent
-- DisplayCategory vocabulary.  These rules deliberately stop at L1: they keep
-- that authoritative family when no stronger structural classifier can justify
-- L2/L3, instead of inventing detail from a translated name or token.
local RULES = {
    Accessory = { l1 = "clothing_protection", id = "clothing" },
    Appearance = { l1 = "clothing_protection", id = "clothing" },
    Clothing = { l1 = "clothing_protection", id = "clothing" },

    Ammo = { l1 = "combat", id = "ammo", overrideNominal = true },
    Devices = { l1 = "combat", id = "explosive_device" },
    Explosives = { l1 = "combat", id = "explosive" },
    Weapon = { l1 = "combat", id = "weapon" },
    WeaponPart = { l1 = "combat", id = "weapon_part", overrideNominal = true },

    Food = { l1 = "food_drink", id = "food" },
    Water = { l1 = "food_drink", id = "water" },
    FirstAid = { l1 = "medicine", id = "first_aid" },
    Laboratory = { l1 = "medicine", id = "laboratory" },

    Tool = { l1 = "tools", id = "tool" },
    Material = { l1 = "materials", id = "material" },
    AnimalPart = { l1 = "materials", id = "animal_part" },
    Corpse = { l1 = "materials", id = "corpse" },
    HumanPart = { l1 = "materials", id = "human_part" },

    WaterContainer = { l1 = "containers", id = "water_container" },
    Cartography = { l1 = "knowledge_media", id = "cartography" },
    Communications = { l1 = "electronics_power", id = "communications" },
    Electronics = { l1 = "electronics_power", id = "electronics", overrideNominal = true },
    LightSource = { l1 = "electronics_power", id = "light_source" },

    Tuning = { l1 = "vehicles", id = "tuning" },
    TuningService = { l1 = "vehicles", id = "tuning_service" },
    VehicleMaintenance = { l1 = "vehicles", id = "vehicle_maintenance" },

    Animal = { l1 = "survival_outdoors", id = "animal" },
    Camping = { l1 = "survival_outdoors", id = "camping" },
    FireSource = { l1 = "survival_outdoors", id = "fire_source" },
    Fishing = { l1 = "survival_outdoors", id = "fishing" },
    Gardening = { l1 = "survival_outdoors", id = "gardening" },
    Generic = { l1 = "survival_outdoors", id = "generic_animal" },
    Security = { l1 = "survival_outdoors", id = "security" },

    Cooking = { l1 = "home_leisure_collection", id = "cooking" },
    Decorations = { l1 = "home_leisure_collection", id = "decorations" },
    Furniture = { l1 = "home_leisure_collection", id = "furniture" },
    Household = { l1 = "home_leisure_collection", id = "household" },
    Instrument = { l1 = "home_leisure_collection", id = "instrument" },
    Memento = { l1 = "home_leisure_collection", id = "memento" },
    Paint = { l1 = "home_leisure_collection", id = "paint" },
    Sports = { l1 = "home_leisure_collection", id = "sports" },
    Badger = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Beaver = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Bug = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Bulldog = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Bunny = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Dog = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Duck = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Eye = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Fox = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Frog = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Goblin = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Mole = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Raccoon = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Spider = { l1 = "home_leisure_collection", id = "collectible_toy" },
    Squirrel = { l1 = "home_leisure_collection", id = "collectible_toy" },
    ["Teddy Bear"] = { l1 = "home_leisure_collection", id = "collectible_toy" },

    Hidden = { l1 = "other", id = "hidden" },
    Junk = { l1 = "other", id = "junk" },
}

-- A module rule is only used when the author supplied no DisplayCategory at
-- all.  It covers the complete, single-purpose public module rather than item
-- names.  PSR contains only its solar-power device family in the audited set.
local MODULE_RULES = {
    PSR = { l1 = "electronics_power", id = "module_psr" },
}

local function emptyCounts()
    return {}
end

local counts = emptyCounts()

local function evidence(source, category, rule)
    return {
        primary = { source = source, scope = "script",
            confidence = source == "source_category_bridge" and 70 or 60,
            l1Kind = source == "source_category_bridge" and "source_category" or "script_module",
            sourceCategory = category, mappingId = rule.id },
        supporting = {}, conflicting = {},
    }
end

function GlobalStorageSiK.NativeSourceCategoryBridge.resolve(fullType, scriptItem)
    local category = GlobalStorageSiK.NativeSourceCategory.get(scriptItem)
    if type(category) == "string" then
        local rule = RULES[category]
        if rule then
            return { l1 = rule.l1 }, {}, {}, evidence("source_category_bridge", category, rule),
                rule.overrideNominal == true
        end
    end
    local module = type(fullType) == "string" and fullType:match("^([^.]+)%.") or nil
    local moduleRule = module and MODULE_RULES[module]
    if not moduleRule then return nil end
    return { l1 = moduleRule.l1 }, {}, {}, evidence("source_module_bridge", nil, moduleRule), false
end
function GlobalStorageSiK.NativeSourceCategoryBridge.record(evidence)
    local id = evidence and evidence.primary and evidence.primary.mappingId
    if id then counts[id] = (counts[id] or 0) + 1 end
end
function GlobalStorageSiK.NativeSourceCategoryBridge.resetMetrics()
    counts = emptyCounts()
end
function GlobalStorageSiK.NativeSourceCategoryBridge.getMetrics()
    local result = {}
    for id, count in pairs(counts) do
        if count > 0 then result[id] = count end
    end
    if result.electronics or result.ammo or result.weapon_part then
        result.electronics = result.electronics or 0
        result.ammo = result.ammo or 0
        result.weapon_part = result.weapon_part or 0
    end
    return result
end

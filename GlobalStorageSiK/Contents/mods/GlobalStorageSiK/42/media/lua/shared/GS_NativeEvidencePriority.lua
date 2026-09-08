-- L1 evidence strength, deliberately independent of confidence and source prefixes.
-- Some structural L1 identities still use nominal detail for L2/L3.
require 'GS_NativeClassifierUtils'
GlobalStorageSiK.NativeEvidencePriority = GlobalStorageSiK.NativeEvidencePriority or {}
local KINDS = {}
local function register(kind, sources)
    for source in sources:gmatch('%S+') do KINDS[source] = kind end
end
register('exact', [[
exact_fulltype_incendiary exact_fulltype_material exact_fulltype_tool
exact_fulltype_own_item exact_fulltype_medicine canonical_fulltype_override
]])
register('structural', [[
script_weapon_category script_is_ranged script_ammo_type script_ammo_tag
script_item_type_weapon_part script_body_location_backpack script_equippable_container
script_body_location_ammo_strap script_body_location_jewelry script_body_location
script_fluid_container_component script_container_structure script_item_is_spice_confirmed
script_food_tag script_item_type script_movable_appliance script_movable_storage
script_item_type_fallback gs_recipe_manual_structural script_recorded_media_category
script_skill_trained script_recipe_resource script_tag_isseed script_tag_tool
script_gardening_seed_packet
]])
register('nominal', [[
name_ammo_box_weak name_clothing_backpack name_containers_liquid
name_containers_special name_containers_portable name_food_prepared_meal
name_food_meat_protein name_food_dairy_egg name_food_fish_seafood name_food_produce
name_food_pantry name_food_ingredient name_food_other name_food_beverage
name_food_animal_feed name_movable_surface name_movable_seating name_home_kitchen
name_home_cleaning name_home_renovation name_home_collection name_home_leisure
name_knowledge_skill_book name_knowledge_recipe_magazine name_knowledge_general_magazine
name_knowledge_literature name_knowledge_document name_knowledge_recorded_media
name_metal name_leather name_textile name_mineral name_organic name_wood
name_medicine_supply name_medicine_surgery name_medicine_treatment name_medicine_medication
name_electronics_power name_electronics_communication name_electronics_lighting
name_electronics_entertainment name_vehicles_part name_vehicles_consumable
name_survival_farming name_survival_fishing
name_survival_trapping name_survival_camping name_survival_security
]])
function GlobalStorageSiK.NativeEvidencePriority.resolve(path, evidence, scriptItem)
    local primary = evidence and evidence.primary
    local kind = primary and KINDS[primary.source] or nil
    -- A liquid-shape heuristic can return before the container fallback. Its
    -- L1 remains structural when the engine explicitly declares a container.
    if kind == 'nominal' and path.l1 == 'containers'
        and GlobalStorageSiK.NativeClassifierUtils.itemTypeLower(scriptItem) == 'base:container' then
        kind = 'structural'
    end
    if kind == 'exact' then return 3, kind end
    if kind == 'structural' then return 2, kind end
    if kind == 'nominal' then return 0, kind end
    -- Unreviewed producers retain their old precedence against a category
    -- bridge; do not silently downgrade them or claim structural evidence.
    return 2, 'unknown'
end

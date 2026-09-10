-- Curated product identities, independent of world-specific staff overrides.
-- Exact fullType only: translated labels and partial names never participate.
GlobalStorageSiK.NativeCanonicalOverrides = GlobalStorageSiK.NativeCanonicalOverrides or {}

local ENTRIES = {
    -- A cleaning implement remains discoverable as such even though vanilla
    -- also permits striking with it. Exact product policy, not a name heuristic.
    ['Base.Mop'] = { 'home_leisure_collection', 'cleaning', 'tool',
        'cleaning_implement', 'B42:weapon.txt:Mop:CleanStains' },
    ['Base.ElectricWire'] = { 'electronics_power', 'component', false,
        'electrical_component', 'B42:normal.txt:ElectricWire' },
    ['Base.ElectronicsScrap'] = { 'electronics_power', 'component', false,
        'electrical_component', 'B42:normal.txt:ElectronicsScrap' },
    ['Base.3030Box'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:3030Box' },
    ['Base.3030Carton'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:3030Carton' },
    ['Base.308Box'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:308Box' },
    ['Base.308Carton'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:308Carton' },
    ['Base.556Box'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:556Box' },
    ['Base.556Carton'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:556Carton' },
    ['Base.Bullets357Box'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:Bullets357Box' },
    ['Base.Bullets357Carton'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:Bullets357Carton' },
    -- B42 ammunition packages declare Ammo and an opening recipe but lack
    -- standalone AmmoType/tags. Keep their curated identity above the L1 bridge.
    ['Base.Bullets38Box'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:Bullets38Box:OpenBoxOfBullets50' },
    ['Base.Bullets38Carton'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:Bullets38Carton:OpenCarton12' },
    ['Base.Bullets44Box'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:Bullets44Box:OpenBoxOfBullets20' },
    ['Base.Bullets44Carton'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:Bullets44Carton:OpenCarton12' },
    ['Base.Bullets45Box'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:Bullets45Box:OpenBoxOfBullets50' },
    ['Base.Bullets45Carton'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:Bullets45Carton:OpenCarton12' },
    ['Base.Bullets9mmBox'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:Bullets9mmBox:OpenBoxOfBullets50' },
    ['Base.Bullets9mmCarton'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:Bullets9mmCarton:OpenCarton12' },
    ['Base.ShotgunShellsBox'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:ShotgunShellsBox:OpenBoxOfShotgunShells' },
    ['Base.ShotgunShellsCarton'] = { 'combat', 'firearm', 'ammunition',
        'packaged_ammunition', 'B42:normal.txt:ShotgunShellsCarton:OpenCarton12' },
    ['Base.Battery'] = { 'electronics_power', 'power', false,
        'portable_power_source', 'B42:drainable.txt:Battery' },
}

function GlobalStorageSiK.NativeCanonicalOverrides.resolve(fullType, scriptItem)
    if not scriptItem then return nil end
    local entry = ENTRIES[fullType]
    if not entry then return nil end
    local facets = {}
    if entry[4] == 'packaged_ammunition' then facets.ammo = true end
    if entry[4] == 'cleaning_implement' then facets.weaponCapability = true end
    return { l1 = entry[1], l2 = entry[2], l3 = entry[3] or nil }, facets, {}, {
        primary = {
            source = 'canonical_fulltype_override', kind = 'exact',
            scope = 'script', confidence = 90,
            reason = entry[4], reference = entry[5],
        },
        supporting = {}, conflicting = {},
    }
end

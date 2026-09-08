-- Curated product identities, independent of world-specific staff overrides.
-- Exact fullType only: translated labels and partial names never participate.
GlobalStorageSiK.NativeCanonicalOverrides = GlobalStorageSiK.NativeCanonicalOverrides or {}

local ENTRIES = {
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
}

function GlobalStorageSiK.NativeCanonicalOverrides.resolve(fullType, scriptItem)
    if not scriptItem then return nil end
    local entry = ENTRIES[fullType]
    if not entry then return nil end
    local facets = {}
    if entry[4] == 'packaged_ammunition' then facets.ammo = true end
    return { l1 = entry[1], l2 = entry[2], l3 = entry[3] or nil }, facets, {}, {
        primary = {
            source = 'canonical_fulltype_override', kind = 'exact',
            scope = 'script', confidence = 90,
            reason = entry[4], reference = entry[5],
        },
        supporting = {}, conflicting = {},
    }
end

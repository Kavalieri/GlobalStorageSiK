-- Optional native body for a physical child already present in the local cell.
-- No chunk loads, network scan, mutations or global Java-reference cache.
local LocalTooltip = {}

local function validId(value)
    return type(value) == "number" and value == value and value >= 0
        and value <= 2147483647 and value == math.floor(value)
end

local function findById(rows, id)
    for i = 1, #(rows or {}) do
        local row = rows[i]
        if row and row.id == id then return row end
    end
end

local function resolveNode(row, state, player)
    local gs = GlobalStorageSiK
    if isClient and isClient() then
        -- The server already filters terminal nodes by this player's zone
        -- permissions. Its persistent registry is not a client-side mirror:
        -- consulting it here discarded loaded, exact items on remote clients.
        local node = findById(state.nodes, row.nodeId)
        local zone = node and findById(state.zones, node.zoneId)
        if not node or not zone or zone.enabled == false
            or (zone.networkId ~= nil and zone.networkId ~= state.networkId) then return nil end
        return node
    end
    if not gs.Zones or not gs.Zones.getRegistry or not gs.Permissions
        or not gs.Permissions.canAccessZone then return nil end
    local registry = gs.Zones.getRegistry()
    local node = registry and registry.nodes and registry.nodes[row.nodeId]
    local zone = node and registry.zones and registry.zones[node.zoneId]
    if not node or not zone or zone.networkId ~= state.networkId or zone.enabled == false
        or not gs.Permissions.canAccessZone(player, state.networkId, node.zoneId) then return nil end
    return node
end

local function resolve(row, terminal)
    local state = terminal and terminal.terminalState
    if not state or not row or row._gsRowKind ~= "child" or row._gsStale
        or not state.networkId or not validId(row.itemId)
        or type(row.fullType) ~= "string" or type(row.nodeId) ~= "string"
        or row.selectionRevision ~= state.inventoryRevision then return nil end
    local gs = GlobalStorageSiK
    if not gs.Network or not gs.Network.findWorldObject
        or not gs.Utils or not gs.Utils.getObjectContainer then return nil end
    local player = getSpecificPlayer and getSpecificPlayer(terminal.playerNum or 0)
    if not player then return nil end
    local node = resolveNode(row, state, player)
    if not node or node.enabled == false or node.offline == true
        or node.membership == "excluded" then return nil end
    local object = gs.Network.findWorldObject(node)
    local container = object and gs.Utils.getObjectContainer(object, node.containerIndex)
    if not container then return nil end
    local item = container.getItemWithID and container:getItemWithID(row.itemId)
    if not item and container.getItemById then item = container:getItemById(row.itemId) end
    if not item or item:getID() ~= row.itemId or item:getFullType() ~= row.fullType
        or item:getContainer() ~= container then return nil end
    local items = container:getItems()
    if not items or not items:contains(item) then return nil end
    return {item=item, container=container, object=object, node=node,
        networkId=state.networkId, revision=state.inventoryRevision,
        itemId=row.itemId, fullType=row.fullType, playerNum=terminal.playerNum or 0,
        checkedAt=getTimestampMs and getTimestampMs() or 0}
end

function LocalTooltip.resolve(row, terminal)
    local ok, result = pcall(resolve, row, terminal)
    return ok and result or nil
end

function LocalTooltip.isCurrent(binding, row, terminal)
    if not binding then return false end
    local ok, current = pcall(function()
        local state = terminal and terminal.terminalState
        if not state or not row or row._gsStale or row.itemId ~= binding.itemId
            or row.fullType ~= binding.fullType or state.networkId ~= binding.networkId
            or state.inventoryRevision ~= binding.revision or row.selectionRevision ~= binding.revision
            or (terminal.playerNum or 0) ~= binding.playerNum
            or binding.item:getID() ~= binding.itemId
            or binding.item:getFullType() ~= binding.fullType
            or binding.item:getContainer() ~= binding.container then return false end
        if binding.object.getObjectIndex and binding.object:getObjectIndex() < 0 then return false end
        -- Movement/revision is checked cheaply every render. Recheck world
        -- membership and permissions only while hovered, with a bounded backup
        -- for changes that do not move the item or emit an inventory revision.
        local now = getTimestampMs and getTimestampMs() or 0
        if now <= 0 or now < binding.checkedAt or now - binding.checkedAt >= 500 then
            local latest = LocalTooltip.resolve(row, terminal)
            if not latest or latest.item ~= binding.item or latest.container ~= binding.container then return false end
            binding.checkedAt = now
        end
        return true
    end)
    return ok and current == true
end

return LocalTooltip

-- Internal shared authority for Craft/Builder physical loans. Addons continue
-- to use WorkSession; a loan never captures unrelated container contents.
require "GS_Transfer"
require "GS_Index"
GlobalStorageSiK.WorkTransfers = {}
local W = GlobalStorageSiK.WorkTransfers

-- A client hint selects one registered container; it never grants access.
-- Reject stale membership/physical identity instead of searching other nodes.
function W.findClaimSource(player, networkId, nodeId, itemId)
    if type(nodeId)~="string" or #nodeId==0 or #nodeId>240
        or type(itemId)~="number" or itemId~=itemId or itemId<0 or itemId>=math.huge
        or itemId~=math.floor(itemId) then return nil end
    local registry=GlobalStorageSiK.Zones.getRegistry()
    local entry=registry.nodes and registry.nodes[nodeId]
    local zone=entry and registry.zones and registry.zones[entry.zoneId]
    if not entry or entry.id~=nodeId or not zone or zone.networkId~=networkId
        or zone.enabled==false or entry.enabled==false or entry.membership=="excluded" or entry.offline==true
        or not GlobalStorageSiK.Permissions.canAccessZone(player,networkId,entry.zoneId) then return nil end
    local object=GlobalStorageSiK.Network.findWorldObject(entry)
    if not object or not GlobalStorageSiK.Utils.isNetworkStorageContainer(object,entry.containerIndex) then return nil end
    local container=GlobalStorageSiK.Utils.getObjectContainer(object,entry.containerIndex)
    local items=container and container:getItems()
    if items then
        for i=0,items:size()-1 do
            local item=items:get(i)
            if item and item.getID and tostring(item:getID())==tostring(itemId)
                and item:getContainer()==container then return item,container,entry end
        end
    end
    return nil
end

function W.changed(player, networkId, updated, nodeId)
    return GlobalStorageSiK.NodeSnapshots.notifyMutation(player,networkId,updated,nodeId)
end

function W.claim(player, networkId, item, container, entry)
    if not GlobalStorageSiK.isAuthoritative() or not player or not item or not container then return false end
    -- A resolved entry is supplied only by the authoritative server search.
    -- SP callers resolve the same permission-filtered live membership here.
    if not entry then
        local live = GlobalStorageSiK.Permissions.filterLiveContainers(player, networkId,
            GlobalStorageSiK.Network.getLiveContainers(networkId))
        for i=1,#live do
            if live[i].container == container then entry=live[i].entry; break end
        end
    end
    if not entry or not entry.id or item:getContainer() ~= container then return false end
    if not GlobalStorageSiK.InventorySync.moveBetween(container, player:getInventory(), item, player) then return false end
    local ok, updated = pcall(GlobalStorageSiK.Index.syncNodeSnapshot, entry, container)
    W.changed(player, networkId, ok and updated == true, entry.id)
    return true
end

function W.deposit(player, networkId, item)
    if not GlobalStorageSiK.isAuthoritative() then return false end
    local ok, reason, updated, nodeId = GlobalStorageSiK.Transfer.depositItem(player, item, networkId)
    if ok then W.changed(player, networkId, updated, nodeId) end
    return ok, reason
end

-- Server integration for explicit floor destinations. The command handler owns
-- terminal access, network locking, selection tickets and correlated feedback.
require 'GS_FloorMutation'
require 'GS_FloorOperationGuard'
require 'GS_Transfer'
GlobalStorageSiK.FloorTransfers = GlobalStorageSiK.FloorTransfers or {}

local function findSource(player, networkId, itemId, fullType, sourceNodeId)
    local live = GlobalStorageSiK.Permissions.filterLiveContainers(player, networkId,
        GlobalStorageSiK.Network.getLiveContainers(networkId))
    for i = 1, #live do
        local source = live[i]
        if source.entry and (sourceNodeId == nil or source.entry.id == sourceNodeId) then
            local container = source.container
            local item = container and container:getItemWithID(itemId)
            if item and tostring(item:getID()) == tostring(itemId)
                and item:getFullType() == fullType then return source, item end
        end
    end
    return nil
end

-- One routed destination per physical pickup; the handler owns its ACK and
-- revision update, just as it does for ordinary depositItems.
function GlobalStorageSiK.FloorTransfers.depositOne(player, networkId, sourceKey,
    itemId, fullType, sequence, visitOnlinePlayers)
    local target
    local moved, reason, reconcile = GlobalStorageSiK.FloorOperationGuard.execute(
        player, sequence, itemId, function()
            if not GlobalStorageSiK.Sandbox.remoteTransferEnabled() then return false, 'remote_disabled', false end
            if not GlobalStorageSiK.Power.networkPowered(networkId) then return false, 'no_power', false end
            local allowed, accessReason = GlobalStorageSiK.Permissions.canAccess(player, networkId)
            if not allowed then return false, accessReason or 'no_access', false end
            local item, sourceReason = GlobalStorageSiK.FloorTargets.findItemOnSquare(player, sourceKey, itemId, fullType)
            if not item then return false, sourceReason, false end
            local accepted, filterReason = GlobalStorageSiK.BulkFilters.canDeposit(item, player,
                GlobalStorageSiK.BulkFilters.SCOPE.SELECTION, nil)
            if not accepted then return false, filterReason or 'filtered', false end
            local session = GlobalStorageSiK.Transfer.createDepositSession(player, networkId)
            local targetReason
            target, targetReason = GlobalStorageSiK.Router.pickDepositTarget(item, session.liveNodes, player,
                { affinityIndex = session.affinityIndex })
            if not target then return false, targetReason or 'no_space', false end
            return GlobalStorageSiK.FloorMutation.fromFloor(player, target.container, sourceKey, itemId, fullType)
        end, visitOnlinePlayers)
    local snapshotsUpdated = false
    if target and (moved or reconcile) then
        local ok, updated = pcall(GlobalStorageSiK.Index.syncNodeSnapshot, target.entry, target.container)
        snapshotsUpdated = ok and updated == true
    end
    return { moved = moved and 1 or 0, skipped = 0,
        failed = (not moved or reconcile) and 1 or 0,
        reason = reason, reconcile = reconcile, snapshotsUpdated = snapshotsUpdated,
        itemIds = moved and { itemId } or {} }
end

function GlobalStorageSiK.FloorTransfers.withdrawOne(player, networkId, targetKey,
    itemIds, fullType, sourceNodeId, sequence, visitOnlinePlayers)
    if type(itemIds) ~= 'table' or #itemIds ~= 1 or type(fullType) ~= 'string'
        or fullType == '' or #fullType > 160 then
        return false, 'exact_selection_required', 0, {}, {}, false, false
    end
    local source
    local moved, reason, reconcile = GlobalStorageSiK.FloorOperationGuard.execute(
        player, sequence, itemIds[1], function()
            if not GlobalStorageSiK.Sandbox.remoteTransferEnabled() then return false, 'remote_disabled', false end
            if not GlobalStorageSiK.Power.networkPowered(networkId) then return false, 'no_power', false end
            local allowed, accessReason = GlobalStorageSiK.Permissions.canAccess(player, networkId)
            if not allowed then return false, accessReason or 'no_permission', false end
            local item
            source, item = findSource(player, networkId, itemIds[1], fullType, sourceNodeId)
            if not source then return false, 'not_found', false end
            return GlobalStorageSiK.FloorMutation.toFloor(player, source.container, item, targetKey)
        end, visitOnlinePlayers)
    local snapshotsUpdated = false
    if source and (moved or reconcile) then
        -- A failed snapshot write cannot conceal a completed physical mutation.
        local ok, updated = pcall(GlobalStorageSiK.Index.syncNodeSnapshot, source.entry, source.container)
        snapshotsUpdated = ok and updated == true
    end
    return moved and not reconcile, reason, moved and 1 or 0,
        moved and { itemIds[1] } or {},
        moved and { source.entry.id } or {}, snapshotsUpdated, reconcile
end

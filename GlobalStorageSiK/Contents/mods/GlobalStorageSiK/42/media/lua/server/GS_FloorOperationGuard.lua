-- Authority-only replay window and custody for floor mutations.
-- No timer, expiry of uncertain receipts, or serialization of Java references.
GlobalStorageSiK.FloorOperationGuard = GlobalStorageSiK.FloorOperationGuard or {}
local Guard = GlobalStorageSiK.FloorOperationGuard
local sessions, pending = {}, {}
local sessionCount, pendingCount = 0, 0
local MAX_SEQUENCE, WINDOW = 2147483647, 64
local MAX_SESSIONS, MAX_PENDING = 256, 128

local function integer(value, minimum, maximum)
    return type(value) == 'number' and value == value and value >= minimum
        and value < math.huge and (maximum == nil or value <= maximum)
        and value == math.floor(value)
end

local function pruneSessions(player, visitOnlinePlayers)
    if type(visitOnlinePlayers) ~= 'function' then return end
    local live = { [player] = true }
    local ok = pcall(visitOnlinePlayers, function(online)
        if online then live[online] = true end
    end)
    if not ok then return end
    local retired = {}
    for previous in pairs(sessions) do
        if not live[previous] then retired[#retired + 1] = previous end
    end
    for i = 1, #retired do
        sessions[retired[i]] = nil
        sessionCount = sessionCount - 1
    end
    -- Pending item custody is intentionally independent of player sessions.
end

local function admit(player, sequence, visitOnlinePlayers)
    pruneSessions(player, visitOnlinePlayers)
    local state = sessions[player]
    if not state then
        if sessionCount >= MAX_SESSIONS then return false, 'floor_busy' end
        state = { head = sequence, seen = {} }
        sessions[player] = state
        sessionCount = sessionCount + 1
    else
        local forward = (sequence - state.head) % MAX_SEQUENCE
        if forward > 0 and forward < MAX_SEQUENCE / 2 then
            state.head = sequence
            local retired = {}
            for previous in pairs(state.seen) do
                if (sequence - previous) % MAX_SEQUENCE >= WINDOW then retired[#retired + 1] = previous end
            end
            for i = 1, #retired do state.seen[retired[i]] = nil end
        elseif (state.head - sequence) % MAX_SEQUENCE >= WINDOW then
            return false, 'floor_request_stale'
        end
    end
    if state.seen[sequence] then return false, 'floor_request_repeated' end
    -- Mark before any callback: SP can execute synchronously and reenter.
    state.seen[sequence] = true
    return true
end

-- mutate returns the exact FloorMutation tuple: moved, reason, reconcile, receipt.
-- Only this narrow callback belongs inside custody; snapshot/UI updates follow it.
function Guard.execute(player, sequence, itemId, mutate, visitOnlinePlayers)
    if not GlobalStorageSiK.isAuthoritative() then return false, 'not_authoritative', false end
    if not player or not integer(sequence, 1, MAX_SEQUENCE) or not integer(itemId, 0) or type(mutate) ~= 'function' then
        return false, 'invalid_request', false
    end
    local admitted, reason = admit(player, sequence, visitOnlinePlayers)
    if not admitted then return false, reason, false end
    local key = tostring(itemId)
    local previous = pending[key]
    local mutation = GlobalStorageSiK.FloorMutation
    if previous and previous.state == 'unresolved' and previous.receipt
        and mutation and type(mutation.inspectReceipt) == 'function' then
        -- A new explicit request may observe settled physical custody. Never
        -- replay the old operation or infer transport success from this check.
        local inspected, physical = pcall(mutation.inspectReceipt, previous.receipt)
        if inspected and (physical == 'moved' or physical == 'restored') then
            pending[key], pendingCount = nil, pendingCount - 1
        end
    end
    if pending[key] then
        local uncertain = pending[key].state == 'unresolved'
        return false, uncertain and 'floor_state_uncertain' or 'floor_busy', uncertain
    end
    if pendingCount >= MAX_PENDING then return false, 'floor_busy', false end
    local record = { itemId = itemId, sequence = sequence, state = 'running' }
    pending[key], pendingCount = record, pendingCount + 1
    local ok, moved, moveReason, reconcile, receipt = pcall(mutate)
    record.receipt = receipt
    if not ok or type(moved) ~= 'boolean' then
        record.state, record.reason = 'unresolved', 'floor_state_uncertain'
        return false, record.reason, true, receipt
    end
    if reconcile == true then
        record.state, record.reason = 'unresolved', moveReason or 'floor_state_uncertain'
        return moved, record.reason, true, receipt
    end
    pending[key], pendingCount = nil, pendingCount - 1
    return moved, moveReason, false, receipt
end

-- Server diagnostics only. This snapshot contains no item/container/player refs.
function Guard.getPendingSummary()
    local result = {}
    for _, record in pairs(pending) do
        result[#result + 1] = { itemId = record.itemId, sequence = record.sequence,
            state = record.state, reason = record.reason }
    end
    return result
end

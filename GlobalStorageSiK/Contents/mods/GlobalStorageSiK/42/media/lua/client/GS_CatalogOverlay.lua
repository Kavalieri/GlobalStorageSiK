-- Confirmed withdrawals projected over an older catalog; never mutate its base.
local Overlay = {}
GlobalStorageSiK.CatalogOverlay = Overlay
local players = {}
local LIMIT = 4096
function Overlay.clear(playerNum)
    if playerNum == nil then players = {} else players[playerNum] = nil end
end
function Overlay.record(playerNum, networkId, rowKey, revision, moved, requestId)
    if type(rowKey) ~= "string" or rowKey == "" or type(revision) ~= "number"
        or type(moved) ~= "number" or moved <= 0 or not requestId then return false end
    local parent = rowKey:match("^(.-)\31item:") or rowKey:match("^(.-)\31detail:") or rowKey
    local entry = players[playerNum]
    if not entry or entry.networkId ~= networkId then
        entry = {networkId=networkId, events={}, count=0, uncertain={}, uncertainCount=0}
        players[playerNum] = entry
    end
    if entry.events[requestId] then return false end
    if entry.count >= LIMIT then
        -- No unconfirmed decrement is evicted. Only this row becomes uncertain.
        if not entry.uncertain[parent] then
            if entry.uncertainCount >= LIMIT then return false end
            entry.uncertainCount = entry.uncertainCount + 1
        end
        entry.uncertain[parent] = math.max(entry.uncertain[parent] or 0, revision)
        return false
    end
    entry.events[requestId] = {rowKey=parent, revision=revision, moved=moved}
    entry.count = entry.count + 1
    return true
end
function Overlay.pendingKeys(playerNum, networkId, revision)
    local keys, entry = {}, players[playerNum]
    if not entry or entry.networkId ~= networkId then return keys end
    for _,event in pairs(entry.events) do
        if event.revision > revision then keys[event.rowKey] = true end
    end
    for rowKey, expected in pairs(entry.uncertain) do
        if expected > revision then keys[rowKey] = true end
    end
    return keys
end
function Overlay.project(items, playerNum, networkId, revision)
    local entry = players[playerNum]
    if not entry or entry.networkId ~= networkId then return items end
    local changes, uncertain = {}, entry.uncertain
    for _,event in pairs(entry.events) do
        if event.revision > revision then changes[event.rowKey]=(changes[event.rowKey] or 0)+event.moved end
    end
    local result = {}
    for i=1,#items do
        local row = items[i]
        local delta = changes[row.rowKey]
        if delta or (uncertain[row.rowKey] or 0)>revision then
            local copy={}
            for key,value in pairs(row) do copy[key]=value end
            copy.count=math.max(0,(tonumber(row.count) or 0)-(delta or 0))
            copy._gsConfirmedPending=true
            row=copy
        end
        result[i]=row
    end
    return result
end
function Overlay.accept(playerNum, networkId, revision)
    local entry=players[playerNum]
    if not entry then return end
    if entry.networkId~=networkId then players[playerNum]=nil; return end
    local retired={}
    for id,event in pairs(entry.events) do if event.revision<=revision then retired[#retired+1]=id end end
    for i=1,#retired do entry.events[retired[i]]=nil; entry.count=entry.count-1 end
    retired={}
    for rowKey,expected in pairs(entry.uncertain) do if expected<=revision then retired[#retired+1]=rowKey end end
    for i=1,#retired do entry.uncertain[retired[i]]=nil; entry.uncertainCount=entry.uncertainCount-1 end
end
return Overlay

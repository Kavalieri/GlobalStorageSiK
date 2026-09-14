-- One receipt per dispatched microbatch. A lost ACK never authorizes moving
-- another unit. Old sequences stay retired after bounded receipt eviction.
require "GS_RoutingProtocol"
require "GS_RoutingTransactions"
local R={}
GlobalStorageSiK.WithdrawReceipts=R
local actors={}
local function prune(player)
    local live={[player]=true}
    if getOnlinePlayers then
        local list=getOnlinePlayers()
        if list then for i=0,list:size()-1 do live[list:get(i)]=true end end
    end
    if getNumActivePlayers and getSpecificPlayer then
        for i=0,getNumActivePlayers()-1 do local p=getSpecificPlayer(i);if p then live[p]=true end end
    end
    local retired,count={},0
    for p in pairs(actors) do if not live[p] then retired[#retired+1]=p else count=count+1 end end
    for i=1,#retired do actors[retired[i]]=nil end
    return count
end
function R.begin(player,args,networkId)
    local GS=GlobalStorageSiK
    local epoch=GS.RoutingTransactions.epoch(player)
    local sequence=args.withdrawSequence
    if type(args.withdrawId)~="string" or #args.withdrawId<1 or #args.withdrawId>96
        or args.withdrawEpoch~=epoch or not epoch or type(sequence)~="number"
        or sequence<1 or sequence>2147483647 or sequence~=math.floor(sequence) then return "invalid_request" end
    local clean,signature=GS.RoutingProtocol.copy(args)
    if not clean then return "invalid_request" end
    local state=actors[player]
    if not state or state.epoch~=epoch then
        if prune(player)>=128 and not state then return "receipt_limit" end
        state={epoch=epoch,high=0,entries={},order={},bytes=0};actors[player]=state
    end
    local entry=state.entries[args.withdrawId]
    if entry then
        if entry.signature~=signature or entry.networkId~=networkId then return "request_conflict" end
        if entry.result then return "replayed",GS.RoutingProtocol.copy(entry.result) end
        return "request_pending"
    end
    if sequence<=state.high then return "request_retired" end
    local bytes=#signature+4096
    while #state.order>0 and (#state.order>=64 or state.bytes+bytes>131072) do
        local id=table.remove(state.order,1)
        local old=state.entries[id]
        if old then state.bytes=state.bytes-old.bytes;state.entries[id]=nil end
    end
    if bytes>131072 then return "receipt_limit" end
    state.high=sequence
    state.entries[args.withdrawId]={networkId=networkId,signature=signature,bytes=bytes}
    state.active=args.withdrawId
    state.order[#state.order+1]=args.withdrawId;state.bytes=state.bytes+bytes
    return "new"
end
function R.capture(player,payload)
    local state=actors[player]
    local entry=state and payload and state.entries[payload.withdrawId]
    if not entry or entry.result or state.active~=payload.withdrawId then return end
    state.active=nil
    local copy,signature=GlobalStorageSiK.RoutingProtocol.copy(payload)
    if copy and #signature<=4096 then entry.result=copy end
    -- If a response exceeds the receipt budget, leave it pending. A retry
    -- must fail closed rather than execute an uncertain physical mutation.
end
function R.finish(player)
    if actors[player] then actors[player].active=nil end
end
return R

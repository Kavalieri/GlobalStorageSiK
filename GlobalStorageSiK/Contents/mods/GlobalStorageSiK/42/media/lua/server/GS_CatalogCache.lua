-- Bounded references to immutable prepared catalogs. Accounting is deliberately
-- conservative and does not depend on whether the Index still owns these rows.
local Cache={}
GlobalStorageSiK.CatalogCache=Cache
local entries,total,count,clock={},0,0,0
local MAX_BYTES,ENTRY_BYTES,MAX_ENTRIES=32*1024*1024,16*1024*1024,128
local function remove(key)
    local entry=entries[key]
    if entry then total=total-entry.bytes;count=count-1;entries[key]=nil end
end
function Cache.get(key)
    local entry=entries[key]
    if entry then clock=clock+1;entry.usedAt=clock end
    return entry
end
function Cache.put(key,entry)
    local stats=entry.stats or {}
    local bytes=math.max(4096,tonumber(stats.cacheBytes) or 0,
        tonumber(stats.retainedBytes) or 0,#(entry.rows or {})*1024)
    if bytes~=bytes or bytes>ENTRY_BYTES then return false,"catalog_budget" end
    local previous=entries[key]
    if previous and previous.revision>entry.revision then return false,"older_revision" end
    remove(key)
    while total+bytes>MAX_BYTES or count>=MAX_ENTRIES do
        local oldest,age=nil,math.huge
        for candidate,value in pairs(entries) do
            if value.usedAt<age then oldest,age=candidate,value.usedAt end
        end
        if not oldest then return false,"catalog_budget" end
        remove(oldest)
    end
    clock=clock+1;entry.usedAt=clock;entry.bytes=bytes
    entries[key]=entry;total=total+bytes;count=count+1
    return true
end
function Cache.invalidate(networkId)
    local retired={}
    for key,entry in pairs(entries) do
        if entry.networkId==networkId then retired[#retired+1]=key end
    end
    for i=1,#retired do remove(retired[i]) end
end
function Cache.diagnostics() return {entries=count,retainedBytes=total,maxBytes=MAX_BYTES} end
return Cache

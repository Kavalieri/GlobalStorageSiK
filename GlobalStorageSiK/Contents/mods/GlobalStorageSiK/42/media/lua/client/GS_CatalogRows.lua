-- Dense compatibility view with keyed O(changed roots) updates. Ordering is
-- presentation-owned. Deletion swaps the last reference, never scans rows.
local Rows={}
function Rows.new(rows)
    local store={rows=rows,byKey={},categories={}}
    for i=1,#rows do
        local row=rows[i]
        if type(row.rowKey)~="string" or store.byKey[row.rowKey] then return nil,"catalog_keys" end
        store.byKey[row.rowKey]=i
        local category=row.vanillaKey or row.category
        if type(category)=="string" then store.categories[category]=(store.categories[category] or 0)+1 end
    end
    return store
end
function Rows.patch(store,changed,removed,expectedCount)
    local seen,count={},#store.rows
    for i=1,#changed do
        local key=changed[i].rowKey
        if type(key)~="string" or seen[key] then return nil,"catalog_keys" end
        seen[key]=true;if not store.byKey[key] then count=count+1 end
    end
    for i=1,#removed do
        local key=removed[i]
        if type(key)~="string" or seen[key] or not store.byKey[key] then return nil,"catalog_keys" end
        seen[key]=true;count=count-1
    end
    if count~=expectedCount then return nil,"catalog_incomplete" end
    local journal={}
    local function write(t,k,value)
        journal[#journal+1]={t,k,t[k]};t[k]=value
    end
    local function category(row,delta)
        local key=row and (row.vanillaKey or row.category)
        if type(key)=="string" then
            local value=(store.categories[key] or 0)+delta
            write(store.categories,key,value>0 and value or nil)
        end
    end
    for i=1,#removed do
        local key=removed[i];local at=store.byKey[key];local last=#store.rows
        category(store.rows[at],-1)
        if at~=last then
            local row=store.rows[last];write(store.rows,at,row);write(store.byKey,row.rowKey,at)
        end
        write(store.rows,last,nil);write(store.byKey,key,nil)
    end
    for i=1,#changed do
        local row=changed[i];local at=store.byKey[row.rowKey] or #store.rows+1
        category(store.rows[at],-1);category(row,1)
        write(store.rows,at,row);write(store.byKey,row.rowKey,at)
    end
    local used=false
    return function()
        if used then return false end;used=true
        for i=#journal,1,-1 do local change=journal[i];change[1][change[2]]=change[3] end
        return true
    end
end
return Rows

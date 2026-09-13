-- Shared immutable index construction, followed by recipient-specific delta.
local Preparation = {}
GlobalStorageSiK.CatalogPreparation = Preparation
local shared, count = {}, 0
local function now() return getTimestampMs and getTimestampMs() or 0 end
local function errorFor(stage,cause) return {stage=stage,cause=tostring(cause)} end
local RETAIN_MS,MAX_BYTES=30000,32*1024*1024
local function remove(key,build,reason)
    if build.index and build.phase~="ready" and GlobalStorageSiK.Index.cancelCatalogBuild then
        GlobalStorageSiK.Index.cancelCatalogBuild(build.index)
    end
    if shared[key]==build then shared[key]=nil;count=count-1 end
    if GlobalStorageSiK.Log then GlobalStorageSiK.Log.debug("CatalogTransport","preparation_retired",
        "network="..tostring(build.networkId).." phase="..tostring(build.phase).." reason="..reason) end
end
function Preparation.prune()
    local retired,total={},0
    for key,build in pairs(shared) do
        if build.refs==0 and (now()<build.usedAt or now()-build.usedAt>=RETAIN_MS or build.error) then
            retired[#retired+1]=key
        else total=total+math.max(4096,build.stats.retainedBytes or 0) end
    end
    for i=1,#retired do local key=retired[i];remove(key,shared[key],"retention_expired") end
    return total
end
local function advanceShared(build,maxWork,maxMillis)
    local Index=GlobalStorageSiK.Index
    local start,used=now(),0
    local stats=build.stats
    stats.workLastStep=0
    if build.error then return 0 end
    if Index.getClassificationStamp()~=build.classificationStamp then
        build.error=errorFor("catalog_build.categories","catalog_stale_classification");return 0
    end
    if build.phase=="index" then
        local done,rows,indexStats=Index.stepCatalogBuild(build.index,maxWork,maxMillis)
        stats=indexStats or stats;build.stats=stats
        used=math.min(maxWork,stats.workLastStep or maxWork)
        if build.index.error then build.error=build.index.error;return used end
        if not done then return used end
        build.rows=rows;build.phase="categories"
    end
    while used<maxWork and (used==0 or now()-start<maxMillis) and build.phase=="categories" do
        local row=build.rows[build.at]
        if row then
            local category=row.vanillaKey or row.category
            if type(category)=="string" and category~="" and not build.seenCategories[category]
                and GlobalStorageSiK.CategoryResolution.isVanillaKey(category) then
                build.seenCategories[category]=true;build.categories[#build.categories+1]=category
            end
            build.at=build.at+1
        else
            build.catalogCategories=GlobalStorageSiK.Categories.buildCatalog(build.networkId,{},build.categories)
            if Index.getClassificationStamp()~=build.classificationStamp then
                build.error=errorFor("catalog_build.categories","catalog_stale_classification");return used
            end
            build.phase="ready"
            if build.publish then build.publish(build.rows,build.categories,build.catalogCategories,stats) end
        end
        used=used+1
    end
    stats.workLastStep=used
    return used
end
function Preparation.update()
    Preparation.prune()
    local selected
    for _,build in pairs(shared) do
        if build.refs==0 and build.phase~="ready" and not build.error
            and (not selected or (build.backgroundAt or 0)<(selected.backgroundAt or 0)) then selected=build end
    end
    if selected then
        selected.backgroundAt=now()
        local ok,reason=pcall(advanceShared,selected,256,1)
        if not ok then selected.error=errorFor("catalog_build.background",reason) end
    end
end
function Preparation.create(player,networkId,scope,revision,base,notModified,cached,publish)
    local retained=Preparation.prune()
    local Index=GlobalStorageSiK.Index
    local classificationStamp=Index.getClassificationStamp()
    local key=tostring(networkId).."\30"..tostring(scope).."\30"..tostring(revision)
        .."\30"..tostring(classificationStamp)
    local build=shared[key]
    if not build then
        build={refs=0,networkId=networkId,revision=revision,classificationStamp=classificationStamp,publish=publish,createdAt=now(),usedAt=now(),
            phase="index",at=1,categories={},seenCategories={},
            stats={workLastStep=0,retainedBytes=4096}}
        if count>=64 or retained>=MAX_BYTES then
            build.error=errorFor("catalog_build.capacity","catalog_busy")
        elseif cached then
            build.rows,build.categories=cached.rows,cached.categories or {}
            build.catalogCategories=cached.catalogCategories
            build.phase=build.catalogCategories and "ready" or "categories"
        else
            local ok,job=pcall(Index.beginCatalogBuild,networkId,player,nil,revision)
            if ok and job then build.index=job
            else build.error=errorFor("catalog_build.begin",job) end
        end
        -- Rejected requests must not consume a retained slot themselves.
        if not build.error then shared[key]=build; count=count+1 end
    end
    build.refs=build.refs+1
    local localState={phase="base",at=1,old={},new={},changed={},removed={},released=false}
    local wrapper={}
    wrapper.startedAt=now()
    wrapper.classificationStamp=classificationStamp
    local function release(reason)
        if localState.released then return end
        localState.released=true
        build.refs=build.refs-1
        build.usedAt=now()
        if build.refs==0 then
            -- Session closures only detach. Immutable preparation survives a
            -- compatible reopen; retention is bounded independently of players.
            if build.error then remove(key,build,reason or "failed") end
        end
    end
    wrapper.cancel=release
    wrapper.error=function() return build.error or localState.error end
    wrapper.diagnostics=function()
        local job=build.index
        return {phase=job and (job.nodeWork and job.nodeWork.phase or job.phase) or build.phase,
            nodeIndex=job and job.nodeIndex,totalNodes=job and #(job.captured or {}),
            remaining=job and math.max(0,#(job.captured or {})-(job.nodeIndex or 1)+1),
            work=build.stats.workTotal or 0,baseRetained=base~=nil}
    end
    local function classificationValid()
        if Index.getClassificationStamp()==build.classificationStamp then return true end
        build.error=errorFor("catalog_build.categories","catalog_stale_classification")
        return false
    end
    wrapper.step=function(maxWork,maxMillis)
        local start,used=now(),0
        build.usedAt=start
        local stats=build.stats
        stats.workLastStep=0
        if localState.released then localState.error=errorFor("catalog_build.session","cancelled"); return false end
        if build.error or not classificationValid() then return false end
        if Preparation.prune()>MAX_BYTES then build.error=errorFor("catalog_build.memory","catalog_busy");return false end
        used=advanceShared(build,maxWork,maxMillis);stats=build.stats
        if build.error then return false,nil,nil,stats end
        if build.phase~="ready" then stats.workLastStep=used; return false,nil,nil,stats end
        if not base or notModified then
            stats.workLastStep=used
            local payload={itemTypeCount=#build.rows,categories=build.catalogCategories}
            if not notModified then payload.items=build.rows end
            return true,payload,build.rows,stats
        end
        while used<maxWork and now()-start<maxMillis and localState.phase~="ready" do
            if localState.phase=="base" then
                local row=base.rows[localState.at]
                if row then localState.old[row.rowKey]=row; localState.at=localState.at+1
                else localState.at=1; localState.phase="current" end
            elseif localState.phase=="current" then
                local row=build.rows[localState.at]
                if row then
                    localState.new[row.rowKey]=true
                    local old=localState.old[row.rowKey]
                    if not old or Index.rowSignature(old)~=Index.rowSignature(row) then
                        localState.changed[#localState.changed+1]=row
                    end
                    localState.at=localState.at+1
                else localState.at=1; localState.phase="removed" end
            elseif localState.phase=="removed" then
                local row=base.rows[localState.at]
                if row then
                    if not localState.new[row.rowKey] then localState.removed[#localState.removed+1]=row.rowKey end
                    localState.at=localState.at+1
                else localState.phase="ready" end
            end
            used=used+1
        end
        stats.workLastStep=used
        stats.retainedBytes=math.max(stats.retainedBytes or 4096,
            #build.rows*512+#(base.rows or {})*192)
        if localState.phase~="ready" then return false,nil,nil,stats end
        return true,{catalogDelta=true,baseRevision=base.revision,
            changedRows=localState.changed,removedRowKeys=localState.removed,
            itemTypeCount=#build.rows,categories=build.catalogCategories},build.rows,stats
    end
    return wrapper
end
return Preparation

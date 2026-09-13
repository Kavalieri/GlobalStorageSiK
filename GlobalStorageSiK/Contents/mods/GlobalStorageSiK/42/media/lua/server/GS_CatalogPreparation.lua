-- Shared immutable index construction, followed by recipient-specific delta.
local Preparation = {}
GlobalStorageSiK.CatalogPreparation = Preparation
local shared, count = {}, 0
local function now() return getTimestampMs and getTimestampMs() or 0 end
local function errorFor(stage,cause) return {stage=stage,cause=tostring(cause)} end
function Preparation.create(player,networkId,scope,revision,base,notModified,cached,publish)
    local Index=GlobalStorageSiK.Index
    local classificationStamp=Index.getClassificationStamp()
    local key=tostring(networkId).."\30"..tostring(scope).."\30"..tostring(revision)
        .."\30"..tostring(classificationStamp)
    local build=shared[key]
    if not build then
        build={refs=0,networkId=networkId,classificationStamp=classificationStamp,
            phase="index",at=1,categories={},seenCategories={},
            stats={workLastStep=0,retainedBytes=4096}}
        if cached then
            build.rows,build.categories=cached.rows,cached.categories or {}
            build.catalogCategories=cached.catalogCategories
            build.phase=build.catalogCategories and "ready" or "categories"
        elseif count>=64 then
            build.error=errorFor("catalog_build.capacity","catalog_busy")
        else
            local ok,job=pcall(Index.beginCatalogBuild,networkId,player,nil,revision)
            if ok and job then build.index=job
            else build.error=errorFor("catalog_build.begin",job) end
        end
        shared[key]=build; count=count+1
    end
    build.refs=build.refs+1
    local localState={phase="base",at=1,old={},new={},changed={},removed={},released=false}
    local wrapper={}
    local function release()
        if localState.released then return end
        localState.released=true
        build.refs=build.refs-1
        if build.refs==0 then
            if build.index and build.phase~="ready" then
                if Index.cancelCatalogBuild then Index.cancelCatalogBuild(build.index)
                else build.index.cancelled=true end
            end
            if shared[key]==build then shared[key]=nil; count=count-1 end
        end
    end
    wrapper.cancel=release
    wrapper.error=function() return build.error or localState.error end
    local function classificationValid()
        if Index.getClassificationStamp()==build.classificationStamp then return true end
        build.error=errorFor("catalog_build.categories","catalog_stale_classification")
        return false
    end
    wrapper.step=function(maxWork,maxMillis)
        local start,used=now(),0
        local stats=build.stats
        stats.workLastStep=0
        if localState.released then localState.error=errorFor("catalog_build.session","cancelled"); return false end
        if build.error or not classificationValid() then return false end
        if build.phase=="index" then
            local done,rows,indexStats=Index.stepCatalogBuild(build.index,maxWork,maxMillis)
            stats=indexStats or stats; build.stats=stats
            used=math.min(maxWork,stats.workLastStep or maxWork)
            if build.index.error then build.error=build.index.error; return false,nil,nil,stats end
            if not done then return false,nil,nil,stats end
            build.rows=rows; build.phase="categories"
        end
        if not classificationValid() then return false,nil,nil,stats end
        while used<maxWork and now()-start<maxMillis and build.phase=="categories" do
            local row=build.rows[build.at]
            if row then
                local category=row.vanillaKey or row.category
                local resolution=GlobalStorageSiK.CategoryResolution
                if type(category)=="string" and category~="" and not build.seenCategories[category]
                    and resolution.isVanillaKey(category) then
                    build.seenCategories[category]=true
                    build.categories[#build.categories+1]=category
                end
                build.at=build.at+1
            else
                build.catalogCategories=GlobalStorageSiK.Categories.buildCatalog(networkId,{},build.categories)
                if not classificationValid() then return false,nil,nil,stats end
                build.phase="ready"
                if publish then publish(build.rows,build.categories,build.catalogCategories,stats) end
            end
            used=used+1
        end
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

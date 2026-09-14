-- Product presentation transaction over affected keys. Table owns ordering and
-- projection; no full visible array is built by an ordinary catalog delta.
local P={}
GlobalStorageSiK.KeyedPresentation=P
local maps={"_expandedKeys","_detailPageByKey","_detailPending","_detailVisualPages"}
local scalars={"_detailVisualNetwork","_detailVisualScope","_withdrawExpectedRevision","_withdrawExpectedNetwork"}
function P.build(panel,terminal,items,changed,removed,derive,ports)
	local previous=panel._gsKeyedPresentation
	local affected,sources,sourceTouched={},{},{}
	for i=1,#(changed or {}) do
		local row=changed[i];local key=ports.key(row)
		if not key or sourceTouched[key] then return nil,"invalid_changed_key" end
		affected[key],sourceTouched[key],sources[key]=true,true,row
	end
	for i=1,#(removed or {}) do
		local key=removed[i]
		if sourceTouched[key] then return nil,"conflicting_catalog_key" end
		affected[key],sourceTouched[key]=true,true
	end
	-- A full recovery/classification response may replace the complete image.
	if derive then
		local live={}
		for i=1,#items do
			local key=ports.key(items[i])
			if not key or live[key] then return nil,"invalid_catalog_keys" end
			live[key]=true;affected[key]=true;sourceTouched[key]=true;sources[key]=items[i]
		end
		for key in pairs(previous.sourceByKey) do
			if not live[key] then affected[key]=true;sourceTouched[key]=true;sources[key]=nil end
		end
	end
	for key in pairs(previous.pendingKeys or {}) do affected[key]=true end
	for key in pairs(ports.pendingKeys or {}) do affected[key]=true end
	local old,scratch,oldScalars,newScalars={},{},{},{}
	for i=1,#maps do
		local field=maps[i];old[field]=panel[field];scratch[field]={}
		for key in pairs(affected) do scratch[field][key]=old[field] and old[field][key] end
		panel[field]=scratch[field]
	end
	for i=1,#scalars do oldScalars[i]=panel[scalars[i]] end
	local oldRendered=panel._detailRendered;panel._detailRendered={}
	local roots,upserts,removeKeys,requests={},{},{},{}
	local ok,reason=pcall(function()
		for key in pairs(affected) do
			local source=sourceTouched[key] and sources[key] or previous.sourceByKey[key]
			if sourceTouched[key] and not sources[key] then source=nil end
			local root=source and ports.project(source,requests,previous.sortKey,previous.sortAsc) or nil
			roots[key]=root
			if root then upserts[#upserts+1]=root
			elseif previous.rootsByKey[key] then removeKeys[#removeKeys+1]=key end
			if not source then
				for i=1,#maps do panel[maps[i]][key]=nil end
			end
		end
	end)
	for i=1,#scalars do newScalars[i]=panel[scalars[i]];panel[scalars[i]]=oldScalars[i] end
	for i=1,#maps do scratch[maps[i]]=panel[maps[i]];panel[maps[i]]=old[maps[i]] end
	panel._detailRendered=oldRendered
	if not ok then return nil,reason end
	local journal,committed={},false
	local function set(map,key,value)
		journal[#journal+1]={map=map,key=key,value=map[key]};map[key]=value
	end
	local model={keyedRoots=true,patch={upserts=upserts,removeKeys=removeKeys},emptyText=ports.emptyText}
	function model.undo()
		if not committed then return end
		for i=#journal,1,-1 do local j=journal[i];j.map[j.key]=j.value end
		committed=false
	end
	function model.commit()
		committed=true
		for key in pairs(affected) do
			if sourceTouched[key] then set(previous.sourceByKey,key,sources[key]) end
			set(previous.rootsByKey,key,roots[key])
			set(previous.pendingKeys,key,roots[key] and roots[key]._gsConfirmedPending and true or nil)
			for i=1,#maps do
				local field=maps[i]
				if not panel[field] then set(panel,field,{}) end
				set(panel[field],key,scratch[field] and scratch[field][key])
			end
		end
		for i=1,#scalars do set(panel,scalars[i],newScalars[i]) end
		-- Legacy arrays are explicit snapshots, never authority in keyed mode.
		set(panel,"_lastItems",nil);set(panel,"_lastItemRoots",nil);set(panel,"_itemsCatalog",nil)
		for i=1,#requests do
			local r=requests[i]
			if not ports.request(r.parent,r.page) then set(panel._detailPending,r.key,nil) end
		end
		return true
	end
	return model
end
return P

-- Opt-in export of already confirmed snapshots, outside the timed opening.
require "GS_Config"
local Codec=require "GS_CatalogCodec"
local Oracle={}
GlobalStorageSiK.InitialLoadOracle=Oracle
local job,lastStarted,serial=nil,nil,0
local function now() return getTimestampMs and getTimestampMs() or 0 end
local function enabled()
	local sandbox=GlobalStorageSiK.Sandbox
	return sandbox and sandbox.debugMode() and sandbox.debugCategoryEnabled("CatalogTransport")
end
local function quote(value)
	return '"'..value:gsub('[%c\\"]',function(c) return string.format('\\u%04x',string.byte(c)) end)..'"'
end
local function tokensText(tokens,first,last)
	local parts={}
	for i=first,last do
		local value=tokens[i]
		parts[#parts+1]=type(value)=="string" and quote(value) or tostring(value)
	end
	return "["..table.concat(parts,",").."]\n"
end
local update
local function metaText(meta)
	local parts={}
	for key,value in pairs(meta) do parts[#parts+1]=quote(key)..":"..(type(value)=="string" and quote(value) or tostring(value)) end
	table.sort(parts)
	return "{"..table.concat(parts,",").."}"
end
local function stop(complete,reason)
	local current=job
	if not current then return end
	job=nil
	if Events and Events.OnTick then Events.OnTick.Remove(update) end
	local written=true
	written=pcall(function()
		current.writer:write('{"schemaVersion":"initial-load-oracle/1.0","complete":'..tostring(complete==true)..',"role":'
			..quote(current.role)..',"meta":'..metaText(current.meta)..',"reason":'..quote(tostring(reason or ""))
			..',"tokenCount":'..current.writtenTokens..',"writeMaxMs":'..current.writeMaxMs
			..',"encodeMaxMs":'..current.encodeMaxMs
			..',"writeMaxBytesBound":'..current.writeMaxBytes
			..',"exportElapsedMs":'..math.max(0,now()-current.started)..'}\n')
	end)
	local closed=pcall(function() current.writer:close() end)
	Oracle.lastResult={complete=complete and written and closed,reason=reason or "",path=current.path,role=current.role}
	local log=GlobalStorageSiK.Log
	if log then log.debug("CatalogTransport","oracle_export",current.role.." complete="..tostring(Oracle.lastResult.complete).." reason="..tostring(reason or "")) end
end
update=function()
	local current=job
	if not current then return end
	local ok,reason=pcall(function()
		if not enabled() or not current.valid() then error("oracle_changed",0) end
		if now()-current.started>120000 then error("oracle_timeout",0) end
		if not current.encoded then
			local encodeStarted=now()
			local result,encodeReason,done=Codec.stepEncode(current.encoder,128)
			current.encodeMaxMs=math.max(current.encodeMaxMs,now()-encodeStarted)
			if encodeReason then error(encodeReason,0) end
			if done then current.encoded=result;current.encoder=nil end
			return
		end
		local tokens=current.encoded.chunks[current.part]
		if not tokens then stop(true);return end
		local last,cost=current.at-1,12
		while last<#tokens and last<current.at+31 do
			local value=tokens[last+1]
			local piece=type(value)=="string" and quote(value) or tostring(value)
			local following=cost+(#piece+1)*4
			if following>32768 then break end
			cost=following;last=last+1
		end
		if last<current.at then error("oracle_atom_budget",0) end
		local text=tokensText(tokens,current.at,last)
		-- Conservative UTF-16/UTF-8 bound, including JSON escaping.
		current.bytes=current.bytes+#text*4
		if current.bytes>64*1024*1024 then error("oracle_file_budget",0) end
		local writeStarted=now()
		current.writer:write(text)
		current.writeMaxMs=math.max(current.writeMaxMs,now()-writeStarted)
		current.writeMaxBytes=math.max(current.writeMaxBytes,#text*4)
		current.writtenTokens=current.writtenTokens+last-current.at+1
		current.at=last+1
		if current.at>#tokens then current.part=current.part+1;current.at=1 end
	end)
	if not ok then stop(false,tostring(reason):sub(1,128)) end
end
function Oracle.begin(role,image,valid)
	local validOk,stillValid=pcall(function() return type(valid)=="function" and valid() end)
	if role~="server" and role~="client" then return false,"oracle_role" end
	if not enabled() or job or not Events or not Events.OnTick or not getFileWriter
		or not validOk or not stillValid then return false,"oracle_unavailable" end
	if lastStarted and now()>=lastStarted and now()-lastStarted<60000 then return false,"oracle_throttle" end
	if type(image)~="table" or not image.meta or image.meta.snapshotCertified~=true
		or image.meta.reconcilePending==true then return false,"oracle_uncertified" end
	local meta={}
	for _,key in ipairs({"openSeq","playerNum","networkId","replicaEpoch","catalogScope","topologySequence",
		"manifestToken","inventoryRevision","initialLoadProfile","initialLoadProfileHash","initialLoadRunId"}) do
		meta[key]=image.meta[key]
	end
	if type(meta.catalogScope)~="string" or #meta.catalogScope>1024 then return false,"oracle_scope" end
	local encoder,reason=Codec.beginEncode({meta=meta,nodes=image.nodes},24000)
	if not encoder then return false,reason end
	serial=serial+1
	local path=string.format("SiKDiagnostics/GlobalStorageSiK/initial-load/oracle-%s-%02d.jsonl",role,serial%4)
	local opened,writer=pcall(getFileWriter,path,true,false)
	if not opened or not writer then return false,"oracle_writer" end
	lastStarted=now()
	job={role=role,writer=writer,path=path,encoder=encoder,valid=valid,started=now(),bytes=0,part=1,at=1,
		meta=meta,writtenTokens=0,writeMaxMs=0,encodeMaxMs=0,writeMaxBytes=0}
	Events.OnTick.Add(update)
	return true,path
end
function Oracle.busy() return job~=nil end
function Oracle.cancel() stop(false,"oracle_cancelled") end
return Oracle

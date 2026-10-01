-- Opt-in export of already confirmed snapshots, outside the timed opening.
require "GS_Config"
local Codec=require "GS_CatalogCodec"
local Results=require "GS_InitialLoadDiagnosticResults"
local Oracle={}
Oracle.exportTimeoutMs=120000
Oracle.replyTimeoutMs=135000 -- Includes a bounded terminal-response grace period.
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
local function report(role,status,reason,meta,requestId,path,callback)
	local result=Results.record(role,status,reason,meta,requestId,path)
	Oracle.lastDiagnosticResult=result
	if callback and result then pcall(callback,result) end
	return result
end
function Oracle.reject(role,reason,meta,requestId,callback)
	report(role,"rejected",reason,meta,requestId,nil,callback)
	return false,reason
end
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
	if Events and Events.OnTick then pcall(Events.OnTick.Remove,update) end
	local written=true
	written=pcall(function()
		current.writer:write('{"schemaVersion":"initial-load-oracle/1.0","complete":'..tostring(complete==true)..',"role":'
			..quote(current.role)..',"requestId":'..quote(Results.requestId(current.requestId) and current.requestId or "")
			..',"meta":'..metaText(current.meta)..',"reason":'..quote(tostring(reason or ""))
			..',"tokenCount":'..current.writtenTokens..',"writeMaxMs":'..current.writeMaxMs
			..',"encodeMaxMs":'..current.encodeMaxMs
			..',"writeMaxBytesBound":'..current.writeMaxBytes
			..',"exportElapsedMs":'..math.max(0,now()-current.started)..'}\n')
	end)
	local closed=pcall(function() current.writer:close() end)
	local terminalReason=not written and "oracle_footer_write" or not closed and "oracle_close" or reason or ""
	Oracle.lastResult={complete=complete and written and closed,reason=terminalReason,path=current.path,role=current.role}
	local diagnostics=Results.context(current.diagnostics)
	diagnostics.writerStatus=not written and "write_failed" or not closed and "close_failed" or "closed"
	diagnostics.exportElapsedMs=math.max(0,now()-current.started);diagnostics.tokenCount=current.writtenTokens
	diagnostics.writeMaxMs=current.writeMaxMs;diagnostics.encodeMaxMs=current.encodeMaxMs
	diagnostics.writeMaxBytesBound=current.writeMaxBytes
	report(current.role,Oracle.lastResult.complete and "complete" or "failed",terminalReason,diagnostics,
		current.requestId,current.path,current.callback)
	local log=GlobalStorageSiK.Log
	if log then log.debug("CatalogTransport","oracle_export",current.role.." complete="..tostring(Oracle.lastResult.complete).." reason="..tostring(reason or "")) end
end
update=function()
	local current=job
	if not current then return end
	local ok,reason=pcall(function()
		if not enabled() then current.diagnostics.validityStatus="disabled";error("oracle_disabled",0) end
		local validOk,valid=pcall(current.valid)
		current.diagnostics.validityStatus=not validOk and "error" or valid and "valid" or "invalid"
		if not validOk then error("oracle_validity_error",0) end
		if not valid then error("oracle_changed",0) end
		if now()<current.started then error("oracle_clock_changed",0) end
		if now()-current.started>=Oracle.exportTimeoutMs then error("oracle_timeout",0) end
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
function Oracle.begin(role,image,valid,requestId,callback,diagnostics)
	local details=Results.context(diagnostics or (type(image)=="table" and image.meta))
	details.writerStatus="not_attempted"
	local function reject(reason) return Oracle.reject(role,reason,details,requestId,callback) end
	if role~="server" and role~="client" then return reject("oracle_role") end
	if not enabled() then return reject("oracle_disabled") end
	if job then return reject("oracle_busy") end
	if not Events or not Events.OnTick or type(Events.OnTick.Add)~="function" or type(Events.OnTick.Remove)~="function" then return reject("oracle_events") end
	if not getFileWriter then return reject("oracle_writer") end
	if lastStarted and now()>=lastStarted and now()-lastStarted<60000 then return reject("oracle_throttle") end
	if type(image)~="table" or type(image.meta)~="table" then return reject("oracle_image") end
	if image.meta.snapshotCertified~=true then return reject("oracle_uncertified") end
	if image.meta.reconcilePending==true then return reject("oracle_reconcile_pending") end
	local validOk,stillValid=pcall(function() return type(valid)=="function" and valid() end)
	details.validityStatus=not validOk and "error" or stillValid and "valid" or "invalid"
	if not validOk then return reject("oracle_validity_error") end
	if not stillValid then return reject("oracle_validity_failed") end
	local meta={}
	for _,key in ipairs({"openSeq","playerNum","networkId","replicaEpoch","catalogScope","topologySequence",
		"manifestToken","inventoryRevision","initialLoadProfile","initialLoadProfileHash","initialLoadRunId"}) do
		meta[key]=image.meta[key]
	end
	if type(meta.catalogScope)~="string" or #meta.catalogScope>1024 then return reject("oracle_scope") end
	local encoder,reason=Codec.beginEncode({meta=meta,nodes=image.nodes},24000)
	if not encoder then return reject(reason) end
	serial=serial+1
	local path=string.format("SiKDiagnostics/GlobalStorageSiK/initial-load/oracle-%s-%02d.jsonl",role,serial%4)
	local opened,writer=pcall(getFileWriter,path,true,false)
	if not opened or not writer then details.writerStatus="unavailable";return reject("oracle_writer") end
	lastStarted=now()
	job={role=role,writer=writer,path=path,encoder=encoder,valid=valid,started=now(),bytes=0,part=1,at=1,
		meta=meta,writtenTokens=0,writeMaxMs=0,encodeMaxMs=0,writeMaxBytes=0,
		diagnostics=details,requestId=requestId,callback=callback}
	local attached=pcall(Events.OnTick.Add,update)
	if not attached then stop(false,"oracle_events");return false,"oracle_events" end
	details.writerStatus="opened"
	report(role,"started","",details,requestId,path,callback)
	return true,path
end
function Oracle.busy() return job~=nil end
function Oracle.cancel(role,requestId)
	if not job or (role and job.role~=role) or (requestId and job.requestId~=requestId) then return false end
	stop(false,"oracle_cancelled");return true
end
return Oracle

-- Explicit research requests only. Fixed-size results; never scans inventory.
local Results={}
GlobalStorageSiK.InitialLoadDiagnosticResults=Results
local serial,lastWrite,pending,attached=0,nil,{},false
local fields={"openSeq","playerNum","networkId","replicaEpoch","catalogScope","topologySequence",
	"manifestToken","inventoryRevision","snapshotRevision","snapshotCertified","reconcilePending",
	"initialLoadProfile","initialLoadProfileHash","initialLoadRunId","completed","hasComplete","partial",
	"contextCurrent","accessAllowed","cacheAccepted","confirmedToken","roundActive","requestPending",
	"readyPending","retryPending","refreshPending","transportBusy","globalBusy","writerStatus","validityStatus",
	"identityComplete","exportElapsedMs","tokenCount","writeMaxMs","encodeMaxMs","writeMaxBytesBound"}
local function now() return getTimestampMs and getTimestampMs() or 0 end
local function quote(value)
	return '"'..value:gsub('[%c\\"]',function(c) return string.format('\\u%04x',string.byte(c)) end)..'"'
end
local function json(value)
	local parts={}
	for key,item in pairs(value) do
		parts[#parts+1]=quote(key)..":"..(type(item)=="string" and quote(item) or tostring(item))
	end
	table.sort(parts)
	return "{"..table.concat(parts,",").."}\n"
end
function Results.context(meta)
	local out={}
	for _,key in ipairs(fields) do
		local value=meta and meta[key]
		if type(value)=="boolean" or (type(value)=="number" and value==value and math.abs(value)<9007199254740992) then out[key]=value
		elseif type(value)=="string" and #value<=(key=="catalogScope" and 1024 or 512) then out[key]=value end
	end
	return out
end
function Results.requestId(value)
	return type(value)=="string" and #value>0 and #value<=96 and value:match("^[%w:._%-]+$")~=nil
end
local flush
local function detach()
	if attached and Events and Events.OnTick then pcall(Events.OnTick.Remove,flush) end
	attached=false
end
local function write(record)
	local text=json(record)
	if #text>8192 then record.persisted=false;record.persistenceReason="result_budget";return end
	local path=record.resultPath
	local opened,writer=pcall(function() return getFileWriter and getFileWriter(path,true,false) end)
	if not opened or not writer then record.persisted=false;record.persistenceReason="result_writer_unavailable";return end
	local written=pcall(function() writer:write(text) end)
	local closed=pcall(function() writer:close() end)
	record.persisted=written and closed
	record.persistenceReason=record.persisted and "" or "result_write_or_close_failed"
end
flush=function()
	local selected
	for _,record in pairs(pending) do
		if not selected or record.sequence<selected.sequence then selected=record end
	end
	if not selected then detach();return end
	local timestamp=now()
	if lastWrite and timestamp>=lastWrite and timestamp-lastWrite<1000 then return end
	pending[selected.role]=nil;lastWrite=timestamp;write(selected)
	local remaining=false
	for _ in pairs(pending) do remaining=true;break end
	if not remaining then detach() end
end
function Results.record(role,status,reason,meta,requestId,oraclePath)
	if role~="client" and role~="server" then role="unknown" end
	serial=serial+1
	local record=Results.context(meta)
	record.schemaVersion="initial-load-oracle-result/1.0";record.operation="oracle"
	record.role=role;record.status=status;record.reason=tostring(reason or ""):sub(1,128)
	record.terminal=status=="complete" or status=="failed" or status=="rejected"
	record.requestId=Results.requestId(requestId) and requestId or ""
	record.generatedAtMs=now();record.sequence=serial
	record.slot=serial%4
	record.oraclePath=type(oraclePath)=="string" and oraclePath:sub(1,256) or ""
	record.resultPath=string.format("SiKDiagnostics/GlobalStorageSiK/initial-load/oracle-result-%s-%02d.json",role,serial%4)
	record.coalescedResults=0
	Results.lastResult=record
	record.identityComplete=true
	for _,key in ipairs({"initialLoadRunId","manifestToken","networkId","replicaEpoch","catalogScope","initialLoadProfile","initialLoadProfileHash"}) do
		if type(record[key])~="string" or record[key]=="" then record.identityComplete=false end
	end
	for _,key in ipairs({"inventoryRevision","openSeq","playerNum","topologySequence"}) do
		if type(record[key])~="number" then record.identityComplete=false end
	end
	if not getFileWriter then record.persisted=false;record.persistenceReason="result_writer_unavailable";return record end
	-- One write/second/process, at most one pending result per bounded role.
	-- Different roles survive a paired request; latest status replaces its role.
	-- No retry on writer failure; coalescing is explicit in the retained result.
	local previous=pending[role]
	if previous then record.coalescedResults=previous.coalescedResults+1 end
	pending[role]=record
	flush()
	local remaining=false
	for _ in pairs(pending) do remaining=true;break end
	if remaining and not attached then
		local available=Events and Events.OnTick and type(Events.OnTick.Add)=="function"
		local ok=available and pcall(Events.OnTick.Add,flush)
		if ok then attached=true
		else
			for _,queued in pairs(pending) do queued.persisted=false;queued.persistenceReason="result_events_unavailable" end
			pending={}
		end
	end
	return record
end
return Results

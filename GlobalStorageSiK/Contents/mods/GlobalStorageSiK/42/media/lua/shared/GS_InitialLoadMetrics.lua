-- Constant-size, opt-in opening aggregates. No payload or inventory traversal.
local Metrics={}
GlobalStorageSiK.InitialLoadMetrics=Metrics
local NULL={}
local serial=0
local function now() return getTimestampMs and getTimestampMs() or 0 end
local function enabled()
	local sandbox=GlobalStorageSiK.Sandbox
	return GlobalStorageSiK.Log and sandbox and sandbox.debugMode()
		and sandbox.debugCategoryEnabled("CatalogTransport")
end
local function escape(value)
	return '"'..value:gsub('[%c\\"]',function(c)
		return string.format('\\u%04x',string.byte(c)) end)..'"'
end
local function json(value)
	if value==NULL then return "null" end
	local kind=type(value)
	if kind=="string" then return escape(value) end
	if kind=="number" or kind=="boolean" then return tostring(value) end
	local keys,parts={},{}
	for key in pairs(value) do keys[#keys+1]=key end
	table.sort(keys)
	for _,key in ipairs(keys) do parts[#parts+1]=escape(key)..":"..json(value[key]) end
	return "{"..table.concat(parts,",").."}"
end
local phases={validate=true,build=true,encode=true,frame=true,size=true,send=true,
	decode=true,dispatch=true,apply=true,manifest=true,prepare=true}
local counters={batches=true,fragments=true,uniqueFrameBytes=true,retransmittedFrameBytes=true,
	decodeSteps=true,views=true,nodeBodies=true,requests=true,recoveries=true,wallYields=true,
	unitYields=true,computeYields=true,frameYields=true,visitYields=true,ackYields=true,
	ackWaitMs=true,queueWaitMs=true,receiveWaitMs=true}
function Metrics.begin(role,meta)
	if not enabled() then return nil end
    serial=serial+1
	local state={started=now(),data={schemaVersion="initial-load-summary/1.0",role=role,
		clock="process-getTimestampMs",clockValid=getTimestampMs~=nil,openSeq=meta.openSeq,
		playerNum=meta.playerNum,localSequence=serial,phases={},counts={},peakTransportReservationBytes=0,
		serverTickP95Ms=NULL,serverTickP99Ms=NULL,serverTickMaxMs=NULL,
		clientFrameP95Ms=NULL,clientFrameP99Ms=NULL,clientFrameMaxMs=NULL,heapPeakBytes=NULL,
		gcPauseMaxMs=NULL,gcPauseRateMsPerSecond=NULL,physicalCaptureMs=NULL,
		uniqueFullTypes=NULL,inventoryDigest=NULL,pressureCoverage=0,scopeHash=NULL,
		catalogScope=NULL,scopeComplete=false,scopeChanged=false,
		unknownReasons="engine pressure sampler and inventory oracle required from Systems; physical capture is separate"}}
	for phase in pairs(phases) do state.data.phases[phase]={activeMs=0,maxMs=0,calls=0} end
	for counter in pairs(counters) do state.data.counts[counter]=0 end
	return state
end
function Metrics.bind(state,meta)
	if not state or state.finished then return end
	local scope=meta.catalogScope
	if type(scope)=="string" then
		if state.scope~=nil and state.scope~=scope then state.data.scopeChanged=true end
		if state.scope==nil then
			-- Preserve exact source bytes for the offline SHA-256 normalizer. Never
			-- disguise a truncated scope or a non-cryptographic fingerprint as a hash.
			state.scope=scope;state.data.scopeLength=#scope
			state.data.scopeComplete=#scope<=1024
			state.data.catalogScope=#scope<=1024 and scope or NULL
		end
	end
	for _,key in ipairs({"networkId","replicaEpoch","manifestToken","inventoryRevision","topologySequence"}) do
		local value=meta[key]
		if type(value)=="number" then state.data[key]=value
		elseif type(value)=="string" then state.data[key]=value:sub(1,512) end
	end
	state.data.profileId=meta.initialLoadProfile or state.data.profileId or "control"
	state.data.profileHash=meta.initialLoadProfileHash or state.data.profileHash or NULL
	state.data.runId=meta.initialLoadRunId or state.data.runId or NULL
end
function Metrics.complete(state)
	if state and not state.finished then state.data.completeUsableMs=math.max(0,now()-state.started);state.completePending=true end
end
function Metrics.work(state,phase,elapsed)
	if not state or state.finished or not phases[phase] then return end
	local value=state.data.phases[phase]
	if elapsed<0 then state.data.clockValid=false;elapsed=0 end
	value.activeMs=value.activeMs+elapsed;value.maxMs=math.max(value.maxMs,elapsed);value.calls=value.calls+1
end
function Metrics.count(state,key,amount)
	if state and not state.finished and counters[key] then state.data.counts[key]=state.data.counts[key]+(amount or 1) end
end
function Metrics.peak(state,bytes)
	if state and not state.finished then state.data.peakTransportReservationBytes=math.max(state.data.peakTransportReservationBytes,bytes) end
end
function Metrics.manifestAccumulator()
	if enabled() then return {nodes=0,confirmed=0,objects=0,zones=0,seenZones={}} end
end
function Metrics.manifestRecord(stats,record)
	if not stats or not record.enabled then return end
	stats.nodes=stats.nodes+1
	if not stats.seenZones[record.zoneId] then
		stats.seenZones[record.zoneId]=true;stats.zones=stats.zones+1
	end
	if record.confirmed then stats.confirmed=stats.confirmed+1;stats.objects=stats.objects+record.units end
end
function Metrics.manifest(state,stats)
	if not state or state.finished or not stats then return end
	state.data.availableNodes=stats.nodes;state.data.confirmedNodes=stats.confirmed
	state.data.physicalObjects=stats.confirmed==stats.nodes and stats.objects or NULL
	state.data.zones=stats.zones
end
function Metrics.view(state,rowCount,complete)
	if not state or state.finished then return end
	Metrics.count(state,"views")
	state.data.aggregateRows=rowCount
	if state.data.firstAppliedViewMs==nil then
		state.data.firstAppliedViewMs=math.max(0,now()-state.started);state.data.firstAppliedViewRows=rowCount
	end
	if complete then state.data.completeUsableMs=math.max(0,now()-state.started) end
end
function Metrics.finish(state,outcome,reason)
	if not state or state.finished then return end
	if (state.nesting or 0)>0 then state.pendingOutcome=outcome;state.pendingReason=reason;return end
	state.finished=true
	local elapsed=now()-state.started
	if elapsed<0 then state.data.clockValid=false end
	state.data.elapsedMs=math.max(0,elapsed);state.data.outcome=outcome
	state.data.reason=tostring(reason or ""):sub(1,128)
	state.data.firstAppliedViewMs=state.data.firstAppliedViewMs or NULL
	state.data.completeUsableMs=state.data.completeUsableMs or NULL
	state.data.phaseCoverage=state.data.scopeComplete and not state.data.scopeChanged and 1 or 0
	local log=GlobalStorageSiK.Log
	if log and log.initialLoadSummary then state.exported=log.initialLoadSummary(state.data.role,json(state.data))==true end
	return state.exported
end
function Metrics.enter(state) if state and not state.finished then state.nesting=(state.nesting or 0)+1 end end
function Metrics.leave(state)
	if not state or state.finished then return end
	state.nesting=math.max(0,(state.nesting or 0)-1)
	if state.nesting==0 and state.pendingOutcome then Metrics.finish(state,state.pendingOutcome,state.pendingReason) end
end
return Metrics

-- Opt-in research helpers; capture is armed explicitly, never by default.
require "GS_Config"
local Profile=require "GS_InitialLoadProfile"
local Oracle=require "GS_InitialLoadOracle"
local Results=require "GS_InitialLoadDiagnosticResults"
local Diagnostics={}
local requests,sequence={},0
local awaiting=false
GlobalStorageSiK.InitialLoadDiagnostics=Diagnostics
local function pendingResults()
	local active=false
	local timestamp=getTimestampMs and getTimestampMs() or 0
	for playerNum=0,3 do
		local pending=requests[playerNum]
		if pending then
			if timestamp<pending.sentAt or timestamp-pending.sentAt>=Oracle.replyTimeoutMs then
				requests[playerNum]=nil
				Oracle.reject("server",timestamp<pending.sentAt and "oracle_clock_changed" or "oracle_result_timeout",
					pending.meta,pending.requestId)
			else active=true end
		end
	end
	if not active and awaiting then Events.OnTick.Remove(pendingResults);awaiting=false end
end
local function requestId(playerNum)
	sequence=sequence+1
	return tostring(getTimestampMs and getTimestampMs() or 0)..":"..tostring(playerNum)..":"..sequence
end
local function admin(player)
	local ok,accepted=pcall(function() return player and player:isAccessLevel("admin") end)
	return ok and accepted==true
end
local function validPlayerNum(value)
	return type(value)=="number" and value>=0 and value<=3 and value%1==0
end
function Diagnostics.select(playerNum,id)
	local player=getSpecificPlayer(playerNum)
	if not player or not Profile.snapshot(id) then return false end
	if GlobalStorageSiK.isAuthoritative() then return Profile.select(id) end
	sendClientCommand(player,"GlobalStorageSiKInitialLoadDiagnostics","select",{profileId=id})
	return true -- request sent; only the server result/next opening ACK proves selection.
end
function Diagnostics.exportClient(playerNum,exportId)
	exportId=Results.requestId(exportId) and exportId or requestId(playerNum)
	if not validPlayerNum(playerNum) then return Oracle.reject("client","oracle_player",nil,exportId) end
	local player=getSpecificPlayer(playerNum)
	if not admin(player) then return Oracle.reject("client","oracle_admin",nil,exportId) end
	local client=GlobalStorageSiK.NodeCatalogClient
	if not client then return Oracle.reject("client","oracle_client_missing",nil,exportId) end
	local details=client.oracleStatus(playerNum)
	local image,reason,valid=client.oracleImage(playerNum)
	if not image then return Oracle.reject("client",reason,details,exportId) end
	return Oracle.begin("client",image,valid,exportId,nil,details)
end
function Diagnostics.exportServer(playerNum,exportId)
	exportId=Results.requestId(exportId) and exportId or requestId(playerNum)
	if not validPlayerNum(playerNum) then return Oracle.reject("server","oracle_player",nil,exportId) end
	local player=getSpecificPlayer(playerNum)
	if not admin(player) then return Oracle.reject("server","oracle_admin",nil,exportId) end
	if GlobalStorageSiK.isAuthoritative() then
		local catalog=GlobalStorageSiK.NodeCatalogServer
		if not catalog then return Oracle.reject("server","oracle_server_missing",nil,exportId) end
		local details=catalog.oracleStatus(player)
		local image,reason,valid=catalog.oracleImage(player)
		if not image then return Oracle.reject("server",reason,details,exportId) end
		return Oracle.begin("server",image,valid,exportId,nil,details)
	end
	local sandbox=GlobalStorageSiK.Sandbox
	if not sandbox or not sandbox.debugMode() or not sandbox.debugCategoryEnabled("CatalogTransport") then
		return Oracle.reject("server","oracle_disabled",nil,exportId)
	end
	if requests[playerNum] and getTimestampMs and getTimestampMs()-requests[playerNum].sentAt<Oracle.replyTimeoutMs then
		return Oracle.reject("server","oracle_request_pending",nil,exportId)
	end
	if not Events or not Events.OnTick or type(Events.OnTick.Add)~="function" or type(Events.OnTick.Remove)~="function" then return Oracle.reject("server","oracle_events",nil,exportId) end
	local client=GlobalStorageSiK.NodeCatalogClient
	local details=client and client.oracleStatus(playerNum) or nil
	requests[playerNum]={requestId=exportId,sentAt=getTimestampMs and getTimestampMs() or 0,meta=details}
	if not awaiting then
		if not pcall(Events.OnTick.Add,pendingResults) then requests[playerNum]=nil;return Oracle.reject("server","oracle_events",details,exportId) end
		awaiting=true
	end
	local sent=pcall(sendClientCommand,player,"GlobalStorageSiKInitialLoadDiagnostics","oracle",{requestId=exportId})
	if not sent then requests[playerNum]=nil;pendingResults();return Oracle.reject("server","oracle_send",details,exportId) end
	Results.record("server","sent","",details,exportId)
	return true
end
-- One explicit request after completeUsable; results are files, no return reading.
function Diagnostics.exportPair(playerNum,exportId)
	exportId=Results.requestId(exportId) and exportId or requestId(playerNum)
	if GlobalStorageSiK.isAuthoritative() then return Diagnostics.exportServer(playerNum,exportId) end
	local localAccepted=Diagnostics.exportClient(playerNum,exportId)
	if not localAccepted then
		Oracle.reject("server","oracle_pair_client_failed",{playerNum=validPlayerNum(playerNum) and playerNum or nil},exportId)
		return false,exportId
	end
	local remoteAccepted=Diagnostics.exportServer(playerNum,exportId)
	return localAccepted and remoteAccepted,exportId
end
-- Systems may arm once before a cold opening. Poll constant-size status only;
-- export starts after complete plus a quiet grace interval, outside timing.
local captures,captureAttached={},false
local captureTick
local function captureOutcome(capture,reason)
 local role=GlobalStorageSiK.isAuthoritative() and "server" or "client"
 Oracle.reject(role,reason,{playerNum=capture.playerNum},capture.requestId)
 if role=="client" then Oracle.reject("server",reason,{playerNum=capture.playerNum},capture.requestId) end
end
captureTick=function()
 local timestamp=getTimestampMs and getTimestampMs() or 0
 for playerNum=0,3 do
  local capture=captures[playerNum]
  if capture and timestamp-capture.polledAt>=1000 then
   capture.polledAt=timestamp
   local player=getSpecificPlayer(playerNum)
   local sandbox=GlobalStorageSiK.Sandbox
   local reason
   if timestamp<capture.startedAt then reason="oracle_clock_changed"
   elseif timestamp-capture.startedAt>=180000 then reason="oracle_capture_timeout"
   elseif player~=capture.player or not admin(player) then reason="oracle_admin"
   elseif not sandbox or not sandbox.debugMode() or not sandbox.debugCategoryEnabled("CatalogTransport") then reason="oracle_disabled" end
   if reason then captures[playerNum]=nil;captureOutcome(capture,reason)
   else
    local authority=GlobalStorageSiK.isAuthoritative()
    local catalog=authority and GlobalStorageSiK.NodeCatalogServer or GlobalStorageSiK.NodeCatalogClient
    local status=catalog and catalog.oracleStatus(authority and player or playerNum)
    local ready=status and status.snapshotCertified==true and status.reconcilePending~=true
     and type(status.initialLoadRunId)=="string" and status.initialLoadRunId~=""
     and status.initialLoadRunId~=capture.baselineRunId and status.manifestToken~=nil and not Oracle.busy()
    if authority then ready=ready and not status.globalBusy and not status.transportBusy and not status.roundActive
     and not status.requestPending and not status.readyPending and not status.retryPending and not status.refreshPending
    else ready=ready and status.completed and status.hasComplete and not status.partial
     and status.contextCurrent and status.accessAllowed and status.cacheAccepted end
    if not ready or capture.runId~=(status and status.initialLoadRunId) then
     capture.readyAt=nil;capture.runId=status and status.initialLoadRunId
    elseif not capture.readyAt then capture.readyAt=timestamp
    elseif timestamp-capture.readyAt>=2500 then
     captures[playerNum]=nil;Diagnostics.exportPair(playerNum,capture.requestId)
    end
   end
  elseif capture and timestamp<capture.startedAt then
   captures[playerNum]=nil;captureOutcome(capture,"oracle_clock_changed")
  end
 end
 local active=false;for playerNum=0,3 do if captures[playerNum] then active=true end end
 if not active and captureAttached then pcall(Events.OnTick.Remove,captureTick);captureAttached=false end
end
function Diagnostics.armCapture(playerNum)
 local exportId=requestId(playerNum)
 if not validPlayerNum(playerNum) then return Oracle.reject("client","oracle_player",nil,exportId) end
 local player=getSpecificPlayer(playerNum)
 local sandbox=GlobalStorageSiK.Sandbox
 if not admin(player) then return Oracle.reject("client","oracle_admin",nil,exportId) end
 if not sandbox or not sandbox.debugMode() or not sandbox.debugCategoryEnabled("CatalogTransport") then
  return Oracle.reject("client","oracle_disabled",nil,exportId)
 end
 if captures[playerNum] then return Oracle.reject("client","oracle_capture_pending",nil,exportId) end
 if not Events or not Events.OnTick or type(Events.OnTick.Add)~="function" or type(Events.OnTick.Remove)~="function" then
  return Oracle.reject("client","oracle_events",nil,exportId)
 end
 local timestamp=getTimestampMs and getTimestampMs() or 0
 local authority=GlobalStorageSiK.isAuthoritative()
 local catalog=authority and GlobalStorageSiK.NodeCatalogServer or GlobalStorageSiK.NodeCatalogClient
 local baseline=catalog and catalog.oracleStatus(authority and player or playerNum)
 captures[playerNum]={player=player,playerNum=playerNum,requestId=exportId,startedAt=timestamp,polledAt=timestamp,
  baselineRunId=baseline and baseline.initialLoadRunId}
 if not captureAttached then
  if not pcall(Events.OnTick.Add,captureTick) then captures[playerNum]=nil;return Oracle.reject("client","oracle_events",nil,exportId) end
  captureAttached=true
 end
 Results.record(GlobalStorageSiK.isAuthoritative() and "server" or "client","armed","",{playerNum=playerNum},exportId)
 return true,exportId
end
function Diagnostics.disarmCapture(playerNum)
 local capture=captures[playerNum]
 if not capture then return false end
 captures[playerNum]=nil;captureOutcome(capture,"oracle_capture_cancelled");captureTick();return true
end
local function result(module,name,args)
	if module~="GlobalStorageSiKInitialLoadDiagnostics" or name~="result" or type(args)~="table" then return end
	if (args.operation~="select" and args.operation~="oracle") or type(args.accepted)~="boolean"
		or type(args.profileId)~="string" or #args.profileId>32 or type(args.profileHash)~="string"
		or #args.profileHash>64 or type(args.reason)~="string" or #args.reason>128 then return end
	if args.operation=="oracle" then
		if not Results.requestId(args.requestId) or type(args.playerNum)~="number" or args.playerNum<0 or args.playerNum>3
			or args.playerNum%1~=0 or type(args.status)~="string" or #args.status>16
			or type(args.oraclePath)~="string" or #args.oraclePath>256 then return end
		local owner,pending=nil,nil
		for playerNum=0,3 do
			if requests[playerNum] and requests[playerNum].requestId==args.requestId then owner=playerNum;pending=requests[playerNum];break end
		end
		if not pending then return end
		if args.status~="started" and args.status~="complete" and args.status~="failed" and args.status~="rejected" then return end
		Results.record("server",args.status,args.reason,Results.context(args),args.requestId,args.oraclePath)
		if args.status~="started" then requests[owner]=nil;pendingResults() end
	end
	Diagnostics.lastResult={operation=args.operation,accepted=args.accepted,profileId=args.profileId,
		profileHash=args.profileHash,reason=args.reason}
	GlobalStorageSiK.Log.debug("CatalogTransport","initial_load_diagnostic_result",
		args.operation.." accepted="..tostring(args.accepted).." profile="..args.profileId.." hash="..args.profileHash.." reason="..args.reason)
end
Events.OnServerCommand.Add(result)
return Diagnostics

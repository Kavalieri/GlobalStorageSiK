-- Research commands have no network-role bypass and never scan physical items.
require "GS_Config"
require "GS_Permissions"
local Profile=require "GS_InitialLoadProfile"
local Oracle=require "GS_InitialLoadOracle"
local Results=require "GS_InitialLoadDiagnosticResults"
local lastRequest=nil
local function command(module,name,player,args)
	if module~="GlobalStorageSiKInitialLoadDiagnostics" or not GlobalStorageSiK.isAuthoritative()
		or not player or type(args)~="table" or getmetatable(args)~=nil then return end
	if name~="select" and name~="oracle" then return end
	-- A network owner/moderator is insufficient for a process-wide selector.
	local staffOk,admin=pcall(function() return player:isAccessLevel("admin") end)
	if not staffOk or admin~=true then return end
	local exportId=args.requestId
	if name=="oracle" and exportId~=nil and not Results.requestId(exportId) then return end
	local catalog=GlobalStorageSiK.NodeCatalogServer
	local details=name=="oracle" and catalog and catalog.oracleStatus(player) or nil
	local function report(record)
		if not sendServerCommand then return end
		local payload=Results.context(record)
		payload.operation="oracle";payload.accepted=record.status=="started" or record.status=="complete"
		payload.profileId="";payload.profileHash="";payload.reason=record.reason
		payload.requestId=exportId or "";payload.status=record.status;payload.oraclePath=record.oraclePath
		payload.playerNum=payload.playerNum or 0
		sendServerCommand(player,"GlobalStorageSiKInitialLoadDiagnostics","result",payload)
	end
	local function reject(reason,details)
		if name=="oracle" then Oracle.reject("server",reason,details,exportId,report) end
	end
	local sandbox=GlobalStorageSiK.Sandbox
	if not sandbox or not sandbox.debugMode() or not sandbox.debugCategoryEnabled("CatalogTransport") then reject("oracle_disabled",details);return end
	local count=0
	for key in pairs(args) do
		count=count+1
		if count>1 or (name=="select" and key~="profileId") or (name=="oracle" and key~="requestId") then return end
	end
	local timestamp=getTimestampMs and getTimestampMs() or 0
	if lastRequest and timestamp>=lastRequest and timestamp-lastRequest<2000 then reject("oracle_request_throttle",details);return end
	lastRequest=timestamp
	if catalog and catalog.initialLoadBusy() then reject("oracle_replication_busy",details);return end
	local accepted,reason=false,"unknown_profile_or_busy"
	local profile
	if name=="select" then
		if type(args.profileId)~="string" or #args.profileId>32 or Oracle.busy() then return end
		accepted=Profile.select(args.profileId);profile=accepted and Profile.snapshot() or nil
		if accepted then reason="" end
	else
		if catalog then
			local image,why,valid=catalog.oracleImage(player)
			if image then Oracle.begin("server",image,valid,exportId,report,details) else reject(why,details) end
		else reject("oracle_server_missing") end
		return
	end
	if sendServerCommand then sendServerCommand(player,"GlobalStorageSiKInitialLoadDiagnostics","result",
		{operation=name,accepted=accepted==true,reason=tostring(reason or ""),
		profileId=profile and profile.id or "",profileHash=profile and profile.hash or ""}) end
end
if GlobalStorageSiK.isAuthoritative() then Events.OnClientCommand.Add(command) end
return command

-- Private console helpers; no new UI, gameplay keybinding or automatic export.
require "GS_Config"
local Profile=require "GS_InitialLoadProfile"
local Oracle=require "GS_InitialLoadOracle"
local Diagnostics={}
GlobalStorageSiK.InitialLoadDiagnostics=Diagnostics
function Diagnostics.select(playerNum,id)
	local player=getSpecificPlayer(playerNum)
	if not player or not Profile.snapshot(id) then return false end
	if GlobalStorageSiK.isAuthoritative() then return Profile.select(id) end
	sendClientCommand(player,"GlobalStorageSiKInitialLoadDiagnostics","select",{profileId=id})
	return true -- request sent; only the server result/next opening ACK proves selection.
end
function Diagnostics.exportClient(playerNum)
	local player=getSpecificPlayer(playerNum)
	local ok,admin=pcall(function() return player and player:isAccessLevel("admin") end)
	if not ok or not admin then return false,"oracle_admin" end
	local client=GlobalStorageSiK.NodeCatalogClient
	if not client then return false,"oracle_unavailable" end
	local image,reason,valid=client.oracleImage(playerNum)
	if not image then return false,reason end
	return Oracle.begin("client",image,valid)
end
function Diagnostics.exportServer(playerNum)
	local player=getSpecificPlayer(playerNum)
	if not player then return false end
	if GlobalStorageSiK.isAuthoritative() then
		local image,reason,valid=GlobalStorageSiK.NodeCatalogServer.oracleImage(player)
		if not image then return false,reason end
		return Oracle.begin("server",image,valid)
	end
	sendClientCommand(player,"GlobalStorageSiKInitialLoadDiagnostics","oracle",{})
	return true
end
local function result(module,name,args)
	if module~="GlobalStorageSiKInitialLoadDiagnostics" or name~="result" or type(args)~="table" then return end
	if (args.operation~="select" and args.operation~="oracle") or type(args.accepted)~="boolean"
		or type(args.profileId)~="string" or #args.profileId>32 or type(args.profileHash)~="string"
		or #args.profileHash>64 or type(args.reason)~="string" or #args.reason>128 then return end
	Diagnostics.lastResult={operation=args.operation,accepted=args.accepted,profileId=args.profileId,
		profileHash=args.profileHash,reason=args.reason}
	GlobalStorageSiK.Log.debug("CatalogTransport","initial_load_diagnostic_result",
		args.operation.." accepted="..tostring(args.accepted).." profile="..args.profileId.." hash="..args.profileHash.." reason="..args.reason)
end
Events.OnServerCommand.Add(result)
return Diagnostics

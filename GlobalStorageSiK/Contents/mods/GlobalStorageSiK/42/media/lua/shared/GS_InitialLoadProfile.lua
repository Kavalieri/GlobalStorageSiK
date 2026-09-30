-- Private research selector: unchanged 2 ms shared client time slice.
local Profile={}
GlobalStorageSiK.InitialLoadProfile=Profile
local definitions={
	control={id="control",buildWork=256,hash="74c19fadb29e2b4dc67a6d5ab9abc4393c9d5eca7d143d457444628e1384e34a"},
	drain1024={id="drain1024",buildWork=1024,hash="b467ce2ae6c883767a65b644b5dd6f34c8d9d39e178398a35fa8d6dfacaa001f"},
	drain4096={id="drain4096",buildWork=4096,hash="162f4a66f08b2fbddc411da166a94b6c06be7eaab8ce821afc068fe151cdc38c"},
}
local selected="control"
function Profile.select(id)
	local sandbox=GlobalStorageSiK.Sandbox
	if not definitions[id] or not sandbox or not sandbox.debugMode()
		or not sandbox.debugCategoryEnabled("CatalogTransport") then return false end
	local server=GlobalStorageSiK.CatalogServer
	if server and server.diagnostics().jobs>0 then return false end
	selected=id;return true
end
function Profile.snapshot(id)
	if id==nil then
		local sandbox=GlobalStorageSiK.Sandbox
		id=sandbox and sandbox.debugMode() and sandbox.debugCategoryEnabled("CatalogTransport") and selected or "control"
	end
	local value=definitions[id]
	if not value then return nil end
	return {id=value.id,buildWork=value.buildWork,hash=value.hash}
end
return Profile

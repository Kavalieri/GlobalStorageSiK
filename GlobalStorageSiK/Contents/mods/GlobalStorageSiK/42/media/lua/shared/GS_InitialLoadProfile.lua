-- Normal complete-replica policy; explicit research profiles retain their pins.
local Profile={}
GlobalStorageSiK.InitialLoadProfile=Profile
local definitions={
	final10={id="final10",buildWork=1024,groupCredits=4,frameBytes=48000,reuseSnapshots=true,viewBlocks=8,viewDelayMs=1000,compactTables=true,efficientCodec=true,streamlinedCodec=true,packedRecords=true,hash="90949a5bee798570092c5c0e8dde180a3e1181fe91b103b3e0e96b0ac35bf2fc"},
	final9={id="final9",buildWork=1024,groupCredits=4,frameBytes=48000,reuseSnapshots=true,viewBlocks=8,compactTables=true,efficientCodec=true,streamlinedCodec=true,hash="7433f11fd3427f775bc6f0ad4aee2bf33eec4142fc8d5d0ee1d4def35d03b150"},
	final8={id="final8",buildWork=1024,groupCredits=4,frameBytes=48000,reuseSnapshots=true,viewBlocks=8,compactTables=true,efficientCodec=true,hash="6d4bdd53a4dc6e8ad331409b4cc3cb51b6bd5ef475c649ce28578a1cbcc5fc67"},
	final7={id="final7",buildWork=1024,groupCredits=4,frameBytes=48000,reuseSnapshots=true,viewBlocks=8,compactTables=true,hash="d1aa832a8a119601725614b137ebba230a481a4a260424d4eb42854250676e5c"},
	final4={id="final4",buildWork=1024,groupCredits=4,frameBytes=48000,reuseSnapshots=true,viewBlocks=8,hash="1459d29be7d967047a9516cefccd46498e755c4dfe23277915fb85763db50612"},
	control={id="control",buildWork=256,hash="74c19fadb29e2b4dc67a6d5ab9abc4393c9d5eca7d143d457444628e1384e34a"},
	drain1024={id="drain1024",buildWork=1024,hash="b467ce2ae6c883767a65b644b5dd6f34c8d9d39e178398a35fa8d6dfacaa001f"},
	drain4096={id="drain4096",buildWork=4096,hash="162f4a66f08b2fbddc411da166a94b6c06be7eaab8ce821afc068fe151cdc38c"},
	group2={id="group2",buildWork=1024,groupCredits=2,frameBytes=24000,hash="dfad15b35ca28ae7bafcf7114f8e4d13cc6a0cd8093de83113d85d6481ada21e"},
	group4={id="group4",buildWork=1024,groupCredits=4,frameBytes=24000,hash="1936fedec0c88b97ca6eef592a2e5a2f553dd67cae86b59a3e4d9ea918010393"},
	frame32={id="frame32",buildWork=1024,frameBytes=32000,hash="9a3a481263e56477885f2163e3125579b13b9be77fb76c2f6f7f954a5db1e935"},
	frame48={id="frame48",buildWork=1024,frameBytes=48000,hash="4c50e28120ee13e1463ace4a58edbef0903f2ca55b9691c2ae5ab496da2cd0dc"},
	reuse4={id="reuse4",buildWork=1024,groupCredits=4,reuseSnapshots=true,hash="99a979e43391b62197d246d73f1c03464ce5f36dbb03c5d3e0af8dd8eb8a804e"},
	combined2={id="combined2",buildWork=1024,groupCredits=2,frameBytes=32000,reuseSnapshots=true,hash="5f4cbacac8fbfe29f3c81fb14df8d2cd18e1826544f9bfce7bd79ac9d9c99da5"},
	combined4={id="combined4",buildWork=1024,groupCredits=4,frameBytes=48000,reuseSnapshots=true,hash="3a60a53d053a3b0d02162ebb2bcf9db4eb43bcab520e0352dfbed78b0cea61bd"},
	wire2={id="wire2",buildWork=1024,groupCredits=2,frameBytes=32000,reuseSnapshots=true,optimizedCodec=true,hash="3e6266527e7bee08aeb9359bd6081c1856fbdca2dd5ea856df9a178a883cd9a1"},
	wire4={id="wire4",buildWork=1024,groupCredits=4,frameBytes=32000,reuseSnapshots=true,optimizedCodec=true,hash="a07b26355b4e7eb98f374f941852a6006b97ac920f37f7443b92bdacc54a41f1"},
}
local selected="final10"
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
		id=sandbox and sandbox.debugMode() and sandbox.debugCategoryEnabled("CatalogTransport") and selected or "final10"
	end
	local value=definitions[id]
	if not value then return nil end
	return {id=value.id,buildWork=value.buildWork,hash=value.hash,groupCredits=value.groupCredits or 1,
		frameBytes=value.frameBytes or 24000,reuseSnapshots=value.reuseSnapshots==true,optimizedCodec=value.optimizedCodec==true,
		viewBlocks=value.viewBlocks or 1,compactTables=value.compactTables==true,efficientCodec=value.efficientCodec==true,streamlinedCodec=value.streamlinedCodec==true,packedRecords=value.packedRecords==true,viewDelayMs=value.viewDelayMs}
end
return Profile

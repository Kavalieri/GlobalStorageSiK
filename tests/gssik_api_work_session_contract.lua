-- Author contract for the final public GSSiK.API.WorkSession facade.
-- Pure Lua 5.1 with generation-aware stubs; no Project Zomboid runtime needed.

local sharedPath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GSSiK_API.lua"
local workPath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
	.. "GSSiK_API_WorkSession.lua"

local function read(path)
	local handle = io.open(path, "rb")
	if not handle then return nil end
	local source = handle:read("*a")
	handle:close()
	return source
end

local sharedSource = assert(read(sharedPath), "missing shared public API")
local workSource = assert(read(workPath), "missing WorkSession public API")
assert(sharedSource:find('WorkSession = "1.0.0"', 1, true),
	"Capabilities do not advertise WorkSession")
assert(not sharedSource:find('CraftSession = "', 1, true),
	"Capabilities still advertise private CraftSession")
for _, symbol in ipairs({
	"function Diagnostics.registerWorkSessionSink(",
	"function Public.begin(", "function Public.endSession(",
	"function Public.get(", "function Public.status(",
	"function Public.getOpenFailure(", "function Public.reportOpenFailure(",
	"function Public.openHandcraft(", "function Public.openBuild(",
	"function Public.startOperation(", "function Public.claimRecipeInputs(",
	"function Public.claimItem(", "function Public.completeOperation(",
	"function Public.abortOperation(", "function Public.narrowInputs(",
	"function Public.withContainerInjectionSuspended(",
	"function Public.setResultDestination(", "function Public.getResultDestination(",
	"function Public.registerLifecycle(",
}) do
	assert(workSource:find(symbol, 1, true), "WorkSession omits public contract: " .. symbol)
end

package.loaded["GS_AddonRegistry"] = true
package.loaded["GS_DiskProgramming"] = true
package.loaded["GS_TerminalAccess"] = true
package.loaded["GSSiK_API"] = true
package.loaded["GS_NetworkCraftSession"] = true

local generation, operationSequence = 0, 0
local debugSinks, hooks, ticks = {}, {}, {}
local activeSessions, statuses = {}, {}
local lastBegin, lastEndReason, lastOpen, lastOpenError = nil, nil, nil, nil
local lastClaimRecipe, lastClaimItem, completed, aborted = nil, nil, {}, {}
local restoreCalls, sentCommands = 0, {}
local failTickRegistration = false

local function nextGeneration()
	generation = generation + 1
	return generation
end

local internal = {}
function internal.registerDebugSink(addonId, callback)
	local current = nextGeneration()
	debugSinks[addonId] = { callback = callback, generation = current }
	return true, current
end
function internal.removeDebugSinkIfGeneration(addonId, expected)
	local entry = debugSinks[addonId]
	if not entry or entry.generation ~= expected then return false end
	debugSinks[addonId] = nil
	return true
end
function internal.registerAddonHooks(addonId, install, uninstall)
	local current = nextGeneration()
	hooks[addonId] = { install = install, uninstall = uninstall, generation = current }
	return true, current
end
function internal.removeAddonHooksIfGeneration(addonId, expected)
	local entry = hooks[addonId]
	if not entry or entry.generation ~= expected then return false end
	hooks[addonId] = nil
	return true
end
function internal.registerTickHandler(addonId, callback)
	if failTickRegistration then return false end
	local current = nextGeneration()
	ticks[addonId] = { callback = callback, generation = current }
	return true, current
end
function internal.removeTickHandlerIfGeneration(addonId, expected)
	local entry = ticks[addonId]
	if not entry or entry.generation ~= expected then return false end
	ticks[addonId] = nil
	return true
end
function internal.begin(options)
	lastBegin = options
	return true
end
function internal.endSession(reason) lastEndReason = reason end
function internal.getActiveSession(addonId) return activeSessions[addonId] end
function internal.getStatus(addonId) return statuses[addonId] end
function internal.setLastOpenError(reason) lastOpenError = reason end
function internal.openHandcraft(mode, recipe, itemString)
	lastOpen = { kind = "handcraft", mode = mode, recipe = recipe, itemString = itemString }
	return true
end
function internal.openBuild(mode, recipe, itemString)
	lastOpen = { kind = "build", mode = mode, recipe = recipe, itemString = itemString }
	return false, "blocked"
end
function internal.newOperationId(addonId)
	operationSequence = operationSequence + 1
	return addonId .. "-operation-" .. operationSequence
end
function internal.claimRecipeItems(player, logic, items, networkId, operationId, count)
	lastClaimRecipe = {
		player = player, logic = logic, items = items, networkId = networkId,
		operationId = operationId, count = count,
	}
	return { "item-1", "item-2" }, 2, 2, 0
end
internal.CLAIM_RECIPE_CONTRACT_VERSION = 7
function internal.isNetworkContainer(container, networkId)
	return container and container.networkId == networkId
end
function internal.claimNetworkItem(player, item, container, networkId, operationId)
	lastClaimItem = {
		player = player, item = item, container = container,
		networkId = networkId, operationId = operationId,
	}
	return true
end
function internal.markOperationComplete(operationId) completed[operationId] = true end
function internal.abortOperation(operationId) aborted[operationId] = true end
function internal.narrowContainersForAction(panel, items, addonId)
	return function()
		restoreCalls = restoreCalls + 1
		return panel ~= nil and items ~= nil and addonId ~= nil
	end
end
function internal.withContainerInjectionSuspended(callback, ...) return callback(...) end

GlobalStorageSiK = {
	AddonRegistry = {}, DiskProgramming = {}, TerminalAccess = {}, Addons = {},
	CraftSession = internal,
	NetClient = {
		sendCommand = function(command, payload)
			sentCommands[#sentCommands + 1] = { command = command, payload = payload }
		end,
	},
}

local function player(number)
	return { getPlayerNum = function() return number end }
end

GSSiK = nil
local API = assert(dofile(sharedPath), "shared API did not load")
assert(API.CraftSession == nil, "shared namespace exposes private CraftSession")
local available, capabilityCode = API.Capabilities.has("WorkSession", "1.0.0")
assert(available == true and capabilityCode == "OK", "WorkSession capability missing")
local privateAvailable = API.Capabilities.has("CraftSession", "1.0.0")
assert(privateAvailable == false, "Capabilities still announce CraftSession")

API.CraftSession = { leaked = true }
API = assert(dofile(workPath), "WorkSession module did not return GSSiK.API")
local WorkSession = assert(API.WorkSession, "WorkSession namespace missing")
local Diagnostics = assert(API.Diagnostics, "Diagnostics namespace missing")
assert(API.CraftSession == nil, "private CraftSession alias survived client load")

for _, name in ipairs({
	"begin", "endSession", "get", "status", "getOpenFailure", "reportOpenFailure",
	"openHandcraft", "openBuild", "startOperation", "claimRecipeInputs", "claimItem",
	"completeOperation", "abortOperation", "narrowInputs",
	"withContainerInjectionSuspended", "setResultDestination", "getResultDestination",
	"registerLifecycle",
}) do
	assert(type(WorkSession[name]) == "function", "missing WorkSession." .. name)
end
assert(type(Diagnostics.registerWorkSessionSink) == "function",
	"missing Diagnostics.registerWorkSessionSink")
for _, name in ipairs({
	"registerDebugSink", "debugLog", "newOperationId", "claimRecipeItems",
	"claimNetworkItem", "isNetworkContainer", "markOperationComplete",
	"narrowContainersForAction", "tableToArrayList", "getLastOpenError",
	"setLastOpenError", "getSendResultToNetwork", "setSendResultToNetwork",
	"notifyAttemptStart", "CLAIM_RECIPE_CONTRACT_VERSION",
}) do
	assert(WorkSession[name] == nil, "legacy public alias survived: " .. name)
end

local function rejectsBegin(options, label)
	local ok, code = WorkSession.begin(options)
	assert(ok == false and code == "ERR_SCHEMA", "begin accepted invalid " .. label)
end
rejectsBegin(nil, "options")
rejectsBegin({ addonId = "", player = player(0), networkId = "net", terminalAnchor = {} },
	"addonId")
rejectsBegin({ addonId = "Craft", networkId = "net", terminalAnchor = {} }, "player")
rejectsBegin({ addonId = "Craft", player = player(0), networkId = "", terminalAnchor = {} },
	"networkId")
rejectsBegin({ addonId = "Craft", player = player(0), networkId = "net" }, "anchor")

local anchor = { x = 1, y = 2, z = 0 }
local beginOptions = {
	addonId = "Craft", player = player(0), networkId = "net-a",
	terminalAnchor = anchor, uiMode = "handcraft",
}
local began, beginCode = WorkSession.begin(beginOptions)
assert(began == true and beginCode == "OK" and lastBegin ~= beginOptions,
	"begin rejected valid options or retained the caller table")
beginOptions.networkId = "mutated"
anchor.x = 99
assert(lastBegin.networkId == "net-a" and lastBegin.terminalAnchor ~= anchor
	and lastBegin.terminalAnchor.x == 1, "begin did not take a defensive request snapshot")

assert(WorkSession.endSession({}) == false, "endSession accepted a non-string reason")
local ended, endCode = WorkSession.endSession("closed")
assert(ended and endCode == "OK" and lastEndReason == "closed", "endSession did not delegate")

activeSessions.Craft = {
	active = true, addonId = "Craft", playerNum = 0, networkId = "net-a",
	terminalAnchor = { x = 10, y = 20, z = 0 }, accessMode = "physical", uiMode = "craft",
}
statuses.Craft = {
	active = true, addonId = "Craft", networkId = "net-a", networkContainers = 4,
	unavailableContainers = 1, uiMode = "craft", lastEndReason = "previous",
}
local got, getCode, session = WorkSession.get("Craft")
assert(got and getCode == "OK" and session ~= activeSessions.Craft
	and session.terminalAnchor ~= activeSessions.Craft.terminalAnchor,
	"get did not return a defensive session snapshot")
session.terminalAnchor.x = -1
assert(activeSessions.Craft.terminalAnchor.x == 10, "get leaked the internal anchor")
local statusOk, statusCode, status = WorkSession.status("Craft")
assert(statusOk and statusCode == "OK" and status ~= statuses.Craft
	and status.networkContainers == 4, "status did not return a bounded snapshot")

local failureOk, failureCode, failure = WorkSession.getOpenFailure("Craft")
assert(failureOk and failureCode == "OK" and failure == nil, "unexpected initial open failure")
local reported, reportCode = WorkSession.reportOpenFailure("Craft", "no terminal")
assert(reported and reportCode == "OK" and lastOpenError == "no terminal",
	"reportOpenFailure did not delegate")
failureOk, failureCode, failure = WorkSession.getOpenFailure("Craft")
assert(failureOk and failure == "no terminal", "getOpenFailure lost the reported reason")
assert(WorkSession.reportOpenFailure("Craft", string.rep("x", 161)) == false,
	"reportOpenFailure accepted an oversized reason")

local opened, openCode = WorkSession.openHandcraft("Craft", "recipe", {}, "Base.Nails")
assert(opened and openCode == "OK" and lastOpen.kind == "handcraft"
	and lastOpen.itemString == "Base.Nails", "openHandcraft did not delegate exact arguments")
opened, openCode = WorkSession.openBuild("Builder", "build", {}, "Base.Plank")
assert(opened == false and openCode == "blocked" and lastOpen.kind == "build",
	"openBuild did not preserve the failure")
failureOk, failureCode, failure = WorkSession.getOpenFailure("Builder")
assert(failureOk and failure == "blocked", "openBuild failure was not retained per addon")

local debugOldCalls, debugNewCalls = 0, 0
local debugOk, debugCode, debugOld = Diagnostics.registerWorkSessionSink("Craft", function()
	debugOldCalls = debugOldCalls + 1
end)
local debugNewOk, debugNewCode, debugNew = Diagnostics.registerWorkSessionSink("Craft", function()
	debugNewCalls = debugNewCalls + 1
end)
assert(debugOk and debugCode == "OK" and debugOld
	and debugNewOk and debugNewCode == "OK" and debugNew,
	"registerWorkSessionSink rejected valid registrations")
assert(debugOld:dispose() == false and debugSinks.Craft.callback ~= nil,
	"stale diagnostics handle removed the current generation")
debugSinks.Craft.callback()
assert(debugOldCalls == 0 and debugNewCalls == 1, "diagnostics retained a stale callback")
assert(debugNew:dispose() == true and debugNew:dispose() == false,
	"diagnostics handle was not generation-safe and idempotent")

local function lifecycleDefinition(tag)
	return {
		install = function() return tag .. ":install" end,
		uninstall = function() return tag .. ":uninstall" end,
		tick = function() return tag .. ":tick" end,
	}
end
local lifecycleOk, lifecycleCode, lifecycleOld =
	WorkSession.registerLifecycle("Builder", lifecycleDefinition("old"))
local lifecycleNewOk, lifecycleNewCode, lifecycleNew =
	WorkSession.registerLifecycle("Builder", lifecycleDefinition("new"))
assert(lifecycleOk and lifecycleCode == "OK" and lifecycleOld
	and lifecycleNewOk and lifecycleNewCode == "OK" and lifecycleNew,
	"registerLifecycle rejected valid hooks")
assert(lifecycleOld:dispose() == false and hooks.Builder and ticks.Builder,
	"stale lifecycle handle removed a newer generation")
assert(hooks.Builder.install() == "new:install" and ticks.Builder.callback() == "new:tick",
	"lifecycle replacement retained stale callbacks")
assert(lifecycleNew:dispose() == true and lifecycleNew:dispose() == false,
	"lifecycle handle was not generation-safe and idempotent")
failTickRegistration = true
local rolledBack, rollbackCode, rollbackHandle =
	WorkSession.registerLifecycle("Rollback", lifecycleDefinition("rollback"))
failTickRegistration = false
assert(rolledBack == false and rollbackCode == "ERR_REQUEST" and rollbackHandle == nil
	and hooks.Rollback == nil and ticks.Rollback == nil,
	"failed tick registration did not roll back lifecycle hooks")

local destinationOk, destinationCode = WorkSession.setResultDestination("Craft", "network")
local readDestinationOk, readDestinationCode, destination = WorkSession.getResultDestination("Craft")
assert(destinationOk and destinationCode == "OK" and readDestinationOk
	and readDestinationCode == "OK" and destination == "network",
	"result destination was not isolated per addon")
local _, _, defaultDestination = WorkSession.getResultDestination("Builder")
assert(defaultDestination == "inventory", "default result destination is not inventory")
assert(WorkSession.setResultDestination("Craft", "floor") == false,
	"setResultDestination accepted an unsupported destination")

local owner = player(0)
local stranger = player(1)
local started, startCode, operation = WorkSession.startOperation({
	addonId = "Craft", player = owner, kind = "recipe", recipeName = "Make Nails",
	batchCount = 2, diagnostics = true, containerCount = 4.9,
	networkId = "client-forged", extra = string.rep("x", 400),
})
assert(started and startCode == "OK" and operation.addonId == "Craft"
	and operation.playerNum == 0 and operation.networkId == "net-a"
	and operation.batchCount == 2, "startOperation lost authoritative ownership")
assert(#sentCommands == 1 and sentCommands[1].command == "craftAttemptStart",
	"startOperation diagnostics did not use the internal bounded command")
local diagnostic = sentCommands[1].payload
local diagnosticKeys = 0
for key in pairs(diagnostic) do
	diagnosticKeys = diagnosticKeys + 1
	assert(key == "operationId" or key == "addonId" or key == "recipe"
		or key == "networkId" or key == "isCanBeDoneFromFloor"
		or key == "containersCliente", "diagnostics leaked caller field: " .. tostring(key))
end
assert(diagnosticKeys == 6 and diagnostic.networkId == "net-a"
	and diagnostic.containersCliente == 4, "diagnostics payload was not exact and bounded")

local operationId = operation.operationId
operation.networkId = "mutated"
operation.addonId = "mutated"
local claimOk, claimCode, recipeClaim = WorkSession.claimRecipeInputs(
	operationId, owner, {}, { "ingredient" }, 2)
assert(claimOk and claimCode == "OK" and recipeClaim.claimedCount == 2
	and lastClaimRecipe.networkId == "net-a" and lastClaimRecipe.count == 2,
	"claimRecipeInputs did not use the retained operation ownership")
assert(WorkSession.claimRecipeInputs(operationId, stranger, {}, {}, 1) == false,
	"claimRecipeInputs accepted another player")
local sourceOk, sourceCode = WorkSession.claimItem(
	operationId, owner, {}, { networkId = "other" })
assert(sourceOk == false and sourceCode == "ERR_SOURCE",
	"claimItem accepted a container from another network")
sourceOk, sourceCode = WorkSession.claimItem(
	operationId, owner, {}, { networkId = "net-a" })
assert(sourceOk == true and sourceCode == "OK" and lastClaimItem.networkId == "net-a",
	"claimItem rejected the authoritative network source")
assert(WorkSession.completeOperation(operationId, stranger) == false,
	"completeOperation accepted another player")
local completeOk, completeCode = WorkSession.completeOperation(operationId, owner)
assert(completeOk and completeCode == "OK" and completed[operationId],
	"completeOperation did not finish owned operation")
assert(WorkSession.completeOperation(operationId, owner) == false,
	"completed operation remained public")

local abortStarted, _, abortSnapshot = WorkSession.startOperation({
	addonId = "Craft", player = owner, kind = "recipe",
})
assert(abortStarted, "abort fixture did not start")
local abortOk, abortCode = WorkSession.abortOperation(abortSnapshot.operationId, owner)
assert(abortOk and abortCode == "OK" and aborted[abortSnapshot.operationId],
	"abortOperation did not close owned operation")

local cleanupStarted, _, cleanupSnapshot = WorkSession.startOperation({
	addonId = "Craft", player = owner, kind = "recipe",
})
assert(cleanupStarted, "session cleanup fixture did not start")
local cleanupEnded, cleanupEndCode = WorkSession.endSession("session_closed")
assert(cleanupEnded and cleanupEndCode == "OK"
	and WorkSession.completeOperation(cleanupSnapshot.operationId, owner) == false,
	"endSession retained an operation outside its owning session")

local panel, items = {}, { "item" }
local narrowed, narrowCode, narrowHandle = WorkSession.narrowInputs(panel, items, "Craft")
assert(narrowed and narrowCode == "OK" and narrowHandle,
	"narrowInputs rejected valid input")
assert(narrowHandle:restore() == true and narrowHandle:restore() == false
	and narrowHandle:dispose() == false and restoreCalls == 1,
	"narrowInputs restore handle was not idempotent")
local suspended = WorkSession.withContainerInjectionSuspended(function(a, b)
	return a .. b
end, "a", "b")
assert(suspended == "ab", "withContainerInjectionSuspended did not preserve callback results")

print("gssik_api_work_session_contract: OK")

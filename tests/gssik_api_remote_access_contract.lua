-- Author contract for GSSiK.API.RemoteAccess.
-- Executes the real public client facade against bounded neutral collaborators.

local apiPath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
	.. "GSSiK_API_Client.lua"

local function read(path)
	local handle = io.open(path, "rb")
	if not handle then return nil end
	local source = handle:read("*a")
	handle:close()
	return source
end

local source = assert(read(apiPath), "missing public client API: " .. apiPath)
for _, symbol in ipairs({
	"function RemoteAccess.list(", "function RemoteAccess.open(",
	"function RemoteAccess.registerCleanup(", "function handle:cancel()",
	"function handle:dispose()", "local function copyPlain(",
	"local generation = cleanupGeneration", "entry.generation == generation",
}) do
	assert(source:find(symbol, 1, true), "public remote API omits contract: " .. symbol)
end
for _, forbidden in ipairs({
	"Events.OnTick", "Events.OnKey", "sendClientCommand(", "while true do",
}) do
	assert(not source:find(forbidden, 1, true),
		"public remote API owns forbidden global/unbounded route: " .. forbidden)
end

package.loaded["GSSiK_API"] = true
package.loaded["GS_PlayerUtils"] = true
package.loaded["GS_TerminalUI_Api"] = true
package.loaded["GS_ItemActions"] = true
package.loaded["GSSiK_API_WorkSession"] = true
package.loaded["GSSiK_API_Terminal"] = true

local nextRequestId = 200
local listRequests, openRequests = {}, {}
local cancelledLists, cancelledOpens = {}, {}
local cleanupCallbacks = {}

local function player(number)
	return { getPlayerNum = function() return number end }
end

local TerminalUI = {}
function TerminalUI.requestRemoteNetworks(callback, playerArg)
	nextRequestId = nextRequestId + 1
	listRequests[nextRequestId] = { callback = callback, player = playerArg }
	return nextRequestId
end
function TerminalUI.cancelRemoteNetworkRequest(requestId, playerArg)
	cancelledLists[#cancelledLists + 1] = { requestId = requestId, player = playerArg }
end
function TerminalUI.requestOpenNetwork(networkId, playerArg, callback)
	nextRequestId = nextRequestId + 1
	openRequests[nextRequestId] = {
		networkId = networkId, player = playerArg, callback = callback,
	}
	return nextRequestId
end
function TerminalUI.cancelOpenNetworkRequest(requestId, playerArg)
	cancelledOpens[#cancelledOpens + 1] = { requestId = requestId, player = playerArg }
end

GSSiK = { API = { RemoteAccess = {}, ItemActions = {} } }
GlobalStorageSiK = {
	PlayerUtils = { resolve = function(value) return value end },
	TerminalUI = TerminalUI,
	Client = {
		registerTransientCleanup = function(id, callback)
			cleanupCallbacks[#cleanupCallbacks + 1] = { id = id, callback = callback }
			return true
		end,
	},
	ItemActions = {},
}

local API = assert(dofile(apiPath), "public client API did not return GSSiK.API")
local RemoteAccess = assert(API.RemoteAccess, "RemoteAccess public surface missing")
local p0, p1 = player(0), player(1)

local ok, code, handle = RemoteAccess.list(p0, nil)
assert(ok == false and code == "ERR_SCHEMA" and handle == nil,
	"list accepted a non-callback")
ok, code, handle = RemoteAccess.open("", p0, nil)
assert(ok == false and code == "ERR_SCHEMA" and handle == nil,
	"open accepted an empty networkId")
ok, code, handle = RemoteAccess.open(string.rep("n", 129), p0, nil)
assert(ok == false and code == "ERR_SCHEMA" and handle == nil,
	"open accepted an oversized networkId")

local staleCalls = 0
local okA, codeA, staleHandle = RemoteAccess.list(p0, function()
	staleCalls = staleCalls + 1
end)
assert(okA and codeA == "OK" and staleHandle and staleHandle.kind == "list",
	"list did not return a cancellable handle")
local staleRequestId = staleHandle.requestId
local copiedNetworks, copyCalls
local okB, codeB, currentHandle = RemoteAccess.list(p0, function(accepted, reason, networks)
	copyCalls = (copyCalls or 0) + 1
	assert(accepted == true and reason == "OK", "list success callback was not normalized")
	copiedNetworks = networks
end)
assert(okB and codeB == "OK" and currentHandle,
	"replacement list request was rejected")
assert(staleHandle.done == true and cancelledLists[#cancelledLists].requestId == staleRequestId,
	"same-player generation did not dispose the stale list request")
listRequests[staleRequestId].callback({ { networkId = "stale" } }, nil)
assert(staleCalls == 0, "stale list generation invoked its callback")

local rawNetworks = {
	{ networkId = "net-a", label = "Alpha", provider = { id = "antenna-a" } },
}
local currentRequestId = currentHandle.requestId
listRequests[currentRequestId].callback(rawNetworks, nil)
listRequests[currentRequestId].callback({ { networkId = "duplicate-callback" } }, nil)
assert(copyCalls == 1 and copiedNetworks[1].networkId == "net-a",
	"list callback was not one-shot")
rawNetworks[1].networkId = "mutated"
rawNetworks[1].provider.id = "mutated"
assert(copiedNetworks[1].networkId == "net-a"
	and copiedNetworks[1].provider.id == "antenna-a",
	"list leaked the mutable transport payload")

local cancelledCode, cancelledCalls = nil, 0
local _, _, cancelHandle = RemoteAccess.list(p1, function(accepted, reason)
	cancelledCalls = cancelledCalls + 1
	assert(accepted == false, "cancel callback reported success")
	cancelledCode = reason
end)
local cancelRequestId = cancelHandle.requestId
assert(cancelHandle:cancel() == true and cancelHandle:cancel() == false,
	"cancel was not exact and idempotent")
assert(cancelledCode == "ERR_CANCELLED" and cancelledCalls == 1
	and cancelledLists[#cancelledLists].requestId == cancelRequestId,
	"cancel did not notify once and cancel the exact Core request")

local disposeCalls = 0
local _, _, disposeHandle = RemoteAccess.list(p1, function() disposeCalls = disposeCalls + 1 end)
local disposeRequestId = disposeHandle.requestId
assert(disposeHandle:dispose() == true and disposeHandle:dispose() == false,
	"dispose was not exact and idempotent")
assert(disposeCalls == 0 and cancelledLists[#cancelledLists].requestId == disposeRequestId,
	"dispose notified the consumer or cancelled the wrong request")

local badAccepted, badCode
local _, _, badHandle = RemoteAccess.list(p1, function(accepted, reason)
	badAccepted, badCode = accepted, reason
end)
listRequests[badHandle.requestId].callback({ invalid = function() end }, nil)
assert(badAccepted == false and badCode == "ERR_PAYLOAD",
	"list accepted a non-plain payload")

local openResult, openCalls
local openOk, openCode, openHandle = RemoteAccess.open("net-exact", p0,
	function(accepted, reason, payload)
		openCalls = (openCalls or 0) + 1
		assert(accepted == true and reason == "OK", "open success callback was not normalized")
		openResult = payload
	end)
assert(openOk and openCode == "OK" and openHandle
	and openRequests[openHandle.requestId].networkId == "net-exact"
	and openRequests[openHandle.requestId].player == p0,
	"open lost exact networkId or player identity")
local rawOpen = { networkId = "net-exact", nested = { permitted = true } }
local openRequestId = openHandle.requestId
openRequests[openRequestId].callback(true, nil, rawOpen)
openRequests[openRequestId].callback(true, nil, { networkId = "late" })
rawOpen.nested.permitted = false
assert(openCalls == 1 and openResult.networkId == "net-exact"
	and openResult.nested.permitted == true,
	"open callback was not one-shot or leaked its payload")

local _, _, cancelOpenHandle = RemoteAccess.open("net-cancel", p1, function() end)
local cancelOpenId = cancelOpenHandle.requestId
assert(cancelOpenHandle:dispose() == true
	and cancelledOpens[#cancelledOpens].requestId == cancelOpenId,
	"open dispose did not cancel the exact Core request")

local oldCleanupCalls, newCleanupCalls = 0, 0
local registeredOld, registerCodeOld, oldRegistration =
	RemoteAccess.registerCleanup("selector", function() oldCleanupCalls = oldCleanupCalls + 1 end)
local registeredNew, registerCodeNew, newRegistration =
	RemoteAccess.registerCleanup("selector", function() newCleanupCalls = newCleanupCalls + 1 end)
assert(registeredOld and registerCodeOld == "OK" and oldRegistration
	and registeredNew and registerCodeNew == "OK" and newRegistration,
	"registerCleanup did not return public generation handles")
local oldCleanup = cleanupCallbacks[#cleanupCallbacks - 1]
local newCleanup = cleanupCallbacks[#cleanupCallbacks]
oldCleanup.callback(0)
newCleanup.callback(0)
assert(oldCleanupCalls == 0 and newCleanupCalls == 1,
	"stale cleanup generation remained authoritative")
assert(oldRegistration:dispose() == false and newRegistration:dispose() == true
	and newRegistration:dispose() == false,
	"cleanup generation disposal removed the wrong registration")
newCleanup.callback(0)
assert(newCleanupCalls == 1, "disposed cleanup callback retained its consumer handler")

local badCleanup, badCleanupCode, badCleanupHandle =
	RemoteAccess.registerCleanup("", function() end)
assert(badCleanup == false and badCleanupCode == "ERR_SCHEMA" and badCleanupHandle == nil,
	"registerCleanup accepted an invalid id")

-- The facade registers one product-owned sweep and does not install polling.
local productCleanupCount = 0
for _, entry in ipairs(cleanupCallbacks) do
	if entry.id == "GSSiK.API.RemoteAccess" then productCleanupCount = productCleanupCount + 1 end
end
assert(productCleanupCount == 1,
	"RemoteAccess registered zero or duplicate product cleanup hooks")

print("gssik_api_remote_access_contract: OK")

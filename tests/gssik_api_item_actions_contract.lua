-- Author contract for GSSiK.API.ItemActions.
-- Executes the real public facade against a generation-aware internal registry.

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
	"function ItemActions.registerTablet(", "function ItemActions.registerProvider(",
	"local function copyProviderDefinition(", "local function actionRegistration(",
	"removeTabletItemIfGeneration", "removeProviderIfGeneration",
}) do
	assert(source:find(symbol, 1, true), "ItemActions public API omits: " .. symbol)
end
for _, forbidden in ipairs({ "Events.OnTick", "sendClientCommand(", "while true do" }) do
	assert(not source:find(forbidden, 1, true),
		"ItemActions facade owns forbidden global/protocol route: " .. forbidden)
end

package.loaded["GSSiK_API"] = true
package.loaded["GS_PlayerUtils"] = true
package.loaded["GS_TerminalUI_Api"] = true
package.loaded["GS_ItemActions"] = true
package.loaded["GSSiK_API_WorkSession"] = true
package.loaded["GSSiK_API_Terminal"] = true

local generation = 0
local tablets, providers = {}, {}
local lastTabletDefinition, lastProviderDefinition
local internal = {}

function internal.registerTabletItem(fullType, labelKey, onUse)
	generation = generation + 1
	lastTabletDefinition = { fullType = fullType, labelKey = labelKey, onUse = onUse }
	tablets[fullType] = { labelKey = labelKey, onUse = onUse, generation = generation }
	return true, generation
end

function internal.removeTabletItemIfGeneration(fullType, expectedGeneration)
	local current = tablets[fullType]
	if not current or current.generation ~= expectedGeneration then return false end
	tablets[fullType] = nil
	return true
end

function internal.registerProvider(definition)
	generation = generation + 1
	lastProviderDefinition = definition
	providers[definition.id] = { definition = definition, generation = generation }
	return true, generation
end

function internal.removeProviderIfGeneration(id, expectedGeneration)
	local current = providers[id]
	if not current or current.generation ~= expectedGeneration then return false end
	providers[id] = nil
	return true
end

GSSiK = { API = { RemoteAccess = {}, ItemActions = {} } }
GlobalStorageSiK = {
	ItemActions = internal,
	PlayerUtils = { resolve = function(value) return value end },
	TerminalUI = {},
	Client = { registerTransientCleanup = function() return true end },
}

local API = assert(dofile(apiPath), "public client API did not return GSSiK.API")
local ItemActions = assert(API.ItemActions, "ItemActions public surface missing")
local callback = function() return "used" end

local function rejectsTablet(definition, label)
	local ok, code, registration = ItemActions.registerTablet(definition)
	assert(ok == false and code == "ERR_SCHEMA" and registration == nil,
		"registerTablet accepted invalid " .. label)
end

rejectsTablet(nil, "definition")
rejectsTablet({}, "empty definition")
rejectsTablet({ fullType = "", labelKey = "Label", onUse = callback }, "fullType")
rejectsTablet({ fullType = string.rep("x", 129), labelKey = "Label", onUse = callback },
	"oversized fullType")
rejectsTablet({ fullType = "Addon.Tablet", labelKey = "", onUse = callback }, "labelKey")
rejectsTablet({ fullType = "Addon.Tablet", labelKey = string.rep("x", 129),
	onUse = callback }, "oversized labelKey")
rejectsTablet({ fullType = "Addon.Tablet", labelKey = "Label" }, "callback")

local tabletDefinition = {
	fullType = "Addon.Tablet", labelKey = "IGUI_Addon_Tablet", onUse = callback,
	private = { mustNotCross = true },
}
local ok, code, oldTablet = ItemActions.registerTablet(tabletDefinition)
assert(ok and code == "OK" and oldTablet and oldTablet.id == "Addon.Tablet",
	"registerTablet rejected a valid definition")
assert(lastTabletDefinition.fullType == "Addon.Tablet"
	and lastTabletDefinition.labelKey == "IGUI_Addon_Tablet"
	and lastTabletDefinition.onUse == callback
	and lastTabletDefinition.private == nil,
	"registerTablet leaked or changed its public fields")
tabletDefinition.fullType = "mutated"
tabletDefinition.labelKey = "mutated"
assert(tablets["Addon.Tablet"].labelKey == "IGUI_Addon_Tablet",
	"registerTablet retained the mutable definition table")

local replacementCallback = function() return "replacement" end
local replacementOk, replacementCode, newTablet = ItemActions.registerTablet({
	fullType = "Addon.Tablet", labelKey = "IGUI_Addon_Tablet_New",
	onUse = replacementCallback,
})
assert(replacementOk and replacementCode == "OK" and newTablet,
	"replacement tablet registration failed")
assert(oldTablet:dispose() == false,
	"stale tablet registration removed a newer generation")
assert(tablets["Addon.Tablet"].onUse == replacementCallback,
	"new tablet generation was lost")
assert(newTablet:dispose() == true and newTablet:dispose() == false
	and tablets["Addon.Tablet"] == nil,
	"tablet disposal was not generation-safe and idempotent")

local function validProvider(id)
	return {
		id = id or "provider-a",
		addonId = "AddonA",
		capabilities = { "craft", "build" },
		actions = {
			{ id = "open", labelKey = "IGUI_Addon_Open", private = "drop" },
			{ id = "inspect", labelKey = "IGUI_Addon_Inspect" },
		},
		appliesTo = function() return true end,
		buildRequest = function() return { exact = true } end,
		executeRequest = function() return true end,
		private = { mustNotCross = true },
	}
end

local function rejectsProvider(definition, label)
	local providerOk, providerCode, registration = ItemActions.registerProvider(definition)
	assert(providerOk == false and providerCode == "ERR_SCHEMA" and registration == nil,
		"registerProvider accepted invalid " .. label)
end

rejectsProvider(nil, "definition")
local invalid = validProvider("")
rejectsProvider(invalid, "id")
invalid = validProvider(string.rep("p", 97))
rejectsProvider(invalid, "oversized id")
invalid = validProvider(); invalid.addonId = ""
rejectsProvider(invalid, "addonId")
invalid = validProvider(); invalid.capabilities = { "" }
rejectsProvider(invalid, "capability")
invalid = validProvider(); invalid.actions = {}
rejectsProvider(invalid, "empty actions")
invalid = validProvider(); invalid.actions = { { id = "", labelKey = "Label" } }
rejectsProvider(invalid, "action id")
invalid = validProvider(); invalid.appliesTo = nil
rejectsProvider(invalid, "appliesTo")
invalid = validProvider(); invalid.buildRequest = nil
rejectsProvider(invalid, "buildRequest")
invalid = validProvider(); invalid.executeRequest = nil
rejectsProvider(invalid, "execute callback")

local providerDefinition = validProvider()
local expectedApplies = providerDefinition.appliesTo
local expectedBuild = providerDefinition.buildRequest
local expectedExecute = providerDefinition.executeRequest
local providerOk, providerCode, oldProvider = ItemActions.registerProvider(providerDefinition)
assert(providerOk and providerCode == "OK" and oldProvider
	and oldProvider.id == "provider-a",
	"registerProvider rejected a valid definition")
assert(lastProviderDefinition ~= providerDefinition
	and lastProviderDefinition.capabilities ~= providerDefinition.capabilities
	and lastProviderDefinition.actions ~= providerDefinition.actions
	and lastProviderDefinition.actions[1] ~= providerDefinition.actions[1],
	"registerProvider did not make owned descriptor copies")
assert(lastProviderDefinition.private == nil
	and lastProviderDefinition.actions[1].private == nil,
	"registerProvider copied undeclared private fields")
assert(lastProviderDefinition.appliesTo == expectedApplies
	and lastProviderDefinition.buildRequest == expectedBuild
	and lastProviderDefinition.executeRequest == expectedExecute,
	"registerProvider changed executable callbacks")
providerDefinition.capabilities[1] = "mutated"
providerDefinition.actions[1].id = "mutated"
providerDefinition.id = "mutated"
assert(lastProviderDefinition.id == "provider-a"
	and lastProviderDefinition.capabilities[1] == "craft"
	and lastProviderDefinition.actions[1].id == "open",
	"registered provider changed after caller mutation")

local replacementProvider = validProvider()
replacementProvider.actions = { { id = "replacement", labelKey = "IGUI_Replacement" } }
local newProviderOk, newProviderCode, newProvider =
	ItemActions.registerProvider(replacementProvider)
assert(newProviderOk and newProviderCode == "OK" and newProvider,
	"replacement provider registration failed")
assert(oldProvider:dispose() == false,
	"stale provider registration removed a newer generation")
assert(providers["provider-a"].definition.actions[1].id == "replacement",
	"new provider generation was lost")
assert(newProvider:dispose() == true and newProvider:dispose() == false
	and providers["provider-a"] == nil,
	"provider disposal was not generation-safe and idempotent")

local executeOnly = validProvider("provider-execute")
executeOnly.execute = executeOnly.executeRequest
executeOnly.executeRequest = nil
local executeOk, executeCode, executeRegistration = ItemActions.registerProvider(executeOnly)
assert(executeOk and executeCode == "OK" and executeRegistration,
	"registerProvider rejected the documented execute compatibility callback")
assert(executeRegistration:dispose() == true,
	"execute-compatible provider did not dispose")

local savedInternal = GlobalStorageSiK.ItemActions
GlobalStorageSiK.ItemActions = nil
local unavailable, unavailableCode, unavailableRegistration = ItemActions.registerTablet({
	fullType = "Addon.Missing", labelKey = "IGUI_Missing", onUse = callback,
})
assert(unavailable == false and unavailableCode == "ERR_UNAVAILABLE"
	and unavailableRegistration == nil,
	"registerTablet masked an unavailable internal registry")
GlobalStorageSiK.ItemActions = savedInternal

local originalRegisterProvider = internal.registerProvider
internal.registerProvider = function() return false end
local failedProvider, failedCode, failedRegistration =
	ItemActions.registerProvider(validProvider("provider-failed"))
assert(failedProvider == false and failedCode == "ERR_REQUEST"
	and failedRegistration == nil,
	"registerProvider masked an internal registration failure")
internal.registerProvider = originalRegisterProvider

print("gssik_api_item_actions_contract: OK")

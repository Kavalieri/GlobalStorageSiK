-- Public GSSiK.API capability negotiation contract.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

package.loaded["GS_AddonRegistry"] = true
package.loaded["GS_DiskProgramming"] = true
package.loaded["GS_TerminalAccess"] = true

GlobalStorageSiK = {
	AddonRegistry = {},
	DiskProgramming = {},
	TerminalAccess = {},
	Addons = {},
}

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GSSiK_API.lua")

local descriptor = GSSiK.API.Capabilities.describe()
assert(descriptor.api == "GSSiK.API", "descriptor must identify the exact public namespace")
assert(descriptor.apiVersion == "1.0.0-dev1", "descriptor must expose semantic API version")
local expected = {
	Addon = "1.0.0",
	Access = "1.0.0",
	Installation = "1.0.0",
	RemoteAccess = "1.0.0",
	Diagnostics = "1.0.0",
	ItemActions = "1.0.0",
	WorkSession = "1.0.0",
	Terminal = "1.0.0",
}
assert(#descriptor.capabilities == 8,
	"descriptor must advertise every implemented public capability")
for index = 1, #descriptor.capabilities do
	local capability = descriptor.capabilities[index]
	assert(expected[capability.name] == capability.version,
		"unexpected or misversioned capability " .. tostring(capability.name))
	expected[capability.name] = nil
end
for name in pairs(expected) do
	error("missing public capability " .. tostring(name))
end

local firstName = descriptor.capabilities[1].name
descriptor.capabilities[1].name = "mutated"
local fresh = GSSiK.API.Capabilities.describe()
assert(fresh.capabilities[1].name == firstName, "descriptors must be defensive copies")

local available, code = GSSiK.API.Capabilities.has("Addon", "1.0.0")
assert(available == true and code == "OK", "exact compatible capability must negotiate")
local workAvailable, workCode = GSSiK.API.Capabilities.has("WorkSession", "1.0.0")
assert(workAvailable == true and workCode == "OK",
	"shared Craft/Builder session must negotiate as WorkSession")
local legacy, legacyCode = GSSiK.API.Capabilities.has("CraftSession")
assert(legacy == false and legacyCode == "ERR_CAPABILITY_UNAVAILABLE",
	"misleading CraftSession public alias must not be advertised")
local future, futureCode = GSSiK.API.Capabilities.has("Addon", "1.1.0")
assert(future == false and futureCode == "ERR_CAPABILITY_VERSION",
	"unsupported capability version must fail explicitly")
local missing, missingCode = GSSiK.API.Capabilities.has("Storage")
assert(missing == false and missingCode == "ERR_CAPABILITY_UNAVAILABLE",
	"unimplemented capabilities must not be advertised")
local invalid, invalidCode = GSSiK.API.Capabilities.has("Addon", "future")
assert(invalid == false and invalidCode == "ERR_SCHEMA",
	"invalid minimum versions must fail schema validation")

print("gssik_api_capabilities_contract: OK")

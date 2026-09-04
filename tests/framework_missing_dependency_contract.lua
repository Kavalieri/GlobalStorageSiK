-- Executable author contract: Global Storage must fail closed with one stable,
-- actionable error when its mandatory SiKUIFramework dependency is absent.
-- Pure Lua 5.1; the fixture deliberately does not load Project Zomboid.

local ADAPTER = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_UI_Framework.lua"
local EXPECTED_ERROR = "Global Storage SiK requires the SiKUIFramework mod (SiK.UI unavailable)"

local function executeWithFrameworkLoader(loader)
	local chunk = assert(loadfile(ADAPTER))
	local originalRequire = _G.require
	local originalSiK = _G.SiK
	local originalProduct = _G.GlobalStorageSiK
	local productSentinel = { privateFallback = true }
	local calls = {}

	_G.SiK = nil
	_G.GlobalStorageSiK = productSentinel
	_G.require = function(moduleName)
		calls[#calls + 1] = moduleName
		if moduleName ~= "SiK_UI" then
			error("unexpected fallback require: " .. tostring(moduleName), 0)
		end
		return loader()
	end

	local ok, result = pcall(chunk)
	local productAfterLoad = _G.GlobalStorageSiK
	local sikAfterLoad = _G.SiK

	_G.require = originalRequire
	_G.SiK = originalSiK
	_G.GlobalStorageSiK = originalProduct

	return {
		ok = ok,
		result = result,
		calls = calls,
		productAfterLoad = productAfterLoad,
		sikAfterLoad = sikAfterLoad,
		productSentinel = productSentinel,
	}
end

local function hasStableError(result)
	return type(result) == "string" and result:find(EXPECTED_ERROR, 1, true) ~= nil
end

local failures = {}
local function check(condition, message)
	if not condition then failures[#failures + 1] = message end
end

local absent = executeWithFrameworkLoader(function()
	error("module 'SiK_UI' not found: deliberately absent", 0)
end)
check(absent.ok == false, "missing SiK_UI must stop Core loading")
check(hasStableError(absent.result),
	"missing SiK_UI must be translated to the stable SiKUIFramework dependency error; got: "
		.. tostring(absent.result))
check(#absent.calls == 1 and absent.calls[1] == "SiK_UI",
	"missing dependency must attempt only the public SiK_UI entrypoint")
check(absent.productAfterLoad == absent.productSentinel,
	"missing dependency must not replace or populate a private product fallback")
check(absent.sikAfterLoad == nil,
	"missing dependency must not synthesize a SiK namespace")

local invalidNamespace = executeWithFrameworkLoader(function()
	_G.SiK = {}
	return true
end)
check(invalidNamespace.ok == false, "SiK_UI without SiK.UI must stop Core loading")
check(hasStableError(invalidNamespace.result),
	"invalid SiK.UI namespace must use the same stable dependency error; got: "
		.. tostring(invalidNamespace.result))
check(#invalidNamespace.calls == 1 and invalidNamespace.calls[1] == "SiK_UI",
	"invalid namespace must not probe legacy/private framework modules")
check(invalidNamespace.productAfterLoad == invalidNamespace.productSentinel,
	"invalid namespace must not install a private product fallback")

if #failures > 0 then
	error("framework_missing_dependency_contract failed:\n - " .. table.concat(failures, "\n - "), 0)
end

print("framework_missing_dependency_contract: OK")

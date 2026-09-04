-- Shared runner for author-side SiK UI contracts.
-- The production framework is an independent ModID, so every runtime contract
-- loads the public SiK.UI module from that repository.  A missing public module
-- is BLOCKED; private Core clones are never accepted as a substitute.

local Support = {}

local function fileExists(path)
	local file = io.open(path, "rb")
	if not file then return false end
	file:close()
	return true
end

function Support.newSuite(name)
	return {
		name = name,
		startedAt = os.clock(),
		passed = 0,
		blocked = 0,
		failed = 0,
		messages = {},
	}
end

local function record(suite, status, label, detail)
	if status == "PASS" then suite.passed = suite.passed + 1
	elseif status == "BLOCKED" then suite.blocked = suite.blocked + 1
	else suite.failed = suite.failed + 1 end
	suite.messages[#suite.messages + 1] = status .. " " .. label
		.. (detail and detail ~= "" and (" :: " .. tostring(detail)) or "")
end

function Support.pass(suite, label)
	record(suite, "PASS", label)
end

function Support.blocked(suite, label, detail)
	record(suite, "BLOCKED", label, detail)
end

function Support.fail(suite, label, detail)
	record(suite, "FAIL", label, detail)
end

function Support.check(suite, label, callback)
	local ok, result = pcall(callback)
	if ok and result ~= false then
		Support.pass(suite, label)
	else
		Support.fail(suite, label, ok and "returned false" or result)
	end
end

function Support.requireFunction(suite, owner, key, label)
	if type(owner) ~= "table" or type(owner[key]) ~= "function" then
		Support.blocked(suite, label, "missing function " .. tostring(key))
		return nil
	end
	return owner[key]
end

local FRAMEWORK_ROOT = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/"

function Support.frameworkRoot()
	return FRAMEWORK_ROOT
end

function Support.frameworkPath(relativePath)
	return FRAMEWORK_ROOT .. "SiK/UI/" .. tostring(relativePath or "")
end

local harnessReady = false
local function prepareFrameworkHarness()
	if harnessReady then return end
	-- Reuse the framework's neutral PZ widget stub so Core-side contracts exercise
	-- exactly the same public modules as the standalone repository tests.
	dofile("../SiKUIFramework-Repo/tests/geometry/pz_ui_stub.lua")
	if not string.find(package.path, FRAMEWORK_ROOT .. "?.lua", 1, true) then
		package.path = FRAMEWORK_ROOT .. "?.lua;" .. package.path
	end
	harnessReady = true
end

function Support.loadFrameworkModule(suite, moduleName)
	prepareFrameworkHarness()
	local path = FRAMEWORK_ROOT .. "SiK/UI/" .. moduleName .. ".lua"
	if not fileExists(path) then
		Support.blocked(suite, "SiK.UI." .. moduleName, "public module not implemented")
		return nil
	end
	local ok, result = pcall(require, "SiK/UI/" .. moduleName)
	if not ok then
		Support.fail(suite, "SiK.UI." .. moduleName,
			"public module cannot load in author harness: " .. tostring(result))
		return nil
	end
	if type(SiK) ~= "table" or type(SiK.UI) ~= "table"
		or SiK.UI[moduleName] ~= result then
		Support.fail(suite, "SiK.UI." .. moduleName,
			"module is not published through the exact public namespace")
		return nil
	end
	return result
end

function Support.assertNumber(value, label)
	assert(type(value) == "number", label .. " must be numeric")
	assert(value == value, label .. " must not be NaN")
end

function Support.assertRect(rect, label)
	assert(type(rect) == "table", label .. " must be a table")
	for _, key in ipairs({ "x", "y", "w", "h" }) do
		Support.assertNumber(rect[key], label .. "." .. key)
	end
	assert(rect.w >= 0 and rect.h >= 0, label .. " dimensions must be non-negative")
end

function Support.assertWithin(inner, outer, label)
	Support.assertRect(inner, label .. " inner")
	Support.assertRect(outer, label .. " outer")
	assert(inner.x >= outer.x, label .. " exceeds left edge")
	assert(inner.y >= outer.y, label .. " exceeds top edge")
	assert(inner.x + inner.w <= outer.x + outer.w, label .. " exceeds right edge")
	assert(inner.y + inner.h <= outer.y + outer.h, label .. " exceeds bottom edge")
end

function Support.finish(suite)
	for i = 1, #suite.messages do print(suite.messages[i]) end
	local elapsedMs = math.floor((os.clock() - suite.startedAt) * 1000 + 0.5)
	local summary = string.format(
		"%s: pass=%d blocked=%d fail=%d durationMs=%d",
		suite.name, suite.passed, suite.blocked, suite.failed, elapsedMs)
	print(summary)
	if suite.blocked > 0 or suite.failed > 0 then
		error(summary, 0)
	end
	return true
end

return Support

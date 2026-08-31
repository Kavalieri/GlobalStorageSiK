-- Shared runner for author-side SiK UI geometry contracts.
-- It deliberately distinguishes missing foundation modules (BLOCKED) from
-- implemented contracts that return invalid geometry (FAIL).

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

function Support.loadClientModule(suite, moduleName)
	local clientRoot = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
	local path = clientRoot .. moduleName .. ".lua"
	if not fileExists(path) then
		Support.blocked(suite, moduleName, "module not implemented")
		return false
	end
        GlobalStorageSiK = GlobalStorageSiK or {}
        GlobalStorageSiK.SiK_UI = GlobalStorageSiK.SiK_UI or {}
        -- Metrics consumes the framework-owned WindowChrome token.  The pure
        -- harness stubs Core, so it supplies the same public accessor rather
        -- than allowing a module-local geometry fallback.
        GlobalStorageSiK.SiK_UI.CHROME = GlobalStorageSiK.SiK_UI.CHROME or {
                headerHeight = 48,
                closeButtonSize = 36,
                horizontalPadding = 14,
                titleCloseGap = 12,
        }
        GlobalStorageSiK.SiK_UI.windowChrome = GlobalStorageSiK.SiK_UI.windowChrome
                or function() return GlobalStorageSiK.SiK_UI.CHROME end
	-- Foundation modules may keep their normal PZ requires. The geometry APIs
	-- exercised here are pure, so loading them only needs dependency sentinels;
	-- no game object is instantiated and no PZ runtime is simulated.
	package.loaded["GS_SiK_UI_Core"] = package.loaded["GS_SiK_UI_Core"] or true
	package.loaded["ISUI/ISModalDialog"] = package.loaded["ISUI/ISModalDialog"] or true
	package.loaded["GS_TerminalUI_Scroll"] = package.loaded["GS_TerminalUI_Scroll"] or true
	if not string.find(package.path, clientRoot .. "?.lua", 1, true) then
		package.path = clientRoot .. "?.lua;" .. package.path
	end
	local ok, result = pcall(dofile, path)
	if not ok then
		Support.fail(suite, moduleName, "module cannot load in author harness: " .. tostring(result))
		return false
	end
	return true
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

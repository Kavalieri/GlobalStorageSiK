-- Binding author contract for the independent SiK.UI framework and products.
-- Source-only by design: it must expose incomplete migration without loading PZ.

local failures, passed = {}, 0

local function check(label, callback)
	local ok, detail = pcall(callback)
	if ok then
		passed = passed + 1
		print("PASS " .. label)
	else
		failures[#failures + 1] = label .. ": " .. tostring(detail)
		print("FAIL " .. failures[#failures])
	end
end

local function read(path)
	local handle = assert(io.open(path, "rb"), "cannot read " .. path)
	local text = handle:read("*a")
	handle:close()
	return text
end

local function luaFiles(path)
	local command = 'rg --files "' .. path .. '" -g "*.lua"'
	local pipe = assert(io.popen(command, "r"), "cannot enumerate " .. path)
	local files = {}
	for file in pipe:lines() do files[#files + 1] = file:gsub("\\", "/") end
	local ok = pipe:close()
	assert(ok ~= nil, "rg failed for " .. path)
	table.sort(files)
	assert(#files > 0, "no Lua files under " .. path)
	return files
end

local function combined(files)
	local parts = {}
	for index = 1, #files do
		parts[#parts + 1] = "\n-- " .. files[index] .. "\n" .. read(files[index])
	end
	return table.concat(parts)
end

local function codeOnly(text)
	-- Dependency checks must inspect executable references. Public API comments
	-- are allowed to explain that product mechanics are separate from SiK.UI;
	-- they do not turn the framework into a runtime dependency.
	text = tostring(text or ""):gsub("%-%-%[%[.-%]%]", "")
	return text:gsub("%-%-[^\r\n]*", "")
end

local function requires(source, moduleName)
	local escaped = tostring(moduleName):gsub("([^%w])", "%%%1")
	return source:match("require%s*[%\"']" .. escaped .. "[%\"']") ~= nil
		or source:match("require%s*%(%s*[%\"']" .. escaped .. "[%\"']%s*%)") ~= nil
end

local function parseDependencies(source, label)
	local result = {}
	for line in tostring(source or ""):gmatch("[^\r\n]+") do
		local value = line:match("^require=(.*)$")
		if value then
			assert(not value:find("[\\/]"),
				tostring(label or "dependency list") .. " contains a slash or backslash")
			for id in value:gmatch("[^,;]+") do
				id = id:match("^%s*(.-)%s*$")
				assert(id ~= "", tostring(label or "dependency list") .. " contains an empty ModID")
				result[#result + 1] = id
			end
		end
	end
	table.sort(result)
	return result
end

local function dependencies(path)
	return parseDependencies(read(path), path)
end

local function exactDependencies(path, expected)
	local actual = dependencies(path)
	assert(#actual == #expected,
		path .. " dependency count expected " .. #expected .. " got " .. #actual)
	for index = 1, #expected do
		assert(actual[index] == expected[index],
			path .. " dependency expected " .. expected[index] .. " got " .. tostring(actual[index]))
	end
end

local coreRoot = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/"
local frameworkRoot = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/"
local addonRoots = {
	Craft = "addons/GSSiK_Addon_Craft/Contents/mods/GSSiK_Addon_Craft/42/",
	Builder = "addons/GSSiK_Addon_Builder/Contents/mods/GSSiK_Addon_Builder/42/",
	Tablet = "addons/GSSiK_Addon_Tablet/Contents/mods/GSSiK_Addon_Tablet/42/",
}
local preproductionAddonRoots = {
	Rack = "addons/GSSiK_Addon_Rack/Contents/mods/GSSiK_Addon_Rack/42/",
}

local productSurfaceRoot = "GlobalStorageSiK/ui/surfaces/"
local generatedSurfaceRoot = "GlobalStorageSiK/ui/generated/tab-options/"

check("ModID dependency graph", function()
	exactDependencies(frameworkRoot .. "mod.info", {})
	exactDependencies(coreRoot .. "mod.info", { "SiKUIFramework" })
	for _, root in pairs(addonRoots) do
		exactDependencies(root .. "mod.info", { "GlobalStorageSiK", "SiKUIFramework" })
	end
end)

check("dependency parser rejects slash-normalized ModIDs", function()
	local backslashOk = pcall(parseDependencies,
		"require=\\GlobalStorageSiK", "backslash dependency fixture")
	assert(not backslashOk, "backslash dependency was silently normalized")
	local slashOk = pcall(parseDependencies,
		"require=/GlobalStorageSiK", "slash dependency fixture")
	assert(not slashOk, "slash dependency was silently normalized")
	local clean = parseDependencies(
		"require= SiKUIFramework, GlobalStorageSiK ", "clean dependency fixture")
	assert(#clean == 2 and clean[1] == "GlobalStorageSiK" and clean[2] == "SiKUIFramework",
		"valid dependency whitespace was not normalized safely")
end)

check("preproduction addons remain inventoried outside the active graph", function()
	assert(addonRoots.Rack == nil, "Rack entered the active dependency graph")
	local rackManifest = read(preproductionAddonRoots.Rack .. "mod.info")
	assert(rackManifest:find("id=GSSiK_Addon_Rack", 1, true),
		"Rack preproduction manifest identity is missing")
end)

check("Options surface has one canonical tab-options identity", function()
	local pipe = assert(io.popen('rg --files "' .. productSurfaceRoot .. '" -g "*.surface.json"', "r"),
		"cannot enumerate product surface specs")
	local ids, canonicalCount = {}, 0
	for path in pipe:lines() do
		local normalized = path:gsub("\\", "/")
		local source = read(normalized)
		local surfaceId = source:match('"surface"%s*:%s*{%s*"id"%s*:%s*"([^"]+)"')
		assert(surfaceId, "surface id not readable in " .. normalized)
		assert(not ids[surfaceId], "duplicate surface id " .. surfaceId)
		ids[surfaceId] = normalized
		if surfaceId == "tab-options" then canonicalCount = canonicalCount + 1 end
		for _, alias in ipairs({ "terminal-tabs", "options-tab" }) do
			assert(not source:find('"' .. alias .. '"', 1, true),
				normalized .. " contains forbidden options alias " .. alias)
		end
	end
	assert(pipe:close() ~= nil, "surface spec enumeration failed")
	assert(canonicalCount == 1, "tab-options spec count expected 1 got " .. canonicalCount)
	local catalogPipe = assert(io.popen('rg --files "GlobalStorageSiK/ui" -g "*.json"', "r"),
		"cannot enumerate product catalog JSON")
	for path in catalogPipe:lines() do
		local source = read(path:gsub("\\", "/"))
		for _, alias in ipairs({ "terminal-tabs", "options-tab" }) do
			assert(not source:find('"' .. alias .. '"', 1, true),
				path .. " contains forbidden catalog alias " .. alias)
		end
	end
	assert(catalogPipe:close() ~= nil, "product catalog enumeration failed")
	local provenance = read(generatedSurfaceRoot .. "tab-options.provenance.json")
	assert(provenance:find('"surfaceId": "tab-options"', 1, true),
		"generated options provenance lost canonical id")
	for _, alias in ipairs({ "terminal-tabs", "options-tab" }) do
		assert(not provenance:find('"' .. alias .. '"', 1, true),
			"generated options provenance contains alias " .. alias)
	end
end)

local coreClientFiles = luaFiles(coreRoot .. "media/lua/client")
local coreClient = combined(coreClientFiles)
local coreAll = combined(luaFiles(coreRoot .. "media/lua"))

check("Core has no private framework clone or alias", function()
	local cloned = {}
	for index = 1, #coreClientFiles do
		local name = coreClientFiles[index]:match("([^/]+)$")
		if name and name:match("^GS_SiK_UI") then cloned[#cloned + 1] = name end
	end
	assert(#cloned == 0, "private framework files remain: " .. table.concat(cloned, ", "))
	assert(not coreClient:find("GlobalStorageSiK.SiK_UI", 1, true),
		"Core still publishes the forbidden GlobalStorageSiK.SiK_UI alias")
end)

check("Core requires SiK.UI and fails explicitly when unavailable", function()
	local loader = codeOnly(read(coreRoot .. "media/lua/client/GS_UI_Framework.lua"))
	assert(requires(loader, "SiK_UI")
		or loader:match("pcall%s*%(%s*require,%s*[%\"']SiK_UI[%\"']%s*%)"),
		"strict binding never imports the external framework")
	assert(coreClient:find("SiK.UI", 1, true), "Core never consumes the public namespace")
	assert(loader:find("SiKUIFramework", 1, true),
		"missing-framework error does not identify the required ModID")
	assert(loader:find("error(", 1, true) or loader:find("assert(", 1, true),
		"missing framework has no explicit terminal failure")
	assert(not loader:find("package.preload", 1, true)
		and not loader:find("GlobalStorageSiK.SiK_UI", 1, true),
		"strict binding injects a private framework fallback")
	assert(not coreClient:find("package.preload", 1, true),
		"Core injects a private framework fallback")
end)

check("Core public product API is GSSiK.API only", function()
	assert(coreAll:find("GSSiK.API", 1, true), "GSSiK.API is not published")
	assert(not codeOnly(coreAll):find("GlobalStorageSiK.API", 1, true),
		"Core publishes the forbidden GlobalStorageSiK.API alias")
	assert(not coreClient:find("GlobalStorageSiK.SiK_UI", 1, true),
		"private UI namespace is exposed to consumers")
end)

for addonName, root in pairs(addonRoots) do
	check(addonName .. " consumes only public APIs", function()
		local source = codeOnly(combined(luaFiles(root .. "media/lua")))
		assert(source:find("GSSiK.API", 1, true), addonName .. " never consumes GSSiK.API")
		assert(not source:find("SandboxVars.GlobalStorageSiK", 1, true)
			and not source:match("SandboxVars%s*%[%s*[%\"']GlobalStorageSiK[%\"']%s*%]"),
			addonName .. " reads Core-owned GlobalStorageSiK sandbox state")
		assert(not source:find("GlobalStorageSiK", 1, true),
			addonName .. " creates or consumes the private GlobalStorageSiK namespace")
		assert(not source:match("require%s*[%\"']GS_[^%\"']+[%\"']"),
			addonName .. " imports a private Core module")
	end)
end

check("recipe-book resolver exposes typed override and abstention", function()
	local api = codeOnly(read(coreRoot .. "media/lua/shared/GSSiK_API.lua"))
	assert(api:find("function Addon.resolveRecipeBookRequirement", 1, true),
		"public recipe-book resolver is missing")
	assert(api:match("if%s+required%s*==%s*nil%s+then%s+return%s+true,%s*OK,%s*nil%s+end"),
		"nil abstention is not returned as a successful public result")
	assert(api:match("type%s*%(%s*required%s*%)%s*~=%s*[%\"']boolean[%\"']"),
		"non-boolean resolver results are not rejected")
	assert(api:match("if%s+not%s+called%s+then.-return%s+false,%s*ERR_INTERNAL,%s*nil"),
		"resolver exceptions do not produce ERR_INTERNAL")
	local tuning = codeOnly(read(coreRoot .. "media/lua/shared/GS_AddonRecipeTuning.lua"))
	assert(tuning:find("AddonAPI.resolveRecipeBookRequirement", 1, true),
		"Core recipe policy bypasses the public resolver")
	assert(tuning:find("GlobalStorageSiK.Sandbox.requireRecipeBooks()", 1, true),
		"Core no longer owns the configured recipe-book fallback")
end)

check("independent products declare framework only when consumed", function()
	local products = {
		{
			root = "../ManureManagerSiK-Repo/Contents/mods/ManureManagerSiK/42/",
			lua = "../ManureManagerSiK-Repo/Contents/mods/ManureManagerSiK/42/media/lua",
		},
		{
			root = "../SiKCorpseLootGuard-Repo/Contents/mods/SiKCorpseLootGuard/42/",
			lua = "../SiKCorpseLootGuard-Repo/Contents/mods/SiKCorpseLootGuard/42/media/lua",
		},
	}
	for index = 1, #products do
		local source = codeOnly(combined(luaFiles(products[index].lua)))
		local usesFramework = source:find("SiK.UI", 1, true) ~= nil
			or source:match("require%s*[%\"']SiK_UI[%\"']") ~= nil
			or source:match("require%s*%(%s*[%\"']SiK_UI[%\"']%s*%)") ~= nil
		local deps = dependencies(products[index].root .. "mod.info")
		local hasFramework = false
		for depIndex = 1, #deps do
			if deps[depIndex] == "SiKUIFramework" then hasFramework = true end
		end
		assert(usesFramework == hasFramework,
			products[index].root .. " code/dependency framework mismatch")
	end
end)

check("independent products publish exact public API namespaces", function()
	local manure = codeOnly(combined(luaFiles(
		"../ManureManagerSiK-Repo/Contents/mods/ManureManagerSiK/42/media/lua")))
	local corpse = codeOnly(combined(luaFiles(
		"../SiKCorpseLootGuard-Repo/Contents/mods/SiKCorpseLootGuard/42/media/lua")))
	assert(manure:find("MMSiK.API", 1, true), "MMSiK.API is not published")
	assert(not manure:find("MMSIK.API", 1, true), "legacy MMSIK.API casing is published")
	assert(corpse:find("SCLGSiK.API", 1, true), "SCLGSiK.API is not published")
	assert(not corpse:find("SCLG.API", 1, true), "legacy SCLG.API alias is published")
end)

check("framework source has one module owner and no product asset references", function()
	local frameworkFiles = luaFiles(frameworkRoot .. "media/lua/client")
	assert(#frameworkFiles > 10, "framework module tree is unexpectedly incomplete")
	for index = 1, #coreClientFiles do
		assert(not coreClientFiles[index]:find("/SiK/UI/", 1, true),
			"Core shadows framework module path " .. coreClientFiles[index])
	end
	local frameworkSource = combined(frameworkFiles)
	for _, token in ipairs({ "GlobalStorageSiK", "GSSiK", "MMSiK", "SCLGSiK", "IGUI_GS_" }) do
		assert(not frameworkSource:find(token, 1, true),
			"framework imports product namespace/asset token " .. token)
	end
end)

print(string.format("api_dependency_boundary_contract: pass=%d fail=%d", passed, #failures))
if #failures > 0 then error(table.concat(failures, "\n")) end

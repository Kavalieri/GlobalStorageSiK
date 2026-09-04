-- Final source boundary for retired UI/product internals. This intentionally
-- scans runtime product Lua only; tests, docs, generated catalogs and archives
-- cannot produce either a false PASS or a false failure.

local failures, scanned = {}, 0

local function read(path)
        local handle = assert(io.open(path, "rb"), "cannot read " .. path)
        local source = handle:read("*a")
        handle:close()
        return source
end

local function codeOnly(source)
        source = tostring(source or ""):gsub("%-%-%[%[.-%]%]", "")
        return source:gsub("%-%-[^\r\n]*", "")
end

local function runtimeFiles(root)
        local pipe = assert(io.popen('rg --files "' .. root .. '" -g "*.lua"', "r"),
                "cannot enumerate " .. root)
        local result = {}
        for path in pipe:lines() do
                path = path:gsub("\\", "/")
                if path:find("/42/media/lua/", 1, true) and not path:find("/tests/", 1, true) then
                        result[#result + 1] = path
                end
        end
        assert(pipe:close() ~= nil, "enumeration failed for " .. root)
        table.sort(result)
        return result
end

local roots = {
        "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua",
        "addons",
        "../ManureManagerSiK-Repo/Contents/mods/ManureManagerSiK/42/media/lua",
        "../SiKCorpseLootGuard-Repo/Contents/mods/SiKCorpseLootGuard/42/media/lua",
}

local forbiddenModules = {
        "GS_TerminalUI_Scroll", "GS_TerminalUI_Sections", "GS_TerminalUI_TabRail",
        "MM_UIChrome", "NeatUI", "GS_AddonApi",
}

local addonRegistryOwners = {
        ["GS_AddonRegistry.lua"] = true,
        ["GSSiK_API.lua"] = true,
}

local function add(path, reason)
        failures[#failures + 1] = path .. ": " .. reason
end

for rootIndex = 1, #roots do
        local files = runtimeFiles(roots[rootIndex])
        for fileIndex = 1, #files do
                local path = files[fileIndex]
                local base = path:match("([^/]+)$") or path
                local source = codeOnly(read(path))
                scanned = scanned + 1
                for tokenIndex = 1, #forbiddenModules do
                        local module = forbiddenModules[tokenIndex]
                        if base == module .. ".lua" then add(path, "retired module file remains") end
                        local escaped = module:gsub("([^%w])", "%%%1")
                        if source:match("require%s*[%\"']" .. escaped .. "[%\"']")
                                or source:match("require%s*%(%s*[%\"']" .. escaped .. "[%\"']%s*%)") then
                                add(path, "requires retired module " .. module)
                        end
                end
                if source:find("GlobalStorageSiK.AddonApi", 1, true) then
                        add(path, "publishes or consumes retired GlobalStorageSiK.AddonApi facade")
                end
                for _, token in ipairs({ "MM_UIChrome", "NeatUI" }) do
                        if source:find(token, 1, true) then
                                add(path, "references retired product UI token " .. token)
                        end
                end
                if not addonRegistryOwners[base] then
                        if source:match("require%s*[%\"']GS_AddonRegistry[%\"']")
                                or source:match("require%s*%(%s*[%\"']GS_AddonRegistry[%\"']%s*%)")
                                or source:find("GlobalStorageSiK.AddonRegistry", 1, true) then
                                add(path, "accesses GS_AddonRegistry outside its public API owner")
                        end
                end
        end
end

assert(scanned > 100, "runtime scan unexpectedly incomplete: " .. scanned)
table.sort(failures)
print(string.format("runtime_product_legacy_boundary_contract: scanned=%d fail=%d",
        scanned, #failures))
if #failures > 0 then error(table.concat(failures, "\n")) end

print("runtime_product_legacy_boundary_contract: OK")

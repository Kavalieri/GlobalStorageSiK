-- Dynamic contract test for the opt-in Global Storage diagnostics policy.
-- This is an isolated Lua harness: no PZ Events, files, or network are used.

local function loadFirst(paths)
    for i = 1, #paths do
        local chunk = loadfile(paths[i])
        if chunk then return chunk end
    end
    error("cannot load production module: " .. tostring(paths[1]))
end

local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
local fallback = shared

local console, relay, fileWrites = {}, {}, {}
local now = 0
local oldPrint = print
_G.print = function(line) console[#console + 1] = tostring(line) end
_G.debug = nil -- error() must remain visible without a second traceback line in this harness.
_G.getTimestampMs = function() return now end
_G.SandboxVars = { GlobalStorageSiK = {} }
_G.Events = { OnTick = { Add = function() error("diagnostic logging installed an OnTick hook") end } }
_G.getFileWriter = function(name)
    return {
        write = function(_, line) fileWrites[#fileWrites + 1] = { name = name, line = tostring(line) } end,
        close = function() end,
    }
end

_G.GlobalStorageSiK = {
    DebugRelay = {
        processTag = function() return "HARNESS" end,
        emit = function(line) relay[#relay + 1] = tostring(line) end,
    },
    DiagnosticsSession = nil,
}
package.preload["GS_Config"] = function() return {} end
package.preload["GS_DebugRelay"] = function() return true end
package.preload["GS_DiagnosticsSession"] = function() return true end
package.loaded["GS_Sandbox"] = nil
package.loaded["GS_Log"] = nil

loadFirst({ shared .. "GS_Sandbox.lua", fallback .. "GS_Sandbox.lua" })()
package.loaded["GS_Sandbox"] = GlobalStorageSiK.Sandbox
loadFirst({ shared .. "GS_Log.lua", fallback .. "GS_Log.lua" })()
local Sandbox = GlobalStorageSiK.Sandbox
local Log = GlobalStorageSiK.Log

local function clearOutput()
    console, relay, fileWrites = {}, {}, {}
end

local function hasLine(needle)
    for i = 1, #console do
        if string.find(console[i], needle, 1, true) then return true end
    end
    return false
end

local function countLines(needle)
    local count = 0
    for i = 1, #console do
        if not needle or string.find(console[i], needle, 1, true) then count = count + 1 end
    end
    return count
end

assert(Sandbox.debugMode() == false, "missing DebugMode must default OFF")
assert(Sandbox.debugCategoryEnabled("Unknown") == false, "unknown category must be OFF")
assert(Sandbox.debugDetailEnabled("Inventory") == false, "legacy detail getter must default OFF")
Log.debug("WithdrawClient", "hidden")
Log.info("NativeProduct", "hidden")
Log.debug("Unknown", "hidden")
Log.info("Unknown", "hidden")
assert(#console == 0 and #relay == 0 and #fileWrites == 0, "debug/info must be silent while disabled")

-- Legacy persisted DETAIL values are harmless and do not create output or hooks.
SandboxVars.GlobalStorageSiK.DebugDetailInventory = true
SandboxVars.GlobalStorageSiK.DebugDetailExactWithdraw = true
Log.detail("NativeProduct", "legacy detail")
assert(#console == 0 and #relay == 0, "persisted legacy detail keys must remain silent")

SandboxVars.GlobalStorageSiK.DebugMode = true
SandboxVars.GlobalStorageSiK.DebugCatExactWithdraw = true
SandboxVars.GlobalStorageSiK.DebugCatInventory = true
SandboxVars.GlobalStorageSiK.DebugCatSiKUI = true
assert(Sandbox.debugCategoryEnabled("ExactWithdraw") == true)
assert(Sandbox.debugCategoryEnabled("Inventory") == true)
assert(Sandbox.debugCategoryEnabled("SiKUI") == true)
assert(Sandbox.debugCategoryEnabled("Unknown") == false)
clearOutput()
Log.debug("WithdrawClient", "withdraw route")
Log.info("ZoneScanJob", "scan route")
Log.info("NativeProduct", "native route")
Log.debug("SiKUI", "ui route")
Log.debug("Unknown", "unknown route")
Log.info("Unknown", "unknown route")
assert(hasLine("DEBUG:WithdrawClient] withdraw route"), "WithdrawClient must map to ExactWithdraw")
assert(hasLine("INFO:ZoneScanJob] scan route"), "ZoneScanJob must map to Inventory")
assert(hasLine("INFO:NativeProduct] native route"), "NativeProduct must map to Inventory")
assert(hasLine("DEBUG:SiKUI] ui route"), "SiKUI must map to SiKUI")
assert(not hasLine("unknown route"), "unknown areas must not emit normal logs")

-- WARN/ERROR are safety-visible even when their category is disabled.
SandboxVars.GlobalStorageSiK.GlobalStorageSiK = nil
SandboxVars.GlobalStorageSiK.DebugMode = false
clearOutput()
Log.warn("Unknown", "visible warning")
Log.error("Unknown", "visible error")
assert(hasLine("WARN:Unknown] visible warning"), "WARN must not be silenced")
assert(hasLine("ERROR:Unknown] visible error"), "ERROR must not be silenced")

-- Twenty normal lines per category per one-second bucket; the 21st is skipped.
SandboxVars.GlobalStorageSiK.DebugMode = true
SandboxVars.GlobalStorageSiK.DebugCatExactWithdraw = true
clearOutput()
now = 1000
for i = 1, 21 do Log.debug("WithdrawClient", "budget-" .. tostring(i)) end
assert(countLines("DEBUG:WithdrawClient]") == 20, "normal line budget must be 20")
now = 2000
Log.debug("WithdrawClient", "after-window")
assert(hasLine("diagnostics throttled"), "next window must report skipped diagnostics")
assert(hasLine("after-window"), "next window must accept a new line")

-- Oversized messages are replaced by a bounded summary; source payload is absent.
clearOutput()
now = 3000
local oversized = string.rep("X", 1500)
Log.debug("WithdrawClient", oversized)
assert(hasLine("oversized diagnostic omitted bytes=1500"), "oversized line must be summarized")
assert(not hasLine(oversized), "oversized source payload must not be emitted")

-- Byte budget is independent per category and rejects the 9th 1000-byte line.
clearOutput()
now = 4000
for i = 1, 9 do Log.info("NativeProduct", string.rep("N", 1000)) end
assert(countLines("INFO:NativeProduct]") == 8, "normal byte budget must reject line nine")
now = 5000
Log.info("NativeProduct", "byte-window")
assert(hasLine("diagnostics throttled"), "byte skips must be summarized after one second")
assert(hasLine("byte-window"), "byte budget must reset after one second")

local function readSource(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end
local uidbg = readSource(fallback .. "../client/GS_UIDebug.lua")
local framework = readSource("../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/Diagnostics.lua")
assert(not string.find(uidbg, "registerSink", 1, true), "GS_UIDebug must not register a duplicate sink")
local _, sinkCount = string.gsub(framework, "Diagnostics%.registerSink%(%\"SiK%.UI%.Framework%\"", "")
assert(sinkCount == 1, "SiK.UI Diagnostics must retain exactly one framework sink")

oldPrint("debug_normal_policy_contract: PASS")

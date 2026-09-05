-- B42 getText receives inert markers; the public API restores %1 and formats it.
local shared = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"
GlobalStorageSiK = {}
package.preload["GS_CatalogManager"] = function() return {} end
getText = function(key, first) return "Terminal " .. tostring(first) end
dofile(shared .. "GS_I18n.lua")
local text = GlobalStorageSiK.I18n.text("IGUI_GS_TerminalDefaultNameFmt", 27)
assert(text == "Terminal 27", "formatted B42 template did not substitute its marker")
assert(not text:find("%%1", 1, true), "formatted I18n leaked %1")
print("PASS B42 formatted template contract")

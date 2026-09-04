-- Hard contract for the Addons generated surface. Release validation must fail
-- if the active adapter falls back to retired product layout code.

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local GENERATED = CLIENT .. "GlobalStorageSiK/UI/Generated/TabAddons.lua"

local function read(path)
	local handle = assert(io.open(path, "rb"), "cannot read " .. path)
	local text = handle:read("*a")
	handle:close()
	return text
end

local function contains(text, needle, label)
	assert(text:find(needle, 1, true), label or ("missing " .. needle))
end

local function excludes(text, needle, label)
	assert(not text:find(needle, 1, true), label or ("unexpected " .. needle))
end

local addons = read(CLIENT .. "GS_TerminalUI_Addons.lua")
local generated = read(GENERATED)

contains(addons, 'local Surface = require "GlobalStorageSiK/UI/Generated/TabAddons"')
contains(addons, "SiK.UI.SurfaceHost.mount")
contains(addons, "_gsSurfaceHost:reflow")
contains(addons, "_gsSurfaceHost:refresh")
contains(addons, "AddonAPI.list()")
excludes(addons, "UI.CardCollection.create")
excludes(addons, "UI.Scroll.childHost")
excludes(addons, "AddonBay")
excludes(addons, "addonSlot")
excludes(addons, "ISPanel:new")
excludes(addons, "math.floor((innerW")
excludes(addons, "scroll.scrollChildren")
excludes(addons, "TerminalScroll.")

contains(generated, '["type"] = "card-collection"')
contains(generated, '["runtimeFactory"] = "SiK.UI.CardCollection.create"')
contains(generated, '["name"] = "columns"')
contains(generated, '["name"] = "maxColumns"')
contains(generated, '["name"] = "exactColumns"')
contains(generated, '["value"] = 2')

local retired = io.open(CLIENT .. "GS_TerminalUI_AddonBay.lua", "rb")
assert(retired == nil, "retired product-specific AddonBay still exists")
if retired then retired:close() end

print("PASS | Addons uses only the generated SiK.UI surface and exact two-column collection")

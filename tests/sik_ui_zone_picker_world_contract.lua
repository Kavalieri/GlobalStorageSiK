-- Static product contract for the zone picker migration to public SiK.UI.
-- Runtime world conversion and highlights remain product callbacks; the
-- framework owns the visual overlay, viewport, focus and disposal lifecycle.

local sourcePath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_ZonePicker.lua"
local file = assert(io.open(sourcePath, "rb"))
local source = file:read("*a")
file:close()

local function contains(needle, message)
	assert(source:find(needle, 1, true), message or ("missing: " .. needle))
end

local function forbids(needle, message)
	assert(not source:find(needle, 1, true), message or ("forbidden: " .. needle))
end

contains('local UI = require "GS_UI_Framework"', "picker must use the public facade")
contains("UI.Viewport.resolve(playerNum)", "picker must resolve the owning player's viewport")
contains("UI.WorldPicker.create({", "picker must use the neutral world overlay")
contains("multiStep = true", "right-click and Escape must cancel between corner clicks")
contains("keepOpen = true", "two-click product selection must persist between clicks")
contains("onStep = function(context)", "world point selection must remain injected")
contains("onCancel = function()", "right-click/Escape cancellation must remain injected")
contains("onRender = function(context)", "visible picker lifecycle must drive hover feedback")
contains("current:dispose()", "picker removal must dispose framework focus and capture")
contains('sendCommand("createZoneSelection"', "authoritative request contract changed")
contains("finishSelection(corner1, sq)", "two-corner selection contract changed")
contains("highlightExistingNetworkNodes()", "existing-node feedback contract changed")
contains("count >= 400", "preview budget changed")

forbids('require "ISUI/ISPanel"', "product must not import the panel primitive")
forbids("ISPanel:new", "product must not construct its own overlay")
forbids("UI.FocusStack.install", "WorldPicker must remain the single focus owner")
forbids("Events.OnKeyPressed.Add", "Escape must be routed by WorldPicker/FocusStack")
forbids("Events.OnTick.Add", "hover refresh must be scoped to the visible picker")
forbids("GlobalStorageSiK.SiK_UI", "private UI namespace must not return")

print("sik_ui_zone_picker_world_contract: OK")

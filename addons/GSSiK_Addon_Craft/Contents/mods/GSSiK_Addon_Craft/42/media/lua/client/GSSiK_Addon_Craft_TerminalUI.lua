-- GSSiK Addon Craft - declarative terminal tab contract.

local API = require "GSSiK_API_Client"
require "SiK_UI"
local Surface = require "GSSiK_Addon_Craft/UI/Generated/TabCraft"
local Context = require "GSSiK_Addon_Craft/UI/TabCraftContext"

GSSiK_Addon_Craft = GSSiK_Addon_Craft or {}
GSSiK_Addon_Craft.TerminalUI = GSSiK_Addon_Craft.TerminalUI or {}
local TerminalModule = GSSiK_Addon_Craft.TerminalUI

TerminalModule.surfaceId = "tab-craft"
TerminalModule.surface = Surface
TerminalModule.builder = SiK.UI.SurfaceHost.mount

function TerminalModule.contextFactory(terminal)
	return Context.create(terminal)
end

-- Existing domain callbacks call refresh after opening or changing a work
-- session. Keep that public seam while delegating UI ownership to SurfaceHost.
function TerminalModule.refresh(_, terminal)
	if not terminal then return false end
	return API.Terminal.refresh(terminal, "craft")
end

return TerminalModule

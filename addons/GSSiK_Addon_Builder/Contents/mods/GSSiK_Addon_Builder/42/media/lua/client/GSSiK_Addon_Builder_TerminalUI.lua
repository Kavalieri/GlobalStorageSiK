-- GSSiK Addon Builder - declarative terminal tab contract.

local API = require "GSSiK_API_Client"
require "SiK_UI"
local Surface = require "GSSiK_Addon_Builder/UI/Generated/TabBuilder"
local Context = require "GSSiK_Addon_Builder/UI/TabBuilderContext"

GSSiK_Addon_Builder = GSSiK_Addon_Builder or {}
GSSiK_Addon_Builder.TerminalUI = GSSiK_Addon_Builder.TerminalUI or {}
local TerminalModule = GSSiK_Addon_Builder.TerminalUI

TerminalModule.surfaceId = "tab-builder"
TerminalModule.surface = Surface
TerminalModule.builder = SiK.UI.SurfaceHost.mount

function TerminalModule.contextFactory(terminal)
	return Context.create(terminal)
end

function TerminalModule.refresh(_, terminal)
	if not terminal then return false end
	return API.Terminal.refresh(terminal, "build")
end

return TerminalModule

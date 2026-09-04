-- Global Storage SiK - Options surface adapter.
--
-- The validated tab-options artifact owns every visible widget and every
-- layout decision. Product code supplies plain state, conditions and actions.

require "GS_Log"

require "GS_UI_Framework"
local TabOptionsSpec = require "GlobalStorageSiK/UI/Generated/TabOptions"
local TabOptionsContext = require "GlobalStorageSiK/UI/TabOptionsContext"

GlobalStorageSiK.TerminalOptions = GlobalStorageSiK.TerminalOptions or {}

local Options = GlobalStorageSiK.TerminalOptions
local SURFACE_ID = "tab-options"
Options.surfaceId = SURFACE_ID

local function panelBounds(panel)
	local width = panel and panel.getWidth and panel:getWidth() or panel and panel.width or 1
	local height = panel and panel.getHeight and panel:getHeight() or panel and panel.height or 1
	return { x = 0, y = 0, w = math.max(1, tonumber(width) or 1), h = math.max(1, tonumber(height) or 1) }
end

local function release(panel)
	if not panel then return false end
	local released = false
	if panel._sikOptionsSurface then
		panel._sikOptionsSurface:dispose()
		panel._sikOptionsSurface = nil
		released = true
	end
	if panel._sikOptionsContext then
		panel._sikOptionsContext:dispose()
		panel._sikOptionsContext = nil
		released = true
	end
	panel.optBuilt = false
	return released
end

local function snapshotFor(terminal, panel, state)
	local adapter = panel and panel._sikOptionsContext
	if not adapter then return nil, "context_unavailable" end
	local snapshot, reason = adapter:snapshot(state)
	if not snapshot then return nil, reason end
	snapshot.viewport = panelBounds(panel)
	return snapshot
end

function Options.buildSection(terminal, optionsPanel)
	if not terminal or not optionsPanel then return nil, "invalid_options_parent" end
	release(optionsPanel)
	local adapter, adapterReason = TabOptionsContext.create(terminal)
	if not adapter then return nil, adapterReason end
	optionsPanel._sikOptionsContext = adapter
	local snapshot, snapshotReason = snapshotFor(terminal, optionsPanel, terminal.terminalState)
	if not snapshot then
		adapter:dispose()
		optionsPanel._sikOptionsContext = nil
		return nil, snapshotReason
	end
	local surface, surfaceReason = SiK.UI.SurfaceHost.mount(optionsPanel, TabOptionsSpec, {
		context = snapshot,
		bounds = snapshot.viewport,
		followParent = true,
	})
	if not surface then
		adapter:dispose()
		optionsPanel._sikOptionsContext = nil
		return nil, surfaceReason
	end
	optionsPanel._sikOptionsSurface = surface
	optionsPanel.optBuilt = true
	return surface
end

function Options.activateSubTab(terminal, key)
	local panel = terminal and terminal.configPanel
	local surface = panel and panel._sikOptionsSurface
	local tree = surface and surface.getTree and surface:getTree() or surface
	local tabs = tree and tree.nodes and tree.nodes["options-tabs"]
	if not tabs or type(tabs.setActive) ~= "function" then return false, "options_tabs_unavailable" end
	local normalized = key == "admin" and "admin" or "estado"
	return tabs:setActive(normalized, true)
end

function Options.refreshActiveTab(terminal, state)
	return Options.refreshScroll(terminal, state)
end

function Options.refreshScroll(terminal, state)
	local panel = terminal and terminal.configPanel
	if not panel then return nil, "options_panel_unavailable" end
	local surface = panel._sikOptionsSurface
	if not surface then
		return Options.buildSection(terminal, panel)
	end
	local snapshot, reason = snapshotFor(terminal, panel, state)
	if not snapshot then return nil, reason end
	return surface:refresh(snapshot)
end

function Options.layoutUi(_, ui)
	return ui
end

function Options.syncScrollLayout(terminal)
	local panel = terminal and terminal.configPanel
	local surface = panel and panel._sikOptionsSurface
	if not surface then return false end
	return surface:reflow(panelBounds(panel))
end

function Options.layout(terminal, innerW, innerH)
	local panel = terminal and terminal.configPanel
	local surface = panel and panel._sikOptionsSurface
	if not surface then return false end
	return surface:reflow({ x = 0, y = 0, w = math.max(1, tonumber(innerW) or 1),
		h = math.max(1, tonumber(innerH) or 1) })
end

function Options.ensureUi(terminal)
	local panel = terminal and terminal.configPanel
	if not panel then return nil, "options_panel_unavailable" end
	return panel._sikOptionsSurface or Options.buildSection(terminal, panel)
end

-- The framework owns both scroll nodes and their overflow geometry. Returning
-- no legacy scrolls prevents the retired TerminalScroll engine from adjusting
-- a second set of offsets or bars over this surface.
function Options.getAllTabScrolls()
	return {}
end

function Options.dispose(terminal)
	return release(terminal and terminal.configPanel)
end

return Options

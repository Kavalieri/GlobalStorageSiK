-- Global Storage SiK - declarative Red tab surface adapter.
-- The validated tab-red surface owns visible widgets and geometry.

require "GS_Log"
require "GS_UI_Framework"

local TabNetworkSpec = require "GlobalStorageSiK/UI/Generated/TabNetwork"
local TabNetworkContext = require "GlobalStorageSiK/UI/TabNetworkContext"

GlobalStorageSiK.TerminalNetwork = GlobalStorageSiK.TerminalNetwork or {}

local Network = GlobalStorageSiK.TerminalNetwork
local SURFACE_ID = "tab-red"
Network.surfaceId = SURFACE_ID

local function panelBounds(panel)
	local width = panel and panel.getWidth and panel:getWidth() or panel and panel.width or 1
	local height = panel and panel.getHeight and panel:getHeight() or panel and panel.height or 1
	return { x = 0, y = 0, w = math.max(1, tonumber(width) or 1),
		h = math.max(1, tonumber(height) or 1) }
end

local function release(panel)
	if not panel then return false end
	local released = false
	if panel._sikNetworkSurface then
		panel._sikNetworkSurface:dispose()
		panel._sikNetworkSurface = nil
		released = true
	end
	if panel._sikNetworkContext then
		panel._sikNetworkContext:dispose()
		panel._sikNetworkContext = nil
		released = true
	end
	panel.netZonesBuilt = false
	return released
end

local function snapshotFor(terminal, panel, state)
	local adapter = panel and panel._sikNetworkContext
	if not adapter then return nil, "context_unavailable" end
	local snapshot, reason = adapter:snapshot(state)
	if not snapshot then return nil, reason end
	snapshot.viewport = panelBounds(panel)
	return snapshot
end

function Network.buildZonesSection(terminal, networkPanel)
	if not terminal or not networkPanel then return nil, "invalid_network_parent" end
	release(networkPanel)
	local adapter, adapterReason = TabNetworkContext.create(terminal)
	if not adapter then return nil, adapterReason end
	networkPanel._sikNetworkContext = adapter
	local snapshot, snapshotReason = snapshotFor(terminal, networkPanel, terminal.terminalState)
	if not snapshot then
		adapter:dispose()
		networkPanel._sikNetworkContext = nil
		return nil, snapshotReason
	end
	local surface, surfaceReason = SiK.UI.SurfaceHost.mount(networkPanel, TabNetworkSpec, {
		context = snapshot,
		bounds = snapshot.viewport,
		followParent = true,
	})
	if not surface then
		adapter:dispose()
		networkPanel._sikNetworkContext = nil
		if GlobalStorageSiK.Log then
			GlobalStorageSiK.Log.error("TerminalUI", "tab-red build failed", tostring(surfaceReason))
		end
		return nil, surfaceReason
	end
	networkPanel._sikNetworkSurface = surface
	networkPanel.netZonesBuilt = true
	return surface
end

function Network.refreshActiveTab(terminal, state)
	return Network.refreshScroll(terminal, state)
end

function Network.refreshScroll(terminal, state)
	local panel = terminal and terminal.networkPanel
	if not panel then return nil, "network_panel_unavailable" end
	local surface = panel._sikNetworkSurface
	if not surface then return Network.buildZonesSection(terminal, panel) end
	local snapshot, reason = snapshotFor(terminal, panel, state)
	if not snapshot then return nil, reason end
	return surface:refresh(snapshot)
end

function Network.layoutUi(_, ui)
	return ui
end

function Network.syncScrollLayout(terminal)
	local panel = terminal and terminal.networkPanel
	local surface = panel and panel._sikNetworkSurface
	if not surface then return false end
	return surface:reflow(panelBounds(panel))
end

function Network.layout(terminal, innerW, innerH)
	local panel = terminal and terminal.networkPanel
	local surface = panel and panel._sikNetworkSurface
	if not surface then return false end
	return surface:reflow({ x = 0, y = 0,
		w = math.max(1, tonumber(innerW) or 1), h = math.max(1, tonumber(innerH) or 1) })
end

function Network.ensureUi(terminal)
	local panel = terminal and terminal.networkPanel
	if not panel then return nil, "network_panel_unavailable" end
	return panel._sikNetworkSurface or Network.buildZonesSection(terminal, panel)
end

-- SiK.UI Block/Table own the only scroll/gutter on this surface.
function Network.getAllTabScrolls()
	return {}
end

function Network.dispose(terminal)
	return release(terminal and terminal.networkPanel)
end

return Network

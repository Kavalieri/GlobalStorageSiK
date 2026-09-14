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

function Network.hideTooltips(terminal)
	local panel=terminal and terminal.networkPanel
	local surface=panel and panel._sikNetworkSurface
	local tree=surface and surface:getTree()
	GlobalStorageSiK.TerminalNodes.hideTooltips(tree and tree.nodes and tree.nodes["network-table"])
end

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
	Network.hideTooltips(terminal)
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

local function sameMetadata(a,b,depth)
	if a==b then return true end
	if type(a)~="table" or type(b)~="table" or depth>16 then return false end
	for key,value in pairs(a) do if not sameMetadata(value,b[key],depth+1) then return false end end
	for key in pairs(b) do if a[key]==nil then return false end end
	return true
end

-- Metadata can converge before inventory blocks. Patch only changed roots;
-- neither the mounted surface nor the last confirmed inventory is rebuilt.
function Network.refreshTopologyRows(terminal,previous,state)
	local panel=terminal and terminal.networkPanel
	local surface=panel and panel._sikNetworkSurface
	local tree=surface and surface:getTree()
	local tableUI=tree and tree.nodes and tree.nodes["network-table"]
	local adapter=panel and panel._sikNetworkContext
	if not tableUI or not adapter then return true end
	local oldZones,newZones,oldNodes,newNodes,changed={},{},{},{},{}
	for _,zone in ipairs(previous.zones or {}) do oldZones[zone.id]=zone end
	for _,zone in ipairs(state.zones or {}) do
		newZones[zone.id]=zone
		if not sameMetadata(zone,oldZones[zone.id],0) then changed[zone.id]=true end
	end
	for _,node in ipairs(previous.nodes or {}) do oldNodes[node.id]=node end
	for _,node in ipairs(state.nodes or {}) do
		newNodes[node.id]=node
		local old=oldNodes[node.id]
		if not sameMetadata(node,old,0) then
			changed[node.zoneId]=true
			if old then changed[old.zoneId]=true end
		end
	end
	for id,node in pairs(oldNodes) do if not newNodes[id] then changed[node.zoneId]=true end end
	local zones,nodes,removeKeys={},{},{}
	for _,zone in ipairs(state.zones or {}) do if changed[zone.id] then zones[#zones+1]=zone end end
	for _,node in ipairs(state.nodes or {}) do if changed[node.zoneId] then nodes[#nodes+1]=node end end
	for id in pairs(oldZones) do if not newZones[id] then removeKeys[#removeKeys+1]="zone:"..tostring(id) end end
	local model=GlobalStorageSiK.TerminalNodes.presentationModel(nodes,zones,adapter.sortColumn,adapter.sortDirection)
	local previousMap,previousNodes,previousZones=adapter.rowsByKey,adapter.nodes,adapter.zones
	local undo,isCurrent
	if #model.rows>0 or #removeKeys>0 then
		GlobalStorageSiK.TerminalNodes.hideTooltips(tableUI)
		local accepted,reason,restore,guard=tableUI:patchRows({upserts=model.rows,removeKeys=removeKeys})
		if not accepted then return false,reason end
		undo,isCurrent=restore,guard
	end
	local nextMap={}
	for key,row in pairs(previousMap) do nextMap[key]=row end
	for id in pairs(oldZones) do if not newZones[id] then nextMap["zone:"..tostring(id)]=nil end end
	for id,node in pairs(oldNodes) do
		if changed[node.zoneId] or not newNodes[id] then nextMap["node:"..tostring(id)]=nil end
	end
	for _,row in ipairs(model.rows) do
		nextMap[row.id]=row
		for _,child in ipairs(row.children or {}) do nextMap[child.id]=child end
	end
	adapter.rowsByKey,adapter.nodes,adapter.zones=nextMap,state.nodes,state.zones
	local function current() return adapter.rowsByKey==nextMap and (not isCurrent or isCurrent()) end
	return true,nil,function()
		if not current() then return false,"image_superseded" end
		if undo and undo()==false then return false,"image_superseded" end
		adapter.rowsByKey,adapter.nodes,adapter.zones=previousMap,previousNodes,previousZones
		return true
	end,current
end

-- Rule ACKs patch the affected zone root (and its inherited child labels).
-- The mounted table retains unrelated roots, selection, expansion and scroll.
function Network.refreshRuleRows(terminal, zoneId, nodeId, rules)
	local state=terminal and terminal.terminalState
	if not state then return false end
	local zone, nodes=nil,{}
	for _,candidate in ipairs(state.zones or {}) do
		if candidate.id==zoneId then zone=candidate;break end
	end
	if not zone then return false end
	if not nodeId then zone.rules=rules end
	for _,node in ipairs(state.nodes or {}) do
		if node.zoneId==zoneId then
			if node.id==nodeId then node.rules=rules end
			nodes[#nodes+1]=node
		end
	end
	local panel=terminal.networkPanel
	local surface=panel and panel._sikNetworkSurface
	local tree=surface and surface:getTree()
	local tableUI=tree and tree.nodes and tree.nodes["network-table"]
	local adapter=panel and panel._sikNetworkContext
	if tableUI and adapter and terminal.activeTabKey=="network" then
		local model=GlobalStorageSiK.TerminalNodes.presentationModel(nodes,{zone},adapter.sortColumn,adapter.sortDirection)
		local row=model.rows[1]
		if row then
			-- A node ACK changes one child; inherited zone changes affect all.
			for i,child in ipairs(row.children or {}) do
				if nodeId and child.id~="node:"..tostring(nodeId) then
					row.children[i]=adapter.rowsByKey[child.id] or child
				end
			end
			GlobalStorageSiK.TerminalNodes.hideTooltips(tableUI)
			local accepted,reason=tableUI:patchRows({upserts={row}})
			if not accepted then return false,reason end
			adapter.rowsByKey[row.id]=row
			for _,child in ipairs(row.children or {}) do adapter.rowsByKey[child.id]=child end
		end
	end
	local editor=GlobalStorageSiK.TerminalZoneEditor and GlobalStorageSiK.TerminalZoneEditor.instance
	if editor and editor.terminal==terminal and editor.zone and editor.zone.id==zoneId and editor.zoneNodesTable then
		if not nodeId then editor.zone.rules=rules end
		local changed={}
		for _,row in ipairs(GlobalStorageSiK.TerminalNodes.zoneRows(nodes,zone)) do
			if not nodeId or row.sourceNode.id==nodeId then changed[#changed+1]=row end
		end
		local accepted,reason=editor.zoneNodesTable:patchRows({upserts=changed})
		if not accepted then return false,reason end
	end
	return true
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

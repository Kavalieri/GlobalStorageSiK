-- Presentation readiness belongs to the window, independently of access ACKs.
-- No cache, permission or inventory is written by this module.
local Loading = {}
GlobalStorageSiK.TerminalLoading = Loading
local keys = {
	checking="IGUI_GS_CheckingAccess", loading="IGUI_GS_LoadingInventory",
	validating="IGUI_GS_ValidatingInventory", updating="IGUI_GS_UpdatingInventory",
}
local function now() return getTimestampMs and getTimestampMs() or 0 end
function Loading.busy(playerNum)
	local api = GlobalStorageSiK.TerminalUI
	local ui = api and api.getInstanceForPlayer and api.getInstanceForPlayer(playerNum)
	return ui and ui._gsCatalogLoad ~= nil or false
end
local function lockWidget(ui, widget)
	if not widget then return end
	local locks = ui._gsCatalogWidgetLocks
	local first = not locks[widget]
	if first then
		local enabled = widget.enable ~= false and widget.enabled ~= false
		if widget.isEnabled then enabled = enabled and widget:isEnabled() ~= false end
		locks[widget] = {enabled=enabled}
	end
	-- Snapshot descendants before a composite setEnabled cascades into them.
	for _, child in pairs(widget.children or {}) do lockWidget(ui, child) end
	if first then
		-- Native enabled also blocks input to lists/panels, not just buttons.
		if widget.setEnabled then widget:setEnabled(false) end
		if ISUIElement and ISUIElement.setEnabled then ISUIElement.setEnabled(widget, false) end
		if widget.unfocus then widget:unfocus() end
	end
end
function Loading.lock(ui)
	if not ui or not ui._gsCatalogLoad then return end
	ui._gsCatalogWidgetLocks = ui._gsCatalogWidgetLocks or {}
	-- Chrome/Close/Escape remain usable. Only the navigation and its body lock.
	local host = ui.navigationContainer
	if host then lockWidget(ui, host.panel or host) end
end
local function unlockWidget(widget, locks)
	if not widget then return end
	local state = locks[widget]
	if state then
		if widget.setEnabled then widget:setEnabled(state.enabled) end
		if ISUIElement and ISUIElement.setEnabled then ISUIElement.setEnabled(widget, state.enabled) end
	end
	-- Restore child-specific availability after composite parent setters.
	for _, child in pairs(widget.children or {}) do unlockWidget(child, locks) end
end
function Loading.unlock(ui)
	local locks = ui and ui._gsCatalogWidgetLocks or {}
	local host = ui and ui.navigationContainer
	if host then unlockWidget(host.panel or host, locks) end
	if ui then ui._gsCatalogWidgetLocks = nil end
end
function Loading.set(ui, phase, sequence, done, total)
	if not ui then return end
	local previous = ui._gsCatalogLoad
	ui._gsCatalogLoad = {phase=phase, sequence=sequence, done=done, total=total,
		started=previous and previous.sequence == sequence and previous.started or now()}
	-- Only an opening without a confirmed catalog blocks interaction. Background
	-- reconciliation keeps the last authoritative image usable while the header
	-- reports progress; it must never disable or repaint the terminal body.
	if phase == "checking" or phase == "loading" or phase == "validating" then
		Loading.lock(ui)
	else
		Loading.unlock(ui)
	end
	if ui.syncHeaderChrome then ui:syncHeaderChrome() end
end
function Loading.header(load)
	if not load then return end
	if load.phase == "failed" then
		return {text=GlobalStorageSiK.I18n.text(load.failureKey or "IGUI_GS_InventoryIncomplete"), tone="danger"}, false
	end
	local label = GlobalStorageSiK.I18n.text(keys[load.phase] or keys.loading)
	local total, done = tonumber(load.total) or 0, tonumber(load.done) or 0
	local value = total > 0 and math.min(1, math.max(0, done / total)) or nil
	return {text=label, tone="warning"}, {label=value and (tostring(math.floor(value*100)) .. "%") or "",
		value=value, mode=value and "determinate" or "indeterminate",
		showProgress=true, status="warning", tone="warning"}
end
function Loading.finish(ui, expected)
	if not ui or ui._gsCatalogLoad ~= expected then return end
	Loading.unlock(ui)
	ui._gsCatalogLoad = nil
	if ui.syncHeaderChrome then ui:syncHeaderChrome() end
	if expected and GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.debug("CatalogTransport", "ui_ready", "player=" .. tostring(ui.playerNum)
			.. " openSeq=" .. tostring(expected.sequence) .. " waitMs=" .. tostring(now()-expected.started))
	end
end
return Loading

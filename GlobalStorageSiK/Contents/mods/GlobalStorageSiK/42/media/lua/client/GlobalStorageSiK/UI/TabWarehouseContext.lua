-- Global Storage SiK - datos y acciones de producto para tab-warehouse.
-- La superficie declarativa/SiK.UI posee widgets y geometria; este adaptador
-- solo entrega estado localizado y los puentes de comportamiento del producto.

require "GS_I18n"
local UI = require "GS_UI_Framework"
local CapacityPresentation = require "GlobalStorageSiK/UI/CapacityPresentation"

GlobalStorageSiK = GlobalStorageSiK or {}
GlobalStorageSiK.UI = GlobalStorageSiK.UI or {}

local TabWarehouseContext = {}
GlobalStorageSiK.UI.TabWarehouseContext = TabWarehouseContext

-- One validated definition is shared by every Warehouse surface. Mutable
-- phase, counts and observers live in the isolated instance created below.
local WarehouseResourceDefinition = assert(UI.StateMachine.asyncResource())

local function text(key, ...)
	local i18n = GlobalStorageSiK.I18n
	if i18n and type(i18n.text) == "function" then return i18n.text(key, ...) end
	return tostring(key or "")
end

local function semantic(envelope)
	-- SiK.UI exposes one stable public envelope and keeps the normalized event
	-- value inside its semantic payload. Consumers never decode vanilla events.
	return type(envelope) == "table" and type(envelope.payload) == "table"
		and envelope.payload or {}
end

local function filterItems(allLabel, filters)
	local result = { { id = "all", value = "", text = allLabel } }
	for index = 1, #(filters or {}) do
		local entry = filters[index]
		result[#result + 1] = { id = entry.key, value = entry.key, text = entry.label }
	end
	return result
end

local function runtimeI18n()
	local allCategories = text("IGUI_GS_FilterCategoryAll")
	local allSubcategories = text("IGUI_GS_FilterSubCategoryAll")
	return {
		["warehouse.title"] = text("IGUI_GS_SectionItems"),
		["warehouse.help"] = text("IGUI_GS_DropHint"),
		["warehouse.search.label"] = text("IGUI_GS_SearchPlaceholder"),
		["warehouse.search.action"] = text("IGUI_GS_Search"),
		["warehouse.filter.family"] = allCategories,
		["warehouse.filter.group"] = allSubcategories,
		["warehouse.filter.detail"] = allSubcategories,
		["warehouse.option.family.all"] = allCategories,
		["warehouse.option.group.all"] = allSubcategories,
		["warehouse.option.detail.all"] = allSubcategories,
		["warehouse.column.name"] = text("IGUI_GS_ColName"),
		["warehouse.column.category"] = text("IGUI_GS_ColCategory"),
		["warehouse.column.zone"] = text("IGUI_GS_ColZone"),
		["warehouse.column.count"] = text("IGUI_GS_ColCount"),
	}
end

local function redistributeState(terminal)
	local running = terminal._autoSortRunning == true
		or (terminal.terminalState and terminal.terminalState.redistributeActive == true)
	local allowed = type(terminal.canUseAutoSort) == "function" and terminal:canUseAutoSort() or false
	local tone = terminal._autoSortStatus or (running and "warning" or "textMuted")
	if tone == "warn" then tone = "warning"
	elseif tone == "muted" then tone = "textMuted"
	elseif tone == "ok" then tone = "success" end
	return {
		action = {
			id = "auto-sort",
			text = text("IGUI_GS_Redistribute"),
			tooltip = allowed and text("IGUI_GS_RedistributeHint") or text("IGUI_GS_RedistributeAdminOnly"),
			enabled = allowed and not running,
			locked = not allowed,
		},
		status = {
			text = terminal._autoSortMessage
				or (running and text("IGUI_GS_RedistributingNetwork") or text("IGUI_GS_RedistributeIdle")),
			tone = tone,
		},
	}
end

function TabWarehouseContext.create(terminal, panel)
	if type(terminal) ~= "table" or type(panel) ~= "table" then
		return nil, "invalid_warehouse_context"
	end
	local resource = assert(WarehouseResourceDefinition:create())
	local context = {
		terminal = terminal, panel = panel, disposed = false,
		resource = resource, resourceFingerprint = nil,
	}
	local searchDueMs = nil
	local SEARCH_DEBOUNCE_MS = 180
	local function nowMs()
		if type(getTimestampMs) == "function" then return getTimestampMs() end
		if type(getTimestamp) == "function" then return getTimestamp() * 1000 end
		return nil
	end
	local function removeSearchTick()
		if context.searchTickInstalled and Events and Events.OnTick then
			Events.OnTick.Remove(context.searchTick)
		end
		context.searchTickInstalled = nil
		searchDueMs = nil
	end
	local function captureLiveSearchText(fallback)
		local field = terminal.searchEntry or terminal.searchBox
		if field and type(field.getText) == "function" then
			local ok, value = pcall(field.getText, field)
			if ok and value ~= nil then
				terminal._warehouseQuery = tostring(value)
				return terminal._warehouseQuery
			end
		end
		if fallback ~= nil then terminal._warehouseQuery = tostring(fallback) end
		return terminal._warehouseQuery or ""
	end
	context.searchTick = function()
		if context.disposed then removeSearchTick(); return end
		local now = nowMs()
		if searchDueMs and (not now or now >= searchDueMs) then
			removeSearchTick()
			captureLiveSearchText()
			if type(terminal.onSearch) == "function" then terminal:onSearch(false) end
		end
	end
	local function scheduleSearch()
		local now = nowMs()
		searchDueMs = now and now + SEARCH_DEBOUNCE_MS or 0
		if not context.searchTickInstalled and Events and Events.OnTick then
			context.searchTickInstalled = true
			Events.OnTick.Add(context.searchTick)
		end
		-- Local harnesses do not expose OnTick; keep their action deterministic.
		if not Events or not Events.OnTick then
			searchDueMs = nil
			captureLiveSearchText()
			if type(terminal.onSearch) == "function" then return terminal:onSearch(false) end
		end
		return true
	end
	context.actions = {
		["warehouse.auto-sort"] = function()
			if type(terminal.onRedistributeNetwork) ~= "function" then
				return false, "auto_sort_unavailable"
			end
			return terminal:onRedistributeNetwork()
		end,
		["warehouse.search-change"] = function(envelope)
			terminal._warehouseQuery = tostring(semantic(envelope).value or "")
			if type(terminal.onSearch) ~= "function" then return false, "search_unavailable" end
			return scheduleSearch()
		end,
		["warehouse.search"] = function(envelope)
			local value = semantic(envelope).value
			captureLiveSearchText(value)
			removeSearchTick()
			if type(terminal.onSearch) == "function" then return terminal:onSearch(true) end
			return false, "search_unavailable"
		end,
		["warehouse.filter-family"] = function(envelope)
			local selected = semantic(envelope).value
			terminal._mainCategoryFilterKey = tostring(type(selected) == "table"
				and (selected.value or selected.id or selected.key) or selected or "")
			terminal._subCategoryFilterKey, terminal._leafCategoryFilterKey = "", ""
			if type(terminal.refreshItemsTab) == "function" then terminal:refreshItemsTab() end
			return true
		end,
		["warehouse.filter-group"] = function(envelope)
			local selected = semantic(envelope).value
			terminal._subCategoryFilterKey = tostring(type(selected) == "table"
				and (selected.value or selected.id or selected.key) or selected or "")
			terminal._leafCategoryFilterKey = ""
			if type(terminal.refreshItemsTab) == "function" then terminal:refreshItemsTab() end
			return true
		end,
		["warehouse.filter-detail"] = function(envelope)
			local selected = semantic(envelope).value
			terminal._leafCategoryFilterKey = tostring(type(selected) == "table"
				and (selected.value or selected.id or selected.key) or selected or "")
			if type(terminal.refreshItemsTab) == "function" then terminal:refreshItemsTab() end
			return true
		end,
		["warehouse.row-activate"] = function() return true end,
	}

	function context:snapshot(items)
		if self.disposed then return nil, "disposed" end
		items = items or (terminal.terminalState and terminal.terminalState.items) or {}
		local catalogItems = (terminal.terminalState and terminal.terminalState.items) or items
		local api = GlobalStorageSiK.TerminalItems or {}
		local mainKey = terminal._mainCategoryFilterKey or ""
		local subKey = terminal._subCategoryFilterKey or ""
		local leafKey = terminal._leafCategoryFilterKey or ""
		local main = type(api.collectMainCategoryFilters) == "function"
			and api.collectMainCategoryFilters(catalogItems) or {}
		local sub = type(api.collectSubCategoryFilters) == "function"
			and api.collectSubCategoryFilters(catalogItems, mainKey) or {}
		local leaf = type(api.collectLeafCategoryFilters) == "function"
			and api.collectLeafCategoryFilters(catalogItems, mainKey, subKey) or {}
		local redistribution = redistributeState(terminal)
		local tableModel = type(api.presentationModel) == "function"
			and api.presentationModel(panel, terminal, items) or { rows = {} }
		local state = terminal.terminalState
		local hasSnapshot = type(state) == "table" and type(state.items) == "table"
		-- A running recapture never hides the last received inventory. Exact
		-- transfers separately require a certified revision, not visual rows.
		local availableCount = #catalogItems
		local visibleCount = #(tableModel.rows or {})
		local fingerprint = tostring(hasSnapshot) .. ":" .. tostring(availableCount)
			.. ":" .. tostring(visibleCount)
		if self.resourceFingerprint ~= fingerprint then
			if self.resource:getState() ~= "loading" then self.resource:send("begin") end
			if hasSnapshot then
				self.resource:send("resolve", { counts = {
					total = visibleCount, available = availableCount,
				} })
			end
			self.resourceFingerprint = fingerprint
		end
		local availability = self.resource:snapshot()
		local itemCount = 0
		for i = 1, #catalogItems do itemCount = itemCount + (tonumber(catalogItems[i].count) or 0) end
		if availability.state == "empty" then
			availability.reason = availableCount > 0 and "no-match" or "no-data"
		end
		return {
			data = { warehouse = {
				headerActions = { redistribution.action },
				capacity = CapacityPresentation.fromState(
					terminal.terminalState and terminal.terminalState.capacity, {
						count = itemCount,
						typeCount = terminal.terminalState and terminal.terminalState.itemTypeCount,
					}),
				search = { query = terminal._warehouseQuery or "" },
				filters = {
					family = { items = filterItems(text("IGUI_GS_FilterCategoryAll"), main), selected = mainKey },
					group = { items = filterItems(text("IGUI_GS_FilterSubCategoryAll"), sub), selected = subKey },
					detail = { items = filterItems(text("IGUI_GS_FilterSubCategoryAll"), leaf), selected = leafKey },
				},
				rows = tableModel,
				availability = availability,
			} },
			state = { warehouse = {
				search = { query = terminal._warehouseQuery or "" },
				filters = { family = mainKey, group = subKey, detail = leafKey },
			} },
			conditions = {}, actions = self.actions,
			tableOptions = { ["warehouse-table"] = api.tableOptions(panel, terminal) },
			i18n = runtimeI18n(), playerNum = terminal.playerNum or 0,
		}
	end

	function context:dispose()
		if self.disposed then return false end
		self.disposed = true
		removeSearchTick()
		if self.resource then self.resource:dispose("warehouse_context_disposed") end
		self.actions, self.terminal, self.panel = nil, nil, nil
		self.resource, self.resourceFingerprint, self.searchTick = nil, nil, nil
		return true
	end
	return context
end

return TabWarehouseContext

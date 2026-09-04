-- Authorial regression for the generated Warehouse event/data flow.
-- Run from GlobalStorageSiK-Repo with Lua 5.1.

local CORE_CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local FRAMEWORK_CLIENT = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/"

local function read(path)
	local handle = assert(io.open(path, "rb"), "cannot read " .. path)
	local source = handle:read("*a")
	handle:close()
	return source
end

local function findNode(node, id)
	if type(node) ~= "table" then return nil end
	if node.id == id then return node end
	for index = 1, #(node.children or {}) do
		local found = findNode(node.children[index], id)
		if found then return found end
	end
	return nil
end

local function action(node, event, actionId)
	for index = 1, #(node.actions or {}) do
		local candidate = node.actions[index]
		if candidate.event == event and candidate.actionId == actionId then return candidate end
	end
	error("generated action missing: " .. tostring(node.id) .. "/" .. event .. "/" .. actionId)
end

local function propDataPath(node)
	for index = 1, #(node.props or {}) do
		local prop = node.props[index]
		if prop.name == "data" and type(prop.value) == "table" then return prop.value.path end
	end
	return nil
end

local function optionValues(items)
	local values = {}
	for index = 1, #(items or {}) do values[items[index].value] = items[index].text end
	return values
end

-- These functions intentionally derive every option from the supplied catalog.
-- A hard-coded combo fixture cannot satisfy the dataset replacement assertions.
local function splitPath(encoded)
	local l1, l2, l3 = tostring(encoded or ""):match("^native:([^/]+)/?([^/]*)/?([^/]*)$")
	return l1, l2 ~= "" and l2 or nil, l3 ~= "" and l3 or nil
end

local labels = {
	food_drink = "Food and drink", perishable = "Perishable", meat = "Meat",
	vehicles = "Vehicles", consumables = "Consumables", fuel = "Fuel",
	knowledge_media = "Knowledge and media", recorded_media = "Recorded media",
	learning = "Learning",
}

local function collect(rows, level, mainKey, subKey)
	local result, seen = {}, {}
	local wantedL1 = splitPath(mainKey)
	local _, wantedL2 = splitPath(subKey)
	for index = 1, #(rows or {}) do
		local l1, l2, l3 = splitPath(rows[index].nativePath)
		local segment, key
		if level == 1 then segment, key = l1, l1 and ("native:" .. l1)
		elseif level == 2 and l1 == wantedL1 then
			segment, key = l2, l2 and ("native:" .. l1 .. "/" .. l2)
		elseif level == 3 and l1 == wantedL1 and l2 == wantedL2 then
			segment, key = l3, l3 and ("native:" .. l1 .. "/" .. l2 .. "/" .. l3)
		end
		if key and not seen[key] then
			seen[key] = true
			result[#result + 1] = { key = key, label = labels[segment] or segment }
		end
	end
	table.sort(result, function(a, b) return a.key < b.key end)
	return result
end

SiK = { UI = {} }
GlobalStorageSiK = {
	I18n = { text = function(key) return key end },
	TerminalItems = {
		collectMainCategoryFilters = function(rows) return collect(rows, 1) end,
		collectSubCategoryFilters = function(rows, mainKey) return collect(rows, 2, mainKey) end,
		collectLeafCategoryFilters = function(rows, mainKey, subKey)
			return collect(rows, 3, mainKey, subKey)
		end,
		presentationModel = function(_, terminal, rows)
			if terminal._warehouseQuery and terminal._warehouseQuery ~= "" then
				return { rows = {} }
			end
			return { rows = rows }
		end,
		tableOptions = function() return { fixture = "warehouse-runtime-adapter" } end,
	},
}

local originalRequire = require
local namespaceLoaded = false
function require(name)
	if name == "GS_I18n" then return GlobalStorageSiK.I18n end
	if name == "SiK/UI/Namespace" then
		if not namespaceLoaded then
			namespaceLoaded = true
			return dofile(FRAMEWORK_CLIENT .. "SiK/UI/Namespace.lua")
		end
		return SiK.UI
	end
	return originalRequire(name)
end

dofile(FRAMEWORK_CLIENT .. "SiK/UI/Namespace.lua")
namespaceLoaded = true
local Bindings = assert(dofile(FRAMEWORK_CLIENT .. "SiK/UI/Bindings.lua"))
local StateMachine = assert(dofile(FRAMEWORK_CLIENT .. "SiK/UI/StateMachine.lua"))
local frameworkFacade = { StateMachine = StateMachine }
local previousRequire = require
function require(name)
	if name == "GS_I18n" then return GlobalStorageSiK.I18n end
	if name == "GS_UI_Framework" then return frameworkFacade end
	if name == "SiK/UI/Namespace" then return SiK.UI.Namespace end
	if name == "GlobalStorageSiK/UI/CapacityPresentation" then
		return dofile(CORE_CLIENT .. "GlobalStorageSiK/UI/CapacityPresentation.lua")
	end
	return previousRequire(name)
end
local TabWarehouseContext = assert(dofile(CORE_CLIENT .. "GlobalStorageSiK/UI/TabWarehouseContext.lua"))
local generated = assert(dofile(CORE_CLIENT .. "GlobalStorageSiK/UI/Generated/TabWarehouse.lua"))
require = originalRequire

local root = assert(generated.surface and generated.surface.root, "generated tab-warehouse root missing")
local nodes = {
	search = assert(findNode(root, "warehouse-search-field")),
	family = assert(findNode(root, "warehouse-family-filter")),
	group = assert(findNode(root, "warehouse-group-filter")),
	detail = assert(findNode(root, "warehouse-detail-filter")),
}
assert(propDataPath(nodes.search) == "warehouse.search.query")
assert(propDataPath(nodes.family) == "warehouse.filters.family")
assert(propDataPath(nodes.group) == "warehouse.filters.group")
assert(propDataPath(nodes.detail) == "warehouse.filters.detail")
assert(#(nodes.family.options or {}) == 1 and nodes.family.options[1].id == "all",
	"generated combo must keep only its declarative fallback; runtime items come from snapshot data")

local terminal = {
	playerNum = 2,
	_mainCategoryFilterKey = "",
	_subCategoryFilterKey = "",
	_leafCategoryFilterKey = "",
	terminalState = { items = {
		{ id = "steak", nativePath = "native:food_drink/perishable/meat" },
		{ id = "petrol", nativePath = "native:vehicles/consumables/fuel" },
	} },
	refreshCount = 0,
	searchCalls = {},
}
local panel = {}
local context = assert(TabWarehouseContext.create(terminal, panel))
function terminal:refreshItemsTab()
	self.refreshCount = self.refreshCount + 1
	self.lastSnapshot = assert(context:snapshot())
end
function terminal:onSearch(explicit)
	self.searchCalls[#self.searchCalls + 1] = { explicit = explicit, query = self._warehouseQuery }
	self:refreshItemsTab()
	return true
end

local first = assert(context:snapshot())
local firstFamilies = optionValues(first.data.warehouse.filters.family.items)
assert(firstFamilies[""] and firstFamilies["native:food_drink"] and firstFamilies["native:vehicles"],
	"family combo did not consume dynamic catalog options")
assert(first.tableOptions["warehouse-table"].fixture == "warehouse-runtime-adapter")
assert(first.data.warehouse.availability.state == "ready")
assert(first.data.warehouse.availability.counts.total == 2
	and first.data.warehouse.availability.counts.available == 2)

local observed = {}
local bindings = {}
local function bind(node, event, actionId)
	local declaration = action(node, event, actionId)
	local original = assert(context.actions[actionId])
	local target = {}
	local binding = assert(Bindings.bind(target, declaration, function(envelope)
		observed[actionId] = envelope
		return original(envelope)
	end, {
		surfaceId = generated.surface.id,
		nodeId = node.id,
		componentType = node.type,
		playerNum = terminal.playerNum,
	}))
	bindings[#bindings + 1] = binding
	return target
end

local searchTarget = bind(nodes.search, "change", "warehouse.search-change")
assert(Bindings.emit(searchTarget, "change", {
	value = "bidon", component = { forbidden = true }, widget = { forbidden = true },
	items = { "forbidden" }, payload = { source = "field" },
}))
local searchEnvelope = assert(observed["warehouse.search-change"])
assert(searchEnvelope.framework == "SiK.UI" and searchEnvelope.surfaceId == "tab-warehouse")
assert(searchEnvelope.nodeId == "warehouse-search-field" and searchEnvelope.playerNum == 2)
assert(searchEnvelope.payload.value == "bidon" and searchEnvelope.payload.source == "field")
assert(searchEnvelope.payload.component == nil and searchEnvelope.payload.widget == nil
	and searchEnvelope.payload.items == nil and searchEnvelope.eventPayload == nil,
	"Bindings leaked widget/private event data into the public envelope")
assert(terminal._warehouseQuery == "bidon")
assert(#terminal.searchCalls == 1 and terminal.searchCalls[1].explicit == false)
assert(terminal.lastSnapshot.state.warehouse.search.query == "bidon",
	"search change did not propagate through refresh into the next snapshot")
assert(terminal.lastSnapshot.data.warehouse.availability.state == "empty"
	and terminal.lastSnapshot.data.warehouse.availability.reason == "no-match",
	"a valid filtered snapshot must report no-match instead of no-data/loading")

assert(Bindings.emit(searchTarget, "change", { value = "" }))
assert(terminal._warehouseQuery == "")
assert(terminal.lastSnapshot.data.warehouse.availability.state == "ready"
	and #terminal.lastSnapshot.data.warehouse.rows.rows == 2,
	"clearing search must recover the authoritative rows without reopening")

local familyTarget = bind(nodes.family, "change", "warehouse.filter-family")
assert(Bindings.emit(familyTarget, "change", {
	value = { id = "visual-id", value = "native:food_drink", text = "Food and drink" },
}))
assert(terminal._mainCategoryFilterKey == "native:food_drink")
assert(terminal._subCategoryFilterKey == "" and terminal._leafCategoryFilterKey == "")
local groups = optionValues(terminal.lastSnapshot.data.warehouse.filters.group.items)
assert(groups["native:food_drink/perishable"] and not groups["native:vehicles/consumables"],
	"family event did not drive dependent group options on refresh")

local groupTarget = bind(nodes.group, "change", "warehouse.filter-group")
assert(Bindings.emit(groupTarget, "change", {
	value = { value = "native:food_drink/perishable" },
}))
assert(terminal._subCategoryFilterKey == "native:food_drink/perishable")
assert(terminal._leafCategoryFilterKey == "")
local details = optionValues(terminal.lastSnapshot.data.warehouse.filters.detail.items)
assert(details["native:food_drink/perishable/meat"],
	"group event did not drive dependent detail options on refresh")

local detailTarget = bind(nodes.detail, "change", "warehouse.filter-detail")
assert(Bindings.emit(detailTarget, "change", {
	value = { key = "native:food_drink/perishable/meat" },
}))
assert(terminal._leafCategoryFilterKey == "native:food_drink/perishable/meat")
assert(terminal.lastSnapshot.state.warehouse.filters.detail
	== "native:food_drink/perishable/meat")
assert(terminal.refreshCount == 5, "each user event must produce exactly one product refresh")

-- Replace the authoritative catalog: the next snapshot must derive new combo
-- options and must not retain static fixture entries from the previous one.
terminal._mainCategoryFilterKey, terminal._subCategoryFilterKey,
	terminal._leafCategoryFilterKey = "", "", ""
terminal.terminalState.items = {
	{ id = "vhs", nativePath = "native:knowledge_media/recorded_media/learning" },
}
local replaced = assert(context:snapshot())
local replacedFamilies = optionValues(replaced.data.warehouse.filters.family.items)
assert(replacedFamilies["native:knowledge_media"], "replacement catalog option missing")
assert(not replacedFamilies["native:food_drink"] and not replacedFamilies["native:vehicles"],
	"combo options were retained from a static/previous snapshot")

for index = 1, #bindings do assert(bindings[index]:dispose()) end
assert(context:dispose() and context:dispose() == false)

-- The real factory must forward snapshot-provided items both at construction
-- and update. This closes the declarative node -> concrete combo bridge without
-- instantiating Project Zomboid ISUI in this pure harness.
local factoriesSource = read(FRAMEWORK_CLIENT .. "SiK/UI/Factories.lua")
assert(factoriesSource:find("if data.items ~= nil then result.items = data.items", 1, true))
assert(factoriesSource:find("items = presentation.items, selected = presentation.selected", 1, true))
assert(factoriesSource:find("handle:setItems(presentation.items, presentation.selected)", 1, true))

print("warehouse_generated_event_flow_contract: OK generated actions, stable envelopes, dynamic options, refresh")

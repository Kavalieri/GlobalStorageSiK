-- Authorial contract: the live Options tab is one generated SiK.UI surface.
-- Product code supplies data/actions only; the generated artifact owns the
-- standard block flow and its two active management tables.

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

local function read(path)
	local file = assert(io.open(path, "rb"))
	local value = assert(file:read("*a"))
	file:close()
	return value
end

local function occurrences(value, needle)
	local count = 0
	local start = 1
	while true do
		local found = string.find(value, needle, start, true)
		if not found then return count end
		count = count + 1
		start = found + #needle
	end
end

local function expectContains(value, needle, message)
	assert(string.find(value, needle, 1, true), message or ("missing: " .. needle))
end

local function expectAbsent(value, needle, message)
	assert(not string.find(value, needle, 1, true), message or ("forbidden: " .. needle))
end

local optionsPath = CLIENT .. "GS_TerminalUI_Options.lua"
local contextPath = CLIENT .. "GlobalStorageSiK/UI/TabOptionsContext.lua"
local generatedPath = CLIENT .. "GlobalStorageSiK/UI/Generated/TabOptions.lua"

local options = read(optionsPath)
local context = read(contextPath)

expectContains(options, 'require "GS_UI_Framework"', "Options must load the public SiK.UI framework")
expectContains(options, 'require "GlobalStorageSiK/UI/Generated/TabOptions"', "Options must consume the generated tab-options artifact")
expectContains(options, 'require "GlobalStorageSiK/UI/TabOptionsContext"', "Options must consume the pure tab-options context")
assert(occurrences(options, "SiK.UI.SurfaceHost.mount(") == 1,
	"Options must mount exactly one generated surface through SiK.UI.SurfaceHost")
expectContains(options, "followParent = true",
	"Options must wait for its final parent geometry before constructing widgets")
expectContains(options, "surface:refresh(snapshot)", "Options refresh must update the mounted surface")
expectContains(options, "surface:reflow(", "Options resize must reflow the mounted surface")
expectContains(options, "panel._sikOptionsSurface:dispose()", "Options lifecycle must dispose the mounted surface")

local retiredBuilders = {
	"GS_TerminalUI_NetworkList", "GS_TerminalUI_NetworkStatus",
	"GS_TerminalUI_NetworkTerminals", "GS_TerminalUI_Permissions",
	"GS_TerminalUI_Scroll", "GS_TerminalUI_Sections", "GS_TerminalUI_TabRail",
}
for i = 1, #retiredBuilders do
	expectAbsent(options, retiredBuilders[i], "Options must not load retired visual builder " .. retiredBuilders[i])
end
expectAbsent(options, "UI.Table.create", "Options caller must not paint tables manually")
expectAbsent(options, "UI.Block.create", "Options caller must not paint blocks manually")
expectAbsent(options, "UI.Controls.create", "Options caller must not paint controls manually")
expectAbsent(options, "ISUI/", "Options caller must not construct vanilla widgets directly")

local spec = assert(dofile(generatedPath))
assert(spec.surface and spec.surface.id == "tab-options", "generated artifact must own canonical surfaceId tab-options")
assert(spec.frameworkRef and spec.frameworkRef.namespace == "SiK.UI",
	"generated artifact must target the public SiK.UI namespace")
assert(spec.provenance and spec.provenance.visualMasterSha256 ==
	"c24833957e26b083bb87adef8608cde8e50dff16e6cfc03f5123feb73b6dabef",
	"generated artifact must remain pinned to Kava's validated terminal-tabs visual master")

local factories = {}
for i = 1, #(spec.componentFactories or {}) do
	local descriptor = spec.componentFactories[i]
	factories[descriptor.typeId] = descriptor.runtimeFactory
end
assert(factories.table == "SiK.UI.Table.create", "active Admin tables must use SiK.UI.Table.create")
assert(factories.block == "SiK.UI.Block.create", "active Admin blocks must use SiK.UI.Block.create")
assert(factories.control == "SiK.UI.Controls.create", "active Admin controls must use SiK.UI.Controls.create")

local function findById(node, id)
	if type(node) ~= "table" then return nil end
	if node.id == id then return node end
	local children = node.children or {}
	for i = 1, #children do
		local found = findById(children[i], id)
		if found then return found end
	end
	return nil
end

local root = spec.root or (spec.surface and spec.surface.root)
assert(findById(root, "options-network-block"), "Options must start with the selected-network block")
assert(findById(root, "options-summary-block"), "Options must contain the summary block")
assert(findById(root, "options-terminals-block"), "Options must contain the Terminales block")
assert(findById(root, "options-members-block"), "Options must contain the Miembros block")
assert(findById(root, "options-palette-block"), "Options must finish with the palette block")
assert(not findById(root, "options-admin-content"), "Retired Options subtabs must not return")

local counts = { table = 0, block = 0, control = 0 }
local actionIds = {}
local function inspect(node)
	if type(node) ~= "table" then return end
	if counts[node.type] ~= nil then counts[node.type] = counts[node.type] + 1 end
	local actionId = node.actionId or (node.props and node.props.actionId)
	if type(actionId) == "string" then actionIds[actionId] = true end
	local actions = node.actions or {}
	for i = 1, #actions do
		if type(actions[i].actionId) == "string" then actionIds[actions[i].actionId] = true end
	end
	local children = node.children or {}
	for i = 1, #children do inspect(children[i]) end
end
inspect(root)

assert(counts.table == 2, "Options must contain exactly the Terminales and Miembros tables")
assert(counts.block > 0, "Options composition must retain framework blocks")
assert(counts.control > 0, "Options composition must retain framework controls")
assert(actionIds["options.open-terminal"], "Terminales table rows must expose their generated action")
assert(actionIds["options.open-member"], "Miembros table rows must expose their generated action")

expectContains(context, "function TabOptionsContext.create(terminal)", "context must expose the canonical adapter constructor")
expectContains(context, "function context:snapshot", "context must expose a dynamic pure snapshot")
expectContains(context, "conditions", "context snapshot must expose declarative conditions")
expectContains(context, "actions", "context snapshot must expose declarative actions")
expectContains(context, "function context:dispose()", "context must expose lifecycle cleanup")
expectAbsent(context, "ISUI/", "context must not render vanilla widgets")
expectAbsent(context, "UI.Table.create", "context must not render tables")
expectAbsent(context, "UI.Block.create", "context must not render blocks")
expectAbsent(context, "UI.Controls.create", "context must not render controls")

print("admin_active_generated_surface_contract: OK")

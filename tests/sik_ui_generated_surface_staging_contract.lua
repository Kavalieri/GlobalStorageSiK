-- Runtime gate for the generated tab-warehouse/tab-options artifacts.
--
-- Warehouse remains owned by its complete host. Options is already an atomic
-- generated surface validated by Kava: its real caller must mount it exactly
-- once and must not retain the retired per-block builders.

local function readAll(path)
    local file = assert(io.open(path, "rb"), "missing file: " .. path)
    local content = file:read("*a")
    file:close()
    return content
end

local function loadArtifact(path)
    local chunk = assert(loadfile(path))
    local artifact = chunk()
    assert(type(artifact) == "table", "artifact must return a table: " .. path)
    assert(type(artifact.surface) == "table", "artifact surface missing: " .. path)
    return artifact
end

local function countNodesByType(node, wanted)
    if type(node) ~= "table" then return 0 end
    local total = node.type == wanted and 1 or 0
    local children = node.children or {}
    for i = 1, #children do
        total = total + countNodesByType(children[i], wanted)
    end
    return total
end

local function findNode(node, wanted)
    if type(node) ~= "table" then return nil end
    if node.id == wanted then return node end
    local children = node.children or {}
    for i = 1, #children do
        local found = findNode(children[i], wanted)
        if found then return found end
    end
    return nil
end

local function hasFactory(artifact, typeId, runtimeFactory)
    local factories = artifact.componentFactories or {}
    for i = 1, #factories do
        local factory = factories[i]
        if factory.typeId == typeId and factory.runtimeFactory == runtimeFactory then
            return true
        end
    end
    return false
end

local root = "GlobalStorageSiK/"
local generatedRoot = root .. "ui/generated/"
local runtimeRoot = root
    .. "Contents/mods/GlobalStorageSiK/42/media/lua/client/GlobalStorageSiK/UI/Generated/"
local clientRoot = root .. "Contents/mods/GlobalStorageSiK/42/media/lua/client/"

local warehouseSource = generatedRoot .. "tab-warehouse/tab-warehouse.generated.lua"
local warehouseRuntime = runtimeRoot .. "TabWarehouse.lua"
local optionsSource = generatedRoot .. "tab-options/tab-options.generated.lua"
local optionsRuntime = runtimeRoot .. "TabOptions.lua"

assert(readAll(warehouseRuntime) == readAll(warehouseSource),
    "TabWarehouse runtime artifact drifted from its generated source")
assert(readAll(optionsRuntime) == readAll(optionsSource),
    "TabOptions runtime artifact drifted from its generated source")

local warehouse = loadArtifact(warehouseRuntime)
local options = loadArtifact(optionsRuntime)

assert(warehouse.surface.id == "tab-warehouse", "warehouse surface id must stay exact")
assert(options.surface.id == "tab-options", "options surface id must stay exact")
assert(not string.find(optionsSource, "tab%-options%-state"),
	"Estado is an internal tab-options state, never a separate surface")
assert(not string.find(optionsSource, "tab%-options%-admin"),
	"Admin is an internal tab-options state, never a separate surface")
assert(countNodesByType(warehouse.surface.root, "table") == 1,
    "tab-warehouse must declare exactly one framework table")
assert(countNodesByType(options.surface.root, "table") == 2,
    "tab-options must declare exactly the terminal and member framework tables")
assert(hasFactory(warehouse, "table", "SiK.UI.Table.create"),
    "tab-warehouse table must resolve through the public framework")
assert(hasFactory(options, "table", "SiK.UI.Table.create"),
    "tab-options tables must resolve through the public framework")
for _, nodeId in ipairs({
    "options-network-block", "options-network-selector", "options-network-actions",
    "options-summary-block", "options-information-host", "options-information-card",
    "options-capacity", "options-info-terminals", "options-info-zones",
    "options-info-containers", "options-info-members", "options-summary-cards",
    "options-energy-card", "options-range-card", "options-palette-block",
    "options-terminals-block", "options-terminals-table", "options-members-block",
    "options-members-table", "options-succession-hint", "options-backup-warning",
    "options-claim-ownership", "options-access-copy", "options-access-form",
    "options-access-warning", "options-palette-options",
}) do
    assert(findNode(options.surface.root, nodeId),
        "tab-options staged artifact is missing current runtime node " .. nodeId)
end
local itemsSource = readAll(clientRoot .. "GS_TerminalUI_Items.lua")
local optionsLoaderSource = readAll(clientRoot .. "GS_TerminalUI_Options.lua")
local terminalSource = readAll(clientRoot .. "GS_TerminalUI.lua")

local function countPlain(source, literal)
    local count, offset = 0, 1
    while true do
        local found = string.find(source, literal, offset, true)
        if not found then return count end
        count = count + 1
        offset = found + #literal
    end
end

assert(countPlain(itemsSource, "SiK.UI.SurfaceHost.mount(") == 1,
    "tab-warehouse caller must mount exactly one generated SiK.UI SurfaceHost")
assert(string.find(itemsSource, "followParent = true", 1, true),
    "tab-warehouse SurfaceHost must follow its final parent geometry")
assert(string.find(itemsSource,
    'require "GlobalStorageSiK/UI/Generated/TabWarehouse"', 1, true),
    "tab-warehouse caller must require its generated artifact")
assert(string.find(itemsSource,
    'require "GlobalStorageSiK/UI/TabWarehouseContext"', 1, true),
    "tab-warehouse caller must require its pure product context")
assert(countPlain(optionsLoaderSource, "SiK.UI.SurfaceHost.mount(") == 1,
    "tab-options caller must mount exactly one generated SiK.UI SurfaceHost")
assert(string.find(optionsLoaderSource, "followParent = true", 1, true),
    "tab-options SurfaceHost must follow its final parent geometry")
assert(string.find(optionsLoaderSource,
    'require "GlobalStorageSiK/UI/Generated/TabOptions"', 1, true),
    "tab-options caller must require its generated artifact")
assert(string.find(optionsLoaderSource,
    'require "GlobalStorageSiK/UI/TabOptionsContext"', 1, true),
    "tab-options caller must require its pure product context")
assert(string.find(optionsLoaderSource, "TabOptionsContext.create", 1, true),
    "tab-options caller must create the product context")
for _, legacy in ipairs({
    "TerminalNetworkList", "TerminalNetworkStatus",
    "TerminalNetworkTerminals", "TerminalPermissions",
}) do
    assert(not string.find(optionsLoaderSource, legacy, 1, true),
        "tab-options caller still depends on legacy builder: " .. legacy)
end
assert(string.find(terminalSource, "function GS_TerminalUI:buildItemsToolbar", 1, true),
    "warehouse host ownership changed: re-evaluate the atomic migration gate")

print("PASS: generated tab-options is mounted once through its context; legacy builders are absent")

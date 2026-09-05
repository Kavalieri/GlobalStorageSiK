-- Consumer-side regression gate for the framework contracts that protect
-- Global Storage tables and exact tab icons before an in-game candidate exists.
local root = arg[1] or "."
local framework = root
	.. "/SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/SiK/UI/"

local function read(path)
	local file = assert(io.open(path, "rb"), path)
	local source = file:read("*a"); file:close(); return source
end
local blockSource = read(framework .. "Block.lua")
local builderSource = read(framework .. "Builder.lua")
local factoriesSource = read(framework .. "Factories.lua")
local surfaceSource = read(framework .. "Surface.lua")
assert(blockSource:find("widget ~= panel and widget.reflow", 1, true)
	and blockSource:find("widget:reflow({ x = x, y = y, w = w or panel.width", 1, true),
	"Block column no longer reflows composite handles through their public boundary")
for _, symbol in ipairs({ "duplicate runtime node", "runtime handle reused",
	"validateRuntimeCoherence", "table_root_duplicate", "table_geometry" }) do
	assert(builderSource:find(symbol, 1, true), "Builder runtime coherence guard missing: " .. symbol)
end
assert(factoriesSource:find("SiK.UI.Table.normalizeColumns(node.columns)", 1, true)
	and factoriesSource:find("validateNode = definition.validateNode", 1, true),
	"Table schema is not registered through the canonical factory contract")
assert(surfaceSource:find('type(contract.validateNode) == "function"', 1, true),
	"Surface validation does not execute component typing guards")

require = function() return nil end
UIFont = { Small = "Small" }
function getTextManager()
	return { getFontHeight = function() return 12 end,
		MeasureStringX = function(_, _, text) return #tostring(text or "") * 6 end }
end
ISPanel = { new = function() return {} end, onMouseDown = function() return false end,
	onMouseMove = function() return false end, onMouseUp = function() return false end }
SiK = { UI = {} }
dofile(framework .. "Namespace.lua")
dofile(framework .. "Metrics.lua")
SiK.UI.Theme = { color = function() return { r = 1, g = 1, b = 1, a = 1 } end,
	tokens = function() return { text = {}, textMuted = {}, border = {}, info = {},
		warning = {}, danger = {}, textPrimary = {}, textSecondary = {}, divider = {},
		rowHover = {} } end }
SiK.UI.Controls = { metrics = function() return { rowHeight = 32, buttonHeight = 30,
	inputHeight = 30, rowGap = 6, controlGap = 6 } end,
	truncateText = function(text) return tostring(text or "") end }
dofile(framework .. "Table.lua")
local Table = SiK.UI.Table
local columns = assert(Table.normalizeColumns({
	{ key = "name", label = "Name", weight = 3 },
	{ key = "state", title = "State", flex = 1 },
}))
assert(columns[1].title == "Name" and columns[1].flex == 3,
	"legacy column aliases were not normalized")
local duplicate, duplicateReason = Table.normalizeColumns({
	{ key = "same", title = "A", flex = 1 }, { key = "same", title = "B", flex = 1 },
})
assert(not duplicate and duplicateReason == "column_key_duplicate:same",
	"duplicate column keys were accepted")
local conflict, conflictReason = Table.normalizeColumns({
	{ key = "a", title = "A", flex = 1, weight = 2 }, { key = "b", title = "B", flex = 1 },
})
assert(not conflict and conflictReason == "column_flex_conflict",
	"conflicting column aliases were accepted")
local layout, metrics = Table.resolveColumns(600, columns, {}), Table.metrics()
assert(layout[1].finish <= layout[2].x and layout[2].finish <= 600,
	"canonical columns overlap or overflow")
assert(Table.intrinsicHeight(3, {}) == metrics.headerHeight + metrics.rowHeight * 3,
	"Builder and Table height contracts drifted")

local Icon = dofile(framework .. "Icon.lua")
local texture = { id = "tab" }
local callable = setmetatable({}, { __call = function(_, target, received, x, y, w, h)
	target.drawn = { texture = received, x = x, y = y, w = w, h = h }
end })
local target = setmetatable({}, { __index = { drawTextureScaled = callable } })
assert(type(target.drawTextureScaled) ~= "function", "fixture did not reproduce Kahlua callable type")
local ok, reason = Icon.drawExact(target,
	{ texture = texture, width = 56, height = 56 }, 10, 10, 56, 56, {})
assert(ok == true and target.drawn and target.drawn.texture == texture,
	"exact inherited renderer failed: " .. tostring(reason))

local nativeCalls, scaledCalls = 0, 0
local nativeCallable = setmetatable({}, { __call = function(_, nativeTarget, received, x, y)
	nativeCalls = nativeCalls + 1
	nativeTarget.nativeDrawn = { texture = received, x = x, y = y }
end })
local scaledCallable = setmetatable({}, { __call = function()
	scaledCalls = scaledCalls + 1
end })
local nativeTarget = setmetatable({}, { __index = {
	drawTexture = nativeCallable,
	drawTextureScaled = scaledCallable,
} })
local nativeOk, nativeReason = Icon.drawExact(nativeTarget,
	{ texture = texture, width = 56, height = 56 }, 10, 10, 56, 56, {})
assert(nativeOk == true and nativeCalls == 1 and scaledCalls == 0
	and nativeTarget.nativeDrawn and nativeTarget.nativeDrawn.texture == texture,
	"exact renderer did not preserve the native no-scale path: " .. tostring(nativeReason))
print("framework_critical_runtime_guards_contract: OK")

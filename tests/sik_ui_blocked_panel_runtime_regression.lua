local framework = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/"
	.. "SiKUIFramework/42/"
local ui = framework .. "media/lua/client/SiK/UI/"
local blockedPath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
	.. "GS_TerminalUI_BlockedPanel.lua"

local function read(path)
	local file = assert(io.open(path, "rb"), "cannot read " .. path)
	local source = file:read("*a")
	file:close()
	return source
end

local function exists(path)
	local file = io.open(path, "rb")
	if not file then return false end
	file:close()
	return true
end

local actionGroup = read(ui .. "ActionGroup.lua")
local scroll = read(ui .. "Scroll.lua")
local controls = read(ui .. "Controls.lua")
local block = read(ui .. "Block.lua")
local blocked = read(blockedPath)

-- Execute the real axis resolver. A flex row with height metadata and no
-- width must never reinterpret that height as a fixed width.
SiK = { UI = {
	Layout = {
		insets = function() return { left = 0, right = 0, top = 0, bottom = 0 } end,
		inset = function(rect) return rect end,
		alignRect = function(available) return available end,
	},
	Metrics = { block = { padding = 8 } },
	Controls = {},
	Theme = { normalizeColor = function(value, fallback) return value or fallback end },
} }
package.loaded["SiK/UI/Namespace"] = true
package.loaded["SiK/UI/Controls"] = true
package.loaded["SiK/UI/Layout"] = true
package.loaded["SiK/UI/Metrics"] = true
package.loaded["SiK/UI/Theme"] = true
SiK.UI.Namespace = { define = function(_, value) return value end }
local Container = assert(dofile(ui .. "Container.lua"))
local rects = Container.resolveRects({ x = 0, y = 0, w = 924, h = 47 }, {
	{ height = 47, grow = 1 }, { height = 47, grow = 1 },
}, { mode = "row", gap = 8, padding = 0, align = "stretch", verticalAlign = "middle" })
assert(rects[1].w == 458 and rects[2].w == 458 and rects[2].x == 466,
	"equal row must distribute 924 px as 458 + 8 + 458, not use height as width")

assert(actionGroup:find('options.mode = options.wrap and "wrap" or options.direction', 1, true),
	"semantic ActionGroup modes must normalize to Container geometry")
assert(actionGroup:find("normalized.width = nil", 1, true)
	and actionGroup:find("normalized.grow = 1", 1, true),
	"equal ActionGroup must ignore construction widths and distribute the row")
assert(actionGroup:find('options.fillParentWidth = mode == "equal" or mode == "stack"', 1, true),
	"structural action groups must follow their parent final width")
assert(block:find("reflowNestedContainers(self.content)", 1, true),
	"Block reflow must synchronously propagate final geometry to nested containers")
assert(scroll:find("return instance:scrollBy((tonumber(delta)", 1, true),
	"compatibility scroll regions must preserve the B42 runtime wheel direction")
assert(controls:find('DEFAULT_INFO_ICON = "sik.info.24"', 1, true),
	"section information must use the framework-owned exact-size icon asset")
assert(controls:find('text = "", chrome = false, iconPadding = 0', 1, true),
	"section information icon must render without text or button chrome")
assert(controls:find('if self.chrome and type(previousPrerender)', 1, true),
	"chrome-free icons must suppress vanilla prerender chrome")
assert(controls:find('n(info.size, 24)', 1, true),
	"section information icon must use the legible framework standard size")
assert(exists(framework .. "media/ui/SiKUIFramework/SiK_Icon_Info_24.png"),
	"framework information icon asset must be packaged")
assert(not blocked:find("REQ_ICON", 1, true),
	"blocked panel must consume the framework requirement-icon standard")
assert(blocked:find('mode = "equal"', 1, true),
	"blocked panel primary actions must use the shared equal layout")

print("sik_ui_blocked_panel_runtime_regression: OK")

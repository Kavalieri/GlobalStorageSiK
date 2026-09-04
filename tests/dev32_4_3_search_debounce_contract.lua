-- Historical filename retained for runner compatibility.
-- Current contract: public SiK.UI owns the neutral debounce/Unicode thresholds;
-- the product receives only effective changes and explicit immediate submits.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("dev32_4_3_search_debounce_contract")

getTextManager = function()
	return {
		getFontHeight = function() return 12 end,
		MeasureStringX = function(_, _, text) return #tostring(text or "") end,
	}
end

local Controls = Support.loadFrameworkModule(suite, "Controls")
local parent = ISPanel:new(0, 0, 500, 120); parent:initialise()
local changed, submitted = {}, {}
local now = 1000
local search = Controls.search(parent, {
	x = 8, y = 8, w = 300, h = 32,
	debounceMs = 180, minChars = 3, wideMinChars = 2,
	now = function() return now end,
	onChange = function(context) changed[#changed + 1] = context.value end,
	onSubmit = function(context) submitted[#submitted + 1] = context.value end,
})

Support.check(suite, "rapid edits apply only the latest eligible value", function()
	for _, value in ipairs({ "ab", "abc", "abcd", "abcde" }) do
		search.entry.text = value
		search.entry:onTextChange()
	end
	assert(#changed == 0, "rapid edits bypassed the public debounce")
	now = 1179; search:update()
	assert(#changed == 0, "search applied before the debounce deadline")
	now = 1180; search:update()
	assert(#changed == 1 and changed[1] == "abcde",
		"search did not apply exactly the latest eligible value")
	assert(search:getText() == "abcde", "search getter is stale")
	return true
end)

Support.check(suite, "UTF-8 character thresholds and submit remain exact", function()
	local accented = "b" .. string.char(0xC3, 0xAD) .. "d"
	local cjk = string.char(0xE6, 0xB1, 0xBD, 0xE6, 0xB2, 0xB9)
	search.entry.text = accented; search.entry:onTextChange()
	now = 1360; search:update()
	assert(changed[#changed] == accented, "accented Latin text was miscounted as wide")
	search.entry.text = cjk; search.entry:onTextChange()
	now = 1540; search:update()
	assert(changed[#changed] == cjk, "two wide UTF-8 characters were not eligible")
	search.action.onclick(search.action.target)
	assert(submitted[#submitted] == cjk, "submit did not reread current entry text")
	assert(search._sikSearchDeadline == nil, "submit left pending debounce work")
	return true
end)

Support.check(suite, "resize retains one entry and one square action", function()
	search:setBounds(12, 14, 420, 36)
	assert(search.entry.width == 420 - 36 - Controls.metrics().controlGap,
		"entry width did not consume the available row")
	assert(search.action.x == 420 - 36 and search.action.width == 36,
		"search action is not right-aligned or square")
	return true
end)

Support.check(suite, "Core consumes public search with explicit change and submit paths", function()
	local root = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
	local function read(path)
		local file = assert(io.open(root .. path, "rb"), path)
		local source = file:read("*a"); file:close()
		return source
	end
	local owner = read("GS_TerminalUI_Items.lua")
	local context = read("GlobalStorageSiK/UI/TabWarehouseContext.lua")
	local generated = read("GlobalStorageSiK/UI/Generated/TabWarehouse.lua")
	assert(owner:find('require "GlobalStorageSiK/UI/Generated/TabWarehouse"', 1, true),
		"Warehouse does not consume the generated search surface")
	assert(owner:find("SiK.UI.SurfaceHost.mount(panel, TabWarehouseSpec, {", 1, true)
		and owner:find("followParent = true", 1, true),
		"Warehouse does not build search after final parent geometry")
	assert(context:find('["warehouse.search%-change"]', 1),
		"Warehouse lost its text-change action")
	assert(context:find('["warehouse.search"]', 1, true),
		"Warehouse lost its explicit submit action")
	assert(context:find("terminal:onSearch(false)", 1, true)
		and context:find("terminal:onSearch(true)", 1, true),
		"Warehouse search actions no longer preserve change/submit semantics")
	assert(generated:find('["id"] = "warehouse-search-field"', 1, true),
		"generated surface lost its public search field")
	return true
end)

Support.finish(suite)

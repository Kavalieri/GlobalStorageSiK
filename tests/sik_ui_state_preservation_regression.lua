-- Author regression for rebuild-safe SiK UI offset and semantic selection.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_state_preservation_regression")

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

local function readSource(name)
	local file = assert(io.open(CLIENT .. name, "rb"), "missing source: " .. name)
	local source = file:read("*a")
	file:close()
	return source
end

local function position(source, needle, after)
	local found = source:find(needle, after or 1, true)
	assert(found, "missing marker: " .. needle)
	return found
end

local function assertRoundtrip(name, functionMarker)
	local source = readSource(name)
	local start = position(source, functionMarker)
	local capture = position(source, "local preservedState = capture", start)
	local clear = position(source, "TerminalScroll.clear", start)
	local finish = source:find("TerminalScroll.finish", clear, true)
		or position(source, "TerminalScroll.setContentHeight", clear)
	local restore = position(source, "restore", finish)
	assert(capture < clear, name .. " captures state after clear")
	assert(finish < restore, name .. " restores state before content is rebuilt")
	assert(source:find("TerminalScroll.getScrollOffset", 1, true),
		name .. " does not capture the offset through TerminalScroll")
	assert(source:find("TerminalScroll.setScrollOffset", 1, true),
		name .. " does not restore the offset through TerminalScroll")
	assert(source:find("selectedKey = scroll._sikSelectedKey", 1, true),
		name .. " does not capture semantic selection")
	assert(source:find("scroll._sikSelectedKey = state.selectedKey", 1, true),
		name .. " does not restore semantic selection")
	return true
end

Support.check(suite, "audit summary preserves offset and selection across rebuild", function()
	return assertRoundtrip("GS_AdminDashboard_Audit.lua",
		"function GlobalStorageSiK.AdminDashboardAudit.refreshSummary")
end)

Support.check(suite, "corpus summary preserves offset and selection across rebuild", function()
	return assertRoundtrip("GS_AdminDashboard_Corpus.lua",
		"function GlobalStorageSiK.AdminDashboardCorpus.refreshSummary")
end)

Support.check(suite, "blocked panel preserves offset and selection across rebuild", function()
	return assertRoundtrip("GS_TerminalUI_BlockedPanel.lua",
		"function GlobalStorageSiK.TerminalBlockedPanel.rebuildContent")
end)

Support.check(suite, "staff audit controls consume the canonical button metric", function()
	for _, name in ipairs({ "GS_AdminDashboard_Audit.lua", "GS_AdminDashboard_Corpus.lua" }) do
		local source = readSource(name)
		assert(source:find("SiK_UI.Controls.metrics().buttonHeight", 1, true),
			name .. " does not use Controls.metrics().buttonHeight")
		assert(not source:find("BTN_H = FONT_HGT_SMALL + 8", 1, true),
			name .. " retains a local button-height variant")
	end
	return true
end)

Support.finish(suite)

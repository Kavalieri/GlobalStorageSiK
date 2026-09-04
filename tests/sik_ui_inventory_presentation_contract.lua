-- Author contract for validated Warehouse presentation details.
-- Static/pure checks only: this does not render Project Zomboid UI.

local Support = dofile("tests/helpers/sik_ui_contract_support.lua")
local suite = Support.newSuite("sik_ui_inventory_presentation_contract")

local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
local SHARED = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"

local function read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a")
	file:close()
	return text
end

local function contains(text, needle, label)
	assert(text:find(needle, 1, true), label or ("missing " .. needle))
end

local function excludes(text, needle, label)
	assert(not text:find(needle, 1, true), label or ("unexpected " .. needle))
end

local terminal = read(CLIENT .. "GS_TerminalUI.lua")
local items = read(CLIENT .. "GS_TerminalUI_Items.lua")
local controls = read(Support.frameworkPath("Controls.lua"))
local warehouseArtifact = read(CLIENT .. "GlobalStorageSiK/UI/Generated/TabWarehouse.lua")
local tooltip = read(CLIENT .. "GS_ItemNetworkTooltip.lua")
local en = read(SHARED .. "Translate/EN/IG_UI.json")
local es = read(SHARED .. "Translate/ES/IG_UI.json")

Support.check(suite, "search owns one full row and filters own the following row", function()
	contains(warehouseArtifact, '["id"] = "warehouse-search-form"',
		"generated Warehouse has no independent search form")
	contains(warehouseArtifact, '["id"] = "warehouse-filter-form"',
		"generated Warehouse has no independent filter form")
	contains(warehouseArtifact, '["id"] = "warehouse-family-filter"',
		"generated Warehouse lost the Family filter")
	contains(warehouseArtifact, '["id"] = "warehouse-group-filter"',
		"generated Warehouse lost the Group filter")
	contains(warehouseArtifact, '["id"] = "warehouse-detail-filter"',
		"generated Warehouse lost the Detail filter")
	excludes(terminal, "self.searchBox:setBounds", "terminal shell still paints Warehouse search geometry")
	excludes(terminal, "mainCategoryFilterCombo:setBounds", "terminal shell still paints Warehouse filters")
	excludes(terminal, "searchSpacer", "invisible search reservation returned")
	excludes(terminal, "searchGapWidget", "invisible search reservation returned")
	contains(controls, "panel.width - buttonW - metrics.controlGap",
		"public search does not reserve exactly one action and one gap")
	contains(controls, "self.action:setX(width - actionW)",
		"public search action does not remain anchored at the right")
	contains(controls, "self.entry:setWidth(math.max(1, width - actionW - metrics.controlGap))",
		"public search entry does not reflow from current bounds")
	return true
end)

Support.check(suite, "network tooltip does not duplicate taxonomy", function()
	excludes(tooltip, "IGUI_GS_CategoryTooltipMain",
		"network tooltip still renders a duplicate Family line")
	excludes(tooltip, "IGUI_GS_CategoryTooltipSub",
		"network tooltip still renders a duplicate Group line")
	excludes(tooltip, "IGUI_GS_CategoryTooltipLeaf",
		"network tooltip still renders a duplicate Detail line")
	return true
end)

Support.check(suite, "Moveable Misc fallback is presentation-only and resolves a concrete family", function()
	contains(items, "local function presentationProjection(data)",
		"Warehouse has no presentation fallback")
	contains(items, 'projection.vanillaKey ~= "Misc"',
		"fallback is not limited to unclassified presentation")
	contains(items, "data.worldSprite", "fallback ignores Moveable sprite evidence")
	contains(items, "CategoryResolution.presentation(data.fullType, data, probe)",
		"fallback does not resolve the reconstructed instance")
	contains(items, "presentation.labels.full",
		"fallback does not expose the resolved Family path")
	excludes(items, "row.nativePath = resolved.nativePath",
		"presentation fallback mutates authoritative row taxonomy")
	contains(es, '"IGUI_ItemCat_GSSiK_home_leisure_collection_furnishing_storage": '
		.. '"Hogar, ocio y colección > Mobiliario > Almacenamiento"',
		"Spanish Moveable path is absent or humanized in English")
	contains(en, '"IGUI_ItemCat_GSSiK_home_leisure_collection_furnishing_storage": '
		.. '"Home, Leisure & Collection > Furnishing > Storage"',
		"English Moveable path is absent")
	return true
end)

Support.check(suite, "warehouse tooltip preserves row identity for counts and media only", function()
	contains(items, "row._gsTooltip._gsRemoteRow = data",
		"virtualized row does not bind its authoritative identity")
	contains(tooltip, "buildTooltipBlocks(self.item, self._gsRemoteRow)",
		"tooltip ignores warehouse identity")
	contains(tooltip, "local remoteIdentity = rowContext or",
		"tooltip can lose its explicit row identity")
	contains(tooltip, "IGUI_GS_NetworkCountLine",
		"tooltip lost its network-specific information")
	return true
end)

Support.finish(suite)

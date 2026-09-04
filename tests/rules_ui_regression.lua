-- Regression tests for Core 1.4.3-dev30.3 rule colors and summaries.
-- Run from repository root: lua51.exe tests/rules_ui_regression.lua

for _, name in ipairs({ "GS_I18n", "GS_ItemTaxonomy", "GS_NativeProduct",
	"GS_RuleSanitizer", "GS_Subcategories", "GS_NodeFilters", "GS_CategoryResolution" }) do
	package.loaded[name] = true
end
package.loaded["GS_UI_Framework"] = {
	Controls = { wrapText = function(text) return { text } end },
}

UIFont = { Small = "Small" }
function getTextManager()
	return { MeasureStringX = function(_, _, text) return #tostring(text or "") * 6 end }
end

local translations = {
	IGUI_GS_NodeRulesSummaryUnrestricted = "Accepts anything.",
	IGUI_GS_NodeRulesSummaryAccepts = "Accepts: {1}.",
	IGUI_GS_NodeRulesSummaryAlso = " Also requires: {1}.",
	IGUI_GS_NodeRulesSummaryNever = " Never accepts: {1}.",
	IGUI_GS_NodeRulesJoinOr = " or ",
	IGUI_GS_NodeRulesJoinAnd = " and ",
	IGUI_GS_NodeRulesJoinNot = " nor ",
}

GlobalStorageSiK = {
	I18n = { text = function(key, value)
		local text = translations[key] or key
		if value ~= nil then text = text:gsub("{1}", tostring(value)) end
		return text
	end },
	ItemTaxonomy = {
		EXT_GROUP_PREFIX = "__extgroup__:", SUBGROUP_PREFIX = "__subgroup__:",
		translateMainKey = function(key) return key end,
		translateSubKey = function(key) return key end,
		hierarchyLabel = function(key) return key end,
	},
	Subcategories = { isSubcategoryKey = function() return false end },
	NodeFilters = { describe = function(condition)
		return tostring(condition.type) .. ": " .. tostring(condition.value)
	end },
	NativeProduct = {
		decodePath = function(value)
			if type(value) == "string" and value:sub(1, 7) == "native:" then
				return { l1 = "food_drink" }
			end
			return nil
		end,
		getView = function() return { fullLabel = "Food > Perishable" } end,
		getColor = function() return { 0.45, 0.78, 0.53 } end,
	},
	CategoryResolution = {
		classifyStoredRule = function() return "SOURCE_CATEGORY" end,
		isVanillaKey = function() return false end,
		label = function() return "" end,
	},
	RuleSanitizer = { isJunkCategoryCondition = function(condition)
		return condition and condition.type == "category"
			and (condition.nativePath == "F" or (condition.nativePath == nil and condition.value == "F"))
	end },
}

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected=" .. tostring(expected)
			.. " actual=" .. tostring(actual), 2)
	end
end

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_RulesUI.lua")

local rules = {
	{ op = "OR", condition = { type = "category", value = "ProjectedFood",
		nativePath = "native:food_drink/perishable" } },
	{ op = "AND", condition = { type = "tag", value = "Packaged" } },
	{ op = "NOT", condition = { type = "category", value = "SafeLegacy", nativePath = "F" } },
}
local summary = GlobalStorageSiK.RulesUI.buildSummary(rules)
assertEqual(summary, "Accepts: Food > Perishable. Also requires: tag: Packaged.",
	"plain summary preserves localized sentence")

local segments = GlobalStorageSiK.RulesUI.buildSummarySegments(rules)
local rebuilt = ""
for i = 1, #segments do rebuilt = rebuilt .. segments[i].text end
assertEqual(rebuilt, summary, "colored segments preserve exact plain summary")

local neutral = { 0.7, 0.7, 0.7 }
local layout = GlobalStorageSiK.RulesUI.layoutSummary(rules, 500, UIFont.Small, neutral)
local categoryColored, prefixNeutral = false, false
for i = 1, #layout.runs do
	local run = layout.runs[i]
	if run.text:find("Food", 1, true) and run.color[2] == 0.78 then categoryColored = true end
	if run.text:find("Accepts", 1, true) and run.color == neutral then prefixNeutral = true end
end
assertEqual(categoryColored, true, "native category fragment uses L1 color")
assertEqual(prefixNeutral, true, "summary statement remains neutral")

local compact = GlobalStorageSiK.RulesUI.compactSummary(rules)
assertEqual(compact.label, "Food > Perishable", "compact summary selects visible category")
assertEqual(compact.extraCount, 1, "junk rule excluded from compact additional count")
assertEqual(compact.condition.nativePath, "native:food_drink/perishable",
	"compact summary exposes condition for L1 color")
assertEqual(GlobalStorageSiK.RulesUI.conditionColor({ type = "category", value = "Legacy" }, neutral),
	neutral, "valid legacy category uses neutral fallback")

print("rules_ui_regression: OK")

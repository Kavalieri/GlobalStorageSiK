-- Author contract: documentary taxonomy map must match the runtime registry.
-- Pure Lua 5.1: parses stable data-* attributes; it does not render HTML or open PZ.

local HTML_PATH = "../Documentacion/UI/taxonomia-categorias.html"
local SHARED = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/"

local function readFile(path)
	local handle = io.open(path, "rb")
	if not handle then return nil end
	local text = handle:read("*a")
	handle:close()
	return text
end

GlobalStorageSiK = {}
dofile(SHARED .. "GS_NativeTaxonomyRegistry.lua")
dofile(SHARED .. "GS_NativeTaxonomy_GroundTruth.lua")

local function pathKey(l1, l2, l3)
	local value = tostring(l1 or "")
	if l2 then value = value .. "/" .. tostring(l2) end
	if l3 then value = value .. "/" .. tostring(l3) end
	return value
end

local groundTruthByPath = {}
local groundTruthByType = {}
for _, case in ipairs(GlobalStorageSiK.NativeTaxonomyGroundTruth.cases or {}) do
	if case.fullType then
		local byType = groundTruthByType[case.fullType]
		if not byType then byType = {}; groundTruthByType[case.fullType] = byType end
		byType[#byType + 1] = case
	end
	if case.expectedL1 and case.expectedL2 then
		local l3 = type(case.expectedL3) == "string" and case.expectedL3 or nil
		groundTruthByPath[pathKey(case.expectedL1, case.expectedL2, l3)] = true
	end
end

local terminalRouteCount, coveredTerminalRouteCount = 0, 0
local groundTruthGaps = {}
local registryTree = GlobalStorageSiK.NativeTaxonomyRegistry.getTree()
for l1, l2s in pairs(registryTree) do
	for l2, l3s in pairs(l2s) do
		if #l3s == 0 then
			local key = pathKey(l1, l2)
			terminalRouteCount = terminalRouteCount + 1
			if groundTruthByPath[key] then coveredTerminalRouteCount = coveredTerminalRouteCount + 1
			else groundTruthGaps[#groundTruthGaps + 1] = key end
		else
			for i = 1, #l3s do
				local key = pathKey(l1, l2, l3s[i])
				terminalRouteCount = terminalRouteCount + 1
				if groundTruthByPath[key] then coveredTerminalRouteCount = coveredTerminalRouteCount + 1
				else groundTruthGaps[#groundTruthGaps + 1] = key end
			end
		end
	end
end
table.sort(groundTruthGaps)
print("taxonomy_groundtruth_coverage: " .. tostring(coveredTerminalRouteCount) .. "/"
	.. tostring(terminalRouteCount) .. " terminal routes")
for i = 1, #groundTruthGaps do print("taxonomy_groundtruth_gap: " .. groundTruthGaps[i]) end

local html = assert(readFile(HTML_PATH),
	"missing canonical taxonomy map " .. HTML_PATH
		.. " (do not point this gate at a historical mockup)")

package.loaded["GS_CatalogManager"] = true
package.loaded["GS_NativeClassifier"] = true
package.loaded["GS_NativeTaxonomyRegistry"] = true
GlobalStorageSiK.CatalogManager = {
	createEpochCache = function() return {} end,
	onEpochChanged = function() end,
	getEpoch = function() return 1 end,
	getLanguageEpoch = function() return 1 end,
	getCatalogFingerprint = function() return "taxonomy-map-fixture" end,
}
GlobalStorageSiK.NativeClassifier = {
	classify = function() return nil end,
	getMetrics = function() return {} end,
}
dofile(SHARED .. "GS_NativeProduct.lua")

local failures = {}
local function check(condition, message)
	if not condition then failures[#failures + 1] = message end
end

local function parseAttributes(tag)
	local attrs = {}
	for key, value in tag:gmatch('data%-([%w%-]+)%s*=%s*"([^"]*)"') do
		attrs[key] = value
	end
	return attrs
end

local documentBranches = {}
local documentColors = {}
local examples = {}
local markerCount = 0
for tag in html:gmatch("<[^>]+>") do
	local attrs = parseAttributes(tag)
	if attrs.l1 or attrs.l2 or attrs.l3 or attrs["color-rgb"] or attrs["example-fulltype"] then
		markerCount = markerCount + 1
		check(attrs.l1 ~= nil and attrs.l1 ~= "", "taxonomy marker lacks data-l1")
		check(not attrs.l3 or (attrs.l2 and attrs.l2 ~= ""),
			"data-l3 requires data-l2 for " .. tostring(attrs.l1))
		if attrs.l1 and attrs.l1 ~= "" then
			documentBranches[pathKey(attrs.l1)] = true
			if attrs.l2 and attrs.l2 ~= "" then
				documentBranches[pathKey(attrs.l1, attrs.l2)] = true
				if attrs.l3 and attrs.l3 ~= "" then
					documentBranches[pathKey(attrs.l1, attrs.l2, attrs.l3)] = true
				end
			end
			if attrs["color-rgb"] then
				local previous = documentColors[attrs.l1]
				check(not previous or previous == attrs["color-rgb"],
					"conflicting data-color-rgb values for " .. attrs.l1)
				documentColors[attrs.l1] = attrs["color-rgb"]
			end
			if attrs["example-fulltype"] then
				examples[#examples + 1] = {
					fullType = attrs["example-fulltype"], l1 = attrs.l1,
					l2 = attrs.l2 ~= "" and attrs.l2 or nil,
					l3 = attrs.l3 ~= "" and attrs.l3 or nil,
				}
			end
		end
	end
end
check(markerCount > 0, "taxonomy map has no stable data-l1/data-l2/data-l3 markers")

local registryBranches = {}
local tree = registryTree
for l1, l2s in pairs(tree) do
	registryBranches[pathKey(l1)] = true
	for l2, l3s in pairs(l2s) do
		registryBranches[pathKey(l1, l2)] = true
		for i = 1, #l3s do
			registryBranches[pathKey(l1, l2, l3s[i])] = true
		end
	end
end
for branch in pairs(registryBranches) do
	check(documentBranches[branch] == true, "document is missing registry branch " .. branch)
end
for branch in pairs(documentBranches) do
	check(registryBranches[branch] == true, "document declares unknown registry branch " .. branch)
end

local function parseRgb(value)
	local r, g, b = tostring(value or ""):match(
		"^%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)%s*$")
	return tonumber(r), tonumber(g), tonumber(b)
end

local function sameColor(documentValue, runtime)
	local r, g, b = parseRgb(documentValue)
	if not r or not g or not b or not runtime then return false end
	if r <= 1 and g <= 1 and b <= 1 then
		return math.abs(r - runtime[1]) < 0.0001
			and math.abs(g - runtime[2]) < 0.0001
			and math.abs(b - runtime[3]) < 0.0001
	end
	return r == math.floor(runtime[1] * 255 + 0.5)
		and g == math.floor(runtime[2] * 255 + 0.5)
		and b == math.floor(runtime[3] * 255 + 0.5)
end

for l1 in pairs(tree) do
	local runtimeColor = GlobalStorageSiK.NativeProduct.getColor({ l1 = l1 })
	check(documentColors[l1] ~= nil, "document is missing data-color-rgb for " .. l1)
	if documentColors[l1] then
		check(sameColor(documentColors[l1], runtimeColor),
			"document color differs from GS_NativeProduct L1 color for " .. l1)
	end
end

for i = 1, #examples do
	local example = examples[i]
	check(example.fullType:match("^[%w_]+%.[%w_]+$") ~= nil,
		"invalid data-example-fulltype " .. tostring(example.fullType))
	local candidates = groundTruthByType[example.fullType]
	check(candidates ~= nil,
		"example has no deterministic GroundTruth case: " .. tostring(example.fullType))
	local matched = false
	for j = 1, #(candidates or {}) do
		local case = candidates[j]
		local expectedL3 = type(case.expectedL3) == "string" and case.expectedL3 or nil
		if case.expectedL1 == example.l1 and case.expectedL2 == example.l2
			and expectedL3 == example.l3 then
			matched = true
			break
		end
	end
	check(matched, "example GroundTruth path mismatch for " .. tostring(example.fullType)
		.. ": document=" .. pathKey(example.l1, example.l2, example.l3))
end

if #failures > 0 then
	error("ui_taxonomy_map_parity_regression failed:\n - " .. table.concat(failures, "\n - "), 0)
end

print("ui_taxonomy_map_parity_regression: OK branches=" .. tostring(markerCount)
	.. " examples=" .. tostring(#examples))

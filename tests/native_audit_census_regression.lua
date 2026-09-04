-- Regression test for Core 1.4.3-dev32.3 census writer.
-- Run from GlobalStorageSiK-Repo: lua51.exe tests/native_audit_census_regression.lua
-- This is a local writer contract only; it does not claim a PZ catalog run.

package.loaded["GS_CatalogManager"] = true
package.loaded["GS_NativeTaxonomyRegistry"] = true
package.loaded["GS_NativeClassifier"] = true
package.loaded["GS_AddonRegistry"] = true
package.loaded["GS_NativeClassifierUtils"] = true
package.loaded["GSSiK_API"] = true

GlobalStorageSiK = {
	NativeClassifierUtils = {
		bodyLocation = function() return nil end,
	},
}
GSSiK = { API = { Addon = {
	list = function() return true, nil, {} end,
	moduleItemTypes = function() return true, nil, {} end,
} } }

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected=" .. tostring(expected)
			.. " actual=" .. tostring(actual), 2)
	end
end

local writes = {}
local writerClosed = false
getFileWriter = function(fileName, create, append)
	assertEqual(fileName, "SiKDiagnostics/test/taxonomy/census-000001.log", "session path")
	assertEqual(create, true, "writer must create census")
	assertEqual(append, false, "census run must not append")
	return {
		write = function(_, text) writes[#writes + 1] = text end,
		close = function() writerClosed = true end,
	}
end

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeAudit.lua")

local ok, err = GlobalStorageSiK.NativeAudit.writeCensusTsv({
	diagnosticCensusFile = "SiKDiagnostics/test/taxonomy/census-000001.log",
	censusInventory = {
		{
			fullType = "Base.Nails", outcome = "classified", l1 = "materials",
			l2 = "components", l3 = "fastener", source = "exact_fulltype",
			confidence = 100, reason = "", bodyLocation = nil,
		},
		{
			fullType = "Base.Wound_Test", outcome = "excluded_internal", l1 = "other",
			l2 = "unclassified_modded", l3 = "", source = "fallback",
			confidence = 0, reason = "body_location_wound", bodyLocation = "base:wound",
		},
	},
})

assertEqual(ok, true, "census writer result")
assertEqual(err, nil, "census writer error")
assertEqual(writerClosed, true, "writer must close")
assertEqual(writes[1], "fullType\toutcome\tl1\tl2\tl3\tsource\tconfidence\treason\tbodyLocation\r\n",
	"census header")
assertEqual(writes[2], "Base.Nails\tclassified\tmaterials\tcomponents\tfastener\texact_fulltype\t100\t\t\r\n",
	"classified row keeps empty body location")
assertEqual(writes[3], "Base.Wound_Test\texcluded_internal\tother\tunclassified_modded\t\tfallback\t0\tbody_location_wound\tbase:wound\r\n",
	"excluded row keeps structural reason")

print("native_audit_census_regression: OK")

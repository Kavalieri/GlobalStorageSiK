-- Product adapter contract: declared warehouse capacity becomes a visible,
-- localized progress presentation with stable numeric data.
local client = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"
GlobalStorageSiK = { I18n = { text = function(key, ...)
	local args = { ... }
	if key == "IGUI_GS_CapacityUsage" then return args[1] .. "/" .. args[2] .. " (" .. args[3] .. ")" end
	if key == "IGUI_GS_CapacityItemCount" then return "Items: " .. args[1] end
	if key == "IGUI_GS_PunctuationMiddleDot" then return "·" end
	return key
end } }
package.preload["GS_I18n"] = function() return true end
local presentation = dofile(client .. "GlobalStorageSiK/UI/CapacityPresentation.lua")
local result = presentation.fromState({ usedWeight = 12, effectiveCapacity = 40, itemCount = 7 })
assert(result.value == 0.3 and result.percent == 30, "capacity progress value is not derived from the declaration")
assert(result.label:find("12/40", 1, true) and result.label:find("Items: 7", 1, true),
	"capacity label omitted declared usage or item count")
assert(result.label ~= "" and result.text == result.label, "progress control has no visible stable label")
print("PASS warehouse capacity progress contract")

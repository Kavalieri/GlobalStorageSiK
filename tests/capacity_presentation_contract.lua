local CLIENT = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/"

local previousGlobalStorageSiK = GlobalStorageSiK
local previousI18nPreload = package.preload["GS_I18n"]
package.preload["GS_I18n"] = function() return true end
GlobalStorageSiK = {
	UI = {},
	I18n = {
		text = function(key, ...)
			local values = { ... }
			if key == "IGUI_GS_PunctuationMiddleDot" then return "|" end
			if key == "IGUI_GS_CapacityUsage" then
				return values[1] .. " / " .. values[2] .. " kg | " .. values[3]
			end
			if key == "IGUI_GS_CapacityItemCount" then return values[1] .. " objects" end
			if key == "IGUI_GS_WeightPersonalBonus" then
				return "(+" .. values[1] .. " kg extra)"
			end
			return key
		end,
	},
}

local CapacityPresentation = dofile(CLIENT .. "GlobalStorageSiK/UI/CapacityPresentation.lua")
local presentation = CapacityPresentation.fromState({
	usedWeight = 40.8,
	totalCapacity = 50,
	effectiveCapacity = 60,
	percent = 68,
	status = "ok",
	personalBonus = 10,
}, { count = 4 })

assert(presentation.value == 0.68 and presentation.effectiveCapacity == 60,
	"capacity presentation must use the trait-aware effective capacity")
assert(string.find(presentation.label, "4 objects", 1, true),
	"capacity presentation must include the item count")
assert(string.find(presentation.label, "40.8 / 60 kg | 68%", 1, true),
	"capacity presentation must include used, effective total and occupancy")
assert(string.find(presentation.label, "(+10 kg extra)", 1, true),
	"capacity presentation must preserve the detected personal trait bonus")

GlobalStorageSiK = previousGlobalStorageSiK
package.preload["GS_I18n"] = previousI18nPreload
print("capacity_presentation_contract: OK")

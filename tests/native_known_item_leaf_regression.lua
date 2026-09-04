-- Known native items rejected by Systems must resolve to exact SiK L1/L2/L3.
package.loaded["GS_NativeClassifierApi"] = true
package.loaded["GS_NativeClassifierUtils"] = true

local classifiers = {}
GlobalStorageSiK = {
	NativeClassifier = {
		registerBlock = function(fn, name) classifiers[name] = fn end,
	},
}
ResourceLocation = { of = function(key) return key end }
ItemTag = { get = function(key) return key end }

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeClassifierUtils.lua")
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeClassifierCombat.lua")
dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_NativeClassifierMedicine.lua")

local cases = {
	{ "combat", "Base.Matches", "combat", "explosive", "incendiary", "exact_fulltype_incendiary" },
	{ "medicine", "Base.ComfreyCataplasm", "medicine", "treatment", "wound_dressing", "exact_fulltype_medicine" },
}
for i = 1, #cases do
	local case = cases[i]
	local path, _, _, evidence = classifiers[case[1]](case[2], nil)
	assert(path and path.l1 == case[3] and path.l2 == case[4] and path.l3 == case[5], case[2] .. " leaf")
	assert(evidence and evidence.primary and evidence.primary.source == case[6], case[2] .. " evidence")
	assert(evidence.primary.confidence == 100, case[2] .. " confidence")
end

print("native_known_item_leaf_regression: OK")

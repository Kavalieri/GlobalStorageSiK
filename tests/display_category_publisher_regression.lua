-- Regression test for Core 1.4.3-dev32.3 DisplayCategory publication.
-- Run from GlobalStorageSiK-Repo: lua51.exe tests/display_category_publisher_regression.lua

package.loaded["GS_CatalogManager"] = true
package.loaded["GS_I18n"] = true
package.loaded["GS_NativeProduct"] = true

local bootHandler = nil
Events = { OnGameBoot = { Add = function(fn) bootHandler = fn end } }

local epochBumps = 0
GlobalStorageSiK = {
	CatalogManager = { forceNewEpoch = function() epochBumps = epochBumps + 1 end },
	NativeProduct = {
		decodePath = function(path) return type(path) == "table" and path or nil end,
		normalizePath = function(path) return type(path) == "table" and path or nil end,
	},
	NativeClassifier = {
		classify = function(fullType)
			if fullType == "Base.Nails" then
				return { primaryPath = { l1 = "materials", l2 = "component", l3 = "fastener" } }
			end
			if fullType == "Base.Bullets9mm" then
				return { primaryPath = { l1 = "combat", l2 = "firearm", l3 = "ammunition" } }
			end
			return { primaryPath = { l1 = "other", l2 = "unclassified_modded" } }
		end,
	},
	Log = { info = function() end, warn = function() end },
}

local function scriptItem(fullType, category)
	return {
		fullType = fullType,
		category = category,
		getFullName = function(self) return self.fullType end,
		getDisplayCategory = function(self) return self.category end,
		DoParam = function(self, key, value)
			assert(key == "DisplayCategory", "only DisplayCategory may be published")
			self.category = value
		end,
	}
end

local nails = scriptItem("Base.Nails", "Misc")
local bullets = scriptItem("Base.Bullets9mm", "Ammo")
local unknown = scriptItem("Mod.Unknown", "Tool")
local items = { nails, bullets, unknown }
ScriptManager = { instance = {
	getAllItems = function()
		return {
			size = function() return #items end,
			get = function(_, index) return items[index + 1] end,
		}
	end,
} }
getActivatedMods = function()
	return { size = function() return 0 end, get = function() return nil end }
end

dofile("GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_DisplayCategoryPublisher.lua")
assert(bootHandler, "publisher must register OnGameBoot")
bootHandler()

assert(nails.category == "GSSiK_materials_component_fastener", "classified item must publish stable key")
assert(bullets.category == "Ammo", "ammo compatibility exception must retain vanilla key")
assert(unknown.category == "Tool", "unclassified item must retain author category")
assert(epochBumps == 1, "a changed publication must invalidate ScriptItem caches once")
assert(GlobalStorageSiK.DisplayCategoryPublisher.isPublishedKey(nails.category), "published key detection")
assert(not GlobalStorageSiK.DisplayCategoryPublisher.isPublishedKey("Tool"), "vanilla key is not published")

BScats = {}
nails.category = "Misc"
bootHandler()
assert(nails.category == "Misc", "external writer conflict must prevent publication")
assert(GlobalStorageSiK.DisplayCategoryPublisher.getStatus().status == "conflict", "conflict must be declared")

print("display_category_publisher_regression: OK")

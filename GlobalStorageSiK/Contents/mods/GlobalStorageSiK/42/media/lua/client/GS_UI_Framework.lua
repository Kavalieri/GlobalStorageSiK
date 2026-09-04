-- Global Storage SiK - required public SiK UI Framework binding.
--
-- This module is intentionally strict: Global Storage has no embedded UI
-- fallback.  If the declared SiKUIFramework dependency is absent or broken,
-- loading stops here with an actionable error instead of silently rendering a
-- second, divergent interface.

local loaded = pcall(require, "SiK_UI")
if not loaded then
	error("Global Storage SiK requires the SiKUIFramework mod (SiK.UI unavailable)")
end

if type(SiK) ~= "table" or type(SiK.UI) ~= "table" then
	error("Global Storage SiK requires the SiKUIFramework mod (SiK.UI unavailable)")
end

-- Product adapter only: SiK.UI owns tree/mount/layout diagnostics. Global
-- Storage contributes its opt-in policy and logger without teaching the
-- framework about GS sandbox keys, namespaces or output formats.
if SiK.UI.Diagnostics and SiK.UI.Diagnostics.registerSink then
	SiK.UI.Diagnostics.registerSink("GlobalStorageSiK", {
		enabled = function()
			return GlobalStorageSiK and GlobalStorageSiK.Sandbox
				and GlobalStorageSiK.Sandbox.debugMode
				and GlobalStorageSiK.Sandbox.debugMode() == true
				and GlobalStorageSiK.Sandbox.debugCategoryEnabled
				and GlobalStorageSiK.Sandbox.debugCategoryEnabled("SiKUI") == true
		end,
		sink = function(event)
			if GlobalStorageSiK and GlobalStorageSiK.Log and GlobalStorageSiK.Log.debug then
				GlobalStorageSiK.Log.debug("SiKUI",
					"framework " .. tostring(event.kind), tostring(event.message))
			end
		end,
	})
end

return SiK.UI

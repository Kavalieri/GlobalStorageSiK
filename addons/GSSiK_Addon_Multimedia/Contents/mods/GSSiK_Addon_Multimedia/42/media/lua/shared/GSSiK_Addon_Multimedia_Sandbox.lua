GSSiK_Addon_Multimedia = GSSiK_Addon_Multimedia or {}
local M = GSSiK_Addon_Multimedia
M.VERSION = "0.1.0-dev1"
M.Sandbox = M.Sandbox or {}
local defaults = { LootPeripheralWeight = 0.08, LootMagazineWeight = 0.35,
	LootDiskProgramMagazineWeight = 0.3, LootComponentWeight = 0.2, LootInstallDiskWeight = 0.15 }
function M.Sandbox.loot(key)
	local vars = SandboxVars and SandboxVars.GSSiK_Addon_Multimedia
	local value = vars and tonumber(vars[key])
	if not value or value ~= value then return defaults[key] or 0 end
	return math.max(0, math.min(5, value))
end
function M.Sandbox.debug(category)
	local vars = SandboxVars and SandboxVars.GSSiK_Addon_Multimedia
	return vars and vars.DebugMode == true
		and (category == "Registration" or category == "Playback")
		and vars["Debug" .. category] == true
end
return M.Sandbox

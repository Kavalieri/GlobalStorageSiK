--[[
	GlobalStorageSiK - Carga segura de librerías externas
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Detección de integraciones funcionales de crafteo, construcción y cocina.
]]

GlobalStorageSiK.Libs = GlobalStorageSiK.Libs or {}

--- Trunca texto mediante el proveedor propio.
---@param text string
---@param maxWidth number
---@param font UIFont|nil
---@param suffix string|nil
---@return string
function GlobalStorageSiK.Libs.truncateText(text, maxWidth, font, suffix)
	font = font or UIFont.Small
	suffix = suffix or ".."
	maxWidth = math.floor(tonumber(maxWidth) or 0)
	if maxWidth <= 0 or not text or text == "" then
		return ""
	end
	local tm = getTextManager()
	if tm:MeasureStringX(font, text) <= maxWidth then
		return text
	end
	local suffixW = tm:MeasureStringX(font, suffix)
	if suffixW >= maxWidth then
		return suffix
	end
	local budget = maxWidth - suffixW
	local left, right, best = 1, #text, 0
	while left <= right do
		local mid = math.floor((left + right) / 2)
		local part = string.sub(text, 1, mid)
		if tm:MeasureStringX(font, part) <= budget then
			best = mid
			left = mid + 1
		else
			right = mid - 1
		end
	end
	if best == 0 then
		return suffix
	end
	return string.sub(text, 1, best) .. suffix
end

--- Indica si Neat Crafting está activo en la partida.
---@return boolean
function GlobalStorageSiK.Libs.hasNeatCrafting()
	if GlobalStorageSiK.Libs._neatCrafting ~= nil then
		return GlobalStorageSiK.Libs._neatCrafting
	end
	local active = false
	if getActivatedMods and getActivatedMods():contains("Neat_Crafting") then
		active = true
	end
	GlobalStorageSiK.Libs._neatCrafting = active
	return active
end

--- Indica si Neat Building está activo en la partida.
---@return boolean
function GlobalStorageSiK.Libs.hasNeatBuilding()
	if GlobalStorageSiK.Libs._neatBuilding ~= nil then
		return GlobalStorageSiK.Libs._neatBuilding
	end
	local active = false
	if getActivatedMods and getActivatedMods():contains("Neat_Building") then
		active = true
	end
	GlobalStorageSiK.Libs._neatBuilding = active
	return active
end

--- Indica si Project Cook (mod de cocina de terceros, addon opcional
--- consumido por GSSiK_Addon_Craft) está activo en la partida.
---@return boolean
function GlobalStorageSiK.Libs.hasProjectCook()
	if GlobalStorageSiK.Libs._projectCook ~= nil then
		return GlobalStorageSiK.Libs._projectCook
	end
	local active = false
	if getActivatedMods and getActivatedMods():contains("Project_Cook") then
		active = true
	end
	GlobalStorageSiK.Libs._projectCook = active
	return active
end

--- Resuelve apertura de crafteo según mods Neat instalados.
---@param mode string|nil "auto"|"vanilla"|"neat"
---@return function|nil
function GlobalStorageSiK.Libs.resolveHandcraftOpener(mode)
	mode = mode or "auto"
	if not ISEntityUI then
		return nil
	end
	if mode == "vanilla" and ISEntityUI._NC_old_OpenHandcraftWindow then
		return ISEntityUI._NC_old_OpenHandcraftWindow
	end
	if mode == "neat" and ISEntityUI._NC_new_OpenHandcraftWindow then
		return ISEntityUI._NC_new_OpenHandcraftWindow
	end
	if mode == "auto" and GlobalStorageSiK.Libs.hasNeatCrafting() and ISEntityUI._NC_new_OpenHandcraftWindow then
		return ISEntityUI._NC_new_OpenHandcraftWindow
	end
	return ISEntityUI.OpenHandcraftWindow
end

--- Resuelve apertura de construcción según mods Neat instalados.
---@param mode string|nil "auto"|"vanilla"|"neat"
---@return function|nil
function GlobalStorageSiK.Libs.resolveBuildOpener(mode)
	mode = mode or "auto"
	if not ISEntityUI or not ISEntityUI.OpenBuildWindow then
		return nil
	end
	if mode == "vanilla" and ISEntityUI._NB_old_OpenBuildWindow then
		return ISEntityUI._NB_old_OpenBuildWindow
	end
	if mode == "neat" or mode == "auto" then
		if GlobalStorageSiK.Libs.hasNeatBuilding() then
			return ISEntityUI.OpenBuildWindow
		end
	end
	return ISEntityUI._NB_old_OpenBuildWindow or ISEntityUI.OpenBuildWindow
end

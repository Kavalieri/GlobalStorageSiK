--[[
	GlobalStorageSiK - Carga segura de librerías externas
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: NeatUI_Framework como dependencia oficial (widgets, NeatTool, scroll).
]]

GlobalStorageSiK.Libs = GlobalStorageSiK.Libs or {}

--- Carga módulos NeatUI_Framework (patrón Neat_Rocco: require explícito).
---@return boolean
function GlobalStorageSiK.Libs.loadNeatUIModules()
	if GlobalStorageSiK.Libs._modulesLoaded ~= nil then
		return GlobalStorageSiK.Libs._modulesLoaded
	end
	pcall(require, "neatui_framework/compat/nui_isuielement_compat")
	pcall(require, "neatui_framework/ui/ni_squarebutton")
	pcall(require, "neatui_framework/scrollview/niscrollview")
	pcall(require, "neatui_framework/scrollview/nivirtualscrollview")
	pcall(require, "neatui_framework/scrollview/nigridvirtualscrollview")
	pcall(require, "neatui_framework/neattool/neattool_truncatetext")
	pcall(require, "neatui_framework/neattool/neattool_3patch")
	pcall(require, "neatui_framework/neattool/neattool_textrender")
	GlobalStorageSiK.Libs._modulesLoaded = NI_SquareButton ~= nil
	return GlobalStorageSiK.Libs._modulesLoaded
end

--- Indica si NeatUI está disponible.
---@return boolean
function GlobalStorageSiK.Libs.hasNeatUI()
	if GlobalStorageSiK.Libs._neatUI ~= nil then
		return GlobalStorageSiK.Libs._neatUI
	end
	GlobalStorageSiK.Libs._neatUI = GlobalStorageSiK.Libs.loadNeatUIModules()
	return GlobalStorageSiK.Libs._neatUI
end

--- Comprueba dependencias NeatUI usadas por el terminal (estilo NC_CheckNeatUIDependency).
---@return boolean
function GlobalStorageSiK.Libs.hasNeatUIComplete()
	if GlobalStorageSiK.Libs._neatUIComplete ~= nil then
		return GlobalStorageSiK.Libs._neatUIComplete
	end
	if not GlobalStorageSiK.Libs.hasNeatUI() then
		GlobalStorageSiK.Libs._neatUIComplete = false
		return false
	end
	local ok = NinePatchTexture ~= nil
		and NinePatchTexture.getSharedTexture ~= nil
		and GlobalStorageSiK.Libs.getNeatTool() ~= nil
	GlobalStorageSiK.Libs._neatUIComplete = ok == true
	return GlobalStorageSiK.Libs._neatUIComplete
end

--- Carga NeatTool (truncate, three-patch, etc.) si existe.
---@return table|nil
function GlobalStorageSiK.Libs.getNeatTool()
	if GlobalStorageSiK.Libs._neatTool ~= nil then
		local cached = GlobalStorageSiK.Libs._neatTool
		return cached ~= false and cached or nil
	end
	GlobalStorageSiK.Libs.loadNeatUIModules()
	if NeatTool and NeatTool.ThreePatch then
		GlobalStorageSiK.Libs._neatTool = NeatTool
	else
		GlobalStorageSiK.Libs._neatTool = false
	end
	return GlobalStorageSiK.Libs._neatTool or nil
end

--- Trunca texto (NeatTool.truncateText del framework; fallback local).
---@param text string
---@param maxWidth number
---@param font UIFont|nil
---@param suffix string|nil
---@return string
function GlobalStorageSiK.Libs.truncateText(text, maxWidth, font, suffix)
	font = font or UIFont.Small
	suffix = suffix or ".."
	local tool = GlobalStorageSiK.Libs.getNeatTool()
	if tool and tool.truncateText then
		return tool.truncateText(text, maxWidth, font, suffix)
	end
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

--- Renderiza dígitos con atlas NeatUI (NeatTool.renderText).
---@param panel ISUIElement
---@param text string
---@param x number
---@param y number
---@param size number|nil
---@param alpha number|nil
---@param r number|nil
---@param g number|nil
---@param b number|nil
---@param useOutline boolean|nil
---@return number width
function GlobalStorageSiK.Libs.renderNeatDigits(panel, text, x, y, size, alpha, r, g, b, useOutline)
	local tool = GlobalStorageSiK.Libs.getNeatTool()
	if tool and tool.renderText and panel then
		return tool.renderText(panel, text, x, y, size or 1, alpha or 1, r or 1, g or 1, b or 1, useOutline == true)
	end
	if panel and panel.drawText then
		panel:drawText(text, x, y, r or 1, g or 1, b or 1, alpha or 1, UIFont.Small)
		return getTextManager():MeasureStringX(UIFont.Small, text)
	end
	return 0
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

--- Devuelve clase NI_SquareButton si NeatUI está cargado.
---@return table|nil
function GlobalStorageSiK.Libs.getNISquareButton()
	if not GlobalStorageSiK.Libs.hasNeatUI() then
		return nil
	end
	return NI_SquareButton
end

--- Devuelve clase NIScrollView si NeatUI está cargado.
---@return table|nil
function GlobalStorageSiK.Libs.getNIScrollView()
	if not GlobalStorageSiK.Libs.hasNeatUI() then
		return nil
	end
	return NIScrollView
end

--- Devuelve clase NIVirtualScrollView si NeatUI está cargado.
---@return table|nil
function GlobalStorageSiK.Libs.getNIVirtualScrollView()
	if not GlobalStorageSiK.Libs.hasNeatUI() then
		return nil
	end
	return NIVirtualScrollView
end

--- Devuelve clase NIGridVirtualScrollView si NeatUI está cargado.
---@return table|nil
function GlobalStorageSiK.Libs.getNIGridVirtualScrollView()
	if not GlobalStorageSiK.Libs.hasNeatUI() then
		return nil
	end
	return NIGridVirtualScrollView
end

-- Global Storage local visual preferences. The visual tokens belong to SiK.UI;
-- this module owns only the product preference keys and their selector lifecycle.

require "GS_I18n"

local UI = require "GS_UI_Framework"

GlobalStorageSiK.UIPalette = GlobalStorageSiK.UIPalette or {}
GlobalStorageSiK.UIOpacity = GlobalStorageSiK.UIOpacity or {}

local Palette = GlobalStorageSiK.UIPalette
local Opacity = GlobalStorageSiK.UIOpacity
local PREF_KEY = "GSSiK_UIPalette"
local OPACITY_PREF_KEY = "GSSiK_UIOpacity"
local activeByPlayer = {}

local function rgb(hex, alpha)
	return { hex[1] / 255, hex[2] / 255, hex[3] / 255, alpha or 1 }
end

local function palette(window, panel, panelAlt, header, row, rowAlt, border, strong)
	return {
		background = rgb(window, 0.98), header = rgb(header),
		surface = rgb(panel, 0.96), surfaceAlt = rgb(panelAlt, 0.96),
		border = rgb(border, 0.90), divider = rgb(rowAlt, 0.80),
		hover = rgb(strong, 0.72), pressed = rgb(row, 0.96),
		selected = rgb(strong, 0.50),
		tableHeader = rgb(window), tableRow = rgb(row),
		tableRowAlt = rgb(rowAlt), tableRowHover = rgb(strong),
		tableRowGroup = rgb(panel), tableRowChild = rgb(window),
		tableRowDivider = rgb(border, 0.58),
	}
end

-- These are the six approved HTML palettes, copied as exact RGB values rather
-- than generated tints. Product preference selects a framework theme; it does
-- not invent an alternative visual system for runtime.
Palette.DEFINITIONS = {
	{ key = "graphite", titleKey = "IGUI_GS_UIPaletteGraphite", colors = palette(
		{ 16, 16, 16 }, { 19, 19, 19 }, { 23, 23, 23 }, { 25, 25, 25 },
		{ 15, 15, 15 }, { 18, 18, 18 }, { 48, 48, 48 }, { 68, 68, 68 }) },
	{ key = "blue", titleKey = "IGUI_GS_UIPaletteBlue", colors = palette(
		{ 13, 17, 20 }, { 17, 23, 27 }, { 21, 29, 34 }, { 23, 29, 33 },
		{ 14, 20, 24 }, { 17, 25, 30 }, { 48, 64, 74 }, { 70, 92, 105 }) },
	{ key = "purple", titleKey = "IGUI_GS_UIPalettePurple", colors = palette(
		{ 17, 14, 19 }, { 23, 18, 25 }, { 29, 23, 31 }, { 29, 24, 31 },
		{ 20, 15, 22 }, { 24, 18, 26 }, { 67, 53, 72 }, { 94, 74, 101 }) },
	{ key = "green", titleKey = "IGUI_GS_UIPaletteGreen", colors = palette(
		{ 13, 18, 15 }, { 17, 24, 19 }, { 22, 30, 25 }, { 23, 29, 25 },
		{ 14, 21, 17 }, { 17, 26, 21 }, { 51, 72, 58 }, { 73, 101, 82 }) },
	{ key = "wine", titleKey = "IGUI_GS_UIPaletteWine", colors = palette(
		{ 19, 14, 14 }, { 26, 18, 18 }, { 33, 23, 23 }, { 32, 24, 24 },
		{ 23, 15, 15 }, { 28, 18, 18 }, { 74, 52, 52 }, { 104, 73, 73 }) },
	{ key = "amber", titleKey = "IGUI_GS_UIPaletteAmber", colors = palette(
		{ 19, 18, 13 }, { 26, 24, 17 }, { 33, 30, 22 }, { 32, 30, 23 },
		{ 23, 21, 14 }, { 28, 25, 17 }, { 74, 68, 50 }, { 104, 95, 70 }) },
}

local function definitionByKey(key)
	for index = 1, #Palette.DEFINITIONS do
		if Palette.DEFINITIONS[index].key == key then
			return Palette.DEFINITIONS[index], index
		end
	end
	return Palette.DEFINITIONS[1], 1
end

local function copyColor(source)
	return {
		r = source[1],
		g = source[2],
		b = source[3],
		a = source[4] or 1,
	}
end

function Palette.getActiveKey(playerNum)
	return activeByPlayer[playerNum or 0] or "graphite"
end

function Palette.previewSwatches(key)
	local definition = definitionByKey(key)
	return {
		copyColor(definition.colors.background),
		copyColor(definition.colors.surface),
		copyColor(definition.colors.surfaceAlt),
		copyColor(definition.colors.border),
	}
end

function Palette.apply(key, playerNum)
	playerNum = playerNum or 0
	local definition = definitionByKey(key)
	local overrides = {}
	for name, source in pairs(definition.colors) do
		overrides[name] = copyColor(source)
	end
	UI.Theme.set(overrides, playerNum)
	activeByPlayer[playerNum] = definition.key
	return definition.key
end

function Palette.load(player)
	local key = "graphite"
	if player and player.getModData then
		local modData = player:getModData()
		key = type(modData[PREF_KEY]) == "string" and modData[PREF_KEY] or key
	end
	return Palette.apply(key, player and player.getPlayerNum and player:getPlayerNum() or 0)
end

function Palette.save(player, key)
	key = Palette.apply(key, player and player.getPlayerNum and player:getPlayerNum() or 0)
	if player and player.getModData then
		-- Local visual preference: deliberately not transmitted.
		player:getModData()[PREF_KEY] = key
	end
	return key
end

Opacity.MIN = 45
Opacity.MAX = 100

local function playerNum(player)
	return player and player.getPlayerNum and player:getPlayerNum() or 0
end

local function normalizeOpacity(value)
	value = tonumber(value)
	if not value or value ~= value then return nil end
	value = math.floor(value + 0.5)
	if value < Opacity.MIN or value > Opacity.MAX then return nil end
	return value
end

function Opacity.get(player)
	return UI.Theme.getOpacity(playerNum(player))
end

function Opacity.load(player)
	local value
	if player and player.getModData then
		value = normalizeOpacity(player:getModData()[OPACITY_PREF_KEY])
	end
	if value then
		UI.Theme.setOpacity(value, playerNum(player))
	else
		UI.Theme.clearOpacity(playerNum(player))
	end
	return UI.Theme.getOpacity(playerNum(player))
end

function Opacity.save(player, value)
	value = normalizeOpacity(value)
	if not value then return nil, "invalid_opacity" end
	UI.Theme.setOpacity(value, playerNum(player))
	if player and player.getModData then
		-- Local visual preference: deliberately not transmitted.
		player:getModData()[OPACITY_PREF_KEY] = value
	end
	return value
end

return Palette

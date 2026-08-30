--[[
	GlobalStorageSiK - Responsive addon bay inside the Addons tab.
	Slots use the shared Controls button instead of a private painted grid.
]]

require "ISUI/ISPanel"
require "GS_I18n"
require "GS_AddonRegistry"
require "GS_TerminalUI_Scroll"
require "GS_AddonManageUI"
require "GS_SiK_UI_Controls"

GlobalStorageSiK.TerminalAddonBay = GlobalStorageSiK.TerminalAddonBay or {}

local T = GlobalStorageSiK.I18n.text
local METRICS = GlobalStorageSiK.SiK_UI.Controls.metrics("standard")
local SLOT_GAP = METRICS.controlGap
local SLOT_MIN_W = 140

local function addonSlotLabel(def)
	if def.itemType and def.itemType ~= "" and GlobalStorageSiK.I18n.typeDisplayName then
		local name = GlobalStorageSiK.I18n.typeDisplayName(def.itemType)
		if name and name ~= "" then return name end
	end
	return T(def.titleKey or "IGUI_GS_AddonUnknown")
end

local function slotTooltip(def, installed)
	if not GlobalStorageSiK.AddonRegistry.isModActive(def.id) then
		return T("IGUI_GS_AddonStatusModOff")
	end
	if installed then return T("IGUI_GS_AddonStatusInstalled") end
	return T("IGUI_GS_AddonStatusReady")
end

local function slotText(def, installed)
	local status
	if not GlobalStorageSiK.AddonRegistry.isModActive(def.id) then
		status = T("IGUI_GS_AddonStatusMissingMod")
	elseif installed then
		status = T("IGUI_GS_AddonStatusInstalled")
	else
		status = T("IGUI_GS_AddonNotInstalledHereMsg")
	end
	return addonSlotLabel(def) .. " · " .. status
end

local function gridMetrics(count, width)
	if count <= 0 then return 0, 0, 0 end
	local columns = math.max(1, math.floor((width + SLOT_GAP) /
		(SLOT_MIN_W + SLOT_GAP)))
	columns = math.min(count, columns)
	local buttonW = math.max(72,
		math.floor((width - (columns - 1) * SLOT_GAP) / columns))
	local rows = math.ceil(count / columns)
	return columns, rows, buttonW
end

function GlobalStorageSiK.TerminalAddonBay.layout(host, width)
	if not host then return 0 end
	width = math.max(72, tonumber(width) or host.width or 72)
	local buttons = host.slotButtons or {}
	local columns, rows, buttonW = gridMetrics(#buttons, width)
	for i = 1, #buttons do
		local column = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		local button = buttons[i]
		button:setX(column * (buttonW + SLOT_GAP))
		button:setY(row * (METRICS.buttonHeight + SLOT_GAP))
		button:setWidth(buttonW)
		button:setHeight(METRICS.buttonHeight)
	end
	local height = rows * METRICS.buttonHeight + math.max(0, rows - 1) * SLOT_GAP
	host:setWidth(width)
	host:setHeight(height)
	return height
end

local function openAddon(def, ctx)
	if not def or not GlobalStorageSiK.AddonRegistry.isModActive(def.id) then return end
	GlobalStorageSiK.AddonManageUI.show(def.id, ctx.networkId, ctx.anchor,
		ctx.terminal, ctx.installed)
end

function GlobalStorageSiK.TerminalAddonBay.addBay(scroll, x, y, innerW, defs, ctx)
	local count = #defs
	if count <= 0 then return y end
	local width = math.max(72, innerW - x * 2)
	local host = ISPanel:new(x, y, width, METRICS.buttonHeight)
	host:initialise()
	host.drawBackground = false
	host.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	host._sikAddonBay = true
	host.slotButtons = {}

	for i = 1, count do
		local def = defs[i]
		local slotDef = def
		local installed = ctx.installed and ctx.installed[def.id] ~= nil
		local active = GlobalStorageSiK.AddonRegistry.isModActive(def.id)
		local button = GlobalStorageSiK.SiK_UI.Controls.button(host, {
			x = 0, y = 0, w = SLOT_MIN_W, h = METRICS.buttonHeight,
			text = slotText(def, installed), fullWidth = true,
			locked = not active,
			activeColor = installed and GlobalStorageSiK.SiK_UI.PALETTE.statusOk or nil,
			tooltip = slotTooltip(def, installed),
			onClick = function() openAddon(slotDef, ctx) end,
		})
		host.slotButtons[#host.slotButtons + 1] = button
	end

	local height = GlobalStorageSiK.TerminalAddonBay.layout(host, width)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, host)
	return y + height + SLOT_GAP
end

function GlobalStorageSiK.TerminalAddonBay.measureHeight(defCount)
	if defCount <= 0 then return 0 end
	return METRICS.buttonHeight
end

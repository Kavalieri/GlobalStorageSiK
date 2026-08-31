--[[
	GlobalStorageSiK - Responsive addon bay inside the Addons tab.
	Slots use the shared data-driven Controls addon component.
]]

require "ISUI/ISPanel"
require "GS_I18n"
require "GS_AddonRegistry"
require "GS_TerminalUI_Scroll"
require "GS_AddonManageUI"
require "GS_SiK_UI_Controls"

GlobalStorageSiK.TerminalAddonBay = GlobalStorageSiK.TerminalAddonBay or {}

local T = GlobalStorageSiK.I18n.text
local Controls = GlobalStorageSiK.SiK_UI.Controls
local METRICS = Controls.metrics("standard")
local SLOT_METRICS = Controls.addonSlotMetrics()
local SLOT_GAP = METRICS.controlGap
local SLOT_MIN_W = SLOT_METRICS.minWidth
local SLOT_H = SLOT_METRICS.minHeight

local function addonSlotLabel(def, installed)
	local itemType = installed and installed.itemType or def.itemType
	if itemType and itemType ~= "" and GlobalStorageSiK.I18n.typeDisplayName then
		local name = GlobalStorageSiK.I18n.typeDisplayName(itemType)
		if name and name ~= "" then return name end
	end
	return T(def.titleKey or "IGUI_GS_AddonUnknown")
end

local function slotTexture(def, installed)
	local itemType = installed and installed.itemType or def.itemType
	if itemType and GlobalStorageSiK.CraftUtils
			and GlobalStorageSiK.CraftUtils.getItemIconTexture then
		local texture = GlobalStorageSiK.CraftUtils.getItemIconTexture(itemType)
		if texture then return texture end
	end
	if def.iconPath and getTexture then return getTexture(def.iconPath) end
	return nil
end

local function slotTooltip(def, installed)
	if not GlobalStorageSiK.AddonRegistry.isModActive(def.id) then
		return T("IGUI_GS_AddonStatusModOff")
	end
	if installed then return T("IGUI_GS_AddonStatusInstalled") end
	return T("IGUI_GS_AddonStatusReady")
end

local function slotStatus(def, installed)
	if not GlobalStorageSiK.AddonRegistry.isModActive(def.id) then
		return T("IGUI_GS_AddonStatusMissingMod"), "missing"
	elseif installed then
		return T("IGUI_GS_AddonStatusInstalled"), "installed"
	end
	return T("IGUI_GS_AddonNotInstalledHereMsg"), "notInstalled"
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
	local slots = host.addonSlots or {}
	local columns, rows, slotW = gridMetrics(#slots, width)
	for i = 1, #slots do
		local column = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		local slot = slots[i]
		slot:setX(column * (slotW + SLOT_GAP))
		slot:setY(row * (SLOT_H + SLOT_GAP))
		slot:setWidth(slotW)
		slot:setHeight(SLOT_H)
	end
	local height = rows * SLOT_H + math.max(0, rows - 1) * SLOT_GAP
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
	local host = ISPanel:new(x, y, width, SLOT_H)
	host:initialise()
	host.drawBackground = false
	host.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	host._sikAddonBay = true
	host.addonSlots = {}

	for i = 1, count do
		local def = defs[i]
		local slotDef = def
		local installed = ctx.installed and ctx.installed[def.id] or nil
		local active = GlobalStorageSiK.AddonRegistry.isModActive(def.id)
		local stateLabel, state = slotStatus(def, installed)
		local nameLabel = addonSlotLabel(def, installed)
		local slot = Controls.addonSlot(host, {
			x = 0, y = 0, w = SLOT_MIN_W, h = SLOT_H,
			texture = slotTexture(def, installed),
			nameLabel = nameLabel, stateLabel = stateLabel, state = state,
			locked = not active,
			activeColor = installed and GlobalStorageSiK.SiK_UI.PALETTE.statusOk
				or nil,
			tooltip = slotTooltip(def, installed ~= nil),
			onClick = function() openAddon(slotDef, ctx) end,
		})
		-- Consumer-visible markers keep HTML -> Lua parity machine-checkable.
		slot._sikAddonSlot = true
		slot.texture = slot:getTexture()
		slot.nameLabel = nameLabel
		slot.stateLabel = stateLabel
		host.addonSlots[#host.addonSlots + 1] = slot
	end

	local height = GlobalStorageSiK.TerminalAddonBay.layout(host, width)
	GlobalStorageSiK.TerminalScroll.addChild(scroll, host)
	return y + height + SLOT_GAP
end

function GlobalStorageSiK.TerminalAddonBay.measureHeight(defCount)
	if defCount <= 0 then return 0 end
	return SLOT_H
end

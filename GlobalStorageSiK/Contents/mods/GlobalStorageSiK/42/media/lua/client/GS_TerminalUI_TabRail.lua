--[[
	GlobalStorageSiK - Columna de pestañas estilo Neat Crafting / Neat Building
	Autor: SiK
	Fecha: 2025-06-27
]]

require "ISUI/ISPanel"
require "ISUI/ISUIElement"
require "GS_I18n"
require "GS_Libs"

GlobalStorageSiK.TerminalTabRail = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

--- Slot de pestaña (icono + estado activo, patrón NC_CategoryList_Slot).
GS_TerminalTabSlot = ISUIElement:derive("GS_TerminalTabSlot")

function GS_TerminalTabSlot:initialise()
	ISUIElement.initialise(self)
end

---@param x number
---@param y number
---@param size number
---@param displayName string
---@param tabKey string
---@param iconPath string|nil
---@param parentRail GS_TerminalTabRail
---@return GS_TerminalTabSlot
function GS_TerminalTabSlot:new(x, y, size, displayName, tabKey, iconPath, parentRail)
	local o = ISUIElement:new(x, y, size, size)
	setmetatable(o, self)
	self.__index = self
	o.displayName = displayName
	o.tabKey = tabKey
	o.parentRail = parentRail
	o.isSelected = false
	o.iconSize = math.floor(size * 0.72)
	o.tabIcon = iconPath and getTexture(iconPath) or nil
	o.defaultBG = getTexture("media/ui/CategoryIcon/Deflaut.png")
	o.neatBtn = nil
	return o
end

function GS_TerminalTabSlot:initialise()
	ISUIElement.initialise(self)
	local NISq = GlobalStorageSiK.Libs.getNISquareButton()
	if not NISq then
		return
	end
	local tabKey = self.tabKey
	local rail = self.parentRail
	local slot = self
	self.neatBtn = NISq:new(0, 0, self.width, self.tabIcon, rail, function()
		if slot.isSelected then
			return
		end
		if getSoundManager and getSoundManager().playUISound then
			getSoundManager():playUISound("UIActivateButton")
		end
		if rail and rail.onTabActivated then
			rail:onTabActivated(tabKey)
		end
	end)
	self.neatBtn:initialise()
	self.neatBtn:setActive(false)
	self.neatBtn:setActiveColor(0.95, 0.5, 0.1)
	self:addChild(self.neatBtn)
end

function GS_TerminalTabSlot:setSelected(selected)
	self.isSelected = selected == true
	if self.neatBtn and self.neatBtn.setActive then
		self.neatBtn:setActive(self.isSelected)
	end
end

function GS_TerminalTabSlot:prerender()
end

function GS_TerminalTabSlot:render()
	if self.neatBtn then
		return
	end
	local inset = 3
	local btnW = self.width - inset * 2
	local btnH = self.height - inset * 2
	local btnX = inset
	local btnY = inset
	local bgA, bgR, bgG, bgB = 0.96, 0.05, 0.05, 0.05
	if self.isSelected then
		bgR, bgG, bgB = 0.12, 0.1, 0.08
	elseif self:isMouseOver() then
		bgR, bgG, bgB = 0.1, 0.1, 0.1
	end
	self:drawRect(btnX, btnY, btnW, btnH, bgA, bgR, bgG, bgB)
	if self.isSelected then
		self:drawRectBorder(btnX, btnY, btnW, btnH, 0.9, 0.95, 0.55, 0.15)
	end

	local iconSize = self:isMouseOver() and (self.iconSize * 1.08) or self.iconSize
	local iconX = (self.width - iconSize) / 2
	local iconY = (self.height - iconSize) / 2
	local a, r, g, b = 0.88, 0.88, 0.88, 0.88
	if self.isSelected then
		a, r, g, b = 1, 0.95, 0.55, 0.15
	elseif self:isMouseOver() then
		a, r, g, b = 1, 0.92, 0.92, 0.92
	end
	if self.tabIcon then
		self:drawTextureScaledAspect(self.tabIcon, iconX, iconY, iconSize, iconSize, a, r, g, b)
	else
		local firstChar = ""
		if self.displayName and #self.displayName > 0 then
			firstChar = string.sub(self.displayName, 1, 1)
		end
		if self.defaultBG then
			self:drawTextureScaled(self.defaultBG, iconX, iconY, iconSize, iconSize, a, r, g, b)
		end
		if firstChar ~= "" then
			local tw = getTextManager():MeasureStringX(UIFont.Medium, firstChar)
			self:drawText(firstChar, iconX + (iconSize - tw) / 2, iconY + (iconSize - FONT_HGT_MEDIUM) / 2, r, g, b, a, UIFont.Medium)
		end
	end
end

--- Panel lateral de pestañas.
GS_TerminalTabRail = ISPanel:derive("GS_TerminalTabRail")

function GS_TerminalTabRail:initialise()
	ISPanel.initialise(self)
end

---@param x number
---@param y number
---@param w number
---@param h number
---@param terminal GS_TerminalUI
---@param tabDefs table[]
---@param footerTabDef table|nil
---@return GS_TerminalTabRail
function GS_TerminalTabRail:new(x, y, w, h, terminal, tabDefs, footerTabDef)
	local o = ISPanel:new(x, y, w, h)
	setmetatable(o, self)
	self.__index = self
	o.terminal = terminal
	o.tabDefs = tabDefs or {}
	o.footerTabDef = footerTabDef
	o.padding = math.floor(FONT_HGT_SMALL * 0.2)
	o.itemHeight = math.floor(FONT_HGT_MEDIUM * 1.85)
	o.scrollBarWidth = 0
	o.tabSlots = {}
	o.flyoutLbl = nil
	o.drawBackground = false
	return o
end

--- Ancho mínimo de la columna (misma fórmula que Neat Crafting).
---@param tabDefs table[]|nil
---@return number
function GlobalStorageSiK.TerminalTabRail.measureWidth(tabDefs)
	local pad = math.floor(FONT_HGT_SMALL * 0.2)
	local itemH = math.floor(FONT_HGT_MEDIUM * 1.85)
	return itemH + pad * 2
end

function GS_TerminalTabRail:createChildren()
	self.tabSlots = {}
	local y = self.padding
	for i = 1, #self.tabDefs do
		local def = self.tabDefs[i]
		local title = T(def.titleKey)
		local slot = GS_TerminalTabSlot:new(self.padding, y, self.itemHeight, title, def.key, def.iconPath, self)
		slot:initialise()
		self:addChild(slot)
		self.tabSlots[def.key] = slot
		y = y + self.itemHeight + 4
	end

	if self.footerTabDef then
		local def = self.footerTabDef
		local title = T(def.titleKey)
		local footerY = math.max(self.padding, self.height - self.padding - self.itemHeight)
		local slot = GS_TerminalTabSlot:new(self.padding, footerY, self.itemHeight, title, def.key, def.iconPath, self)
		slot:initialise()
		slot.isFooter = true
		self:addChild(slot)
		self.tabSlots[def.key] = slot
		self.footerSlot = slot
	end

	self:syncSelection()
end

function GS_TerminalTabRail:layoutSlots()
	local y = self.padding
	for i = 1, #self.tabDefs do
		local def = self.tabDefs[i]
		local slot = self.tabSlots[def.key]
		if slot then
			slot:setY(y)
			slot:setWidth(self.itemHeight)
			slot:setHeight(self.itemHeight)
			if slot.neatBtn then
				slot.neatBtn:setWidth(self.itemHeight)
				slot.neatBtn:setHeight(self.itemHeight)
			end
			y = y + self.itemHeight + 4
		end
	end
	-- BUG REAL encontrado (reportado: "Craft y Builder usan la misma
	-- posicion"): esto antes reposicionaba solo self.craftSlot (una unica
	-- ranura), pero Craft Y Builder (y Cook en el futuro) llaman ambos a
	-- setCraftTabVisible - la segunda en añadirse pisaba la referencia de la
	-- primera, que se quedaba huerfana sin recolocarse nunca mas, en la
	-- MISMA posicion que la nueva. self.dynamicSlots es una lista ordenada
	-- (no un unico slot), cada una se coloca secuencialmente tras las fijas.
	for i = 1, #(self.dynamicSlots or {}) do
		local slot = self.dynamicSlots[i]
		if slot then
			slot:setY(y)
			y = y + self.itemHeight + 4
		end
	end
	if self.footerSlot then
		local footerY = math.max(y + 8, self.height - self.padding - self.itemHeight)
		self.footerSlot:setY(footerY)
	end
end

function GS_TerminalTabRail:syncSelection()
	local active = self.terminal and self.terminal.activeTabKey or "items"
	for key, slot in pairs(self.tabSlots) do
		if slot.setSelected then
			slot:setSelected(key == active)
		else
			slot.isSelected = (key == active)
		end
	end
end

function GS_TerminalTabRail:onTabActivated(tabKey)
	if self.terminal and self.terminal.activateTab then
		self.terminal:activateTab(tabKey)
	end
	self:syncSelection()
end

function GS_TerminalTabRail:hideFlyout()
	if self.flyoutLbl then
		self.flyoutLbl:setVisible(false)
	end
end

function GS_TerminalTabRail:showFlyoutForSlot(slot)
	if not slot or not slot.displayName then
		return
	end
	local tm = getTextManager()
	local textW = tm:MeasureStringX(UIFont.Small, slot.displayName) + 16
	local flyH = FONT_HGT_SMALL + 10
	if not self.flyoutLbl then
		self.flyoutLbl = ISPanel:new(-200, 0, textW, flyH)
		self.flyoutLbl:initialise()
		self.flyoutLbl.drawBackground = false
		self.flyoutLbl.prerender = function(panel)
			ISPanel.prerender(panel)
			local patch = nil
			if NinePatchTexture and NinePatchTexture.getSharedTexture then
				patch = NinePatchTexture.getSharedTexture("media/ui/Neat_Crafting/Panel/CategoryBG_Normal.png")
			end
			if patch and patch.render then
				patch:render(panel:getAbsoluteX(), panel:getAbsoluteY(), panel.width, panel.height, 0.12, 0.12, 0.12, 0.95)
			else
				panel:drawRect(0, 0, panel.width, panel.height, 0.95, 0.1, 0.1, 0.1)
			end
		end
		self.flyoutLbl.render = function(panel)
			panel:drawText(panel._flyoutText or "", 8, 4, 0.92, 0.94, 0.96, 1, UIFont.Small)
		end
		self:addChild(self.flyoutLbl)
	end
	self.flyoutLbl._flyoutText = slot.displayName
	self.flyoutLbl:setWidth(textW)
	self.flyoutLbl:setHeight(flyH)
	self.flyoutLbl:setX(-textW - 4)
	self.flyoutLbl:setY(slot:getY())
	self.flyoutLbl:setVisible(true)
	self.flyoutLbl:bringToTop()
end

function GS_TerminalTabRail:onMouseMove()
	for _, slot in pairs(self.tabSlots) do
		local hover = slot.neatBtn and slot.neatBtn:isMouseOver() or slot:isMouseOver()
		if hover then
			self:showFlyoutForSlot(slot)
			return true
		end
	end
	self:hideFlyout()
	return false
end

function GS_TerminalTabRail:onMouseMoveOutside()
	self:hideFlyout()
	return false
end

function GS_TerminalTabRail:prerender()
	ISPanel.prerender(self)
	if NinePatchTexture and NinePatchTexture.getSharedTexture then
		local bg = NinePatchTexture.getSharedTexture("media/ui/Neat_Crafting/Panel/CategoryBG_RightAngle.png")
		if bg and bg.render then
			bg:render(self:getAbsoluteX(), self:getAbsoluteY(), self.width - self.scrollBarWidth, self.height, 0.14, 0.14, 0.14, 0.96)
		end
	end
	if self.footerSlot then
		local sepY = self.footerSlot:getY() - 6
		self:drawRect(self.padding, sepY, self.width - self.scrollBarWidth - self.padding * 2, 1, 0.45, 0.35, 0.35, 0.35)
	end
end

--- Construye columna lateral en el terminal.
---@param terminal GS_TerminalUI
---@param tabDefs table[]
---@param footerTabDef table|nil
function GlobalStorageSiK.TerminalTabRail.build(terminal, tabDefs, footerTabDef)
	local railW = GlobalStorageSiK.TerminalTabRail.measureWidth(tabDefs)
	terminal.tabRail = GS_TerminalTabRail:new(0, 0, railW, 10, terminal, tabDefs, footerTabDef)
	terminal.tabRail:initialise()
	terminal.tabRail:createChildren()
	terminal:addChild(terminal.tabRail)
end

--- Reposiciona slots.
---@param terminal GS_TerminalUI
function GlobalStorageSiK.TerminalTabRail.layout(terminal)
	if not terminal.tabRail then
		return
	end
	terminal.tabRail:layoutSlots()
	terminal.tabRail:syncSelection()
end

--- Muestra u oculta una pestaña de addon (genérico, cualquier addon la usa
--- vía GS_TerminalUI_Extensions.setTabVisible o directamente).
---@param visible boolean
---@param def table|nil
function GS_TerminalTabRail:setCraftTabVisible(visible, def)
	def = def or {}
	local key = def.key or "craft"
	self.dynamicSlots = self.dynamicSlots or {}
	if visible then
		if self.tabSlots[key] then
			return
		end
		local title = T(def.titleKey or "IGUI_GS_TabCraft")
		-- Posicion inicial provisional (layoutSlots la corrige de inmediato
		-- mas abajo) - solo hace falta un valor valido para construir el slot.
		local slot = GS_TerminalTabSlot:new(self.padding, self.padding, self.itemHeight, title, key, def.iconPath, self)
		slot:initialise()
		self:addChild(slot)
		self.tabSlots[key] = slot
		self.dynamicSlots[#self.dynamicSlots + 1] = slot
	else
		local slot = self.tabSlots[key]
		if slot then
			self:removeChild(slot)
			self.tabSlots[key] = nil
			for i = #self.dynamicSlots, 1, -1 do
				if self.dynamicSlots[i] == slot then
					table.remove(self.dynamicSlots, i)
					break
				end
			end
			if self.terminal and self.terminal.activeTabKey == key then
				self.terminal:activateTab("items")
			end
		end
	end
	self:layoutSlots()
	self:syncSelection()
end

--[[
	GlobalStorageSiK - Secciones visuales del terminal (NeatUI)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Títulos y agrupación sin marcos azules ni cajas anidadas.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_Libs"
require "GS_TerminalUI_Chrome"

GlobalStorageSiK.TerminalSections = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

--- Crea panel de sección plano: solo título y línea separadora sutil.
---@param parent ISPanel
---@param x number
---@param y number
---@param w number
---@param h number
---@param titleKey string|nil
---@return ISPanel
function GlobalStorageSiK.TerminalSections.create(parent, x, y, w, h, titleKey)
	local titleH = titleKey and (FONT_HGT_SMALL + 10) or 0
	local section = ISPanel:new(x, y, w, h)
	section:initialise()
	section.drawBackground = false
	section.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	section.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	section.titleKey = titleKey
	section.titleHeight = titleH
	section.contentPad = 8
	section.clipChildren = true
	section:setScrollWithParent(false)
	if section.setScrollChildren then
		section:setScrollChildren(false)
	end

	section.prerender = function(self)
		if self.drawBackground then
			ISPanel.prerender(self)
		end
		if not self.titleKey then
			return
		end
		local title = self.displayTitle
		if not title then
			title = T(self.titleKey)
		end
		if title and title ~= "" then
			local titleH = self.titleHeight or (FONT_HGT_SMALL + 10)
			local patches = GlobalStorageSiK.TerminalChrome.getNeatPanelPatches()
			if not GlobalStorageSiK.TerminalChrome.renderNinePatch(self, patches.innerTitle, 0, 0, self.width, titleH, 0.2, 0.2, 0.2, 0.85) then
				self:drawRect(0, 0, self.width, titleH, 0.85, 0.12, 0.12, 0.12)
			end
			self:drawText(title, self.contentPad, 2, 0.88, 0.9, 0.94, 1, UIFont.Small)
			local lineY = self.titleHeight - 2
			self:drawRect(self.contentPad, lineY, math.max(0, self.width - self.contentPad * 2), 1, 0.35, 0.32, 0.32, 0.32)
		end
	end

	parent:addChild(section)
	return section
end

--- Crea etiqueta de título suelta (sin panel contenedor).
---@param parent ISPanel
---@param x number
---@param y number
---@param titleKey string
---@return ISLabel
function GlobalStorageSiK.TerminalSections.addTitleLabel(parent, x, y, titleKey)
	local lbl = GlobalStorageSiK.TerminalChrome.createSectionLabel(x, y, T(titleKey))
	parent:addChild(lbl)
	return lbl
end

--- Crea etiqueta de stat dentro de una sección.
---@param section ISPanel
---@param y number
---@param text string
---@param r number
---@param g number
---@param b number
---@return ISLabel
function GlobalStorageSiK.TerminalSections.addStatLabel(section, y, text, r, g, b)
	local lbl = ISLabel:new(section.contentPad, y, FONT_HGT_SMALL, text, r or 0.88, g or 0.9, b or 0.94, 1, UIFont.Small, true)
	lbl:initialise()
	section:addChild(lbl)
	return lbl
end

--- Añade líneas de stat con salto de línea; devuelve la Y siguiente.
---@param section ISPanel
---@param y number
---@param text string
---@param maxWidth number
---@param r number
---@param g number
---@param b number
---@return number nextY
function GlobalStorageSiK.TerminalSections.addWrappedStatLabels(section, y, text, maxWidth, r, g, b)
	local lines = GlobalStorageSiK.TerminalChrome.wrapTextLines(text, maxWidth, UIFont.Small)
	for i = 1, #lines do
		GlobalStorageSiK.TerminalSections.addStatLabel(section, y, lines[i], r, g, b)
		y = y + FONT_HGT_SMALL + 3
	end
	return y
end

--- Limpia hijos bajo la cabecera de una sección.
---@param section ISPanel
function GlobalStorageSiK.TerminalSections.clearContent(section)
	if not section or not section.childrenInOrder then
		return
	end
	local minY = (section.titleHeight or 0) + (section.contentPad or 8)
	for i = #section.childrenInOrder, 1, -1 do
		local child = section.childrenInOrder[i]
		if child and child:getY() >= minY then
			if child.removeFromUIManager then
				child:removeFromUIManager()
			end
			section:removeChild(child)
			if child.destroy then
				child:destroy()
			end
		end
	end
end

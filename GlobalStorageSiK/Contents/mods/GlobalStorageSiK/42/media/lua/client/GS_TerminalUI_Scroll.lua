--[[
	GlobalStorageSiK - Motor de scroll (NeatUI_Framework nativo)
	Autor: SiK
	Fecha: 2025-06-25
	Descripción:
	  mode "panel" + NeatUI -> NIScrollView (addScrollChild, setScrollHeight)
	  mode "rows"  -> pool legacy o NIVirtualScrollView
	  mode "panel" sin NeatUI -> ISPanel + contentPanel (fallback)
	  Referencia: docs/NEATUI_FRAMEWORK.md — no destruir NIScrollBar ni dibujar barra duplicada.
]]

require "ISUI/ISPanel"

GlobalStorageSiK.TerminalScroll = {}

local SCROLLBAR_W = 14
local SCROLLBAR_LIST_GAP = 10
local WHEEL_STEP = 40
local TAB_BOTTOM_INSET = 32
local LIST_BOTTOM_GAP = 12
local CONTENT_BOTTOM_PAD = 24
local THUMB_MIN_H = 22

local function applyScrollStyle(scroll)
	scroll.drawBackground = false
	scroll.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	scroll.borderColor = { r = 0, g = 0, b = 0, a = 0 }
end

--- Barras NeatUI siempre visibles cuando hay desborde (sin auto-ocultar).
---@param scroll ISUIElement|nil
local function configureScrollbarVisibility(scroll)
	if not scroll then
		return
	end
	if scroll.setAutoHideScrollbar then
		scroll:setAutoHideScrollbar(false)
	end
	if scroll.setShowScrollBars then
		scroll:setShowScrollBars(true)
	end
end

---@param scroll ISPanel
local function maxScrollOffset(scroll)
	local viewH = scroll.height or 0
	local contentH = scroll._gsContentHeight or viewH
	return math.max(0, contentH - viewH)
end

--- Recorta hijos al viewport del scroll (evita sangrado sobre cabecera/pestañas).
---@param scroll ISPanel
local function installViewportClip(scroll)
	if scroll._gsClipInstalled then
		return
	end
	scroll._gsClipInstalled = true
	local basePrerender = scroll.prerender
	scroll.prerender = function(self)
		if basePrerender then
			basePrerender(self)
		else
			ISPanel.prerender(self)
		end
		if self.setStencilRect then
			self:setStencilRect(0, 0, self.width, self.height)
		end
	end
	local baseRender = scroll.render
	scroll.render = function(self)
		if baseRender then
			baseRender(self)
		else
			ISPanel.render(self)
		end
		if self.clearStencilRect then
			self:clearStencilRect()
		end
		GlobalStorageSiK.TerminalScroll.drawScrollBar(self)
	end
end

--- Dibuja barra vertical propia (thumb NeatUI si está disponible).
---@param scroll ISPanel|nil
function GlobalStorageSiK.TerminalScroll.drawScrollBar(scroll)
	if not scroll or scroll._gsScrollBarsHidden then
		return
	end
	if GlobalStorageSiK.TerminalScroll.isNeatScroll(scroll) then
		return
	end
	local viewH = scroll.height or 0
	local contentH = scroll._gsContentHeight or viewH
	if scroll._gsScrollMode == "neat_virtual" and scroll.dataSource then
		local ih = scroll.itemHeight or 40
		local pad = scroll.padding or 0
		contentH = math.max(viewH, #scroll.dataSource * ih + pad * 2)
	elseif scroll._gsScrollMode == "neat" and scroll.getScrollHeight then
		local ok, sh = pcall(function()
			return scroll:getScrollHeight()
		end)
		if ok and sh and sh > contentH then
			contentH = sh
		end
	end
	if contentH <= viewH + 2 then
		return
	end
	local trackX = math.max(0, (scroll.width or 0) - SCROLLBAR_W - (scroll._gsBarRightPad or 0))
	scroll:drawRect(trackX, 0, SCROLLBAR_W, viewH, 0.25, 0.06, 0.06, 0.06)
	local ratio = viewH / contentH
	local thumbH = math.max(THUMB_MIN_H, math.floor(viewH * ratio))
	local maxOff = maxScrollOffset(scroll)
	local offset = scroll._gsScrollOffset or 0
	local thumbY = 0
	if maxOff > 0 then
		thumbY = math.floor((offset / maxOff) * (viewH - thumbH))
	end
	local thumbW = math.max(6, SCROLLBAR_W - 6)
	local thumbX = trackX + math.floor((SCROLLBAR_W - thumbW) / 2)
	local drawn = false
	if NinePatchTexture and NinePatchTexture.getSharedTexture then
		local ok, patch = pcall(function()
			return NinePatchTexture.getSharedTexture("media/ui/NeatUI/ScrollView/ScrollBar_V.png")
		end)
		if ok and patch and patch.render then
			local bright = 0.85
			patch:render(scroll:getAbsoluteX() + thumbX, scroll:getAbsoluteY() + thumbY, thumbW, thumbH, bright, bright, bright, 0.85)
			drawn = true
		end
	end
	if not drawn then
		scroll:drawRect(thumbX, thumbY, thumbW, thumbH, 0.9, 0.38, 0.38, 0.42)
	end
end

---@param scroll ISPanel|nil
---@param x number
---@return boolean
local function isOnScrollTrack(scroll, x)
	if not scroll then
		return false
	end
	return x >= (scroll.width or 0) - SCROLLBAR_W - (scroll._gsBarRightPad or 0)
end

---@param scroll ISPanel
---@param localY number
local function offsetFromTrackY(scroll, localY)
	local viewH = scroll.height or 0
	local contentH = scroll._gsContentHeight or viewH
	local maxOff = maxScrollOffset(scroll)
	if maxOff <= 0 then
		return 0
	end
	local ratio = math.max(0, math.min(1, localY / viewH))
	return math.floor(ratio * maxOff + 0.5)
end

---@param scroll ISPanel
---@param onScroll function|nil
function GlobalStorageSiK.TerminalScroll.bindScrollEvents(scroll, onScroll)
	if not scroll then
		return
	end
	if onScroll then
		scroll._gsOnScroll = onScroll
	end
	if scroll._gsEventsBound then
		return
	end
	scroll._gsEventsBound = true

	scroll.onMouseWheel = function(self, del)
		GlobalStorageSiK.TerminalScroll.applyWheelDelta(self, del, WHEEL_STEP)
		if self._gsOnScroll then
			self._gsOnScroll()
		end
		return true
	end

	local baseDown = scroll.onMouseDown
	scroll.onMouseDown = function(self, x, y)
		if isOnScrollTrack(self, x) and maxScrollOffset(self) > 0 then
			self._gsDraggingScroll = true
			self:setCapture(true)
			GlobalStorageSiK.TerminalScroll.setScrollOffset(self, offsetFromTrackY(self, y))
			if self._gsOnScroll then
				self._gsOnScroll()
			end
			return true
		end
		if baseDown then
			return baseDown(self, x, y)
		end
		return false
	end

	local baseMove = scroll.onMouseMove
	scroll.onMouseMove = function(self, dx, dy)
		if self._gsDraggingScroll then
			local my = self:getMouseY()
			GlobalStorageSiK.TerminalScroll.setScrollOffset(self, offsetFromTrackY(self, my))
			if self._gsOnScroll then
				self._gsOnScroll()
			end
			return true
		end
		if baseMove then
			return baseMove(self, dx, dy)
		end
		return false
	end

	local function releaseDrag(self)
		if self._gsDraggingScroll then
			self._gsDraggingScroll = false
			self:setCapture(false)
			return true
		end
		return false
	end

	local baseUp = scroll.onMouseUp
	scroll.onMouseUp = function(self, x, y)
		if releaseDrag(self) then
			return true
		end
		if baseUp then
			return baseUp(self, x, y)
		end
		return false
	end
	scroll.onMouseUpOutside = function(self, x, y)
		if releaseDrag(self) then
			return true
		end
		return false
	end
end

--- Margen inferior del área de contenido (contentHost más bajo que el borde).
---@return number
function GlobalStorageSiK.TerminalScroll.contentBottomInset()
	return TAB_BOTTOM_INSET
end

--- Filas de pool necesarias para un viewport (misma fórmula que NIVirtualScrollView).
---@param viewH number
---@param rowH number
---@param buffer number|nil
---@return number
function GlobalStorageSiK.TerminalScroll.rowPoolSizeForViewport(viewH, rowH, buffer)
	buffer = buffer or 2
	rowH = math.max(1, rowH or 1)
	return math.max(3, math.ceil((viewH or rowH) / rowH) + buffer)
end

---@deprecated Usar contentBottomInset; alias por compatibilidad.
---@return number
function GlobalStorageSiK.TerminalScroll.viewportBottomGap()
	return TAB_BOTTOM_INSET
end

--- Hueco inferior dentro de paneles de lista.
---@return number
function GlobalStorageSiK.TerminalScroll.listBottomGap()
	return LIST_BOTTOM_GAP
end

--- Padding extra al final del contenido scrollable.
---@return number
function GlobalStorageSiK.TerminalScroll.bottomPad()
	return CONTENT_BOTTOM_PAD
end

---@param scroll ISPanel|nil
---@return boolean
function GlobalStorageSiK.TerminalScroll.isNeatScroll(scroll)
	return scroll and (scroll._gsScrollMode == "neat" or scroll._gsScrollMode == "neat_virtual")
end

--- Posiciona un hijo en coordenadas de contenido (NIScrollView aplica getYScroll internamente).
---@param scroll ISPanel|nil
---@param child ISUIElement|nil
---@param contentY number
function GlobalStorageSiK.TerminalScroll.setContentY(scroll, child, contentY)
	if not scroll or not child or not child.setY then
		return
	end
	if GlobalStorageSiK.TerminalScroll.isNeatScroll(scroll) and scroll.getYScroll then
		child._gsContentY = contentY
		child:setY(contentY + (scroll:getYScroll() or 0))
	else
		child:setY(contentY)
	end
end

--- Posiciona un hijo en X de contenido (NIScrollView).
---@param scroll ISPanel|nil
---@param child ISUIElement|nil
---@param contentX number
function GlobalStorageSiK.TerminalScroll.setContentX(scroll, child, contentX)
	if not scroll or not child or not child.setX then
		return
	end
	if GlobalStorageSiK.TerminalScroll.isNeatScroll(scroll) and scroll.getXScroll then
		child._gsContentX = contentX
		child:setX(contentX + (scroll:getXScroll() or 0))
	else
		child:setX(contentX)
	end
end

--- Evita que updateScroll de NIScrollView desplace de nuevo tras un layout manual.
---@param scroll ISPanel|nil
function GlobalStorageSiK.TerminalScroll.resetNeatScrollDelta(scroll)
	if scroll and scroll.lastX ~= nil and scroll.getXScroll then
		scroll.lastX = scroll:getXScroll() or 0
		scroll.lastY = scroll:getYScroll() or 0
	end
end

--- Elimina y destruye hijos de NIScrollView (removeScrollChild no destruye por sí solo).
---@param scroll ISPanel|nil
function GlobalStorageSiK.TerminalScroll.disposeNeatScrollChildren(scroll)
	if not scroll then
		return
	end
	if scroll.scrollChildren then
		while #scroll.scrollChildren > 0 do
			local child = scroll.scrollChildren[1]
			if scroll.removeScrollChild then
				scroll:removeScrollChild(child)
			end
			GlobalStorageSiK.TerminalScroll.disposeChild(scroll, child)
		end
	end
	if scroll.childrenInOrder then
		for i = #scroll.childrenInOrder, 1, -1 do
			local child = scroll.childrenInOrder[i]
			if child and not GlobalStorageSiK.TerminalScroll.isNeatScrollBar(child) then
				GlobalStorageSiK.TerminalScroll.disposeChild(scroll, child)
			end
		end
	end
	if scroll.setScrollHeight then
		scroll:setScrollHeight(0)
	end
	if scroll.resetScroll then
		scroll:resetScroll()
	end
end

---@param scroll ISPanel|nil
---@return number
function GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	if not scroll then
		return 0
	end
	if GlobalStorageSiK.TerminalScroll.isNeatScroll(scroll) and scroll.getYScroll then
		return math.max(0, -(scroll:getYScroll() or 0))
	end
	if scroll._gsScrollMode == "neat_virtual" and scroll.scrollOffset ~= nil then
		return math.max(0, scroll.scrollOffset or 0)
	end
	return scroll._gsScrollOffset or 0
end

--- Desplaza contentPanel (modo panel).
---@param scroll ISPanel
function GlobalStorageSiK.TerminalScroll.applyPanelOffset(scroll)
	if not scroll or GlobalStorageSiK.TerminalScroll.isNeatScroll(scroll) then
		return
	end
	if scroll._gsScrollMode ~= "panel" or not scroll.contentPanel then
		return
	end
	scroll.contentPanel:setY(-(scroll._gsScrollOffset or 0))
end

---@param scroll ISPanel|nil
---@param offset number
function GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, offset)
	if not scroll then
		return
	end
	if GlobalStorageSiK.TerminalScroll.isNeatScroll(scroll) and scroll.setYScroll then
		offset = math.max(0, offset or 0)
		scroll._gsScrollOffset = offset
		scroll:setYScroll(-offset)
		if scroll.updateScroll then
			scroll:updateScroll()
		end
		GlobalStorageSiK.TerminalScroll.resetNeatScrollDelta(scroll)
		return
	end
	if scroll._gsScrollMode == "neat_virtual" and scroll.setScrollOffsetDirect then
		offset = math.max(0, offset or 0)
		scroll:setScrollOffsetDirect(offset)
		scroll._gsScrollOffset = scroll.scrollOffset or offset
		if scroll.refreshItems then
			scroll.visibleStartIndex = -1
			scroll.visibleEndIndex = -1
			scroll:refreshItems()
		end
		return
	end
	offset = math.max(0, offset or 0)
	offset = math.min(offset, maxScrollOffset(scroll))
	scroll._gsScrollOffset = offset
	if scroll._gsScrollMode == "panel" then
		GlobalStorageSiK.TerminalScroll.applyPanelOffset(scroll)
	end
end

---@param scroll ISPanel|nil
function GlobalStorageSiK.TerminalScroll.resetPosition(scroll)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, 0)
end

---@param scroll ISPanel
---@param del number
---@param step number|nil
function GlobalStorageSiK.TerminalScroll.applyWheelDelta(scroll, del, step)
	if not scroll then
		return
	end
	step = step or WHEEL_STEP
	local offset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	local newOffset = math.max(0, math.min(maxScrollOffset(scroll), offset + del * step))
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, newOffset)
end

--- Elimina un hijo UI de forma segura (UIManager + destroy).
---@param parent ISUIElement|nil
---@param child ISUIElement|nil
function GlobalStorageSiK.TerminalScroll.disposeChild(parent, child)
	if not parent or not child then
		return
	end
	if child.removeFromUIManager then
		child:removeFromUIManager()
	end
	if parent.removeChild then
		parent:removeChild(child)
	end
	if child.destroy then
		child:destroy()
	end
end

---@param scroll ISPanel
---@param child ISUIElement
local function disposeScrollChild(scroll, child)
	GlobalStorageSiK.TerminalScroll.disposeChild(scroll, child)
end

--- Crea scroll NeatUI (NIScrollView) para paneles con hijos reales.
---@param parent ISUIElement
---@param x number
---@param y number
---@param w number
---@param h number
---@return ISUIElement
function GlobalStorageSiK.TerminalScroll.createNeat(parent, x, y, w, h)
	local NIScroll = GlobalStorageSiK.Libs.getNIScrollView()
	if not NIScroll then
		return GlobalStorageSiK.TerminalScroll.createLegacy(parent, x, y, w, h, "panel")
	end
	local scroll = NIScroll:new(x, y, w, h)
	configureScrollbarVisibility(scroll)
	scroll:initialise()
	scroll:setScrollDirection("vertical")
	scroll:setScrollSensitivity(40)
	scroll.gsTerminalScroll = true
	scroll._gsScrollMode = "neat"
	scroll._gsScrollOffset = 0
	scroll._gsContentHeight = h
	parent:addChild(scroll)
	return scroll
end

--- Crea lista virtual NeatUI (NIVirtualScrollView).
---@param parent ISUIElement
---@param x number
---@param y number
---@param w number
---@param h number
---@param itemHeight number
---@param padding number|nil
---@return ISUIElement|nil
function GlobalStorageSiK.TerminalScroll.createVirtual(parent, x, y, w, h, itemHeight, padding)
	local NIVirtual = GlobalStorageSiK.Libs.getNIVirtualScrollView()
	if not NIVirtual then
		return nil
	end
	local scroll = NIVirtual:new(x, y, w, h)
	scroll:initialise()
	configureScrollbarVisibility(scroll)
	scroll:setConfig(itemHeight, padding or 0)
	scroll.gsTerminalScroll = true
	scroll._gsScrollMode = "neat_virtual"
	scroll._gsScrollOffset = 0
	scroll._gsContentHeight = h
	parent:addChild(scroll)
	return scroll
end

--- Scroll legacy (ISPanel + barra propia o pool manual).
---@param parent ISUIElement
---@param x number
---@param y number
---@param w number
---@param h number
---@param mode string|nil "panel" (default) o "rows"
---@return ISPanel
function GlobalStorageSiK.TerminalScroll.createLegacy(parent, x, y, w, h, mode)
	mode = mode or "panel"
	local scroll = ISPanel:new(x, y, w, h)
	scroll:initialise()
	applyScrollStyle(scroll)
	scroll.clipChildren = true
	scroll:setScrollWithParent(false)
	if scroll.setScrollChildren then
		scroll:setScrollChildren(false)
	end
	scroll.gsTerminalScroll = true
	scroll._gsScrollMode = mode
	scroll._gsScrollOffset = 0
	if mode == "rows" then
		scroll._gsVirtualItems = true
	end

	if mode == "panel" then
		scroll.contentPanel = ISPanel:new(0, 0, w, h)
		scroll.contentPanel:initialise()
		scroll.contentPanel.drawBackground = false
		scroll.contentPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
		scroll.contentPanel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
		scroll.contentPanel.clipChildren = true
		scroll:addChild(scroll.contentPanel)
	end

	installViewportClip(scroll)
	GlobalStorageSiK.TerminalScroll.bindScrollEvents(scroll, nil)
	parent:addChild(scroll)
	return scroll
end

--- Crea scroll del terminal (NeatUI por defecto en modo panel).
---@param parent ISUIElement
---@param x number
---@param y number
---@param w number
---@param h number
---@param mode string|nil "panel" (default) o "rows"
---@return ISPanel|ISUIElement
function GlobalStorageSiK.TerminalScroll.create(parent, x, y, w, h, mode)
	mode = mode or "panel"
	if mode == "panel" and GlobalStorageSiK.Libs.getNIScrollView() then
		return GlobalStorageSiK.TerminalScroll.createNeat(parent, x, y, w, h)
	end
	return GlobalStorageSiK.TerminalScroll.createLegacy(parent, x, y, w, h, mode)
end

--- Scroll con hijos clicables (botones, filas, combos). Evita NIScrollView que puede tragar clics.
---@param parent ISUIElement
---@param x number
---@param y number
---@param w number
---@param h number
---@return ISPanel
function GlobalStorageSiK.TerminalScroll.createInteractive(parent, x, y, w, h)
	return GlobalStorageSiK.TerminalScroll.createLegacy(parent, x, y, w, h, "panel")
end

---@param scroll ISPanel|nil
---@return ISUIElement|nil
function GlobalStorageSiK.TerminalScroll.childHost(scroll)
	if not scroll then
		return nil
	end
	if scroll._gsScrollMode == "neat" or scroll._gsScrollMode == "neat_virtual" then
		return scroll
	end
	return scroll.contentPanel or scroll
end

--- Comprueba que un widget UI sigue vivo (no dispuesto tras clear/reload).
---@param widget ISUIElement|nil
---@return boolean
function GlobalStorageSiK.TerminalScroll.isLiveWidget(widget)
	if not widget then
		return false
	end
	local ok = pcall(function()
		if widget.getWidth then
			widget:getWidth()
		elseif widget.setX then
			widget:setX(widget.x or 0)
		end
	end)
	return ok
end

---@param scroll ISPanel
---@param child ISUIElement
function GlobalStorageSiK.TerminalScroll.addChild(scroll, child)
	if not scroll or not child then
		return
	end
	if scroll._gsScrollMode == "neat_virtual" then
		return
	end
	if scroll._gsScrollMode == "neat" and scroll.addScrollChild then
		if child._gsContentY == nil then
			local sy = scroll:getYScroll() or 0
			local sx = scroll:getXScroll() or 0
			child._gsContentY = (child.y or (child.getY and child:getY()) or 0) - sy
			child._gsContentX = (child.x or (child.getX and child:getX()) or 0) - sx
		end
		scroll:addScrollChild(child)
		child:setVisible(true)
		return
	end
	local host = GlobalStorageSiK.TerminalScroll.childHost(scroll)
	if host then
		host:addChild(child)
		child:setVisible(true)
	end
end

---@param scroll ISPanel
---@param tagField string
function GlobalStorageSiK.TerminalScroll.clearTagged(scroll, tagField)
	if not scroll or not tagField or tagField == "" then
		return
	end
	local host = GlobalStorageSiK.TerminalScroll.childHost(scroll)
	if not host or not host.childrenInOrder then
		return
	end
	for i = #host.childrenInOrder, 1, -1 do
		local child = host.childrenInOrder[i]
		if child and child[tagField] then
			disposeScrollChild(host, child)
		end
	end
end

---@param scroll ISPanel
---@param preserveOffset boolean|nil
function GlobalStorageSiK.TerminalScroll.clear(scroll, preserveOffset)
	if not scroll then
		return
	end
	local saved = preserveOffset and GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll) or 0

	if scroll._gsScrollMode == "neat_virtual" then
		if scroll.setDataSource then
			scroll:setDataSource({}, false)
		end
		if scroll.setYScroll then
			scroll:setYScroll(0)
		end
		GlobalStorageSiK.TerminalScroll.resetPosition(scroll)
		return
	end

	if scroll._gsScrollMode == "neat" and scroll.scrollChildren then
		GlobalStorageSiK.TerminalScroll.disposeNeatScrollChildren(scroll)
		if preserveOffset then
			GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, saved)
		else
			GlobalStorageSiK.TerminalScroll.resetPosition(scroll)
		end
		return
	end

	local host = GlobalStorageSiK.TerminalScroll.childHost(scroll)

	if host and host.childrenInOrder then
		for i = #host.childrenInOrder, 1, -1 do
			disposeScrollChild(host, host.childrenInOrder[i])
		end
	end

	if scroll._gsScrollMode == "rows" and scroll.childrenInOrder then
		for i = #scroll.childrenInOrder, 1, -1 do
			local child = scroll.childrenInOrder[i]
			if not child._gsVirtualRow then
				disposeScrollChild(scroll, child)
			end
		end
	end

	scroll.zoneRows = nil
	scroll.nodeRows = nil
	if preserveOffset then
		GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, saved)
	else
		GlobalStorageSiK.TerminalScroll.resetPosition(scroll)
	end
end

---@param scroll ISPanel
---@param contentHeight number
function GlobalStorageSiK.TerminalScroll.finish(scroll, contentHeight)
	GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, contentHeight)
end

---@param scroll ISPanel
---@param contentHeight number
function GlobalStorageSiK.TerminalScroll.setContentHeight(scroll, contentHeight)
	if not scroll then
		return
	end
	local saved = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	scroll._gsContentHeight = math.max(0, (contentHeight or 0) + CONTENT_BOTTOM_PAD)
	if scroll._gsScrollMode == "neat_virtual" then
		if scroll.updateScrollMetrics then
			scroll:updateScrollMetrics()
		end
		GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, saved)
		return
	end
	if scroll._gsScrollMode == "neat" and scroll.setScrollHeight then
		scroll:setScrollHeight(scroll._gsContentHeight)
		if scroll.updateScroll then
			scroll:updateScroll()
		end
		GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, saved)
		return
	end
	if scroll.contentPanel then
		scroll.contentPanel:setWidth(GlobalStorageSiK.TerminalScroll.contentWidth(scroll))
		scroll.contentPanel:setHeight(math.max(scroll.height or 0, scroll._gsContentHeight))
	end
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, saved)
end

---@param scroll ISPanel
---@return number
function GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	if not scroll then
		return 0
	end
	local w = scroll.width or 0
	local pad = 8
	if scroll._gsScrollMode == "neat" or scroll._gsScrollMode == "neat_virtual" then
		local barW = GlobalStorageSiK.TerminalChrome and GlobalStorageSiK.TerminalChrome.scrollBarWidth
			and GlobalStorageSiK.TerminalChrome.scrollBarWidth() or SCROLLBAR_W
		return math.max(120, w - pad * 2 - barW)
	end
	local contentH = scroll._gsContentHeight or 0
	local viewH = scroll.height or 0
	local needsBar = contentH > viewH + 2
	local gap = scroll._gsScrollBarGap or SCROLLBAR_LIST_GAP
	if needsBar then
		return math.max(120, w - pad * 2 - SCROLLBAR_W - gap - (scroll._gsBarRightPad or 0))
	end
	return math.max(120, w - pad * 2)
end

---@param scroll ISPanel
---@param w number
---@param h number
function GlobalStorageSiK.TerminalScroll.resize(scroll, w, h)
	if not scroll then
		return
	end
	local saved = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	scroll:setWidth(w)
	scroll:setHeight(h)
	if scroll._gsScrollMode == "neat" or scroll._gsScrollMode == "neat_virtual" then
		if scroll._gsScrollMode == "neat_virtual" and scroll.setScrollOffsetDirect then
			GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, saved)
		elseif scroll.updateScroll then
			scroll:updateScroll()
			GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, saved)
		else
			GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, saved)
		end
		GlobalStorageSiK.TerminalScroll.resetNeatScrollDelta(scroll)
		return
	end
	if scroll.contentPanel then
		scroll.contentPanel:setWidth(GlobalStorageSiK.TerminalScroll.contentWidth(scroll))
		local contentH = scroll._gsContentHeight or h
		scroll.contentPanel:setHeight(math.max(h, contentH))
	end
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, saved)
end

---@param parent ISUIElement
---@param child ISUIElement
local function disposeUiChild(parent, child)
	GlobalStorageSiK.TerminalScroll.disposeChild(parent, child)
end

function GlobalStorageSiK.TerminalScroll.isNeatScrollBar(widget)
	if not widget then
		return false
	end
	return widget.Type == "NIScrollBar"
end

--- Barra vanilla de PZ (huérfana); no confundir con NIScrollBar del framework.
---@param widget ISUIElement|nil
---@return boolean
function GlobalStorageSiK.TerminalScroll.isVanillaScrollBar(widget)
	if not widget then
		return false
	end
	return widget.Type == "ISScrollBar"
end

---@param widget ISUIElement|nil
---@return boolean
function GlobalStorageSiK.TerminalScroll.isScrollBarWidget(widget)
	return GlobalStorageSiK.TerminalScroll.isVanillaScrollBar(widget)
end

--- Elimina solo ISScrollBar vanilla huérfanas (no NIScrollBar).
---@param scroll ISUIElement|nil
function GlobalStorageSiK.TerminalScroll.stripVanillaScrollBarGhosts(scroll)
	if not scroll or not scroll.childrenInOrder then
		return
	end
	for i = #scroll.childrenInOrder, 1, -1 do
		local child = scroll.childrenInOrder[i]
		if child and GlobalStorageSiK.TerminalScroll.isVanillaScrollBar(child) then
			disposeUiChild(scroll, child)
		end
	end
end

---@deprecated Usar stripVanillaScrollBarGhosts; nombre histórico.
function GlobalStorageSiK.TerminalScroll.removeLeftGhostScrollBars(root, depth)
	if not root or not root.childrenInOrder then
		return
	end
	depth = depth or 0
	if depth > 12 then
		return
	end
	GlobalStorageSiK.TerminalScroll.stripVanillaScrollBarGhosts(root)
	for i = 1, #root.childrenInOrder do
		local child = root.childrenInOrder[i]
		if child and child.childrenInOrder and not GlobalStorageSiK.TerminalScroll.isNeatScrollBar(child) then
			GlobalStorageSiK.TerminalScroll.removeLeftGhostScrollBars(child, depth + 1)
		end
	end
end

---@deprecated No hookear render de NeatUI; la barra la gestiona NIScrollView.
function GlobalStorageSiK.TerminalScroll.installCustomBarRender(scroll)
end

---@deprecated No interferir con updateScroll de NeatUI.
function GlobalStorageSiK.TerminalScroll.installScrollBarGuard(scroll)
end

---@deprecated Solo limpia ISScrollBar vanilla; nunca toca NIScrollBar.
---@param scroll ISPanel|nil
function GlobalStorageSiK.TerminalScroll.stripNativeBarWidgets(scroll)
	GlobalStorageSiK.TerminalScroll.stripVanillaScrollBarGhosts(scroll)
end

---@deprecated Alias de stripVanillaScrollBarGhosts para compatibilidad.
---@param scroll ISPanel|nil
function GlobalStorageSiK.TerminalScroll.suppressNativeScrollBars(scroll)
	GlobalStorageSiK.TerminalScroll.stripVanillaScrollBarGhosts(scroll)
end

--- Elimina ISScrollBar vanilla del subárbol (no NIScrollBar).
---@param root ISUIElement|nil
---@param depth number|nil
function GlobalStorageSiK.TerminalScroll.destroyAllScrollBarWidgets(root, depth)
	if not root then
		return
	end
	depth = depth or 0
	if depth > 18 then
		return
	end
	if root.childrenInOrder then
		for i = #root.childrenInOrder, 1, -1 do
			local child = root.childrenInOrder[i]
			if child then
				if GlobalStorageSiK.TerminalScroll.isVanillaScrollBar(child) then
					disposeUiChild(root, child)
				else
					GlobalStorageSiK.TerminalScroll.destroyAllScrollBarWidgets(child, depth + 1)
				end
			end
		end
	end
end

--- Limpieza puntual de ISScrollBar vanilla en el terminal (no en cada frame).
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalScroll.purgeTerminalNativeBars(terminal)
	if not terminal then
		return
	end
	GlobalStorageSiK.TerminalScroll.destroyAllScrollBarWidgets(terminal, 0)
end

--- Reposiciona la barra vertical de NeatUI a la derecha del scroll.
---@param scroll ISUIElement|nil
---@deprecated Usar suppressNativeScrollBars
function GlobalStorageSiK.TerminalScroll.layoutRightScrollBar(scroll)
	if not scroll or not GlobalStorageSiK.TerminalScroll.isNeatScroll(scroll) then
		return
	end
	local bar = scroll.vscroll or scroll.scrollBarV
	if not bar or not bar.setX then
		return
	end
	local w = scroll.width or 0
	local h = scroll.height or 0
	local bw = bar.width or SCROLLBAR_W
	bar:setX(math.max(0, w - bw))
	bar:setY(0)
	bar:setHeight(h)
	bar:setVisible(true)
end

---@param scroll ISUIElement|nil
function GlobalStorageSiK.TerminalScroll.fixNeatScrollBar(scroll)
	GlobalStorageSiK.TerminalScroll.suppressNativeScrollBars(scroll)
end

---@param scroll ISUIElement|nil
function GlobalStorageSiK.TerminalScroll.removeDuplicateScrollBars(scroll)
	GlobalStorageSiK.TerminalScroll.removeLeftGhostScrollBars(scroll)
end

---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalScroll.stripTabPanelGhosts(terminal)
	GlobalStorageSiK.TerminalScroll.purgeTerminalNativeBars(terminal)
end

---@param root ISUIElement|nil
function GlobalStorageSiK.TerminalScroll.purgeAllScrollBars(root)
	GlobalStorageSiK.TerminalScroll.destroyAllScrollBarWidgets(root, 0)
end

---@param panel ISUIElement|nil
function GlobalStorageSiK.TerminalScroll.cleanTabPanel(panel)
	GlobalStorageSiK.TerminalScroll.destroyAllScrollBarWidgets(panel, 0)
end

---@param scroll ISPanel|nil
function GlobalStorageSiK.TerminalScroll.ensureScrollBars(scroll)
	if scroll and scroll._gsScrollMode == "panel" and not scroll._gsClipInstalled then
		installViewportClip(scroll)
	end
end

---@param scroll ISPanel
---@param visible boolean|nil
function GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(scroll, visible)
	if not scroll then
		return
	end
	if GlobalStorageSiK.TerminalScroll.isNeatScroll(scroll) then
		if scroll.setShowScrollBars then
			scroll:setShowScrollBars(visible ~= false)
		end
		if scroll.setAutoHideScrollbar then
			scroll:setAutoHideScrollbar(false)
		end
		return
	end
	scroll._gsScrollBarsHidden = visible == false
end

---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalScroll.applyTabScrollVisibility(terminal)
	if not terminal then
		return
	end
	local nodesScroll = terminal.nodesPanel and terminal.nodesPanel.nodesListPanel
		and terminal.nodesPanel.nodesListPanel.nodeScroll
	local tabScrolls = {
		terminal.itemsListPanel and terminal.itemsListPanel.itemScroll,
		nodesScroll or terminal.nodesScroll,
		terminal.addonsPanel and terminal.addonsPanel.addonsScroll,
		terminal.blockedScroll,
	}
	-- Sub-pestañas de la pestaña Red (cada una tiene su propio scroll)
	if GlobalStorageSiK.TerminalNetwork and GlobalStorageSiK.TerminalNetwork.getAllTabScrolls then
		local netScrolls = GlobalStorageSiK.TerminalNetwork.getAllTabScrolls(terminal)
		for i = 1, #netScrolls do tabScrolls[#tabScrolls + 1] = netScrolls[i] end
	end
	for _, scroll in pairs(tabScrolls) do
		if scroll then
			local viewH = scroll.height or 0
			local contentH = scroll._gsContentHeight or viewH
			if scroll._gsScrollMode == "neat_virtual" and scroll.dataSource then
				local ih = scroll.itemHeight or 40
				local pad = scroll.padding or 0
				contentH = math.max(viewH, #scroll.dataSource * ih + pad * 2)
			elseif scroll._gsScrollMode == "neat" and scroll.getScrollHeight then
				local ok, sh = pcall(function()
					return scroll:getScrollHeight()
				end)
				if ok and sh and sh > contentH then
					contentH = sh
				end
			end
			GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(scroll, contentH > viewH + 2)
		end
	end
end

---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalScroll.stripTerminalTree(terminal)
	if not terminal then
		return
	end
	local nodesScroll = terminal.nodesPanel and terminal.nodesPanel.nodesListPanel
		and terminal.nodesPanel.nodesListPanel.nodeScroll
	local scrolls = {
		terminal.itemsListPanel and terminal.itemsListPanel.itemScroll,
		nodesScroll or terminal.nodesScroll,
		terminal.addonsPanel and terminal.addonsPanel.addonsScroll,
	}
	if GlobalStorageSiK.TerminalNetwork and GlobalStorageSiK.TerminalNetwork.getAllTabScrolls then
		local netScrolls = GlobalStorageSiK.TerminalNetwork.getAllTabScrolls(terminal)
		for i = 1, #netScrolls do scrolls[#scrolls + 1] = netScrolls[i] end
	end
	for i = 1, #scrolls do
		local scroll = scrolls[i]
		if scroll then
			if scroll._gsScrollMode == "panel" then
				GlobalStorageSiK.TerminalScroll.applyPanelOffset(scroll)
			end
		end
	end
	GlobalStorageSiK.TerminalScroll.applyTabScrollVisibility(terminal)
end

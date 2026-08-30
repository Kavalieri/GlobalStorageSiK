--[[
	GlobalStorageSiK - Motor de scroll SiK UI
	Autor: SiK
	Fecha: 2025-06-25
	Descripción:
	  mode "panel"       -> ISPanel + contentPanel + barra SiK UI
	  mode "rows"        -> pool manual acotado
	  mode "sik_virtual" -> lista virtual propia con pool reutilizable
	El contrato no depende de clases de scroll externas.
]]

require "ISUI/ISPanel"
require "GS_SiK_UI_Core"
if not GlobalStorageSiK.SiK_UI.Metrics then require "GS_SiK_UI_Metrics" end
if not GlobalStorageSiK.SiK_UI.Block then require "GS_SiK_UI_Block" end

GlobalStorageSiK.TerminalScroll = GlobalStorageSiK.TerminalScroll or {}

local BLOCK = GlobalStorageSiK.SiK_UI.Block
local TOKENS = GlobalStorageSiK.SiK_UI.Metrics.tokens()
local SCROLLBAR_W = TOKENS.scrollBarWidth
local WHEEL_STEP = 40
local TAB_BOTTOM_INSET = 32
local LIST_BOTTOM_GAP = 12
local CONTENT_BOTTOM_PAD = 24
local THUMB_MIN_H = 22

local function blockContentRect(scroll, contentHeight)
	return BLOCK.resolveContentRect({
		x = 0, y = 0, w = scroll and scroll.width or 0, h = scroll and scroll.height or 0,
	}, { scrollable = true, contentHeight = contentHeight or (scroll and scroll._gsContentHeight) or 0 })
end

local function scrollBarRect(scroll)
	return BLOCK.resolveScrollBarRect({
		x = 0, y = 0, w = scroll and scroll.width or 0, h = scroll and scroll.height or 0,
	}, { scrollable = true, contentHeight = (scroll and scroll._gsContentHeight) or 0 })
end

local function notifyContentRectChanged(scroll, previous, current, reason)
	if not scroll or not current then
		return
	end
	if scroll.contentPanel then
		scroll.contentPanel:setX(current.x)
		scroll.contentPanel:setWidth(current.w)
		scroll.contentPanel:setHeight(math.max(current.h, scroll._gsContentHeight or current.h))
	end
	if type(scroll._gsOnContentRectChanged) == "function" and not scroll._gsNotifyingContentRect then
		scroll._gsNotifyingContentRect = true
		local ok, err = pcall(scroll._gsOnContentRectChanged, scroll, current, previous, reason)
		scroll._gsNotifyingContentRect = false
		if not ok and GlobalStorageSiK.Log then
			GlobalStorageSiK.Log.error("SiKUIScroll", "content rect callback failed", tostring(err))
		end
	end
end

local function bindBlockGeometry(scroll, reason)
	local previous = scroll and scroll._sikBlockContentRect or nil
	local current, changed = BLOCK.bindScrollable(scroll, {
		contentHeight = scroll and scroll._gsContentHeight or 0,
	})
	if scroll and current then
		scroll._gsScrollBarsHidden = not current.overflow
	end
	if changed then
		notifyContentRectChanged(scroll, previous, current, reason)
	elseif scroll and scroll.contentPanel and current then
		scroll.contentPanel:setHeight(math.max(current.h, scroll._gsContentHeight or current.h))
	end
	return current, changed
end

local function applyScrollStyle(scroll)
	scroll.drawBackground = false
	scroll.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	scroll.borderColor = { r = 0, g = 0, b = 0, a = 0 }
end

---@param scroll ISPanel
local function maxScrollOffset(scroll)
	local viewH = blockContentRect(scroll).h
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
			local rect = blockContentRect(self)
			self:setStencilRect(rect.x, rect.y, rect.w, rect.h)
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

--- Dibuja la barra vertical propia de SiK UI.
---@param scroll ISPanel|nil
function GlobalStorageSiK.TerminalScroll.drawScrollBar(scroll)
	if not scroll or scroll._gsScrollBarsHidden then
		return
	end
	local content = blockContentRect(scroll)
	if not content.overflow then
		return
	end
	local bar = scrollBarRect(scroll)
	local viewH = bar.h
	local contentH = scroll._gsContentHeight or viewH
	if scroll._gsScrollMode == "sik_virtual" and scroll.dataSource then
		local ih = scroll.itemHeight or 40
		local pad = scroll.padding or 0
		contentH = math.max(viewH, #scroll.dataSource * ih + pad * 2)
	end
	local trackX = bar.x
	scroll:drawRect(trackX, bar.y, SCROLLBAR_W, viewH, 0.25, 0.06, 0.06, 0.06)
	local ratio = viewH / contentH
	local thumbH = math.max(THUMB_MIN_H, math.floor(viewH * ratio))
	local maxOff = maxScrollOffset(scroll)
	local offset = scroll._gsScrollOffset or 0
	local thumbY = bar.y
	if maxOff > 0 then
		thumbY = bar.y + math.floor((offset / maxOff) * (viewH - thumbH))
	end
	local thumbW = math.max(6, SCROLLBAR_W - 6)
	local thumbX = trackX + math.floor((SCROLLBAR_W - thumbW) / 2)
	local active = scroll._gsDraggingScroll == true
	local mouseX = scroll.getMouseX and scroll:getMouseX() or -1
	local hover = scroll.isMouseOver and scroll:isMouseOver()
		and mouseX >= bar.x and mouseX < bar.x + bar.w
	local alpha = active and 1 or (hover and 0.92 or 0.76)
	scroll:drawRect(thumbX, thumbY, thumbW, thumbH, alpha, 0.42, 0.46, 0.52)
	scroll:drawRectBorder(thumbX, thumbY, thumbW, thumbH, 0.9, 0.58, 0.62, 0.68)
end

---@param scroll ISPanel|nil
---@param x number
---@return boolean
local function isOnScrollTrack(scroll, x)
	if not scroll then
		return false
	end
	if scroll._gsScrollBarsHidden or not blockContentRect(scroll).overflow then
		return false
	end
	local bar = scrollBarRect(scroll)
	return x >= bar.x and x < bar.x + bar.w
end

---@param scroll ISPanel
---@param localY number
local function offsetFromTrackY(scroll, localY)
	local bar = scrollBarRect(scroll)
	local viewH = bar.h
	local contentH = scroll._gsContentHeight or viewH
	local maxOff = maxScrollOffset(scroll)
	if maxOff <= 0 then
		return 0
	end
	local ratio = math.max(0, math.min(1, (localY - bar.y) / math.max(1, viewH)))
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

--- Filas de pool necesarias para un viewport, incluidas las filas de guarda.
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

--- Posiciona un hijo en coordenadas de contenido.
---@param scroll ISPanel|nil
---@param child ISUIElement|nil
---@param contentY number
function GlobalStorageSiK.TerminalScroll.setContentY(scroll, child, contentY)
	if not scroll or not child or not child.setY then
		return
	end
	child:setY(contentY)
end

--- Posiciona un hijo en X de contenido.
---@param scroll ISPanel|nil
---@param child ISUIElement|nil
---@param contentX number
function GlobalStorageSiK.TerminalScroll.setContentX(scroll, child, contentX)
	if not scroll or not child or not child.setX then
		return
	end
	child:setX(contentX)
end

---@param scroll ISPanel|nil
---@return number
function GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
	if not scroll then
		return 0
	end
	return scroll._gsScrollOffset or 0
end

--- Desplaza contentPanel (modo panel).
---@param scroll ISPanel
function GlobalStorageSiK.TerminalScroll.applyPanelOffset(scroll)
	if not scroll then
		return
	end
	if scroll._gsScrollMode ~= "panel" or not scroll.contentPanel then
		return
	end
	local rect = blockContentRect(scroll)
	scroll.contentPanel:setX(rect.x)
	scroll.contentPanel:setY(rect.y - (scroll._gsScrollOffset or 0))
end

---@param scroll ISPanel|nil
---@param offset number
function GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, offset)
	if not scroll then
		return
	end
	offset = math.max(0, offset or 0)
	offset = math.min(offset, maxScrollOffset(scroll))
	scroll._gsScrollOffset = offset
	if scroll._gsScrollMode == "panel" then
		GlobalStorageSiK.TerminalScroll.applyPanelOffset(scroll)
	elseif scroll._gsScrollMode == "sik_virtual" and scroll.refreshItems then
		scroll:refreshItems()
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

--- Instala el contrato de lista virtual SiK UI sobre un scroll de filas.
---@param scroll ISPanel
---@param itemHeight number
---@param padding number
local function installVirtualListApi(scroll, itemHeight, padding)
	scroll._gsScrollMode = "sik_virtual"
	scroll.itemHeight = math.max(1, itemHeight or 40)
	scroll.padding = math.max(0, padding or 0)
	scroll.dataSource = {}
	scroll.itemPool = {}
	scroll.visibleStartIndex = 0
	scroll.visibleEndIndex = 0

	function scroll:setConfig(nextItemHeight, nextPadding)
                self.itemHeight = math.max(1, nextItemHeight or self.itemHeight or 40)
                self.padding = math.max(0, nextPadding or 0)
                self._gsContentHeight = #self.dataSource * self.itemHeight + self.padding * 2
		bindBlockGeometry(self, "config")
                GlobalStorageSiK.TerminalScroll.setScrollOffset(
                        self, GlobalStorageSiK.TerminalScroll.getScrollOffset(self))
	end

	function scroll:setOnCreateItem(callback)
		self.onCreateItem = callback
		self:refreshItems()
	end

	function scroll:setOnUpdateItem(callback)
		self.onUpdateItem = callback
		self:refreshItems()
	end

	function scroll:ensureItemPool()
		if type(self.onCreateItem) ~= "function" then
			return
		end
		local needed = GlobalStorageSiK.TerminalScroll.rowPoolSizeForViewport(
			blockContentRect(self).h, self.itemHeight, 2)
		local before = #self.itemPool
		while #self.itemPool < needed do
			local row = self.onCreateItem()
			if not row then
				break
			end
			row._gsVirtualRow = true
			row:setVisible(false)
			GlobalStorageSiK.TerminalScroll.addChild(self, row)
			row.onMouseWheel = function(_, del)
				return self:onMouseWheel(del)
			end
			self.itemPool[#self.itemPool + 1] = row
		end
		-- dev36 (debug SiK UI): crecer el pool es un evento raro (primera
		-- construccion o resize a un viewport mayor), nunca por fotograma -
		-- seguro loguearlo siempre que ocurra de verdad.
		if #self.itemPool ~= before then
			GlobalStorageSiK.Log.debug("SiKUIScroll", "ensureItemPool grow",
				string.format("%d->%d needed=%d viewport=%d rowH=%d", before, #self.itemPool, needed,
					self.height or self.itemHeight, self.itemHeight))
		end
	end

	function scroll:refreshItems()
		self:ensureItemPool()
		local data = self.dataSource or {}
		local rowH = math.max(1, self.itemHeight or 1)
		local offset = GlobalStorageSiK.TerminalScroll.getScrollOffset(self)
		local contentOffset = math.max(0, offset - (self.padding or 0))
		local firstIndex = math.floor(contentOffset / rowH) + 1
		local rect = blockContentRect(self)
		local rowY = rect.y + (self.padding or 0) + (firstIndex - 1) * rowH - offset
		local rowW = rect.w
		local lastIndex = math.min(#data, firstIndex + #self.itemPool - 1)
		self.visibleStartIndex = #data > 0 and firstIndex or 0
		self.visibleEndIndex = #data > 0 and lastIndex or 0
		for i = 1, #self.itemPool do
			local row = self.itemPool[i]
			local dataIndex = firstIndex + i - 1
			local value = data[dataIndex]
			if value then
				row:setX(rect.x)
				row:setY(rowY + (i - 1) * rowH)
				row:setWidth(rowW)
				row:setHeight(rowH)
				row.rowIndex = dataIndex
				if type(self.onUpdateItem) == "function" then
					self.onUpdateItem(row, value, dataIndex)
				end
				row:setVisible(true)
			else
				row.rowIndex = nil
				row:setVisible(false)
			end
		end
	end

	function scroll:setDataSource(data, preserveOffset)
                local saved = preserveOffset and GlobalStorageSiK.TerminalScroll.getScrollOffset(self) or 0
                self.dataSource = type(data) == "table" and data or {}
                self._gsContentHeight = #self.dataSource * self.itemHeight + self.padding * 2
		bindBlockGeometry(self, "content")
                self._gsScrollOffset = math.max(0, math.min(saved, maxScrollOffset(self)))
                GlobalStorageSiK.Log.debug("SiKUIScroll", "setDataSource",
                        string.format("items=%d preserveOffset=%s offset=%d->%d", #self.dataSource,
                                tostring(preserveOffset == true), saved, self._gsScrollOffset))
                self:refreshItems()
        end

	GlobalStorageSiK.TerminalScroll.bindScrollEvents(scroll, function()
		scroll:refreshItems()
	end)
end

--- Crea una lista virtual propia SiK UI con pool de filas reutilizable.
---@param parent ISUIElement
---@param x number
---@param y number
---@param w number
---@param h number
---@param itemHeight number
---@param padding number|nil
---@return ISPanel
function GlobalStorageSiK.TerminalScroll.createVirtual(parent, x, y, w, h, itemHeight, padding)
	local scroll = GlobalStorageSiK.TerminalScroll.createLegacy(parent, x, y, w, h, "sik_virtual")
	installVirtualListApi(scroll, itemHeight, padding or 0)
	return scroll
end

GlobalStorageSiK.SiK_UI.VirtualList = GlobalStorageSiK.SiK_UI.VirtualList or {}
GlobalStorageSiK.SiK_UI.VirtualList.create = GlobalStorageSiK.TerminalScroll.createVirtual

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
	scroll._gsContentHeight = 0
	bindBlockGeometry(scroll, "create")
	if mode == "rows" then
		scroll._gsVirtualItems = true
	end

	if mode == "panel" then
		local rect = blockContentRect(scroll, h)
		scroll.contentPanel = ISPanel:new(rect.x, rect.y, rect.w, rect.h)
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

--- Crea scroll de panel o filas usando siempre el motor propio SiK UI.
---@param parent ISUIElement
---@param x number
---@param y number
---@param w number
---@param h number
---@param mode string|nil "panel" (default) o "rows"
---@return ISPanel|ISUIElement
function GlobalStorageSiK.TerminalScroll.create(parent, x, y, w, h, mode)
	mode = mode or "panel"
	return GlobalStorageSiK.TerminalScroll.createLegacy(parent, x, y, w, h, mode)
end

--- Scroll con hijos clicables (botones, filas, combos).
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

	if scroll._gsScrollMode == "sik_virtual" then
		if scroll.setDataSource then
			scroll:setDataSource({}, preserveOffset == true)
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
	if scroll._gsScrollMode == "sik_virtual" then
		scroll._gsContentHeight = #(scroll.dataSource or {}) * (scroll.itemHeight or 1)
			+ (scroll.padding or 0) * 2
		bindBlockGeometry(scroll, "content")
		GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, saved)
		return
	end
	bindBlockGeometry(scroll, "content")
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, saved)
end

---@param scroll ISPanel
---@return number
function GlobalStorageSiK.TerminalScroll.contentWidth(scroll)
	if not scroll then
		return 0
	end
	return blockContentRect(scroll).w
end

--- Rectangulo canonico que consumen lista, tabla, formulario y tarjeta.
---@param scroll ISPanel|nil
---@return table
function GlobalStorageSiK.TerminalScroll.contentRect(scroll)
	if not scroll then
		return { x = 0, y = 0, w = 0, h = 0, scrollGutter = 0, overflow = false }
	end
	return blockContentRect(scroll)
end

--- Notifica al consumidor solo cuando cambia el contentRect (resize u overflow).
--- El callback debe relayout, nunca reconstruir por frame.
---@param scroll ISPanel|nil
---@param callback function|nil fn(scroll, currentRect, previousRect, reason)
function GlobalStorageSiK.TerminalScroll.setOnContentRectChanged(scroll, callback)
	if not scroll then
		return
	end
	scroll._gsOnContentRectChanged = type(callback) == "function" and callback or nil
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
	bindBlockGeometry(scroll, "resize")
	if scroll._gsScrollMode == "sik_virtual" then
		if scroll.ensureItemPool then
			scroll:ensureItemPool()
		end
		GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, saved)
		return
	end
	GlobalStorageSiK.TerminalScroll.setScrollOffset(scroll, saved)
end

---@param parent ISUIElement
---@param child ISUIElement
local function disposeUiChild(parent, child)
	GlobalStorageSiK.TerminalScroll.disposeChild(parent, child)
end

--- Barra vanilla de PZ huérfana.
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

--- Elimina solo ISScrollBar vanilla huérfanas.
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
		if child and child.childrenInOrder then
			GlobalStorageSiK.TerminalScroll.removeLeftGhostScrollBars(child, depth + 1)
		end
	end
end

--- Elimina ISScrollBar vanilla del subárbol.
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
function GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(scroll, _visible)
	if not scroll then
		return
	end
	-- Alias legacy: la geometria real prevalece sobre estimaciones del consumidor.
	-- Solo overflow puede mostrar la barra; no existe reserva manual ni umbral +2.
	local overflow = blockContentRect(scroll).overflow
	scroll._gsScrollBarsHidden = not overflow
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
	-- Scroll único de la pestaña Red ("Zonas y nodos")
	if GlobalStorageSiK.TerminalNetwork and GlobalStorageSiK.TerminalNetwork.getAllTabScrolls then
		local netScrolls = GlobalStorageSiK.TerminalNetwork.getAllTabScrolls(terminal)
		for i = 1, #netScrolls do tabScrolls[#tabScrolls + 1] = netScrolls[i] end
	end
	-- Sub-pestañas de la pestaña Configuración (Admin | Estado), cada una con su propio scroll
	if GlobalStorageSiK.TerminalOptions and GlobalStorageSiK.TerminalOptions.getAllTabScrolls then
		local optScrolls = GlobalStorageSiK.TerminalOptions.getAllTabScrolls(terminal)
		for i = 1, #optScrolls do tabScrolls[#tabScrolls + 1] = optScrolls[i] end
	end
	for _, scroll in pairs(tabScrolls) do
		if scroll then
			local viewH = blockContentRect(scroll).h
			local contentH = scroll._gsContentHeight or viewH
			if scroll._gsScrollMode == "sik_virtual" and scroll.dataSource then
				local ih = scroll.itemHeight or 40
				local pad = scroll.padding or 0
				contentH = math.max(viewH, #scroll.dataSource * ih + pad * 2)
			end
			GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(scroll, contentH > viewH)
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
	if GlobalStorageSiK.TerminalOptions and GlobalStorageSiK.TerminalOptions.getAllTabScrolls then
		local optScrolls = GlobalStorageSiK.TerminalOptions.getAllTabScrolls(terminal)
		for i = 1, #optScrolls do scrolls[#scrolls + 1] = optScrolls[i] end
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

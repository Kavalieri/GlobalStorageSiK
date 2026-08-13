--[[
	GlobalStorageSiK - Utilidades de menú contextual sobre terminal
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Evita que el terminal alwaysOnTop bloquee interacción con ISContextMenu.
]]

GlobalStorageSiK.ContextMenuUi = {}

--- Indica si hay algún menú contextual visible.
---@return boolean
function GlobalStorageSiK.ContextMenuUi.isAnyContextMenuOpen()
	if not UIManager or not UIManager.getUI then
		return false
	end
	local uiList = UIManager:getUI()
	if not uiList then
		return false
	end
	for i = 0, uiList:size() - 1 do
		local ui = uiList:get(i)
		if ui and ui.isVisible and ui:isVisible() then
			if ui.Type == "ISContextMenu" then
				return true
			end
			if ui.javaObject and ui.javaObject.getType and ui.javaObject:getType() == "ISContextMenu" then
				return true
			end
		end
	end
	return false
end

--- Oculta temporalmente el terminal para que el menú reciba clics.
---@param terminal GS_TerminalUI|nil
---@return table|nil state
function GlobalStorageSiK.ContextMenuUi.prepareTerminal(terminal)
	if not terminal then
		return nil
	end
	local state = {
		ui = terminal,
		wasVisible = terminal.getIsVisible and terminal:getIsVisible() or true,
		wasAlwaysOnTop = terminal.isAlwaysOnTop and terminal:isAlwaysOnTop() or false,
	}
	terminal.gsContextMenuOpen = true
	if terminal.setAlwaysOnTop then
		terminal:setAlwaysOnTop(false)
	end
	-- No ocultar el terminal: rompe submenús de segundo nivel del menú contextual.
	if terminal.setCapture then
		terminal:setCapture(false)
	end
	return state
end

--- Eleva menú contextual al frente.
---@param cm ISContextMenu|nil
function GlobalStorageSiK.ContextMenuUi.raiseMenu(cm)
	if not cm then
		return
	end
	pcall(function()
		if cm.setAlwaysOnTop then
			cm:setAlwaysOnTop(true)
		end
		if cm.bringToTop then
			cm:bringToTop()
		end
		if UIManager and UIManager.pushToTop then
			UIManager:pushToTop(cm)
		end
	end)
end

--- Restaura terminal tras cerrar el menú contextual.
---@param state table|nil
function GlobalStorageSiK.ContextMenuUi.scheduleTerminalRestore(state)
	if not state or not state.ui then
		return
	end
	local ticks = 0
	local function tick()
		ticks = ticks + 1
		if not GlobalStorageSiK.ContextMenuUi.isAnyContextMenuOpen() or ticks > 300 then
			local ui = state.ui
			if state.wasVisible and ui.setVisible then
				ui:setVisible(true)
			end
			if state.wasAlwaysOnTop and ui.setAlwaysOnTop then
				ui:setAlwaysOnTop(true)
			end
			ui.gsContextMenuOpen = false
			if ui.bringToTop then
				ui:bringToTop()
			end
			Events.OnTick.Remove(tick)
		end
	end
	Events.OnTick.Add(tick)
end

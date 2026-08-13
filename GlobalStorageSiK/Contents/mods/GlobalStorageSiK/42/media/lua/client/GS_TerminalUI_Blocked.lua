--[[
	GlobalStorageSiK - API compatibilidad ventana bloqueada
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Delega en GS_TerminalUI (pestaña bloqueo integrada).
]]

require "GS_TerminalUI_BlockedPanel"

GlobalStorageSiK.TerminalBlockedUI = {}
GlobalStorageSiK.TerminalBlockedUI.instance = nil

---@param panel ISPanel|nil
local function safeClosePanel(panel)
	if not panel or not panel.onClose then
		return
	end
	pcall(function()
		panel:onClose()
	end)
end

--- Abre o refresca el terminal en modo bloqueado (misma ventana que la UI principal).
---@param state table|string|nil
---@param keepX number|nil
---@param keepY number|nil
---@param keepW number|nil
---@param keepH number|nil
function GlobalStorageSiK.TerminalBlockedUI.showFromMain(state, keepX, keepY, keepW, keepH)
	if type(state) == "string" then
		state = { reason = state }
	end
	if GlobalStorageSiK.TerminalBlockedPanel and GlobalStorageSiK.TerminalBlockedPanel.ensureEvents then
		GlobalStorageSiK.TerminalBlockedPanel.ensureEvents()
	end

	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	-- Singleton estricto: si ya existe instancia, siempre reutilizar (nunca crear segunda ventana).
	if ui then
		if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.applyAccessMode then
			GlobalStorageSiK.TerminalTabs.applyAccessMode(ui, "blocked", state or {})
		end
		ui:setVisible(true)
		ui:bringToTop()
		GlobalStorageSiK.TerminalBlockedUI.instance = ui
		return
	end

	if not GS_TerminalUI then
		print("[GlobalStorageSiK] GS_TerminalUI class missing for blocked mode")
		return
	end

	local sw = getCore():getScreenWidth()
	local sh = getCore():getScreenHeight()
	local w = keepW or math.min(960, math.max(820, math.floor(sw * 0.78)))
	local h = keepH or math.min(900, math.max(680, math.floor(sh * 0.86)))
	local x = keepX or ((sw - w) / 2)
	local y = keepY or ((sh - h) / 2)
	ui = GS_TerminalUI:new(x, y, w, h)
	ui.terminalState = {}
	ui:initialise()
	ui:addToUIManager()
	GlobalStorageSiK.TerminalUI.instance = ui
	if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.applyAccessMode then
		GlobalStorageSiK.TerminalTabs.applyAccessMode(ui, "blocked", state or {})
	end
	GlobalStorageSiK.TerminalBlockedUI.instance = ui
end

---@param state table|string|nil
function GlobalStorageSiK.TerminalBlockedUI.show(state)
	GlobalStorageSiK.TerminalBlockedUI.showFromMain(state, nil, nil, nil, nil)
end

---@param state table|nil
function GlobalStorageSiK.TerminalBlockedUI.refresh(state)
	local ui = GlobalStorageSiK.TerminalBlockedUI.instance
		or (GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance)
	if not ui or ui.accessMode ~= "blocked" then
		return
	end
	if state then
		ui.blockedState = state
	end
	if GlobalStorageSiK.TerminalBlockedPanel and GlobalStorageSiK.TerminalBlockedPanel.refresh then
		GlobalStorageSiK.TerminalBlockedPanel.refresh(ui, ui.blockedState)
	end
end

function GlobalStorageSiK.TerminalBlockedUI.ensureEvents()
	if GlobalStorageSiK.TerminalBlockedPanel and GlobalStorageSiK.TerminalBlockedPanel.ensureEvents then
		GlobalStorageSiK.TerminalBlockedPanel.ensureEvents()
	end
end

--[[
	GlobalStorageSiK - API compatibilidad ventana bloqueada
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Delega en GS_TerminalUI (pestaña bloqueo integrada).
]]

require "GS_TerminalUI_BlockedPanel"
require "GS_Log"
require "GS_SiK_UI_Window"

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

	local playerNum = tonumber(state and state.playerNum) or 0
	GlobalStorageSiK.TerminalBlockedUI.instances = GlobalStorageSiK.TerminalBlockedUI.instances or {}
	local ui = nil
	if GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.getInstanceForPlayer then
		ui = GlobalStorageSiK.TerminalUI.getInstanceForPlayer(playerNum)
	elseif GlobalStorageSiK.TerminalUI then
		ui = GlobalStorageSiK.TerminalUI.instance
	end
	-- Singleton estricto: si ya existe instancia, siempre reutilizar (nunca crear segunda ventana).
	if ui then
		if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.applyAccessMode then
			GlobalStorageSiK.TerminalTabs.applyAccessMode(ui, "blocked", state or {})
		end
		ui:setVisible(true)
		ui:bringToTop()
		GlobalStorageSiK.TerminalBlockedUI.instance = ui
		GlobalStorageSiK.TerminalBlockedUI.instances[playerNum] = ui
		return
	end

	if not GS_TerminalUI then
		GlobalStorageSiK.Log.error("TerminalUI", "GS_TerminalUI class missing for blocked mode")
		return
	end

	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer
		and GlobalStorageSiK.NetClient.getPlayer(playerNum) or (playerNum == 0 and getPlayer and getPlayer() or nil)
	local viewport = GlobalStorageSiK.SiK_UI.Viewport.resolve(playerNum)
	local rect
	if keepX or keepY or keepW or keepH then
		rect = GlobalStorageSiK.SiK_UI.Window.resolveProfile(viewport.profile, viewport, {
			playerNum = playerNum, x = keepX, y = keepY, width = keepW, height = keepH,
		})
	else
		rect = GlobalStorageSiK.SiK_UI.Window.recall("terminal-shell", playerNum, viewport)
			or GlobalStorageSiK.SiK_UI.Window.resolveProfile(viewport.profile, viewport, {
				playerNum = playerNum,
			})
	end
	ui = GS_TerminalUI:new(rect.x, rect.y, rect.w, rect.h, playerNum)
	ui._sikWindowProfile = rect.profile
	ui.terminalState = {}
	ui:initialise()
	ui:addToUIManager()
	if GlobalStorageSiK.TerminalUI.setInstanceForPlayer then
		GlobalStorageSiK.TerminalUI.setInstanceForPlayer(playerNum, ui)
	else
		GlobalStorageSiK.TerminalUI.instance = ui
	end
	if GlobalStorageSiK.TerminalTabs and GlobalStorageSiK.TerminalTabs.applyAccessMode then
		GlobalStorageSiK.TerminalTabs.applyAccessMode(ui, "blocked", state or {})
	end
	GlobalStorageSiK.TerminalBlockedUI.instance = ui
	GlobalStorageSiK.TerminalBlockedUI.instances[playerNum] = ui
end

---@param state table|string|nil
function GlobalStorageSiK.TerminalBlockedUI.show(state)
	GlobalStorageSiK.TerminalBlockedUI.showFromMain(state, nil, nil, nil, nil)
end

---@param state table|nil
function GlobalStorageSiK.TerminalBlockedUI.refresh(state)
	local playerNum = tonumber(state and state.playerNum) or 0
	local ui = nil
	if GlobalStorageSiK.TerminalBlockedUI.instances then
		ui = GlobalStorageSiK.TerminalBlockedUI.instances[playerNum]
	elseif playerNum == 0 then
		ui = GlobalStorageSiK.TerminalBlockedUI.instance
			or (GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance)
	end
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

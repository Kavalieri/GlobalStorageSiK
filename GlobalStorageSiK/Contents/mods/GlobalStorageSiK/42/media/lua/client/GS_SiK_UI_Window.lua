--[[
	GlobalStorageSiK - Modelos reutilizables de ventana SiK UI
	Unifica modal de tarea, confirmacion y editor grande redimensionable.
]]

require "ISUI/ISModalDialog"
require "GS_SiK_UI_Core"

local SiK_UI = GlobalStorageSiK.SiK_UI
SiK_UI.Modal = SiK_UI.Modal or {}
SiK_UI.Window = SiK_UI.Window or {}

local Modal = SiK_UI.Modal
local Window = SiK_UI.Window
local rememberedGeometry = {}

local function installEscape(panel, onClose)
	if not panel or panel._sikEscapeInstalled then return end
	panel._sikEscapeInstalled = true
	local previous = panel.onKeyRelease
	panel.onKeyRelease = function(self, key)
		local escapeKey = Keyboard and Keyboard.KEY_ESCAPE or 1
		if key == escapeKey then
			onClose(self)
			return true
		end
		if previous then return previous(self, key) end
		return false
	end
end
Window.installEscape = installEscape

--- Aplica el modelo de modal mediano de una sola tarea.
function Modal.apply(panel, onClose, options)
	if not panel then return panel end
	options = options or {}
	local close = onClose or function(target)
		if target.destroy then target:destroy()
		elseif target.setVisible then target:setVisible(false) end
	end
	panel.headerHeight = options.headerHeight or panel.headerHeight
	SiK_UI.setupModalPanel(panel, function() close(panel) end, options.padding)
	installEscape(panel, close)
	return panel
end

--- Fija el alto desde el último Y real y centra solo después de dimensionar.
function Modal.fitContent(panel, contentBottomY, options)
	if not panel then return panel end
	options = options or {}
	local bottomPadding = tonumber(options.bottomPadding) or panel.padding or 14
	panel:setHeight(math.max(tonumber(options.minHeight) or 80,
		math.floor((tonumber(contentBottomY) or 0) + bottomPadding)))
	SiK_UI.layoutModalFrame(panel, panel.padding)
	if options.center ~= false then SiK_UI.centerModal(panel) end
	return panel
end

--- Confirmacion Si/No coherente, dimensionada a partir del texto envuelto.
function Modal.confirm(message, onYes, options)
	options = options or {}
	local width = tonumber(options.width) or SiK_UI.STANDARD_MODAL_W
	local pad = tonumber(options.padding) or 18
	local font = options.font or UIFont.Small
	local lines = SiK_UI.wrapTextLines(tostring(message or ""), width - pad * 2, font)
	local lineH = getTextManager():getFontHeight(font) + 2
	local height = math.max(tonumber(options.minHeight) or 140, 104 + #lines * lineH)
	local function onResult(_, button)
		if button and button.internal == "YES" then
			if onYes then onYes() end
		elseif options.onNo then
			options.onNo()
		end
	end
	local modal = ISModalDialog:new(0, 0, width, height, message, true, nil, onResult, nil)
	modal:initialise()
	modal:addToUIManager()
	SiK_UI.centerModal(modal)
	if modal.setAlwaysOnTop then modal:setAlwaysOnTop(true) end
	if modal.bringToTop then modal:bringToTop() end
	return modal
end

--- Geometria del modelo grande redimensionable. `key` activa memoria local
--- opcional; nunca se transmite al servidor ni se mezcla entre ventanas.
function Window.editorGeometry(terminal, key, options)
	options = options or {}
	local saved = key and rememberedGeometry[key] or nil
	if saved then return saved.x, saved.y, saved.w, saved.h end
	local w, h = SiK_UI.resolveEditorWindowSize()
	w = tonumber(options.width) or w
	h = tonumber(options.height) or h
	local x, y = SiK_UI.resolveEditorWindowPos(terminal, w, h)
	return x, y, w, h
end

function Window.remember(panel, key)
	if not panel or not key then return end
	rememberedGeometry[key] = {
		x = panel:getX(), y = panel:getY(), w = panel:getWidth(), h = panel:getHeight(),
	}
end

function Window.applyEditor(panel, onClose, key, options)
	options = options or {}
	Modal.apply(panel, function(target)
		Window.remember(target, key)
		if onClose then onClose(target)
		elseif target.destroy then target:destroy()
		else target:setVisible(false) end
	end, options)
	panel.resizable = true
	panel.minimumWidth = tonumber(options.minWidth) or SiK_UI.EDITOR_MIN_W
	panel.minimumHeight = tonumber(options.minHeight) or SiK_UI.EDITOR_MIN_H
	return panel
end

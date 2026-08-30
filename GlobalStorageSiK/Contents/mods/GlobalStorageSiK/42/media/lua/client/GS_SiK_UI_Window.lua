--[[
	GlobalStorageSiK - Responsive top-level SiK UI windows.
	Geometry is resolved against the local player's safe viewport.
]]

require "GS_SiK_UI_Core"
require "GS_SiK_UI_EscapeStack"

if not GlobalStorageSiK.SiK_UI.Metrics then require "GS_SiK_UI_Metrics" end
if not GlobalStorageSiK.SiK_UI.Viewport then pcall(require, "GS_SiK_UI_Viewport") end

local SiK_UI = GlobalStorageSiK.SiK_UI
SiK_UI.Window = SiK_UI.Window or {}
SiK_UI.Modal = SiK_UI.Modal or {}

local Window = SiK_UI.Window
local rememberedGeometry = {}

local function clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

local function copyRect(rect)
	return { x = rect.x, y = rect.y, w = rect.w, h = rect.h,
		profile = rect.profile, playerNum = rect.playerNum }
end

local function resolveViewport(viewport, options)
	if type(viewport) == "table" then return viewport end
	local playerNum = options and options.playerNum or 0
	if SiK_UI.Viewport and SiK_UI.Viewport.resolve then
		return SiK_UI.Viewport.resolve(playerNum, options and options.environment)
	end
	local width = getCore and getCore():getScreenWidth() or 1280
	local height = getCore and getCore():getScreenHeight() or 720
	return { x = 0, y = 0, w = width, h = height, playerNum = playerNum,
		profile = "standard" }
end

local function profileSpec(profileName)
	local profile = SiK_UI.Metrics.profile(profileName)
	local window = profile.window
	return {
		preferredW = window.preferredWidth, preferredH = window.preferredHeight,
		minW = window.minWidth, minH = window.minHeight,
		maxW = window.maxWidth, maxH = window.maxHeight,
	}
end

--- Interactive limits have a single owner. Profile maxima describe the
--- preferred opening size; explicit consumer maxima remain supported, while
--- an unconstrained resizable window may grow to the complete safe viewport.
function Window.resolveLimits(profileName, viewport, options)
	options = options or {}
	viewport = resolveViewport(viewport, options)
	profileName = profileName or viewport.profile or "standard"
	local spec = profileSpec(profileName)
	local availableW = math.max(0, math.floor(tonumber(viewport.w) or 0))
	local availableH = math.max(0, math.floor(tonumber(viewport.h) or 0))
	local maximumW = math.min(tonumber(options.maxWidth) or availableW, availableW)
	local maximumH = math.min(tonumber(options.maxHeight) or availableH, availableH)
	local requestedMinW = tonumber(options.minWidth or options.contentMinW) or spec.minW
	local requestedMinH = tonumber(options.minHeight or options.contentMinH) or spec.minH
	return {
		minW = math.min(requestedMinW, maximumW),
		minH = math.min(requestedMinH, maximumH),
		maxW = maximumW,
		maxH = maximumH,
		profile = profileName,
		playerNum = viewport.playerNum or options.playerNum or 0,
		viewport = viewport,
	}
end

--- Pure responsive geometry. Content minima degrade inside small viewports.
function Window.resolveProfile(profileName, viewport, options)
	options = options or {}
	viewport = resolveViewport(viewport, options)
	profileName = profileName or viewport.profile or "standard"
	local spec = profileSpec(profileName)
	local limits = Window.resolveLimits(profileName, viewport, options)
	local availableW = math.max(0, math.floor(tonumber(viewport.w) or 0))
	local availableH = math.max(0, math.floor(tonumber(viewport.h) or 0))
	local wantedW = tonumber(options.width) or math.max(spec.preferredW, limits.minW)
	local wantedH = tonumber(options.height) or math.max(spec.preferredH, limits.minH)
	local width = clamp(math.floor(wantedW), limits.minW, limits.maxW)
	local height = clamp(math.floor(wantedH), limits.minH, limits.maxH)
	local left = math.floor(tonumber(viewport.x) or 0)
	local top = math.floor(tonumber(viewport.y) or 0)
	local x = tonumber(options.x)
	local y = tonumber(options.y)
	if x == nil then x = left + math.floor((availableW - width) / 2) end
	if y == nil then y = top + math.floor((availableH - height) / 2) end
	x = clamp(math.floor(x), left, left + availableW - width)
	y = clamp(math.floor(y), top, top + availableH - height)
	return { x = x, y = y, w = width, h = height, profile = profileName,
		playerNum = viewport.playerNum or options.playerNum or 0 }
end

function Window.safeRect(playerNum, environment)
	return resolveViewport(nil, { playerNum = playerNum, environment = environment })
end

function Window.clampRect(rect, viewport)
	viewport = resolveViewport(viewport, { playerNum = rect and rect.playerNum or 0 })
	rect = rect or {}
	return Window.resolveProfile(rect.profile or viewport.profile, viewport, {
		x = rect.x, y = rect.y, width = rect.w, height = rect.h,
		playerNum = rect.playerNum, minWidth = 0, minHeight = 0,
	})
end

local function geometryKey(key, playerNum)
	if not key then return nil end
	return tostring(playerNum or 0) .. ":" .. tostring(key)
end

function Window.remember(panel, key, playerNum)
	if not panel or not key then return end
	local memoryKey = geometryKey(key, playerNum or panel.playerNum)
	rememberedGeometry[memoryKey] = {
		x = panel:getX(), y = panel:getY(), w = panel:getWidth(),
		h = panel:getHeight(), profile = panel._sikWindowProfile or "standard",
		playerNum = playerNum or panel.playerNum or 0,
	}
end

function Window.recall(key, playerNum, viewport)
	local saved = rememberedGeometry[geometryKey(key, playerNum)]
	if not saved then return nil end
	return Window.clampRect(copyRect(saved), viewport)
end

function Window.forget(key, playerNum)
	if key then rememberedGeometry[geometryKey(key, playerNum)] = nil end
end

function Window.installEscape(panel, onClose, priority)
	if not panel then return end
	SiK_UI.EscapeStack.install(panel, onClose, priority)
end

function Window.layoutHeader(panel, options)
	if not panel then return end
	options = options or {}
	panel.padding = tonumber(options.padding) or panel.padding or 14
	panel.headerHeight = tonumber(options.headerHeight) or panel.headerHeight
	SiK_UI.layoutModalFrame(panel, panel.padding)
end

local function defaultClose(target)
	if target.destroy then target:destroy()
	elseif target.setVisible then target:setVisible(false) end
end

--- Shared header, close, drag, resize, viewport and geometry-memory path.
function Window.apply(panel, onClose, key, options)
	if not panel then return panel end
	options = options or {}
	local playerNum = options.playerNum or panel.playerNum or 0
	local close = function(target)
		Window.remember(target, key, playerNum)
		if onClose then onClose(target) else defaultClose(target) end
	end
	panel._sikWindowProfile = options.profile or panel._sikWindowProfile or "standard"
	panel.playerNum = playerNum
	panel.padding = tonumber(options.padding) or panel.padding or 14
	SiK_UI.setupModalPanel(panel, function() close(panel) end, panel.padding)
	Window.installEscape(panel, close, options.escapePriority)
	panel.resizable = options.resizable ~= false
	local viewport = resolveViewport(options.viewport, {
		playerNum = playerNum, environment = options.environment,
	})
	local limits = Window.resolveLimits(panel._sikWindowProfile, viewport, options)
	panel.minimumWidth = limits.minW
	panel.minimumHeight = limits.minH
	panel.maximumWidth = limits.maxW
	panel.maximumHeight = limits.maxH
	panel._sikSafeViewport = limits.viewport
	local priorResize = panel.onResize
	panel.onResize = function(self, ...)
		Window.layoutHeader(self, options)
		if priorResize then priorResize(self, ...) end
		if options.onResize then options.onResize(self, ...) end
	end
	Window.layoutHeader(panel, options)
	return panel
end

--- Legacy editor geometry remains stable until each consumer is migrated.
function Window.editorGeometry(terminal, key, options)
	options = options or {}
	local playerNum = options.playerNum or 0
	local saved = Window.recall(key, playerNum)
	if saved then return saved.x, saved.y, saved.w, saved.h end
	local width, height = SiK_UI.resolveEditorWindowSize()
	width = tonumber(options.width) or width
	height = tonumber(options.height) or height
	local x, y = SiK_UI.resolveEditorWindowPos(terminal, width, height)
	return x, y, width, height
end

--- Compatibility name; delegates to the real shared Window path.
function Window.applyEditor(panel, onClose, key, options)
	options = options or {}
	options.profile = options.profile or "editor"
	if options.minWidth == nil then options.minWidth = SiK_UI.EDITOR_MIN_W end
	if options.minHeight == nil then options.minHeight = SiK_UI.EDITOR_MIN_H end
	return Window.apply(panel, onClose, key, options)
end

-- Existing consumers require Window and call Modal directly. Load the new
-- module lazily when that compatibility route is exercised.
local function modalProxy(name)
	return function(...)
		require "GS_SiK_UI_Modal"
		return SiK_UI.Modal[name](...)
	end
end
if not SiK_UI.Modal.apply then SiK_UI.Modal.apply = modalProxy("apply") end
if not SiK_UI.Modal.fitContent then SiK_UI.Modal.fitContent = modalProxy("fitContent") end
if not SiK_UI.Modal.confirm then SiK_UI.Modal.confirm = modalProxy("confirm") end

return Window

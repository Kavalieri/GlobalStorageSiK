local sourcePath = "GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_EquippedItemHook.lua"

local passed, failed = 0, 0
local function check(name, condition, detail)
	if condition then
		passed = passed + 1
		io.write("PASS ", name, "\n")
	else
		failed = failed + 1
		io.write("FAIL ", name, ": ", tostring(detail), "\n")
	end
end

local function readAll(path)
	local file = assert(io.open(path, "rb"))
	local source = file:read("*a")
	file:close()
	return source
end

local function countPlain(source, needle)
	local count, position = 0, 1
	while true do
		local found = source:find(needle, position, true)
		if not found then return count end
		count, position = count + 1, found + #needle
	end
end

local source = readAll(sourcePath)
check("sidebar loads the public framework", source:find('require "GS_UI_Framework"', 1, true)
	and source:find("local UI = SiK.UI", 1, true))
check("sidebar composes one panel and two icon buttons",
	countPlain(source, "UI.Controls.panel(") == 1
	and countPlain(source, "UI.Controls.iconButton(") == 1
	and countPlain(source, "UI.Menu.sideMenuExtension(") == 2)
check("sidebar has no private primitive or tooltip dependency",
	not source:find('require "ISUI/ISPanel"', 1, true)
	and not source:find("ISPanel:new", 1, true)
	and not source:find("ISToolTip", 1, true))
check("sidebar has no local texture or chrome painting",
	not source:find(":drawTexture", 1, true)
	and not source:find(":drawRect", 1, true)
	and not source:find(":drawRectBorder", 1, true))
check("sidebar delegates refresh ownership to framework lifecycle",
	countPlain(source, "UI.Lifecycle.bindHoverReveal(") == 1
	and countPlain(source, "UI.Lifecycle.own(") == 1
	and not source:find("ISEquippedItem.prerender =", 1, true)
	and not source:find("Events.OnTick", 1, true))

GlobalStorageSiK = {
	I18n = { text = function(key) return key end },
	TerminalUI = { instance = nil, requestOpen = function() end },
	TerminalRecipes = {},
	AdminDashboard = { instance = nil, show = function() end },
}

local staff, currentPlayerData = false, nil
GlobalStorageSiK.Permissions = {
	shouldEnforce = function() return true end,
	isServerStaff = function() return staff end,
}

local controlCalls = { panel = 0, iconButton = 0 }
local function setWidgetMethods(widget)
	function widget:setX(value) self.x = value end
	function widget:setY(value) self.y = value end
	function widget:setWidth(value) self.width = value end
	function widget:setHeight(value) self.height = value end
	function widget:setVisible(value) self.visible = value end
	function widget:getIsVisible() return self.visible end
	function widget:addToUIManager() self.inManager = true end
	function widget:removeFromUIManager() self.inManager = false end
	function widget:bringToTop() self.bringToTopCalls = (self.bringToTopCalls or 0) + 1 end
	function widget:isMouseOver() return self.mouseOver == true end
	return widget
end

local Controls = {}
function Controls.panel(_, options)
	controlCalls.panel = controlCalls.panel + 1
	local panel = setWidgetMethods({
		x = options.x, y = options.y, width = options.w, height = options.h,
		visible = true, children = {}, options = options,
	})
	function panel:dispose()
		if self.disposed then return false end
		self.disposed = true
		self:removeFromUIManager()
		return true
	end
	return panel
end

function Controls.iconButton(parent, options)
	controlCalls.iconButton = controlCalls.iconButton + 1
	local tooltipHandle = { hidden = 0, disposed = false }
	function tooltipHandle:hide() self.hidden = self.hidden + 1 end
	function tooltipHandle:dispose()
		if self.disposed then return false end
		self.disposed = true
		return true
	end
	local button = setWidgetMethods({
		x = options.x, y = options.y, width = options.w, height = options.h,
		visible = true, texture = options.icon, options = options,
		_sikTooltipHandle = tooltipHandle,
	})
	function button:setTexture(value) self.texture = value; return self end
	function button:dispose()
		if self.disposed then return false end
		self.disposed = true
		self._sikTooltipHandle:dispose()
		return true
	end
	button.target, button.onclick = button, function(_, self)
		return options.onClick and options.onClick(self)
	end
	parent.children[#parent.children + 1] = button
	button.parent = parent
	return button
end

local Menu = {}
function Menu.sideMenuExtension(options)
	local extension = { asset = options.asset, control = nil }
	function extension:mount(anchor)
		self.control = options.mount(anchor, {
			asset = self.asset, tooltip = options.tooltip, action = options.action,
		})
		return self.control
	end
	function extension:dispose()
		if not self.control then return false end
		options.unmount(self.control)
		self.control = nil
		return true
	end
	return extension
end

SiK = { UI = { Controls = Controls, Menu = Menu } }
package.path = "../SiKUIFramework-Repo/SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/?.lua;"
	.. package.path
require "SiK/UI/Namespace"
require "SiK/UI/Lifecycle"
package.preload["GS_UI_Framework"] = function() return SiK.UI end
package.preload["GS_I18n"] = function() return GlobalStorageSiK.I18n end
package.preload["GS_NetClient"] = function() return {} end
package.preload["GS_TerminalUI"] = function() return GlobalStorageSiK.TerminalUI end
package.preload["GS_TerminalUI_Api"] = function() return GlobalStorageSiK.TerminalUI end
package.preload["GS_TerminalUI_Blocked"] = function() return {} end
package.preload["GS_TerminalAccess"] = function() return {} end
package.preload["GS_TerminalRecipes"] = function() return GlobalStorageSiK.TerminalRecipes end
package.preload["GS_Permissions"] = function() return GlobalStorageSiK.Permissions end
package.preload["GS_AdminDashboard"] = function() return GlobalStorageSiK.AdminDashboard end

local sidebarSize, gameMode = 1, "Survival"
function getCore()
	return {
		getOptionSidebarSize = function() return sidebarSize end,
		getOptionFontSizeReal = function() return 2 end,
		getGameMode = function() return gameMode end,
	}
end
function getTexture(path) return { path = path } end
function getPlayerData() return currentPlayerData end

local gameStartHandlers, tickHandlers = {}, {}
local tickAdds, tickRemoves = 0, 0
Events = {
	OnGameStart = { Add = function(callback)
		gameStartHandlers[#gameStartHandlers + 1] = callback
	end },
	OnTick = {
		Add = function(callback)
			tickAdds = tickAdds + 1
			tickHandlers[callback] = true
		end,
		Remove = function(callback)
			tickRemoves = tickRemoves + 1
			tickHandlers[callback] = nil
		end,
	},
}

local function tick()
	local callbacks = {}
	for callback in pairs(tickHandlers) do callbacks[#callbacks + 1] = callback end
	for index = 1, #callbacks do callbacks[index]() end
end

local function tickHandlerCount()
	local count = 0
	for _ in pairs(tickHandlers) do count = count + 1 end
	return count
end

local originalCalls = { initialise = 0, prerender = 0, remove = 0, size = 0 }
ISEquippedItem = {}
function ISEquippedItem:initialise() originalCalls.initialise = originalCalls.initialise + 1 end
function ISEquippedItem:prerender() originalCalls.prerender = originalCalls.prerender + 1 end
function ISEquippedItem:removeFromUIManager() originalCalls.remove = originalCalls.remove + 1 end
function ISEquippedItem:checkSidebarSizeOption() originalCalls.size = originalCalls.size + 1 end
function ISEquippedItem:setVisible(value) self.visible = value end
function ISEquippedItem:getIsVisible() return self.visible ~= false end
function ISEquippedItem:addToUIManager() self.inManager = true end
function ISEquippedItem:getAbsoluteX() return self.absoluteX end
function ISEquippedItem:getAbsoluteY() return self.absoluteY end

dofile(sourcePath)
check("sidebar registers one startup hook", #gameStartHandlers == 1)
GlobalStorageSiK.UIHook.patchEquippedItem()

local anchorCalls = 0
local anchor = {
	x = 10, y = 20, mouseOver = false,
	getX = function(self) return self.x end,
	getY = function(self) return self.y end,
	isMouseOver = function(self) return self.mouseOver end,
	onMouseDown = function(_, x, y)
		if x == 0 and y == 0 then anchorCalls = anchorCalls + 1 end
	end,
}
local character = { getPlayerNum = function() return 0 end }
local equipped = setmetatable({ playerNum = 0, chr = character, invBtn = anchor,
	absoluteX = 100, absoluteY = 200, visible = true }, { __index = ISEquippedItem })
currentPlayerData = { equipped = equipped }
equipped:initialise()

local popup = equipped.gsInventoryPopup
local terminalButton, staffButton = popup and popup.terminalButton, popup and popup.staffButton
check("sidebar creates framework controls once", popup ~= nil
	and controlCalls.panel == 1 and controlCalls.iconButton == 2
	and #popup.children == 2)
check("sidebar initial geometry preserves vanilla anchor slot", popup.x == 110
	and popup.y == 220 and popup.width == 96 and popup.height == 36
	and terminalButton.x == 48 and terminalButton.width == 48
	and staffButton.x == 96 and staffButton.visible == false)
check("sidebar forwards its anchor slot to vanilla", popup:onMouseDown(24) == true
	and anchorCalls == 1 and popup:onMouseDown(50) == false)
check("sidebar owns exactly one active refresh handler", tickAdds == 1
	and tickHandlerCount() == 1 and popup._sikOwnedResources
	and #popup._sikOwnedResources == 1)

anchor.mouseOver = true
equipped:prerender()
local prerenderIsVanillaOnly = popup.visible == false and originalCalls.prerender == 1
equipped.absoluteX, equipped.absoluteY = 130, 240
tick()
local visibleOverAnchor = popup.visible == true and popup.bringToTopCalls == 1
	and popup.x == 140 and popup.y == 260
anchor.mouseOver = false
popup.mouseOver = true
tick()
local visibleOverPopup = popup.visible == true
popup.mouseOver = false
for _ = 1, 5 do tick() end
local hiddenAway = popup.visible == false
	and terminalButton._sikTooltipHandle.hidden > 0
	and staffButton._sikTooltipHandle.hidden > 0
GlobalStorageSiK.TerminalUI.instance = { getIsVisible = function() return true end }
tick()
local visibleWithTerminal = popup.visible == true
gameMode = "Tutorial"
tick()
local hiddenInTutorial = popup.visible == false
gameMode = "Survival"
check("sidebar refreshes geometry and visibility only from lifecycle tick",
	prerenderIsVanillaOnly and visibleOverAnchor and visibleOverPopup and hiddenAway
	and visibleWithTerminal and hiddenInTutorial)

equipped:setVisible(false)
local unregisteredWhileHidden = tickHandlerCount() == 0 and tickRemoves == 1
equipped:setVisible(true); equipped:setVisible(true)
check("sidebar lifecycle tracks host visibility without duplicate handlers",
	unregisteredWhileHidden and tickHandlerCount() == 1 and tickAdds == 2)

staff = true
equipped:checkSidebarSizeOption()
check("sidebar geometry reserves staff slot only when visible", originalCalls.size == 1
	and popup.width == 144 and popup.height == 36 and popup.isStaff == true
	and terminalButton.x == 48 and staffButton.x == 96 and staffButton.visible == true)
check("sidebar preserves vanilla lifecycle forwarding", originalCalls.initialise == 1
	and originalCalls.prerender == 1)

equipped:removeFromUIManager()
check("sidebar disposal owns both controls and forwards vanilla removal",
	equipped.gsInventoryPopup == nil and popup.disposed == true
	and terminalButton.disposed == true and staffButton.disposed == true
	and terminalButton._sikTooltipHandle.disposed == true
	and staffButton._sikTooltipHandle.disposed == true
	and originalCalls.remove == 1 and popup:dispose() == false)
check("sidebar removal cleans refresh and restores host lifecycle",
	tickHandlerCount() == 0 and tickRemoves == 2
	and equipped.setVisible == ISEquippedItem.setVisible
	and equipped.addToUIManager == ISEquippedItem.addToUIManager
	and equipped.removeFromUIManager == ISEquippedItem.removeFromUIManager)

io.write(string.format("RESULT %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end

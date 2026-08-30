--[[
	GlobalStorageSiK - pila Escape SiK UI por jugador local.
	Sin evento global: cada superficie conserva su onKeyRelease y solo la
	superficie SiK superior de su jugador puede consumir Escape.
]]

GlobalStorageSiK = GlobalStorageSiK or {}
GlobalStorageSiK.SiK_UI = GlobalStorageSiK.SiK_UI or {}
GlobalStorageSiK.SiK_UI.EscapeStack = GlobalStorageSiK.SiK_UI.EscapeStack or {}

local EscapeStack = GlobalStorageSiK.SiK_UI.EscapeStack
local stacksByPlayer = {}
local stateByPanel = setmetatable({}, { __mode = "k" })
local sequence = 0

EscapeStack.PRIORITY = EscapeStack.PRIORITY or {
	STAFF = 100,
	TERMINAL = 200,
	MODAL = 300,
	TRANSIENT = 400,
}

local function playerNum(panel)
	local value = panel and tonumber(panel.playerNum) or 0
	return math.max(0, math.floor(value or 0))
end

local function isVisible(panel)
	if not panel then return false end
	if panel.getIsVisible then
		local ok, value = pcall(function() return panel:getIsVisible() end)
		if ok then return value == true end
	end
	if panel.isVisible then
		local ok, value = pcall(function() return panel:isVisible() end)
		if ok then return value == true end
	end
	return panel.visible ~= false
end

local function removeFromStack(stack, panel)
	for i = #stack, 1, -1 do
		if stack[i] == panel then table.remove(stack, i) end
	end
end

local function stackFor(number)
	local stack = stacksByPlayer[number]
	if not stack then stack = {}; stacksByPlayer[number] = stack end
	return stack
end

local function prune(stack)
	for i = #stack, 1, -1 do
		local panel = stack[i]
		if not stateByPanel[panel] or not isVisible(panel) then table.remove(stack, i) end
	end
end

function EscapeStack.push(panel, onClose, priority)
	if not panel then return end
	local number = playerNum(panel)
	local prior = stateByPanel[panel]
	if prior and prior.playerNum ~= number then
		removeFromStack(stackFor(prior.playerNum), panel)
	end
	sequence = sequence + 1
	stateByPanel[panel] = {
		playerNum = number,
		onClose = onClose or (prior and prior.onClose),
		priority = tonumber(priority) or (prior and prior.priority)
			or EscapeStack.PRIORITY.MODAL,
		sequence = sequence,
	}
	local stack = stackFor(number)
	removeFromStack(stack, panel)
	stack[#stack + 1] = panel
	table.sort(stack, function(left, right)
		local leftState = stateByPanel[left] or {}
		local rightState = stateByPanel[right] or {}
		local leftPriority = tonumber(leftState.priority) or 0
		local rightPriority = tonumber(rightState.priority) or 0
		if leftPriority == rightPriority then
			return (tonumber(leftState.sequence) or 0) < (tonumber(rightState.sequence) or 0)
		end
		return leftPriority < rightPriority
	end)
	if stack[#stack] == panel and panel.bringToTop then panel:bringToTop() end
end

function EscapeStack.remove(panel)
	local state = panel and stateByPanel[panel] or nil
	if not state then return end
	removeFromStack(stackFor(state.playerNum), panel)
	stateByPanel[panel] = nil
end

function EscapeStack.isTop(panel)
	local state = panel and stateByPanel[panel] or nil
	if not state then return false end
	local stack = stackFor(state.playerNum)
	prune(stack)
	return stack[#stack] == panel
end

function EscapeStack.install(panel, onClose, priority)
	if not panel then return end
	panel._sikEscapeClose = onClose
	panel._sikEscapePriority = tonumber(priority) or panel._sikEscapePriority
		or EscapeStack.PRIORITY.MODAL
	if panel._sikEscapeStackInstalled then
		EscapeStack.push(panel, onClose, panel._sikEscapePriority)
		return
	end
	panel._sikEscapeStackInstalled = true
	panel._sikEscapeInstalled = true
	local previous = panel.onKeyRelease
	local previousIsKeyConsumed = panel.isKeyConsumed
	local previousSetVisible = panel.setVisible
	local previousRemove = panel.removeFromUIManager
	panel.isKeyConsumed = function(self, key)
		local escapeKey = Keyboard and Keyboard.KEY_ESCAPE or 1
		if key == escapeKey and EscapeStack.isTop(self) then
			return true
		end
		if previousIsKeyConsumed then return previousIsKeyConsumed(self, key) end
		return false
	end
	panel.onKeyRelease = function(self, key)
		local escapeKey = Keyboard and Keyboard.KEY_ESCAPE or 1
		if key == escapeKey then
			if not EscapeStack.isTop(self) then return false end
			local state = stateByPanel[self]
			local close = state and state.onClose or self._sikEscapeClose
			EscapeStack.remove(self)
			if self.setWantKeyEvents then self:setWantKeyEvents(false) end
			if close then close(self) end
			return true
		end
		if previous then return previous(self, key) end
		return false
	end
	if previousSetVisible then
		panel.setVisible = function(self, visible)
			local result = previousSetVisible(self, visible)
			if visible then
				if self.setWantKeyEvents then self:setWantKeyEvents(true) end
				EscapeStack.push(self, self._sikEscapeClose, self._sikEscapePriority)
			else
				if self.setWantKeyEvents then self:setWantKeyEvents(false) end
				EscapeStack.remove(self)
			end
			return result
		end
	end
	if previousRemove then
		panel.removeFromUIManager = function(self)
			EscapeStack.remove(self)
			if self.setWantKeyEvents then self:setWantKeyEvents(false) end
			return previousRemove(self)
		end
	end
	if panel.setWantKeyEvents then panel:setWantKeyEvents(true) end
	EscapeStack.push(panel, onClose, panel._sikEscapePriority)
end

return EscapeStack

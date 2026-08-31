--[[
	GlobalStorageSiK - Viewport seguro SiK UI
	Resuelve siempre el rectangulo del jugador local solicitado; nunca asume 0.
]]

if not GlobalStorageSiK or not GlobalStorageSiK.SiK_UI
		or not GlobalStorageSiK.SiK_UI.Metrics then
	require "GS_SiK_UI_Metrics"
end

GlobalStorageSiK.SiK_UI.Viewport = GlobalStorageSiK.SiK_UI.Viewport or {}

local Viewport = GlobalStorageSiK.SiK_UI.Viewport
local Metrics = GlobalStorageSiK.SiK_UI.Metrics

local function finiteNumber(value)
	value = tonumber(value)
	if value and value == value then
		return value
	end
	return nil
end

local function callNumber(callback, argument)
	if type(callback) ~= "function" then
		return nil
	end
	local ok, value = pcall(callback, argument)
	if ok then
		return finiteNumber(value)
	end
	return nil
end

local function runtimeScreenSize()
	local width = callNumber(rawget(_G, "getScreenWidth"))
	local height = callNumber(rawget(_G, "getScreenHeight"))
	local coreFn = rawget(_G, "getCore")
	if (not width or not height) and type(coreFn) == "function" then
		local ok, core = pcall(coreFn)
		if ok and core then
			width = width or callNumber(core.getScreenWidth, core)
			height = height or callNumber(core.getScreenHeight, core)
		end
	end
	return math.max(1, width or 1280), math.max(1, height or 720)
end

local function runtimePlayerRect(playerNum)
	local x = callNumber(rawget(_G, "getPlayerScreenLeft"), playerNum)
	local y = callNumber(rawget(_G, "getPlayerScreenTop"), playerNum)
	local w = callNumber(rawget(_G, "getPlayerScreenWidth"), playerNum)
	local h = callNumber(rawget(_G, "getPlayerScreenHeight"), playerNum)
	if x and y and w and h and w > 0 and h > 0 then
		return { x = x, y = y, w = w, h = h }
	end
	return nil
end

local function injectedPlayerRect(playerNum, environment)
	if not environment or type(environment.playerRect) ~= "function" then
		return nil
	end
	local ok, rect = pcall(environment.playerRect, playerNum)
	if not ok or type(rect) ~= "table" then
		return nil
	end
	local x = finiteNumber(rect.x)
	local y = finiteNumber(rect.y)
	local w = finiteNumber(rect.w)
	local h = finiteNumber(rect.h)
	if not x or not y or not w or not h or w <= 0 or h <= 0 then
		return nil
	end
	return { x = x, y = y, w = w, h = h }
end

function Viewport.resolve(playerNum, environment)
	playerNum = math.max(0, math.floor(tonumber(playerNum) or 0))
	environment = environment or {}
	local screenW, screenH = runtimeScreenSize()
	screenW = finiteNumber(environment.screenW) or screenW
	screenH = finiteNumber(environment.screenH) or screenH
	local source = injectedPlayerRect(playerNum, environment) or runtimePlayerRect(playerNum)
	if not source then
		source = { x = 0, y = 0, w = screenW, h = screenH }
	end
	local safe = finiteNumber(environment.safeMargin) or Metrics.tokens().safeMargin
	safe = math.max(0, safe)
	local insetX = math.min(safe, math.floor(source.w / 2))
	local insetY = math.min(safe, math.floor(source.h / 2))
	local result = {
		x = source.x + insetX,
		y = source.y + insetY,
		w = math.max(0, source.w - insetX * 2),
		h = math.max(0, source.h - insetY * 2),
		playerNum = playerNum,
		safeMargin = safe,
		source = { x = source.x, y = source.y, w = source.w, h = source.h },
	}
	-- El terminal no tiene breakpoints visuales: toda resolucion usa el mismo
	-- contrato. El viewport solo aporta limites seguros, tambien en split-screen.
	result.profile = Metrics.profileFor(source.w, source.h)
	return result
end

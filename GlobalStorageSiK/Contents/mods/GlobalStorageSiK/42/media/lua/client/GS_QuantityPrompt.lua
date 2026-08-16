--[[
	GlobalStorageSiK - Diálogo de cantidad
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Entrada numérica para menús contextuales (B42).
]]

require "GS_I18n"
require "GS_Log"

require "ISUI/ISTextBox"

GlobalStorageSiK.QuantityPrompt = {}

local T = GlobalStorageSiK.I18n.text

--- Normaliza y valida una cantidad entera.
---@param text string|nil
---@param min number|nil
---@param max number|nil
---@return number|nil
function GlobalStorageSiK.QuantityPrompt.parseAmount(text, min, max)
	if not text or text == "" then
		return nil
	end
	local n = tonumber(text)
	if not n then
		return nil
	end
	n = math.floor(n + 0.0001)
	min = min or 1
	if n < min then
		return nil
	end
	if max and n > max then
		return nil
	end
	return n
end

--- Muestra halo de cantidad inválida.
---@param player IsoPlayer|nil
local function showInvalid(player)
	if not player or not player.setHaloNote then
		return
	end
	pcall(function()
		player:setHaloNote(T("IGUI_GS_InvalidQuantity"), 220, 120, 120, 280)
	end)
end

--- Abre cuadro de texto para introducir cantidad.
---@param options table { title?: string, default?: number, min?: number, max?: number, player?: IsoPlayer, onConfirm: fun(amount: number), onClose?: fun() }
function GlobalStorageSiK.QuantityPrompt.show(options)
	if not options or not options.onConfirm then
		return
	end

	local player = options.player
	if not player then
		player = getSpecificPlayer and getSpecificPlayer(0) or nil
	end
	local playerNum = 0
	if player and player.getPlayerNum then
		playerNum = player:getPlayerNum()
	end

	local minVal = options.min or 1
	local maxVal = options.max
	local defaultText = tostring(options.default or minVal)
	local title = options.title or T("IGUI_GS_QuantityPrompt")
	if maxVal and maxVal > 0 then
		title = title .. " (" .. tostring(minVal) .. "-" .. tostring(maxVal) .. ")"
	end

	local function onClick(_, button, text)
		if not button or button.internal ~= "OK" then
			if options.onClose then
				options.onClose()
			end
			return
		end
		local amount = GlobalStorageSiK.QuantityPrompt.parseAmount(text, minVal, maxVal)
		if amount then
			options.onConfirm(amount)
		else
			showInvalid(player)
			if options.onClose then
				options.onClose()
			end
		end
	end

	local ok, err = pcall(function()
		local box = ISTextBox:new(0, 0, 300, 180, title, defaultText, nil, onClick, playerNum)
		box:initialise()
		box:addToUIManager()
		if box.setOnlyNumbers then
			box:setOnlyNumbers(true)
		end
		if box.setAlwaysOnTop then
			box:setAlwaysOnTop(true)
		end
		if box.bringToTop then
			box:bringToTop()
		end
		if UIManager and UIManager.pushToTop then
			UIManager:pushToTop(box)
		end
	end)

	if not ok then
		GlobalStorageSiK.Log.error("QuantityPrompt", "show failed", err)
		showInvalid(player)
	end
end

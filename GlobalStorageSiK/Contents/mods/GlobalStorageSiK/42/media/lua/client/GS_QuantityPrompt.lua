--[[
	GlobalStorageSiK - Diálogo de cantidad
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Entrada numérica para menús contextuales (B42).
]]

require "GS_I18n"
require "GS_Log"
local UI = require "GS_UI_Framework"
require "GS_UI_Feedback"

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
	if not player then
		return
	end
	pcall(function()
		GlobalStorageSiK.UIFeedback.halo(player, T("IGUI_GS_InvalidQuantity"),
			220, 120, 120, 280, { tone = "danger" })
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

	local ok, err = pcall(function()
		UI.Modal.input({
			title = title,
			text = defaultText,
			fieldTitle = maxVal and (T("IGUI_GS_QuantityAvailableNow") .. ": " .. tostring(maxVal))
				or T("IGUI_GS_QuantityPrompt"),
			fieldTooltip = maxVal and T("IGUI_GS_QuantityRangeHelp", minVal, maxVal)
				or T("IGUI_GS_QuantityActionsHelp"),
			actionsTitle = T("IGUI_GS_PermColActions"),
			actionsTooltip = T("IGUI_GS_QuantityActionsHelp"),
			acceptText = options.acceptText,
			acceptActive = true,
			playerNum = playerNum,
			width = UI.Modal.STANDARD_MODAL_W,
			numeric = true,
			maxLength = math.max(1, #tostring(maxVal or 999999999)),
			quantity = {
				min = minVal,
				max = maxVal,
				step = 1,
				decrementText = "−",
				incrementText = "+",
				decrementTooltip = T("IGUI_GS_QuantityDecrease"),
				incrementTooltip = T("IGUI_GS_QuantityIncrease"),
				maxText = T("IGUI_GS_QuantityMaximum") .. " "
					.. T("IGUI_GS_PunctuationMiddleDot") .. " " .. tostring(maxVal or minVal),
			},
			validate = function(text)
				local amount = GlobalStorageSiK.QuantityPrompt.parseAmount(text, minVal, maxVal)
				if not amount then return false, "invalid_quantity" end
				return true, amount
			end,
			onInvalid = function()
				showInvalid(player)
			end,
			onAccept = function(amount)
				options.onConfirm(amount)
			end,
			onCancel = options.onClose,
		})
	end)

	if not ok then
		GlobalStorageSiK.Log.error("QuantityPrompt", "show failed", err)
		showInvalid(player)
	end
end

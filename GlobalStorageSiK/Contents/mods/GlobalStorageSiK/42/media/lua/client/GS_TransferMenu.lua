--[[
	GlobalStorageSiK - Menú contextual de transferencia a la red
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Depósito con cantidades predefinidas y personalizadas.
]]

require "GS_I18n"
require "GS_QuantityPrompt"
require "GS_DepositClient"
require "GS_PlayerUtils"
require "GS_ContextMenu"

require "ISUI/ISContextMenu"

GlobalStorageSiK.TransferMenu = {}

local T = GlobalStorageSiK.I18n.text
local PRESET_AMOUNTS = { 2, 3, 5, 10, 25, 50, 100, 250, 500 }

--- Cuenta instancias físicas del mismo tipo en el contenedor de la referencia.
---@param item InventoryItem|nil
---@return number
local function stackCount(item)
	if not item or not GlobalStorageSiK.DepositClient.collectSameTypeItemIds then return 0 end
	return #GlobalStorageSiK.DepositClient.collectSameTypeItemIds(item)
end

--- Deposita cantidad acotada de un ítem.
---@param playerArg IsoPlayer|number
---@param item InventoryItem
---@param count number
local function doTransferAmount(playerArg, item, count)
	if not item then
		return
	end
	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
	local maxCount = stackCount(item)
	local n = math.floor(count or 1)
	if n < 1 then
		n = 1
	end
	if maxCount > 0 and n > maxCount then
		n = maxCount
	end
	if n >= maxCount then
		GlobalStorageSiK.DepositClient.sendDepositItems(
			GlobalStorageSiK.DepositClient.collectItemIds({ item }), player
		)
	else
		GlobalStorageSiK.DepositClient.sendDepositPartial(player, item, n)
	end
end

--- Abre diálogo para cantidad de depósito.
---@param playerArg IsoPlayer|number
---@param item InventoryItem
local function promptCustomTransfer(playerArg, item)
	local maxCount = math.max(1, stackCount(item))
	GlobalStorageSiK.QuantityPrompt.show({
		title = T("IGUI_GS_TransferAmountPrompt"),
		default = 1,
		min = 1,
		max = maxCount,
		player = GlobalStorageSiK.PlayerUtils.resolve(playerArg),
		onConfirm = function(amount)
			doTransferAmount(playerArg, item, amount)
		end,
	})
end

--- Añade submenú de transferencia bajo el menú raíz del mod.
---@param context ISContextMenu
---@param playerArg IsoPlayer|number
---@param items InventoryItem[]
---@param parentSubMenu ISContextMenu|nil
function GlobalStorageSiK.TransferMenu.addToContext(context, playerArg, items, parentSubMenu)
	if not context or not items or #items == 0 then
		return
	end

	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
	local first = items[1]
	if not first then
		return
	end

	local host = parentSubMenu or GlobalStorageSiK.ContextMenu.ensureRoot(context)
	if not host then
		return
	end

	local root = host:addOption(T("IGUI_GS_ContextTransfer"))
	local subMenu = ISContextMenu:getNew(host)
	host:addSubMenu(root, subMenu)

	subMenu:addOption(T("IGUI_GS_TransferThis"), player, function()
		GlobalStorageSiK.DepositClient.sendDepositItems(
			GlobalStorageSiK.DepositClient.collectItemIds({ first }), player
		)
	end)

	if #items > 1 then
		subMenu:addOption(T("IGUI_GS_TransferSelection"), player, function()
			GlobalStorageSiK.DepositClient.sendDepositItems(
				GlobalStorageSiK.DepositClient.collectItemIds(items), player
			)
		end)
	end

	subMenu:addOption(T("IGUI_GS_TransferContainer"), player, function()
		GlobalStorageSiK.DepositClient.sendDepositContainer(playerArg, first)
	end)

	local maxCount = stackCount(first)
	if maxCount > 1 then
		local qtyRoot = subMenu:addOption(T("IGUI_GS_TransferAmount"))
		local qtyMenu = ISContextMenu:getNew(subMenu)
		subMenu:addSubMenu(qtyRoot, qtyMenu)

		local seen = {}
		for i = 1, #PRESET_AMOUNTS do
			local preset = PRESET_AMOUNTS[i]
			if preset < maxCount and not seen[preset] then
				seen[preset] = true
				qtyMenu:addOption(tostring(preset), player, function()
					doTransferAmount(playerArg, first, preset)
				end)
			end
		end
		if not seen[maxCount] then
			qtyMenu:addOption(T("IGUI_GS_TransferAmountMax", tostring(maxCount)), player, function()
				doTransferAmount(playerArg, first, maxCount)
			end)
		end
		qtyMenu:addOption(T("IGUI_GS_TransferAmountCustom"), player, promptCustomTransfer, first)
	end
end

--[[

	GlobalStorageSiK - Menú contextual de extracción

	Autor: SiK

	Fecha: 2025-06-24

	Descripción: Opciones de retiro con cantidad seleccionable o personalizada.

]]



require "GS_I18n"

require "GS_QuantityPrompt"

require "GS_ContainerTargets"

require "GS_ContextMenuUi"

require "GS_ContextMenu"



require "ISUI/ISContextMenu"



GlobalStorageSiK.WithdrawMenu = {}



local T = GlobalStorageSiK.I18n.text



local PRESET_AMOUNTS = { 2, 3, 5, 10, 25, 50, 100, 250, 500 }



--- Ejecuta retiro con cantidad acotada al stock disponible.

---@param onWithdraw fun(rowData: table, amount: number, targetKey: string|nil)|nil

---@param player IsoPlayer|nil

---@param rowData table

---@param amount number

local function doWithdraw(onWithdraw, player, rowData, amount)

	if not onWithdraw or not rowData then

		return

	end

	local maxCount = rowData.count or 1

	local n = math.floor(amount or 1)

	if n < 1 then

		n = maxCount

	end

	if maxCount > 0 and n > maxCount then

		n = maxCount

	end

	-- El contextual interno siempre retira al inventario del jugador. Un pane
	-- concreto solo se elige mediante drag-and-drop; no existe destino oculto o
	-- persistido en la UI de Almacen.
	onWithdraw(rowData, n, nil)

end



--- Abre diálogo para cantidad personalizada.

---@param player IsoPlayer|nil

---@param rowData table

---@param onWithdraw fun(rowData: table, amount: number, targetKey: string|nil)|nil

local function promptCustomAmount(player, rowData, onWithdraw)

	local maxCount = math.max(1, rowData.count or 1)

	local menuState = GlobalStorageSiK.ContextMenuUi.prepareTerminal(

		GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance

	)

	local function restoreTerminal()

		GlobalStorageSiK.ContextMenuUi.scheduleTerminalRestore(menuState)

	end

	GlobalStorageSiK.QuantityPrompt.show({

		title = T("IGUI_GS_WithdrawAmountPrompt"),
		acceptText = T("IGUI_GS_QuantityWithdraw"),

		default = 1,

		min = 1,

		max = maxCount,

		player = player,

		onConfirm = function(amount)

			doWithdraw(onWithdraw, player, rowData, amount)

			restoreTerminal()

		end,

		onClose = restoreTerminal,

	})

end



--- Añade submenú de extracción con cantidades predefinidas y entrada manual.

---@param parentMenu ISContextMenu

---@param player IsoPlayer|nil

---@param rowData table

---@param onWithdraw fun(rowData: table, amount: number, targetKey: string|nil)|nil

---@param skipDestination boolean|nil

function GlobalStorageSiK.WithdrawMenu.fillSubMenu(parentMenu, player, rowData, onWithdraw, skipDestination)

	if not parentMenu or not rowData or not onWithdraw then

		return

	end



	local maxCount = rowData.count or 1

	parentMenu:addOption(T("IGUI_GS_WithdrawOne"), rowData, function(data)

		doWithdraw(onWithdraw, player, data, 1)

	end)



	if maxCount > 1 then

		parentMenu:addOption(T("IGUI_GS_WithdrawType", tostring(maxCount)), rowData, function(data)

			doWithdraw(onWithdraw, player, data, 0)

		end)



		local qtyRoot = parentMenu:addOption(T("IGUI_GS_WithdrawAmount"))

		local qtyMenu = ISContextMenu:getNew(parentMenu)

		parentMenu:addSubMenu(qtyRoot, qtyMenu)



		local seen = {}

		for i = 1, #PRESET_AMOUNTS do

			local preset = PRESET_AMOUNTS[i]

			if preset < maxCount and not seen[preset] then

				seen[preset] = true

				qtyMenu:addOption(tostring(preset), rowData, function(data)

					doWithdraw(onWithdraw, player, data, preset)

				end)

			end

		end



		if maxCount > 1 and not seen[maxCount] then

			qtyMenu:addOption(T("IGUI_GS_WithdrawAmountMax", tostring(maxCount)), rowData, function(data)

				doWithdraw(onWithdraw, player, data, maxCount)

			end)

		end



		qtyMenu:addOption(T("IGUI_GS_WithdrawAmountCustom"), player, promptCustomAmount, rowData, onWithdraw)

	end

end



--- Añade raíz «Extraer de la red» al menú contextual.

---@param context ISContextMenu

---@param player IsoPlayer|nil

---@param rowData table

---@param onWithdraw fun(rowData: table, amount: number, targetKey: string|nil)|nil

---@param selectionRows table[]|nil
function GlobalStorageSiK.WithdrawMenu.addToContext(context, player, rowData, onWithdraw, selectionRows)

	if not context or not rowData or not onWithdraw then

		return

	end

	selectionRows = selectionRows or { rowData }

	local multi = #selectionRows > 1



	-- WithdrawMenu is terminal-internal: the caller already owns the exact menu
	-- root. External inventory actions use TransferMenu/ItemActions instead.
	local host = context

	if not host then

		return

	end

	local root = host:addOption(T("IGUI_GS_ContextWithdraw"))

	local subMenu = ISContextMenu:getNew(host)

	host:addSubMenu(root, subMenu)



	if multi then

		subMenu:addOption(T("IGUI_GS_WithdrawSelectionOne"), player, function()

			for i = 1, #selectionRows do

				doWithdraw(onWithdraw, player, selectionRows[i], 1)

			end

		end)

		subMenu:addOption(T("IGUI_GS_WithdrawSelectionAll"), player, function()

			for i = 1, #selectionRows do

				doWithdraw(onWithdraw, player, selectionRows[i], 0)

			end

		end)

	else

		GlobalStorageSiK.WithdrawMenu.fillSubMenu(subMenu, player, rowData, onWithdraw, true)

	end

end

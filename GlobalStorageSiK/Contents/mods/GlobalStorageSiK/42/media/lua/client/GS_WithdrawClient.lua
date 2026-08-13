--[[
	GlobalStorageSiK - Retiro desde red (cliente)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Comando withdrawItem con destino opcional y bloqueo local anti-spam.
]]

require "GS_NetClient"
require "GS_I18n"
require "GS_PlayerUtils"

GlobalStorageSiK.WithdrawClient = {}

GlobalStorageSiK.WithdrawClient._pending = false
GlobalStorageSiK.WithdrawClient._pendingType = nil

--- Libera el bloqueo local de retiro pendiente.
function GlobalStorageSiK.WithdrawClient.clearPending()
	GlobalStorageSiK.WithdrawClient._pending = false
	GlobalStorageSiK.WithdrawClient._pendingType = nil
end

--- Indica si hay un retiro en curso esperando respuesta del servidor.
---@return boolean
function GlobalStorageSiK.WithdrawClient.isPending()
	return GlobalStorageSiK.WithdrawClient._pending == true
end

--- Solicita retiro de ítems de la red.
---@param rowData table { fullType, count, ... }
---@param amount number|nil 1 = una unidad; 0 = todo el tipo
---@param targetKey string|nil clave de contenedor destino
---@param searchQuery string|nil
---@return boolean
function GlobalStorageSiK.WithdrawClient.sendWithdraw(rowData, amount, targetKey, searchQuery)
	if not rowData or not rowData.fullType then
		return false
	end
	if GlobalStorageSiK.WithdrawClient._pending then
		return false
	end
	GlobalStorageSiK.WithdrawClient._pending = true
	GlobalStorageSiK.WithdrawClient._pendingType = rowData.fullType

	local player = GlobalStorageSiK.NetClient.getPlayer()
	if player and player.setHaloNote then
		pcall(function()
			player:setHaloNote(GlobalStorageSiK.I18n.text("IGUI_GS_WithdrawPending"), 200, 220, 200, 200)
		end)
	end
	return GlobalStorageSiK.NetClient.sendCommand("withdrawItem", {
		fullType = rowData.fullType,
		amount = amount or 1,
		targetKey = targetKey,
		searchQuery = searchQuery or "",
	})
end

--- Retira varias filas en lote (arrastre de selección múltiple). No usa el
--- bloqueo `_pending` de sendWithdraw: ese gate está pensado para evitar doble
--- click en una sola acción, y con arrastre multi-fila haría que solo la
--- primera fila del lote se enviase al servidor (el resto se descartaría en
--- silencio porque _pending seguiría en true hasta la respuesta del servidor).
---@param rows table[] filas { fullType, ... }
---@param amount number|nil
---@param targetKey string|nil
---@param searchQuery string|nil
---@return boolean okAny
function GlobalStorageSiK.WithdrawClient.sendWithdrawBatch(rows, amount, targetKey, searchQuery)
	if not rows or #rows == 0 then
		return false
	end
	local okAny = false
	for i = 1, #rows do
		local row = rows[i]
		if row and row.fullType then
			local ok = GlobalStorageSiK.NetClient.sendCommand("withdrawItem", {
				fullType = row.fullType,
				amount = amount or 1,
				targetKey = targetKey,
				searchQuery = searchQuery or "",
			})
			if ok then
				okAny = true
			end
		end
	end
	return okAny
end

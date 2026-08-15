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
-- BUG REAL (2026-08-16, "el retiro almacen->inventario deja de hacer nada
-- en cuanto retiro varios montones seguidos, hasta al cabo de un rato" -
-- pedido explicito de unificar el comportamiento con el deposito, que SI
-- encola via GS_TransferQueue): antes, si el jugador pedia un segundo
-- retiro mientras el primero seguia esperando respuesta del servidor
-- (_pending=true), sendWithdraw lo descartaba en silencio (return false
-- sin encolar ni avisar) - el jugador tenia que esperar el roundtrip
-- completo del primero y volver a pedir el siguiente a mano, pareciendo
-- que el sistema se "atascaba". Ahora los retiros pedidos mientras hay uno
-- en curso se encolan (FIFO) y se disparan automaticamente uno detras de
-- otro segun van llegando las respuestas del servidor, mismo patron que
-- ya usa el deposito.
local _queue = {}

--- Libera el bloqueo local de retiro pendiente y dispara el siguiente en cola si lo hay.
function GlobalStorageSiK.WithdrawClient.clearPending()
	GlobalStorageSiK.WithdrawClient._pending = false
	GlobalStorageSiK.WithdrawClient._pendingType = nil
	if #_queue > 0 then
		local next = table.remove(_queue, 1)
		GlobalStorageSiK.WithdrawClient.sendWithdraw(next.rowData, next.amount, next.targetKey, next.searchQuery)
	end
end

--- Indica si hay un retiro en curso esperando respuesta del servidor.
---@return boolean
function GlobalStorageSiK.WithdrawClient.isPending()
	return GlobalStorageSiK.WithdrawClient._pending == true
end

--- Solicita retiro de ítems de la red. Si ya hay uno en curso, encola esta
--- petición en vez de descartarla (se dispara sola cuando el anterior responda).
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
		table.insert(_queue, { rowData = rowData, amount = amount, targetKey = targetKey, searchQuery = searchQuery })
		return true
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

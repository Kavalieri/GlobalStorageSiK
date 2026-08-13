--[[
	GlobalStorageSiK - Acciones de ítem (transferencia a red + tablet)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Menú contextual vanilla vía OnPreFillInventoryObjectContextMenu (B42).
]]

require "GS_I18n"
require "GS_NetClient"
require "GS_TerminalUI_Api"
require "GS_TerminalAccess"
require "GS_PlayerUtils"
require "GS_DepositClient"
require "GS_DepositSources"
require "GS_TransferMenu"
require "GS_ContextMenu"
require "GS_TerminalInstallReaderChoice"
require "GS_KeyBinding"
require "GS_InstallTerminalReader"
require "GS_Config"
require "GS_Sandbox"
require "GS_DiskProgramming"
require "TimedActions/GS_ProgramDiskAction"
require "ISUI/ISContextMenu"

GlobalStorageSiK.ItemActions = {}

local T = GlobalStorageSiK.I18n.text

--- Registro de ítems de tableta que abren el terminal por click derecho.
--- El Core no conoce ni menciona ningún addon por nombre: cada addon con su
--- propio ítem de tableta se registra a sí mismo una vez, en su propio
--- fichero de cliente, con:
---   GlobalStorageSiK.ItemActions.registerTabletItem(fullType, labelKey)
--- labelKey es la clave de traducción del texto del menú contextual.
GlobalStorageSiK.ItemActions._tabletItemLabels = GlobalStorageSiK.ItemActions._tabletItemLabels or {}

---@param fullType string
---@param labelKey string
function GlobalStorageSiK.ItemActions.registerTabletItem(fullType, labelKey)
	if not fullType or not labelKey then
		return
	end
	GlobalStorageSiK.ItemActions._tabletItemLabels[fullType] = labelKey
end

--- Deposita un ítem concreto en la red.
--- Firma menú contextual PZ: onSelect(target, param1) → (player, item).
---@param playerArg number|IsoPlayer
---@param item InventoryItem
function GlobalStorageSiK.ItemActions.onTransferOne(playerArg, item)
	if not item or not item.getContainer then
		return
	end
	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
	GlobalStorageSiK.DepositClient.sendDepositItems(
		GlobalStorageSiK.DepositClient.collectItemIds({ item }), player
	)
end

--- Deposita la selección contextual en la red.
---@param playerArg number|IsoPlayer
---@param items InventoryItem[]
function GlobalStorageSiK.ItemActions.onTransferSelection(playerArg, items)
	if not items or #items == 0 then
		return
	end
	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
	GlobalStorageSiK.DepositClient.sendDepositItems(
		GlobalStorageSiK.DepositClient.collectItemIds(items), player
	)
end

--- Deposita todo el contenedor del ítem de referencia.
---@param playerArg number|IsoPlayer
---@param item InventoryItem
function GlobalStorageSiK.ItemActions.onTransferContainer(playerArg, item)
	GlobalStorageSiK.DepositClient.sendDepositContainer(playerArg, item)
end

--- Abre el terminal al usar la tablet.
---@param playerArg number|IsoPlayer
---@param item InventoryItem
function GlobalStorageSiK.ItemActions.onUseTerminalTablet(playerArg, item)
	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
	if GlobalStorageSiK.PlayerUtils.isUnavailable(player) then
		return
	end
	GlobalStorageSiK.TerminalUI.requestOpen()
end

--- Resuelve ítems del menú contextual (formato B42; pila abierta o cerrada).
---@param items table
---@return InventoryItem[]
function GlobalStorageSiK.ItemActions.resolveContextItems(items)
	if not items or #items == 0 then
		return {}
	end
	if ISInventoryPane and ISInventoryPane.getActualItems then
		local resolved = ISInventoryPane.getActualItems(items)
		if resolved and #resolved > 0 then
			return resolved
		end
	end
	local out = {}
	for i = 1, #items do
		local entry = items[i]
		local item = entry
		if item and not instanceof(item, "InventoryItem") and item.items then
			item = item.items[1]
		end
		if entry and entry.items then
			for j = 2, #entry.items do
				if entry.items[j] and entry.items[j].getContainer then
					table.insert(out, entry.items[j])
				end
			end
		elseif item and item.getContainer then
			table.insert(out, item)
		end
	end
	return out
end

--- Indica si el origen es un nodo de la red GS.
---@param items InventoryItem[]
---@return boolean
function GlobalStorageSiK.ItemActions.isFromNetworkStorage(items)
	if not items or #items == 0 then
		return false
	end
	local item = items[1]
	if not item or not item.getContainer then
		return false
	end
	local container = item:getContainer()
	if not container then
		return false
	end
	return GlobalStorageSiK.DepositSources.isNetworkNodeContainer(container)
end

--- Indica si `addTransferOptions` añadiría algo para estos ítems, SIN tocar
--- la UI. Se usa para decidir si merece la pena crear siquiera el submenú
--- raíz "Global Storage" (ver onPreFillInventoryObjectContextMenu: antes se
--- creaba siempre, aunque quedara vacío).
---@param playerArg number|IsoPlayer
---@param items InventoryItem[]
---@return boolean
function GlobalStorageSiK.ItemActions.canTransfer(playerArg, items)
	if not items or #items == 0 then
		return false
	end
	if GlobalStorageSiK.ItemActions.isFromNetworkStorage(items) then
		return false
	end
	local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)
	if GlobalStorageSiK.PlayerUtils.isUnavailable(player) then
		return false
	end
	local first = items[1]
	if not first or not first.getContainer or not first:getContainer() then
		return false
	end
	-- Transferir ítems de inventario a la red solo tiene sentido a rango de
	-- un terminal ACTIVO (mismo rango que abrirlo) - sin esto, el submenú
	-- "Transferir" aparecía siempre en cualquier ítem, en cualquier parte del
	-- mapa, sin relación con poder depositar de verdad.
	local range = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	return GlobalStorageSiK.TerminalAccess.findNearestTerminal(player, range) ~= nil
end

--- Añade opciones de transferencia al menú contextual. Llamar solo tras
--- confirmar `canTransfer` (o dejar que este repita el mismo chequeo, es barato).
---@param context ISContextMenu
---@param playerArg number|IsoPlayer
---@param items InventoryItem[]
---@param parentSubMenu ISContextMenu|nil submenú raíz Global Storage SiK
function GlobalStorageSiK.ItemActions.addTransferOptions(context, playerArg, items, parentSubMenu)
	if not context or not GlobalStorageSiK.ItemActions.canTransfer(playerArg, items) then
		return
	end
	GlobalStorageSiK.TransferMenu.addToContext(context, playerArg, items, parentSubMenu)
end

--- Handler del evento vanilla (PreFill = raíz del menú, no overflow «Más»).
---@param playerArg number|IsoPlayer
---@param context ISContextMenu
---@param items table
local function onPreFillInventoryObjectContextMenu(playerArg, context, items)
	local ok, err = pcall(function()
		if not context or not items or #items == 0 then
			return
		end

		local resolved = GlobalStorageSiK.ItemActions.resolveContextItems(items)
		if #resolved == 0 then
			return
		end

		local first = resolved[1]
		local player = GlobalStorageSiK.PlayerUtils.resolve(playerArg)

		-- El submenú raíz "Global Storage" solo se crea la primera vez que de
		-- verdad hay una opción que meter dentro - antes se creaba siempre
		-- (aunque quedara vacío), apareciendo en CUALQUIER ítem sin motivo.
		local gsSub = nil
		local function ensureSub()
			if not gsSub then
				gsSub = GlobalStorageSiK.ContextMenu.ensureRoot(context)
			end
			return gsSub
		end

		if first and first.getFullType then
			-- Metodo nuevo de instalacion: click derecho en el DISQUETE (no en
			-- el ordenador), con el lector puesto directamente en el
			-- inventario PRINCIPAL del personaje (no dentro de una mochila -
			-- getItemCount, NO getItemCountRecurse, es a proposito) y un
			-- ordenador sin instalar detectado cerca. Ver
			-- GS_TerminalInstallReaderChoice.lua.
			if first:getFullType() == "GlobalStorageSiK.GS_FloppyDisk" and player then
				local inv = player.getInventory and player:getInventory()
				local hasReader = inv and (inv:getItemCount(GlobalStorageSiK.Config.ITEM_TERMINAL_READER) or 0) > 0
				if hasReader then
					local range = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
					-- Se usa findNearestKnownComputer (no findNearestUninstalledComputer):
					-- si el PC mas cercano YA tiene terminal, la opcion sigue
					-- apareciendo, pero al pulsarla se avisa claramente en vez de
					-- desaparecer sin explicacion (confundia: parecia que el menu
					-- fallaba en vez de que ya estuviera instalado).
					local target = GlobalStorageSiK.TerminalAccess.findNearestKnownComputer(player, range)
					if target then
						local sub = ensureSub()
						if sub then
							sub:addOption(T("IGUI_GS_InstallReaderMenu"), player, function(p)
								-- Re-resolver SIEMPRE en el momento del clic, no reusar el
								-- "target" capturado al abrir el menu: entre abrir el menu
								-- (submenus se navegan con el raton, puede tardar) y pulsar
								-- la opcion el jugador pudo moverse fuera de rango o alguien
								-- pudo instalar el terminal entretanto - igual que ya se hace
								-- en el boton "Instalar aqui" de la pantalla de bloqueo.
								local freshRange = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
								local freshTarget = GlobalStorageSiK.TerminalAccess.findNearestKnownComputer(p, freshRange)
								if not freshTarget then
									if p and p.setHaloNote then
										p:setHaloNote(T("IGUI_GS_InstallReaderComputerNoneShort"), 220, 180, 100, 300)
									end
									return
								end
								if freshTarget.alreadyInstalled then
									if p and p.setHaloNote then
										local keyLabel = GlobalStorageSiK.KeyBinding and GlobalStorageSiK.KeyBinding.getKeyLabel and GlobalStorageSiK.KeyBinding.getKeyLabel() or "F9"
										p:setHaloNote(T("IGUI_GS_InstallReaderAlreadyInstalled", keyLabel), 220, 180, 100, 300)
									end
									return
								end
								-- Inicia la accion cronometrada directamente - el
								-- dialogo de red nueva/existente se abre solo al
								-- terminar (ver GS_InstallTerminalReaderAction:perform).
								GlobalStorageSiK.InstallTerminalReader.begin(p, freshTarget)
							end)
						end
					end
				end
			end
			-- Mecánica de "programar" disquetes: clic derecho en un disquete
			-- EN BLANCO ofrece un submenú "Programar" con un botón por cada
			-- programa cuya receta el jugador ya conoce (revista leída). Si no
			-- conoce ninguno todavía, no se muestra nada - igual que el resto
			-- del menú, nunca una opción muerta sin explicación. El terminal
			-- cerca SÍ se revalida en el momento del clic (puede que el
			-- jugador se haya movido desde que se abrió el menú) y, si falta,
			-- se avisa con un mensaje claro en vez de fallar en silencio.
			-- Opciones planas (sin submenu anidado propio): un unico
			-- ISContextMenu:getNew() por clic ya lo hace ensureSub() al
			-- crear la raiz "Global Storage" - no merece la pena arriesgar
			-- otro nivel de submenu propio por un solo programa disponible
			-- de momento.
			if first:getFullType() == GlobalStorageSiK.DiskProgramming.BLANK_DISK and player then
				for id, def in pairs(GlobalStorageSiK.DiskProgramming.PROGRAMS) do
					if GlobalStorageSiK.DiskProgramming.knowsProgram(player, id) then
						local sub = ensureSub()
						if sub then
							sub:addOption(T(def.menuTextKey), player, function(p)
								if not GlobalStorageSiK.DiskProgramming.terminalInRange(p) then
									if p and p.setHaloNote then
										p:setHaloNote(T("IGUI_GS_ProgramDiskFailTerminal"), 220, 180, 100, 300)
									end
									return
								end
								ISTimedActionQueue.add(GS_ProgramDiskAction:new(p, id))
							end)
						end
					end
				end
			end

			local fullType = first:getFullType()
			local tabletLabelKey = GlobalStorageSiK.ItemActions._tabletItemLabels[fullType]
			if tabletLabelKey then
				local sub = ensureSub()
				if sub then
					sub:addOption(T(tabletLabelKey), player, GlobalStorageSiK.ItemActions.onUseTerminalTablet, first)
				end
			end
		end

		if GlobalStorageSiK.ItemActions.canTransfer(playerArg, resolved) then
			GlobalStorageSiK.ItemActions.addTransferOptions(context, playerArg, resolved, ensureSub())
		end
	end)
	if not ok then
		print("[GlobalStorageSiK] OnPreFillInventoryObjectContextMenu error: " .. tostring(err))
	end
end

Events.OnPreFillInventoryObjectContextMenu.Add(onPreFillInventoryObjectContextMenu)

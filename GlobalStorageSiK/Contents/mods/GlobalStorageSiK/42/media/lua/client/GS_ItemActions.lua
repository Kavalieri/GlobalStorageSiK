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
require "GS_Log"
require "GS_InstallTerminalReader"
require "GS_Config"
require "GS_Sandbox"
require "GS_CraftUtils"
require "GS_DiskProgramming"
require "TimedActions/GS_ProgramDiskAction"
require "TimedActions/GS_AddonInstallAction"
require "TimedActions/ISTimedActionQueue"
require "GS_AddonRegistry"
require "GS_Network"
require "GS_Addons"
require "ISUI/ISContextMenu"
require "ISUI/ISInventoryPaneContextMenu"

GlobalStorageSiK.ItemActions = {}

local T = GlobalStorageSiK.I18n.text

--- Adjunta el tooltip de requisitos a una opcion del menu, SIEMPRE (pedido
--- explicito 2026-08-23: "vamos a mostrarlo siempre, tengamos o no, para
--- indicar lo que tenemos y lo que falta" - antes solo se adjuntaba cuando
--- la opcion ya estaba deshabilitada, igual que cualquier tooltip de
--- crafteo vanilla que se puede consultar este disponible o no la receta).
---@param option table|nil resultado de context:addOption(...)
---@param text string|nil
local function attachTooltip(option, text)
	if not option or not text or text == "" then
		return
	end
	if ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.addToolTip then
		option.toolTip = ISInventoryPaneContextMenu.addToolTip()
		option.toolTip.description = text
	end
end

--- Marca una opcion del menu contextual como no disponible (mismo patron
--- vanilla que usa cualquier receta de crafteo: texto en rojo, no clicable)
--- - ver ISContextMenu.lua:372 (notAvailable). El tooltip se adjunta aparte
--- con attachTooltip(), siempre, disponible o no.
---@param option table|nil resultado de context:addOption(...)
local function markUnavailable(option)
	if option then
		option.notAvailable = true
	end
end

local REQ_OK_RGB = "0.5,0.72,0.55"
local REQ_MISSING_RGB = "0.85,0.4,0.35"

--- Una línea del checklist (icono opcional vía texto, color segun estado) -
--- " <LINE> " es el token de salto de línea real que usa ISToolTip/vanilla
--- (ver Translate/*/Tooltip.json), NO "\n" - un tooltip con una sola frase
--- larga sin esto se sale del panel o queda ilegible.
---@param text string
---@param ok boolean
---@return string
local function reqLine(text, ok)
	local rgb = ok and REQ_OK_RGB or REQ_MISSING_RGB
	local mark = ok and "OK" or "X"
	return string.format(" <RGB:%s> %s: %s", rgb, text, mark)
end

--- Nombre para mostrar del módulo instalable, contemplando TODOS los tiers
--- válidos (pedido explicito 2026-08-23, bug real: la Antena WiFi tiene 3
--- tiers compatibles - T1/T2/T3 - pero el tooltip/etiqueta solo miraba
--- `addonDef.itemType` (siempre T1), asi que con la T3 YA instalada seguia
--- pidiendo "Antena WiFi GS T1" como si nada se cumpliera. Mismo patron que
--- `moduleRequirementText` en GS_AddonManageUI.lua, duplicado aqui a
--- proposito para no crear una dependencia cliente-cliente entre estos dos
--- ficheros por una sola funcion de 10 lineas.
---@param def table
---@return string
local function moduleTierLabel(def)
	local names, seen = {}, {}
	local moduleTypes = GlobalStorageSiK.AddonRegistry.moduleItemTypes(def)
	for i = 1, #moduleTypes do
		local fullType = moduleTypes[i]
		if fullType and fullType ~= "" and not seen[fullType] then
			seen[fullType] = true
			local name = GlobalStorageSiK.I18n.typeDisplayName and GlobalStorageSiK.I18n.typeDisplayName(fullType) or fullType
			names[#names + 1] = name
		end
	end
	if #names == 0 then
		return T(def.titleKey or "IGUI_GS_AddonUnknown")
	end
	return table.concat(names, " / ")
end

--- Resuelve el contexto de red del terminal (para "Instalar"/"Desinstalar"
--- por disquete).
--- BUG REAL cerrado (2026-08-23, dev7): la version anterior a esta resolvia
--- la red via el mirror LOCAL de GS_Network.findNetworkIdAtTerminal, que
--- puede no estar poblado a tiempo en el cliente - "ya instalado" nunca se
--- detectaba y "Desinstalar" fallaba en silencio pese a estar de pie frente
--- al terminal.
--- BUG REAL cerrado (2026-08-23, ronda siguiente - reportado con capturas
--- ESTANDO LEJOS de cualquier terminal): el arreglo de dev7 confiaba en
--- `ui:getIsVisible()` SIN comprobar que el jugador siguiera de verdad
--- dentro de rango de esa ancla - la ventana de terminal puede seguir
--- "visible" (p.ej. el panel de bloqueo "Sin terminal cercano") con un
--- `terminalState` de una sesion ANTERIOR mientras el jugador ya se alejo,
--- asi que "ya instalado"/"Desinstalar" seguian mostrando datos de un
--- terminal que ya no esta cerca.
--- BUG REAL cerrado (2026-08-23, ronda siguiente todavia - reportado DE PIE
--- junto al terminal: "Instalar" seguia sin detectar "ya instalado" y
--- "Desinstalar" pedia acercarse estando ya cerca): el intento anterior
--- exigia que un reescaneo fisico SEPARADO (`findNearestKnownComputer`)
--- devolviera coordenadas que coincidieran EXACTAMENTE con
--- `ui.terminalState.terminalAnchor` para poder usar los datos de la
--- ventana - dos fuentes independientes divergiendo en un redondeo o en que
--- objeto exacto detecta cada una bastaba para que nunca coincidieran.
--- Ahora la ventana abierta (si la hay, no bloqueada) es la fuente PRIMARIA
--- directa - se comprueba distancia del jugador a SU PROPIA ancla, sin
--- comparar contra ningun segundo reescaneo. Solo si no hay ventana
--- valida (o el jugador esta fuera de su rango) se cae al reescaneo fisico
--- de siempre.
---@param player IsoPlayer|nil
---@return table|nil target { x, y, z, alreadyInstalled }
---@return string|nil networkId
---@return table|nil anchor { x, y, z }
---@return table|nil installedAddons {addonId: meta}|nil
local function resolveNearbyNetworkContext(player)
	if not player then
		return nil, nil, nil, nil
	end
	local range = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if ui and ui.getIsVisible and ui:getIsVisible() and ui.accessMode ~= "blocked"
		and ui.terminalState and ui.terminalState.networkId and ui.terminalState.terminalAnchor then
		local anchor = ui.terminalState.terminalAnchor
		local dx = math.abs(player:getX() - anchor.x)
		local dy = math.abs(player:getY() - anchor.y)
		if dx <= range and dy <= range then
			return { x = anchor.x, y = anchor.y, z = anchor.z or 0, alreadyInstalled = true },
				ui.terminalState.networkId, anchor, ui.terminalState.installedAddons or {}
		end
	end
	local target = GlobalStorageSiK.TerminalAccess.findNearestKnownComputer(player, range)
	if not target or not target.alreadyInstalled then
		return target, nil, nil, nil
	end
	local anchor = { x = target.x, y = target.y, z = target.z or 0 }
	local networkId = GlobalStorageSiK.Network.findNetworkIdAtTerminal(target.x, target.y, target.z or 0)
	local installedAddons = networkId and GlobalStorageSiK.Addons.serializeForTerminal(networkId, anchor) or nil
	return target, networkId, anchor, installedAddons
end

---@param player IsoPlayer|nil
---@param addonDef table
---@return boolean
local function hasAnyModuleTier(player, addonDef)
	local inv = player and player.getInventory and player:getInventory()
	if not inv then
		return false
	end
	local moduleTypes = GlobalStorageSiK.AddonRegistry.moduleItemTypes(addonDef)
	for i = 1, #moduleTypes do
		if moduleTypes[i] and (inv:getItemCountRecurse(moduleTypes[i]) or 0) >= 1 then
			return true
		end
	end
	return false
end

--- Checklist completo de requisitos para instalar un addon por disquete
--- (pedido explicito 2026-08-23: "necesitamos que valide también el
--- requisito de tener la disquetera instalada o en el inventario... con los
--- saltos de línea necesarios para que no colapse ni quede ilegible") -
--- antes solo se mostraba el PRIMER motivo que fallaba (canInstallModule
--- corta en el primer false); esto se comprueba todo a la vez, como
--- cualquier tooltip de crafteo vanilla que lista ingrediente a ingrediente.
---@param player IsoPlayer|nil
---@param addonDef table
---@param hasTerminalNear boolean
---@param nid string|nil red del terminal detectado, para comprobar la
---  disquetera instalada como addon en ESA red (ver hasReaderAvailable)
---@param anchor table|nil
---@return string
local function buildInstallChecklistTooltip(player, addonDef, hasTerminalNear, nid, anchor)
	-- Progresivo (pedido explicito 2026-08-23): sin terminal detectado, el
	-- resto de requisitos (disquetera/modulo/revista) no se pueden validar
	-- de verdad contra ESA red - listarlos igualmente induce a error (p.ej.
	-- "modulo: OK" cuando ni siquiera sabemos en que red se instalaria). Se
	-- muestra solo la linea de terminal hasta que se detecte uno; a partir
	-- de ahi, el resto de la lista de siempre.
	if not hasTerminalNear then
		return T("IGUI_GS_ReqApproachTerminal")
	end
	local readerType = GlobalStorageSiK.Config and GlobalStorageSiK.Config.ITEM_TERMINAL_READER
	-- BUG REAL cerrado (2026-08-23, pedido explicito: "la disquetera está
	-- instalada en el terminal... hay que validar o uno u otro, ambas formas
	-- son buenas") - antes solo miraba el inventario principal
	-- (inv:getItemCount), nunca si ya estaba instalada como addon en esta
	-- red. hasReaderAvailable ya contempla ambos casos (mismo helper que ya
	-- usa "Desinstalar").
	local hasReader = GlobalStorageSiK.Addons.hasReaderAvailable(player, nid, anchor)
	local readerLabel = (readerType and GlobalStorageSiK.I18n.typeDisplayName
		and GlobalStorageSiK.I18n.typeDisplayName(readerType)) or T("IGUI_GS_AddonReaderTitle")
	local knowsMag = player and GlobalStorageSiK.AddonRegistry.playerKnowsMagazine(player, addonDef.id)
	local magazineLabel = (addonDef.magazineType and GlobalStorageSiK.I18n.typeDisplayName
		and GlobalStorageSiK.I18n.typeDisplayName(addonDef.magazineType)) or T("IGUI_GS_AddonStatusNeedMagazine")

	local requiredSkill = GlobalStorageSiK.Sandbox.getAddonInstallSkillRequired()
	local hasSkill = requiredSkill <= 0 or (player and GlobalStorageSiK.CraftUtils.getElectricityLevel(player) >= requiredSkill)
	local lines = {
		reqLine(T("IGUI_GS_ReqTerminalNear"), true),
		reqLine(readerLabel, hasReader == true),
		reqLine(moduleTierLabel(addonDef), hasAnyModuleTier(player, addonDef)),
		reqLine(magazineLabel, knowsMag == true),
	}
	if requiredSkill > 0 then
		lines[#lines + 1] = reqLine(T("IGUI_GS_AddonReqSkill", requiredSkill), hasSkill == true)
	end
	return table.concat(lines, " <LINE> ")
end

--- Registro de ítems de tableta que abren el terminal por click derecho.
--- El Core no conoce ni menciona ningún addon por nombre: cada addon con su
--- propio ítem de tableta se registra a sí mismo una vez, en su propio
--- fichero de cliente, con:
---   GlobalStorageSiK.ItemActions.registerTabletItem(fullType, labelKey)
--- labelKey es la clave de traducción del texto del menú contextual.
GlobalStorageSiK.ItemActions._tabletItemLabels = GlobalStorageSiK.ItemActions._tabletItemLabels or {}
GlobalStorageSiK.ItemActions._tabletItemActions = GlobalStorageSiK.ItemActions._tabletItemActions or {}

---@param fullType string
---@param labelKey string
---@param onUse function|nil
function GlobalStorageSiK.ItemActions.registerTabletItem(fullType, labelKey, onUse)
	if not fullType or not labelKey then
		return
	end
	GlobalStorageSiK.ItemActions._tabletItemLabels[fullType] = labelKey
	GlobalStorageSiK.ItemActions._tabletItemActions[fullType] =
		type(onUse) == "function" and onUse or GlobalStorageSiK.ItemActions.onUseTerminalTablet
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
	-- BUG REAL cerrado (2026-08-23, pedido explicito del usuario): antes
	-- exigia proximidad FISICA a un terminal (findNearestTerminal), lo que
	-- dejaba fuera el caso de acceso INALAMBRICO (addon Tablet) - un jugador
	-- con el Almacen realmente abierto y viendo la red en directo, pero sin
	-- ningun terminal fisico cerca, nunca veia la opcion "Transferir" del
	-- menu contextual, solo podia arrastrar. El criterio correcto es "el
	-- Almacen esta abierto y accesible ahora mismo" - el mismo que ya exige
	-- soltar un item arrastrado sobre la ventana del terminal
	-- (GS_TerminalWithdrawDrag.lua) - cubre proximidad fisica Y acceso
	-- inalambrico por igual, sin necesitar dos caminos distintos, y evita
	-- ofrecer "Transferir" a ciegas sin que el jugador pueda ver primero el
	-- estado real de la red.
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	return ui ~= nil and ui.getIsVisible and ui:getIsVisible() and ui.accessMode ~= "blocked"
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
	GlobalStorageSiK.Log.debug("ItemActions", string.format(
		"OnPreFillInventoryObjectContextMenu disparado: items=%s uiVisible=%s",
		tostring(items and #items or 0),
		tostring(GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
			and GlobalStorageSiK.TerminalUI.instance.getIsVisible
			and GlobalStorageSiK.TerminalUI.instance:getIsVisible())
	))
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
				-- BUG REAL cerrado (2026-08-23, reportado explicito: "el disquete
				-- de la disquetera no tiene su propio menú o no como los demás,
				-- debemos mantener coherencia") - antes esta opcion SOLO aparecia
				-- si ya se cumplian los requisitos (disquetera en inventario +
				-- ordenador conocido cerca); si faltaba cualquiera de los dos, el
				-- disquete no mostraba NADA, distinto del resto del menu (que
				-- siempre muestra la opcion, roja con tooltip si algo falta).
				-- Ahora sigue el mismo patron que "Instalar"/"Programar".
				local sub = ensureSub()
				if sub then
					local inv = player.getInventory and player:getInventory()
					local hasReader = inv and (inv:getItemCount(GlobalStorageSiK.Config.ITEM_TERMINAL_READER) or 0) > 0
					local range = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
					-- Se usa findNearestKnownComputer (no findNearestUninstalledComputer):
					-- si el PC mas cercano YA tiene terminal, la opcion sigue
					-- apareciendo, pero al pulsarla se avisa claramente en vez de
					-- desaparecer sin explicacion (confundia: parecia que el menu
					-- fallaba en vez de que ya estuviera instalado).
					local target = GlobalStorageSiK.TerminalAccess.findNearestKnownComputer(player, range)
					local option = sub:addOption(T("IGUI_GS_InstallReaderMenu"), player, function(p)
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
					local readerLabel = (GlobalStorageSiK.Config and GlobalStorageSiK.Config.ITEM_TERMINAL_READER
						and GlobalStorageSiK.I18n.typeDisplayName
						and GlobalStorageSiK.I18n.typeDisplayName(GlobalStorageSiK.Config.ITEM_TERMINAL_READER))
						or T("IGUI_GS_AddonReaderTitle")
					-- Progresivo (pedido explicito 2026-08-23): sin terminal
					-- detectado, no tiene sentido validar la disquetera todavia.
					if not target then
						attachTooltip(option, T("IGUI_GS_ReqApproachTerminal"))
					else
						attachTooltip(option, table.concat({
							reqLine(T("IGUI_GS_ReqTerminalNear"), true),
							reqLine(readerLabel, hasReader == true),
						}, " <LINE> "))
					end
					if not hasReader or not target or target.alreadyInstalled then
						markUnavailable(option)
					end
				end
			end
			-- Mecánica de "programar" disquetes: clic derecho en un disquete
			-- EN BLANCO ofrece un submenú "Programar" con un botón por CADA
			-- programa registrado (pedido explicito 2026-08-23: "en rojo si no
			-- se cumplen los requisitos y con el tooltip de lo que consume y
			-- el estado, como cualquier crafteo vanilla") - antes solo se
			-- mostraban los programas cuya receta ya se conocia, ocultando por
			-- completo el resto sin explicar que existian ni que faltaba para
			-- desbloquearlos. Ahora todos aparecen siempre; si falta la receta
			-- o no hay terminal cerca, la opcion sale en rojo (notAvailable,
			-- mismo patron vanilla) con tooltip explicando el motivo exacto -
			-- activacion propia e independiente de "Transferir" (que exige el
			-- Almacen abierto): aqui solo hace falta proximidad fisica a un
			-- terminal conocido, igual que ya exigia programar. El terminal
			-- cerca SIEMPRE se revalida en el momento del clic (pudo cambiar
			-- desde que se abrio el menu).
			if first:getFullType() == GlobalStorageSiK.DiskProgramming.BLANK_DISK and player then
				local hasTerminalNear = GlobalStorageSiK.DiskProgramming.terminalInRange(player)
				for id, def in pairs(GlobalStorageSiK.DiskProgramming.PROGRAMS) do
					local sub = ensureSub()
					if sub then
						local knows = GlobalStorageSiK.DiskProgramming.knowsProgram(player, id)
						local option = sub:addOption(T(def.menuTextKey), player, function(p)
							if not GlobalStorageSiK.DiskProgramming.knowsProgram(p, id) then
								if p and p.setHaloNote then
									p:setHaloNote(T("IGUI_GS_ProgramDiskFailBook"), 220, 180, 100, 300)
								end
								return
							end
							if not GlobalStorageSiK.DiskProgramming.terminalInRange(p) then
								if p and p.setHaloNote then
									p:setHaloNote(T("IGUI_GS_ProgramDiskFailTerminal"), 220, 180, 100, 300)
								end
								return
							end
							ISTimedActionQueue.add(GS_ProgramDiskAction:new(p, id))
						end)
						-- Checklist SIEMPRE visible (pedido explicito 2026-08-23),
						-- disponible o no la opcion - las recetas de programar
						-- disco no exigen ninguna herramienta (soldador,
						-- destornillador...), solo revista + terminal cerca, asi
						-- que el checklist se limita a esos dos requisitos reales.
						-- Progresivo (pedido explicito 2026-08-23): sin terminal
						-- detectado, no se valida la revista todavia.
						if not hasTerminalNear then
							attachTooltip(option, T("IGUI_GS_ReqApproachTerminal"))
						else
							attachTooltip(option, table.concat({
								reqLine(T("IGUI_GS_ReqTerminalNear"), true),
								reqLine(T("IGUI_GS_ReqMagazineKnown"), knows == true),
							}, " <LINE> "))
						end
						if not knows or not hasTerminalNear then
							markUnavailable(option)
						end
					end
				end
			end

			-- "Instalar" generico por disquete de modulo de addon (pedido
			-- explicito 2026-08-23: "Todos los disquetes activan su menu de
			-- Global Storage propio, submenu instalar + periferico que
			-- instalemos con ese disquete"). Independiente de Reader (que
			-- instala el TERMINAL en si sobre un PC sin red, flujo ya cubierto
			-- arriba con su propia mecanica de eleccion red nueva/existente) y
			-- de "Transferir" (exige el Almacen abierto) - esta activacion
			-- solo exige un terminal fisico YA instalado cerca, mismo criterio
			-- que programar. GS_Server.lua ("installAddon") ya sabe reescanear
			-- esa proximidad en servidor si no hay sesion de terminal abierta.
			-- BUG REAL cerrado (2026-08-23): "Reader" quedaba excluido de este
			-- bucle a proposito (confundiendolo con el flujo de "Red GS" de
			-- arriba, que es una mecanica DISTINTA - bootstrapear un terminal
			-- nuevo). El disquete "Disquetera GS" (installDiskItem real del
			-- addon Reader, GS_FloppyDisk_DriveInstall) instala el periferico
			-- Lector como ADDON en un terminal YA EXISTENTE - exactamente el
			-- mismo caso que Craft/Builder/Antena, nunca deberia haberse
			-- excluido. Sin esto, ese disquete no ofrecia ninguna opcion.
			for _, addonDef in ipairs(GlobalStorageSiK.AddonRegistry.listSorted()) do
				if addonDef.installDiskItem == first:getFullType() and player then
					local sub = ensureSub()
					if sub then
						local peripheralLabel = moduleTierLabel(addonDef)
						local target, nid, anchor, installedAddons = resolveNearbyNetworkContext(player)
						local hasTerminalNear = target ~= nil
						-- "Ya instalado" (pedido explicito 2026-08-23: "necesitamos
						-- algun modo de indicar al jugador que ese periferico ya se
						-- detecto instalado, para que no muestre infinitamente la
						-- opcion de instalar disponible cuando ya lo esta") - usa
						-- installedAddons ya resuelto por resolveNearbyNetworkContext
						-- (terminalState real si la ventana esta abierta, o el
						-- mirror local como respaldo) en vez de volver a consultar
						-- por separado - orientativo, el servidor sigue siendo quien
						-- de verdad decide al pulsar.
						local alreadyInstalled = installedAddons ~= nil and installedAddons[addonDef.id] ~= nil
						local addonId = addonDef.id
						if alreadyInstalled then
							-- Entrada informativa, no un boton activo - evita
							-- ofrecer "Instalar" sin fin sobre un periferico que ya
							-- esta puesto (independientemente de que tier).
							local option = sub:addOption(T("IGUI_GS_InstallAddonMenu", peripheralLabel), player, function() end)
							markUnavailable(option)
							attachTooltip(option, T("IGUI_GS_AddonAlreadyInstalledMsg"))
						else
							-- BUG REAL cerrado (2026-08-23, pedido explicito: "la
							-- disquetera está instalada en el terminal... hay que
							-- validar o uno u otro") - antes se pasaba nil,nil en
							-- vez de nid/anchor, asi que canInstallModule (via
							-- hasRequiredInstallItems) SOLO podia ver la disquetera
							-- en el inventario, nunca instalada como addon en la
							-- red ya detectada.
							local canInstall = GlobalStorageSiK.AddonRegistry.canInstallModule(player, addonId, nid, anchor)
							local option = sub:addOption(T("IGUI_GS_InstallAddonMenu", peripheralLabel), player, function(p)
								local freshTarget, freshNid, freshAnchor = resolveNearbyNetworkContext(p)
								if not freshTarget then
									if p and p.setHaloNote then
										p:setHaloNote(T("IGUI_GS_ProgramDiskFailTerminal"), 220, 180, 100, 300)
									end
									return
								end
								if not GlobalStorageSiK.AddonRegistry.canInstallModule(p, addonId, freshNid, freshAnchor) then
									if p and p.setHaloNote then
										p:setHaloNote(T("IGUI_GS_CraftMissing"), 220, 180, 100, 300)
									end
									return
								end
								-- Pedido explicito del usuario: instalar/desinstalar un
								-- addon ya no es instantaneo, corre una accion
								-- cronometrada con barra de progreso y animacion de
								-- manos trabajando (mismo requisito desde el menu
								-- contextual del disquete y desde el modal de
								-- gestion). ISTimedActionQueue.add mas abajo.
								ISTimedActionQueue.add(GS_AddonInstallAction:new(p, addonId, "install", freshNid, freshAnchor, nil))
							end)
							-- Checklist completo SIEMPRE visible (terminal +
							-- disquetera + modulo, cualquier tier + revista), no
							-- solo el primer requisito que falle - pedido
							-- explicito 2026-08-23. Las recetas de instalar un
							-- addon no exigen herramientas (soldador,
							-- destornillador...) - esas se piden al FABRICAR el
							-- modulo en si, no al instalarlo ya fabricado, asi que
							-- no se listan aqui.
							attachTooltip(option, buildInstallChecklistTooltip(player, addonDef, hasTerminalNear, nid, anchor))
							if not hasTerminalNear or not canInstall then
								markUnavailable(option)
							end
						end
					end
				end
			end

			-- "Desinstalar" generico por disquete de desinstalacion (pedido
			-- explicito 2026-08-23: "el disquete de desinstalar también debe
			-- tener su propia opción que detecte los addons instalados en la
			-- red y nos permita desinstalarlo, validando también la
			-- disquetera tanto inventario como instalada como addon"). Lista
			-- cada addon YA instalado en la red del terminal mas cercano (uno
			-- por linea) - a diferencia de "Instalar", aqui SI se acepta el
			-- Lector instalado en la propia red ademas de en el inventario
			-- (hasReaderAvailable, no solo inventario) porque desinstalar es
			-- una accion de gestion de esa red concreta, no de "traer" un
			-- periferico nuevo desde fuera.
			if player and GlobalStorageSiK.Addons.uninstallDiskItem
				and first:getFullType() == GlobalStorageSiK.Addons.uninstallDiskItem() then
				local target, nid, anchor, installed = resolveNearbyNetworkContext(player)
				local hasTerminalNear = target ~= nil
				if hasTerminalNear and nid then
					installed = installed or {}
					local hasReader = GlobalStorageSiK.Addons.hasReaderAvailable(player, nid, anchor)
					for addonId, _ in pairs(installed) do
						local addonDef = GlobalStorageSiK.AddonRegistry.get(addonId)
						if addonDef then
							local sub = ensureSub()
							if sub then
								local peripheralLabel = moduleTierLabel(addonDef)
								local readerLabel = (GlobalStorageSiK.Config and GlobalStorageSiK.Config.ITEM_TERMINAL_READER
									and GlobalStorageSiK.I18n.typeDisplayName
									and GlobalStorageSiK.I18n.typeDisplayName(GlobalStorageSiK.Config.ITEM_TERMINAL_READER))
									or T("IGUI_GS_AddonReaderTitle")
								local option = sub:addOption(T("IGUI_GS_UninstallAddonMenu", peripheralLabel), player, function(p)
									local freshTarget, freshNid, freshAnchor = resolveNearbyNetworkContext(p)
									if not freshTarget or not freshNid then
										if p and p.setHaloNote then
											p:setHaloNote(T("IGUI_GS_ProgramDiskFailTerminal"), 220, 180, 100, 300)
										end
										return
									end
									if not GlobalStorageSiK.Addons.hasReaderAvailable(p, freshNid, freshAnchor) then
										if p and p.setHaloNote then
											p:setHaloNote(T("IGUI_GS_NeedReaderNetworkOrInventoryMsg"), 220, 180, 100, 300)
										end
										return
									end
									local requiredSkillFresh = GlobalStorageSiK.Sandbox.getAddonInstallSkillRequired()
									if requiredSkillFresh > 0 and GlobalStorageSiK.CraftUtils.getElectricityLevel(p) < requiredSkillFresh then
										if p and p.setHaloNote then
											p:setHaloNote(T("IGUI_GS_CraftMissing"), 220, 180, 100, 300)
										end
										return
									end
									ISTimedActionQueue.add(GS_AddonInstallAction:new(p, addonId, "uninstall", freshNid, freshAnchor, nil))
								end)
								local requiredSkill = GlobalStorageSiK.Sandbox.getAddonInstallSkillRequired()
								local hasSkill = requiredSkill <= 0 or (player and GlobalStorageSiK.CraftUtils.getElectricityLevel(player) >= requiredSkill)
								local tooltipLines = {
									reqLine(T("IGUI_GS_ReqTerminalNear"), true),
									reqLine(readerLabel, hasReader == true),
								}
								if requiredSkill > 0 then
									tooltipLines[#tooltipLines + 1] = reqLine(T("IGUI_GS_AddonReqSkill", requiredSkill), hasSkill == true)
								end
								attachTooltip(option, table.concat(tooltipLines, " <LINE> "))
								if not hasReader or not hasSkill then
									markUnavailable(option)
								end
							end
						end
					end
				elseif ensureSub() then
						-- Sin terminal detectado: entrada unica desactivada, en vez
						-- de no mostrar nada (pedido explicito: mantener coherencia
						-- con "Instalar"/"Programar", que si muestran algo aunque
						-- sea "acercate a un terminal").
						local option = ensureSub():addOption(T("IGUI_GS_UninstallAddonMenuGeneric"), player, function() end)
						markUnavailable(option)
						attachTooltip(option, T("IGUI_GS_ReqApproachTerminal"))
					end
				end

			local fullType = first:getFullType()
			local tabletLabelKey = GlobalStorageSiK.ItemActions._tabletItemLabels[fullType]
			if tabletLabelKey then
				local sub = ensureSub()
				if sub then
					local onUse = GlobalStorageSiK.ItemActions._tabletItemActions[fullType]
						or GlobalStorageSiK.ItemActions.onUseTerminalTablet
					sub:addOption(T(tabletLabelKey), player, onUse, first)
				end
			end
		end

		if GlobalStorageSiK.ItemActions.canTransfer(playerArg, resolved) then
			GlobalStorageSiK.ItemActions.addTransferOptions(context, playerArg, resolved, ensureSub())
		end
	end)
	if not ok then
		GlobalStorageSiK.Log.error("ItemActions", "OnPreFillInventoryObjectContextMenu", err)
	end
end

Events.OnPreFillInventoryObjectContextMenu.Add(onPreFillInventoryObjectContextMenu)

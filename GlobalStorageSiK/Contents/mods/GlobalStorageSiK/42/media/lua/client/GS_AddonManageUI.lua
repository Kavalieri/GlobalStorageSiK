--[[
	GlobalStorageSiK - Ventana "Gestionar periférico" (por addon)
	Autor: SiK
	Fecha: 2026-08-13
	Descripción: Ventana modal genérica, una por addon del AddonRegistry
	(Tablet/Craft/Builder/Reader/futuros) - antes esto vivía siempre visible,
	apilado para los 4 addons a la vez, dentro de la pestaña Addons
	(reportado: "ruido", los botones instalar/desinstalar quedaban bajo la
	receta). Ahora la pestaña Addons solo muestra la bahía con el estado de
	cada periférico (icono real, instalado o no) - clic en una ranura abre
	esta ventana con: descripción, receta para fabricar el módulo (si el mod
	del addon está activo), requisitos de instalación (manual/disquete) y el
	botón instalar/desinstalar. Mismo patrón de ventana modal ya usado en
	GS_ReaderAcquireUI.lua/GS_PCAcquireUI.lua (mismo marco, mismo refresco en
	vivo de bajo coste) - no es una clase nueva desde cero, es el mismo molde
	ya probado.
]]

require "GS_UI_Feedback"

require "GS_I18n"
require "GS_NetClient"
require "GSSiK_API"
require "GS_AddonRecipes"
require "GS_CraftUtils"
require "GS_TerminalRecipeCards"
require "GS_Sandbox"
require "TimedActions/GS_AddonInstallAction"
require "TimedActions/ISTimedActionQueue"

local UI = require "GS_UI_Framework"
local AddonAPI = GSSiK.API.Addon

local function addonDefinition(addonId)
	local ok, _, definition = AddonAPI.get(addonId)
	if ok then return definition end
	return nil
end

local function addonIsActive(addonId)
	local ok, _, active = AddonAPI.isActive(addonId)
	return ok == true and active == true
end

local function addonModuleItemTypes(addonId)
	local ok, _, itemTypes = AddonAPI.moduleItemTypes(addonId)
	if ok then return itemTypes end
	return {}
end

local function playerKnowsMagazine(player, addonId)
	local ok, _, known = AddonAPI.playerKnowsMagazine(player, addonId)
	return ok == true and known == true
end

local function canInstallAddon(player, addonId, networkId, anchor)
	local ok, _, allowed = AddonAPI.canInstall(player, addonId, networkId, anchor)
	return ok == true and allowed == true
end

GlobalStorageSiK.AddonManageUI = {}
GlobalStorageSiK.AddonManageUI.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local PAD = 14
local CONTROL_METRICS = UI.Controls.metrics("task")
local PANEL_W = math.max(UI.Modal.STANDARD_MODAL_W, 640)

GS_AddonManageUI = UI.Window.derive("GS_AddonManageUI")

---@param fullType string|nil
---@return string
local function itemDisplayName(fullType)
	return GlobalStorageSiK.AddonRecipes.displayNameForType(fullType)
end

--- Nombre de todos los perifericos que satisfacen el requisito. Normalmente
--- solo hay uno; Tablet registra tres tiers compatibles y la UI debe mostrar
--- los tres objetos reales en vez de describirlos como un periferico generico.
---@param def table
---@return string
local function moduleRequirementText(def)
	local names = {}
	local seen = {}
	local moduleTypes = addonModuleItemTypes(def.id)
	for i = 1, #moduleTypes do
		local fullType = moduleTypes[i]
		if fullType and fullType ~= "" and not seen[fullType] then
			seen[fullType] = true
			table.insert(names, itemDisplayName(fullType))
		end
	end
	if #names == 0 then
		return itemDisplayName(def.itemType)
	end
	return table.concat(names, " / ")
end

local function requirementTexture(spec)
	if spec.texture then return spec.texture end
	if spec.itemType and GlobalStorageSiK.CraftUtils
		and GlobalStorageSiK.CraftUtils.getItemIconTexture then
		return GlobalStorageSiK.CraftUtils.getItemIconTexture(spec.itemType)
	end
	return spec.icon
end

local function addRequirementCard(owner, y, width, title, rows)
	local card = assert(UI.Block.create({
		parent = owner, x = owner.padding, y = y, w = width, h = 1000,
		title = title, variant = "section", contentHost = true,
		playerNum = owner.playerNum,
	}))
	owner._sikCards = owner._sikCards or {}
	owner._sikCards[#owner._sikCards + 1] = card
	local rowY = 0
	for index = 1, #rows do
		local spec = rows[index]
		local row = UI.Controls.requirementRow(card.content, {
			x = 0, y = rowY, w = card.content.width,
			text = spec.text, texture = requirementTexture(spec),
			state = spec.ok, playerNum = owner.playerNum,
		})
		rowY = rowY + row.height
		if index < #rows then rowY = rowY + 6 end
	end
	local reserved = title and (CONTROL_METRICS.rowHeight + 8) or 0
	local height = 16 + reserved + rowY
	card:reflow({ x = owner.padding, y = y, w = width, h = height })
	return height
end

--- Huella de los materiales de la receta base del modulo (chasis/cabezal/
--- placa, etc.) - BUG REAL cerrado (2026-08-23, reportado explicitamente:
--- "la ventana no refleja en tiempo real los materiales de fabricacion").
--- statusSignature() nunca incluia esto, asi que aunque OnContainerUpdate ya
--- disparaba refresh() en cada cambio de inventario, refresh() lo descartaba
--- de inmediato porque la firma completa no habia cambiado - la tarjeta de
--- receta (chasis 0/1, cabezal 0/1, nivel de electricidad) se quedaba
--- obsoleta hasta cambiar de pestaña o reabrir la ventana, mientras que
--- "conoce la receta" (via revista) SI formaba parte de la firma y por eso
--- se actualizaba al instante. Barato: getModuleIngredients() son pocos
--- items (2-4 tipicamente), getItemCountRecurse por item ya es la misma
--- llamada que hace el propio recipe card.
---@param player IsoPlayer|nil
---@param def table
---@return string
local function ingredientSignature(player, def)
	local ingDefs = GlobalStorageSiK.AddonRecipes.getModuleIngredients(def)
	if #ingDefs == 0 or not player or not player.getInventory then
		return "0"
	end
	local inv = player:getInventory()
	local parts = {}
	for i = 1, #ingDefs do
		local ing = ingDefs[i]
		local have = ing.item and (inv:getItemCountRecurse(ing.item) or 0) or 0
		parts[#parts + 1] = tostring(have)
	end
	local skillHave = GlobalStorageSiK.CraftUtils and GlobalStorageSiK.CraftUtils.getElectricityLevel
		and GlobalStorageSiK.CraftUtils.getElectricityLevel(player) or 0
	parts[#parts + 1] = tostring(skillHave)
	return table.concat(parts, ",")
end

--- Huella de cada requisito visible de instalación. El booleano final de
--- canInstall no basta: si faltan dos requisitos, obtener uno mantiene false y
--- no permite saber qué fila debe repintarse.
---@param player IsoPlayer|nil
---@param def table
---@param networkId string|nil
---@param anchor table|nil
---@return string
local function installRequirementSignature(player, def, networkId, anchor)
	if not player or not player.getInventory then return "invalid" end
	local inv = player:getInventory()
	local moduleCount = 0
	local moduleTypes = addonModuleItemTypes(def.id)
	for i = 1, #moduleTypes do
		if moduleTypes[i] then
			moduleCount = moduleCount + (inv:getItemCountRecurse(moduleTypes[i]) or 0)
		end
	end
	local diskCount = 0
	if def.installDiskItem and def.installDiskItem ~= "" then
		diskCount = inv:getItemCountRecurse(def.installDiskItem) or 0
	end
	local hasReader = GlobalStorageSiK.Addons.hasReaderAvailable(player, networkId, anchor)
	local requiredSkill = GlobalStorageSiK.Sandbox.getAddonInstallSkillRequired()
	local skillHave = GlobalStorageSiK.CraftUtils.getElectricityLevel(player)
	return table.concat({ tostring(hasReader == true), tostring(moduleCount),
		tostring(diskCount), tostring(playerKnowsMagazine(player, def.id)),
		tostring(requiredSkill), tostring(skillHave) }, ",")
end

--- Firma corta del estado actual, para no reconstruir si no cambio nada
--- (mismo motivo que GS_ReaderAcquireUI/GS_PCAcquireUI: evita que la
--- ventana "salte" con cada tick de refresco si nada cambio de verdad).
---@param player IsoPlayer|nil
---@param def table
---@param networkId string|nil
---@param anchor table|nil
---@param installed table ya confirmado por el servidor (ver nota en buildLayout)
---@return string
local function statusSignature(player, def, networkId, anchor, installed)
	local modActive = addonIsActive(def.id)
	local isInstalled = (installed or {})[def.id] ~= nil
	local knowsMag = player and playerKnowsMagazine(player, def.id)
	local canInstall = player and canInstallAddon(player, def.id, networkId, anchor)
	local uninstallDiskItem = GlobalStorageSiK.Addons.uninstallDiskItem()
	local hasUninstallDisk = uninstallDiskItem and player and player:getInventory()
		and (player:getInventory():getItemCountRecurse(uninstallDiskItem) or 0) >= 1
	return table.concat({ tostring(modActive), tostring(isInstalled),
		tostring(knowsMag), tostring(canInstall), tostring(hasUninstallDisk),
		ingredientSignature(player, def),
		installRequirementSignature(player, def, networkId, anchor) }, "|")
end

function GS_AddonManageUI:initialise()
	UI.Window.callBase(self, "initialise")
	-- Mismo fondo que la ventana principal del terminal (ver nota identica en
	-- GS_ReaderAcquireUI.lua).
	self.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	self.borderColor = { r = 0, g = 0, b = 0, a = 1 }
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + 4
	local def = addonDefinition(self.addonId)
	UI.Modal.apply(self, {
		kind = "task", padding = PAD,
		title = def and T(def.titleKey or "IGUI_GS_AddonUnknown") or "",
		onClose = function()
			GlobalStorageSiK.AddonManageUI.instance = nil
		end,
	})
	self.padding = PAD
	self:buildLayout()
end

function GS_AddonManageUI:destroy()
	UI.Modal.close(self, "product")
end

function GS_AddonManageUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then
		UI.Modal.close(self, "escape")
	end
end

--- Crea el boton instalar/desinstalar - extraido a funcion aparte (pedido
--- explicito: el boton debe ir junto al bloque de requisitos al que
--- pertenece, no al final tras la receta) para poder llamarlo justo despues
--- de CADA bloque (instalacion O desinstalacion), en vez de siempre al
--- final del todo.
---@param self GS_AddonManageUI
---@param y number
---@param def table
---@param isInstalled boolean
---@param canInstall boolean
---@param canUninstall boolean
---@return number newY
local function createAddonActionButton(self, y, def, isInstalled, canInstall, canUninstall)
	-- BUG REAL cerrado (2026-08-22, reportado en Steam Workshop: "requisitos
	-- en verde pero el boton nunca aparece" - un jugador incluso publico un
	-- parche no oficial para esto): esto exigia self.isOwner, una lectura de
	-- solo-propietario calculada EN EL CLIENTE (ver
	-- GlobalStorageSiK.AddonManageUI.show, isOwnerPlayer(player, networkId))
	-- - doblemente incorrecto. Primero, el gate del servidor para instalar/
	-- desinstalar (requireAdminAccess en GS_Server.lua) es propietario O
	-- ADMIN de la red, nunca solo propietario - un admin de red nunca podia
	-- ver este boton aunque el servidor SI le fuera a dejar pulsarlo.
	-- Segundo, incluso para el propietario real, una lectura de permisos
	-- calculada en el cliente puede llegar desincronizada frente al servidor
	-- (mismo problema de fondo que motivo cerrar isOwnerPlayer() como
	-- consulta pura de solo lectura esta misma ronda, ver GS_Permissions.lua)
	-- - la UI no tiene por que confiar en su propia copia para decidir si
	-- ENSEÑAR el boton. El servidor sigue siendo la unica autoridad real:
	-- el propio boton ya revalida en el momento del clic
	-- (canInstallModule/canUninstall, mas abajo) y el comando
	-- installAddon/uninstallAddon vuelve a revalidar en servidor antes de
	-- hacer nada - exactamente igual que canInstall/canUninstall (abajo) ya
	-- se calculan y se usan solo para habilitar/deshabilitar el boton, nunca
	-- para decidir si existe.
	if not def then
		return y
	end
	local pad = self.padding
	local textW = self.width - pad * 2
	local btnLabel = isInstalled and T("IGUI_GS_AddonUninstallBtn") or T("IGUI_GS_AddonInstallBtn")
	local searchQuery = self.terminal and self.terminal.searchEntry and self.terminal.searchEntry:getText() or ""
	-- Ancho total + boton "bloqueado" (2026-08-26, pedido explicito del
	-- usuario: "las ventanas de instalacion de addons no estan actualizadas
	-- correctamente, botones y demas") - antes sin fullWidth (se encogia al
	-- texto) y con :setEnable() vanilla (textura gris generica, distinta del
	-- resto del proyecto). El chequeo de "revalida en el momento del clic"
	-- de mas abajo se conserva como red de seguridad para el hueco entre
	-- refrescos, igual que ya se acepto en Programacion/PC/disquetera al
	-- migrar a este mismo patron.
	local locked = isInstalled and (canUninstall ~= true) or (not isInstalled and canInstall ~= true)
	local actionBtn = UI.Controls.button(self, {
		x = pad, y = y, w = textW, h = CONTROL_METRICS.buttonHeight,
		text = btnLabel, fullWidth = true, locked = locked,
		onClick = function()
		-- BUG REAL encontrado (reportado: "si no tenemos antena en el
		-- inventario no da feedback, falla en silencio aunque el boton
		-- reacciona"): antes esto enviaba el comando y cerraba la ventana
		-- SIEMPRE, sin comprobar si de verdad se podia instalar - si el
		-- servidor lo rechazaba, el jugador nunca se enteraba de nada
		-- porque la ventana ya se habia cerrado. Revalida en el momento
		-- del clic (igual que GS_ReaderAcquireUI.lua) y avisa con un halo
		-- si falta algo, en vez de enviar un comando que sabemos que va
		-- a fallar.
		--
		-- Pedido explicito del usuario (2026-08-27): instalar/desinstalar ya
		-- no es instantaneo - se lanza una accion cronometrada con barra de
		-- progreso y animacion de manos trabajando (GS_AddonInstallAction,
		-- mismo patron ya probado en GS_ProgramDiskAction/
		-- GS_InstallTerminalReaderAction). El comando real al servidor solo
		-- se envia si la accion llega a completarse ENTERA (perform(), nunca
		-- stop()) - cancelar a medias (moverse, Escape) no consume ni manda
		-- nada, sin riesgo de duplicar. Mismo patron ya usado por el resto
		-- de acciones cronometradas del mod: la ventana se cierra al lanzar
		-- la accion (igual que GS_ReaderAcquireUI/GS_PCAcquireUI), el
		-- feedback de exito/fallo llega despues via el toast generico de
		-- GS_Client.lua (actionResult) cuando la accion termine de verdad.
		if not isInstalled then
			local recheckOk = self.player and canInstallAddon(self.player, def.id, self.networkId, self.anchor)
			if not recheckOk then
				if self.player then
					GlobalStorageSiK.UIFeedback.halo(self.player, T("IGUI_GS_CraftMissing"),
						220, 180, 100, 300, { tone = "warning" })
				end
				return
			end
			ISTimedActionQueue.add(GS_AddonInstallAction:new(self.player, def.id, "install", self.networkId, self.anchor, searchQuery))
		else
			-- Mismo criterio que instalar: revalida el disquete de
			-- desinstalacion aqui mismo antes de enviar, en vez de
			-- descubrir el fallo solo por el mensaje del servidor con la
			-- ventana ya cerrada.
			if not canUninstall then
				if self.player then
					GlobalStorageSiK.UIFeedback.halo(self.player, T("IGUI_GS_CraftMissing"),
						220, 180, 100, 300, { tone = "warning" })
				end
				return
			end
			ISTimedActionQueue.add(GS_AddonInstallAction:new(self.player, def.id, "uninstall", self.networkId, self.anchor, searchQuery))
		end
		self:destroy()
	end })
	if locked then
		UI.Controls.setTooltip(actionBtn, T("IGUI_GS_CraftMissing"))
	end
	self._actionBtn = actionBtn
	return y + CONTROL_METRICS.buttonHeight + pad
end

--- (Re)construye todo el contenido a partir del estado actual.
function GS_AddonManageUI:buildLayout()
	for i = #(self._sikCards or {}), 1, -1 do
		self._sikCards[i]:dispose()
	end
	self._sikCards = {}
	for i = #(self.childrenInOrder or {}), 1, -1 do
		local child = self.childrenInOrder[i]
		local chrome = child == self.closeControl or child == self.titleControl
			or child == self.headerStatusControl
		if not chrome then
			self:removeChild(child)
			if child.removeFromUIManager then child:removeFromUIManager() end
		end
	end

	local def = addonDefinition(self.addonId)
	if not def then
		self:destroy()
		return
	end

	local pad = self.padding
	local textW = self.width - pad * 2
	local y = self.headerHeight + pad

	local description = UI.Controls.copyText(self, {
		x = pad, y = y, w = textW,
		text = T(def.descKey or "IGUI_GS_AddonDescGeneric"),
		tone = "textMuted", playerNum = self.playerNum,
	})
	y = y + description.height + 6

	local modActive = addonIsActive(def.id)
	-- BUG REAL encontrado (reportado: "aparece como instalado en la bahia
	-- pero la ventana dice Instalar en vez de Desinstalar"): esto llamaba a
	-- serializeForTerminal(), que lee el mirror LOCAL de ModData en el
	-- cliente - el mismo tipo de dato desincronizado ya documentado para el
	-- chequeo de la antena. self.installed llega ya resuelto desde quien
	-- abre esta ventana (la bahia), a partir de state.installedAddons -
	-- el mismo dato ya confirmado por el servidor que usa la propia bahia
	-- para pintar el icono, así que ambos SIEMPRE coinciden.
	local installed = self.installed or {}
	local isInstalled = installed[def.id] ~= nil

	if not modActive then
		local status = UI.Controls.status(self, {
			x = pad, y = y, text = T("IGUI_GS_AddonStatusModOff"),
			tone = "danger", playerNum = self.playerNum,
		})
		y = y + status.height + 8
	end

	-- Que item CONCRETO esta instalado (igual que en la bahia/panel Addons -
	-- ver GS_TerminalUI_Addons.lua, mismo dato, misma resolucion de nombre).
	-- El nombre real del item YA incluye el tier (ver
	-- gssik_addon_tablet/Translate/*/ItemName.json: "Antena WiFi GS T2"), asi
	-- que esto ya informa del tier sin nada mas que añadir aqui.
	local installedItemType = isInstalled and installed[def.id].itemType or nil
	if installedItemType then
		local itemName = GlobalStorageSiK.I18n.typeDisplayName(installedItemType)
		local status = UI.Controls.status(self, {
			x = pad, y = y, text = T("IGUI_GS_AddonInstalledItem", itemName),
			tone = "success", playerNum = self.playerNum,
		})
		y = y + status.height + 8
	end

	-- Cadena de tiers (ver def.tierItems, hoy solo la usa la Antena WiFi GS
	-- del addon Tablet, T1->T2->T3) - pedido explicitamente: "que las 3 se
	-- indiquen claramente en la ranura de addon adecuada". Lista compacta
	-- (no tarjetas de receta completas, serian demasiado altas para 3
	-- niveles) con el tier instalado/en inventario resaltado en verde.
	if def.tierItems and #def.tierItems > 0 then
		local inv = self.player and self.player:getInventory()
		local rows = {}
		for i = 1, #def.tierItems do
			local tier = def.tierItems[i]
			local tierName = GlobalStorageSiK.I18n.typeDisplayName(tier.item)
			local isActiveTier = installedItemType == tier.item
			local owned = inv and (inv:getItemCountRecurse(tier.item) or 0) >= 1
			local statusKey = isActiveTier and "IGUI_GS_TierInstalled" or (owned and "IGUI_GS_TierInInventory" or "IGUI_GS_TierNotOwned")
			rows[#rows + 1] = {
				itemType = tier.item, text = tierName .. " - " .. T(statusKey),
				ok = isActiveTier or owned,
			}
		end
		y = y + addRequirementCard(self, y, textW, nil, rows) + 10
	end

	-- Bloque de instalacion, claramente diferenciado (pedido explicitamente:
	-- "un bloque superior claramente diferenciado... si detectamos el
	-- periferico, si disponemos del disquete, si tenemos todos los
	-- requisitos, valorados visualmente"). Antes esto eran simples avisos de
	-- texto suelto que solo aparecian cuando FALTABA algo (via la primera
	-- razon que devolviera hasRequiredInstallItems) - ahora se comprueban los
	-- 3 requisitos por separado y se muestran siempre con icono real +
	-- color, igual que el resto de ventanas modales del mod.
	local canInstall = false
	local canUninstall = true
	if modActive and isInstalled then
		-- Bloque de desinstalacion (pedido explicitamente: "para desinstalar,
		-- tambien mostraremos los requisitos, que basicamente sera el
		-- disquete de desinstalacion... que no se consumira, como el resto
		-- de disquetes" + "obviamente necesitaremos el lector/disquetera, ya
		-- sea instalado como addon o en el inventario, como el resto de
		-- ejecuciones de programas"). Mismo patron visual que el bloque de
		-- instalacion de abajo: tarjeta + addRequirementLine, dimensionada al
		-- final.
		local uninstallDiskItem = GlobalStorageSiK.Addons.uninstallDiskItem()
		local hasReader = GlobalStorageSiK.Addons.hasReaderAvailable(self.player, self.networkId, self.anchor)
		local inv = self.player and self.player:getInventory()
		local hasUninstallDisk = uninstallDiskItem and inv and (inv:getItemCountRecurse(uninstallDiskItem) or 0) >= 1
		local requiredSkill = GlobalStorageSiK.Sandbox.getAddonInstallSkillRequired()
		local hasSkill = requiredSkill <= 0 or (self.player and GlobalStorageSiK.CraftUtils.getElectricityLevel(self.player) >= requiredSkill)
		canUninstall = hasReader and (not uninstallDiskItem or hasUninstallDisk == true) and hasSkill

		local readerType = GlobalStorageSiK.Config and GlobalStorageSiK.Config.ITEM_TERMINAL_READER
		local rows = {
			{ itemType = readerType, text = T("IGUI_GS_AddonReqReader"), ok = hasReader },
		}
		if uninstallDiskItem then
			rows[#rows + 1] = { itemType = uninstallDiskItem,
				text = T("IGUI_GS_AddonReqUninstallDisk"), ok = hasUninstallDisk }
		end
		if requiredSkill > 0 then
			local skillIcon = GlobalStorageSiK.CraftUtils.getPerkTexture and GlobalStorageSiK.CraftUtils.getPerkTexture(Perks and Perks.Electricity)
			rows[#rows + 1] = { texture = skillIcon,
				text = T("IGUI_GS_AddonReqSkill", requiredSkill), ok = hasSkill }
		end
		y = y + addRequirementCard(self, y, textW,
			T("IGUI_GS_AddonReqUninstallTitle"), rows) + 10
		-- Boton justo debajo de SU bloque de requisitos (pedido explicito: no
		-- tiene sentido detras de todas las recetas).
		y = createAddonActionButton(self, y, def, true, canInstall, canUninstall)
	end
	if modActive and not isInstalled then
		local inv = self.player and self.player:getInventory()
		local hasModule = false
		if inv then
			local moduleTypes = addonModuleItemTypes(def.id)
			for i = 1, #moduleTypes do
				if moduleTypes[i] and (inv:getItemCountRecurse(moduleTypes[i]) or 0) >= 1 then
					hasModule = true
					break
				end
			end
		end
		local hasDisk = not def.installDiskItem or def.installDiskItem == ""
			or (inv and (inv:getItemCountRecurse(def.installDiskItem) or 0) >= 1)
		local hasMagazine = self.player and playerKnowsMagazine(self.player, def.id)
		-- BUG REAL cerrado (2026-08-23, pedido explicito: "no veo la
		-- disquetera como requisito global de todas las instalaciones, en su
		-- modal, junto al resto de requisitos") - este bloque nunca
		-- comprobaba ni mostraba la disquetera (aceptando inventario O
		-- instalada como addon, hasReaderAvailable) como requisito, pese a
		-- que el servidor SI la exige (hasRequiredInstallItems) - "Instalar"
		-- podia aparecer habilitado sin ella y el jugador nunca veia ese
		-- requisito en ningun lado de esta ventana.
		local hasReader = GlobalStorageSiK.Addons.hasReaderAvailable(self.player, self.networkId, self.anchor)
		local requiredSkill = GlobalStorageSiK.Sandbox.getAddonInstallSkillRequired()
		local hasSkill = requiredSkill <= 0 or (self.player and GlobalStorageSiK.CraftUtils.getElectricityLevel(self.player) >= requiredSkill)
		canInstall = hasReader and hasModule and hasDisk and hasMagazine and hasSkill

		local readerType = GlobalStorageSiK.Config and GlobalStorageSiK.Config.ITEM_TERMINAL_READER
		local rows = {
			{ itemType = readerType, text = T("IGUI_GS_AddonReqReader"), ok = hasReader },
			{ itemType = def.itemType, text = moduleRequirementText(def), ok = hasModule },
		}
		if def.installDiskItem and def.installDiskItem ~= "" then
			rows[#rows + 1] = { itemType = def.installDiskItem,
				text = itemDisplayName(def.installDiskItem), ok = hasDisk }
		end
		rows[#rows + 1] = { itemType = def.magazineType,
			text = itemDisplayName(def.magazineType), ok = hasMagazine }
		y = y + addRequirementCard(self, y, textW,
			T("IGUI_GS_AddonReqInstallTitle"), rows) + 10
		-- Boton justo debajo de SU bloque de requisitos (pedido explicito: no
		-- tiene sentido detras de todas las recetas).
		y = createAddonActionButton(self, y, def, false, canInstall, canUninstall)
	end

	if modActive then
		local recipe = nil
		if self.player then
			recipe = GlobalStorageSiK.AddonRecipes.serializeModuleForClient(self.player, def.id)
		end
		if recipe then
			local cardW = textW
			local cardH = GlobalStorageSiK.TerminalRecipeCards.addCard(self, recipe, y, cardW, self.terminal)
			y = y + cardH + 10
		end
	end

	-- Punto de extension ya existente (ver GS_TerminalUI_Addons.lua original):
	-- un addon puede definir def.onRenderPanel para pintar contenido propio
	-- adicional una vez instalado - se mantiene aqui para no perder esa
	-- capacidad al mover el resto del panel a esta ventana.
	if def.onRenderPanel and modActive and isInstalled then
		local state = self.terminal and self.terminal.terminalState
		local ok, nextY = pcall(def.onRenderPanel, self, self.terminal, state, pad, y, textW)
		if ok and type(nextY) == "number" then
			y = nextY
		end
	end

	self._lastSig = statusSignature(self.player, def, self.networkId, self.anchor, self.installed)
	local previousX = self:getX()
	local previousY = self:getY()
	local wasPositioned = self._positioned == true
	UI.Modal.fitContent(self, y, {
		-- y ya apunta al final del contenido, pero el modal necesita conservar
		-- tambien su margen inferior real. Sin esta reserva el clamp de Window
		-- podia dejar el boton de accion unos pixeles fuera del padre.
		contentBottom = true, bottomPadding = pad,
	})
	if wasPositioned then
		self:setX(previousX)
		self:setY(previousY)
	else
		self._positioned = true
	end
	if GlobalStorageSiK.UIDebug and GlobalStorageSiK.UIDebug.enabled and GlobalStorageSiK.UIDebug.enabled() then
		GlobalStorageSiK.UIDebug.dumpTree(self, "AddonManageUI")
		GlobalStorageSiK.UIDebug.checkOverlaps(self, "AddonManageUI")
	end
end

--- Helper local de etiqueta envuelta (mismo patron que el resto del terminal).
---@param x number
---@param y number
---@param text string
---@param maxW number
---@param r number
---@param g number
---@param b number
---@return number
function GS_AddonManageUI:addWrappedLabel(x, y, text, maxW, r, g, b)
	local copy = UI.Controls.copyText(self, {
		x = x, y = y, w = maxW, text = text,
		tone = "text", playerNum = self.playerNum,
	})
	return y + copy.height
end

--- Refresca sin reabrir (mismas guardas que GS_ReaderAcquireUI:refresh()).
---@param force boolean|nil
function GS_AddonManageUI:refresh(force)
	if not self.getIsVisible or not self:getIsVisible() then
		return
	end
	if not force and isMouseButtonDown and isMouseButtonDown(0) then
		self._refreshPending = true
		return
	end
	local def = addonDefinition(self.addonId)
	if not def then
		return
	end
	local sig = statusSignature(self.player, def, self.networkId, self.anchor, self.installed)
	if not force and sig == self._lastSig then
		return
	end
	self._refreshPending = false
	self:buildLayout()
end

---@param addonId string
---@param networkId string|nil
---@param anchor table|nil
---@param terminal GS_TerminalUI|nil
---@param installed table|nil ya confirmado por el servidor (state.installedAddons) -
--- ver nota en buildLayout: sin esto la ventana releia el mirror local de
--- ModData y podia mostrar "Instalar" para un addon que la propia bahia
--- ya pintaba como instalado.
function GlobalStorageSiK.AddonManageUI.show(addonId, networkId, anchor, terminal, installed)
	if not addonId or not addonDefinition(addonId) then
		return
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	if not player then
		return
	end
	if GlobalStorageSiK.AddonManageUI.instance then
		GlobalStorageSiK.AddonManageUI.instance:destroy()
	end
	-- self.isOwner ya no existe (bug real cerrado, ver comentario en
	-- createAddonActionButton mas arriba) - el boton de instalar/desinstalar
	-- ya no depende de una lectura de permisos calculada en el cliente.
	local ui = GS_AddonManageUI:new(0, 0, PANEL_W, 200)
	ui.player = player
	ui.addonId = addonId
	ui.networkId = networkId
	ui.anchor = anchor
	ui.terminal = terminal
	ui.installed = installed or {}
	ui:initialise()
	UI.Modal.show(ui)
	GlobalStorageSiK.AddonManageUI.instance = ui
end

local function onInventoryChanged()
	if GlobalStorageSiK.AddonManageUI.instance then
		GlobalStorageSiK.AddonManageUI.instance:refresh()
	end
end

local function onRecipeLearned()
	if GlobalStorageSiK.AddonManageUI.instance then
		GlobalStorageSiK.AddonManageUI.instance:refresh()
	end
end

-- BUG REAL cerrado (2026-08-27): el mecanismo de "ventana bloqueada hasta
-- actionResult" (con correlacion action+addonId, hallazgo del equipo de
-- sistemas) queda retirado - superado por la accion cronometrada
-- (GS_AddonInstallAction, ver createAddonActionButton): la ventana se
-- cierra en cuanto se lanza la accion, igual que el resto de acciones
-- cronometradas del mod (GS_ReaderAcquireUI/GS_PCAcquireUI), y el feedback
-- de exito/fallo llega via el toast generico de GS_Client.lua cuando la
-- accion termine de verdad (perform()) - sin ventana viva que necesite
-- correlacionar ni desbloquearse por timeout.

local REFRESH_TICKS = 30
local function onTick()
	local ui = GlobalStorageSiK.AddonManageUI.instance
	if not ui or not ui.getIsVisible or not ui:getIsVisible() then
		return
	end
	ui._tick = (ui._tick or 0) + 1
	if ui._refreshPending or (ui._tick % REFRESH_TICKS == 0) then
		ui:refresh()
	end
end

if Events then
	if Events.OnContainerUpdate then
		Events.OnContainerUpdate.Add(onInventoryChanged)
	end
	local recipeLearnEvents = { "OnPlayerLearnRecipe", "OnLearnRecipe", "OnRecipeLearned", "OnNewRecipe" }
	for i = 1, #recipeLearnEvents do
		local ev = Events[recipeLearnEvents[i]]
		if ev and ev.Add then
			ev.Add(onRecipeLearned)
		end
	end
	if Events.OnTick then
		Events.OnTick.Add(onTick)
	end
end

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
	GS_ReaderAcquireUI.lua/GS_PCAcquireUI.lua (mismo chrome, mismo refresco en
	vivo de bajo coste) - no es una clase nueva desde cero, es el mismo molde
	ya probado.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "GS_I18n"
require "GS_NetClient"
require "GS_AddonRegistry"
require "GS_AddonRecipes"
require "GS_TerminalRecipeCards"
require "GS_TerminalUI_Chrome"
require "GS_TerminalUI_Scroll"

GlobalStorageSiK.AddonManageUI = {}
GlobalStorageSiK.AddonManageUI.instance = nil

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local PAD = 14
local BTN_H = FONT_HGT_SMALL + 10
local PANEL_W = 640

GS_AddonManageUI = ISPanel:derive("GS_AddonManageUI")

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
	local modActive = GlobalStorageSiK.AddonRegistry.isModActive(def.id)
	local isInstalled = (installed or {})[def.id] ~= nil
	local knowsMag = player and GlobalStorageSiK.AddonRegistry.playerKnowsMagazine(player, def.id)
	local canInstall = player and GlobalStorageSiK.AddonRegistry.canInstallModule(player, def.id, networkId, anchor)
	local uninstallDiskItem = GlobalStorageSiK.Addons.uninstallDiskItem()
	local hasUninstallDisk = uninstallDiskItem and player and player:getInventory()
		and (player:getInventory():getItemCountRecurse(uninstallDiskItem) or 0) >= 1
	return string.format("%s|%s|%s|%s|%s", tostring(modActive), tostring(isInstalled), tostring(knowsMag), tostring(canInstall), tostring(hasUninstallDisk))
end

function GS_AddonManageUI:initialise()
	ISPanel.initialise(self)
	-- Mismo fondo que la ventana principal del terminal (ver nota identica en
	-- GS_ReaderAcquireUI.lua).
	self.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.98 }
	self.borderColor = { r = 0, g = 0, b = 0, a = 1 }
	self:setAlwaysOnTop(true)
	self.headerHeight = FONT_HGT_MEDIUM + PAD + 4
	GlobalStorageSiK.TerminalChrome.setupModalPanel(self, function()
		self:destroy()
	end, PAD)
	self:buildLayout()
end

function GS_AddonManageUI:destroy()
	GlobalStorageSiK.AddonManageUI.instance = nil
	self:setVisible(false)
	if self.removeFromUIManager then
		self:removeFromUIManager()
	end
end

function GS_AddonManageUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then
		self:destroy()
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
	if not (def and self.isOwner) then
		return y
	end
	local pad = self.padding
	local textW = self.width - pad * 2
	local btnLabel = isInstalled and T("IGUI_GS_AddonUninstallBtn") or T("IGUI_GS_AddonInstallBtn")
	local searchQuery = self.terminal and self.terminal.searchEntry and self.terminal.searchEntry:getText() or ""
	local actionBtn = GlobalStorageSiK.TerminalChrome.createNeatButton(pad, y, textW, BTN_H, btnLabel, self, function()
		-- BUG REAL encontrado (reportado: "si no tenemos antena en el
		-- inventario no da feedback, falla en silencio aunque el boton
		-- reacciona"): antes esto enviaba el comando y cerraba la ventana
		-- SIEMPRE, sin comprobar si de verdad se podia instalar - si el
		-- servidor lo rechazaba, el jugador nunca se enteraba de nada
		-- porque la ventana ya se habia cerrado. Revalida en el momento
		-- del clic (igual que GS_ReaderAcquireUI.lua) y avisa con un halo
		-- si falta algo, en vez de enviar un comando que sabemos que va
		-- a fallar.
		if not isInstalled then
			local recheckOk = self.player and GlobalStorageSiK.AddonRegistry.canInstallModule(self.player, def.id, self.networkId, self.anchor)
			if not recheckOk then
				if self.player and self.player.setHaloNote then
					self.player:setHaloNote(T("IGUI_GS_CraftMissing"), 220, 180, 100, 300)
				end
				return
			end
			GlobalStorageSiK.NetClient.sendCommand("installAddon", { addonId = def.id, searchQuery = searchQuery })
		else
			-- Mismo criterio que instalar: revalida el disquete de
			-- desinstalacion aqui mismo antes de enviar, en vez de
			-- descubrir el fallo solo por el mensaje del servidor con la
			-- ventana ya cerrada.
			if not canUninstall then
				if self.player and self.player.setHaloNote then
					self.player:setHaloNote(T("IGUI_GS_CraftMissing"), 220, 180, 100, 300)
				end
				return
			end
			GlobalStorageSiK.NetClient.sendCommand("uninstallAddon", { addonId = def.id, searchQuery = searchQuery })
		end
		self:destroy()
	end)
	if not isInstalled then
		actionBtn:setEnable(canInstall == true)
	else
		actionBtn:setEnable(canUninstall == true)
	end
	self:addChild(actionBtn)
	return y + BTN_H + pad
end

--- (Re)construye todo el contenido a partir del estado actual.
function GS_AddonManageUI:buildLayout()
	for i = #(self.childrenInOrder or {}), 1, -1 do
		local child = self.childrenInOrder[i]
		if child ~= self.closeBtn then
			self:removeChild(child)
			if child.removeFromUIManager then child:removeFromUIManager() end
		end
	end

	local def = GlobalStorageSiK.AddonRegistry.get(self.addonId)
	if not def then
		self:destroy()
		return
	end

	local pad = self.padding
	local textW = self.width - pad * 2
	local y = self.headerHeight + pad

	local descLines = GlobalStorageSiK.TerminalChrome.wrapTextLines(T(def.descKey or "IGUI_GS_AddonDescGeneric"), textW, UIFont.Small)
	for _, line in ipairs(descLines) do
		local lbl = ISLabel:new(pad, y, FONT_HGT_SMALL, line, 0.75, 0.78, 0.82, 1, UIFont.Small, true)
		lbl:initialise()
		self:addChild(lbl)
		y = y + FONT_HGT_SMALL + 2
	end
	y = y + 6

	local modActive = GlobalStorageSiK.AddonRegistry.isModActive(def.id)
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
		local lbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_AddonStatusModOff"), 0.72, 0.55, 0.45, 1, UIFont.Small, true)
		lbl:initialise()
		self:addChild(lbl)
		y = y + FONT_HGT_SMALL + 8
	end

	-- Que item CONCRETO esta instalado (igual que en la bahia/panel Addons -
	-- ver GS_TerminalUI_Addons.lua, mismo dato, misma resolucion de nombre).
	-- El nombre real del item YA incluye el tier (ver
	-- gssik_addon_tablet/Translate/*/ItemName.json: "Antena WiFi GS T2"), asi
	-- que esto ya informa del tier sin nada mas que añadir aqui.
	local installedItemType = isInstalled and installed[def.id].itemType or nil
	if installedItemType then
		local itemName = GlobalStorageSiK.I18n.typeDisplayName(installedItemType)
		local lbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_AddonInstalledItem", itemName), 0.5, 0.72, 0.55, 1, UIFont.Small, true)
		lbl:initialise()
		self:addChild(lbl)
		y = y + FONT_HGT_SMALL + 8
	end

	-- Cadena de tiers (ver def.tierItems, hoy solo la usa la Antena WiFi GS
	-- del addon Tablet, T1->T2->T3) - pedido explicitamente: "que las 3 se
	-- indiquen claramente en la ranura de addon adecuada". Lista compacta
	-- (no tarjetas de receta completas, serian demasiado altas para 3
	-- niveles) con el tier instalado/en inventario resaltado en verde.
	if def.tierItems and #def.tierItems > 0 then
		local tierCardTop = y
		local tierCard = GlobalStorageSiK.TerminalChrome.createSectionCard(pad, tierCardTop, textW, 10)
		self:addChild(tierCard)
		y = y + 8
		local inv = self.player and self.player:getInventory()
		for i = 1, #def.tierItems do
			local tier = def.tierItems[i]
			local tierName = GlobalStorageSiK.I18n.typeDisplayName(tier.item)
			local isActiveTier = installedItemType == tier.item
			local owned = inv and (inv:getItemCountRecurse(tier.item) or 0) >= 1
			local statusKey = isActiveTier and "IGUI_GS_TierInstalled" or (owned and "IGUI_GS_TierInInventory" or "IGUI_GS_TierNotOwned")
			local line = tierName .. " - " .. T(statusKey)
			y = GlobalStorageSiK.TerminalChrome.addRequirementLine(self, pad + 8, y, textW - 16, tier.item, line, isActiveTier or owned)
			y = y + 4
		end
		y = y + 4
		GlobalStorageSiK.TerminalChrome.resizeSectionCard(tierCard, pad, tierCardTop, textW, y - tierCardTop)
		y = y + 10
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
		canUninstall = hasReader and (not uninstallDiskItem or hasUninstallDisk == true)

		local reqLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_AddonReqUninstallTitle"), 0.82, 0.85, 0.9, 1, UIFont.Small, true)
		reqLbl:initialise()
		self:addChild(reqLbl)
		y = y + FONT_HGT_SMALL + 6

		local cardTop = y
		local card = GlobalStorageSiK.TerminalChrome.createSectionCard(pad, cardTop, textW, 10)
		self:addChild(card)
		y = y + 8
		local readerType = GlobalStorageSiK.Config and GlobalStorageSiK.Config.ITEM_TERMINAL_READER
		y = GlobalStorageSiK.TerminalChrome.addRequirementLine(self, pad + 8, y, textW - 16, readerType, T("IGUI_GS_AddonReqReader"), hasReader)
		y = y + 6
		if uninstallDiskItem then
			y = GlobalStorageSiK.TerminalChrome.addRequirementLine(self, pad + 8, y, textW - 16, uninstallDiskItem, T("IGUI_GS_AddonReqUninstallDisk"), hasUninstallDisk)
			y = y + 6
		end
		y = y + 2
		GlobalStorageSiK.TerminalChrome.resizeSectionCard(card, pad, cardTop, textW, y - cardTop)
		y = y + 10
		-- Boton justo debajo de SU bloque de requisitos (pedido explicito: no
		-- tiene sentido detras de todas las recetas).
		y = createAddonActionButton(self, y, def, true, canInstall, canUninstall)
	end
	if modActive and not isInstalled then
		local inv = self.player and self.player:getInventory()
		local hasModule = false
		if inv then
			local moduleTypes = GlobalStorageSiK.AddonRegistry.moduleItemTypes(def)
			for i = 1, #moduleTypes do
				if moduleTypes[i] and (inv:getItemCountRecurse(moduleTypes[i]) or 0) >= 1 then
					hasModule = true
					break
				end
			end
		end
		local hasDisk = not def.installDiskItem or def.installDiskItem == ""
			or (inv and (inv:getItemCountRecurse(def.installDiskItem) or 0) >= 1)
		local hasMagazine = self.player and GlobalStorageSiK.AddonRegistry.playerKnowsMagazine(self.player, def.id)
		canInstall = hasModule and hasDisk and hasMagazine

		local reqLbl = ISLabel:new(pad, y, FONT_HGT_SMALL, T("IGUI_GS_AddonReqInstallTitle"), 0.82, 0.85, 0.9, 1, UIFont.Small, true)
		reqLbl:initialise()
		self:addChild(reqLbl)
		y = y + FONT_HGT_SMALL + 6

		-- La tarjeta de fondo se crea y se añade PRIMERO (para que quede
		-- detras de las lineas de requisito, añadidas justo despues) y se
		-- redimensiona AL FINAL, una vez conocido el contenido real - mismo
		-- orden que createSectionCard/resizeSectionCard usan en el resto del
		-- terminal, para no repetir el bug ya documentado de dimensionar
		-- despues de rellenar contenido.
		local cardTop = y
		local card = GlobalStorageSiK.TerminalChrome.createSectionCard(pad, cardTop, textW, 10)
		self:addChild(card)
		y = y + 8
		y = GlobalStorageSiK.TerminalChrome.addRequirementLine(self, pad + 8, y, textW - 16, def.itemType, T("IGUI_GS_AddonReqModule"), hasModule)
		y = y + 6
		if def.installDiskItem and def.installDiskItem ~= "" then
			y = GlobalStorageSiK.TerminalChrome.addRequirementLine(self, pad + 8, y, textW - 16, def.installDiskItem, T("IGUI_GS_AddonReqDisk"), hasDisk)
			y = y + 6
		end
		y = GlobalStorageSiK.TerminalChrome.addRequirementLine(self, pad + 8, y, textW - 16, def.magazineType, T("IGUI_GS_AddonReqMagazine"), hasMagazine)
		y = y + 8
		GlobalStorageSiK.TerminalChrome.resizeSectionCard(card, pad, cardTop, textW, y - cardTop)
		y = y + 10
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
	self:setHeight(y)
	GlobalStorageSiK.TerminalChrome.layoutModalChrome(self, pad)
	if not self._positioned then
		self:setY(math.floor((getCore():getScreenHeight() - self.height) / 2))
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
	local lines = GlobalStorageSiK.TerminalChrome.wrapTextLines(text, maxW, UIFont.Small)
	for _, line in ipairs(lines) do
		local lbl = ISLabel:new(x, y, FONT_HGT_SMALL, line, r, g, b, 1, UIFont.Small, true)
		lbl:initialise()
		self:addChild(lbl)
		y = y + FONT_HGT_SMALL + 2
	end
	return y
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
	local def = GlobalStorageSiK.AddonRegistry.get(self.addonId)
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
	if not addonId or not GlobalStorageSiK.AddonRegistry.get(addonId) then
		return
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getPlayer()
	if not player then
		return
	end
	if GlobalStorageSiK.AddonManageUI.instance then
		GlobalStorageSiK.AddonManageUI.instance:destroy()
	end
	local isOwner = true
	if GlobalStorageSiK.Permissions and GlobalStorageSiK.Permissions.isOwnerPlayer then
		isOwner = GlobalStorageSiK.Permissions.isOwnerPlayer(player, networkId)
	end
	local ui = GS_AddonManageUI:new(0, 0, PANEL_W, 200)
	ui.player = player
	ui.addonId = addonId
	ui.networkId = networkId
	ui.anchor = anchor
	ui.terminal = terminal
	ui.installed = installed or {}
	ui.isOwner = isOwner
	ui:initialise()
	ui:addToUIManager()
	GlobalStorageSiK.TerminalChrome.centerModal(ui)
	GlobalStorageSiK.TerminalChrome.finalizeModalShow(ui)
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

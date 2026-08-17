--[[
	GlobalStorageSiK - Tooltip global "cuánto tengo en mi red"
	Autor: SiK
	Fecha: 2026-07-07
	Descripción: Añade, a CUALQUIER tooltip de inventario vanilla, una línea por
	cada red del jugador que contenga ese fullType (estilo Home Inventory).
]]

require "GS_NetClient"
require "GS_I18n"
require "GS_Index"
require "GS_Sandbox"
require "GS_Log"
require "GS_ItemTaxonomy"

GlobalStorageSiK.ItemNetworkTooltip = {}

local T = GlobalStorageSiK.I18n.text

local cache = {}
local pending = {}
local CACHE_TTL_MS = 4000
local hooksInstalled = false
local activeRenderWrapper = nil

-- Todos los wrappers GS comparten estas guardas. Es importante que no vivan
-- dentro de installHooks(): si otro mod sustituye ISToolTipInv.render despues
-- y tenemos que envolverlo de nuevo, el wrapper GS anterior puede seguir en
-- mitad de la cadena capturada por ese mod. La instancia GS mas reciente es
-- la unica que dibuja nuestra extension; las anteriores se convierten en una
-- pasarela transparente hacia su original y no duplican bloques ni guardas.
local renderingInstances = {}
local failCooldownUntil = setmetatable({}, { __mode = "k" })
local FAIL_COOLDOWN_MS = 8000
local FAIL_LOG_COOLDOWN_MS = 3000
local lastFailLogAt = 0
local lastFailSig = nil

-- Reactivado en v1.2.97 tras confirmar (traza real del jugador) que el bucle
-- de renders encadenados que rompia el tooltip era entre "Show VHS skills in
-- tooltip" y "Magic Accessories" - ninguno de los dos es nuestro codigo, y la
-- traza no mostraba GlobalStorageSiK en ningun punto de la pila mientras este
-- parche ya estaba desactivado (v1.2.96), asi que no era la causa. Con la
-- guarda por instancia (v1.2.94, "original" siempre capturado por closure,
-- nunca self:render() dinamico) y sin reenviar errores de "original" hacia
-- arriba (mas abajo), no deberiamos añadir inestabilidad a esa cadena aunque
-- sigamos compartiendo la misma clase parcheada que esos otros mods.
local FEATURE_ENABLED = true

--- Invalida toda la cache (llamar tras cualquier deposito/retiro de red: sin
--- esto, el tooltip podia seguir mostrando la cantidad de antes de la
--- transferencia hasta que expirase el TTL).
function GlobalStorageSiK.ItemNetworkTooltip.invalidateAll()
	cache = {}
end

--- Recibe la respuesta del servidor con los conteos por red de un fullType.
---@param fullType string|nil
---@param networks table[]
---@param hasAnyNetwork boolean|nil si el jugador tiene AL MENOS una red accesible (independientemente de si este fullType esta en ella) - distingue "no tienes redes todavia" de "no esta en ninguna de tus redes"
function GlobalStorageSiK.ItemNetworkTooltip.onCountsReceived(fullType, networks, hasAnyNetwork)
	if not fullType then
		return
	end
	cache[fullType] = {
		networks = networks or {},
		hasAnyNetwork = hasAnyNetwork and true or false,
		ts = getTimestampMs and getTimestampMs() or 0,
	}
	pending[fullType] = nil
end

--- En singleplayer real (no anfitrion), isClient()/isServer() son ambos
--- false y GlobalStorageSiK.NetClient.sendCommand nunca llega a enviar nada
--- (corta pronto si not isClient()) — el mismo caso ya documentado en
--- Permissions.shouldEnforce(). Sin este atajo, el tooltip global nunca
--- funcionaba en partidas de un solo jugador: como cliente y "servidor"
--- comparten la misma VM de Lua en SP, podemos llamar la logica de
--- GS_Index.lua directamente, sin ronda de red.
---@return boolean
local function isTrueSingleplayer()
	return not (isClient and isClient()) and not (isServer and isServer())
end

local function requestCounts(fullType)
	if pending[fullType] then
		return
	end
	if isTrueSingleplayer() then
		local player = GlobalStorageSiK.NetClient.getPlayer()
		if player and GlobalStorageSiK.Index and GlobalStorageSiK.Index.getNetworkCountsForItem then
			local ok, networks, hasAnyNetwork = pcall(GlobalStorageSiK.Index.getNetworkCountsForItem, player, fullType)
			if ok then
				GlobalStorageSiK.ItemNetworkTooltip.onCountsReceived(fullType, networks, hasAnyNetwork)
			end
		end
		return
	end
	pending[fullType] = true
	GlobalStorageSiK.NetClient.sendCommand("getItemNetworkCounts", { fullType = fullType })
end

--- Devuelve conteos cacheados y dispara refresco en segundo plano si caducó.
--- Devuelve tambien "loaded" para poder distinguir "todavia sin respuesta"
--- (no dibujar nada, evita parpadear un falso "no esta en ninguna red" antes
--- de que llegue el primer dato) de "ya consultado y de verdad no esta en
--- ninguna red" (aqui si hay que avisar, a peticion del usuario).
---@param fullType string
---@return table[]|nil, boolean loaded, boolean hasAnyNetwork
local function getCachedCounts(fullType)
	local entry = cache[fullType]
	local now = getTimestampMs and getTimestampMs() or 0
	if not entry or (now - entry.ts) >= CACHE_TTL_MS then
		requestCounts(fullType)
	end
	if not entry then
		return nil, false, false
	end
	return entry.networks, true, entry.hasAnyNetwork
end

--- Version publica de getCachedCounts: la usa tambien nuestra propia UI
--- (pestaña Almacen) para mostrar el desglose de OTRAS redes del jugador
--- que tengan el mismo fullType, ademas de la cantidad de la red activa que
--- ya conoce al instante (sin ronda de red). Misma cache/TTL/fuente que el
--- tooltip global: informacion consistente en los dos sitios.
---@param fullType string
---@return table[]|nil, boolean
function GlobalStorageSiK.ItemNetworkTooltip.getCachedCounts(fullType)
	return getCachedCounts(fullType)
end

local NET_FONT = UIFont.Small
local LINE_PAD = 4

--- Trunca una linea al ancho disponible (reutiliza el helper ya usado en el
--- resto de la UI del mod si esta cargado; si no, la deja tal cual).
---@param text string
---@param maxW number
---@return string
local function truncate(text, maxW)
	if GlobalStorageSiK.TerminalChrome and GlobalStorageSiK.TerminalChrome.truncateText then
		return GlobalStorageSiK.TerminalChrome.truncateText(text, maxW, NET_FONT)
	end
	return text
end

--- Interpretacion PROPIA (no la del mod "Show VHS skills in tooltip", retirado
--- por incompatibilidad real con nuestro propio parche de ISToolTipInv.render
--- Y el de "Magic Accessories" - ver installHooks mas abajo) de que skill
--- enseña un item: lee directamente los campos de script vainilla
--- SkillTrained/LvlSkillTrained/getMaxLevelTrained (misma API publica que ya
--- usa el propio juego en ISReadABook.lua para libros), sin depender de
--- ningun otro mod ni reconstruir su tabla de datos. Se excluyen
--- libros/revistas (isLiterature): vanilla YA les muestra esta info en su
--- propio tooltip nativo, duplicarla ahi no aporta nada.
---
--- BUG REAL CONFIRMADO (2026-08-14, reportado explicitamente): el comentario
--- de esta funcion siempre dijo que cubria "cintas VHS y cualquier otro item
--- moddeado con estos mismos campos", pero NUNCA fue cierto para VHS de
--- verdad - las cintas VHS NO usan getSkillTrained()/SkillBook (eso es
--- exclusivo de libros), sino un sistema completamente distinto: el item
--- referencia un indice de "medio grabado" (getRecordedMediaIndex()) que
--- apunta a una entrada del global RecMedia (definiciones de radio/TV,
--- scripteadas), cuyas lineas de dialogo llevan "codigos" de 3 letras
--- (SPR, CRP, DOC...) que el propio vainilla interpreta en
--- shared/RadioCom/ISRadioInteractions.lua para dar XP al verlo/escucharlo -
--- confirmado leyendo ese fichero vainilla directamente, mismo trigrama que
--- usa el mod retirado "Show VHS skills in tooltip" (workshop 3716522633,
--- ver SVSIT_data.lua/SVSIT_logic.lua/SVSIT_parser.lua para la referencia
--- original de este enfoque). Ver getVHSTrainingLines mas abajo.
---@param item table|nil InventoryItem
---@return string[]|nil
local function getBookSkillTrainingLines(item)
	if not item or not item.getSkillTrained then
		return nil
	end
	local okLit, isLit = pcall(function() return item.isLiterature and item:isLiterature() end)
	if okLit and isLit then
		return nil
	end
	local okKey, key = pcall(function() return item:getSkillTrained() end)
	if not okKey or not key or key == "" then
		return nil
	end
	local perkName = key
	local okPerk, perk = pcall(function()
		return rawget(_G, "SkillBook") and SkillBook[key] and SkillBook[key].perk
	end)
	if okPerk and perk and perk.getName then
		local okName, name = pcall(function() return perk:getName() end)
		if okName and name and name ~= "" then
			perkName = name
		end
	end
	local okLvl, lvl = pcall(function() return item:getLvlSkillTrained() end)
	local okMax, maxLvl = pcall(function() return item:getMaxLevelTrained() end)
	local line
	if okLvl and lvl and lvl >= 0 and okMax and maxLvl and maxLvl >= 0 then
		line = T("IGUI_GS_VHSSkillLineRange", perkName, tostring(lvl), tostring(maxLvl))
	elseif okLvl and lvl and lvl >= 0 then
		line = T("IGUI_GS_VHSSkillLine", perkName, tostring(lvl))
	else
		line = perkName
	end
	return { T("IGUI_GS_VHSSkillHeader"), line }
end

--- Trigrama -> clave getText del perk, copiado DIRECTAMENTE de
--- shared/RadioCom/ISRadioInteractions.lua (linea Interactions.XXX =
--- function(...) doSkill(_player, _amount, getText("IGUI_perks_..."),
--- Perks...) end) - fuente unica de verdad vainilla, no una copia de otro
--- mod. Solo trigramas de SKILL (Interactions tambien tiene ANG/BOR/END/...
--- para stats como hambre/animo, deliberadamente fuera de este mapa).
local VHS_TRIGRAM_TO_PERK_KEY = {
	SPR = "IGUI_perks_Sprinting", LFT = "IGUI_perks_Lightfooted", NIM = "IGUI_perks_Nimble",
	SNE = "IGUI_perks_Sneaking", BAA = "IGUI_perks_Axe", BUA = "IGUI_perks_Blunt",
	CRP = "IGUI_perks_Carpentry", COO = "IGUI_perks_Cooking", FRM = "IGUI_perks_Farming",
	DOC = "IGUI_perks_Doctor", ELC = "IGUI_perks_Electricity", MTL = "IGUI_perks_MetalWelding",
	FKN = "IGUI_perks_FlintKnapping", CRV = "IGUI_perks_Carving", AIM = "IGUI_perks_Aiming",
	REL = "IGUI_perks_Reloading", FIS = "IGUI_perks_Fishing", TRA = "IGUI_perks_Trapping",
	FOR = "IGUI_perks_Foraging", TAI = "IGUI_perks_Tailoring", MEC = "IGUI_perks_Mechanics",
	CMB = "IGUI_perks_Combat", SPE = "IGUI_perks_Spear", SBU = "IGUI_perks_SmallBlunt",
	LBA = "IGUI_perks_LongBlade", SBA = "IGUI_perks_SmallBlade", MAS = "IGUI_perks_Masonry",
	POT = "IGUI_perks_Pottery", BLA = "IGUI_perks_Blacksmith", GLA = "IGUI_perks_Glassmaking",
	HUS = "IGUI_perks_Husbandry", BUT = "IGUI_perks_Butchering", TRK = "IGUI_perks_Tracking",
}

--- id de RecMedia -> { skillNames = {...}, empty = boolean }. Construido UNA
--- vez (perezoso, en el primer item VHS que se inspeccione) recorriendo el
--- global RecMedia entero - caro para hacerlo por item, barato hacerlo una
--- sola vez para toda la sesion (RecMedia no cambia en caliente).
local recMediaSkillsById = nil
--- nombre de pantalla del item -> id de RecMedia, para poder correlacionar
--- un InventoryItem con su entrada de RecMedia. NO se usa
--- rm:getMediaDataFromIndex(index) directo pese a que
--- item:getRecordedMediaIndex() SI funciona: ese metodo espera un "short"
--- del lado Java y Kahlua siempre pasa numeros como Double, lo que revienta
--- con un error real de tipo (mismo hallazgo exacto que el mod retirado
--- "Show VHS skills in tooltip", ver comentario en su SVSIT_logic.lua) - por
--- eso se correlaciona por NOMBRE, mismo rodeo que ese mod ya validaba en
--- producción.
local mediaIdByDisplayName = nil

local function ensureRecMediaIndexBuilt()
	if recMediaSkillsById then
		return
	end
	recMediaSkillsById = {}
	mediaIdByDisplayName = {}
	if not rawget(_G, "RecMedia") then
		return
	end
	for id, media in pairs(RecMedia) do
		local skillNames = {}
		local seen = {}
		if media.lines then
			for i = 1, #media.lines do
				local line = media.lines[i]
				local codes = line and line.codes
				if codes then
					-- BUG REAL CORREGIDO (2026-08-14, reportado con un caso real:
					-- "VHS: Cultivar hierbas en casa" mostraba "nada que aprender"
					-- pese a enseñar Farming): confirmado leyendo directamente
					-- shared/RecordedMedia/recorded_media.lua (fuente vainilla, no
					-- una suposicion) que cada codigo lleva SIEMPRE una cantidad
					-- pegada sin separador, ej. codes = "FRM+1" o
					-- "BOR-1,FRM+1,RCP=base:basil growing season". La version
					-- anterior buscaba el trigrama como token EXACTO delimitado por
					-- comas (",FRM,") y nunca podia coincidir con ",FRM+1,". Ahora
					-- se trocea por comas y se lee solo el PREFIJO de letras
					-- mayusculas de cada trozo (se detiene solo en encontrar el
					-- primer caracter no-mayuscula, sea "+", "-" o el "=" de RCP=),
					-- que es precisamente el trigrama sin su cantidad.
					for segment in tostring(codes):gmatch("[^,]+") do
						local trigram = segment:match("^%u+")
						local perkKey = trigram and VHS_TRIGRAM_TO_PERK_KEY[trigram]
						if perkKey and not seen[perkKey] then
							seen[perkKey] = true
							skillNames[#skillNames + 1] = getText(perkKey)
						end
					end
				end
			end
		end
		recMediaSkillsById[id] = { skillNames = skillNames }
		local okName, displayName = pcall(getText, media.itemDisplayName)
		if okName and displayName and displayName ~= "" then
			mediaIdByDisplayName[displayName] = id
		end
	end
end

--- Ver comentario largo de getBookSkillTrainingLines - camino REAL para
--- cintas VHS (y cualquier otro "medio grabado" que use el mismo sistema
--- vainilla de RecMedia, no solo items con "VHS" en el fullType). A peticion
--- explicita: si el item ES un medio grabado correlacionado pero no enseña
--- nada, se devuelve la linea "nada que aprender" en vez de no mostrar
--- nada - distingue "confirmado que no enseña" de "no hemos podido saber
--- que es este item".
---@param item table|nil InventoryItem
---@return string[]|nil
local function getVHSTrainingLines(item)
	if not item or not item.getRecordedMediaIndex then
		return nil
	end
	local okIdx, idx = pcall(function() return item:getRecordedMediaIndex() end)
	if not okIdx or not idx or idx < 0 then
		return nil
	end
	ensureRecMediaIndexBuilt()
	local okName, displayName = pcall(function() return item:getDisplayName() end)
	local mediaId = okName and displayName and mediaIdByDisplayName[displayName]
	if not mediaId then
		-- No pudimos correlacionar este item concreto con ninguna entrada de
		-- RecMedia por nombre - no afirmar "nada que aprender" sin estar
		-- seguros, mejor no mostrar nada (mismo criterio conservador que el
		-- resto del tooltip).
		return nil
	end
	local data = recMediaSkillsById[mediaId]
	if not data or #data.skillNames == 0 then
		return { T("IGUI_GS_VHSSkillHeader"), T("IGUI_GS_VHSNothingToLearn") }
	end
	local lines = { T("IGUI_GS_VHSSkillHeader") }
	for i = 1, #data.skillNames do
		lines[#lines + 1] = data.skillNames[i]
	end
	return lines
end

---@param item table|nil InventoryItem
---@return string[]|nil
local function getSkillTrainingLines(item)
	local bookLines = getBookSkillTrainingLines(item)
	if bookLines then
		return bookLines
	end
	return getVHSTrainingLines(item)
end

--- Dibuja la extension de red justo debajo del tooltip de item vanilla,
--- DENTRO del mismo render() y con el MISMO ancho que el tooltip (self.width),
--- en vez de un panel ISToolTip flotante aparte.
--- Un overlay separado (posicionado desde ISInventoryPane.updateTooltip, que
--- corre en el ciclo de update(), no de render()) siempre iba un frame por
--- detras de la posicion real del tooltip vanilla (que se recalcula fresca
--- en CADA render() a partir del raton) — de ahi el temblor/rebote que
--- reporto el usuario. Dibujando aqui, en el mismo render() y usando el
--- mismo self.width, queda pegado con precision de pixel y sin desbordar.
-- Ancho maximo al que estamos dispuestos a AMPLIAR el tooltip para que el
-- texto de red/categoria quepa entero (a peticion del usuario: no truncar,
-- ampliar como hace vanilla con descripciones largas). Un tope evita que una
-- red con nombre absurdamente largo, o muchas redes a la vez, produzca un
-- tooltip inmanejable de medio monitor de ancho - mas alla de esto, se
-- vuelve a truncar como red de seguridad.
local MAX_EXT_WIDTH = 520

---@param tr table  el propio ISToolTipInv, ya con x/y/width/height finales de este frame
---@param lines string[]
---@param yOffset number|nil  extra por encima de tr.height (para apilar un segundo bloque distinto debajo del primero)
---@param colorRGB number[]|nil  {r,g,b} del texto (por defecto, el amarillo de red)
---@return number boxH  alto real dibujado, para poder apilar el siguiente bloque
local function drawNetworkExtension(tr, lines, yOffset, colorRGB)
	local textManager = getTextManager()
	local lineHgt = textManager:getFontHeight(NET_FONT)
	colorRGB = colorRGB or { 0.9, 0.85, 0.4 }

	-- Medimos el ancho real de cada linea: si el tooltip vanilla ya es mas
	-- estrecho que lo que necesita nuestro texto (categoria de 3 niveles,
	-- nombres de red largos...), lo AMPLIAMOS aqui mismo antes de dibujar, en
	-- vez de truncar con "...". Con tope en MAX_EXT_WIDTH; si aun asi no cabe,
	-- se trunca esa linea concreta como ultimo recurso.
	local maxTextW = 0
	for i = 1, #lines do
		local w = textManager:MeasureStringX(NET_FONT, lines[i])
		if w > maxTextW then
			maxTextW = w
		end
	end
	local neededW = math.min(MAX_EXT_WIDTH, maxTextW + 16)
	if neededW > tr.width then
		tr:setWidth(neededW)
	end

	local boxW = tr.width
	local boxH = (#lines * lineHgt) + LINE_PAD * 2
	local y = tr.height + 2 + (yOffset or 0)
	local innerW = math.max(20, boxW - 16)
	tr:drawRect(0, y, boxW, boxH, 0.85, 0.05, 0.05, 0.05)
	tr:drawRectBorder(0, y, boxW, boxH, 0.6, 0.9, 0.9, 1)
	for i = 1, #lines do
		tr:drawText(truncate(lines[i], innerW), 8, y + LINE_PAD + (i - 1) * lineHgt, colorRGB[1], colorRGB[2], colorRGB[3], 1, NET_FONT)
	end
	return boxH
end

--- Version minima (sin ajustes de context-menu/joypad, no hacen falta aqui)
--- del render() vanilla real de ISToolTipInv - ver
--- media/lua/client/ISUI/ISToolTipInv.lua del juego base. Se usa SOLO cuando
--- detectamos reentrada (ver mas abajo): otro mod (Magic Accessories,
--- confirmado) nos ha vuelto a llamar para ESTE MISMO tooltip dentro de la
--- misma pasada de render porque delega en nosotros para items normales, y
--- termina rebotando de vuelta a nosotros. Antes, en ese caso nos
--- limitabamos a "return" sin dibujar nada - evitaba el bucle infinito, pero
--- dejaba el tooltip completamente en blanco (ni contenido vanilla ni
--- nuestra linea de red) para CUALQUIER item normal, ya que ese rebote
--- ocurre en el camino normal de Magic Accessories, no en un caso raro.
--- Dibujamos aqui una version real y minima nosotros mismos, sin volver a
--- llamar a "original" (que es quien nos ha llamado en bucle) - rompe el
--- ciclo igual, pero el jugador ve contenido real en vez de un hueco vacio.
---@param self table ISToolTipInv
local function safeFallbackRender(self)
	local mx = getMouseX() + 24
	local my = getMouseY() + 24
	if not self.followMouse then
		mx = self:getX()
		my = self:getY()
		if self.anchorBottomLeft then
			mx = self.anchorBottomLeft.x
			my = self.anchorBottomLeft.y
		end
	end
	self.tooltip:setX(mx)
	self.tooltip:setY(my)
	self.tooltip:setWidth(50)
	self.tooltip:setMeasureOnly(true)
	if self.item then self.item:DoTooltip(self.tooltip) end
	self.tooltip:setMeasureOnly(false)
	local myCore = getCore()
	local maxX = myCore:getScreenWidth()
	local maxY = myCore:getScreenHeight()
	local tw = self.tooltip:getWidth()
	local th = self.tooltip:getHeight()
	self.tooltip:setX(math.max(0, math.min(mx, maxX - tw - 1)))
	self.tooltip:setY(math.max(0, math.min(my, maxY - th - 1)))
	self:setX(self.tooltip:getX())
	self:setY(self.tooltip:getY())
	self:setWidth(tw)
	self:setHeight(th)
	self:drawRect(0, 0, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
	self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
	if self.item then self.item:DoTooltip(self.tooltip) end
end

--- Engancha ISToolTipInv:render para dibujar la extension de red en el mismo
--- frame/posicion que el tooltip de item vanilla. No marca hooksInstalled=true
--- hasta confirmar que pudo parchear de verdad: si ISToolTipInv no existe
--- todavia en el momento en que este fichero se carga, un "hooksInstalled=true"
--- prematuro desactivaria la funcion entera para siempre en esa sesion, sin
--- reintento posible.
function GlobalStorageSiK.ItemNetworkTooltip.installHooks()
	if not FEATURE_ENABLED then
		return false
	end
	if not ISToolTipInv or not ISToolTipInv.render then
		return false
	end
	if activeRenderWrapper and ISToolTipInv.render == activeRenderWrapper then
		hooksInstalled = true
		return true
	end

	local recoveringOuterPosition = hooksInstalled and activeRenderWrapper ~= nil
	local original = ISToolTipInv.render
	-- Guarda de reentrada: reportado un crash en SP (stack overflow) al usar
	-- el mod "Magic Accessories" a la vez - su cadena de "customRender
	-- fallback" (MagicAccessories_Tooltip.lua) acaba re-invocando este mismo
	-- wrapper desde DENTRO de la llamada a "original" (via despacho dinamico
	-- self:render(), que resuelve al valor ACTUAL de ISToolTipInv.render, no
	-- al "original" capturado por closure) - un ciclo A llama a B llama a A
	-- que crece sin limite hasta desbordar la pila de Lua. No podemos tocar
	-- el otro mod, asi que cortamos aqui: si ya estamos dentro de este mismo
	-- wrapper en la pila actual, no volver a invocar nada, simplemente salir.
	--
	-- CRITICO: la guarda debe ser POR INSTANCIA (tabla con self como clave),
	-- NUNCA un unico booleano compartido. El juego mantiene varias instancias
	-- de ISToolTipInv vivas a la vez (el tooltip vanilla del inventario, más
	-- cualquier ISToolTipInv propio como el de las filas de nuestra ventana
	-- Almacén en GS_TerminalUI_Items.lua) y TODAS pasan por este mismo
	-- render() parcheado. Con un booleano compartido, la instancia que
	-- renderiza primero en un frame "gana" la bandera y bloquea el render
	-- de CUALQUIER OTRA instancia distinta ese mismo frame - confirmado como
	-- la causa de que solo un item (el que tenía enganchado el tooltip de
	-- una fila de Almacén) mostrara tooltip y ningún otro item del juego,
	-- ni siquiera vanilla, mostrara nada, en SP y en MP.
	-- Tabla normal (sin metatabla de claves debiles): cada entrada solo vive
	-- entre el "= true" y el "= nil" de la MISMA llamada sincrona de abajo,
	-- nunca se acumula nada que limpiar.
	-- BUG REAL encontrado (traza real de un jugador: "Show VHS skills in
	-- tooltip" se re-invoca a si mismo decenas de veces antes de fallar
	-- dentro de la cadena Magic Accessories -> nosotros): el motor vuelca la
	-- pila COMPLETA en consola en el instante mismo de la excepcion, ANTES de
	-- que nuestro pcall la atrape - un "macrospam" de miles de lineas por
	-- segundo mientras el raton siga sobre ese tooltip, ya que render() corre
	-- a 30-60 fps. Deduplicar solo NUESTRO log no arregla esto (el volcado no
	-- es nuestro) - hay que dejar de invocar "original" en cada frame
	-- mientras siga fallando. Cooldown por instancia de tooltip: tras un
	-- fallo, unos segundos con el render minimo propio (safeFallbackRender,
	-- que no vuelve a llamar a original) antes de reintentar - recupera solo
	-- si el problema de fondo era transitorio, sin machacar la consola.
	-- Claves DEBILES: a diferencia de renderingInstances (vive y muere dentro
	-- de la misma llamada sincrona), esta entrada persiste minimo 3s entre
	-- frames - sin metatabla debil, cada instancia de tooltip que falle
	-- alguna vez quedaria referenciada aqui para siempre (fuga de memoria en
	-- sesiones largas con muchos items distintos).
	-- 8s en vez de 3s: la traza real muestra un STACK OVERFLOW autentico
	-- (Coroutine.ensureCallFrameStackSize) dentro de SVSIT, no un error
	-- ligero - mas caro de recuperar y mas motivo para no reintentar cada
	-- pocos segundos mientras el jugador siga con el raton quieto encima.
	local wrapper
	wrapper = function(self, ...)
		-- Si un mod de terceros capturo un wrapper GS anterior y despues GS
		-- recupero la posicion exterior, ese wrapper viejo seguira apareciendo
		-- dentro de la cadena. Debe limitarse a delegar: solo el wrapper activo
		-- aplica guardas, fallback y extension visual.
		if wrapper ~= activeRenderWrapper then
			return original(self, ...)
		end
		if renderingInstances[self] then
			-- Reentrada real (mismo self, dentro de la misma pasada) - ver
			-- safeFallbackRender de arriba: dibujamos contenido real sin volver
			-- a llamar a "original", en vez de dejar el tooltip en blanco.
			pcall(safeFallbackRender, self)
			return
		end
		local now = getTimestampMs and getTimestampMs() or 0
		local ok, result = true, nil
		if failCooldownUntil[self] and now < failCooldownUntil[self] then
			-- Todavia en cooldown tras un fallo reciente de ESTE tooltip: no
			-- volver a invocar "original" (el mismo mod de terceros volveria a
			-- fallar y el motor volcaria la pila otra vez) - dibujar el render
			-- minimo propio para este frame.
			pcall(safeFallbackRender, self)
			ok = false
		else
			renderingInstances[self] = true
			ok, result = pcall(original, self, ...)
			renderingInstances[self] = nil
		end
		if not ok then
			-- BUG REAL encontrado (confirmado con traza real: crash dentro de
			-- MagicAccessories_Tooltip.lua:321 customRender, capturado aqui via
			-- pcall): antes, cuando "original" fallaba (revienta el RENDER de
			-- OTRO mod encadenado, no el nuestro), haciamos return inmediato y
			-- NUNCA llegabamos a dibujar nuestra propia extension - el jugador
			-- se quedaba sin tooltip de red/categoria precisamente en los items
			-- que otro mod (Magic Accessories, con joyas encantadas) rompe por
			-- su cuenta. Nuestro contenido no depende de que "original" tenga
			-- exito, asi que ya no lo condicionamos a ello - solo se pierde el
			-- dibujado vainilla+de terceros de ESE frame, nunca el nuestro.
			failCooldownUntil[self] = now + FAIL_COOLDOWN_MS
			if result and GlobalStorageSiK.Sandbox.debugMode() then
				local sig = tostring(result)
				if sig ~= lastFailSig or (now - lastFailLogAt) >= FAIL_LOG_COOLDOWN_MS then
					lastFailSig = sig
					lastFailLogAt = now
					GlobalStorageSiK.Log.debug("ItemNetworkTooltip", "ISToolTipInv.render original fallo: " .. sig)
				end
			end
		end
		pcall(function()
			if self.item and self.isVisible and self:isVisible() then
				local fullType = self.item.getFullType and self.item:getFullType()
				if fullType then
					-- Diagnostico de compatibilidad con mods que tambien parchean el
					-- tooltip de items (Magic Accessories, etc.): confirma que ESTE
					-- wrapper se ejecuta de verdad para items con modData de otros
					-- mods (encantamientos, bonos aleatorios...) antes de asumir que
					-- el problema esta en nuestro codigo.
					local hasModData = self.item.hasModData and self.item:hasModData()
					GlobalStorageSiK.Log.detail("ItemNetworkTooltipDetail", "render",
						string.format("fullType=%s hasModData=%s", tostring(fullType), tostring(hasModData)))
				end
				if fullType then
					-- Linea(s) de categoria detectada por nuestro motor de 3 niveles
					-- (misma fuente unica que Almacen/Nodos/GS_Router.lua) - a peticion
					-- del usuario, para poder ver de un vistazo que categoria/sub/detalle
					-- le asignamos a un item SIN tener que abrir el editor de nodos.
					-- Siempre se muestra si resuelve algo, este o no el item en una red.
					-- UNA LINEA POR NIVEL (no concatenado en una sola con " - "): la
					-- idea de este tooltip es poder leer SIN truncar lo que en la
					-- columna del Almacen si se trunca por falta de espacio - una
					-- unica linea larga se truncaba igual dentro de esta caja de ancho
					-- fijo (mismo ancho que el tooltip vanilla, ver drawNetworkExtension),
					-- perdiendo la jerarquia. Separando por nivel, cada linea es corta
					-- y casi nunca hace falta truncarla; solo aparecen los niveles que
					-- el item realmente tiene.
					local lines = {}
					local okTax, tax = pcall(GlobalStorageSiK.ItemTaxonomy.resolve, fullType, {})
					if okTax and tax and tax.groupLabel and tax.groupLabel ~= "" then
						lines[#lines + 1] = T("IGUI_GS_CategoryTooltipMain", tax.groupLabel)
						if tax.subGroupLabel and tax.subGroupLabel ~= "" then
							lines[#lines + 1] = T("IGUI_GS_CategoryTooltipSub", tax.subGroupLabel)
						end
						if tax.leafLabel and tax.leafLabel ~= "" then
							lines[#lines + 1] = T("IGUI_GS_CategoryTooltipLeaf", tax.leafLabel)
						end
					end

					local networks, loaded, hasAnyNetwork = getCachedCounts(fullType)
					if networks and #networks > 0 then
						for i = 1, #networks do
							lines[#lines + 1] = T("IGUI_GS_NetworkCountLine", networks[i].name, tostring(networks[i].count))
						end
					elseif loaded then
						-- Distinguir "todavia sin ninguna red creada" (mensaje generico,
						-- no implica que falte en algo que no existe) de "tienes redes
						-- pero este item no esta en ninguna" - a peticion del usuario,
						-- que reporto que el segundo mensaje confundia a jugadores que
						-- aun no habian creado su primera red.
						if hasAnyNetwork then
							lines[#lines + 1] = T("IGUI_GS_NetworkCountNone")
						else
							lines[#lines + 1] = T("IGUI_GS_NoNetworksYet")
						end
					end

					local usedH = 0
					if #lines > 0 then
						usedH = drawNetworkExtension(self, lines)
					end

					-- Bloque de skills VHS, SEPARADO del resto de informacion (a
					-- peticion del usuario) - propio color para distinguirlo a
					-- simple vista del bloque rojo de red/categoria.
					local skillLines = getSkillTrainingLines(self.item)
					if skillLines and #skillLines > 0 then
						drawNetworkExtension(self, skillLines, usedH, { 0.55, 0.85, 1 })
					end
				end
			end
		end)
		return result
	end

	activeRenderWrapper = wrapper
	ISToolTipInv.render = wrapper
	hooksInstalled = true
	if recoveringOuterPosition then
		GlobalStorageSiK.Log.debug("ItemNetworkTooltip",
			"hook chain changed; GS outer wrapper restored")
	end
	return true
end

-- Espera a que el resto de la UI/mods hayan instalado sus hooks y despues
-- vigila a bajo coste la identidad de ISToolTipInv.render. Si otro mod lo
-- sustituye mas tarde, GS vuelve a envolver la NUEVA cadena en el siguiente
-- intervalo; no obliga al usuario a resolver el orden de carga a mano.
--
-- Nuestro wrapper SIEMPRE
-- dibuja su contenido tras llamar a "original", pase lo que pase dentro -
-- eso conserva el contenido vanilla/ajeno y deja GS como envoltorio exterior.
-- Los wrappers GS anteriores que hayan quedado capturados dentro de otro mod
-- se vuelven pasarelas transparentes (ver installHooks), por lo que recuperar
-- la posicion exterior no duplica nuestra informacion.
local INSTALL_DELAY_TICKS = 180
local HOOK_MONITOR_INTERVAL_TICKS = 60
local _hookTickCount = 0
local function monitorTooltipHook()
	_hookTickCount = _hookTickCount + 1
	if _hookTickCount < INSTALL_DELAY_TICKS then
		return
	end
	if ((_hookTickCount - INSTALL_DELAY_TICKS) % HOOK_MONITOR_INTERVAL_TICKS) ~= 0 then
		return
	end
	if hooksInstalled and activeRenderWrapper and ISToolTipInv
		and ISToolTipInv.render == activeRenderWrapper then
		return
	end
	GlobalStorageSiK.ItemNetworkTooltip.installHooks()
end
if FEATURE_ENABLED then
	Events.OnTick.Add(monitorTooltipHook)
end

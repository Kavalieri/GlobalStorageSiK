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
require "GS_ItemSnapshot"
require "GS_Sandbox"
require "GS_Log"
require "GS_CategoryResolution"

GlobalStorageSiK.ItemNetworkTooltip = {}

local T = GlobalStorageSiK.I18n.text

local cache = {}
local pending = {}
local CACHE_TTL_MS = 4000

-- Cache de sesion, SOLO fullType (2026-08-23, root cause real del spam
-- "Couldn't find item" que persistia pese a las 4 rondas de cache previas -
-- ver GS_I18n.lua:cachedScriptItem): render() de ISToolTipInv corre a
-- 30-60fps SIEMPRE que el jugador mantiene el raton sobre CUALQUIER item, y
-- llamaba a ItemTaxonomy.resolve(fullType, {}) sin cache en cada uno de esos
-- fotogramas - resolve() es una funcion no trivial (varias tablas, varios
-- niveles de traduccion), no solo la consulta a ScriptManager (esa parte SI
-- ya estaba cacheada via GS_I18n.getScriptItem, por eso las rondas
-- anteriores de fix no lo detectaban con un grep de "getItem sin cache").
-- Aqui SIEMPRE se llama con row={} (nunca datos de fila reales), asi que
-- cachear unicamente por fullType es correcto para este call site concreto;
local _categoryResolveCache = {}
local function getCachedCategory(fullType)
	local cached = _categoryResolveCache[fullType]
	if cached ~= nil then
		return cached or nil
	end
	local ok, resolved = pcall(GlobalStorageSiK.CategoryResolution.resolve, fullType, nil)
	local result = (ok and resolved) or false
	_categoryResolveCache[fullType] = result
	return result or nil
end
local hooksInstalled = false

-- BUG REAL DE ARQUITECTURA cerrado (2026-08-27, estudio real de TooltipLib -
-- Workshop 3694097672 - que nos nombra EXPLICITAMENTE por Workshop ID como
-- uno de los 2 mods causantes de un ciclo real de stack overflow: "Global
-- Storage SiK WS 3750612158... wrap ISToolTipInv.render with an 'install
-- late to win' reclaim loop: they periodically re-take the slot"). Las 3
-- rondas anteriores (dev26/27/28) parcheaban SINTOMAS de ese mismo patron de
-- fondo (desmontar al morir, suspender el monitor durante la transicion de
-- vida, corregir el log) sin cambiar el patron en si: un monitor que
-- comprobaba cada ~60 ticks si seguiamos siendo el wrapper EXTERIOR y, si
-- no, volvia a envolver para RECUPERAR esa posicion - una carrera activa por
-- el puesto exterior que se repetia indefinidamente durante toda la partida,
-- exactamente lo que TooltipLib llama "install late to win".
--
-- TooltipLib nunca libra esa carrera: instala su wrapper UNA SOLA VEZ por
-- proceso y jamas vuelve a comprobar/reinstalar despues, se quede donde se
-- quede en la cadena de otros mods. Mismo principio aplicado aqui, con nuestra
-- propia implementacion (sin depender de TooltipLib ni copiar su codigo):
-- `installHooks()` ahora se llama como maximo una vez de verdad (ver
-- monitorTooltipHook mas abajo, que deja de vigilar en cuanto instala con
-- exito) - nunca vuelve a intentar recuperar la posicion exterior si otro mod
-- envuelve por encima despues. Esto elimina de raiz la posibilidad de que
-- exista un "wrapper GS de la vida anterior" atrapado en la cadena de otro
-- mod (solo se crea UN wrapper en toda la sesion), asi que ya no hace falta
-- desmontar nada al morir - toda la maquinaria de dev26-28
-- (uninstallHooks/suspendedForLifeTransition/onCreatePlayerResumeMonitor) se
-- retira por completo, no por limpieza cosmetica sino porque el problema que
-- resolvia ya no puede ocurrir bajo este diseño.
--
-- Guarda de reentrada POR INSTANCIA (nunca un booleano/contador compartido -
-- confirmado en v1.2.94 que un flag compartido bloquea el tooltip de
-- CUALQUIER OTRA instancia de ISToolTipInv activa el mismo frame, ver
-- comentario historico mas abajo): si "original" (fijado una sola vez al
-- instalar, nunca reevaluado) rebota de vuelta a nuestro propio wrapper para
-- la MISMA instancia de tooltip, se corta con safeFallbackRender (dibuja
-- contenido real via item:DoTooltip, nunca vuelve a invocar nada ajeno) en
-- vez de seguir la cadena. Claves debiles: la instancia de tooltip puede
-- destruirse a mitad de un ciclo real.
local renderingInstances = setmetatable({}, { __mode = "k" })
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

--- Clave de cache/pending: fullType a secas para el caso normal,
--- fullType+mediaTitle para cintas VHS/radio (2026-08-26, fix de agrupacion
--- de VHS) - sin esto, dos cintas de distinta habilidad pero mismo fullType
--- generico compartirian la misma entrada de cache y una tapaba a la otra.
---@param fullType string
---@param mediaTitle string|nil
---@return string
local function countsCacheKey(fullType, mediaTitle)
	return mediaTitle and (fullType .. "\31media:" .. mediaTitle) or fullType
end

--- Recibe la respuesta del servidor con los conteos por red de un fullType
--- (+ mediaTitle si es una cinta VHS/radio con contenido concreto).
---@param fullType string|nil
---@param networks table[]
---@param hasAnyNetwork boolean|nil si el jugador tiene AL MENOS una red accesible (independientemente de si este fullType esta en ella) - distingue "no tienes redes todavia" de "no esta en ninguna de tus redes"
---@param mediaTitle string|nil
function GlobalStorageSiK.ItemNetworkTooltip.onCountsReceived(fullType, networks, hasAnyNetwork, mediaTitle)
	if not fullType then
		return
	end
	local key = countsCacheKey(fullType, mediaTitle)
	cache[key] = {
		networks = networks or {},
		hasAnyNetwork = hasAnyNetwork and true or false,
		ts = getTimestampMs and getTimestampMs() or 0,
	}
	pending[key] = nil
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

local function requestCounts(fullType, mediaTitle)
	local key = countsCacheKey(fullType, mediaTitle)
	if pending[key] then
		return
	end
	if isTrueSingleplayer() then
		local player = GlobalStorageSiK.NetClient.getPlayer()
		if player and GlobalStorageSiK.Index and GlobalStorageSiK.Index.getNetworkCountsForItem then
			local ok, networks, hasAnyNetwork = pcall(GlobalStorageSiK.Index.getNetworkCountsForItem, player, fullType, mediaTitle)
			if ok then
				GlobalStorageSiK.ItemNetworkTooltip.onCountsReceived(fullType, networks, hasAnyNetwork, mediaTitle)
			end
		end
		return
	end
	pending[key] = true
	GlobalStorageSiK.NetClient.sendCommand("getItemNetworkCounts", { fullType = fullType, mediaTitle = mediaTitle })
end

--- Devuelve conteos cacheados y dispara refresco en segundo plano si caducó.
--- Devuelve tambien "loaded" para poder distinguir "todavia sin respuesta"
--- (no dibujar nada, evita parpadear un falso "no esta en ninguna red" antes
--- de que llegue el primer dato) de "ya consultado y de verdad no esta en
--- ninguna red" (aqui si hay que avisar, a peticion del usuario).
---@param fullType string
---@param mediaTitle string|nil
---@return table[]|nil, boolean loaded, boolean hasAnyNetwork
local function getCachedCounts(fullType, mediaTitle)
	local key = countsCacheKey(fullType, mediaTitle)
	local entry = cache[key]
	local now = getTimestampMs and getTimestampMs() or 0
	if not entry or (now - entry.ts) >= CACHE_TTL_MS then
		requestCounts(fullType, mediaTitle)
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
---@param mediaTitle string|nil
---@return table[]|nil, boolean
function GlobalStorageSiK.ItemNetworkTooltip.getCachedCounts(fullType, mediaTitle)
	return getCachedCounts(fullType, mediaTitle)
end

local NET_FONT = UIFont.Small
local LINE_PAD = 4

--- Trunca una linea al ancho disponible (reutiliza el helper ya usado en el
--- resto de la UI del mod si esta cargado; si no, la deja tal cual).
---@param text string
---@param maxW number
---@return string
local function truncate(text, maxW)
	if GlobalStorageSiK.SiK_UI and GlobalStorageSiK.SiK_UI.truncateText then
		return GlobalStorageSiK.SiK_UI.truncateText(text, maxW, NET_FONT)
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

--- Pista narrativa "hay que encontrarlo" del GS_SolderingIron (2026-08-25,
--- pedido explicito del usuario tras el comentario de Steam de "Corvalao":
--- la receta de ensamblaje ya esta oculta salvo que se active
--- GlobalStorageSiK.EnableSolderingIronCraft en el sandbox, pero el item no
--- explicaba por que en ningun sitio). SOLO se muestra cuando la opcion esta
--- DESACTIVADA (el caso por defecto) - si esta activada, el tooltip estatico
--- normal (Tooltip_GS_SolderingIron en Tooltip.json) ya es una descripcion
--- corta sin alusiones, no hace falta añadir nada mas.
--- Envuelto con SiK_UI.wrapTextLines (si esta cargado) para no
--- depender de que la traduccion de cada idioma quepa en una sola linea del
--- ancho fijo de drawNetworkExtension - mismo criterio que el resto de la UI
--- del mod para texto de longitud variable (ver CLAUDE.md regla 7).
local SOLDERING_IRON_FULLTYPE = "GlobalStorageSiK.GS_SolderingIron"
local SOLDERING_LORE_MAX_W = MAX_EXT_WIDTH - 16
---@param fullType string|nil
---@return string[]|nil
local function getSolderingIronLoreLines(fullType)
	if fullType ~= SOLDERING_IRON_FULLTYPE then
		return nil
	end
	local enabled = SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.EnableSolderingIronCraft == true
	if enabled then
		return nil
	end
	local text = T("IGUI_GS_SolderingIronFindHint")
	if GlobalStorageSiK.SiK_UI and GlobalStorageSiK.SiK_UI.wrapTextLines then
		return GlobalStorageSiK.SiK_UI.wrapTextLines(text, SOLDERING_LORE_MAX_W, NET_FONT)
	end
	return { text }
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
--- Construye el contenido propio (categoria/red, skills VHS, pista soldador)
--- para UN item concreto - independiente de COMO se pinte despues (nuestro
--- wrapper propio via drawNetworkExtension, o un proveedor de TooltipLib via
--- ctx:addText). Antes vivia inline dentro del wrapper; extraido para no
--- duplicar la logica entre los 2 mecanismos de render posibles (ver
--- installHooks mas abajo).
---@param item InventoryItem|nil
---@return table[] blocks lista de { lines: string[], color: number[] }
local function buildTooltipBlocks(item)
	local blocks = {}
	if not (item and item.getFullType) then
		return blocks
	end
	local fullType = item:getFullType()
	if not fullType then
		return blocks
	end
	if item.hasModData then
		-- Diagnostico de compatibilidad con mods que tambien parchean el
		-- tooltip de items (Magic Accessories, etc.): confirma que este
		-- codigo se ejecuta de verdad para items con modData de otros mods
		-- (encantamientos, bonos aleatorios...) antes de asumir que el
		-- problema esta en nuestro codigo.
		local hasModData = item:hasModData()
		GlobalStorageSiK.Log.detail("ItemNetworkTooltipDetail", "render",
			string.format("fullType=%s hasModData=%s", tostring(fullType), tostring(hasModData)))
	end

	-- Linea(s) de categoria detectada por nuestro motor de 3 niveles (misma
	-- fuente unica que Almacen/Nodos/GS_Router.lua) - a peticion del usuario,
	-- para poder ver de un vistazo que categoria/sub/detalle le asignamos a
	-- un item SIN tener que abrir el editor de nodos. UNA LINEA POR NIVEL (no
	-- concatenado con " - "): la caja de ancho fijo truncaba igual una unica
	-- linea larga, perdiendo la jerarquia.
	local lines = {}
	local resolved = getCachedCategory(fullType)
	if resolved then
		if resolved.effective == "native" then
			local path = GlobalStorageSiK.NativeProduct.decodePath(resolved.nativePath)
			local view = path and GlobalStorageSiK.NativeProduct.getView(path) or nil
			if view and view.l1Label then lines[#lines + 1] = T("IGUI_GS_CategoryTooltipMain", view.l1Label) end
			if view and view.l2Label then lines[#lines + 1] = T("IGUI_GS_CategoryTooltipSub", view.l2Label) end
			if view and view.l3Label then lines[#lines + 1] = T("IGUI_GS_CategoryTooltipLeaf", view.l3Label) end
		else
			lines[#lines + 1] = T("IGUI_GS_CategoryTooltipMain", GlobalStorageSiK.CategoryResolution.label(resolved))
		end
	end

	-- mediaTitle (2026-08-26, fix de agrupacion de VHS): si el item bajo el
	-- raton es una cinta VHS/radio con contenido concreto, contar SOLO cintas
	-- con ese mismo contenido en vez de sumar todas las del fullType generico.
	local mediaTitle = GlobalStorageSiK.ItemSnapshot and GlobalStorageSiK.ItemSnapshot.recordedMediaTitleFromItem
		and GlobalStorageSiK.ItemSnapshot.recordedMediaTitleFromItem(item)
	local networks, loaded, hasAnyNetwork = getCachedCounts(fullType, mediaTitle)
	if networks and #networks > 0 then
		for i = 1, #networks do
			lines[#lines + 1] = T("IGUI_GS_NetworkCountLine", networks[i].name, tostring(networks[i].count))
		end
	elseif loaded then
		-- Distinguir "todavia sin ninguna red creada" (mensaje generico) de
		-- "tienes redes pero este item no esta en ninguna" - a peticion del
		-- usuario, que reporto que el segundo mensaje confundia a jugadores
		-- que aun no habian creado su primera red.
		if hasAnyNetwork then
			lines[#lines + 1] = T("IGUI_GS_NetworkCountNone")
		else
			lines[#lines + 1] = T("IGUI_GS_NoNetworksYet")
		end
	end
	if #lines > 0 then
		blocks[#blocks + 1] = { lines = lines, color = { 0.9, 0.85, 0.4, 1.0 } }
	end

	-- Bloque de skills VHS, SEPARADO del resto de informacion (a peticion del
	-- usuario) - propio color para distinguirlo a simple vista.
	local skillLines = getSkillTrainingLines(item)
	if skillLines and #skillLines > 0 then
		blocks[#blocks + 1] = { lines = skillLines, color = { 0.55, 0.85, 1, 1.0 } }
	end

	-- Pista narrativa del soldador (solo si el crafteo del GS_SolderingIron
	-- sigue desactivado en el sandbox) - propio color neutro.
	local loreLines = getSolderingIronLoreLines(fullType)
	if loreLines and #loreLines > 0 then
		blocks[#blocks + 1] = { lines = loreLines, color = { 0.75, 0.7, 0.6, 1.0 } }
	end
	return blocks
end

-- BUG REAL DE ARQUITECTURA cerrado (2026-08-27, ver comentario extenso junto
-- a "hooksInstalled" arriba): dos vias de instalacion, evaluadas en este
-- orden.
--
-- VIA 1 - integracion con TooltipLib (Workshop 3694097672) cuando esta
-- presente: nos registramos como proveedor via TooltipLib.registerProvider,
-- SIN tocar ISToolTipInv.render en absoluto - cero riesgo de ciclo porque no
-- formamos parte de ninguna cadena de wrappers, es TooltipLib quien despacha
-- nuestro callback de forma aislada (su propio framework ya gestiona el
-- render real). Decision explicita: no depender de TooltipLib como unica
-- solucion (es un mod opcional de terceros, la mayoria de jugadores no lo
-- tendran) - esta via es una MEJORA cuando aplica, nunca la unica defensa.
--
-- VIA 2 - wrapper propio, autonomo, instalado UNA SOLA VEZ (usado cuando
-- TooltipLib no esta presente): a diferencia del diseño anterior (dev7-dev28),
-- este wrapper NUNCA intenta recuperar la posicion exterior si otro mod
-- envuelve por encima despues - se instala, y a partir de ahi es
-- responsabilidad exclusiva de la guarda de reentrada (renderingInstances,
-- por instancia) y del contador de profundidad COMPARTIDO (ver
-- sharedRenderDepth) evitar cualquier ciclo, sin importar donde acabemos
-- colocados en la cadena de otros mods.
-- Envuelta en pcall completo (no solo la llamada a registerProvider): una
-- copia vieja o alterada de TooltipLib puede exponer el global de forma
-- parcial (p.ej. "TooltipLib" ya existe pero "TooltipLib.hasProvider" lanza
-- en vez de devolver nil) - cualquier excepcion aqui debe hacer que GS caiga
-- al wrapper autonomo, nunca perder la instalacion porque el evento de
-- arranque ya se retiro (ver installOnceTick).
---@return boolean installed
local function installViaTooltipLib()
	if not (rawget(_G, "TooltipLib") and type(TooltipLib.registerProvider) == "function") then
		return false
	end
	local ok, result = pcall(function()
		if TooltipLib.checkVersion and not TooltipLib.checkVersion("1.0.0") then
			return false
		end
		if TooltipLib.hasProvider and TooltipLib.hasProvider("GlobalStorageSiK") then
			return true
		end
		return TooltipLib.registerProvider{
			id = "GlobalStorageSiK",
			target = "item",
			description = "Global Storage SiK - red y categoria",
			minVersion = "1.0.0",
			callback = function(ctx)
				local blocks = buildTooltipBlocks(ctx and ctx.item)
				for i = 1, #blocks do
					local block = blocks[i]
					for j = 1, #block.lines do
						ctx:addText(block.lines[j], block.color)
					end
				end
			end,
		} == true
	end)
	return ok and result == true
end

-- Contador de profundidad COMPARTIDO (no por instancia) - pedido explicito
-- tras revisar TooltipLib: una guarda adicional independiente de
-- renderingInstances[self], para el caso (no confirmado pero tampoco
-- descartable) de que un ciclo involucre MAS de una instancia de tooltip
-- alternandose. SIEMPRE se decrementa a traves de wrapper() (pcall
-- envolvente sobre wrapperBody, ver mas abajo) - nunca puede quedar
-- "atascado" por encima de 0 aunque wrapperBody lance un error, evitando que
-- un fallo puntual degrade el tooltip para el resto de la sesion (incluida
-- cualquier vida posterior del mismo personaje).
local sharedRenderDepth = 0
local MAX_SHARED_RENDER_DEPTH = 8

function GlobalStorageSiK.ItemNetworkTooltip.installHooks()
	if not FEATURE_ENABLED or hooksInstalled then
		return hooksInstalled
	end
	if installViaTooltipLib() then
		hooksInstalled = true
		GlobalStorageSiK.Log.debug("ItemNetworkTooltip", "registrado como proveedor de TooltipLib")
		return true
	end
	if not ISToolTipInv or not ISToolTipInv.render then
		return false
	end

	local original = ISToolTipInv.render
	local wrapper, wrapperBody
	wrapper = function(self, ...)
		if renderingInstances[self] then
			-- Reentrada real para ESTA MISMA instancia de tooltip - dibujamos
			-- contenido real sin volver a llamar a nada ajeno.
			pcall(safeFallbackRender, self)
			return
		end
		sharedRenderDepth = sharedRenderDepth + 1
		local ok, result = pcall(wrapperBody, self, ...)
		sharedRenderDepth = sharedRenderDepth - 1
		if not ok then
			pcall(safeFallbackRender, self)
			return
		end
		return result
	end
	wrapperBody = function(self, ...)
		if sharedRenderDepth > MAX_SHARED_RENDER_DEPTH then
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
			-- NUNCA llegabamos a dibujar nuestra propia extension. Nuestro
			-- contenido no depende de que "original" tenga exito.
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
				local blocks = buildTooltipBlocks(self.item)
				local usedH = 0
				for i = 1, #blocks do
					usedH = usedH + drawNetworkExtension(self, blocks[i].lines, usedH, blocks[i].color)
				end
			end
		end)
		return result
	end

	ISToolTipInv.render = wrapper
	hooksInstalled = true
	GlobalStorageSiK.Log.debug("ItemNetworkTooltip", "ISToolTipInv.render envuelto (autonomo, instalacion unica)")
	return true
end

-- Ventana de arranque LIMITADA, nunca un monitor indefinido: el primer
-- intento a los 180 ticks puede caer en una carga temprana real (TooltipLib
-- todavia no ha creado su global, o ISToolTipInv aun no existe) - sin
-- ningun reintento eso degradaba una simple carrera de arranque en perdida
-- total del tooltip GS durante toda la sesion. Reintenta cada
-- RETRY_INTERVAL_TICKS hasta el primer exito o hasta agotar
-- MAX_ATTEMPT_TICKS; SIEMPRE se retira de OnTick en ese punto (exito,
-- agotamiento, o feature desactivada) y jamas vuelve a comprobar nada
-- despues - esto sigue siendo instalacion unica, no un reclamador periodico
-- de posicion exterior (esta ventana solo cubre el ARRANQUE, nunca compite
-- por el wrapper una vez instalado).
local INSTALL_DELAY_TICKS = 180
local RETRY_INTERVAL_TICKS = 45
local MAX_ATTEMPT_TICKS = 900
local _hookTickCount = 0
local function installOnceTick()
	_hookTickCount = _hookTickCount + 1
	if _hookTickCount < INSTALL_DELAY_TICKS then
		return
	end
	if ((_hookTickCount - INSTALL_DELAY_TICKS) % RETRY_INTERVAL_TICKS) ~= 0 then
		return
	end
	local installed = GlobalStorageSiK.ItemNetworkTooltip.installHooks()
	if installed or _hookTickCount >= MAX_ATTEMPT_TICKS then
		if Events and Events.OnTick and Events.OnTick.Remove then
			Events.OnTick.Remove(installOnceTick)
		end
		if not installed then
			GlobalStorageSiK.Log.warn("ItemNetworkTooltip",
				"no se pudo instalar el enganche de tooltip tras agotar la ventana de arranque")
		end
	end
end
if FEATURE_ENABLED then
	Events.OnTick.Add(installOnceTick)
end

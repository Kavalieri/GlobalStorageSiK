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
require "GS_RecordedMedia"
require "GS_Sandbox"
require "GS_Log"
local RemotePresentation = require "GS_RemoteTooltipPresentation"
local UI = require "GS_UI_Framework"

GlobalStorageSiK.ItemNetworkTooltip = {}

local T = GlobalStorageSiK.I18n.text

local cache = {}
local pending = {}
local CACHE_TTL_MS = 4000
local PENDING_TIMEOUT_MS = 5000
local MAX_COUNT_CACHE = 256
local MAX_PENDING = 128
local cacheOrder = {}
local pendingOrder = {}

local function insertBounded(target, order, key, value, limit)
	if target[key] == nil then
		order[#order + 1] = key
		if #order > limit then
			local oldest = table.remove(order, 1)
			if oldest then target[oldest] = nil end
		end
	end
	target[key] = value
end

local function removeOrdered(target, order, key)
	target[key] = nil
	for i = #order, 1, -1 do
		if order[i] == key then table.remove(order, i) end
	end
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
	pending = {}
	cacheOrder = {}
	pendingOrder = {}
end

--- Clave de cache/pending: fullType a secas para el caso normal,
--- fullType+mediaTitle para cintas VHS/radio (2026-08-26, fix de agrupacion
--- de VHS) - sin esto, dos cintas de distinta habilidad pero mismo fullType
--- generico compartirian la misma entrada de cache y una tapaba a la otra.
---@param fullType string
---@param mediaTitle string|nil
---@return string
local function countsCacheKey(playerNum, fullType, mediaTitle, mediaIndex, dynamicStateKey)
	local prefix = tostring(tonumber(playerNum) or 0) .. "\30"
	if mediaIndex ~= nil then return prefix .. fullType .. "\31mediaIndex:" .. tostring(mediaIndex) end
	if dynamicStateKey then return prefix .. fullType .. "\31state:" .. tostring(dynamicStateKey) end
	return prefix .. (mediaTitle and (fullType .. "\31media:" .. mediaTitle) or fullType)
end

--- Recibe la respuesta del servidor con los conteos por red de un fullType
--- (+ mediaTitle si es una cinta VHS/radio con contenido concreto).
---@param fullType string|nil
---@param networks table[]
---@param hasAnyNetwork boolean|nil si el jugador tiene AL MENOS una red accesible (independientemente de si este fullType esta en ella) - distingue "no tienes redes todavia" de "no esta en ninguna de tus redes"
---@param mediaTitle string|nil
function GlobalStorageSiK.ItemNetworkTooltip.onCountsReceived(fullType, networks, hasAnyNetwork,
	mediaTitle, mediaIndex, dynamicStateKey, playerNum)
	if not fullType then
		return
	end
	local key = countsCacheKey(playerNum, fullType, mediaTitle, mediaIndex, dynamicStateKey)
	insertBounded(cache, cacheOrder, key, {
		networks = networks or {},
		hasAnyNetwork = hasAnyNetwork and true or false,
		ts = getTimestampMs and getTimestampMs() or 0,
	}, MAX_COUNT_CACHE)
	removeOrdered(pending, pendingOrder, key)
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

local function requestCounts(fullType, mediaTitle, mediaIndex, dynamicStateKey, playerNum)
	playerNum = tonumber(playerNum) or 0
	local key = countsCacheKey(playerNum, fullType, mediaTitle, mediaIndex, dynamicStateKey)
	local now = getTimestampMs and getTimestampMs() or 0
	local sentAt = pending[key]
	if sentAt and (now <= 0 or sentAt <= 0 or now - sentAt < PENDING_TIMEOUT_MS) then
		return
	end
	if sentAt then removeOrdered(pending, pendingOrder, key) end
	if isTrueSingleplayer() then
		local player = GlobalStorageSiK.NetClient.getPlayer(playerNum)
		if player and GlobalStorageSiK.Index and GlobalStorageSiK.Index.getNetworkCountsForItem then
			local ok, networks, hasAnyNetwork = pcall(GlobalStorageSiK.Index.getNetworkCountsForItem,
				player, fullType, mediaTitle, mediaIndex, dynamicStateKey)
			if ok then
				GlobalStorageSiK.ItemNetworkTooltip.onCountsReceived(fullType, networks,
					hasAnyNetwork, mediaTitle, mediaIndex, dynamicStateKey, playerNum)
			end
		end
		return
	end
	insertBounded(pending, pendingOrder, key, now, MAX_PENDING)
	local sent = GlobalStorageSiK.NetClient.sendCommand("getItemNetworkCounts", {
		fullType = fullType, mediaTitle = mediaTitle, mediaIndex = mediaIndex,
		dynamicStateKey = dynamicStateKey,
	}, playerNum)
	if not sent then removeOrdered(pending, pendingOrder, key) end
end

--- Devuelve conteos cacheados y dispara refresco en segundo plano si caducó.
--- Devuelve tambien "loaded" para poder distinguir "todavia sin respuesta"
--- (no dibujar nada, evita parpadear un falso "no esta en ninguna red" antes
--- de que llegue el primer dato) de "ya consultado y de verdad no esta en
--- ninguna red" (aqui si hay que avisar, a peticion del usuario).
---@param fullType string
---@param mediaTitle string|nil
---@return table[]|nil, boolean loaded, boolean hasAnyNetwork
local function getCachedCounts(fullType, mediaTitle, mediaIndex, dynamicStateKey, playerNum)
	local key = countsCacheKey(playerNum, fullType, mediaTitle, mediaIndex, dynamicStateKey)
	local entry = cache[key]
	local now = getTimestampMs and getTimestampMs() or 0
	if not entry or (now - entry.ts) >= CACHE_TTL_MS then
		requestCounts(fullType, mediaTitle, mediaIndex, dynamicStateKey, playerNum)
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
function GlobalStorageSiK.ItemNetworkTooltip.getCachedCounts(fullType, mediaTitle, mediaIndex, dynamicStateKey, playerNum)
	return getCachedCounts(fullType, mediaTitle, mediaIndex, dynamicStateKey, playerNum)
end

local function playerNumForItem(item)
	local container = item and item.getContainer and item:getContainer() or nil
	for _ = 1, 8 do
		local parent = container and container.getParent and container:getParent() or nil
		if not parent then break end
		if parent.getPlayerNum then return parent:getPlayerNum() end
		container = parent.getContainer and parent:getContainer() or nil
	end
	return 0
end

local NET_FONT = UIFont.Small
local LINE_PAD = 4

--- Interpretacion propia de la formacion de una cinta VHS. Los libros ya
--- exponen sus campos SkillTrained/LvlSkillTrained en el tooltip vanilla y no
--- se repiten aqui. Las cintas VHS no usan ese sistema: el item
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
--- Trigrama -> clave getText del perk, copiado DIRECTAMENTE de
--- shared/RadioCom/ISRadioInteractions.lua (linea Interactions.XXX =
--- function(...) doSkill(_player, _amount, getText("IGUI_perks_..."),
--- Perks...) end) - fuente unica de verdad vainilla, no una copia de otro
--- mod. Solo trigramas de SKILL (Interactions tambien tiene ANG/BOR/END/...
--- para stats como hambre/animo, deliberadamente fuera de este mapa).
--- Lee solo la MediaData de la cinta bajo el raton. Evita construir/retener un
--- indice de TODO RecMedia en el primer hover y usa las mismas lineas reales
--- que vanilla reproduce. getLine recibe int, no el short problematico de
--- RecordedMedia.getMediaDataFromIndex.
local function mediaTeachingNames(mediaData)
	if not mediaData or not mediaData.getLineCount or not mediaData.getLine then
		return nil
	end
	local okCount, count = pcall(function() return mediaData:getLineCount() end)
	if not okCount or type(count) ~= "number" or count ~= count
		or count < 0 or count > 4096 or count ~= math.floor(count) then return nil end
	local teachingNames, seen, seenRecipes = {}, {}, {}
	for i = 0, count - 1 do
		local okLine, line = pcall(function() return mediaData:getLine(i) end)
		if not okLine or not line or not line.getCodes then return nil end
		local okCodes, lineCodes = pcall(function() return line:getCodes() end)
		if not okCodes then return nil end
		-- Parse each exact catalogue line, not a truncated network sample. The
		-- shared parser's payload limit must not discard teaching after line 64.
		local codes = { tostring(lineCodes or "") }
		local perkKeys = GlobalStorageSiK.RecordedMedia.perkKeysFromCodes(codes)
		for j = 1, #(perkKeys or {}) do
			local key = perkKeys[j]
			if not seen[key] then
				seen[key] = true
				teachingNames[#teachingNames + 1] = getText(key)
			end
		end
		local recipes = GlobalStorageSiK.RecordedMedia.recipeIdsFromCodes(codes)
		for j = 1, #(recipes or {}) do
			local recipe = recipes[j]
			if not seenRecipes[recipe] then
				seenRecipes[recipe] = true
				-- Match vanilla's learning feedback, removing only its first dot
				-- namespace. Colon-based recipe identifiers remain intact.
				local dot = recipe:find(".", 1, true)
				local displayId = dot and recipe:sub(dot + 1) or recipe
				local okName, name = false, nil
				if type(getRecipeDisplayName) == "function" then
					okName, name = pcall(getRecipeDisplayName, displayId)
				end
				teachingNames[#teachingNames + 1] = okName and type(name) == "string"
					and name ~= "" and name or recipe
			end
		end
	end
	return teachingNames
end

--- Camino REAL para
--- cintas VHS (y cualquier otro "medio grabado" que use el mismo sistema
--- vainilla de RecMedia, no solo items con "VHS" en el fullType). El anexo
--- depende del contenido didactico, nunca del conocimiento del personaje.
--- Sin aprendizaje o sin MediaData exacta no se añade un bloque vacio.
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
	if not item.getMediaData then return nil end
	local okData, mediaData = pcall(function() return item:getMediaData() end)
	local skillNames = okData and mediaTeachingNames(mediaData) or nil
	if not skillNames then
		-- Sin MediaData exacta no se afirma nada sobre la cinta.
		return nil
	end
	if #skillNames == 0 then
		return nil
	end
	local lines = { T("IGUI_GS_VHSSkillHeader") }
	for i = 1, #skillNames do
		lines[#lines + 1] = skillNames[i]
	end
	return lines
end

local function getRemoteVHSTrainingLines(detail)
	if not detail or detail.mediaIndex == nil then return nil end
	local mediaData = GlobalStorageSiK.RecordedMedia.dataFromIndex(detail.mediaIndex, detail.fullType)
	local skillNames = mediaTeachingNames(mediaData)
	if not skillNames or #skillNames == 0 then return nil end
	local lines = { T("IGUI_GS_VHSSkillHeader") }
	for i = 1, #skillNames do lines[#lines + 1] = skillNames[i] end
	return lines
end

---@param item table|nil InventoryItem
---@return string[]|nil
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
-- Coincide con el anclaje vanilla/fallback de ISToolTipInv. No se desplaza
-- lateralmente el tooltip al añadir contenido SiK ya medido.
local TOOLTIP_GUTTER = 24
local renderCapturedTooltip

local function remoteContextFor(item)
	return GlobalStorageSiK.RemoteItemDetail and GlobalStorageSiK.RemoteItemDetail.contextForProbe
		and GlobalStorageSiK.RemoteItemDetail.contextForProbe(item) or nil
end

local function withdrawDragActive()
	return GlobalStorageSiK.TerminalWithdrawDrag
		and GlobalStorageSiK.TerminalWithdrawDrag.isActive
		and GlobalStorageSiK.TerminalWithdrawDrag.isActive() == true
end

local function makeTooltipMouseTransparent(panel)
	if panel and panel.javaObject and panel.javaObject.setConsumeMouseEvents then
		panel.javaObject:setConsumeMouseEvents(false)
	end
end

local function extensionMetrics(blocks, baseWidth, maxWidth)
        local textManager = getTextManager()
        -- ISToolTipInv puede conservar una anchura de medida de un proveedor
        -- anterior. El anexo no hereda nunca ese rectangulo: su contrato tiene
        -- un maximo propio y medido, para no convertir el tooltip en una pared.
        local width = math.min(MAX_EXT_WIDTH, math.max(0, tonumber(baseWidth) or 0))
	for i = 1, #(blocks or {}) do
		local lines = blocks[i].lines or {}
		local maxTextW = 0
		for j = 1, #lines do
			maxTextW = math.max(maxTextW, textManager:MeasureStringX(NET_FONT, lines[j]))
		end
		width = math.max(width, math.min(MAX_EXT_WIDTH, maxTextW + 16))
	end
	width = math.min(width, maxWidth or MAX_EXT_WIDTH)
	local height = 0
	for i = 1, #(blocks or {}) do
		local section = UI.Tooltip.objectSection(blocks[i].lines, {
			font = NET_FONT, paddingX = 8, paddingY = LINE_PAD,
		})
		height = height + UI.Tooltip.measureSection(section, width).height + 2
	end
	return width, height
end

local function axisPlacement(anchor, size, low, high)
	local forward = anchor + TOOLTIP_GUTTER
	if forward + size <= high then return forward end
	local backward = anchor - size - TOOLTIP_GUTTER
	if backward >= low then return backward end
	return nil
end

--- Coloca el rectangulo YA medido sin usar clamp como solucion primaria.
--- Si el anexo no cabe conservando el corredor del cursor, el caller no lo
--- dibuja; el tooltip vanilla mantiene su propio placement.
local function placeMeasuredTooltip(panel, item, width, totalHeight)
	local playerNum = playerNumForItem(item)
	local viewport = UI.Viewport.resolve(playerNum)
	local right = viewport.x + viewport.w
	local bottom = viewport.y + viewport.h
	-- Los tooltips fijos y los anclados por menú/joypad ya fueron colocados por
	-- vanilla. Conservar ese origen y desplazar únicamente lo imprescindible
	-- para que la extensión medida siga dentro del viewport; nunca sustituir su
	-- ancla por el ratón global.
	if panel.followMouse == false or (panel.contextMenu and panel.contextMenu.joyfocus) then
		local x = panel.getX and panel:getX() or panel.x or viewport.x
		local y = panel.getY and panel:getY() or panel.y or viewport.y
		if x + width > right then x = right - width end
		if y + totalHeight > bottom then y = bottom - totalHeight end
		if x < viewport.x or y < viewport.y then return false end
		panel:setX(x)
		panel:setY(y)
		panel:setWidth(width)
		makeTooltipMouseTransparent(panel)
		return true
	end
	local anchorX = getMouseX and getMouseX() or panel:getX()
	local anchorY = getMouseY and getMouseY() or panel:getY()
	local x = axisPlacement(anchorX, width, viewport.x, right)
	local y = axisPlacement(anchorY, totalHeight, viewport.y, bottom)
	-- A clear corridor on either axis already excludes the cursor. A tall
	-- wrapped tooltip may therefore use the full vertical viewport beside it
	-- (and a wide tooltip the full horizontal viewport above/below it).
	if x ~= nil and y == nil and totalHeight <= viewport.h then
		y = bottom - totalHeight
		if y > anchorY then y = anchorY end
		if y < viewport.y then y = viewport.y end
	elseif y ~= nil and x == nil and width <= viewport.w then
		x = right - width
		if x > anchorX then x = anchorX end
		if x < viewport.x then x = viewport.x end
	end
	if x == nil or y == nil then return false end
	panel:setX(x)
	panel:setY(y)
	panel:setWidth(width)
	makeTooltipMouseTransparent(panel)
	return true
end

---@param tr table  el propio ISToolTipInv, ya con x/y/width/height finales de este frame
---@param lines string[]
---@param yOffset number|nil  extra por encima de tr.height (para apilar un segundo bloque distinto debajo del primero)
---@param colorRGB number[]|nil  {r,g,b} del texto (por defecto, el amarillo de red)
---@return number boxH  alto real dibujado, para poder apilar el siguiente bloque
local function drawNetworkExtension(tr, lines, yOffset, colorRGB, width)
	colorRGB = colorRGB or { 0.9, 0.85, 0.4 }
	local boxW = width or tr.width
	local y = tr.height + 2 + (yOffset or 0)
	local section = UI.Tooltip.objectSection(lines, {
		lineColor = colorRGB,
		backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.85 },
		borderColor = { r = 0.9, g = 0.9, b = 1, a = 0.6 },
		paddingX = 8,
		paddingY = LINE_PAD,
		font = NET_FONT,
	})
	local measured = UI.Tooltip.renderSection(tr, section, 0, y, boxW)
	return measured and measured.height or 0
end

--- Pista narrativa "hay que encontrarlo" del GS_SolderingIron (2026-08-25,
--- pedido explicito del usuario tras el comentario de Steam de "Corvalao":
--- la receta de ensamblaje ya esta oculta salvo que se active
--- GlobalStorageSiK.EnableSolderingIronCraft en el sandbox, pero el item no
--- explicaba por que en ningun sitio). SOLO se muestra cuando la opcion esta
--- DESACTIVADA (el caso por defecto). Si esta activada, no se añade esta
--- pista: el cuerpo vanilla ya presenta la herramienta y sus propiedades.
--- Envuelto con Controls.wrapText para no
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
	if UI.Controls and UI.Controls.wrapText then
		return UI.Controls.wrapText(text, SOLDERING_LORE_MAX_W, NET_FONT)
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
	local remoteContext = remoteContextFor(self.item)
	if remoteContext then
		-- Even reentrance/cooldown must not fall back to fabricated script state.
		if renderCapturedTooltip then renderCapturedTooltip(self, remoteContext) end
		return
	end
	if withdrawDragActive() then
		if self.setVisible then self:setVisible(false) end
		return
	end
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
	local tw = self.tooltip:getWidth()
	local th = self.tooltip:getHeight()
	if not placeMeasuredTooltip(self, self.item, tw, th) then
		-- Ultimo guardarrail solo para el tooltip vanilla minimo. Nunca se
		-- ensancha ni se añade el anexo cuando no existe una posicion segura.
		local viewport = UI.Viewport.resolve(playerNumForItem(self.item))
		self:setX(math.max(viewport.x, math.min(mx, viewport.x + viewport.w - tw)))
		self:setY(math.max(viewport.y, math.min(my, viewport.y + viewport.h - th)))
	end
	self.tooltip:setX(self:getX())
	self.tooltip:setY(self:getY())
	self:setWidth(tw)
	self:setHeight(th)
	UI.Tooltip.renderFrame(self, 0, 0, self.width, self.height, {
		backgroundColor = self.backgroundColor,
		borderColor = self.borderColor,
	})
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
local function buildTooltipBlocks(item, rowContext)
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
	local remoteContext = GlobalStorageSiK.RemoteItemDetail
		and GlobalStorageSiK.RemoteItemDetail.contextForProbe
		and GlobalStorageSiK.RemoteItemDetail.contextForProbe(item) or nil
	local remote = remoteContext and remoteContext.detail or nil
	-- El detalle remoto describe peso/fluido/VHS, pero no sustituye la fila
	-- autoritativa del escaneo: dicha fila contiene la categoria ya decidida.
	-- Elegir el detalle primero perdia nativePath/routingIdentity y devolvia la
	-- clasificacion del probe efimero (por ejemplo solo "Mobiliario").
	local remoteIdentity = rowContext or (remoteContext and remoteContext.row)
		or (remote and remote.ok == true and remote) or nil
	-- Para una fila remota, el item bajo el ratón puede ser sólo el tipo de
	-- script. La misma sonda indexada que proyecta su nombre en Almacén permite
	-- a RecMedia exponer las enseñanzas vanilla de ESA edición concreta.
	local mediaProbe = item
	if remoteIdentity and GlobalStorageSiK.TerminalItems
		and GlobalStorageSiK.TerminalItems.probeForRow then
		local ok, probe = pcall(GlobalStorageSiK.TerminalItems.probeForRow, remoteIdentity)
		if ok and probe then mediaProbe = probe end
	end

	-- La categoria se presenta una sola vez en la fila/proyeccion comun. El
	-- tooltip remoto conserva datos propios de la unidad, pero no recompone ni
	-- duplica taxonomia: evita otra fuente visual y no puede degradar L1/L2/L3.
	local lines = {}

	-- mediaTitle (2026-08-26, fix de agrupacion de VHS): si el item bajo el
	-- raton es una cinta VHS/radio con contenido concreto, contar SOLO cintas
	-- con ese mismo contenido en vez de sumar todas las del fullType generico.
	local mediaTitle, mediaIndex, dynamicStateKey
	if remoteIdentity then
		mediaTitle = remoteIdentity.mediaTitle
		mediaIndex = remoteIdentity.mediaIndex
		dynamicStateKey = remoteIdentity.dynamicStateKey
	else
		mediaTitle = GlobalStorageSiK.ItemSnapshot and GlobalStorageSiK.ItemSnapshot.recordedMediaTitleFromItem
			and GlobalStorageSiK.ItemSnapshot.recordedMediaTitleFromItem(item)
		mediaIndex = GlobalStorageSiK.ItemSnapshot and GlobalStorageSiK.ItemSnapshot.recordedMediaIndexFromItem
			and GlobalStorageSiK.ItemSnapshot.recordedMediaIndexFromItem(item)
		dynamicStateKey = GlobalStorageSiK.FluidTaxonomy and GlobalStorageSiK.FluidTaxonomy.stateKey
			and GlobalStorageSiK.FluidTaxonomy.stateKey(item)
	end
	-- Remote probes supply identity only. The snapshot-only renderer owns their
	-- condition/food/fluid section; DoTooltip remains exclusive to real items.
	-- Solo VHS: los libros ya describen en DoTooltip vanilla su habilidad y
	-- rango, por lo que repetirlo en el anexo SiK añade ruido sin informacion.
	-- La formacion de una cinta si es dato propio de su media concreta.
	local mediaDetail = remote and remote.ok == true and remote or nil
	if not mediaDetail then mediaDetail = remoteIdentity end
	-- Both paths resolve the exact MediaData. Partial snapshot codes never
	-- substitute for the catalogue or assert that a tape has no teaching.
	local skillLines = getVHSTrainingLines(mediaProbe)
		or (mediaDetail and getRemoteVHSTrainingLines(mediaDetail) or nil)
	if skillLines and #skillLines > 0 then
		blocks[#blocks + 1] = { lines = skillLines, color = { 0.55, 0.85, 1, 1.0 } }
	end

	-- El bloque SiK cierra el tooltip: primero se explica lo que enseña la
	-- unidad y después en qué redes existe. No se crea ningún bloque vacío.
	local networks, loaded, hasAnyNetwork = getCachedCounts(
		fullType, mediaTitle, mediaIndex, dynamicStateKey, playerNumForItem(item))
	if networks and #networks > 0 then
		for i = 1, #networks do
			lines[#lines + 1] = T("IGUI_GS_NetworkCountLine", networks[i].name, tostring(networks[i].count))
		end
	elseif loaded then
		if hasAnyNetwork then
			lines[#lines + 1] = T("IGUI_GS_NetworkCountNone")
		else
			lines[#lines + 1] = T("IGUI_GS_NoNetworksYet")
		end
	end
	if #lines > 0 then
		blocks[#blocks + 1] = { lines = lines, color = { 0.9, 0.85, 0.4, 1.0 } }
	end

	-- Pista narrativa del soldador (solo si el crafteo del GS_SolderingIron
	-- sigue desactivado en el sandbox) - propio color neutro.
	local loreLines = getSolderingIronLoreLines(fullType)
	if loreLines and #loreLines > 0 then
		blocks[#blocks + 1] = { lines = loreLines, color = { 0.75, 0.7, 0.6, 1.0 } }
	end
	return blocks
end

renderCapturedTooltip = function(panel, context)
	if withdrawDragActive() then return end
	local blocks = RemotePresentation.blocks(context)
	local extra = buildTooltipBlocks(panel.item, context.row)
	for i = 1, #extra do blocks[#blocks + 1] = extra[i] end
	local viewport = UI.Viewport.resolve(playerNumForItem(panel.item))
	local width = math.min(MAX_EXT_WIDTH, math.max(1, viewport.w - TOOLTIP_GUTTER * 2))
	local naturalWidth = extensionMetrics(blocks, 240)
	width = math.min(width, naturalWidth)
	local height = 0
	for i = 1, #blocks do
		local block = UI.Tooltip.objectSection(blocks[i].lines, blocks[i])
		blocks[i] = block
		block.lineColor, block.font = block.color, NET_FONT
		block.paddingX, block.paddingY = 8, LINE_PAD
		height = height + UI.Tooltip.measureSection(block, width).height
	end
	if not placeMeasuredTooltip(panel, panel.item, width, height) then return end
	panel:setHeight(height)
	UI.Tooltip.renderFrame(panel, 0, 0, width, height, {
		backgroundColor = panel.backgroundColor, borderColor = panel.borderColor,
	})
	local y = 0
	for i = 1, #blocks do
		local measured = UI.Tooltip.renderSection(panel, blocks[i], 0, y, width)
		y = y + measured.height
	end
end

-- BUG REAL DE ARQUITECTURA cerrado (2026-08-27, ver comentario extenso junto
-- a "hooksInstalled" arriba): dos vias de instalacion, evaluadas en este
-- orden.
--
-- VIA 1 - integracion con TooltipLib (Workshop 3694097672) cuando esta
-- presente: nos registramos como proveedor via TooltipLib.registerProvider,
-- TooltipLib despacha el anexo para inventarios reales. El wrapper único
-- sigue siendo necesario para las sondas remotas: su rama previa evita que
-- cualquier renderer base invente frescura o capacidad desde el script.
-- Decision explicita: no depender de TooltipLib como unica
-- solucion (es un mod opcional de terceros, la mayoria de jugadores no lo
-- tendran) - esta via es una MEJORA cuando aplica, nunca la unica defensa.
--
-- VIA 2 - wrapper propio, autonomo, instalado UNA SOLA VEZ. Para objetos
-- reales sin TooltipLib añade el anexo; con TooltipLib no lo duplica.
-- A diferencia del diseño anterior (dev7-dev28),
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
				if withdrawDragActive() then return end
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
	local usesTooltipLib = installViaTooltipLib()
	if usesTooltipLib then
		GlobalStorageSiK.Log.debug("ItemNetworkTooltip", "registrado como proveedor de TooltipLib")
	end
	if not ISToolTipInv or not ISToolTipInv.render then
		return false
	end

	local original = ISToolTipInv.render
	local wrapper, wrapperBody
	wrapper = function(self, ...)
		if withdrawDragActive() then
			if self.setVisible then self:setVisible(false) end
			return
		end
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
		local remoteContext = remoteContextFor(self.item)
		if remoteContext then return renderCapturedTooltip(self, remoteContext) end
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
		-- TooltipLib already runs our provider for real items. Remote probes
		-- bypass that base render above, so synthetic quantities never leak.
		if usesTooltipLib then return result end
		pcall(function()
			if self.item and self.isVisible and self:isVisible() then
				local blocks = buildTooltipBlocks(self.item, self._gsRemoteRow)
				local baseH = self.height
				local viewport = UI.Viewport.resolve(playerNumForItem(self.item))
				local neededW, extensionH = extensionMetrics(blocks, self.width,
					math.max(1, viewport.w - TOOLTIP_GUTTER * 2))
				-- The annex owns its width; never shrink the vanilla/third-party body.
				local hostW = math.max(self.width, neededW)
				-- Medir ANTES de fijar posicion. Si el rectangulo completo no cabe
				-- sin ocupar el corredor del cursor, se conserva solo vanilla.
				if #blocks > 0 and placeMeasuredTooltip(
					self, self.item, hostW, baseH + extensionH) then
					local usedH = 0
					for i = 1, #blocks do
						usedH = usedH + drawNetworkExtension(
							self, blocks[i].lines, usedH, blocks[i].color, neededW) + 2
					end
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

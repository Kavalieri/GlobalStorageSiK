--[[
	GlobalStorageSiK - Pestaña de ítems del terminal (iconos, orden, menú contextual)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Lista virtual propia SiK UI con pool reutilizable.
]]

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISContextMenu"
require "GS_CatalogManager"
require "GS_I18n"
require "GS_ItemTaxonomy"
require "GS_Libs"
require "GS_BulkFilters"
require "GS_DepositSources"
require "GS_TerminalWithdrawDrag"
require "GS_WithdrawMenu"
require "GS_QuantityPrompt"
require "GS_Log"
require "GS_ContextMenuUi"
require "GS_NodeHighlight"
require "GS_ContainerTargets"
require "GS_TerminalUI_Scroll"
require "GS_SiK_UI_Table"
require "GS_SiK_UI_Core"
require "GS_ItemNetworkTooltip"
require "GS_NetworkReadAction"

GlobalStorageSiK.TerminalItems = {}

local T = GlobalStorageSiK.I18n.text
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local ICON_SIZE = 32
local TABLE_METRICS = GlobalStorageSiK.SiK_UI.Table.metrics()
local ROW_H = math.max(TABLE_METRICS.rowHeight, ICON_SIZE + 8)
local HEADER_H = TABLE_METRICS.headerHeight
local DRAG_THRESHOLD = 6
local ITEM_TEXTURE_CACHE = {}
local ITEM_TABLE_COLUMNS = {
	{ key = "displayName", titleKey = "IGUI_GS_ColName", flex = 1.5, minWidth = 180, pad = 6 },
	{ key = "category", titleKey = "IGUI_GS_ColCategory", flex = 1.0, minWidth = 130, pad = 6 },
	{ key = "zone", titleKey = "IGUI_GS_ColZone", flex = 0.9, minWidth = 110, pad = 6 },
	{ key = "count", titleKey = "IGUI_GS_ColCount", align = "right", measureValues = { "999999" }, pad = 8 },
}
local ITEM_TABLE_OPTIONS = { left = 0, right = 0, gap = 4 }

---@param panel ISPanel
---@param fullType string|nil
---@return number|nil
local function findItemIndex(panel, fullType)
	local items = panel and panel._lastItems
	if not items or not fullType then
		return nil
	end
	for i = 1, #items do
		if items[i].fullType == fullType then
			return i
		end
	end
	return nil
end

---@param panel ISPanel
---@return table[]
local function getSelectedRows(panel)
	local out = {}
	local items = panel and panel._lastItems
	if not items or not panel._selectedKeys then
		return out
	end
	for i = 1, #items do
		local row = items[i]
		if row.fullType and panel._selectedKeys[row.fullType] then
			out[#out + 1] = row
		end
	end
	return out
end

---@param panel ISPanel
---@param fullType string|nil
---@param index number|nil
local function selectSingleRow(panel, fullType, index)
	if not panel or not fullType then
		return
	end
	panel._selectedKeys = { [fullType] = true }
	panel._selectionAnchor = index or findItemIndex(panel, fullType) or 1
end

---@param panel ISPanel
---@param fullType string|nil
local function toggleRowSelection(panel, fullType)
	if not panel or not fullType then
		return
	end
	panel._selectedKeys = panel._selectedKeys or {}
	if panel._selectedKeys[fullType] then
		panel._selectedKeys[fullType] = nil
	else
		panel._selectedKeys[fullType] = true
		panel._selectionAnchor = findItemIndex(panel, fullType) or panel._selectionAnchor
	end
end

---@param panel ISPanel
---@param toIndex number
local function selectRangeTo(panel, toIndex)
	local items = panel._lastItems
	if not items or #items == 0 then
		return
	end
	local anchor = panel._selectionAnchor or toIndex
	local lo = math.max(1, math.min(anchor, toIndex))
	local hi = math.min(#items, math.max(anchor, toIndex))
	panel._selectedKeys = panel._selectedKeys or {}
	for i = lo, hi do
		local row = items[i]
		if row and row.fullType then
			panel._selectedKeys[row.fullType] = true
		end
	end
end

---@param panel ISPanel
---@param row ISPanel
local function handleRowClick(panel, row)
	local data = row.itemData
	if not data or not data.fullType then
		return
	end
	-- BUG REAL (auditoria post-migracion SiK_UI, dev35): `row.rowIndex` es el
	-- indice de la fila POOLEADA/visual, reasignado por `bindItemRowIndex` en
	-- cada `refreshItems()` - si un scroll o refresco de datos ocurre entre el
	-- mousedown y el mouseup de un clic (o durante un Shift-click posterior),
	-- puede quedar apuntando a un dato distinto del que el usuario clico de
	-- verdad, descuadrando el ancla de rango Shift. `findItemIndex` busca por
	-- identidad real (`fullType`) en el dataset actual `panel._lastItems`,
	-- siempre correcto independientemente del pool - preferirlo siempre,
	-- `row.rowIndex` queda solo como reserva si la busqueda no encuentra nada.
	local idx = findItemIndex(panel, data.fullType) or row.rowIndex or 1
	if isCtrlKeyDown and isCtrlKeyDown() then
		toggleRowSelection(panel, data.fullType)
	elseif isShiftKeyDown and isShiftKeyDown() then
		if not panel._selectionAnchor then
			panel._selectionAnchor = idx
		end
		selectRangeTo(panel, idx)
	else
		selectSingleRow(panel, data.fullType, idx)
	end
end

--- Trunca texto al ancho máximo en píxeles.
---@param text string
---@param maxW number
---@param font UIFont|nil
---@return string
local function truncateText(text, maxW, font)
	return GlobalStorageSiK.SiK_UI.truncateText(text, maxW, font or UIFont.Small)
end

GlobalStorageSiK.TerminalItems.ROW_H = ROW_H

-- BUG REAL cerrado (2026-08-22, misma clase que GS_Categories.lua/
-- GS_NetworkCapacity.lua/GS_ItemTaxonomy.lua - sm:getItem(fullType) SIN
-- CACHE, aqui llamado al construir cada fila de la tabla de items del
-- terminal): usar el cache de sesion compartido en vez de consultar
-- ScriptManager a pelo.
---@param fullType string|nil
---@return any|nil
local function scriptItem(fullType)
	if not fullType or not GlobalStorageSiK.I18n or not GlobalStorageSiK.I18n.getScriptItem then return nil end
	return GlobalStorageSiK.I18n.getScriptItem(fullType)
end

-- BUG REAL cerrado (2026-08-22, "crece sin parar" - spam de "Couldn't find
-- item X" confirmado en pruebas reales mientras el raton quedaba sobre una
-- fila con fullType corrupto): itemProbe() nunca cacheaba el caso de
-- fallo - para un item que NUNCA logra resolverse (nuestro caso real,
-- "Base.carpentry_01_16"), tanto itemTexture() como el tooltip de
-- GS_TerminalUI_Items.lua (mas abajo, prerender de la fila) volvian a
-- llamar a props:instanceItem()/instanceItem() EN CADA FRAME mientras la
-- fila seguia dibujandose/bajo el raton - sin cache posible de exito
-- porque nunca habia exito, el intento (y el log vanilla incondicional que
-- dispara) se repetia sin limite. Cachear tambien el fallo, una vez por
-- fila distinta (fullType+worldSprite) durante toda la sesion.
local PROBE_FAIL_CACHE = {}

--- Crea una instancia de tooltip válida sin consultar como ScriptItem los
--- tokens de muebles recogidos.
---@param row table|nil
---@return InventoryItem|nil
local function itemProbe(row)
	if not row then return nil end
	local probeCacheKey = tostring(row.fullType or "") .. "\31" .. tostring(row.worldSprite or "")
	if PROBE_FAIL_CACHE[probeCacheKey] then
		return nil
	end
	-- Los muebles recogidos suelen compartir un fullType generico. Vanilla
	-- reconstruye el InventoryItem desde el sprite del mundo; hacerlo primero
	-- conserva su icono de inventario, nombre y propiedades reales.
	if row.worldSprite then
		if not ISMoveableSpriteProps then
			pcall(require, "Moveables/ISMoveableSpriteProps")
		end
		if ISMoveableSpriteProps and ISMoveableSpriteProps.new then
			local ok, probe = pcall(function()
				local props = ISMoveableSpriteProps.new(row.worldSprite)
				return props and props.instanceItem and props:instanceItem(row.worldSprite) or nil
			end)
			if ok and probe then return probe end
		end
	end
	if scriptItem(row.fullType) and instanceItem then
		local ok, probe = pcall(instanceItem, row.fullType)
		if ok and probe then return probe end
	end
	PROBE_FAIL_CACHE[probeCacheKey] = true
	return nil
end

--- Textura de inventario resuelta como vanilla (`InventoryItem:getTex()`).
--- El resultado se cachea porque la lista virtual puede redibujar la misma
--- fila muchas veces. ScriptItem y sprite del mundo son solo fallbacks.
---@param row table|nil
---@return Texture|nil
local function itemTexture(row)
	if not row or not row.fullType then
		return nil
	end
	local cacheKey = tostring(row.fullType) .. "\31" .. tostring(row.worldSprite or "")
	local cached = ITEM_TEXTURE_CACHE[cacheKey]
	if cached ~= nil then
		return cached or nil
	end

	local probe = itemProbe(row)
	if probe and probe.getTex then
		local ok, tex = pcall(function() return probe:getTex() end)
		if ok and tex then
			ITEM_TEXTURE_CACHE[cacheKey] = tex
			return tex
		end
	end

	local script = scriptItem(row.fullType)
	if script and script.getNormalTexture then
		local ok, tex = pcall(function() return script:getNormalTexture() end)
		if ok and tex then
			ITEM_TEXTURE_CACHE[cacheKey] = tex
			return tex
		end
	end
	if row.worldSprite and getSprite then
		local ok, tex = pcall(function()
			local sprite = getSprite(row.worldSprite)
			return sprite and sprite.getTexture and sprite:getTexture() or nil
		end)
		if ok and tex then
			ITEM_TEXTURE_CACHE[cacheKey] = tex
			return tex
		end
	end
	ITEM_TEXTURE_CACHE[cacheKey] = false
	return nil
end

--- Version PUBLICA de itemTexture, para cualquier otro fichero que necesite
--- el icono real de una fila del Almacen (fullType + worldSprite) - unica
--- ruta "robusta" del mod: reconstruye el item real desde el worldSprite via
--- ISMoveableSpriteProps antes de caer a ScriptItem/sprite crudo, para que
--- items derivados de un Moveable (p.ej. una caja recogida) muestren su
--- icono de inventario real, no un "?" (bug real cerrado 2026-08-23: el
--- "fantasma" de arrastre de GS_TerminalWithdrawDrag.lua mantenia su PROPIA
--- cadena de fallback, mas corta, que nunca llegaba a ISMoveableSpriteProps -
--- unificado aqui, la unica fuente, en vez de mantener dos caminos que
--- pueden divergir).
---@param row table|nil
---@return Texture|nil
GlobalStorageSiK.TerminalItems.textureForRow = itemTexture

-- Cache de respaldo cliente (ver clientLearnedRecipeNames abajo): solo se
-- escribe en exito, nunca en fallo, para no envenenar la entrada como paso
-- el bug ya corregido de -dev17.
local CLIENT_LEARNED_RECIPES_CACHE = {}

-- Cache de respaldo cliente para NumberOfPages (ver numberOfPagesFromItem en
-- GS_ItemSnapshot.lua para la explicacion completa de por que este dato NO
-- esta en el script de una revista de receta, solo en la instancia real).
local CLIENT_NUMBER_OF_PAGES_CACHE = {}

--- Respaldo INSTANTANEO en cliente del numero real de paginas de una revista
--- de receta (row.numberOfPages, capturado por el servidor, puede tardar
--- hasta el proximo reescaneo de zona en llegar). instanceItem() SI dispara
--- OnCreate (ItemCodeOnCreate.onCreateRecipeMagazine es un hook de
--- construccion del motor, no un evento scripted que dependa de estar en el
--- mundo), asi que da el mismo NumberOfPages real que tendria cualquier
--- instancia del mismo fullType.
---@param fullType string
---@return integer|nil
local function clientNumberOfPages(fullType)
	local cached = CLIENT_NUMBER_OF_PAGES_CACHE[fullType]
	if cached ~= nil then return cached or nil end
	-- BUG REAL cerrado (2026-08-23, misma clase exacta que itemProbe en este
	-- mismo fichero - ver comentario mas abajo, "2026-08-22"): esta funcion
	-- SOLO cacheaba el EXITO. Para un fullType que nunca resuelve (item
	-- corrupto/movable mal escaneado), instanceItem(fullType) - funcion
	-- vanilla que imprime su propio log incondicional si el fullType no
	-- existe - se repetia SIN CACHE en cada llamada. isLiteratureReadSafe
	-- (mas abajo) llama a esta funcion desde el render() de CADA fila del
	-- Almacen, en CADA fotograma - con una fila rota simplemente VISIBLE en
	-- la lista (sin necesidad de pasar el raton ni arrastrarla), el fallo se
	-- repetia 30-60 veces/segundo de forma continua. Cachear tambien el
	-- fallo (como `false`) para que la consulta ocurra como mucho una vez
	-- por fullType distinto.
	if not instanceItem then
		CLIENT_NUMBER_OF_PAGES_CACHE[fullType] = false
		return nil
	end
	local ok, probe = pcall(instanceItem, fullType)
	if not ok or not probe or not probe.getNumberOfPages then
		CLIENT_NUMBER_OF_PAGES_CACHE[fullType] = false
		return nil
	end
	local okPages, pages = pcall(function() return probe:getNumberOfPages() end)
	if not okPages or not pages or pages <= 0 then
		CLIENT_NUMBER_OF_PAGES_CACHE[fullType] = false
		return nil
	end
	CLIENT_NUMBER_OF_PAGES_CACHE[fullType] = pages
	return pages
end

--- Respaldo INSTANTANEO en cliente cuando la fila todavia no trae
--- learnedRecipeNames del servidor (nodo sin reescanear desde -dev19).
--- Pedido explicito (2026-08-21): "da igual la recarga, si lo acabo de leer
--- debe marchar el check YA" - el vanilla de verdad es instantaneo, asi que
--- nuestro respaldo tambien debe serlo.
---
--- BUG REAL corregido (2026-08-21, log real: "ok=true known=false" siempre,
--- para 3 revistas confirmadas leidas por el propio tick de vanilla): la
--- sonda SI funcionaba, el fallo estaba en convertir la lista a texto Lua
--- (tostring) y comparar luego contra getKnownRecipes(). Vanilla NUNCA hace
--- esa conversion (ISInventoryPane.lua:2597, ISLiteratureUI.lua:391) -
--- siempre pasa la lista/valor Java ORIGINAL, sin tocar, a containsAll()/
--- contains(). Aqui SI tenemos ese valor original (probe:getLearnedRecipes()
--- es la lista Java real) - se cachea y se compara TAL CUAL, igual que
--- vanilla, sin convertir a string en ningun punto.
---@param fullType string
---@return any|nil recipes lista Java original, o nil si no aplica
local function clientLearnedRecipesRaw(fullType)
	local cached = CLIENT_LEARNED_RECIPES_CACHE[fullType]
	if cached ~= nil then return cached or nil end
	local debugOn = GlobalStorageSiK.Sandbox.debugMode() and GlobalStorageSiK.Sandbox.debugCategoryEnabled("LiteratureRead")
	-- BUG REAL cerrado (2026-08-23, misma clase exacta que clientNumberOfPages
	-- arriba y que itemProbe mas abajo): SOLO se cacheaba el EXITO. Para un
	-- fullType que nunca resuelve, instanceItem() se repetia sin cache en
	-- cada llamada de isLiteratureReadSafe - una vez por fotograma por cada
	-- fila visible del Almacen, sin necesitar interaccion del jugador.
	if not instanceItem then
		if debugOn then
			GlobalStorageSiK.Log.debug("LiteratureRead", "clientLearnedRecipesRaw",
				"fullType=" .. tostring(fullType) .. " SIN instanceItem global en este cliente")
		end
		CLIENT_LEARNED_RECIPES_CACHE[fullType] = false
		return nil
	end
	local ok, probe = pcall(instanceItem, fullType)
	if not ok or not probe or not probe.getLearnedRecipes then
		if debugOn then
			GlobalStorageSiK.Log.debug("LiteratureRead", "clientLearnedRecipesRaw",
				"fullType=" .. tostring(fullType) .. " instanceItem FALLO ok=" .. tostring(ok)
					.. " probe=" .. tostring(probe ~= nil) .. " err=" .. tostring(not ok and probe or nil))
		end
		CLIENT_LEARNED_RECIPES_CACHE[fullType] = false
		return nil
	end
	local okRecipes, recipes = pcall(function() return probe:getLearnedRecipes() end)
	local size = okRecipes and recipes and recipes.size and recipes:size() or -1
	if debugOn then
		GlobalStorageSiK.Log.debug("LiteratureRead", "clientLearnedRecipesRaw",
			"fullType=" .. tostring(fullType) .. " instanceItem OK getLearnedRecipesOk=" .. tostring(okRecipes)
				.. " size=" .. tostring(size))
	end
	if not okRecipes or not recipes or size <= 0 then
		CLIENT_LEARNED_RECIPES_CACHE[fullType] = false
		return nil
	end
	CLIENT_LEARNED_RECIPES_CACHE[fullType] = recipes
	return recipes
end

-- Tick de "ya leído" en el Almacen (pedido explicito 2026-08-21): ahora que
-- se puede leer directamente desde la red (GS_NetworkReadAction.lua), saber
-- de un vistazo cual ya se leyo evita reservarlo/pedirlo prestado sin falta.
-- Replica ISInventoryPane:isLiteratureRead (vanilla, ISUI/ISInventoryPane.lua)
-- - nuestras propias revistas (GS_Manual_*) son literatura vanilla real
-- (ItemType=base:literature, LearnedRecipes en su script), deben funcionar
-- exactamente igual que cualquier revista del juego, no con un mecanismo aparte.
---@param player IsoPlayer|nil
---@param row table|nil fila del Almacén (fullType + learnedRecipeNames del snapshot)
---@return boolean
local function isLiteratureReadSafe(player, row)
	local fullType = row and row.fullType
	if not player or not fullType then return false end
	local debugOn0 = GlobalStorageSiK.Sandbox.debugMode() and GlobalStorageSiK.Sandbox.debugCategoryEnabled("LiteratureRead")

	-- Camino REAL de vanilla (ISInventoryPane.lua:2585-2599, leido del .lua
	-- real del juego instalado, no supuesto): el PRIMER chequeo, antes que
	-- cualquier receta o pagina, es item:getModData().literatureTitle contra
	-- playerObj:isLiteratureRead(literatureTitle). Es el mecanismo que usa
	-- tambien ContextMenu_RecentlyRead (ISInventoryPaneContextMenu.lua:1079).
	-- Las recetas/paginas de mas abajo son solo los FALLBACKS que vanilla
	-- prueba despues si esto no aplica - no el camino principal como se
	-- asumio en rondas anteriores.
	if row.literatureTitle and player.isLiteratureRead then
		local ok, read = pcall(function() return player:isLiteratureRead(row.literatureTitle) end)
		if debugOn0 then
			GlobalStorageSiK.Log.debug("LiteratureRead", "isLiteratureReadSafe (literatureTitle)",
				"fullType=" .. tostring(fullType) .. " literatureTitle=" .. tostring(row.literatureTitle)
					.. " ok=" .. tostring(ok) .. " read=" .. tostring(read))
		end
		if ok and read == true then return true end
	elseif debugOn0 then
		GlobalStorageSiK.Log.debug("LiteratureRead", "isLiteratureReadSafe (literatureTitle)",
			"fullType=" .. tostring(fullType) .. " SIN literatureTitle en la fila (nodo sin reescanear tras leer)")
	end

	local si = scriptItem(fullType)
	if si then
		local ok1, isBook = pcall(function()
			if si.getSkillTrained then
				local skill = si:getSkillTrained()
				local skillBook = skill and SkillBook and SkillBook[skill]
				if skillBook and si.getMaxLevelTrained and player.getPerkLevel
					and si:getMaxLevelTrained() < player:getPerkLevel(skillBook.perk) + 1 then
					return true
				end
			end
			if si.getNumberOfPages and si:getNumberOfPages() > 0 and player.getAlreadyReadPages then
				if player:getAlreadyReadPages(fullType) == si:getNumberOfPages() then return true end
			end
			return false
		end)
		if ok1 and isBook == true then return true end
	end
	local debugOn = GlobalStorageSiK.Sandbox.debugMode() and GlobalStorageSiK.Sandbox.debugCategoryEnabled("LiteratureRead")

	-- Revistas de receta (Base.HuntingMag*, GS_Manual_*, etc.): mismo
	-- mecanismo de "paginas ya leidas" que el chequeo de libro de arriba, NO
	-- las recetas - la diferencia real encontrada 2026-08-21: su
	-- NumberOfPages lo asigna el motor en tiempo de ejecucion via OnCreate
	-- (ItemCodeOnCreate.onCreateRecipeMagazine), no esta en el script como en
	-- un libro de habilidad, asi que scriptItem():getNumberOfPages() daba
	-- siempre 0 y el chequeo de arriba nunca se disparaba para ellas. row.
	-- numberOfPages es el valor real, capturado por el servidor desde una
	-- instancia viva (GS_ItemSnapshot.lua); clientNumberOfPages() es el
	-- respaldo instantaneo via instanceItem() (que SI dispara OnCreate) para
	-- cuando el nodo todavia no trajo ese dato del servidor.
	if player.getAlreadyReadPages then
		local pages = row.numberOfPages or clientNumberOfPages(fullType)
		if pages and pages > 0 then
			local ok, alreadyRead = pcall(function() return player:getAlreadyReadPages(fullType) end)
			if debugOn then
				GlobalStorageSiK.Log.debug("LiteratureRead", "isLiteratureReadSafe (paginas revista)",
					"fullType=" .. tostring(fullType) .. " pages=" .. tostring(pages)
						.. " fromRow=" .. tostring(row.numberOfPages ~= nil)
						.. " ok=" .. tostring(ok) .. " alreadyRead=" .. tostring(alreadyRead))
			end
			if ok and alreadyRead == pages then return true end
		end
	end

	-- "Camino 0" (comparar scriptItem(fullType):getLearnedRecipes() contra
	-- player:getKnownRecipes() via containsAll()/contains(), SIN convertir a
	-- string) ELIMINADO (2026-08-21) - causa raiz real, encontrada leyendo el
	-- .lua real de vanilla instalado: ISInventoryPane.lua:2597 e
	-- ISLiteratureUI.lua:373-374/391 NUNCA llaman getLearnedRecipes() sobre un
	-- scriptItem (plantilla de definicion), SIEMPRE sobre la INSTANCIA REAL
	-- del item mostrado/leido. Un scriptItem() es una plantilla distinta -
	-- comparar sus objetos Receta en bruto contra getKnownRecipes() (misma
	-- familia de bug que el intento anterior con instanceItem(), tambien
	-- descartado) daba "ok=true known=false" SIEMPRE pese a nombres
	-- correctos, confirmado con log real en produccion (build -dev27:
	-- perRecipe=[Program GS Floppy Drive Network Disk=false] pese a que esa
	-- receta la enseña justo ese manual). La comparacion en bruto (sin
	-- tostring) solo es fiable cuando el objeto Receta viene de la instancia
	-- real igual que hace vanilla - los caminos A/B de abajo ya cubren esto,
	-- comparando por NOMBRE (tostring) en vez de por identidad de objeto,
	-- que es robusto sea cual sea el origen del objeto Receta.

	-- Camino A (preferido cuando existe): recetas capturadas por el SERVIDOR
	-- desde un item REAL durante el escaneo (GS_ItemSnapshot.lua), pero
	-- viajaron por red como texto Lua (un valor Java vivo no se puede
	-- serializar) - se comparan normalizando AMBOS lados con tostring().
	-- El camino B de abajo usa el mismo patron por nombre, sobre una fuente
	-- distinta (sonda cliente en vez de captura de servidor).
	if row.learnedRecipeNames and #row.learnedRecipeNames > 0 and player.getKnownRecipes then
		local recipes = row.learnedRecipeNames
		local ok, known = pcall(function()
			local knownSet = {}
			local knownRecipes = player:getKnownRecipes()
			for i = 0, knownRecipes:size() - 1 do
				knownSet[tostring(knownRecipes:get(i))] = true
			end
			for i = 1, #recipes do
				if not knownSet[tostring(recipes[i])] then
					return false
				end
			end
			return true
		end)
		if debugOn then
			GlobalStorageSiK.Log.debug("LiteratureRead", "isLiteratureReadSafe (red)",
				"fullType=" .. tostring(fullType) .. " recipes=" .. table.concat(recipes, ",")
					.. " ok=" .. tostring(ok) .. " known=" .. tostring(known))
		end
		if ok and known == true then return true end
	end

	-- Camino B: respaldo instantaneo en cliente cuando la fila todavia no
	-- trae el dato del servidor (nodo sin reescanear desde -dev19). Fuente:
	-- instanceItem(fullType) - una sonda SINTETICA, no la instancia real que
	-- el jugador tiene/lee. Por eso NO se compara en bruto con containsAll()/
	-- contains() (bug real encontrado 2026-08-21, misma familia que el
	-- "Camino 0" ya eliminado mas arriba: un objeto Receta obtenido de una
	-- fuente que no es la instancia real del item mostrado/leido no es
	-- reconocido como igual por Java aunque su nombre imprima identico) -
	-- se compara por NOMBRE (tostring), igual que el Camino A, que es
	-- robusto sea cual sea el origen del objeto Receta.
	local rawRecipes = clientLearnedRecipesRaw(fullType)
	if rawRecipes and player.getKnownRecipes then
		local ok, known = pcall(function()
			local knownSet = {}
			local knownRecipes = player:getKnownRecipes()
			for i = 0, knownRecipes:size() - 1 do
				knownSet[tostring(knownRecipes:get(i))] = true
			end
			for i = 0, rawRecipes:size() - 1 do
				if not knownSet[tostring(rawRecipes:get(i))] then
					return false
				end
			end
			return true
		end)
		if debugOn then
			GlobalStorageSiK.Log.debug("LiteratureRead", "isLiteratureReadSafe (cliente, por nombre)",
				"fullType=" .. tostring(fullType) .. " ok=" .. tostring(ok) .. " known=" .. tostring(known))
		end
		if ok and known == true then return true end
	end
	return false
end

--- Nombre de zona del nodo indicado, ya sincronizado en terminalState.nodes
--- (cada nodo ya trae zoneName, ver GS_Server.lua:serializeNodes) - sin
--- llamada de red aparte.
---@param nodes table[]
---@param nodeId string
---@return string|nil
local function findNodeZoneName(nodes, nodeId)
	for i = 1, #nodes do
		if nodes[i].id == nodeId then
			-- "or nil" en vez de devolver zoneName tal cual: una cadena
			-- vacia es VERDADERA en Lua (solo nil/false son falsy), asi que
			-- un "zoneName or T(...)" en el llamante NUNCA caeria al
			-- fallback "Global" si zoneName llegara como "" en vez de nil -
			-- se quedaria en blanco de verdad, sin mostrar nada.
			local zn = nodes[i].zoneName
			if zn == "" then return nil end
			return zn
		end
	end
	return nil
end

--- Columna "Zona" (dev26 ronda 4quinquies, pedido explicito del usuario):
--- nombre de la zona donde esta almacenado este tipo de item. Un fullType
--- agregado puede repartirse en VARIOS contenedores (ver data.locations,
--- GS_Index.lua) - si todos caen en la misma zona se muestra su nombre, si
--- no se muestra un aviso generico en vez de elegir una zona al azar.
---@param terminal GS_TerminalUI|nil
---@param data table|nil
---@return string
-- BUG REAL DE RENDIMIENTO cerrado (2026-08-26, propuesta de mejora futura de
-- Desarrollo tras validar dev20 - "cachear resolveZoneLabel() por fila y
-- referencia de terminalState.nodes; la ordenacion por zona todavia puede
-- recorrer ubicaciones y nodos por cada fila"): memorizado por fila, con
-- INVALIDACION explicita contra la referencia de `nodes` usada - la lista de
-- nodos puede cambiar (renombrar zona, mover terminal) SIN que la fila del
-- item se reemplace (a diferencia de items/precio, que si generan filas
-- nuevas en cada sync) - cachear solo por fila sin comprobar `nodes` daria
-- una zona obsoleta tras ese tipo de cambio.
local zoneLabelCache = setmetatable({}, { __mode = "k" })
local function resolveZoneLabel(terminal, data)
	local locations = data and data.locations
	if not terminal or not locations or #locations == 0 then
		return "—"
	end
	local nodes = terminal.terminalState and terminal.terminalState.nodes or {}
	local cached = zoneLabelCache[data]
	if cached and cached.nodes == nodes then
		return cached.label
	end
	local zoneName, multiple = nil, false
	for i = 1, #locations do
		local zn = findNodeZoneName(nodes, locations[i].nodeId) or T("IGUI_GS_ProtocolGlobal")
		if zoneName == nil then
			zoneName = zn
		elseif zoneName ~= zn then
			multiple = true
		end
	end
	local label = multiple and T("IGUI_GS_ColZoneMultiple") or (zoneName or "—")
	zoneLabelCache[data] = { nodes = nodes, label = label }
	return label
end

--- Ordena filas según clave y dirección.
---@param rows table[]
---@param sortKey string
---@param ascending boolean
---@return table[]
-- BUG REAL DE RENDIMIENTO cerrado (2026-08-26, propuesta de mejora futura de
-- Desarrollo tras validar dev20 - "mantener claves de ordenacion estables por
-- fila para displayName/category; sus resoluciones profundas ya estan
-- cacheadas (dev20), pero la propia tabla de claves se reconstruye en cada
-- ordenacion"): "displayName"/"category" son puras por fila (dependen solo
-- de row.fullType/row.displayName/row.worldSprite/row.category/
-- row.subCategory, que nunca cambian sin que el servidor entregue una fila
-- NUEVA - ver comentario de itemSearchHaystackCache en GS_I18n.lua sobre esta
-- misma invariante) - memorizadas de forma persistente por fila+clave, no
-- solo dentro de una llamada a sortRows. "zone" NO se memoriza aqui (tiene su
-- propia cache con invalidacion por referencia de nodos, ver
-- resolveZoneLabel) y "count" es ya trivial (lectura directa de campo, cachearla
-- no aportaria nada).
-- BUG REAL DE RENDIMIENTO #2 cerrado (2026-08-27, informe de telemetria de
-- Simucad tras dev19: mismo hallazgo que itemSearchHaystackCache en
-- GS_I18n.lua - "el snapshot del servidor entrega tablas de fila nuevas
-- aproximadamente cada dos segundos", la clave por REFERENCIA de `row`
-- (`__mode="k"`) pierde efectividad entre snapshots aunque el tipo/nombre/
-- categoria de la fila no haya cambiado. Cambiada a clave por COMPUESTO de
-- los campos intrinsecos de los que depende (fullType/worldSprite/
-- displayName/category/subCategory/gsSubKeysStr) + sortKey - mismo patron
-- ya usado por itemSearchHaystackCache/itemTaxonomyResolveCache. `count` y
-- `zone` siguen fuera de esta cache (ya lo estaban: count es lectura
-- directa, zone tiene su propia invalidacion por referencia de nodos).
local sortKeyValueCache = GlobalStorageSiK.CatalogManager
	and GlobalStorageSiK.CatalogManager.createEpochCache() or {}
local function sortRowCacheKey(row)
	return tostring(row.fullType or "") .. "\1" .. tostring(row.worldSprite or "")
		.. "\1" .. tostring(row.displayName or "") .. "\1" .. tostring(row.category or "")
		.. "\1" .. tostring(row.subCategory or "") .. "\1" .. tostring(row.gsSubKeysStr or "")
end
local function sortKeyValue(row, sortKey, terminal)
	if sortKey == "count" then
		return row.count or 0
	end
	if sortKey == "zone" then
		return string.lower(resolveZoneLabel(terminal, row))
	end
	local cacheKey = sortRowCacheKey(row) .. "\1" .. sortKey
	local cached = sortKeyValueCache[cacheKey]
	if cached ~= nil then
		return cached
	end
	local value
	if sortKey == "category" then
		if GlobalStorageSiK.ItemTaxonomy and GlobalStorageSiK.ItemTaxonomy.resolve then
			value = string.lower(GlobalStorageSiK.ItemTaxonomy.resolve(row.fullType, row).fullLabel)
		else
			value = string.lower(tostring(row.category or ""))
		end
	else
		local name = GlobalStorageSiK.I18n.itemDisplayName(row.fullType, row.displayName, row.worldSprite)
		value = string.lower(tostring(name or row.fullType or ""))
	end
	sortKeyValueCache[cacheKey] = value
	return value
end

--- Ordena filas según clave y dirección.
---@param rows table[]
---@param sortKey string
---@param ascending boolean
---@param terminal GS_TerminalUI|nil solo lo necesita sortKey=="zone"
---@return table[]
local function sortRows(rows, sortKey, ascending, terminal)
	local sorted = {}
	for i = 1, #rows do
		sorted[i] = rows[i]
	end
	-- BUG REAL DE RENDIMIENTO cerrado (2026-08-26, reportado por un miembro de
	-- la comunidad con telemetria real de servidor dedicado: red de 1286
	-- tipos/188 nodos, refreshItemsTab en 1157ms, 1069ms solo del sort -
	-- "displayName", la clave POR DEFECTO, resolvia I18n.itemDisplayName() DOS
	-- VECES POR COMPARACION, ~26000 llamadas para 1286 filas). Cerrado en 2
	-- pasos: primero (dev18) un cache local de UNA pasada por sortRows;
	-- despues (dev20/dev21, propuesta de mejora futura de Desarrollo tras
	-- validar dev20) sortKeyValue() paso a memorizar sus propios resultados de
	-- forma PERSISTENTE por fila (sortKeyValueCache, arriba) - ya no hace
	-- falta ninguna tabla intermedia aqui, el propio comparador puede llamar a
	-- sortKeyValue() directamente en cada comparacion: la primera vez que se
	-- ve una fila hace el trabajo real, cualquier ordenacion posterior (o
	-- reordenar mientras se escribe en el buscador) son lecturas O(1).
	table.sort(sorted, function(a, b)
		local av = sortKeyValue(a, sortKey, terminal)
		local bv = sortKeyValue(b, sortKey, terminal)
		if av == bv then
			return (a.fullType or "") < (b.fullType or "")
		end
		if ascending then
			return av < bv
		end
		return av > bv
	end)
	return sorted
end

--- Taxonomía vanilla resuelta de una fila.
---@param row table|nil
---@return table
function GlobalStorageSiK.TerminalItems.rowTaxonomy(row)
	if not row then
		return { mainKey = "", subKey = "", mainLabel = "", subLabel = "", fullLabel = "",
			groupKey = "", subGroupKey = nil, groupLabel = "", subGroupLabel = nil, leafLabel = nil }
	end
	return GlobalStorageSiK.ItemTaxonomy.resolve(row.fullType, row)
end

--- Recopila categorías principales únicas del catálogo.
---@param rows table[]
---@return table[] { key: string, label: string, typeCount: number }
function GlobalStorageSiK.TerminalItems.collectMainCategoryFilters(rows)
	return GlobalStorageSiK.ItemTaxonomy.collectMainFilters(rows or {})
end

--- Recopila subcategorías únicas (opcionalmente restringidas a una categoría principal).
---@param rows table[]
---@param mainKey string|nil
---@return table[] { key: string, label: string, typeCount: number }
function GlobalStorageSiK.TerminalItems.collectSubCategoryFilters(rows, mainKey)
	return GlobalStorageSiK.ItemTaxonomy.collectSubFilters(rows or {}, mainKey)
end

--- Filtra filas por categoría principal (vacío = todas).
---@param rows table[]
---@param mainKey string|nil
---@return table[]
function GlobalStorageSiK.TerminalItems.filterByMainCategory(rows, mainKey)
	if not mainKey or mainKey == "" then
		return rows
	end
	local EXT = GlobalStorageSiK.ItemTaxonomy.EXT_GROUP_PREFIX
	if mainKey:sub(1, #EXT) == EXT then
		-- Clave de familia canonica (groupKey, fuente unica - ver
		-- GS_ItemTaxonomy.lua resolve()/collectMainFilters): se compara por clave, NO
		-- solo por extGroupLabel, para incluir tambien los items "genericos"
		-- de la misma familia que no tienen division cualificada (antes se
		-- quedaban fuera del filtro sin que se notara, ya que rara vez se
		-- posee a la vez un item de cada variante).
		local group = string.lower(mainKey:sub(#EXT + 1))
		local filtered = {}
		for i = 1, #rows do
			local tax = GlobalStorageSiK.TerminalItems.rowTaxonomy(rows[i])
			if tax.groupKey and tax.groupKey ~= "" and string.lower(tax.groupKey) == group then
				filtered[#filtered + 1] = rows[i]
			end
		end
		return filtered
	end
	local key = string.lower(mainKey)
	local filtered = {}
	for i = 1, #rows do
		if GlobalStorageSiK.TerminalItems.rowTaxonomy(rows[i]).mainKey == key then
			filtered[#filtered + 1] = rows[i]
		end
	end
	return filtered
end

--- Recopila sub-subcategorías (Nivel 3) únicas, restringidas a Nivel 1 (y
--- Nivel 2, si se eligió).
---@param rows table[]
---@param mainKey string|nil
---@param subKey string|nil
---@return table[] { key: string, label: string, typeCount: number }
function GlobalStorageSiK.TerminalItems.collectLeafCategoryFilters(rows, mainKey, subKey)
	return GlobalStorageSiK.ItemTaxonomy.collectLeafFilters(rows or {}, mainKey, subKey)
end

--- Filtra filas por Nivel 2 (subcategoría, ej. "Perecedero" - vacío = todas).
--- Acepta CUALQUIER hoja de Nivel 3 dentro de ese subgrupo (fruta, queso,
--- carne perecederos...), no solo coincidencia exacta - misma fuente unica
--- (tax.groupKey/subGroupKey) que usa GS_Router.lua al depositar.
---@param rows table[]
---@param subKey string|nil clave con prefijo SUBGROUP_PREFIX
---@return table[]
function GlobalStorageSiK.TerminalItems.filterBySubCategory(rows, subKey)
	if not subKey or subKey == "" then
		return rows
	end
	local SUB = GlobalStorageSiK.ItemTaxonomy.SUBGROUP_PREFIX
	if subKey:sub(1, #SUB) ~= SUB then
		return rows
	end
	local rest = subKey:sub(#SUB + 1)
	local sepPos = rest:find("::", 1, true)
	if not sepPos then
		return rows
	end
	local wantGroup = string.lower(rest:sub(1, sepPos - 1))
	local wantSubGroup = string.lower(rest:sub(sepPos + 2))
	local filtered = {}
	for i = 1, #rows do
		local tax = GlobalStorageSiK.TerminalItems.rowTaxonomy(rows[i])
		if tax.groupKey and string.lower(tax.groupKey) == wantGroup
			and tax.subGroupKey and string.lower(tax.subGroupKey) == wantSubGroup then
			filtered[#filtered + 1] = rows[i]
		end
	end
	return filtered
end

--- Filtra filas por Nivel 3 (hoja final: tipo de comida, hueco de
--- joyeria/ropa, o tercer segmento con guion de un mod de categorias
--- extendidas - vacío = todas). Coincidencia EXACTA, es el nivel mas especifico.
---@param rows table[]
---@param leafKey string|nil
---@return table[]
function GlobalStorageSiK.TerminalItems.filterByLeafCategory(rows, leafKey)
	if not leafKey or leafKey == "" then
		return rows
	end
	local key = string.lower(leafKey)

	-- Clave compuesta "categoria::hueco" (joyeria O cualquier subcategoria
	-- vanilla cruda, ej. la prenda exacta de Ropa) - ver
	-- GS_ItemTaxonomy.lua:collectLeafFilters.
	local sepPos = key:find("::", 1, true)
	if sepPos then
		local mainPart = key:sub(1, sepPos - 1)
		local slotPart = key:sub(sepPos + 2)
		local filtered = {}
		for i = 1, #rows do
			local tax = GlobalStorageSiK.TerminalItems.rowTaxonomy(rows[i])
			if tax.mainKey == mainPart and (tax.jewelrySlotKey == slotPart or tax.subKey == slotPart) then
				filtered[#filtered + 1] = rows[i]
			end
		end
		return filtered
	end

	-- Hoja "plana": el tercer segmento con guion ya deja mainCanon completo
	-- y unico (ej. "foodperishablecheese"), coincidencia exacta contra mainKey.
	local filtered = {}
	for i = 1, #rows do
		if GlobalStorageSiK.TerminalItems.rowTaxonomy(rows[i]).mainKey == key then
			filtered[#filtered + 1] = rows[i]
		end
	end
	return filtered
end

---@param panel ISPanel
---@param fullType string|nil
---@return boolean
local function isRowSelected(panel, fullType)
	if not panel or not fullType or not panel._selectedKeys then
		return false
	end
	return panel._selectedKeys[fullType] == true
end

---@param panel ISPanel
local function clearRowSelection(panel)
	if panel then
		panel._selectedKeys = {}
		panel._selectionAnchor = nil
	end
end

--- Menú contextual de fila de ítem de la red.
---@param terminal GS_TerminalUI
---@param data table
---@param amount number
---@param targetKey string|nil
local function withdrawFromRowData(terminal, data, amount, targetKey)
	if terminal and data then
		terminal:onWithdrawRow(data, amount, targetKey)
	end
end

--- Retira usando inventario activo o bajo el ratón.
---@param terminal GS_TerminalUI
---@param data table
---@param amount number
local function withdrawRowWithActiveTarget(terminal, data, amount)
	if not terminal or not data then
		return
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getSpecificPlayer(0)
	local key = GlobalStorageSiK.ContainerTargets.resolveWithdrawTarget(player)
	terminal:onWithdrawRow(data, amount, key)
end

--- Construye titulo + descripcion (multi-linea, separador <LINE>) con los
--- datos utiles de un item de la red: tipo, categoria, peso unitario y
--- cantidad en esta red. Sin informacion de debug (no fullType interno de
--- Java, no ModData, etc.), solo lo que le interesa al jugador.
---@param fullType string
---@param data table|nil fila con count/category/subCategory
---@return string title
---@return string[] lines
local function buildItemDetailLines(fullType, data)
	local name = GlobalStorageSiK.I18n.itemDisplayName(fullType, data and data.displayName)
	local weightText = "?"
	-- Igual que GlobalStorageSiK.NetworkCapacity.estimateSnapshotWeight: prueba
	-- getActualWeight() primero, getWeight() como respaldo (en 42.20 no todos
	-- los script items resuelven getWeight() de forma fiable).
	-- Cache de sesion compartido (GlobalStorageSiK.I18n.getScriptItem) en vez
	-- de sm:getItem() a pelo - mismo bug de spam ya cerrado en los demas
	-- sitios de este fichero.
	if GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.getScriptItem then
		local ok, w = pcall(function()
			local script = GlobalStorageSiK.I18n.getScriptItem(fullType)
			if script and script.getActualWeight then
				return script:getActualWeight()
			end
			if script and script.getWeight then
				return script:getWeight()
			end
			return nil
		end)
		if ok and w then
			weightText = string.format("%.2f", w)
		end
	end
	local cat = GlobalStorageSiK.I18n.itemCategoryDisplay(fullType, data and data.category, data and data.subCategory, data and data.gsSubKeysStr)
	local count = data and data.count or 0
	local lines = {
		T("IGUI_GS_DetailType", fullType),
		T("IGUI_GS_DetailCategory", cat),
		T("IGUI_GS_DetailWeight", weightText),
		T("IGUI_GS_DetailCount", tostring(count)),
	}
	-- Desglose de OTRAS redes del jugador que tambien tengan este fullType
	-- (misma cache/fuente que el tooltip global vanilla, filtrada por
	-- Permissions.canAccess en el servidor: solo redes propias/con acceso,
	-- nunca de otros jugadores o facciones). La red activa ya se muestra
	-- arriba via "Cant." con el dato instantaneo del estado del terminal;
	-- aqui solo se añaden las DEMAS, para no duplicar la misma cifra.
	if GlobalStorageSiK.ItemNetworkTooltip and GlobalStorageSiK.ItemNetworkTooltip.getCachedCounts then
		local activeId = GlobalStorageSiK.Client and GlobalStorageSiK.Client.activeNetworkId
		local networks = GlobalStorageSiK.ItemNetworkTooltip.getCachedCounts(fullType)
		if networks then
			for i = 1, #networks do
				local n = networks[i]
				if n.id ~= activeId then
					lines[#lines + 1] = T("IGUI_GS_NetworkCountLine", n.name, tostring(n.count))
				end
			end
		end
	end
	return name, lines
end

--- Añade opción Examinar para ítems de la red (sin invocar menú vanilla).
---@param cm ISContextMenu
---@param player IsoPlayer|nil
---@param fullType string
local function addNetworkItemExamine(cm, player, fullType)
	if not cm or not fullType or not instanceItem then
		return
	end
	local probe = instanceItem(fullType)
	if not probe then
		return
	end
	local label = T("IGUI_GS_Examine")
	if getText then
		local ok, examine = pcall(getText, "ContextMenu_examine")
		if ok and examine and examine ~= "ContextMenu_examine" then
			label = examine
		else
			ok, examine = pcall(getText, "IGUI_invpanel_Inspect")
			if ok and examine and examine ~= "IGUI_invpanel_Inspect" then
				label = examine
			end
		end
	end
	cm:addOption(label, player, function(target)
		local p = target or player
		if not p or not p.setHaloNote then
			return
		end
		local sample = instanceItem(fullType)
		local text = sample and sample:getName() or fullType
		if sample and sample.getDescription then
			local desc = sample:getDescription()
			if desc and desc ~= "" then
				text = desc
			end
		end
		pcall(function()
			p:setHaloNote(text, 220, 220, 200, 450)
		end)
	end)
end

--- Menú contextual de fila de ítem.
---@param listPanel ISPanel
---@param terminal GS_TerminalUI
---@param data table
local function openItemContextMenu(listPanel, terminal, data)
	if not terminal or not data then
		return
	end
	local player = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getSpecificPlayer(0)
	local playerNum = 0
	if player and player.getPlayerNum then
		playerNum = player:getPlayerNum()
	end

	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	local menuState = GlobalStorageSiK.ContextMenuUi.prepareTerminal(ui)

	local ok, err = pcall(function()
		local cm = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
		addNetworkItemExamine(cm, player, data.fullType)
		GlobalStorageSiK.NetworkReadAction.addToContext(cm, player, data, terminal)
		cm:addOption(T("IGUI_GS_ViewDetails"), player, function(target)
			local p = target or player
			if not p or not p.setHaloNote then return end
			local name, lines = buildItemDetailLines(data.fullType, data)
			pcall(function()
				p:setHaloNote(name .. " | " .. table.concat(lines, " | "), 220, 220, 200, 600)
			end)
		end)

		-- BUG REAL reportado por el usuario (2026-08-26): "el menu contextual
		-- del almacen es muy grande... las opciones de transferencia deben ir
		-- dentro del submenu de Retirar". addFlatToContext volcaba TODAS las
		-- opciones de retiro (destino, cantidades, seleccion) sueltas en la
		-- raiz del menu - GlobalStorageSiK.WithdrawMenu.addToContext YA
		-- construia exactamente el submenu "Retirar" agrupado que hacia
		-- falta (usado en otro punto del proyecto), simplemente no se llamaba
		-- aqui todavia. Cero codigo nuevo, solo la llamada correcta.
		GlobalStorageSiK.WithdrawMenu.addToContext(cm, player, data, function(rowData, amount, targetKey)
			withdrawFromRowData(terminal, rowData, amount, targetKey)
		end, getSelectedRows(listPanel))

		-- "Localizar objeto" (dev26 ronda 4quinquies, ver Documentacion/
		-- pending-work/DEFERRED.md): ilumina TODOS los contenedores reales que
		-- aportan a esta fila agregada (data.locations, ver GS_Index.lua) con
		-- el mismo sistema seguro ya usado en la pestaña Nodos
		-- (GS_NodeHighlight.highlightNodes) - nunca un resaltado propio nuevo,
		-- misma proteccion contra parpadeo/coste de render repetido.
		if data.locations and #data.locations > 0 then
			cm:addOption(T("IGUI_GS_LocateItem"), player, function()
				local nodeIds = {}
				for i = 1, #data.locations do
					nodeIds[#nodeIds + 1] = data.locations[i].nodeId
				end
				local allNodes = terminal.terminalState and terminal.terminalState.nodes or {}
				GlobalStorageSiK.NodeHighlight.highlightNodes(nodeIds, allNodes)
			end)
		end

		GlobalStorageSiK.ContextMenuUi.raiseMenu(cm)
	end)

	if not ok then
		GlobalStorageSiK.Log.error("TerminalUI", "openItemContextMenu failed", err)
		if menuState and menuState.ui then
			if menuState.wasVisible then
				menuState.ui:setVisible(true)
			end
			if menuState.wasAlwaysOnTop then
				menuState.ui:setAlwaysOnTop(true)
			end
		end
		return
	end

	GlobalStorageSiK.ContextMenuUi.scheduleTerminalRestore(menuState)
end

--- Crea una fila reutilizable de la lista virtual SiK UI.
---@param scroll ISPanel
---@param listPanel ISPanel
---@param terminal GS_TerminalUI
---@return ISPanel
local function createItemRow(scroll, listPanel, terminal)
	local rowW = scroll.width or 200
	if scroll.getWidth then
		rowW = math.max(120, scroll:getWidth() - 8)
	end
	local row = ISPanel:new(0, 0, rowW, ROW_H)
	row:initialise()
	row.listPanel = listPanel
	row.terminal = terminal
	row.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	row.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	row._gsVirtualRow = true

	row.prerender = function(self)
		ISPanel.prerender(self)
		local data = self.itemData
		local selected = data and self.listPanel and isRowSelected(self.listPanel, data.fullType)
		GlobalStorageSiK.SiK_UI.drawTableRowBackground(self, self.rowIndex, self:isMouseOver(), selected)
		if data and GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
			local types = GlobalStorageSiK.TerminalWithdrawDrag.activePreviewTypes
			if types and data.fullType and types[data.fullType] then
				self:drawRect(0, 0, self.width, self.height, 0.25, 0.28, 0.28, 0.28)
			elseif GlobalStorageSiK.TerminalWithdrawDrag.activePreview
				and GlobalStorageSiK.TerminalWithdrawDrag.activePreview.fullType == data.fullType then
				self:drawRect(0, 0, self.width, self.height, 0.25, 0.28, 0.28, 0.28)
			end
		end
		if data then
			local pal = GlobalStorageSiK.SiK_UI.PALETTE
			local tex = itemTexture(data)
			local iconY = math.floor((self.height - ICON_SIZE) / 2)
			if tex then
				self:drawTextureScaledAspect(tex, 6, iconY, ICON_SIZE, ICON_SIZE, 1, 1, 1, 1)
			end
			-- Mismo tick vanilla (media/ui/Tick_Mark-10.png) que ISInventoryPane
			-- dibuja sobre un libro/revista ya leido - reconocible al instante,
			-- sin inventar un icono propio para lo mismo.
			local player = self.terminal and GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer()
				or getSpecificPlayer(0)
			if isLiteratureReadSafe(player, data) then
				local tick = getTexture("media/ui/Tick_Mark-10.png")
				if tick then
					self:drawTexture(tick, 6, iconY - 1, 1, 1, 1, 1)
				end
			end
			local columns = GlobalStorageSiK.SiK_UI.Table.resolveColumns(
				self.width, ITEM_TABLE_COLUMNS, ITEM_TABLE_OPTIONS)
			local nameCol, catCol, zoneCol, countCol = columns[1], columns[2], columns[3], columns[4]
			local textX = nameCol.x + 6 + ICON_SIZE + 8
			local name = GlobalStorageSiK.I18n.itemDisplayName(data.fullType, data.displayName, data.worldSprite)
			local cat = GlobalStorageSiK.I18n.itemCategoryDisplay(data.fullType, data.category, data.subCategory, data.gsSubKeysStr)
			local zoneLabel = self._gsZoneLabel or "—"
			local count = tostring(data.count or 0)
			local yMid = math.floor((self.height - FONT_HGT_SMALL) / 2)
			local catX = catCol.x + catCol.pad
			local zoneX = zoneCol.x + zoneCol.pad
			local nameMaxW = nameCol.finish - textX - 8
			-- Reserva de espacio para la columna Cant. (numero corto, pero con
			-- margen holgado: hay contenedores con miles de unidades) antes de
			-- truncar categoria/zona - sin esto, un texto largo (p.ej.
			-- "Herramienta / Arma - Arma de hoja corta") se dibujaba entero y se
			-- solapaba visualmente con la cantidad.
			local catMaxW = catCol.finish - catX - catCol.pad
			local zoneMaxW = zoneCol.finish - zoneX - zoneCol.pad
			self:drawText(truncateText(name, nameMaxW, UIFont.Small), textX, yMid, pal.textPrimary[1], pal.textPrimary[2], pal.textPrimary[3], 1, UIFont.Small)
			self:drawText(truncateText(cat, catMaxW, UIFont.Small), catX, yMid, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small)
			self:drawText(truncateText(zoneLabel, zoneMaxW, UIFont.Small), zoneX, yMid, pal.textMuted[1], pal.textMuted[2], pal.textMuted[3], 1, UIFont.Small)
			self:drawTextRight(count, countCol.finish - countCol.pad, yMid, pal.textSecondary[1], pal.textSecondary[2], pal.textSecondary[3], 1, UIFont.Small)
		end

		-- Tooltip al pasar el raton: en TODA la fila (icono/nombre/categoria)
		-- mostramos el mismo ISToolTipInv vanilla completo (comida, peso,
		-- estado, "cuanto tengo en red" + categoria detectada, ambos anadidos
		-- por GS_ItemNetworkTooltip.lua a CUALQUIER ISToolTipInv, incluido
		-- este). Ya no hace falta un tooltip de texto plano aparte para la
		-- columna Categoria (antes duplicaba la info que ahora ya sale aqui);
		-- si el texto no cabe en la columna, se trunca con "..." (ver
		-- drawText de arriba) y el detalle completo se lee en este tooltip.
		-- Se oculta mientras hay un arrastre activo (no tapar el preview de drop).
		if data and self:isMouseOver() and not GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
			local tooltipKey = tostring(data.fullType) .. "\31" .. tostring(data.worldSprite or "")
			if not self._gsTooltip or self._gsTooltip._gsItemKey ~= tooltipKey then
				local probe = itemProbe(data)
				if probe then
					if self._gsTooltip then
						self._gsTooltip:setItem(probe)
					else
						self._gsTooltip = ISToolTipInv:new(probe)
						self._gsTooltip:initialise()
						self._gsTooltip:setOwner(self)
						local ttPlayer = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer() or getSpecificPlayer(0)
						self._gsTooltip:setCharacter(ttPlayer)
					end
					self._gsTooltip._gsItemKey = tooltipKey
				elseif self._gsTooltip then
					self._gsTooltip:removeFromUIManager()
					self._gsTooltip:setVisible(false)
					self._gsTooltip = nil
				end
			end
			if self._gsTooltip then
				self._gsTooltip:setVisible(true)
				self._gsTooltip:addToUIManager()
				self._gsTooltip:bringToTop()
			end
		else
			if self._gsTooltip and self._gsTooltip:isVisible() then
				self._gsTooltip:removeFromUIManager()
				self._gsTooltip:setVisible(false)
			end
		end
	end

	row.onMouseDown = function(self, x, y)
		if isRightMouseButtonDown and isRightMouseButtonDown() then
			return false
		end
		self._gsDragPending = true
		self._gsDragAccum = 0
		return true
	end

	row.onMouseMove = function(self, dx, dy)
		if not self._gsDragPending or not self.itemData or not self.terminal then
			return false
		end
		self._gsDragAccum = (self._gsDragAccum or 0) + math.abs(dx or 0) + math.abs(dy or 0)
		if self._gsDragAccum >= DRAG_THRESHOLD then
			self._gsDragPending = false
			local selection = getSelectedRows(self.listPanel)
			local rowSelected = isRowSelected(self.listPanel, self.itemData.fullType)
			local multiDrag = #selection > 1 and self.itemData and rowSelected
			-- amount=0 = "todo el stock de este fullType" (misma convencion que
			-- el menu de clic derecho). Antes se mandaba amount=1 a fuego: al
			-- arrastrar una fila con varias unidades solo se retiraba 1. El
			-- usuario pide que arrastrar mueva todo por defecto, y que las
			-- cantidades parciales queden solo para las opciones del menu.
			if multiDrag then
				GlobalStorageSiK.TerminalWithdrawDrag.begin(self.itemData, 0, selection)
			else
				GlobalStorageSiK.TerminalWithdrawDrag.begin(self.itemData, 0)
			end
			return true
		end
		return false
	end
	row.onMouseMoveOutside = row.onMouseMove

	row.onMouseUp = function(self, x, y)
		if GlobalStorageSiK.TerminalWithdrawDrag.isActive() then
			return false
		end
		if self._gsDragPending and self.listPanel then
			self._gsDragPending = false
			handleRowClick(self.listPanel, self)
			return true
		end
		return false
	end

	row.onMouseDoubleClick = function(self, x, y)
		if self.itemData and self.terminal then
			withdrawRowWithActiveTarget(self.terminal, self.itemData, 1)
			return true
		end
		return false
	end

	row.onRightMouseUp = function(self, x, y)
		if self.itemData and self.listPanel and self.terminal then
			if not isRowSelected(self.listPanel, self.itemData.fullType) then
				selectSingleRow(self.listPanel, self.itemData.fullType, self.rowIndex)
			end
			openItemContextMenu(self.listPanel, self.terminal, self.itemData)
		end
		return true
	end

	return row
end

--- Actualiza fila con datos de ítem.
---@param row ISPanel
---@param data table|nil
local function updateItemRow(row, data)
	row.itemData = data
	row._gsZoneLabel = data and resolveZoneLabel(row.terminal, data) or nil
end

---@param panel ISPanel
local function bindItemRowIndex(row, data, panel, dataIndex)
	updateItemRow(row, data)
	row.rowIndex = dataIndex
	if dataIndex then
		return
	end
	row.rowIndex = nil
	if not data or not panel._lastItems then
		return
	end
	for i = 1, #panel._lastItems do
		local item = panel._lastItems[i]
		if item == data or (data.fullType and item.fullType == data.fullType) then
			row.rowIndex = i
			break
		end
	end
end

--- Actualiza las filas visibles de la lista virtual SiK UI.
---@param listPanel ISPanel
function GlobalStorageSiK.TerminalItems.updateVirtualRows(listPanel)
	local scroll = listPanel and listPanel.itemScroll
	if scroll and scroll.refreshItems then
		scroll:refreshItems()
	end
end

--- Cabecera de columnas ordenables.
---@param panel ISPanel
---@param terminal GS_TerminalUI
local function ensureColumnHeader(panel, terminal)
	if panel.columnHeader then
		return
	end
	panel.columnHeader = ISPanel:new(0, 0, panel.width, HEADER_H)
	panel.columnHeader:initialise()
	panel.columnHeader.drawBackground = false
	panel.columnHeader.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.columnHeader.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	panel.columnHeader.prerender = function(self)
		ISPanel.prerender(self)
		local parent = self.parentPanel
		local sortKey = parent and parent.itemsSortKey or "displayName"
		local asc = parent and parent.itemsSortAsc ~= false
		GlobalStorageSiK.SiK_UI.Table.drawHeader(
			self, ITEM_TABLE_COLUMNS, sortKey, asc, 2, UIFont.Small, ITEM_TABLE_OPTIONS)
	end
	panel.columnHeader.parentPanel = panel
	panel.columnHeader.terminal = terminal
	panel.columnHeader.onMouseUp = function(self, x, y)
		local parent = self.parentPanel
		if not parent then
			return false
		end
		local layout = GlobalStorageSiK.SiK_UI.Table.resolveColumns(
			self.width, ITEM_TABLE_COLUMNS, ITEM_TABLE_OPTIONS)
		local column = GlobalStorageSiK.SiK_UI.Table.columnAtX(layout, x)
		parent.itemsSortKey = column and column.key or "displayName"
		if parent.itemsSortKey == (parent._lastSortKey or "") then
			parent.itemsSortAsc = not parent.itemsSortAsc
		else
			parent.itemsSortAsc = true
		end
		parent._lastSortKey = parent.itemsSortKey
		parent._itemsScrollOffset = 0
		if self.terminal and self.terminal.refreshItemsTab then
			self.terminal:refreshItemsTab()
		elseif self.terminal then
			GlobalStorageSiK.TerminalItems.refresh(parent, self.terminal, parent._itemsCatalog or parent._lastItems or {})
		end
		return true
	end
	panel:addChild(panel.columnHeader)
end

--- Crea la lista virtual propia SiK UI del Almacén.
---@param panel ISPanel
---@param terminal GS_TerminalUI
local function disposeItemScroll(panel)
	if not panel or not panel.itemScroll then
		return
	end
	panel:removeChild(panel.itemScroll)
	if panel.itemScroll.removeFromUIManager then
		panel.itemScroll:removeFromUIManager()
	end
	if panel.itemScroll.destroy then
		panel.itemScroll:destroy()
	end
	panel.itemScroll = nil
end

local function ensureItemScroll(panel, terminal)
	if panel.itemScroll and panel.itemScroll._gsScrollMode == "sik_virtual" then
		return
	end
	disposeItemScroll(panel)

	local listGap = GlobalStorageSiK.TerminalScroll.listBottomGap()
	local scrollH = math.max(120, (panel.height or 200) - HEADER_H - listGap - 4)
	local scrollBarW = GlobalStorageSiK.SiK_UI.scrollBarWidth()
	local itemW = math.max(120, (panel.width or 200) - scrollBarW - 8)

	local scroll = GlobalStorageSiK.SiK_UI.Table.createVirtual(
		panel, 0, HEADER_H + 2, panel.width, scrollH, ROW_H, 0,
		ITEM_TABLE_COLUMNS, nil, nil, ITEM_TABLE_OPTIONS)
	scroll._gsScrollBarGap = 12
	scroll._gsBarRightPad = 6
	panel.itemScroll = scroll
	scroll:setOnCreateItem(function()
		local row = createItemRow(scroll, panel, terminal)
		row:setWidth(itemW)
		return row
	end)
	scroll:setOnUpdateItem(function(row, data, dataIndex)
		bindItemRowIndex(row, data, panel, dataIndex)
	end)
	GlobalStorageSiK.TerminalScroll.bindScrollEvents(scroll, function()
		panel._itemsScrollOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(scroll)
		scroll:refreshItems()
	end)
end

--- Lista opciones de depósito (jugador + contenedores cercanos).
---@param player IsoPlayer|nil
---@return table[]
function GlobalStorageSiK.TerminalItems.buildDepositSources(player)
	return GlobalStorageSiK.DepositSources.buildList(player)
end

--- Rellena combo de origen de depósito.
---@param combo ISComboBox
---@param player IsoPlayer|nil
function GlobalStorageSiK.TerminalItems.fillDepositCombo(combo, player)
	if not combo then
		return
	end
	combo:clear()
	local ok, sources = pcall(GlobalStorageSiK.TerminalItems.buildDepositSources, player)
	combo.depositSources = ok and sources or {}
	for i = 1, #combo.depositSources do
		combo:addOption(combo.depositSources[i].label)
	end
	combo.selected = 1
end

--- Obtiene índice de opción de depósito (1-based).
---@param combo ISComboBox
---@return number sourceIndex
function GlobalStorageSiK.TerminalItems.getDepositSelection(combo)
	if not combo then
		return 1
	end
	return combo.selected or 1
end

--- Fuerza la actualización de filas visibles en la lista SiK UI.
---@param scroll ISUIElement|nil
local function forceVirtualListRefresh(scroll)
	if not scroll or scroll._gsScrollMode ~= "sik_virtual" or not scroll.refreshItems then
		return
	end
	scroll:refreshItems()
end

--- Construye o refresca el scroll de ítems.
---@param panel ISPanel
---@param terminal GS_TerminalUI
---@param items table[]
function GlobalStorageSiK.TerminalItems.refresh(panel, terminal, items)
	if not panel then
		return
	end

	items = items or {}
	panel.itemsSortKey = panel.itemsSortKey or "displayName"
	panel.itemsSortAsc = panel.itemsSortAsc ~= false
	panel._selectedKeys = panel._selectedKeys or {}
	items = sortRows(items, panel.itemsSortKey, panel.itemsSortAsc, terminal)
	-- BUG REAL (Shift+Click seleccionaba rango incorrecto/inconsistente,
	-- reportado 2026-08-16): _lastItems se asignaba ANTES de ordenar, con la
	-- referencia SIN ORDENAR - pero sortRows() copia a una tabla NUEVA y
	-- distinta, que es la que de verdad se manda a la lista visual
	-- (setDataSource mas abajo). Toda la logica de seleccion (findItemIndex,
	-- selectRangeTo, bindItemRowIndex) buscaba posiciones en _lastItems, asi
	-- que operaba sobre un orden DISTINTO al que el jugador veia en pantalla
	-- - un indice de fila visual no correspondia al mismo indice en la lista
	-- sin ordenar, dando rangos de Shift+Click aparentemente aleatorios
	-- salvo que ambos ordenes coincidieran por casualidad. Fix: asignar
	-- _lastItems DESPUES de ordenar, con la MISMA tabla que se muestra.
	panel._lastItems = items

	ensureColumnHeader(panel, terminal)
	ensureItemScroll(panel, terminal)

	if panel.columnHeader then
		panel.columnHeader:setWidth(panel.width)
	end

        if #items == 0 then
		if panel.itemScroll and panel.itemScroll.setDataSource then
			panel.itemScroll:setDataSource({}, false)
			panel._itemsScrollOffset = 0
		end
                if panel.emptyLbl then
			panel.emptyLbl:setVisible(true)
		else
			local _epal = GlobalStorageSiK.SiK_UI.PALETTE
			panel.emptyLbl = ISLabel:new(10, HEADER_H + 8, FONT_HGT_SMALL, T("IGUI_GS_NoItems"), _epal.textMuted[1], _epal.textMuted[2], _epal.textMuted[3], 1, UIFont.Small, true)
			panel.emptyLbl:initialise()
			panel:addChild(panel.emptyLbl)
		end
		if panel.itemScroll then
			panel.itemScroll:setVisible(false)
		end
	else
		if panel.emptyLbl then
			panel.emptyLbl:setVisible(false)
		end
		if panel.itemScroll then
			local listGap = GlobalStorageSiK.TerminalScroll.listBottomGap()
			local scrollH = math.max(120, panel.height - HEADER_H - listGap - 4)
			local savedOffset = panel._itemsScrollOffset
				or GlobalStorageSiK.TerminalScroll.getScrollOffset(panel.itemScroll)
			panel.itemScroll:setX(0)
			panel.itemScroll:setY(HEADER_H + 2)
			panel.itemScroll:setWidth(panel.width)
			panel.itemScroll:setHeight(scrollH)
			panel.itemScroll:setVisible(true)
			panel.itemScroll:setDataSource(items, true)
			GlobalStorageSiK.TerminalScroll.setScrollOffset(panel.itemScroll, savedOffset)
			forceVirtualListRefresh(panel.itemScroll)
			GlobalStorageSiK.TerminalScroll.ensureScrollBars(panel.itemScroll)
			GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(
				panel.itemScroll, #items * ROW_H + 4 > scrollH + 2)
			panel._itemsScrollOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(panel.itemScroll)
		end
	end
end

--- Solo geometría de la lista de ítems (resize); sin reconstruir datos.
---@param panel ISPanel|nil
---@param terminal GS_TerminalUI|nil
function GlobalStorageSiK.TerminalItems.syncLayout(panel, terminal)
	if not panel then
		return
	end
	ensureColumnHeader(panel, terminal)
	if panel.columnHeader then
		panel.columnHeader:setWidth(panel.width)
	end
	if not panel.itemScroll then
		ensureItemScroll(panel, terminal)
	end
	if not panel.itemScroll then
		return
	end
	local items = panel._lastItems or {}
	local listGap = GlobalStorageSiK.TerminalScroll.listBottomGap()
	local scrollH = math.max(120, panel.height - HEADER_H - listGap - 4)
	local savedOffset = panel._itemsScrollOffset
		or GlobalStorageSiK.TerminalScroll.getScrollOffset(panel.itemScroll)
	panel.itemScroll:setX(0)
	panel.itemScroll:setY(HEADER_H + 2)
	panel.itemScroll:setWidth(panel.width)
	panel.itemScroll:setHeight(scrollH)
	panel.itemScroll:setVisible(#items > 0)
	local scrollBarW = GlobalStorageSiK.SiK_UI.scrollBarWidth()
	local itemW = math.max(120, panel.width - scrollBarW - 8)
	panel.itemScroll:setConfig(ROW_H, 0)
	if panel.itemScroll.itemPool then
		for _, row in ipairs(panel.itemScroll.itemPool) do
			if row and row.setWidth then
				row:setWidth(itemW)
			end
		end
	end
	panel.itemScroll:setDataSource(items, true)
	GlobalStorageSiK.TerminalScroll.setScrollOffset(panel.itemScroll, savedOffset)
	forceVirtualListRefresh(panel.itemScroll)
	GlobalStorageSiK.TerminalScroll.ensureScrollBars(panel.itemScroll)
	GlobalStorageSiK.TerminalScroll.setScrollBarsVisible(
		panel.itemScroll, #items * ROW_H + 4 > scrollH + 2)
	panel._itemsScrollOffset = GlobalStorageSiK.TerminalScroll.getScrollOffset(panel.itemScroll)
end

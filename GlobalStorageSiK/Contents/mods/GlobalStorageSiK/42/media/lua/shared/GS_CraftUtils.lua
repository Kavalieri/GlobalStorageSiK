--[[
	GlobalStorageSiK - Utilidades de craft (mesa, recetas aprendidas)
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Detección de mesa segura en cliente y servidor dedicado.
]]

require "GS_Sandbox"
require "GS_Log"

GlobalStorageSiK.CraftUtils = {}

--- Resuelve un CraftRecipe por nombre probando variantes de módulo.
--- La UI de crafteo vanilla encuentra la receta por iteración de objeto
--- (ISHandcraftAction.craftRecipe), no por nombre — por eso el crafteo
--- vanilla funciona aunque sm:getCraftRecipe(nombreSinCualificar) devuelva
--- nil para recetas declaradas fuera del módulo Base.
---@param sm ScriptManager|nil
---@param recipeName string
---@return CraftRecipe|nil
local function resolveCraftRecipe(sm, recipeName)
	if not sm or not sm.getCraftRecipe or not recipeName then
		return nil
	end
	local candidates = {
		recipeName,
		"GlobalStorageSiK." .. recipeName,
		"GlobalStorageSiK:" .. recipeName,
	}
	for i = 1, #candidates do
		local ok, recipe = pcall(function() return sm:getCraftRecipe(candidates[i]) end)
		if ok and recipe then
			return recipe
		end
	end
	return nil
end

--- Vuelca el contenido de getKnownRecipes() a texto (solo DebugMode) para
--- diagnosticar el formato real de clave que usa B42 internamente.
---@param known any|nil
---@return string
local function dumpKnownRecipes(known)
	if not known then
		return "(nil)"
	end
	local ok, list = pcall(function()
		local out = {}
		if known.iterator then
			local it = known:iterator()
			while it:hasNext() do
				out[#out + 1] = tostring(it:next())
			end
		elseif known.size and known.get then
			for i = 0, known:size() - 1 do
				out[#out + 1] = tostring(known:get(i))
			end
		end
		return out
	end)
	if not ok or not list or #list == 0 then
		return "(vacio o no iterable)"
	end
	return table.concat(list, ", ")
end

--- Comprueba si el jugador conoce una receta por nombre (craftRecipe B42).
---@param player IsoPlayer
---@param recipeName string
---@return boolean
function GlobalStorageSiK.CraftUtils.knowsRecipe(player, recipeName)
	if not player or not recipeName then
		return false
	end
	if not GlobalStorageSiK.Sandbox.requireRecipeBooks() then
		return true
	end

	-- Diagnostico: por que la ventana de instalar terminal a veces no
	-- detecta la receta aprendida via revista aunque el jugador la haya
	-- leido. Registra cada paso (resolucion de craftRecipe, resultado de
	-- isRecipeKnown/isRecipeActuallyKnown, contenido real de
	-- getKnownRecipes()) para localizar en cual de los 3 metodos falla.
	local debugOn = GlobalStorageSiK.Sandbox.debugMode()

	local sm = getScriptManager and getScriptManager() or nil
	local craftRecipe = resolveCraftRecipe(sm, recipeName)
	if debugOn then
		GlobalStorageSiK.Log.debug("CraftUtils", "knowsRecipe | recipeName=" .. tostring(recipeName)
			.. " craftRecipeResolved=" .. tostring(craftRecipe ~= nil))
	end

	if craftRecipe then
		if player.isRecipeKnown then
			local ok, known = pcall(function()
				return player:isRecipeKnown(craftRecipe, true)
			end)
			if debugOn then
				GlobalStorageSiK.Log.debug("CraftUtils", "knowsRecipe | isRecipeKnown ok=" .. tostring(ok) .. " known=" .. tostring(known))
			end
			if ok and known then
				return true
			end
		end
		if player.isRecipeActuallyKnown then
			local ok, known = pcall(function()
				return player:isRecipeActuallyKnown(craftRecipe)
			end)
			if debugOn then
				GlobalStorageSiK.Log.debug("CraftUtils", "knowsRecipe | isRecipeActuallyKnown ok=" .. tostring(ok) .. " known=" .. tostring(known))
			end
			if ok and known then
				return true
			end
		end
	end

	if player.getKnownRecipes then
		local known = player:getKnownRecipes()
		if debugOn then
			GlobalStorageSiK.Log.debug("CraftUtils", "knowsRecipe | getKnownRecipes contents: " .. dumpKnownRecipes(known))
		end
		if known and known.contains then
			local variants = {
				recipeName,
				"GlobalStorageSiK:" .. recipeName,
			}
			for i = 1, #variants do
				local ok, contains = pcall(function() return known:contains(variants[i]) end)
				if debugOn then
					GlobalStorageSiK.Log.debug("CraftUtils", "knowsRecipe | contains(\"" .. variants[i] .. "\") ok=" .. tostring(ok) .. " => " .. tostring(contains))
				end
				if ok and contains then
					return true
				end
			end
		end
	end

	if debugOn then
		GlobalStorageSiK.Log.debug("CraftUtils", "knowsRecipe | RESULT: NOT known (todos los metodos fallaron)")
	end
	return false
end

--- Comprueba receta aprendida (ignora sandbox RequireRecipeBooks del core).
---@param player IsoPlayer
---@param recipeName string
---@return boolean
function GlobalStorageSiK.CraftUtils.knowsRecipeStrict(player, recipeName)
	if not player or not recipeName then
		return false
	end

	local sm = getScriptManager and getScriptManager() or nil
	local craftRecipe = resolveCraftRecipe(sm, recipeName)
	if craftRecipe then
		if player.isRecipeKnown then
			local ok, known = pcall(function()
				return player:isRecipeKnown(craftRecipe, true)
			end)
			if ok and known then
				return true
			end
		end
		if player.isRecipeActuallyKnown then
			local ok, known = pcall(function()
				return player:isRecipeActuallyKnown(craftRecipe)
			end)
			if ok and known then
				return true
			end
		end
	end

	if player.getKnownRecipes then
		local known = player:getKnownRecipes()
		if known and known.contains then
			local variants = {
				recipeName,
				"GlobalStorageSiK:" .. recipeName,
			}
			for i = 1, #variants do
				if known:contains(variants[i]) then
					return true
				end
			end
		end
	end

	return false
end

--- Recetas que enseña cada manual GS via LearnedRecipes - copiado a mano de
--- globalstoragesik_items.txt (mantener en sincronia si cambia alguna
--- lista). Se probo leer esto dinamicamente desde el script item
--- (sm:getItem(fullType):getLearnedRecipes()) pero ese metodo no existe en
--- el script item - solo en el InventoryItem vivo que lee ISReadABook.lua -
--- asi que la consulta no devolvia nada nunca. Lista fija: mas fiable.
local MANUAL_RECIPES = {
	["GlobalStorageSiK.GS_Manual_TerminalUnit"] = {
		"Build GS Terminal Reader",
		"Build GS Reader Casing",
		"Build GS Reader Circuit Board",
		"Build GS Reader Antenna",
	},
	["GlobalStorageSiK.GS_Manual_PCBuild"] = {
		"Build GS Desktop Computer",
		"Build GS PC Tower",
		"Build GS Motherboard",
		"Build GS IO Controller",
		"Build GS Keyboard",
	},
	["GlobalStorageSiK.GS_Manual_DiskPrograms"] = {
		"Program GS Uninstall Disk",
	},
}

--- BUG VANILLA confirmado (no nuestro, no hay fix de motor posible): leer un
--- item de literatura marca su fullType como "ya leido para siempre" en
--- character:getAlreadyReadBook() - un set POR TIPO, no por instancia. Si
--- una actualizacion del mod AÑADE una receta nueva al LearnedRecipes de un
--- manual que el jugador ya leyo alguna vez (aunque sea con una version
--- anterior de ese mismo manual), vanilla nunca vuelve a conceder recetas de
--- ese fullType - ni siquiera leyendo una copia totalmente nueva y sin
--- estrenar, porque el check es "¿ya lei ESTE TIPO de item?", no "¿ya lei
--- ESTA copia?". Confirmado en pruebas: releer una copia nueva sigue
--- ofreciendo "Releer" y no concede nada.
--- Este fix concede a mano, via player:learnRecipe(), cualquier receta de
--- MANUAL_RECIPES que el jugador aun no conozca de un manual que ya tiene
--- marcado como leido - SIN exigir que vuelva a leer nada. Llamar SOLO
--- desde contexto autoritativo (servidor / SP real) - nunca desde codigo
--- que tambien corre en el cliente puro, ya que aprender una receta es una
--- mutacion del personaje.
---@param player IsoPlayer|nil
--- Intenta player:learnRecipe(nombre) probando variantes de modulo, igual
--- que resolveCraftRecipe() de mas arriba - learnRecipe() DEVUELVE un
--- booleano de exito real (confirmado en el propio Lua vanilla,
--- ISRadioInteractions.lua: "local learned = player:learnRecipe(recipe)"),
--- asi que hay que comprobarlo: que la llamada no lance excepcion NO
--- significa que la receta se aprendiera de verdad. Sin esto, el fix
--- registraba "concedida" aunque learnRecipe hubiera devuelto false por no
--- encontrar la receta con el nombre sin cualificar - el mismo problema de
--- resolucion de nombres de modulo ya documentado en resolveCraftRecipe().
--- Ejecuta fn() protegido: devuelve el resultado si no lanza excepcion, nil
--- si falla. BUG REAL encontrado en pruebas (v1.2.105-107): esta funcion se
--- USABA en ensureManualRecipesGranted() sin existir en ningun sitio del
--- fichero - "Object tried to call nil in ensureManualRecipesGranted" al
--- ejecutarla a mano desde la consola de debug. Explica por que la funcion
--- nunca imprimia NADA (ni siquiera la linea "ya conocida"/"FALLO"): petaba
--- en la primera linea que la llamaba, silenciosamente, tanto desde
--- OnCreatePlayer como desde handleOpenTerminal (ninguno de los dos
--- envolvia la llamada en pcall).
---@param fn function
---@return any
local function safeGet(fn)
	local ok, result = pcall(fn)
	if ok then
		return result
	end
	return nil
end

---@param player IsoPlayer
---@param recipeName string
---@return boolean
local function tryLearnRecipe(player, recipeName)
	local candidates = {
		recipeName,
		"GlobalStorageSiK." .. recipeName,
		"GlobalStorageSiK:" .. recipeName,
	}
	for i = 1, #candidates do
		local ok, learned = pcall(function() return player:learnRecipe(candidates[i]) end)
		if ok and learned then
			return true
		end
	end
	-- Ultimo recurso si learnRecipe() devolvio false con las 3 variantes:
	-- añadir directamente al set de getKnownRecipes(), el mismo objeto que
	-- knowsRecipe()/knowsRecipeStrict() ya consultan mas arriba como uno de
	-- sus metodos de comprobacion - si es la MISMA referencia viva que
	-- mantiene el personaje (no una copia), esto basta para que el resto del
	-- juego (y nuestras propias comprobaciones) lo reconozcan como conocido.
	if player.getKnownRecipes then
		local ok, known = pcall(function() return player:getKnownRecipes() end)
		if ok and known and known.add then
			for i = 1, #candidates do
				local addOk = pcall(function() known:add(candidates[i]) end)
				if addOk then
					local checkOk, contains = pcall(function() return known:contains(candidates[i]) end)
					if checkOk and contains then
						return true
					end
				end
			end
		end
	end
	return false
end

function GlobalStorageSiK.CraftUtils.ensureManualRecipesGranted(player)
	local debugOn = GlobalStorageSiK.Sandbox.debugMode()
	-- Linea de entrada INCONDICIONAL (no depende de que haya algo que
	-- conceder): confirma que la funcion se invoco de verdad en este punto -
	-- sin esto, "no aparece ninguna linea de CraftUtils" es ambiguo entre
	-- "la funcion no corrio" y "corrio pero no encontro nada que hacer".
	if debugOn then
		GlobalStorageSiK.Log.debug("CraftUtils", "ensureManualRecipesGranted.entry",
			"player=" .. tostring(player and player.getUsername and player:getUsername() or player))
	end
	if not player or not player.getAlreadyReadBook or not player.learnRecipe then
		if debugOn then
			GlobalStorageSiK.Log.debug("CraftUtils", "ensureManualRecipesGranted.exit",
				"player invalido o sin getAlreadyReadBook/learnRecipe")
		end
		return
	end
	local alreadyRead = safeGet(function() return player:getAlreadyReadBook() end)
	if not alreadyRead or not alreadyRead.contains then
		if debugOn then
			GlobalStorageSiK.Log.debug("CraftUtils", "ensureManualRecipesGranted.exit",
				"getAlreadyReadBook() devolvio nil o sin metodo contains")
		end
		return
	end
	local grantedAny = false
	for fullType, recipeList in pairs(MANUAL_RECIPES) do
		local hasRead = safeGet(function() return alreadyRead:contains(fullType) end)
		if debugOn then
			GlobalStorageSiK.Log.debug("CraftUtils", "ensureManualRecipesGranted.manual",
				fullType .. " hasRead=" .. tostring(hasRead))
		end
		if hasRead then
			for i = 1, #recipeList do
				local recipeName = recipeList[i]
				local known = GlobalStorageSiK.CraftUtils.knowsRecipeStrict(player, recipeName)
				if not known then
					local granted = tryLearnRecipe(player, recipeName)
					if granted then
						grantedAny = true
					end
					if debugOn then
						GlobalStorageSiK.Log.debug("CraftUtils", "ensureManualRecipesGranted",
							(granted and "concedida " or "FALLO al conceder ") .. tostring(recipeName)
							.. " (manual " .. fullType .. " ya leido)")
					end
				elseif debugOn then
					GlobalStorageSiK.Log.debug("CraftUtils", "ensureManualRecipesGranted.recipe",
						tostring(recipeName) .. " ya conocida, nada que hacer")
				end
			end
		end
	end
	-- Paso que faltaba (encontrado leyendo el vanilla real): learnRecipe()/
	-- getKnownRecipes():add() cambian el estado autoritativo, pero SIN esta
	-- sincronizacion la interfaz de crafteo sigue mostrando "Receta No
	-- Aprendida" con la receta ya concedida de verdad. Vanilla SIEMPRE hace
	-- esta llamada tras conceder una receta fuera del flujo normal de lectura
	-- - ISReadABook.lua:374 (`sendSyncPlayerFields(self.character,
	-- 0x00000007)`, que incluye PF_Recipes) al terminar de leer un libro, e
	-- ISResearchRecipe.lua:85 (`sendSyncPlayerFields(self.character,
	-- 0x00000001)`, comentado "--PF_Recipes") tras investigar una receta.
	-- 0x00000001 = PF_Recipes en solitario (confirmado por ese comentario);
	-- suficiente aqui, no tocamos traits ni alreadyReadBook.
	if grantedAny and sendSyncPlayerFields then
		local ok = pcall(sendSyncPlayerFields, player, 0x00000001)
		if debugOn then
			GlobalStorageSiK.Log.debug("CraftUtils", "ensureManualRecipesGranted.sync",
				"sendSyncPlayerFields(PF_Recipes) ok=" .. tostring(ok))
		end
	end
end

--- Radio de búsqueda de mesa (casillas Manhattan; alineado con HandcraftLogic B42).
local CRAFT_SURFACE_RADIUS = 2

--- Umbral mínimo de luz para craft sin tag CanBeDoneInDark (aprox. vanilla B42).
local CRAFT_LIGHT_MIN = 0.19

--- Indica si un valor de propiedad de tile es afirmativo.
---@param props SpriteProperties|nil
---@param key string
---@return boolean
local function propValTruthy(props, key)
	if not props or not props.Val then
		return false
	end
	local valOk, val = pcall(function()
		return props:Val(key)
	end)
	if not valOk or val == nil then
		return false
	end
	local s = tostring(val)
	return s ~= "" and s ~= "false" and s ~= "0"
end

--- Indica si un nombre de sprite sugiere superficie de craft.
---@param spriteName string
---@return boolean
local function spriteNameIsCraftSurface(spriteName)
	if not spriteName or spriteName == "" then
		return false
	end
	local name = string.lower(spriteName)
	if string.find(name, "workbench", 1, true)
		or string.find(name, "furniture_tables", 1, true)
		or string.find(name, "furniture_table", 1, true)
		or string.find(name, "furniture_carpentry", 1, true)
		or string.find(name, "carpentry_", 1, true)
		or string.find(name, "counter", 1, true)
		or string.find(name, "desk", 1, true)
		or string.find(name, "branch_table", 1, true)
		or string.find(name, "picnic", 1, true)
		or string.find(name, "stool", 1, true)
		or string.find(name, "table", 1, true) then
		return true
	end
	return false
end

--- Comprueba flag de superficie de craft en propiedades de sprite (B42).
---@param props SpriteProperties|nil
---@return boolean
local function propsIsCraftSurface(props)
	if not props then
		return false
	end
	if propValTruthy(props, "GenericCraftingSurface") then
		return true
	end
	if props.Is then
		local flags = {
			"GenericCraftingSurface",
			"IsTable",
			"IsCounter",
			"Workbench",
			"CraftSurface",
		}
		for i = 1, #flags do
			local flagOk, isSet = pcall(function()
				return props:Is(flags[i])
			end)
			if flagOk and isSet then
				return true
			end
		end
	end
	if propValTruthy(props, "Workbench") or propValTruthy(props, "IsTable") then
		return true
	end
	-- Baldosa con altura de superficie (mesas de carpintería, contadores…).
	if propValTruthy(props, "Surface") then
		return true
	end
	return false
end

--- Indica si un sprite/objeto cuenta como superficie de craft (sin APIs frágiles en servidor).
---@param obj IsoObject|nil
---@return boolean
local function objectIsCraftSurface(obj)
	if not obj then
		return false
	end
	if isServer and isServer() then
		return false
	end

	local ok, result = pcall(function()
		if not obj.getSprite then
			return false
		end
		local sprite = obj:getSprite()
		if not sprite then
			return false
		end

		local onDedicated = isServer and isServer() or false
		if not onDedicated and sprite.getProperties then
			local props = sprite:getProperties()
			if propsIsCraftSurface(props) then
				return true
			end
		end

		if sprite.getName then
			local nameOk, spriteName = pcall(function() return sprite:getName() end)
			if nameOk and spriteNameIsCraftSurface(spriteName) then
				return true
			end
		end

		return false
	end)

	return ok and result == true
end

--- Comprueba si una baldosa tiene mesa/superficie de craft.
---@param square IsoGridSquare|nil
---@return boolean
local function squareHasCraftSurface(square)
	if not square or not square.getObjects then
		return false
	end
	local ok, result = pcall(function()
		local objects = square:getObjects()
		if not objects then
			return false
		end
		for i = 0, objects:size() - 1 do
			if objectIsCraftSurface(objects:get(i)) then
				return true
			end
		end
		return false
	end)
	return ok and result == true
end

--- Busca superficie de craft con HandcraftLogic (misma lógica que elaboración vanilla).
---@param player IsoPlayer
---@param radius number
---@return IsoObject|nil
local function findVanillaCraftSurface(player, radius)
	if not player or not HandcraftLogic or not HandcraftLogic.new then
		return nil
	end
	local ok, surface = pcall(function()
		local logic = HandcraftLogic.new(player, nil, nil)
		if logic and logic.findCraftSurface then
			return logic:findCraftSurface(player, radius)
		end
		return nil
	end)
	if ok and surface then
		return surface
	end
	return nil
end

--- Comprueba casillas alrededor del jugador buscando superficie de craft.
---@param square IsoGridSquare|nil
---@param radius number|nil
---@return boolean
local function nearSquareHasCraftSurface(square, radius)
	if not square then
		return false
	end
	radius = radius or CRAFT_SURFACE_RADIUS
	if squareHasCraftSurface(square) then
		return true
	end
	local cell = square.getCell and square:getCell() or nil
	if not cell or not cell.getGridSquare then
		return false
	end
	local x, y, z = square:getX(), square:getY(), square:getZ()
	for dx = -radius, radius do
		for dy = -radius, radius do
			if dx ~= 0 or dy ~= 0 then
				local adj = cell:getGridSquare(x + dx, y + dy, z)
				if squareHasCraftSurface(adj) then
					return true
				end
			end
		end
	end
	return false
end

--- Comprueba si el jugador está junto a una mesa de trabajo / superficie válida.
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.CraftUtils.isNearWorkbench(player)
	if not player then
		return false
	end
	if not GlobalStorageSiK.Sandbox.requireWorkbench() then
		return true
	end
	-- Servidor dedicado: sin APIs de sprite; el cliente valida la mesa.
	if isServer and isServer() then
		return false
	end

	local ok, result = pcall(function()
		if findVanillaCraftSurface(player, CRAFT_SURFACE_RADIUS) then
			return true
		end
		local square = player.getSquare and player:getSquare() or nil
		return nearSquareHasCraftSurface(square, CRAFT_SURFACE_RADIUS)
	end)

	if not ok then
		return false
	end
	return result == true
end

--- Indica si una craftRecipe B42 permite elaborar a oscuras.
---@param recipeName string|nil
---@return boolean
function GlobalStorageSiK.CraftUtils.recipeAllowsDarkCraft(recipeName)
	if not recipeName then
		return false
	end
	local sm = getScriptManager and getScriptManager() or nil
	local craftRecipe = resolveCraftRecipe(sm, recipeName)
	if not craftRecipe or not craftRecipe.getTags then
		return false
	end
	local ok, tags = pcall(function()
		return craftRecipe:getTags()
	end)
	if not ok or not tags then
		return false
	end
	for i = 0, tags:size() - 1 do
		if tags:get(i) == "CanBeDoneInDark" then
			return true
		end
	end
	return false
end

--- Nivel de luz en la casilla del jugador (0–1 aprox.).
---@param player IsoPlayer|nil
---@return number
function GlobalStorageSiK.CraftUtils.getCraftLightLevel(player)
	if not player then
		return 0
	end
	local sq = player.getSquare and player:getSquare() or nil
	if not sq then
		return 0
	end
	if sq.getLightLevel and player.getPlayerNum then
		local ok, level = pcall(function()
			return sq:getLightLevel(player:getPlayerNum())
		end)
		if ok and level then
			return tonumber(level) or 0
		end
	end
	if player.getLightLevel then
		local ok, level = pcall(function()
			return player:getLightLevel()
		end)
		if ok and level then
			return tonumber(level) or 0
		end
	end
	return 1
end

--- Comprueba luz suficiente para craft (recetas eléctricas del mod exigen luz salvo CanBeDoneInDark).
---@param player IsoPlayer|nil
---@param recipeName string|nil
---@return boolean
function GlobalStorageSiK.CraftUtils.hasCraftLight(player, recipeName)
	if not player then
		return false
	end
	if GlobalStorageSiK.CraftUtils.recipeAllowsDarkCraft(recipeName) then
		return true
	end
	return GlobalStorageSiK.CraftUtils.getCraftLightLevel(player) >= CRAFT_LIGHT_MIN
end

--- Nivel actual de Electricidad del jugador.
---@param player IsoPlayer|nil
---@return number
function GlobalStorageSiK.CraftUtils.getElectricityLevel(player)
	if not player or not player.getPerkLevel or not Perks or not Perks.Electricity then
		return 0
	end
	return player:getPerkLevel(Perks.Electricity) or 0
end

--- Textura de icono de un perk (p. ej. Electricidad).
---@param perk any
---@return Texture|nil
function GlobalStorageSiK.CraftUtils.getPerkTexture(perk)
	if not perk then
		return nil
	end
	if PerkFactory and PerkFactory.getPerk then
		local def = PerkFactory.getPerk(perk)
		if def and def.getTexture then
			local ok, tex = pcall(function()
				return def:getTexture()
			end)
			if ok and tex then
				return tex
			end
		end
	end
	if Perks and perk == Perks.Electricity then
		local paths = {
			"media/ui/Skill_Icon_Electricity.png",
			"media/textures/Skill_Icon_Electricity.png",
		}
		for i = 1, #paths do
			local tex = getTexture(paths[i])
			if tex then
				return tex
			end
		end
	end
	return nil
end

--- Item real del soldador de electrónica GS - herramienta reutilizable
--- (mode:keep en recetas), obligatoria junto a un destornillador cualquiera
--- para todo crafteo de piezas/lector/PC del mod (nunca para instalar un
--- disquete: eso no es fabricar nada).
GlobalStorageSiK.CraftUtils.SOLDERING_IRON_TYPE = "GlobalStorageSiK.GS_SolderingIron"

--- Inventario del jugador + contenedores cercanos, usando EXACTAMENTE el
--- mismo mecanismo que el panel de crafteo vanilla B42
--- (ISHandCraftPanel:updateContainers llama a
--- ISInventoryPaneContextMenu.getContainers(player) - ver
--- media/lua/client/Entity/ISUI/CraftRecipe/ISHandCraftPanel.lua y
--- media/lua/client/ISUI/ISInventoryPaneContextMenu.lua en el juego base).
--- Esa función lee las "backpacks" ya resueltas por los paneles de
--- inventario/loot del propio jugador (getPlayerInventory/getPlayerLoot),
--- que el juego mantiene actualizados en segundo plano con lo que hay cerca
--- - no reinventamos radio ni lógica de detección propia, evita el
--- desajuste que teníamos antes (nuestro escaneo de baldosas propio no
--- coincidía con lo que el crafteo vanilla sí detectaba).
--- ISInventoryPaneContextMenu es una clase de CLIENTE (no existe en un
--- servidor dedicado sin UI, ni en un cliente MP puro sin panel de
--- inventario propio a mano) - si no está disponible, se cae a solo el
--- inventario del jugador.
---@param player IsoPlayer|nil
---@return ItemContainer[]
local function nearbyContainers(player)
	local list = {}
	local inv = player and player.getInventory and player:getInventory()
	if inv then
		list[#list + 1] = inv
	end
	if not player or not ISInventoryPaneContextMenu or not ISInventoryPaneContextMenu.getContainers then
		return list
	end
	local ok, containers = pcall(function()
		return ISInventoryPaneContextMenu.getContainers(player)
	end)
	if not ok or not containers then
		return list
	end
	for i = 0, containers:size() - 1 do
		local container = containers:get(i)
		if container and container ~= inv then
			list[#list + 1] = container
		end
	end
	return list
end

--- Comprueba si el jugador tiene un ítem de un tipo exacto en su inventario
--- o en un contenedor cercano (recursivo, cuenta lo que lleve dentro de
--- bolsas/cofres). No lo consume.
---@param player IsoPlayer|nil
---@param fullType string
---@return boolean
function GlobalStorageSiK.CraftUtils.hasItemType(player, fullType)
	if not player or not fullType then
		return false
	end
	local containers = nearbyContainers(player)
	for i = 1, #containers do
		local ok, count = pcall(function() return containers[i]:getItemCountRecurse(fullType) end)
		if ok and count and count > 0 then
			return true
		end
	end
	return false
end

--- Busca un ítem por fullType exacto en el inventario del jugador o en un
--- contenedor cercano (mismo alcance que hasItemType) y lo devuelve SIN
--- quitarlo de donde esté. Usar item:getContainer():Remove(item) para
--- consumirlo del contenedor real en el que se encontró, nunca asumir que
--- estaba en player:getInventory().
---@param player IsoPlayer|nil
---@param fullType string
---@return InventoryItem|nil
function GlobalStorageSiK.CraftUtils.findItemTypeNearby(player, fullType)
	if not player or not fullType then
		return nil
	end
	local containers = nearbyContainers(player)
	for i = 1, #containers do
		local ok, item = pcall(function() return containers[i]:FindAndReturn(fullType) end)
		if ok and item then
			return item
		end
	end
	return nil
end

---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.CraftUtils.hasSolderingIron(player)
	return GlobalStorageSiK.CraftUtils.hasItemType(player, GlobalStorageSiK.CraftUtils.SOLDERING_IRON_TYPE)
end

-- Set de fullTypes (minuscula) con el tag "screwdriver" (base:screwdriver),
-- construido una vez via API global de tags - igual que buildMetalSet() en
-- GS_Subcategories.lua. Evita llamar hasTag() sobre items vivos (Kahlua
-- "No implementation found" con items moddeados, ver memoria
-- kahlua_modded_items_subcategories).
local _screwdriverTypes = nil
local function buildScrewdriverSet()
	if _screwdriverTypes then return _screwdriverTypes end
	_screwdriverTypes = {}
	local sm = getScriptManager and getScriptManager()
	if not sm or not sm.getItemsTag then return _screwdriverTypes end
	local ok, items = pcall(function()
		return sm:getItemsTag(ItemTag.get(ResourceLocation.of("base:screwdriver")))
	end)
	if ok and items and items.size then
		for i = 0, items:size() - 1 do
			local si = items:get(i)
			local fn = si and si.getFullName and (select(2, pcall(function() return si:getFullName() end)))
			if fn then _screwdriverTypes[string.lower(fn)] = true end
		end
	end
	return _screwdriverTypes
end

--- Comprueba si el jugador lleva cualquier destornillador (tag vanilla
--- base:screwdriver) en el inventario o en un contenedor cercano, recursivo.
--- No lo consume. Compara por fullType sobre un set precalculado (nunca
--- hasTag() en items vivos).
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.CraftUtils.hasScrewdriver(player)
	local set = buildScrewdriverSet()
	local containers = nearbyContainers(player)
	for c = 1, #containers do
		local inv = containers[c]
		if inv.getAllEvalRecurse then
			local ok, items = pcall(function()
				return inv:getAllEvalRecurse(function() return true end)
			end)
			if ok and items then
				for i = 0, items:size() - 1 do
					local item = items:get(i)
					local ftOk, ft = pcall(function() return item:getFullType() end)
					if ftOk and ft and set[string.lower(ft)] then
						return true
					end
				end
			end
		end
	end
	return false
end

--- Textura de icono de ítem por fullType.
---@param fullType string|nil
---@return Texture|nil
function GlobalStorageSiK.CraftUtils.getItemIconTexture(fullType)
	if not fullType then
		return nil
	end
	if getItemTex then
		return getItemTex(fullType)
	end
	local script = getScriptManager() and getScriptManager():getItem(fullType) or nil
	if script and script.getNormalTexture then
		return script:getNormalTexture()
	end
	return nil
end

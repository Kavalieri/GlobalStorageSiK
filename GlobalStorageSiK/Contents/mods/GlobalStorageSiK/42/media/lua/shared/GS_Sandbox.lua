--[[
	GlobalStorageSiK - Lectura de sandbox options
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Acceso centralizado a SandboxVars para B42.
]]

require "GS_Config"

GlobalStorageSiK.Sandbox = {}

--- Sin ningun addon con tableta inalambrica instalado, NO hay acceso
--- inalambrico de ningun tipo - el core no anticipa ni preconfigura nada de
--- esa mecanica (rango, sandbox, valor por defecto util): es responsabilidad
--- exclusiva de cada addon, que se registra via
--- GlobalStorageSiK.TerminalAccess.registerWirelessProvider (ver
--- GS_TerminalAccess.getWirelessRangeForPlayer). 0 = ningun acceso sin
--- terminal fisico cerca, coherente con "el core no depende de futuros addons".
---@return number
function GlobalStorageSiK.Sandbox.getWirelessRange()
	return 0
end

--- Alias legacy.
---@return number
function GlobalStorageSiK.Sandbox.getNetworkRange()
	return GlobalStorageSiK.Sandbox.getWirelessRange()
end

--- Rango de proximidad al mueble terminal físico.
---@return number
function GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.TerminalProximityRange or 2
end

--- Rango de "cobertura" de una red: distancia horizontal (en baldosas) máxima
--- desde el terminal principal de una red (ver GS_TerminalRecord.getPrimaryAnchor,
--- el primero colocado salvo que se marque otro como principal) dentro de la
--- cual un terminal ADICIONAL se considera parte de esa misma cobertura y
--- puede vincularse a ella. Independiente del rango inalámbrico de la Tablet
--- (ese es para acceder SIN terminal físico cerca; esto es sobre terminales
--- físicos reales, disponible ya sin ningún addon).
---@return number
function GlobalStorageSiK.Sandbox.getTerminalNetworkRange()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.TerminalNetworkRange or 40
end

--- Límite de diferencia de altura (plantas, no baldosas Z crudas) para el
--- mismo chequeo de cobertura de arriba. 0 = sin límite (por defecto): un
--- terminal en la 5ª planta o en un sótano cuenta igual si está dentro del
--- rango horizontal, salvo que el jugador quiera restringir explícitamente
--- la cobertura a ciertas plantas.
---@return number
function GlobalStorageSiK.Sandbox.getTerminalNetworkHeight()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.TerminalNetworkHeight or 0
end

--- Comprueba si una coordenada candidata (nuevo terminal a instalar) está
--- dentro de la cobertura de red medida desde un ancla (normalmente
--- GS_TerminalRecord.getPrimaryAnchor de la red destino). Sin ancla (red sin
--- ningún terminal activo todavía) no hay nada de lo que estar "fuera de
--- rango", así que se permite.
---@param anchor table|nil { x, y, z }
---@param x number
---@param y number
---@param z number|nil
---@return boolean
function GlobalStorageSiK.Sandbox.isWithinNetworkRange(anchor, x, y, z)
	if not anchor or not anchor.x or not anchor.y then
		return true
	end
	local range = GlobalStorageSiK.Sandbox.getTerminalNetworkRange()
	local dx, dy = x - anchor.x, y - anchor.y
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist > range then
		return false
	end
	local heightLimit = GlobalStorageSiK.Sandbox.getTerminalNetworkHeight()
	if heightLimit and heightLimit > 0 then
		local dz = math.abs((z or 0) - (anchor.z or 0))
		if dz > heightLimit then
			return false
		end
	end
	return true
end

--- Indica si se exige terminal físico o tableta para abrir la UI.
--- Opcion de sandbox invertida (v1.2.110, a peticion del usuario, por
--- coherencia con el resto de casillas de la pestaña Debug: una casilla
--- MARCADA en Debug siempre activa un comportamiento especial, nunca
--- exige uno estricto). DebugSkipTerminalAccess por defecto en false =
--- comportamiento estricto normal (equivalente al antiguo
--- RequireTerminalAccess=true por defecto); marcarla en Debug SALTA la
--- exigencia. Esta funcion publica no cambia de nombre ni de sentido -
--- todo el resto del codigo que la llama sigue igual.
---@return boolean
function GlobalStorageSiK.Sandbox.requireTerminalAccess()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.DebugSkipTerminalAccess ~= true
end

--- Obtiene el máximo de nodos por red.
---@return number
function GlobalStorageSiK.Sandbox.getMaxNodes()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.MaxNodesPerNetwork or 128
end

--- Baldosas extra de histéresis al cerrar sesión de terminal.
---@return number
function GlobalStorageSiK.Sandbox.getAccessHysteresis()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.AccessHysteresisTiles or 1
end

--- Indica si la red requiere electricidad.
---@return boolean
function GlobalStorageSiK.Sandbox.requiresPower()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.RequirePower == true
end

--- Indica si la red debe restar combustible a un generador cercano activo
--- mientras funcione (nunca con la red electrica normal). Ver GS_FuelConsumption.lua.
---@return boolean
function GlobalStorageSiK.Sandbox.enableFuelConsumption()
	if not SandboxVars.GlobalStorageSiK then
		return false
	end
	return SandboxVars.GlobalStorageSiK.EnableFuelConsumption == true
end

--- Combustible consumido por hora de partida solo por tener la red activa
--- (antes de sumar el consumo por contenedor). Misma unidad que usa el
--- propio generador (getFuel()/getMaxFuel()), igual que la opcion vanilla
--- GeneratorFuelConsumption.
---@return number
function GlobalStorageSiK.Sandbox.fuelConsumptionBase()
	if not SandboxVars.GlobalStorageSiK then
		return 0.05
	end
	return SandboxVars.GlobalStorageSiK.FuelConsumptionBase or 0.05
end

--- Combustible extra por hora de partida, multiplicado por el numero de
--- contenedores/nodos registrados en la red.
---@return number
function GlobalStorageSiK.Sandbox.fuelConsumptionPerContainer()
	if not SandboxVars.GlobalStorageSiK then
		return 0.01
	end
	return SandboxVars.GlobalStorageSiK.FuelConsumptionPerContainer or 0.01
end

--- [WIP] En vez de usar solo el generador mas cercano, busca todos los
--- generadores/baterias del mismo edificio que el terminal y reparte el
--- consumo entre todos. Requiere enableFuelConsumption() tambien activo.
---@return boolean
function GlobalStorageSiK.Sandbox.enableGeneratorGrid()
	if not SandboxVars.GlobalStorageSiK then
		return false
	end
	return SandboxVars.GlobalStorageSiK.EnableGeneratorGrid == true
end

--- [WIP] Intenta incluir tambien baterias de mods solares tipo ISA/PSR
--- (best-effort, via los mismos campos de ModData que usan ambos mods -
--- ver GS_Power.lua). Requiere enableFuelConsumption() tambien activo.
---@return boolean
function GlobalStorageSiK.Sandbox.enableBatteryCompat()
	if not SandboxVars.GlobalStorageSiK then
		return false
	end
	return SandboxVars.GlobalStorageSiK.EnableBatteryCompat == true
end

--- Indica si se permiten contenedores vanilla marcados.
---@return boolean
function GlobalStorageSiK.Sandbox.allowMarkedContainers()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.AllowMarkedContainers ~= false
end

--- Indica si la transferencia remota está habilitada.
---@return boolean
function GlobalStorageSiK.Sandbox.remoteTransferEnabled()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.RemoteTransferEnabled ~= false
end

--- Indica si el auto-ordenado está habilitado.
---@return boolean
function GlobalStorageSiK.Sandbox.autoSortEnabled()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.AutoSortEnabled ~= false
end

--- Indica si el depósito debe RECHAZARSE (quedar en el inventario del
--- jugador) cuando el ítem no encuentra categoría, filtro personalizado, ni
--- otro contenedor con el mismo ítem (afinidad) - en vez de caer al primer
--- contenedor «cualquiera» con hueco libre. Desactivada por defecto: el
--- comportamiento de siempre (fallback a cualquier hueco) no cambia salvo
--- que el jugador la active a propósito.
---@return boolean
function GlobalStorageSiK.Sandbox.rejectDepositIfNoMatch()
	if not SandboxVars.GlobalStorageSiK then
		return false
	end
	return SandboxVars.GlobalStorageSiK.RejectDepositIfNoMatch == true
end

--- Indica si el depósito masivo está habilitado.
---@return boolean
function GlobalStorageSiK.Sandbox.bulkDepositEnabled()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.BulkDepositEnabled ~= false
end

--- Muestra progreso y resumen de depósito, extracción y Auto Sort mediante
--- notas sobre el personaje. Es feedback de juego, independiente de debug.
---@return boolean
function GlobalStorageSiK.Sandbox.operationHaloFeedbackEnabled()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.OperationHaloFeedback ~= false
end

--- Presupuesto interno e invariable de una petición masiva. Ya no se expone
--- en sandbox: valores configurables alteraban el contrato de progreso. El
--- planificador añade pausas y permite intercalar redes independientes.
---@return number
function GlobalStorageSiK.Sandbox.getMaxItemsPerBulkTick()
	return 10
end

--- Indica si se deben respetar los ítems favoritos.
---@return boolean
function GlobalStorageSiK.Sandbox.respectFavoriteItems()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.RespectFavoriteItems ~= false
end

--- Máximo de zonas por red.
---@return number
function GlobalStorageSiK.Sandbox.getMaxZonesPerNetwork()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.MaxZonesPerNetwork or 8
end

--- Indica si se permite importar safehouse como zona.
---@return boolean
function GlobalStorageSiK.Sandbox.allowSafehouseImport()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.AllowSafehouseImport ~= false
end

--- Indica si se deben respetar los ítems equipados.
---@return boolean
function GlobalStorageSiK.Sandbox.respectEquippedItems()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.RespectEquippedItems ~= false
end

--- Indica si se reescanea al abrir el terminal.
---@return boolean
function GlobalStorageSiK.Sandbox.rescanOnTerminalOpen()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.RescanOnTerminalOpen ~= false
end

--- Tiempo (unidades de receta B42, no segundos literales) de la accion
--- cronometrada de la ventana "Fabricar lector" (GS_AcquireReaderAction).
---@return number
function GlobalStorageSiK.Sandbox.getReaderAcquireCraftTime()
	if not SandboxVars.GlobalStorageSiK then
		return 120
	end
	return SandboxVars.GlobalStorageSiK.ReaderAcquireCraftTime or 120
end

--- Tiempo de la accion cronometrada de "Conseguir PC" (GS_AcquirePCAction).
---@return number
function GlobalStorageSiK.Sandbox.getPCAcquireCraftTime()
	if not SandboxVars.GlobalStorageSiK then
		return 100
	end
	return SandboxVars.GlobalStorageSiK.PCAcquireCraftTime or 100
end

--- Tiempo de instalar un disquete de red en un ordenador (metodo lector +
--- disquete). Compartido por el core y por cualquier addon que instale su
--- propio disquete sobre un terminal (ver GS_InstallTerminalReader.lua).
---@return number
function GlobalStorageSiK.Sandbox.getTerminalInstallTime()
	if not SandboxVars.GlobalStorageSiK then
		return 90
	end
	return SandboxVars.GlobalStorageSiK.TerminalInstallTime or 90
end

--- Obtiene el máximo de contenedores por zona al escanear.
---@return number
function GlobalStorageSiK.Sandbox.getMaxContainersPerZone()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.MaxContainersPerZone or 128
end

--- Indica si el modo debug está activo (trazas de red/servidor - muy ruidoso).
---@return boolean
function GlobalStorageSiK.Sandbox.debugMode()
	if not SandboxVars.GlobalStorageSiK then
		return false
	end
	return SandboxVars.GlobalStorageSiK.DebugMode == true
end

--- Reenvia al cliente suscrito las lineas que nacen en el dedicado. Es una
--- opcion separada porque el debug local puede ser util sin multiplicar
--- trafico; el transporte aplica limites y lotes adicionales.
---@return boolean
function GlobalStorageSiK.Sandbox.debugRelayToClients()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.DebugRelayToClients ~= false
end

--- Indica si el bloque de interfaz está activo (clicks, árbol de widgets,
--- solapes - ver GS_UIDebug.lua). DebugMode es el interruptor maestro; las
--- categorías normales y DETAIL siguen siendo opt-in para evitar ruido.
---@return boolean
function GlobalStorageSiK.Sandbox.debugModeUI()
	if not GlobalStorageSiK.Sandbox.debugMode() or not SandboxVars.GlobalStorageSiK then
		return false
	end
	return SandboxVars.GlobalStorageSiK.DebugModeUI == true
end

--- Categorias de traza granulares dentro de debugMode() (a peticion del
--- usuario, tras un log de prueba con decenas de lineas de NetTrace/
--- TerminalAccess por segundo que tapaban la unica linea que interesaba de
--- verdad, la de CraftUtils). DebugMode sigue siendo el interruptor maestro -
--- si esta desactivado, ninguna categoria imprime nada, sin excepcion; con
--- DebugMode activo, cada categoria se puede apagar por separado para ver
--- solo el tipo de diagnostico que se necesita en cada momento. Todas
--- En instalaciones nuevas todas quedan apagadas y el administrador activa
--- solo el bloque que corresponda a su prueba. Una clave ausente de una
--- partida anterior conserva el fallback historico para no ocultar trazas.
---@param key string "Network"|"TerminalAccess"|"Craft"|"Inventory"|"Tooltip"|"UI"|"Router"
---@return boolean
function GlobalStorageSiK.Sandbox.debugCategoryEnabled(key)
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	local varName = "DebugCat" .. tostring(key)
	local value = SandboxVars.GlobalStorageSiK[varName]
	if value == nil then
		-- Categoria desconocida (area de log sin mapear todavia): no
		-- silenciarla por defecto, mejor pecar de mostrar de mas que de
		-- ocultar una traza nueva sin que nadie se de cuenta del porque.
		return true
	end
	return value == true
end

--- Sublog detallado dentro de una categoria principal. Siempre requiere que
--- la categoria padre este activa; las claves nuevas/ausentes quedan apagadas
--- para que una actualizacion no empiece a volcar inventarios completos.
---@param key string "Network"|"Craft"|"Inventory"|"Router"
---@return boolean
function GlobalStorageSiK.Sandbox.debugDetailEnabled(key)
	if not GlobalStorageSiK.Sandbox.debugMode()
		or not GlobalStorageSiK.Sandbox.debugCategoryEnabled(key) then
		return false
	end
	if not SandboxVars.GlobalStorageSiK then return false end
	return SandboxVars.GlobalStorageSiK["DebugDetail" .. tostring(key)] == true
end

--- Indica si la construcción GS es gratuita (ambas recetas).
---@return boolean
function GlobalStorageSiK.Sandbox.freeBuilding()
	if not SandboxVars.GlobalStorageSiK then
		return false
	end
	return SandboxVars.GlobalStorageSiK.FreeBuilding == true
end

--- Craft gratis del terminal mueble.
---@return boolean
function GlobalStorageSiK.Sandbox.freeCraftTerminalUnit()
	if GlobalStorageSiK.Sandbox.freeBuilding() then
		return true
	end
	if not SandboxVars.GlobalStorageSiK then
		return false
	end
	return SandboxVars.GlobalStorageSiK.FreeCraftTerminalUnit == true
end

--- Indica si el craft de una receta GS es gratis.
---@param recipeId string
---@return boolean
function GlobalStorageSiK.Sandbox.isFreeCraft(recipeId)
	if recipeId == "terminal_unit" or recipeId == "terminal_install" then
		return GlobalStorageSiK.Sandbox.freeCraftTerminalUnit()
	end
	return GlobalStorageSiK.Sandbox.freeBuilding()
end

--- Nivel Electricidad para instalar terminal GS en ordenador vanilla.
---@return number
function GlobalStorageSiK.Sandbox.getInstallTerminalSkill()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.InstallTerminalSkillLevel or 2
end

--- Nivel Electricidad para terminal mueble.
---@return number
function GlobalStorageSiK.Sandbox.getTerminalUnitSkill()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.TerminalUnitSkillLevel or 4
end

--- Máximo de terminales físicos por red.
---@return number
function GlobalStorageSiK.Sandbox.getMaxTerminalsPerNetwork()
	local cfg = GlobalStorageSiK.Config and GlobalStorageSiK.Config.MAX_TERMINALS_PER_NETWORK or 8
	local sv = SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.MaxTerminalsPerNetwork
	if sv == nil then
		return cfg
	end
	return math.max(1, tonumber(sv) or cfg)
end

--- Distancia máxima (baldosas) para vincular un terminal adicional a la red
--- Y para que un contenedor cuente como parte de ella (mismo concepto:
--- "alcance de la red" desde un terminal activo). Antes eran DOS sandbox
--- vars independientes (TerminalLinkMaxDistance, con su propio cálculo
--- automático de hasta ~480 baldosas por defecto, y TerminalContainerMaxDistance)
--- que confundían al mostrarse en la misma pantalla con valores distintos
--- para "lo mismo" en la práctica - unificadas en una sola fuente de verdad.
---@return number
function GlobalStorageSiK.Sandbox.getTerminalLinkMaxDistance()
	return GlobalStorageSiK.Sandbox.getContainerMaxDistance()
end

--- Exige que los contenedores detectados por un escaneo de zona estén dentro
--- de `getContainerMaxDistance()` del terminal activo más cercano de la red.
--- Se puede sobreescribir por red desde la pestaña Red (ver GS_Network.containerRangeEnabled).
---@return boolean
--- Ver comentario de requireTerminalAccess(): misma inversion de polaridad
--- (v1.2.110), mismo motivo. DebugSkipContainerRange por defecto en false.
function GlobalStorageSiK.Sandbox.requireContainerRange()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.DebugSkipContainerRange ~= true
end

--- Distancia máxima (baldosas) entre un contenedor y el terminal activo más
--- cercano de su red para que un escaneo de zona lo recoja. Solo aplica
--- cuando requireContainerRange() es true.
---@return number
function GlobalStorageSiK.Sandbox.getContainerMaxDistance()
	local sv = SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.TerminalContainerMaxDistance
	return math.max(5, tonumber(sv) or 40)
end

--- Exige leer manuales antes de craftear.
---@return boolean
function GlobalStorageSiK.Sandbox.requireRecipeBooks()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.RequireRecipeBooks ~= false
end

--- Exige mesa de trabajo / superficie de craft.
---@return boolean
function GlobalStorageSiK.Sandbox.requireWorkbench()
	if not SandboxVars.GlobalStorageSiK then
		return true
	end
	return SandboxVars.GlobalStorageSiK.RequireWorkbench ~= false
end

--- Peso de spawn de manuales en loot.
---@return number
function GlobalStorageSiK.Sandbox.getLootBooksWeight()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.LootBooksWeight or 2.0
end

--- Multiplicadores de sandbox por familia de item para GS_LootDistributions.lua
--- (0 = nunca aparece en loot, 1.0 = comportamiento original). Mismo patron
--- que ya usan los addons (GSSiK_Addon_Tablet_Sandbox.lua, getLoot*Weight).
---@return number
function GlobalStorageSiK.Sandbox.getLootFloppyDiskWeight()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.LootFloppyDiskWeight or 1.0
end

---@return number
function GlobalStorageSiK.Sandbox.getLootBlankDiskWeight()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.LootBlankDiskWeight or 1.0
end

---@return number
function GlobalStorageSiK.Sandbox.getLootUninstallDiskWeight()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.LootUninstallDiskWeight or 1.0
end

---@return number
function GlobalStorageSiK.Sandbox.getLootDriveDiskWeight()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.LootDriveDiskWeight or 1.0
end

---@return number
function GlobalStorageSiK.Sandbox.getLootManualWeight()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.LootManualWeight or 1.0
end

---@return number
function GlobalStorageSiK.Sandbox.getLootDiskProgramMagazineWeight()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.LootDiskProgramMagazineWeight or 1.0
end

---@return number
function GlobalStorageSiK.Sandbox.getLootSolderingIronWeight()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.LootSolderingIronWeight or 1.0
end

---@return number
function GlobalStorageSiK.Sandbox.getLootPCPartsWeight()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.LootPCPartsWeight or 1.0
end

---@return number
function GlobalStorageSiK.Sandbox.getLootSolderingPartsWeight()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.LootSolderingPartsWeight or 1.0
end

---@return number
function GlobalStorageSiK.Sandbox.getLootTerminalReaderWeight()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.LootTerminalReaderWeight or 1.0
end

---@return number
function GlobalStorageSiK.Sandbox.getLootSolderingIronManualWeight()
	return SandboxVars.GlobalStorageSiK and SandboxVars.GlobalStorageSiK.LootSolderingIronManualWeight or 1.0
end

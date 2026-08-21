--[[
	GlobalStorageSiK - Reescritura de DisplayCategory en el arranque
	Autor: SiK
	Fecha: 2026-08-02
	Descripcion: para nuestras subcategorias que distinguen items dentro de una
	misma categoria vanilla compartida (comida perecedera, joyeria/
	otros accesorios, armas de fuego/cuerpo a cuerpo, material metal/cuero/madera...),
	fijamos una DisplayCategory REAL sobre el script item, con la misma tecnica
	que usa Extended Categories (item:DoParam("DisplayCategory", ...)).

	IMPORTANTE - nunca duplicamos ni pisamos un mod de categorias extendidas ya
	instalado: si detectamos Extended Categories (CAEC_Global, ver GS_CompatMods.lua),
	esta reescritura NO SE EJECUTA. El probablemente ya tiene su propia categoria
	para "comida perecedera" etc., y nosotros solo LEEMOS la que haya puesto -
	reutilizamos sus mismas claves cuando existen (ver GS_Subcategories.lua) para
	que el resultado sea identico este el instalado o no.

	Better Sorting (ver GS_CompatMods.hasBetterSorting) es distinto: SI se
	ejecuta esta reescritura con el activo, porque sin escribir nuestro
	"override" real sobre el item, el desplegable de filtros y "Categorias
	aceptadas" de un contenedor (que enumeran el DisplayCategory REAL ya
	almacenado en cada item, no un valor recalculado al vuelo) nunca ofrecen
	nuestras subcategorias (bug real 2026-08-21: "Comida" sin opcion
	"Perecedero", "Arma - cuerpo a cuerpo" duplicado 4 veces sin dividir por
	tipo). overrideForScriptItem() ya normaliza el codigo de Better Sorting via
	BETTER_SORTING_CANON (GS_Subcategories.lua) antes de decidir el override,
	asi que el resultado es el mismo que sin ningun mod de categorias. Solo
	toca los items que caen en una de las 6 categorias con subcategoria GS real
	(Accessory/Food/Gardening/FirstAid/Weapon/Material) - la ropa por hueco
	(ClothHead/ClothArm/...) ya la divide bien Better Sorting solo, y no forma
	parte de BETTER_SORTING_CANON, asi que esta reescritura la deja intacta sin
	necesitar logica aparte.

	Better Sorting engancha el MISMO evento (OnGameBoot) para su propia
	escritura - si su handler se registra despues del nuestro, su codigo plano
	gana la carrera y pisa nuestro override. Por eso, SOLO si se detecta
	Better Sorting, se programa ademas una reaplicacion diferida un frame
	despues via OnTick (una vez, se autoelimina) para garantizar la ultima
	palabra sin depender del orden de carga de mods.

	El hueco de joyeria (collar/anillo/muñeca/pendiente) NO se gestiona aqui -
	ver GS_ItemTaxonomy.lua: ya se detecta solo via BodyLocation vanilla
	(subcategoria real, sin inventar una DisplayCategory nueva para ello).

	Se ejecuta en TODOS los procesos (cliente, servidor dedicado, servidor local
	en SP) porque cada uno carga su propio ScriptManager de forma independiente.

	Idempotente: vuelve a evaluar todos los items en cada arranque, pero como el
	resultado depende de propiedades ESTABLES del script item (BodyLocation,
	DaysFresh, tags, nombre), siempre calcula la misma DisplayCategory - no hay
	estado que puede desincronizarse entre partidas guardadas.
]]

require "GS_Subcategories"
require "GS_CompatMods"

local function ensureCategoryOverrides()
	if GlobalStorageSiK.CompatMods.hasExtendedCategories() then
		-- Extended Categories (u otro mod de categorias extendidas detectado
		-- en el futuro) ya gestiona esto - no duplicar ni competir por el
		-- mismo campo.
		return
	end
	if not getAllItems then
		return
	end
	local ok, items = pcall(getAllItems)
	if not ok or not items then
		return
	end
	local total = items:size()
	for i = 0, total - 1 do
		local si = items:get(i)
		local subOk, sub = pcall(GlobalStorageSiK.Subcategories.overrideForScriptItem, si)
		if subOk and sub and sub.override then
			pcall(function()
				si:DoParam("DisplayCategory", sub.override)
			end)
		end
	end
end

--- BUG REAL encontrado (2026-08-21, primera prueba DEV de Better Sorting): la
--- deteccion `hasBetterSorting()` para programar la reaplicacion diferida
--- estaba como sentencia de nivel superior de este fichero, evaluada al
--- CARGAR el fichero (require), no al disparar OnGameBoot. Como BScats lo fija
--- el propio shared file de Better Sorting al cargarse, si el orden de carga
--- de mods evaluaba este fichero ANTES de que el de Better Sorting hubiera
--- terminado, la deteccion daba (falso) negativo, la reaplicacion nunca se
--- programaba y el override de GS quedaba a merced de que orden ganara la
--- carrera - exactamente lo que "evitar que el orden de carga importe" pide
--- no depender. Ahora TODO (rewrite inicial + deteccion + programar el
--- reintento) vive dentro de la MISMA funcion, disparada por OnGameBoot: para
--- ese momento, los shared files de TODOS los mods (incluido BScats) ya han
--- terminado de cargar, sea cual sea el orden.
local function onGameBoot()
	ensureCategoryOverrides()
	if GlobalStorageSiK.CompatMods.hasBetterSorting() then
		-- Aviso siempre visible (no depende de DebugMode) para confirmar en
		-- pruebas DEV que la capa de compatibilidad se activo; detalle por
		-- item bajo DebugCatCompatCategories + DebugDetailCompatCategories.
		GlobalStorageSiK.Log.warn("Compat", "Better Sorting detectado - reescritura de subcategorias GS reaplicada con retardo para ganar la carrera de OnGameBoot (ver DebugCatCompatCategories)")
		local function reapplyOnceAfterBoot()
			Events.OnTick.Remove(reapplyOnceAfterBoot)
			ensureCategoryOverrides()
		end
		Events.OnTick.Add(reapplyOnceAfterBoot)
	end
end

Events.OnGameBoot.Add(onGameBoot)

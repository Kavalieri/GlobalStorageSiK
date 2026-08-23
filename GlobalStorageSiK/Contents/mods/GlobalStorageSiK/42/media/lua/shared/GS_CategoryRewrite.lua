--[[
	GlobalStorageSiK - Reescritura de DisplayCategory en el arranque
	Autor: SiK
	Fecha: 2026-08-02 (politica de compatibilidad revisada 2026-08-21)
	Descripcion: para nuestras subcategorias que distinguen items dentro de una
	misma categoria vanilla compartida (comida perecedera, joyeria/
	otros accesorios, armas de fuego/cuerpo a cuerpo, material metal/cuero/madera...),
	fijamos una DisplayCategory REAL sobre el script item, con la misma tecnica
	que usa Extended Categories (item:DoParam("DisplayCategory", ...)).

	POLITICA FIRME (2026-08-21, sin excepciones): si el jugador ha instalado
	CUALQUIER mod de categorias, es porque quiere usar SU organizacion en su
	partida - nosotros NUNCA reescribimos DisplayCategory encima de lo que
	ese mod ya puso, sea cual sea (Extended Categories, Organized Categories:
	Core, Better Sorting, o cualquier otro detectado en el futuro). Esta
	reescritura NO SE EJECUTA si se detecta ninguno de ellos. Solo cubrimos,
	por LECTURA (nunca escritura), los huecos que ese mod deje para que
	nuestro propio entorno (3 niveles de filtro del Almacen, distincion de
	joyeria, etc.) siga funcionando sobre la categoria que el ya puso - ver
	canonicalDisplayCat()/BETTER_SORTING_CANON en GS_Subcategories.lua para
	Better Sorting, e isDisplayCategoryKey() en GS_ItemTaxonomy.lua (recoge
	solo IGUI_ItemCat_<codigo> de cualquier mod activo) para Extended
	Categories y Organized Categories: Core.

	Limitacion aceptada como consecuencia directa de esta politica: el
	desplegable de "Categorias aceptadas" de un contenedor nuestro (que
	enumera el DisplayCategory REAL ya almacenado en cada item, no un valor
	recalculado al vuelo) no podra ofrecer las subcategorias PROPIAS de GS
	para items ya retagueados por el mod de categorias del jugador - solo
	ofrecera las que ESE mod haya expuesto. Es el mismo compromiso que ya
	aceptabamos con Extended Categories desde el principio; ahora se aplica
	por igual a los tres.

	[Historico, ya no aplica] Hasta 2026-08-21 esta reescritura SI competia
	deliberadamente con Better Sorting (incluso con una reaplicacion diferida
	via OnTick para ganar la carrera de OnGameBoot), justificado por un bug
	real donde el propio desplegable de GS salia incompleto/duplicado sin
	ese override. Se revirtio por decision explicita: "no debemos reescribir
	NUESTRAS categorias encima. Solo aplicaremos los ajustes necesarios para
	cubrir los huecos... por lectura" - el jugador que instala Better Sorting
	tiene el mismo derecho a que se respete su eleccion que con cualquier
	otro mod de categorias, aunque eso signifique aceptar la limitacion del
	parrafo anterior tambien para el.

	El hueco de joyeria (collar/anillo/muñeca/pendiente) NO se gestiona aqui -
	ver GS_ItemTaxonomy.lua: ya se detecta solo via BodyLocation vanilla
	(subcategoria real, sin inventar una DisplayCategory nueva para ello) -
	funciona igual haya o no un mod de categorias instalado, porque nunca
	dependio de escribir DisplayCategory.

	Se ejecuta en TODOS los procesos (cliente, servidor dedicado, servidor local
	en SP) porque cada uno carga su propio ScriptManager de forma independiente.

	Idempotente: vuelve a evaluar todos los items en cada arranque, pero como el
	resultado depende de propiedades ESTABLES del script item (BodyLocation,
	DaysFresh, tags, nombre), siempre calcula la misma DisplayCategory - no hay
	estado que puede desincronizarse entre partidas guardadas.
]]

require "GS_Subcategories"
require "GS_CompatMods"

--- Cualquier mod de categorias detectado deja de escribir esta funcion por
--- completo - lista unica, sin distinguir "cuales sí compiten"; ver politica
--- firme en la cabecera del fichero.
---@return boolean
local function anyCategoryModActive()
	return GlobalStorageSiK.CompatMods.hasExtendedCategories()
		or GlobalStorageSiK.CompatMods.hasOrganizedCategoriesCore()
		or GlobalStorageSiK.CompatMods.hasBetterSorting()
end

local function ensureCategoryOverrides()
	if anyCategoryModActive() then
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

local function onGameBoot()
	ensureCategoryOverrides()
end

Events.OnGameBoot.Add(onGameBoot)

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

Events.OnGameBoot.Add(ensureCategoryOverrides)

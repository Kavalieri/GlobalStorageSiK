--[[
	GlobalStorageSiK - Clasificador de bloque: Combate
	Autor: SiK
	Fecha: 2026-08-27

	Primer bloque real de la taxonomia nativa (§12, orden de trabajo - mayor
	confianza tecnica, sin dependencia de ningun probe pendiente). Cubre:
	- Cuerpo a cuerpo: WeaponCategory del script item, confianza 100.
	- Armas de fuego: isRanged() + isTwoHandWeapon()/AmmoType, confianza 100
	  para el hecho de ser arma de fuego; el tipo exacto (corta/rifle/
	  escopeta) usa el mismo limite honesto ya documentado (§3.4) - nunca
	  revolver/subfusil por nombre.
	- Municion: AmmoType real sobre un item que NO es el arma en si.
	- Piezas de arma: ItemType base:weaponpart confirmado en scripts B42.
	NO cubre todavia explosivos generales - sin una señal publica
	confirmada y fiable sobre el script item para distinguirlos (evita
	inventar heuristicas de nombre, confianza 0 segun §6) - quedan
	pendientes de un getter/tag confirmado en una ronda posterior. La unica
	excepcion exacta curada es Base.Matches, anclada al fullType real.
]]

require "GS_NativeClassifierApi"
require "GS_NativeClassifierUtils"

local U = GlobalStorageSiK.NativeClassifierUtils

--- WeaponCategory -> clave L3 registrada (GS_NativeTaxonomyRegistry.combat.melee).
local MELEE_CATEGORY_TO_L3 = {
	{ "AXE", "axe" },
	{ "BLUNT", "blunt_long" },
	{ "SMALL_BLUNT", "blunt_short" },
	{ "LONG_BLADE", "blade_long" },
	{ "SMALL_BLADE", "blade_short" },
	{ "SPEAR", "spear" },
	{ "IMPROVISED", "improvised" },
}

---@param fullType string
---@param si table|nil script item
---@return table|nil primaryPath
---@return table|nil facets
---@return table|nil attributes
---@return table|nil evidence
local function classifyCombat(fullType, si)
	if fullType == "Base.Matches" then
		return
			{ l1 = "combat", l2 = "explosive", l3 = "incendiary" },
			{ fireSource = true },
			{},
			U.evidence("exact_fulltype_incendiary", 100)
	end
	if not si then return nil end
	-- B42 declares weapon parts structurally, including RedDot and modded
	-- parts whose names contain no weapon token. No translated category probe.
	if U.itemTypeLower(si) == "base:weaponpart" then
		return { l1 = "combat", l2 = "firearm", l3 = "weapon_part" },
			{ weaponPart = true }, {}, U.evidence("script_item_type_weapon_part", 100)
	end

	-- Cuerpo a cuerpo: WeaponCategory es un Set - un arma puede tener mas de
	-- una categoria (§3.5); la primera que coincida en este orden fijo
	-- decide la ruta primaria, el resto queda fuera por ahora (facet
	-- multi-categoria pendiente de una ronda posterior si hace falta).
	local weaponCats = U.getWeaponCategories(si)
	if weaponCats then
		for i = 1, #MELEE_CATEGORY_TO_L3 do
			local wcName, l3 = MELEE_CATEGORY_TO_L3[i][1], MELEE_CATEGORY_TO_L3[i][2]
			local wc = WeaponCategory and WeaponCategory[wcName]
			if wc and U.safeCall(function() return weaponCats:contains(wc) end) then
				-- dev9: la excepcion "SHARP_KNIFE cede a Combate" se revirtio en
				-- GS_NativeClassifierTools.lua (Herramientas gana siempre con tag
				-- oficial, regla autoritativa de sistemas) - un cuchillo/machete
				-- con SHARP_KNIFE nunca llega aqui, asi que ya no hace falta
				-- comprobar ese tag en esta rama.
				return
					{ l1 = "combat", l2 = "melee", l3 = l3 },
					{ melee = true },
					{},
					U.evidence("script_weapon_category", 100)
			end
		end
	end

	-- Armas de fuego: isRanged() sobre el script item, mismo getter ya
	-- confirmado y en uso en GS_Subcategories.lua (isFirearm). Tipo exacto
	-- via isTwoHandWeapon()+AmmoType, mismo criterio que
	-- weaponFirearmTypeKey() ya existente - sin inventar revolver/subfusil.
	local isRanged = si.isRanged and U.safeCall(function() return si:isRanged() end)
	if isRanged == true then
		local l3
		local twoHand = si.isTwoHandWeapon and U.safeCall(function() return si:isTwoHandWeapon() end)
		local ammoType = si.getAmmoType and U.safeCall(function() return si:getAmmoType() end)
		-- BUG REAL revertido (2026-08-27, dev6 → dev8 → dev9): dev6 exigia
		-- `twoHand == false` exacto (nil se quedaba en "other"); dev8 lo
		-- cambio a `not twoHand` (nil se colaba como "handgun"). Sistemas
		-- confirmo con la auditoria real que NINGUNA de las dos es segura sin
		-- verificar en vivo por que isTwoHandWeapon() devuelve nil para ese
		-- ScriptItem (¿el metodo no existe en la clase base, la llamada
		-- fallo, o el campo realmente no esta seteado?) - "un valor
		-- desconocido no deberia recibir subtipo con confianza 100". Vuelve a
		-- la comprobacion de 3 vias EXPLICITA: false confirmado -> arma
		-- corta, true confirmado -> arma larga (rifle/escopeta por AmmoType),
		-- nil -> "other" HONESTO, nunca adivinado. Pendiente: confirmar en
		-- TEST por que isTwoHandWeapon() no siempre devuelve un booleano
		-- claro sobre el ScriptItem (posible limite real de la API, no un
		-- bug de este fichero).
		if twoHand == false then
			l3 = "handgun"
		elseif twoHand == true then
			local ammoLower = ammoType and string.lower(tostring(ammoType)) or ""
			if ammoLower:find("shell", 1, true) or ammoLower:find("slug", 1, true) then
				l3 = "shotgun"
			else
				l3 = "rifle"
			end
		else
			l3 = "other"
		end
		local attributes = {}
		if ammoType then attributes.ammoType = tostring(ammoType) end
		-- Probe controlado pedido por sistemas (dev10, informe de dev9):
		-- "registrar por una muestra controlada de pistola/rifle/escopeta el
		-- resultado de isTwoHandWeapon()" - SOLO diagnostico, nunca decide
		-- nada; permite a la auditoria mostrar el valor crudo real (incluido
		-- "nil" como string) sin adivinar nada en la clasificacion.
		if l3 == "other" then
			attributes.twoHandRaw = tostring(twoHand)
		end
		return
			{ l1 = "combat", l2 = "firearm", l3 = l3 },
			{ firearm = true },
			attributes,
			U.evidence("script_is_ranged", 100)
	end

	-- Municion: NO es un arma en si (isRanged ya descartado arriba). Dos
	-- señales independientes, cualquiera de las dos basta:
	-- - AmmoType real (cargadores, principalmente).
	-- - Un tag oficial de municion suelta/caja (AMMO/AMMO_CASE/SHOTGUN_SHELL).
	-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev6): "solo
	-- reconoce seis cargadores mediante AmmoType; no captura munición suelta
	-- ni cajas" - la version anterior exigia AmmoType PRIMERO y solo miraba
	-- los tags de munición suelta/caja DENTRO de ese if, así que una bala o
	-- caja de munición sin AmmoType propio (no "usan" munición, SON
	-- munición) nunca entraban en esta rama. Los tags ahora se comprueban
	-- de forma independiente.
	local ammoTypeStandalone = si.getAmmoType and U.safeCall(function() return si:getAmmoType() end)
	local hasAmmoTypeStandalone = ammoTypeStandalone and tostring(ammoTypeStandalone) ~= ""
	local hasAmmoTag = ItemTag and U.hasAnyTag(si, {
		ItemTag.PISTOL_MAGAZINE, ItemTag.RIFLE_MAGAZINE, ItemTag.AMMO_CASE,
		ItemTag.AMMO, ItemTag.SHOTGUN_SHELL,
	})
	if hasAmmoTypeStandalone or hasAmmoTag then
		local facets = { ammo = true }
		-- dev27 (§5: "conserva señales" de contenido/capacidad real, nunca
		-- pierde informacion por resolver identidad primaria): confirmado por
		-- lectura de scripts que Bag_AmmoBox_* son ItemType=base:container
		-- ademas de llevar el tag AMMO_CASE - la caja SI es un contenedor de
		-- verdad, faceta conservada sin que Contenedores tenga que reclamar
		-- identidad (Combate gana por evidencia de contenido real, orden ya
		-- establecido).
		if U.itemTypeLower(si) == "base:container" then
			facets.containerCapacity = true
		end
		local attributes = {}
		if hasAmmoTypeStandalone then attributes.ammoType = tostring(ammoTypeStandalone) end
		if ItemTag then
			if U.hasAnyTag(si, { ItemTag.PISTOL_MAGAZINE, ItemTag.RIFLE_MAGAZINE }) then
				facets.magazine = true
				attributes.ammoForm = "magazine"
			elseif U.hasTag(si, ItemTag.AMMO_CASE) then
				attributes.ammoForm = "box"
			elseif U.hasAnyTag(si, { ItemTag.AMMO, ItemTag.SHOTGUN_SHELL }) then
				attributes.ammoForm = "loose"
			end
		end
		-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev8): TODA
		-- municion se marcaba "script_ammo_type" confianza 100, aunque la
		-- unica señal real fuera un tag (AMMO/AMMO_CASE/SHOTGUN_SHELL) sin
		-- AmmoType propio - "no afecta a la ruta, pero sí a la honestidad del
		-- diagnóstico". Fuente real segun cual señal esté presente de verdad;
		-- si coinciden ambas, la de AmmoType es la primaria y el tag queda
		-- como apoyo.
		local evidence
		if hasAmmoTypeStandalone and hasAmmoTag then
			evidence = U.evidence("script_ammo_type", 100)
			evidence.supporting = { "script_ammo_tag" }
		elseif hasAmmoTypeStandalone then
			evidence = U.evidence("script_ammo_type", 100)
		else
			evidence = U.evidence("script_ammo_tag", 95)
		end
		return
			{ l1 = "combat", l2 = "firearm", l3 = "ammunition" },
			facets,
			attributes,
			evidence
	end

	-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev12):
	-- Base.Bullets357Box no tiene AmmoType propio ni ninguno de los tags
	-- oficiales de arriba - "probablemente carece del tag estatico
	-- utilizado por el clasificador" - caia en Contenedores por el token
	-- "box". Regla secundaria y ESTRUCTURADA (nunca "box" suelto, pedido
	-- explicito): solo cuenta como municion debil si el nombre demuestra
	-- ser municion de verdad (token "bullets"/"shells") o la combinacion
	-- "ammo"+"box" - confianza inferior al tag oficial (30) pero registrada
	-- aqui, ANTES que Contenedores en la cadena.
	local weakAmmoTokens = U.tokenize(U.typeName(si))
	local hasBulletsOrShells = U.hasAnyToken(weakAmmoTokens, { bullets = true, shells = true })
	local hasAmmoBoxCombo = U.hasAnyToken(weakAmmoTokens, { ammo = true }) and U.hasAnyToken(weakAmmoTokens, { box = true })
	if hasBulletsOrShells or hasAmmoBoxCombo then
		return
			{ l1 = "combat", l2 = "firearm", l3 = "ammunition" },
			{ ammo = true },
			{},
			U.evidence("name_ammo_box_weak", 30)
	end

	return nil
end

GlobalStorageSiK.NativeClassifier.registerBlock(classifyCombat, "combat")

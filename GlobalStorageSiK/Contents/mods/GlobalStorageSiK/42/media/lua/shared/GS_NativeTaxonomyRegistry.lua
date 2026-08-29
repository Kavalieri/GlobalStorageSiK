--[[
	GlobalStorageSiK - Registro estable de claves L1/L2/L3 de la taxonomia nativa
	Autor: SiK
	Fecha: 2026-08-27

	Datos puros, sin logica de clasificacion (ver Documentacion/
	GSSiK_Taxonomia_Nativa_Analisis.md §5). Claves ASCII estables, nunca
	texto traducido - el texto vive en las traducciones (IGUI_GS_Tax_<clave>),
	añadidas cuando cada bloque de clasificacion se implemente de verdad.

	L3 (hojas) solo se registra para grupos ya con clasificador real
	implementado o con getters confirmados y sin bloqueo de probe pendiente -
	nunca especulativo. El primer bloque de clasificacion (Combate, ver §12
	orden de trabajo) es el unico con L3 completo por ahora; el resto de
	grupos llega con L1/L2 fijados de antemano (aprobados por el equipo de
	sistemas) y su propio L3 se añade cuando toque implementarlos, en el
	mismo orden ya acordado.

	classifierSchema (GS_CatalogManager.CLASSIFIER_SCHEMA) debe incrementarse
	si esta tabla cambia de forma que afecte a clasificaciones ya cacheadas
	(añadir/quitar/renombrar una clave L1/L2/L3 existente) - nunca al solo
	añadir un grupo nuevo sin tocar los existentes.
]]

GlobalStorageSiK.NativeTaxonomyRegistry = GlobalStorageSiK.NativeTaxonomyRegistry or {}

--- Arbol L1 -> { l2Key -> { l3Keys... } }. Un grupo L2 sin L3 registrado
--- todavia es valido (la ruta primaria puede quedarse en l2 hasta que su
--- bloque de clasificacion añada detalle) - nunca inventar un L3 solo para
--- rellenar.
local TREE = {
	combat = {
		melee = { "axe", "blunt_long", "blunt_short", "blade_long", "blade_short", "spear", "improvised" },
		-- Corregido dos veces (2026-08-27, pedido explicito del usuario,
		-- mientras se revisaba dev1):
		-- 1ª corrección: munición y piezas de arma NO son grupos L2 hermanos
		--    de "armas de fuego" - son Nivel 3 DENTRO de armas de fuego.
		-- 2ª corrección ("no veo el tercer nivel, me has ignorado"): la 1ª
		--    pasada aplano TODO en una unica lista L3 (tipos de arma +
		--    nombres de pieza sueltos) - eso perdia el Nivel 3 real. Lo que
		--    hace falta es que "Munición" y "Piezas" sean, cada una, SU
		--    PROPIO nodo de Nivel 3 (al mismo nivel que "Arma corta"/
		--    "Rifle"/...), no una lista de nombres de pieza disueltos ahi
		--    dentro. El calibre concreto (9mm, .45...) o el tipo de pieza
		--    concreto (óptica, cargador...) NO son un cuarto nivel - la
		--    taxonomia es de 3 niveles fijos - viven como faceta/atributo
		--    de ESE nodo L3 (`attributes.ammoType`/`facets.partType`),
		--    igual que el tier de la antena WiFi en el grupo 14.
		firearm = {
			"handgun", "rifle", "shotgun", "long_gun", "other", -- tipo de arma
			"ammunition",  -- L3 propio; calibre real en attributes.ammoType (§3.3, dinamico por AmmoType)
			"weapon_part", -- L3 propio; tipo de pieza real en facets.partType (óptica/cargador/culata/correa/cañón/luz/otra)
		},
		explosive = { "throwable", "trap", "incendiary", "flashbang", "component" },
	},
	food_drink = {
		perishable = { "meat_protein", "dairy_egg", "fish_seafood", "produce", "prepared_meal", "ingredient", "preserved", "beverage", "other_food" },
		non_perishable = { "meat_protein", "dairy_egg", "fish_seafood", "produce", "pantry", "ingredient", "spice", "preserved", "prepared_meal", "beverage", "animal_feed", "other_food" },
	},
	-- Precedencia entre bloques (pedido explicito del usuario, aplicada en
	-- el ORDEN DE REGISTRO en GS_NativeClassifier.lua, nunca aqui): si un
	-- objeto es herramienta Y arma a la vez, gana Herramienta. Si es
	-- material Y arma a la vez, gana Material. El registro de este fichero
	-- solo define claves validas; quien decide "quien clasifica primero" es
	-- el orden real de GlobalStorageSiK.NativeClassifier.registerBlock().
	tools = {
		construction = { "carpentry", "metalworking", "masonry" },
		maintenance = { "mechanic", "sewing" },
		harvesting = { "butchery", "fishing" },
		general = { "striking", "cutting" },
	},
	materials = {
		metal = {}, wood = {}, textile = {}, leather_hide = {}, mineral = {},
		component = { "adhesive", "fastener", "welding_consumable" }, organic = {},
	},
	medicine = {
		-- L3 poblado 2026-08-27 junto con GS_NativeClassifierMedicine.lua
		-- (senal de nombre interno, confianza baja - ver evidencia por
		-- fuente en la auditoria, nunca tratar estas claves como certeza).
		treatment = { "wound_dressing", "splint" },
		medication = { "painkiller", "antibiotic", "vitamin", "sedative" },
		instrument = { "surgical" },
		supply = { "injection", "protective" },
	},
	clothing_protection = {
		-- L3 de "clothing" poblado 2026-08-27 (dev6, pedido explícito del
		-- usuario: "quiero poder filtrar por pierna, torso, cabeza etc") -
		-- region corporal real derivada del hueco de equipacion oficial
		-- (ItemBodyLocation), ver GS_NativeClassifierClothing.lua.
		clothing = { "head", "neck", "torso", "arms", "legs", "feet" },
		protection = {},
		-- L3 poblado dev11 (pedido explícito: "las joyas... organizarlos por
		-- hueco equipable también") - mismos valores que
		-- GS_Subcategories.JEWELRY_SLOT_BUCKET (ya en producción, ya
		-- compatible con Magic y otros mods de joyería), reutilizados vía
		-- GS_Subcategories.jewelrySlotKey() en GS_NativeClassifierClothing.lua
		-- - nunca una lista nueva y duplicada aquí.
		accessory = { "necklace", "ring", "wrist", "earring", "nose" },
		-- "equipment"/"backpack" anadido dev27 (decision de sistemas: mochila
		-- o bolsa vestible se busca primariamente en Ropa/Equipamiento; su
		-- capacidad se conserva como faceta de contenedor - reemplaza
		-- containers.wearable.backpack de dev12, ver
		-- GS_NativeClassifierClothing.lua).
		equipment = { "backpack", "ammo_strap" },
	},
	containers = {
		portable = {}, liquid = {}, special = {},
	},
	knowledge_media = {
		-- "general_magazine" añadido dev10 (hallazgo de sistemas: "mag"/
		-- "magazine" solos no garantizan tema de receta - revistas de tema
		-- general sin evidencia de receta/oficio caen aqui, nunca en
		-- recipe_magazine sin confirmar).
		skill_book = {}, recipe_magazine = {}, general_magazine = {}, literature = {}, document = {}, recorded_media = {},
	},
	electronics_power = {
		power = {}, communication = {}, lighting = {}, component = {}, entertainment = {},
	},
	vehicles = {
		part = {}, consumable = {}, accessory = {},
	},
	survival_outdoors = {
		farming = {}, fishing = {}, trapping = {}, camping = {}, security = {},
	},
	home_leisure_collection = {
		furnishing = { "storage", "surface", "seating", "appliance", "decor" },
		-- L3 poblado 2026-08-27 junto con GS_NativeClassifierHomeLeisure.lua
		-- (senal de nombre interno, confianza baja - ver nota de "medicine").
		kitchen = { "cookware", "appliance" },
		cleaning = { "chemical", "tool" },
		renovation = { "paint" },
		collection = { "collectible", "media" },
		leisure = { "music", "game" },
	},
	other = {
		junk = {}, broken = {}, debug = {}, unclassified_modded = {},
		-- "classifier_error": bloque de diagnostico REAL, no un cajon de
		-- sastre - un fullType cae aqui solo si un clasificador de bloque
		-- lanzo una excepcion real (ver GS_NativeClassifier.computeClassification),
		-- nunca porque simplemente no le tocara todavia (eso es
		-- unclassified_modded).
		classifier_error = {},
	},
	-- Grupo 14, blindado (ver §5/§7 del documento): jamas proyectable a
	-- DisplayCategory por ningun mod de categorias externo, esté o no
	-- activo - CategoryProjection debe excluirlo explicitamente antes de
	-- decidir si hay algo que proyectar.
	globalstoragesik = {
		floppy_disk = { "blank", "recorded" },
		-- BUG REAL cerrado (2026-08-27, hallazgo del equipo de sistemas):
		-- esto era un mapa anidado ({floppy_drive={}, printer_3d={}, ...}),
		-- forma distinta a la de TODOS los demas grupos L2 (lista numerica
		-- de strings) - hasL3() solo recorre listas numericas con ipairs-like
		-- (#sub + indices 1..N), asi que estos 4 valores nunca se
		-- reconocian como L3 validos. Cada periferico (unidad + sus
		-- componentes propios, distinguidos por facets.role="unit"|
		-- "component", ver §5 grupo 14) es su propio nodo L3 plano, igual
		-- que el resto del registro - sin introducir un 4º nivel.
		peripheral = { "floppy_drive", "printer_3d", "wifi_antenna", "digital_whiteboard" },
		-- El Soldador es una HERRAMIENTA propia de GS, no un periferico de
		-- red - subgrupo L2 propio (ver §5 grupo 14). Nombrado
		-- "manufacturing" (pedido explicito del usuario: "fabricacion", para
		-- no ser redundante con el L1 general "tools"/Herramientas - este
		-- es el equipo con el que GS FABRICA sus propios perifericos, no
		-- una herramienta de uso general). Se fabrica aunque su receta este
		-- desactivada por defecto en sandbox; eso es disponibilidad de
		-- servidor, no afecta a la clasificacion.
		-- "computer_components" añadido dev17 (hallazgo de sistemas, §13.1):
		-- las 4 piezas GS que fabrican/consiguen Base.Mov_DesktopComputer
		-- (un ordenador VANILLA) - nunca un "terminal_computer" propio de
		-- GS, eso no existe como objeto real.
		manufacturing = { "soldering_iron", "computer_components" },
		-- "access_device"/"tablet" añadido dev17 (hallazgo de sistemas,
		-- §13): hardware funcional del addon Tablet - unidad (4 tabletas) +
		-- sus componentes de fabricación (pantalla/módulos/núcleo).
		access_device = { "tablet" },
	},
}

--- L1 exclusivo: ninguna categoria externa puede proyectarse sobre un
--- fullType clasificado bajo estas raices, sin excepcion (ver §7).
local SHIELDED_L1 = { globalstoragesik = true }

---@return table árbol completo L1->L2->L3[] - de solo lectura, no mutar.
function GlobalStorageSiK.NativeTaxonomyRegistry.getTree()
	return TREE
end

---@param l1 string
---@return boolean
function GlobalStorageSiK.NativeTaxonomyRegistry.isShielded(l1)
	return SHIELDED_L1[l1] == true
end

---@param l1 string
---@return boolean
function GlobalStorageSiK.NativeTaxonomyRegistry.hasL1(l1)
	return l1 ~= nil and TREE[l1] ~= nil
end

---@param l1 string
---@param l2 string
---@return boolean
function GlobalStorageSiK.NativeTaxonomyRegistry.hasL2(l1, l2)
	local group = l1 and TREE[l1]
	return group ~= nil and l2 ~= nil and group[l2] ~= nil
end

-- BUG REAL cerrado (2026-08-27, hallazgo del equipo de sistemas): el
-- consumidor (GS_NativeAudit.lua) trataba "lista L3 vacia" como "cualquier
-- L3 vale" (pensado para el caso de munición dinámica) - pero tras la
-- restructuración de Combate, "ammunition"/"weapon_part" ya son claves L3
-- ESTÁTICAS (el calibre/tipo de pieza real vive en attributes/facets, no
-- como valor de L3), asi que YA NO HAY ningun caso real de L3 dinamico. Esa
-- regla autorizaba sin querer cualquier L3 inventado en los 12 grupos aun
-- sin poblar (food_drink.meat_protein={}, tools.construction={}...).
-- Declaracion EXPLICITA: solo l1/l2 aqui listados aceptan cualquier valor
-- de L3 (ninguno por ahora) - todos los demas exigen que el L3 este
-- registrado de verdad, aunque su lista este vacia (vacia = "sin decidir
-- todavia", nunca "vale cualquier cosa").
local DYNAMIC_L3 = {
	-- Ejemplo de como se declararia un caso futuro real:
	-- ["combat/ammunition_caliber"] = true,
}

---@param l1 string
---@param l2 string
---@return boolean
function GlobalStorageSiK.NativeTaxonomyRegistry.isDynamicL3(l1, l2)
	return DYNAMIC_L3[tostring(l1) .. "/" .. tostring(l2)] == true
end

---@param l1 string
---@param l2 string
---@param l3 string
---@return boolean
function GlobalStorageSiK.NativeTaxonomyRegistry.hasL3(l1, l2, l3)
	local group = l1 and TREE[l1]
	local sub = group and l2 and group[l2]
	if not sub or not l3 then
		return false
	end
	if GlobalStorageSiK.NativeTaxonomyRegistry.isDynamicL3(l1, l2) then
		return true
	end
	for i = 1, #sub do
		if sub[i] == l3 then
			return true
		end
	end
	return false
end

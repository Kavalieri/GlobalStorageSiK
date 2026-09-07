--[[
	GlobalStorageSiK - Clasificador de bloque: Medicina
	Autor: SiK
	Fecha: 2026-08-27

	Pedido explícito del usuario: "añade 1 o 2 bloques más, los sencillos,
	medicina, hogar ocio". Sin un tag oficial confirmado equivalente a
	"base:hasmetal" para medicina en el catálogo de ItemTag ya estudiado
	(§3.2) - por ahora usa coincidencia de TOKEN completo (nunca subcadena)
	sobre el tipo real sin namespace de módulo, confianza 30 (§6), igual de
	honesta que las reglas débiles de Materiales. Reutiliza los mismos
	términos ya validados en producción en GS_Subcategories.lua (scalpel/
	suture/surgical/bloodbag/retractor/forceps para cirugía).

	CORREGIDO 2026-08-27 (dev6, hallazgo de sistemas sobre dev5): la versión
	anterior comparaba subcadenas sobre el fullType COMPLETO (namespace
	incluido) - ahora usa GlobalStorageSiK.NativeClassifierUtils.typeName()
	(sin el prefijo de módulo) tokenizado por límite CamelCase/guion bajo
	(tokenize()), comparado por TOKEN EXACTO, nunca por subcadena.

	Registrado ANTES que Combate/Materiales, mismo criterio que Herramientas
	- un objeto de medicina no debería competir nunca con una clasificación
	de arma, pero por si acaso alguno tuviera WeaponCategory.IMPROVISED.
]]

require "GS_NativeClassifierApi"
require "GS_NativeClassifierUtils"

local U = GlobalStorageSiK.NativeClassifierUtils

---@param list string[]
---@return table<string, boolean>
local function toSet(list)
	local set = {}
	for i = 1, #list do set[list[i]] = true end
	return set
end

-- Instrumental/cirugia: mismos terminos ya confirmados y en produccion en
-- GS_Subcategories.lua (gs_med_surgery). Un unico L3 ("surgical") - no hay
-- señal real para distinguir sub-tipos de instrumental todavia.
local SURGERY_TOKENS = toSet({ "scalpel", "suture", "surgical", "bloodbag", "retractor", "forceps" })
-- Tratamiento general, dos L3: vendaje (heridas) y ferula/inmovilizacion.
local WOUND_DRESSING_TOKENS = toSet({ "bandage", "gauze", "disinfectant" })
local SPLINT_TOKENS = toSet({ "splint" })
-- Medicamentos, cuatro L3 por efecto real. "pills" es el catch-all generico
-- (sedante/analgesico sin marca especifica) - se comprueba EL ULTIMO de los
-- 4 para que las marcas especificas (antibiotico/vitamina/analgesico) ganen
-- primero si tambien contienen la palabra "pills".
local PAINKILLER_TOKENS = toSet({ "painkiller", "beta" })
local ANTIBIOTIC_TOKENS = toSet({ "antibiotic", "antibiotics" })
local VITAMIN_TOKENS = toSet({ "vitamin", "vitamins" })
-- BUG REAL cerrado (2026-08-27, hallazgo de sistemas sobre dev6): "sleeping"
-- suelto capturaba Base.SleepingBag_* (sacos de dormir, ver
-- GS_NativeClassifierSurvival.lua) - un sedante real se llama
-- "PillsSleepingTablets", nunca solo "sleeping". Token generico quitado;
-- "antidep"/"pills" siguen siendo suficientes (PillsAntiDep, Pills,
-- PillsSleepingTablets ya contienen "pills" de todos modos).
local SEDATIVE_TOKENS = toSet({ "antidep", "pills" })
-- Suministros, dos L3: inyeccion y proteccion respiratoria/manos.
local INJECTION_TOKENS = toSet({ "syringe" })
local PROTECTIVE_TOKENS = toSet({ "neoprene", "gasmask" })
-- dev9 (hallazgo de sistemas sobre dev8): Base.CottonBalls/BoxOfCottonBalls/
-- AlcoholedCottonBalls son suministro medico real, pero "cotton" solo (sin
-- "balls") tambien nombra tela/hilo genuino (materiales) - regla compuesta
-- mas abajo: solo cuenta como suministro si el tipo tiene AMBOS tokens
-- "cotton" Y "balls" a la vez, nunca "cotton" suelto.

---@param fullType string
---@param si table|nil
---@return table|nil primaryPath
---@return table|nil facets
---@return table|nil attributes
---@return table|nil evidence
local function classifyMedicine(fullType, si)
	if fullType == "Base.ComfreyCataplasm" then
		return
			{ l1 = "medicine", l2 = "treatment", l3 = "wound_dressing" },
			{},
			{},
			U.evidence("exact_fulltype_medicine", 100)
	end
	if not si then return nil end
	local tokens = U.tokenize(U.typeName(si))
	if #tokens == 0 then return nil end

	do
		local hasCotton, hasBalls = false, false
		for i = 1, #tokens do
			if tokens[i] == "cotton" then hasCotton = true end
			if tokens[i] == "balls" then hasBalls = true end
		end
		if hasCotton and hasBalls then
			return
				{ l1 = "medicine", l2 = "supply", l3 = "protective" },
				{},
				{},
				U.evidence("name_medicine_supply", 30)
		end
	end
	if U.hasAnyToken(tokens, SURGERY_TOKENS) then
		return
			{ l1 = "medicine", l2 = "instrument", l3 = "surgical" },
			{},
			{},
			U.evidence("name_medicine_surgery", 30)
	end
	if U.hasAnyToken(tokens, WOUND_DRESSING_TOKENS) then
		return
			{ l1 = "medicine", l2 = "treatment", l3 = "wound_dressing" },
			{},
			{},
			U.evidence("name_medicine_treatment", 30)
	end
	if U.hasAnyToken(tokens, SPLINT_TOKENS) then
		return
			{ l1 = "medicine", l2 = "treatment", l3 = "splint" },
			{},
			{},
			U.evidence("name_medicine_treatment", 30)
	end
	if U.hasAnyToken(tokens, PAINKILLER_TOKENS) then
		return
			{ l1 = "medicine", l2 = "medication", l3 = "painkiller" },
			{},
			{},
			U.evidence("name_medicine_medication", 30)
	end
	if U.hasAnyToken(tokens, ANTIBIOTIC_TOKENS) then
		return
			{ l1 = "medicine", l2 = "medication", l3 = "antibiotic" },
			{},
			{},
			U.evidence("name_medicine_medication", 30)
	end
	if U.hasAnyToken(tokens, VITAMIN_TOKENS) then
		return
			{ l1 = "medicine", l2 = "medication", l3 = "vitamin" },
			{},
			{},
			U.evidence("name_medicine_medication", 30)
	end
	if U.hasAnyToken(tokens, SEDATIVE_TOKENS) then
		return
			{ l1 = "medicine", l2 = "medication", l3 = "sedative" },
			{},
			{},
			U.evidence("name_medicine_medication", 30)
	end
	if U.hasAnyToken(tokens, INJECTION_TOKENS) then
		return
			{ l1 = "medicine", l2 = "supply", l3 = "injection" },
			{},
			{},
			U.evidence("name_medicine_supply", 30)
	end
	if U.hasAnyToken(tokens, PROTECTIVE_TOKENS) then
		return
			{ l1 = "medicine", l2 = "supply", l3 = "protective" },
			{},
			{},
			U.evidence("name_medicine_supply", 30)
	end

	return nil
end

GlobalStorageSiK.NativeClassifier.registerBlock(classifyMedicine, "medicine")

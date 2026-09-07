--[[
	GlobalStorageSiK - Clasificador de bloque: Conocimiento/medios (último recurso)
	Autor: SiK
	Fecha: 2026-08-27

	dev15 (hallazgo de sistemas sobre dev14): "una regla funcional fuerte
	debe poder vencer al comodín genérico de ItemType" - `base:literature`
	confirmado sin palabra de conocimiento real (ver
	GS_NativeClassifierKnowledgeMedia.lua) ya NO se clasifica ahí, para que
	Supervivencia/Agricultura y cualquier otro bloque de identidad más
	específico lo reclamen primero (bolsas de semillas, principalmente).

	Este bloque es el ÚLTIMO RECURSO honesto: si NINGÚN otro bloque de
	identidad reclamó el tipo Y el motor confirma `ItemType=base:literature`,
	es más correcto decir "es literatura, sin más detalle" que dejarlo en
	`unclassified_modded` cuando el motor ya nos dio una respuesta real.
	Registrado al final de todos los bloques de identidad, junto a
	Contenedores y Materiales (débil) - ver GS_NativeClassifier.lua para el
	orden real.
]]

require "GS_NativeClassifierApi"
require "GS_NativeClassifierUtils"

local U = GlobalStorageSiK.NativeClassifierUtils

---@param fullType string
---@param si table|nil
---@return table|nil primaryPath
---@return table|nil facets
---@return table|nil attributes
---@return table|nil evidence
local function classifyKnowledgeFallback(fullType, si)
	if not si then return nil end
	if U.itemTypeLower(si) ~= "base:literature" then return nil end
	return { l1 = "knowledge_media", l2 = "literature", l3 = nil }, {}, {}, U.evidence("script_item_type_fallback", 100)
end

GlobalStorageSiK.NativeClassifier.registerBlock(classifyKnowledgeFallback, "knowledge_fallback")

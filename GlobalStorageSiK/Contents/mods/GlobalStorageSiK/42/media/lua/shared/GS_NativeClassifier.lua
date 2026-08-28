--[[
	GlobalStorageSiK - Agregador de la taxonomia nativa (orden de precedencia real)
	Autor: SiK
	Fecha: 2026-08-27

	SEPARADO de GS_NativeClassifierApi.lua en dev8 (hallazgo de sistemas:
	avisos "recursive require" en consola) - este fichero SOLO requiere el
	contrato (Api) y, en el ORDEN CORRECTO, cada bloque de clasificacion
	concreto. Nada de este fichero se requiere entre sí en sentido
	contrario: cada bloque requiere GS_NativeClassifierApi (nunca este
	agregador), así que cargar este fichero nunca puede volver a disparar su
	propia carga - mismo patron ya resuelto para GS_ContextMenu.lua/
	GS_TerminalUI_Api.lua.

	Requerir ESTE fichero (no GS_NativeClassifierApi.lua a secas) desde
	cualquier consumidor (GS_Server.lua, GS_NativeAudit.lua) es lo que
	garantiza que los 9 bloques estén realmente registrados antes de
	sellar - GS_NativeClassifierApi.lua por sí sola no conoce ningún bloque.

	BUG REAL evitado a proposito (pedido explicito del usuario, mismo motivo
	que registerBlock/sealBlocks en el Api): el ORDEN DE REGISTRO decide que
	bloque "gana" cuando un objeto encaja en mas de uno (el primero que
	reclama un fullType se queda con el, ver computeClassification en el
	Api). Los objetos propios de GS (grupo blindado) se registran primero de
	todos - su identidad exacta por fullType es la evidencia mas fuerte
	posible y nunca deberia competir con heuristicas de tag/nombre de otro
	bloque.

	REORDENADO 2026-08-27 (dev6, hallazgo real de sistemas sobre dev5):
	Materiales pasa a registrarse EL ULTIMO de todos, no el tercero. El tag
	"base:hasmetal" solo prueba composicion (el objeto contiene metal), nunca
	identidad ("es una materia prima") - con Materiales registrado antes que
	Combate/Herramientas/Medicina/Hogar-ocio, ganaba sistematicamente sobre
	espadas, hachas, armas de fuego, munición, instrumental quirúrgico y
	utensilios de cocina solo porque tambien contienen metal (ver colisiones
	reales de dev5: Base.Sword, Base.Revolver_Long, Base.SutureNeedleBox...).
	La regla real nunca fue "material > arma" en el sentido de composicion -
	era "un objeto que es GENUINAMENTE materia prima gana sobre una
	clasificacion de arma por casualidad" - y Materiales, tal y como estaba,
	no distinguia una cosa de la otra. Con Materiales al final, solo reclama
	lo que NINGUN otro bloque de identidad (herramienta/arma/medicina/hogar)
	ya reclamo - vuelve a ser un autentico catch-all de materia prima, no un
	competidor de identidad.

	dev7 (hallazgo de sistemas): "MetalBar"/"SteelBar" son materia prima real
	pero el motor tambien permite golpear con ellos (WeaponCategory.BLUNT) -
	Combate los reclamaba antes. Solucion: identidad exacta y curada a mano
	(confianza 90, GS_NativeClassifierMaterialsConfirmed.lua), registrada
	ANTES que Combate/Herramientas - nunca reordenar Materiales(debil) de
	vuelta, seguiria ganando sobre Sword/Axe/Revolver por accidente.
]]

require "GS_NativeClassifierApi"

-- dev9 (2 bloques nuevos, pedido explicito: "añade los bloques restantes,
-- mejor hacerlo mal e ir arreglando que dejarlo bloqueado" - Alimentos y
-- Conocimiento/medios estaban "bloqueados" solo para su version de ALTA
-- confianza, nunca para una primera pasada por nombre honesta). Registrados
-- justo tras Herramientas: Alimentos resuelve "comida en un recipiente"
-- antes de que Hogar-ocio la reclame como menaje; Conocimiento/medios
-- resuelve "revista de radio" antes de que Electronica la reclame como
-- comunicacion.
require "GS_NativeClassifierOwnItems"
require "GS_NativeClassifierClothing"
require "GS_NativeClassifierMaterialsConfirmed"
require "GS_NativeClassifierTools"
require "GS_NativeClassifierFood"
require "GS_NativeClassifierKnowledgeMedia"
require "GS_NativeClassifierMedicine"
require "GS_NativeClassifierHomeLeisure"
require "GS_NativeClassifierSurvival"
require "GS_NativeClassifierCombat"
-- BUG REAL cerrado (2026-08-27, dev11 → dev12, hallazgo de sistemas):
-- Contenedores se registro justo tras Hogar-ocio en dev11 - un clasificador
-- generico y debil por nombre ("bag"/"box"/"bottle"...) ROBABA
-- identidades mas especificas registradas DESPUES de el: bolsas de
-- semillas a Agricultura (Supervivencia), cajas de municion a Combate,
-- sacos de dormir/cajas de trampas a Supervivencia, cajas de utilidad a
-- Vehiculos (Supervivencia/Electronica/Vehiculos comparten fichero, ver
-- GS_NativeClassifierSurvival.lua) - eso explico tambien que la cobertura
-- de municion por tag bajara de 27 a 9 en la auditoria real. Reordenado
-- al FINAL de todos los bloques de identidad, justo antes de Materiales
-- (debil) - un contenedor generico solo deberia reclamar lo que NINGUN
-- otro bloque de identidad mas especifico ya reclamo, mismo criterio ya
-- aplicado a Materiales desde dev6.
require "GS_NativeClassifierContainers"
-- dev15 (hallazgo de sistemas): ultimo recurso para base:literature
-- confirmado que NINGUN otro bloque de identidad (incluida Supervivencia/
-- Agricultura arriba) reclamo - ver cabecera de GS_NativeClassifierKnowledgeFallback.lua.
require "GS_NativeClassifierKnowledgeFallback"
require "GS_NativeClassifierMaterials"

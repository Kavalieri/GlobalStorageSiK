--[[
	GlobalStorageSiK - Clasificador de bloque: objetos propios (grupo 14, blindado)
	Autor: SiK
	Fecha: 2026-08-27

	Cubre el grupo L1 "globalstoragesik" (§5 grupo 14, §7 regla de blindaje):
	disquetes, disquetera, periféricos de addon y sus componentes de
	fabricación, y el Soldador. Coincidencia por fullType EXACTO (confianza
	90 per §6, atada al catalogFingerprint actual - una excepción exacta no
	es certeza permanente, puede quedar obsoleta tras una actualización).

	Registrado ANTES que Herramientas/Materiales/Combate (pedido explícito:
	precedencia herramienta/material > arma no debe competir con esto -
	nuestros propios objetos nunca deberían coincidir con ningún tag de
	arma/herramienta/material real, pero la identidad exacta es la evidencia
	más fuerte posible y debe decidir primero de todos modos).
]]

require "GS_NativeClassifierApi"
require "GS_NativeClassifierUtils"

local U = GlobalStorageSiK.NativeClassifierUtils

--- fullType exacto -> { l2, l3, facets adicionales opcionales }
local EXACT = {
	-- Disquetes
	["GlobalStorageSiK.GS_FloppyDisk_Blank"] = { l2 = "floppy_disk", l3 = "blank" },
	["GlobalStorageSiK.GS_FloppyDisk"] = { l2 = "floppy_disk", l3 = "recorded" },
	["GlobalStorageSiK.GS_FloppyDisk_Uninstall"] = { l2 = "floppy_disk", l3 = "recorded" },
	["GlobalStorageSiK.GS_FloppyDisk_DriveInstall"] = { l2 = "floppy_disk", l3 = "recorded" },
	["GSSiK_Addon_Craft.GS_FloppyDisk_Craft"] = { l2 = "floppy_disk", l3 = "recorded" },
	["GSSiK_Addon_Tablet.GS_FloppyDisk_Tablet"] = { l2 = "floppy_disk", l3 = "recorded" },
	["GSSiK_Addon_Builder.GS_FloppyDisk_Builder"] = { l2 = "floppy_disk", l3 = "recorded" },

	-- Periféricos - Disquetera (unidad + componentes propios)
	["GlobalStorageSiK.GS_TerminalReader"] = { l2 = "peripheral", l3 = "floppy_drive", role = "unit" },
	["GlobalStorageSiK.GS_ReaderCasing"] = { l2 = "peripheral", l3 = "floppy_drive", role = "component" },
	["GlobalStorageSiK.GS_ReaderCircuit"] = { l2 = "peripheral", l3 = "floppy_drive", role = "component" },
	["GlobalStorageSiK.GS_ReaderAntenna"] = { l2 = "peripheral", l3 = "floppy_drive", role = "component" },

	-- Periféricos - Impresora 3D
	["GSSiK_Addon_Craft.GS_Printer3D"] = { l2 = "peripheral", l3 = "printer_3d", role = "unit" },
	["GSSiK_Addon_Craft.GS_Printer3D_Frame"] = { l2 = "peripheral", l3 = "printer_3d", role = "component" },
	["GSSiK_Addon_Craft.GS_Printer3D_ExtruderHead"] = { l2 = "peripheral", l3 = "printer_3d", role = "component" },
	["GSSiK_Addon_Craft.GS_Printer3D_ControlBoard"] = { l2 = "peripheral", l3 = "printer_3d", role = "component" },

	-- Periféricos - Antena WiFi (tier como atributo, nunca L3 aparte)
	["GSSiK_Addon_Tablet.GS_WifiAntenna"] = { l2 = "peripheral", l3 = "wifi_antenna", role = "unit", tier = "1" },
	["GSSiK_Addon_Tablet.GS_WifiAntenna_T2"] = { l2 = "peripheral", l3 = "wifi_antenna", role = "unit", tier = "2" },
	["GSSiK_Addon_Tablet.GS_WifiAntenna_T3"] = { l2 = "peripheral", l3 = "wifi_antenna", role = "unit", tier = "3" },
	["GSSiK_Addon_Tablet.GS_WifiAntenna_Dish"] = { l2 = "peripheral", l3 = "wifi_antenna", role = "component" },
	["GSSiK_Addon_Tablet.GS_WifiAntenna_Transmitter"] = { l2 = "peripheral", l3 = "wifi_antenna", role = "component" },
	-- tier añadido dev18 (hallazgo de sistemas: "T1/T2/T3 tienen mapping
	-- pero el código no les asigna explícitamente tier" - mismo atributo ya
	-- usado en las unidades GS_WifiAntenna* de arriba, nunca L3 aparte).
	["GSSiK_Addon_Tablet.GS_WifiChip_T1"] = { l2 = "peripheral", l3 = "wifi_antenna", role = "component", tier = "1" },
	-- T2/T3 añadidos dev17 (hallazgo de sistemas: "diez objetos del addon
	-- Tablet todavia sin clasificar" - completa el mapping ya existente
	-- de T1, mismo l2/l3/role, sin inventar ningun nivel nuevo).
	["GSSiK_Addon_Tablet.GS_WifiChip_T2"] = { l2 = "peripheral", l3 = "wifi_antenna", role = "component", tier = "2" },
	["GSSiK_Addon_Tablet.GS_WifiChip_T3"] = { l2 = "peripheral", l3 = "wifi_antenna", role = "component", tier = "3" },

	-- dev17 (hallazgo de sistemas): hardware funcional del addon Tablet -
	-- nuevo L2 "access_device"/L3 "tablet" (§13, propuesta de sistemas).
	-- Las 4 tabletas son la unidad; pantalla/módulos/núcleo son sus
	-- componentes de fabricación propios. variant añadido dev18 (hallazgo
	-- de sistemas: distinguir las 4 unidades sin depender del nombre
	-- traducido ni crear un nivel nuevo).
	["GSSiK_Addon_Tablet.GS_Tablet"] = { l2 = "access_device", l3 = "tablet", role = "unit", variant = "base" },
	["GSSiK_Addon_Tablet.GS_TabletCraft"] = { l2 = "access_device", l3 = "tablet", role = "unit", variant = "craft" },
	["GSSiK_Addon_Tablet.GS_TabletBuilder"] = { l2 = "access_device", l3 = "tablet", role = "unit", variant = "builder" },
	["GSSiK_Addon_Tablet.GS_TabletMaster"] = { l2 = "access_device", l3 = "tablet", role = "unit", variant = "master" },
	["GSSiK_Addon_Tablet.GS_Tablet_Screen"] = { l2 = "access_device", l3 = "tablet", role = "component" },
	["GSSiK_Addon_Tablet.GS_TabletCraft_Module"] = { l2 = "access_device", l3 = "tablet", role = "component" },
	["GSSiK_Addon_Tablet.GS_TabletBuilder_Module"] = { l2 = "access_device", l3 = "tablet", role = "component" },
	["GSSiK_Addon_Tablet.GS_TabletMaster_Core"] = { l2 = "access_device", l3 = "tablet", role = "component" },
	-- Batería añadida dev18 (hallazgo de sistemas: "GS_Tablet_Battery sigue
	-- en Electrónica genérica pese a ser componente funcional conocido de
	-- la tableta" - mismo criterio de blindaje que pantalla/módulos/núcleo).
	["GSSiK_Addon_Tablet.GS_Tablet_Battery"] = { l2 = "access_device", l3 = "tablet", role = "component" },

	-- dev17 (hallazgo de sistemas, §13.1: "piezas GS, resultado final
	-- vanilla" - confirmado via globalstoragesik_items.txt/recetas/
	-- GS_PCAcquire.lua/GS_LootDistributions.lua: estas 4 piezas se
	-- fabrican/consiguen para construir Base.Mov_DesktopComputer, un
	-- ordenador VANILLA - nunca crear un "terminal_computer" propio de GS,
	-- eso no existe. Van al mismo subgrupo "Fabricación" que el Soldador,
	-- como componentes, nunca como unidad).
	["GlobalStorageSiK.GS_PC_Tower"] = { l2 = "manufacturing", l3 = "computer_components", role = "component" },
	["GlobalStorageSiK.GS_Motherboard"] = { l2 = "manufacturing", l3 = "computer_components", role = "component" },
	["GlobalStorageSiK.GS_Keyboard"] = { l2 = "manufacturing", l3 = "computer_components", role = "component" },
	["GlobalStorageSiK.GS_IODevice"] = { l2 = "manufacturing", l3 = "computer_components", role = "component" },

	-- Periféricos - Pizarra digital
	["GSSiK_Addon_Builder.GS_DigitalWhiteboard"] = { l2 = "peripheral", l3 = "digital_whiteboard", role = "unit" },
	["GSSiK_Addon_Builder.GS_DigitalWhiteboard_Frame"] = { l2 = "peripheral", l3 = "digital_whiteboard", role = "component" },
	["GSSiK_Addon_Builder.GS_DigitalWhiteboard_Screen"] = { l2 = "peripheral", l3 = "digital_whiteboard", role = "component" },
	["GSSiK_Addon_Builder.GS_DigitalWhiteboard_Stylus"] = { l2 = "peripheral", l3 = "digital_whiteboard", role = "component" },

	-- Fabricación - Soldador (nombre elegido para no ser redundante con el
	-- grupo L1 general "tools"/Herramientas - este es el equipo con el que
	-- GS fabrica sus propios periféricos).
	["GlobalStorageSiK.GS_SolderingIron"] = { l2 = "manufacturing", l3 = "soldering_iron", role = "unit" },
	["GlobalStorageSiK.GS_SolderingTip"] = { l2 = "manufacturing", l3 = "soldering_iron", role = "component" },
	["GlobalStorageSiK.GS_SolderingResistance"] = { l2 = "manufacturing", l3 = "soldering_iron", role = "component" },
	["GlobalStorageSiK.GS_SolderingHandle"] = { l2 = "manufacturing", l3 = "soldering_iron", role = "component" },
}

---@param fullType string
---@param si table|nil script item (sin usar aqui - coincidencia solo por fullType)
---@return table|nil primaryPath
---@return table|nil facets
---@return table|nil attributes
---@return table|nil evidence
local function classifyOwnItems(fullType, si)
	local entry = EXACT[fullType]
	if not entry then return nil end
	local facets = {}
	local attributes = {}
	if entry.role then facets[entry.role] = true end
	if entry.tier then attributes.tier = entry.tier end
	if entry.variant then attributes.variant = entry.variant end
	return
		{ l1 = "globalstoragesik", l2 = entry.l2, l3 = entry.l3 },
		facets,
		attributes,
		U.evidence("exact_fulltype_own_item", 90)
end

GlobalStorageSiK.NativeClassifier.registerBlock(classifyOwnItems, "own_items")

-- Expuesta SOLO para diagnostico (GS_NativeAudit.lua: expectedExactMappings/
-- missingExactMappings) - nunca para que otro clasificador de bloque decida
-- nada a partir de ella, la unica fuente de verdad para clasificar sigue
-- siendo classifyOwnItems() de arriba.
---@return table<string, table> fullType -> entrada { l2, l3, role, tier }
function GlobalStorageSiK.NativeClassifier.getOwnItemsExactTable()
	return EXACT
end

--[[
	GlobalStorageSiK - Utilidades compartidas
	Autor: SiK
	Fecha: 2025-06-23
	Descripción: Identificación y validación de contenedores del mundo.
]]

require "GS_Config"

GlobalStorageSiK.Utils = {}

--- Numero de contenedores reales de un objeto del mundo. La inmensa mayoria
--- de muebles tiene 1, pero algunos (mueble con 2+ contenedores definidos en
--- las propiedades del sprite, ver ISMoveableSpriteProps.lua/createContainersFromSpriteProperties
--- del propio juego) exponen varios via getContainerByIndex - antes de este
--- soporte, obj:getContainer() en esos casos SOLO devolvia (o no) el primero,
--- dejando el resto invisibles para nuestro escaneo (reportado: nevera+congelador
--- combinados en un mismo mueble, el segundo compartimento nunca se detectaba).
---@param obj IsoObject
---@return number
function GlobalStorageSiK.Utils.getContainerCount(obj)
	if not obj then
		return 0
	end
	if obj.getContainerCount then
		local ok, n = pcall(function() return obj:getContainerCount() end)
		if ok and n and n > 0 then
			return n
		end
	end
	if obj.getContainer and obj:getContainer() then
		return 1
	end
	return 0
end

--- Contenedor de un objeto por indice (0-based, igual que getContainerByIndex
--- vanilla). Con containerIndex nil se asume 0 (contenedor "principal"),
--- igual que el comportamiento previo de este fichero.
---@param obj IsoObject
---@param containerIndex number|nil
---@return ItemContainer|nil
function GlobalStorageSiK.Utils.getContainerByIndex(obj, containerIndex)
	if not obj then
		return nil
	end
	containerIndex = containerIndex or 0
	if obj.getContainerByIndex then
		local ok, container = pcall(function() return obj:getContainerByIndex(containerIndex) end)
		if ok and container then
			return container
		end
	end
	if containerIndex == 0 and obj.getContainer then
		return obj:getContainer()
	end
	return nil
end

--- Genera un identificador estable para un contenedor de un objeto.
--- IMPORTANTE: con containerIndex nil o 0 devuelve EXACTAMENTE el mismo
--- string que antes de soportar multi-contenedor (sin sufijo) - no huerfana
--- entradas ya guardadas en partidas existentes, que siempre referenciaban
--- el contenedor 0. El sufijo "_cN" solo aparece para el segundo contenedor
--- en adelante, un caso que antes era directamente invisible para el mod.
---@param obj IsoObject
---@param containerIndex number|nil
---@return string|nil
function GlobalStorageSiK.Utils.getContainerId(obj, containerIndex)
	if not obj then
		return nil
	end
	containerIndex = containerIndex or 0

	local container = GlobalStorageSiK.Utils.getContainerByIndex(obj, containerIndex)
	if not container then
		return nil
	end

	local square = obj:getSquare()
	if not square then
		return nil
	end

	local x = square:getX()
	local y = square:getY()
	local z = square:getZ()
	local sprite = obj:getSprite() and obj:getSprite():getName() or "unknown"

	local id = string.format("%d_%d_%d_%s_%s", x, y, z, tostring(obj:getObjectIndex()), sprite)
	if containerIndex > 0 then
		id = id .. "_c" .. tostring(containerIndex)
	end
	return id
end

--- Comprueba si un objeto del mundo tiene inventario (1 o mas contenedores).
---@param obj IsoObject
---@return boolean
function GlobalStorageSiK.Utils.isStorageObject(obj)
	return GlobalStorageSiK.Utils.getContainerCount(obj) > 0
end

--- Obtiene un contenedor de un objeto o nil. Sin containerIndex, el contenedor
--- 0 (comportamiento identico al de antes del soporte multi-contenedor).
---@param obj IsoObject
---@param containerIndex number|nil
---@return ItemContainer|nil
function GlobalStorageSiK.Utils.getObjectContainer(obj, containerIndex)
	return GlobalStorageSiK.Utils.getContainerByIndex(obj, containerIndex or 0)
end

--- Sugiere un nombre legible por tipo de contenedor (Nevera, Congelador, Estanteria...)
--- cuando el objeto del mundo no tiene nombre propio (obj:getName() vacio).
--- Reutiliza la clave vanilla IGUI_ContainerTitle_<tipo> (mismo patron que
--- GS_DepositSources.describeContainer, ya probado en la UI de fuentes de deposito).
--- Recibe containerIndex para poder distinguir "Nevera" de "Congelador" cuando
--- ambos compartimentos viven en el mismo objeto del mundo.
---@param obj IsoObject
---@param containerIndex number|nil
---@return string
function GlobalStorageSiK.Utils.detectContainerTypeName(obj, containerIndex)
	local container = GlobalStorageSiK.Utils.getObjectContainer(obj, containerIndex)
	if container and container.getType then
		local ok, typeKey = pcall(function() return container:getType() end)
		if ok and typeKey and typeKey ~= "" then
			local key = "IGUI_ContainerTitle_" .. tostring(typeKey)
			local ok2, label = pcall(getText, key)
			if ok2 and label and label ~= key then
				return label
			end
		end
	end
	local T = GlobalStorageSiK.I18n and GlobalStorageSiK.I18n.text or getText
	return T("IGUI_GS_GenericContainerName")
end

--- Crea una entrada serializable para la red. containerIndex identifica QUE
--- contenedor de este objeto representa la entrada (0 = principal, el unico
--- caso que existia antes de soportar objetos con varios contenedores) - se
--- guarda en la propia entrada para que GS_Network.findWorldObject/getLiveContainers
--- y GS_Server.resolveNodeContents sepan a que compartimento exacto volver.
---@param obj IsoObject
---@param containerIndex number|nil
---@return table|nil
function GlobalStorageSiK.Utils.buildContainerEntry(obj, containerIndex)
	containerIndex = containerIndex or 0
	local id = GlobalStorageSiK.Utils.getContainerId(obj, containerIndex)
	local square = obj:getSquare()
	if not id or not square then
		return nil
	end

	local name = obj:getName()
	if not name or name == "" then
		name = GlobalStorageSiK.Utils.detectContainerTypeName(obj, containerIndex)
	end

	return {
		id = id,
		x = square:getX(),
		y = square:getY(),
		z = square:getZ(),
		name = name,
		containerIndex = containerIndex,
	}
end

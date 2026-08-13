--[[
	GlobalStorageSiK - Espejo INI del catálogo (servidor)
	Autor: SiK
	Fecha: 2026-06-28
	Descripción: Copia legible del registro ModData en Lua/ del save para depuración y respaldo.
]]

require "GS_Config"
require "GS_Network"
require "GS_TerminalCatalog"

GlobalStorageSiK.RegistryStore = GlobalStorageSiK.RegistryStore or {}

GlobalStorageSiK.RegistryStore.FILE_NAME = "GlobalStorageSiK/network_catalog.ini"
GlobalStorageSiK.RegistryStore._saveQueued = false

---@param writer BufferedWriter
---@param line string
local function writeLine(writer, line)
	if writer and writer.write then
		writer:write(tostring(line) .. "\r\n")
	end
end

--- Escribe catálogo de redes/terminales en INI (servidor / SP host).
function GlobalStorageSiK.RegistryStore.saveNow()
	if not isServer or not isServer() or not getFileWriter then
		return
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	if not registry or not registry.networks then
		return
	end
	local writer = getFileWriter(GlobalStorageSiK.RegistryStore.FILE_NAME, true, false)
	if not writer then
		return
	end
	writeLine(writer, "; GlobalStorageSiK — catálogo de redes (generado automáticamente)")
	writeLine(writer, "; Fuente autoritativa: ModData " .. tostring(GlobalStorageSiK.MODDATA_KEY))
	writeLine(writer, "schema=1")
	writeLine(writer, "savedMs=" .. tostring((getTimestampMs and getTimestampMs()) or 0))
	local count = 0
	for networkId, net in pairs(registry.networks) do
		count = count + 1
		writeLine(writer, "")
		writeLine(writer, "[network:" .. tostring(networkId) .. "]")
		writeLine(writer, "name=" .. tostring(net.name or ""))
		writeLine(writer, "owner=" .. tostring(net.owner or ""))
		writeLine(writer, "ownerAccount=" .. tostring(net.ownerAccount or ""))
		if net.relocation and net.relocation.status then
			writeLine(writer, "relocation=" .. tostring(net.relocation.status))
		end
		local entries = GlobalStorageSiK.TerminalCatalog.collectEntries(net)
		writeLine(writer, "terminalCount=" .. tostring(#entries))
		for i = 1, #entries do
			local t = entries[i]
			writeLine(writer, string.format(
				"terminal_%d=%d,%d,%d,%s,%s",
				i, t.x, t.y, t.z or 0,
				t.controller and "controller" or "secondary",
				tostring(t.catalogStatus or "registered")
			))
		end
	end
	writeLine(writer, "")
	writeLine(writer, "[meta]")
	writeLine(writer, "networkCount=" .. tostring(count))
	writer:close()
end

--- Programa guardado diferido (evita escribir en cada tick).
function GlobalStorageSiK.RegistryStore.scheduleSave()
	-- CRITICO corregido: "not isServer()" bloqueaba el guardado del registro
	-- COMPLETO (redes, zonas, terminales) en singleplayer real, donde
	-- isServer() da false (ver GlobalStorageSiK.isAuthoritative en
	-- GS_Config.lua) - nada de lo creado en una partida de un jugador se
	-- llegaba a persistir nunca en disco.
	if not GlobalStorageSiK.isAuthoritative() then
		return
	end
	if GlobalStorageSiK.RegistryStore._saveQueued then
		return
	end
	GlobalStorageSiK.RegistryStore._saveQueued = true
	local function onTick()
		GlobalStorageSiK.RegistryStore._saveQueued = false
		if Events and Events.OnTick then
			Events.OnTick.Remove(onTick)
		end
		GlobalStorageSiK.RegistryStore.saveNow()
	end
	if Events and Events.OnTick then
		Events.OnTick.Add(onTick)
	end
end

--- Llamar tras cambios en el registro de redes/terminales.
function GlobalStorageSiK.RegistryStore.notifyChanged()
	GlobalStorageSiK.RegistryStore.scheduleSave()
end

if Events and Events.OnInitGlobalModData then
	Events.OnInitGlobalModData.Add(function()
		if GlobalStorageSiK.isAuthoritative() then
			GlobalStorageSiK.RegistryStore.scheduleSave()
		end
	end)
end

--[[
	GlobalStorageSiK - Suspensión del registro al recoger el ordenador
	Autor: SiK
	Fecha: 2025-06-24
	Descripción: Único método de instalación soportado: lector + disquete
	sobre un PC ya en el mapa (ver GS_InstallTerminalReader.lua /
	GS_Server.lua "installTerminalReader"). Este fichero ya no coloca ni
	registra nada al colocar - eso lo hace directamente el comando de
	instalación. Solo queda la contraparte: cuando el objeto físico se quita
	del mundo (recogido), avisa al registro para suspender esa entrada,
	igual sea el objeto que sea (detección puramente por coordenada, ver
	GS_TerminalAccess.isTerminalObject).
]]

require "GS_TerminalAccess"
require "GS_TerminalRegistry"
require "GS_Network"

GlobalStorageSiK.TerminalPlace = GlobalStorageSiK.TerminalPlace or {}

--- Suspende red al recoger terminal del mundo.
---@param object IsoObject|nil
local function onObjectAboutToBeRemoved(object)
	if not object or not GlobalStorageSiK.TerminalAccess then
		return
	end
	if not GlobalStorageSiK.TerminalAccess.isTerminalObject(object) then
		return
	end
	local sq = object.getSquare and object:getSquare() or nil
	if not sq then
		return
	end
	local x, y, z = sq:getX(), sq:getY(), sq:getZ()
	local nid = GlobalStorageSiK.Network and GlobalStorageSiK.Network.findNetworkIdAtTerminal(x, y, z)
	-- isAuthoritative() (no isServer() a pelo): en SP real isServer() da
	-- false y esta rama nunca se ejecutaba - la red nunca se marcaba como
	-- "suspendida" al recoger el terminal en partidas de un jugador.
	if GlobalStorageSiK.isAuthoritative() and GlobalStorageSiK.TerminalRegistry then
		GlobalStorageSiK.TerminalRegistry.suspendTerminalAt(nid, x, y, z)
	elseif not GlobalStorageSiK.isAuthoritative() and GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		local payload = { x = x, y = y, z = z }
		if nid then
			payload.gsnNetworkId = nid
		end
		GlobalStorageSiK.NetClient.sendCommand("suspendTerminal", payload)
	end
end

if Events and Events.OnObjectAboutToBeRemoved then
	Events.OnObjectAboutToBeRemoved.Add(onObjectAboutToBeRemoved)
end

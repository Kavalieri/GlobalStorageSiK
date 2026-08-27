--[[
	GlobalStorageSiK - Limpieza de UI de terminal al morir (cliente)
	Autor: SiK
	Fecha: 2026-08-26

	BUG REAL cerrado (revision tecnica de Desarrollo tras probar en TEST,
	prueba real "morir y reclamar"): no existia ningun Events.OnPlayerDeath
	en el lado cliente que cerrara/destruyera la interfaz del terminal. Si el
	jugador moria con la ventana abierta (principal o bloqueada), podian
	sobrevivir hacia la vida siguiente: GS_TerminalUI.instance, la ventana
	bloqueada y sus widgets, los probes periodicos de GS_TerminalAccessGuard/
	TerminalBlockedPanel, pendingTerminalOpen/cachedTerminalState, sesion de
	terminal y cola de transferencias, resaltados de mundo/nodo, y
	referencias al IsoPlayer ya muerto - una vida nueva heredaba estado de
	la anterior sin haberlo pedido. Encaja con bloqueos previos ya vistos con
	la ventana de terminal abierta durante una muerte.

	GS_TerminalUI:onClose() (GS_TerminalUI.lua) YA hace practicamente toda
	esta limpieza (notifica cierre al servidor, limpia sesion/cola de
	transferencias/resaltados) - simplemente nunca se llamaba al morir. Este
	fichero solo se encarga de dispararlo de forma fiable en el momento
	correcto, y de limpiar el resto de estado global que onClose() no cubre
	porque vive fuera de la instancia de ventana.
]]

require "GS_TerminalUI_Api"
require "GS_NetClient"
require "GS_AdminDashboard"

-- DIAGNOSTICO DIRIGIDO (2026-08-26, pedido explicito del usuario: "dejarlo
-- listo para un diagnostico completo" ante el riesgo de que el cuelgue de
-- cliente ya visto en TEST vuelva a reproducirse): esta funcion solo
-- registraba en log cuando onClose() fallaba, nunca el progreso normal - si
-- el cliente se congela DENTRO de esta limpieza, no habria forma de saber
-- en que paso exacto se detuvo solo mirando el log. Traza por etapas,
-- SIEMPRE visible (no gateada por Modo depuracion, a proposito: si vuelve a
-- colgarse no se puede pedir activar debug de antemano) - cada paso se
-- registra ANTES de ejecutarse, asi que la ULTIMA linea "stage=X" que
-- aparezca en el log es el paso que se estaba ejecutando cuando el cliente
-- dejo de responder. Un "deathCleanupDone" final confirma que la limpieza
-- entera termino sin colgarse.
---@param stage string
local function trace(stage)
	if GlobalStorageSiK.Log then
		GlobalStorageSiK.Log.warn("TerminalUI", "deathCleanupStage stage=" .. tostring(stage))
	end
end

--- Solo actua sobre la muerte del jugador LOCAL - Events.OnPlayerDeath
--- tambien se dispara al ver morir a otro jugador en MP, y tocar la UI
--- propia por la muerte de otro seria un error.
---@param player IsoPlayer
local function onPlayerDeath(player)
	trace("start")
	local localPlayer = GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.getPlayer
		and GlobalStorageSiK.NetClient.getPlayer()
	if not localPlayer or player ~= localPlayer then
		trace("skipped_not_local_player")
		return
	end
	-- BUG REAL cerrado (2026-08-26, revision tecnica de Desarrollo): orden
	-- anterior mandaba identityDeath DESPUES de onClose()/limpieza - si
	-- onClose() es precisamente el punto que se cuelga (sospecha real, ver
	-- FullMapSyncB42), el servidor nunca llega a recibir la muerte y la
	-- propiedad queda huerfana otra vez. player:isDead() ya se comprueba en
	-- servidor, adelantar el envio no reduce seguridad alguna.
	trace("send_identityDeath")
	if GlobalStorageSiK.NetClient and GlobalStorageSiK.NetClient.sendCommand then
		GlobalStorageSiK.NetClient.sendCommand("identityDeath", {})
	end
	-- BUG REAL DE CICLO cerrado definitivamente en origen (2026-08-27, ver
	-- GS_ItemNetworkTooltip.lua): el wrapper de tooltip ya no se reinstala
	-- nunca por reclamo periodico de posicion exterior ni se desmonta al
	-- morir - se instala UNA SOLA VEZ por sesion (o se delega por completo en
	-- TooltipLib si esta presente) y usa una guarda de reentrada propia, asi
	-- que ninguna vida nueva puede dejarlo atrapado en un ciclo con otro mod.
	-- Ya no hace falta ningun paso de desmontaje aqui.
	trace("onClose_begin")
	local ui = GlobalStorageSiK.TerminalUI and GlobalStorageSiK.TerminalUI.instance
	if ui and ui.onClose then
		local ok, err = pcall(function() ui:onClose() end)
		if not ok and GlobalStorageSiK.Log then
			GlobalStorageSiK.Log.error("TerminalUI", "deathCleanupOnCloseFailed", tostring(err))
		end
	end
	trace("onClose_end")
	-- BUG REAL cerrado (2026-08-26, revision tecnica de Desarrollo tras
	-- probar dev13 en TEST, confirmado por capturas: el panel de soporte
	-- seguia abierto DURANTE la muerte, la pantalla de personaje muerto, la
	-- creacion de la nueva vida y despues de entrar con ella - y seguia
	-- pidiendo adminListNetworks/adminGetNetworkMembers todo ese rato).
	-- Ninguna ventana del panel de soporte (staff) se cerraba al morir -
	-- coincide temporalmente con varios "SpriteRenderer RingBuffer overrun"
	-- en las pruebas, sin poder demostrar causalidad todavia, pero mantener
	-- una interfaz con referencias a un IsoPlayer ya destruido operando
	-- sobre otro personaje nuevo es un riesgo real por si mismo. Se cierran
	-- las 3 ventanas del panel de soporte igual que la del terminal.
	trace("close_admin_dashboard")
	local memberEditor = GlobalStorageSiK.AdminDashboard and GlobalStorageSiK.AdminDashboard.memberEditorInstance
	if memberEditor and memberEditor.destroy then
		pcall(function() memberEditor:destroy() end)
	end
	local history = GlobalStorageSiK.AdminDashboard and GlobalStorageSiK.AdminDashboard.historyInstance
	if history and history.destroy then
		pcall(function() history:destroy() end)
	end
	local dashboard = GlobalStorageSiK.AdminDashboard and GlobalStorageSiK.AdminDashboard.instance
	if dashboard and dashboard.destroy then
		pcall(function() dashboard:destroy() end)
	end
	-- Estado global fuera de la instancia de ventana - onClose() solo lo
	-- limpia si habia una instancia viva; una muerte con la ventana ya
	-- cerrada (o bloqueada sin instancia principal) podia dejarlo huerfano.
	trace("clear_global_state")
	if GlobalStorageSiK.Client then
		GlobalStorageSiK.Client.pendingTerminalOpen = false
		GlobalStorageSiK.Client.cachedTerminalState = nil
	end
	trace("clear_highlights")
	if GlobalStorageSiK.NodeHighlight and GlobalStorageSiK.NodeHighlight.clear then
		GlobalStorageSiK.NodeHighlight.clear()
	end
	if GlobalStorageSiK.WorldHighlight and GlobalStorageSiK.WorldHighlight.clearAll then
		GlobalStorageSiK.WorldHighlight.clearAll()
	end
	trace("done")
end

Events.OnPlayerDeath.Add(onPlayerDeath)

--[[
	GlobalStorageSiK - Lanza la acción temporizada de instalar terminal SiK
	Autor: SiK
	Descripción: Punto de entrada único, llamado tanto desde el menú
	contextual del disquete como desde el botón "Instalar aquí" de la
	pantalla de terminal bloqueado - MISMA acción, sin abrir ningún diálogo
	antes. El proceso es: 1) acción cronometrada (instalar el programa en
	el ordenador), 2) al completarse, SOLO ENTONCES se abre el diálogo de
	elegir red nueva/existente (GS_TerminalInstallReaderChoice) - igual que
	el método antiguo (craftear/instalar primero, elegir red después), en
	vez del orden anterior (elegir red antes de esperar la acción).

	Nombre heredado, aclaración: lo que se "instala" es el DISQUETE (su
	programa se vuelca sobre el ordenador ya colocado en el mapa, ver
	target.object) - el lector es solo un requisito de inventario (hardware
	necesario para poder usar el disquete), no lo que se instala. El punto de
	entrada se llama "InstallTerminalReader" por motivos históricos, no
	porque el lector sea el objeto de la instalación.
]]

require "TimedActions/ISTimedActionQueue"
require "TimedActions/GS_InstallTerminalReaderAction"
require "GS_Sandbox"

GlobalStorageSiK.InstallTerminalReader = {}

--- Duración de instalación, configurable por sandbox (GS_Sandbox.
--- getTerminalInstallTime) - compartida por el core y por cualquier addon
--- que instale su propio disquete sobre un terminal, asi que se expone como
--- funcion (lee el valor actual en cada llamada) en vez de una constante
--- fija capturada una sola vez al cargar el fichero.
---@return number
function GlobalStorageSiK.InstallTerminalReader.getInstallTime()
	return GlobalStorageSiK.Sandbox.getTerminalInstallTime()
end

---@param player IsoPlayer|nil
---@param target table { x, y, z, object }
function GlobalStorageSiK.InstallTerminalReader.begin(player, target)
	player = player or getPlayer()
	if not player or not target or not target.x then
		return
	end
	local action = GS_InstallTerminalReaderAction:new(player, target)
	ISTimedActionQueue.add(action)
end

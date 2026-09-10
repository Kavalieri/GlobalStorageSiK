--[[
	GlobalStorageSiK - Mecánica de "programar" disquetes
	Descripción: Convierte un GS_FloppyDisk_Blank (disquete en blanco) en un
	disquete con el programa elegido, entregado al inventario del jugador.
	Grabar no instala ni modifica componentes del terminal.
	Accesible desde el panel de crafteo vanilla (craftRecipe "Program GS
	Uninstall Disk", solo pide el disquete en blanco + la receta aprendida)
	y desde el propio disquete en blanco por clic derecho > Global Storage
	(GS_ItemActions.lua), donde además se exige un terminal cerca - esa
	comprobación es NUESTRA, la receta vanilla no la conoce. La entrega real
	del disquete programado la hace SIEMPRE esta función (validada en
	servidor, ver GS_Server.lua comando "programDisk"), igual que
	GS_PCAcquire.craft / GS_ReaderAcquire.craft.
]]

require "GS_Config"
require "GS_Sandbox"
require "GS_InventorySync"
require "GS_CraftUtils"
require "GS_TerminalAccess"

GlobalStorageSiK.DiskProgramming = {}

GlobalStorageSiK.DiskProgramming.BLANK_DISK = "GlobalStorageSiK.GS_FloppyDisk_Blank"

--- Cada entrada define un "programa" grabable: la receta que hay que
--- conocer (enseñada por manualItem) y el item resultante. Los addons
--- registran los suyos en tiempo de carga via registerProgram() (ver mas
--- abajo) en vez de escribirse aqui a mano, igual que el resto de APIs de
--- registro desacoplada del Core (GS_TerminalAccess, GS_ItemActions, etc.).
GlobalStorageSiK.DiskProgramming.PROGRAMS = {
	network = {
		id = "network",
		recipeName = "Program GS Network Disk",
		manualItem = "GlobalStorageSiK.GS_Manual_NetworkDisk_DiskProgram",
		outputItem = "GlobalStorageSiK.GS_FloppyDisk",
		menuTextKey = "IGUI_GS_ProgramNetworkDiskMenu",
		titleKey = "IGUI_GS_ProgramNetworkDiskTitle",
		iconPath = "media/textures/Item_GS_FloppyDisk.png",
		descKey = "IGUI_GS_ProgramNetworkDiskDesc",
	},
	uninstall = {
		id = "uninstall",
		recipeName = "Program GS Uninstall Disk",
		manualItem = "GlobalStorageSiK.GS_Manual_DiskPrograms",
		outputItem = "GlobalStorageSiK.GS_FloppyDisk_Uninstall",
		menuTextKey = "IGUI_GS_ProgramUninstallDiskMenu",
		titleKey = "IGUI_GS_ProgramUninstallDiskTitle",
		iconPath = "media/textures/Item_GS_UninstallDisk.png",
		descKey = "IGUI_GS_ProgramUninstallDiskDesc",
	},
	driveinstall = {
		id = "driveinstall",
		recipeName = "Program GS Floppy Drive Network Disk",
		manualItem = "GlobalStorageSiK.GS_Manual_DriveInstall_DiskProgram",
		outputItem = "GlobalStorageSiK.GS_FloppyDisk_DriveInstall",
		menuTextKey = "IGUI_GS_ProgramDriveInstallDiskMenu",
		titleKey = "IGUI_GS_ProgramDriveInstallDiskTitle",
		iconPath = "media/textures/Item_GS_FloppyDisk_DriveInstall.png",
		descKey = "IGUI_GS_ProgramDriveInstallDiskDesc",
	},
}

GlobalStorageSiK.DiskProgramming._programOwners =
	GlobalStorageSiK.DiskProgramming._programOwners or {
		network = "core",
		uninstall = "core",
		driveinstall = "core",
	}
GlobalStorageSiK.DiskProgramming._programGenerations =
	GlobalStorageSiK.DiskProgramming._programGenerations or {}
GlobalStorageSiK.DiskProgramming._addonProgramIds =
	GlobalStorageSiK.DiskProgramming._addonProgramIds or {}

local PROGRAM_FIELDS = {
	"id", "recipeName", "manualItem", "outputItem", "menuTextKey",
	"iconPath", "descKey", "titleKey",
}

local function validProgramString(value, limit)
	return type(value) == "string" and value ~= "" and #value <= limit
end

local function copyProgram(def, explicitId)
	if type(def) ~= "table" then return nil end
	local programId = explicitId or def.id
	if not validProgramString(programId, 64)
		or not string.match(programId, "^[A-Za-z0-9_.%-]+$")
		or not validProgramString(def.recipeName, 192)
		or not validProgramString(def.manualItem, 128)
		or not validProgramString(def.outputItem, 128)
		or not validProgramString(def.menuTextKey, 128)
		or not validProgramString(def.iconPath, 256)
		or not validProgramString(def.descKey, 128)
		or (def.titleKey ~= nil and not validProgramString(def.titleKey, 128))
		or string.find(def.iconPath, "..", 1, true)
		or string.sub(def.iconPath, 1, 1) == "/"
		or string.find(def.iconPath, ":", 1, true) then
		return nil
	end
	local copy = {}
	for index = 1, #PROGRAM_FIELDS do
		local field = PROGRAM_FIELDS[index]
		copy[field] = def[field]
	end
	copy.id = programId
	return copy
end

function GlobalStorageSiK.DiskProgramming._prepareAddonProgram(addonId, def)
	if not validProgramString(addonId, 64) then
		return false, "ERR_SCHEMA", nil
	end
	if def == nil then return true, "OK", nil end
	if type(def) ~= "table" then return false, "ERR_SCHEMA", nil end
	local prepared = copyProgram(def)
	if not prepared then return false, "ERR_SCHEMA", nil end
	local owner = GlobalStorageSiK.DiskProgramming._programOwners[prepared.id]
	if owner ~= nil and owner ~= addonId then
		return false, "ERR_PROGRAM_ID_CONFLICT", nil
	end
	return true, "OK", prepared
end

function GlobalStorageSiK.DiskProgramming._commitAddonProgram(addonId, generation, prepared)
	local previousId = GlobalStorageSiK.DiskProgramming._addonProgramIds[addonId]
	if previousId and (not prepared or previousId ~= prepared.id)
		and GlobalStorageSiK.DiskProgramming._programOwners[previousId] == addonId then
		GlobalStorageSiK.DiskProgramming.PROGRAMS[previousId] = nil
		GlobalStorageSiK.DiskProgramming._programOwners[previousId] = nil
		GlobalStorageSiK.DiskProgramming._programGenerations[previousId] = nil
	end
	if not prepared then
		GlobalStorageSiK.DiskProgramming._addonProgramIds[addonId] = nil
		return true
	end
	GlobalStorageSiK.DiskProgramming.PROGRAMS[prepared.id] = copyProgram(prepared)
	GlobalStorageSiK.DiskProgramming._programOwners[prepared.id] = addonId
	GlobalStorageSiK.DiskProgramming._programGenerations[prepared.id] = generation
	GlobalStorageSiK.DiskProgramming._addonProgramIds[addonId] = prepared.id
	return true
end

function GlobalStorageSiK.DiskProgramming._removeAddonProgramIfGeneration(addonId, generation)
	local programId = GlobalStorageSiK.DiskProgramming._addonProgramIds[addonId]
	if not programId
		or GlobalStorageSiK.DiskProgramming._programOwners[programId] ~= addonId
		or GlobalStorageSiK.DiskProgramming._programGenerations[programId] ~= generation then
		return false
	end
	GlobalStorageSiK.DiskProgramming.PROGRAMS[programId] = nil
	GlobalStorageSiK.DiskProgramming._programOwners[programId] = nil
	GlobalStorageSiK.DiskProgramming._programGenerations[programId] = nil
	GlobalStorageSiK.DiskProgramming._addonProgramIds[addonId] = nil
	return true
end

--- Punto de registro para que cada addon aporte su propio disco programable
--- (mismos campos que las entradas de arriba, incluidos iconPath/descKey
--- para la tarjeta visual de la pestaña Programación) sin que el Core tenga
--- que conocer sus nombres de antemano.
---@param id string
---@param def table { recipeName, manualItem, outputItem, menuTextKey, iconPath, descKey }
function GlobalStorageSiK.DiskProgramming.registerProgram(id, def)
	local prepared = copyProgram(def, id)
	if not prepared or GlobalStorageSiK.DiskProgramming._programOwners[id] == "core" then
		return false
	end
	GlobalStorageSiK.DiskProgramming.PROGRAMS[id] = prepared
	GlobalStorageSiK.DiskProgramming._programOwners[id] = "legacy"
	return true
end

---@param player IsoPlayer|nil
---@param programId string
---@return boolean
function GlobalStorageSiK.DiskProgramming.knowsProgram(player, programId)
	local def = GlobalStorageSiK.DiskProgramming.PROGRAMS[programId]
	if not def or not player then
		return false
	end
	return GlobalStorageSiK.CraftUtils.knowsRecipe(player, def.recipeName)
end

--- Terminal de red conocido a rango (misma comprobación que usa el metodo
--- de instalacion por disquete - ver GS_TerminalAccess.findNearestKnownComputer).
---@param player IsoPlayer|nil
---@return boolean
function GlobalStorageSiK.DiskProgramming.terminalInRange(player)
	if not player or not GlobalStorageSiK.TerminalAccess or not GlobalStorageSiK.TerminalAccess.findNearestKnownComputer then
		return false
	end
	local range = GlobalStorageSiK.Sandbox.getTerminalProximityRange()
	return GlobalStorageSiK.TerminalAccess.findNearestKnownComputer(player, range) ~= nil
end

-- The contextual route also bootstraps the first network: a compatible
-- computer need not already be a GS terminal. The portable reader is a
-- prerequisite, never a reason to expose the installed-terminal tab.
function GlobalStorageSiK.DiskProgramming.contextReadiness(player)
	if not player or (player.isDead and player:isDead()) then return false, "invalid" end
	local access = GlobalStorageSiK.TerminalAccess
	local target = access.findNearestKnownComputer(player,
		GlobalStorageSiK.Sandbox.getTerminalProximityRange())
	if not target then return false, "terminal" end
	local anchor = { x = target.x, y = target.y, z = target.z }
	local networkId
	if target.alreadyInstalled then
		networkId = GlobalStorageSiK.Network.findNetworkIdAtTerminal(anchor.x, anchor.y, anchor.z)
		if not networkId or not GlobalStorageSiK.Permissions.canAccess(player, networkId) then
			return false, "terminal"
		end
	end
	local addons = GlobalStorageSiK.Addons
	if not addons or not addons.hasReaderAvailable
		or not addons.hasReaderAvailable(player, networkId, anchor) then
		return false, "reader"
	end
	return true, nil
end

--- Graba un programa en un disquete en blanco. SOLO se llama en el servidor
--- (o SP autoritativo); vuelve a validar todo, nunca confía en lo que dijo
--- el cliente.
---@param player IsoPlayer
---@param programId string
---@return boolean ok
---@return string|nil reason "invalid"|"book"|"terminal"|"materials"|"output"
local function recordProgram(player, programId, itemId)
	local def = GlobalStorageSiK.DiskProgramming.PROGRAMS[programId]
	if not GlobalStorageSiK.isAuthoritative() or not player or not def
		or (player.isDead and player:isDead()) then
		return false, "invalid"
	end
	if not GlobalStorageSiK.DiskProgramming.knowsProgram(player, programId) then
		return false, "book"
	end
	local inv = player:getInventory()
	if not inv then
		return false, "invalid"
	end
	local disk
	if itemId ~= nil then
		if type(itemId) ~= "number" or itemId ~= itemId or math.abs(itemId) > 9007199254740991
			or itemId ~= math.floor(itemId) then return false, "invalid" end
		-- Context menus queue the vanilla transfer first. An explicit item must
		-- be this exact disk in this player's main inventory; never substitute.
		disk = inv:getItemWithID(itemId)
		if not disk or disk:getContainer() ~= inv
			or disk:getFullType() ~= GlobalStorageSiK.DiskProgramming.BLANK_DISK then
			return false, "materials"
		end
	else
		local containers = GlobalStorageSiK.CraftUtils.collectIngredientContainers(player)
		disk = GlobalStorageSiK.CraftUtils.findItemTypeNearby(player,
			GlobalStorageSiK.DiskProgramming.BLANK_DISK, containers)
	end
	if not disk then return false, "materials" end
	local replaced, _, replaceReason = GlobalStorageSiK.CraftUtils.replaceItemsWithOutput(player,
		{ disk }, def.outputItem)
	if not replaced then
		return false, replaceReason == "materials" and "materials" or "output"
	end
	return true, nil
end

function GlobalStorageSiK.DiskProgramming.program(player, programId, itemId)
	if not GlobalStorageSiK.isAuthoritative() then return false, "invalid" end
	local ready, reason = GlobalStorageSiK.DiskProgramming.contextReadiness(player)
	if not ready then return false, reason end
	return recordProgram(player, programId, itemId)
end

-- Terminal UI commands bind the installed peripheral to the exact captured
-- network/anchor. Standalone disk recipes retain their original requirements.
function GlobalStorageSiK.DiskProgramming.programAtTerminal(player, programId, context)
	if not GlobalStorageSiK.isAuthoritative() or not player or type(context) ~= "table"
		or type(context.networkId) ~= "string" or context.networkId == ""
		or #context.networkId > 192 or type(context.terminalAnchor) ~= "table" then
		return false, "terminal"
	end
	local anchor = context.terminalAnchor
	for _, axis in ipairs({ "x", "y", "z" }) do
		local value = anchor[axis]
		if type(value) ~= "number" or value ~= value or value == math.huge
			or value == -math.huge or value ~= math.floor(value) then return false, "terminal" end
	end
	local access = GlobalStorageSiK.TerminalAccess
	local sessionAnchor = access.getSessionAnchor(player)
	if access.getSessionNetworkId(player) ~= context.networkId or type(sessionAnchor) ~= "table"
		or sessionAnchor.x ~= anchor.x or sessionAnchor.y ~= anchor.y or sessionAnchor.z ~= anchor.z
		or not GlobalStorageSiK.Permissions.canAccess(player, context.networkId) then
		return false, "terminal"
	end
	local registry = GlobalStorageSiK.Network.getRegistry()
	local network = registry.networks and registry.networks[context.networkId]
	local record = network and GlobalStorageSiK.TerminalRecord.findAt(network, anchor.x, anchor.y, anchor.z)
	if not GlobalStorageSiK.TerminalRecord.isActive(record) then return false, "terminal" end
	local installs = network.addonInstalls and network.addonInstalls[GlobalStorageSiK.Addons.anchorKey(anchor)]
	if type(installs) ~= "table" or (installs.Reader ~= true and type(installs.Reader) ~= "table") then
		return false, "reader"
	end
	local allowed, mode, hint = access.evaluate(player, context.networkId, anchor,
		{ ignoreSession = true, strictDistance = true })
	-- evaluate may fall back to another terminal; it cannot authorize this one.
	if not allowed or (mode ~= "bypass" and (not hint or hint.x ~= anchor.x
		or hint.y ~= anchor.y or hint.z ~= anchor.z)) then return false, "terminal" end
	return recordProgram(player, programId)
end

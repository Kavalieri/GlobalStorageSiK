--[[
	GlobalStorageSiK - (DEPRECADO v1.3.36) Instalación del Lector en red
	Autor: SiK
	Descripción: Retirado - el Lector (antes gestionado aqui, en su propia
	tabla net.floppyDriveInstalls) es ahora una entrada mas del
	AddonRegistry (ver GS_ReaderAddon.lua) y usa el mismo GS_Addons.install/
	uninstall/isInstalled que Tablet/Craft/Builder, en vez de su propio
	sistema aparte. Los datos historicos de net.floppyDriveInstalls (partidas
	con el Lector ya instalado antes de esta version) se migran una sola vez
	a net.addonInstalls[key]["Reader"] - ver GS_NetworkMigrate.runV1080.
	Fichero dejado vacio (no require de ningun otro sitio) en vez de
	borrado, por si algo externo llegara a requerirlo todavia.
]]

GlobalStorageSiK.FloppyDriveNetwork = GlobalStorageSiK.FloppyDriveNetwork or {}

# GlobalStorageSiK

Documentación para desarrolladores: [API de addons](docs/ADDON_API.md) · [diagnóstico y logs](docs/DEBUGGING.md)

Mod de Project Zomboid (Build 42) que añade almacenamiento de red compartido entre contenedores/terminales.

## Estructura del repositorio

- `GlobalStorageSiK/` — mod Core (obligatorio, publicado en [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3750612158))
- `addons/` — addons opcionales que extienden el Core:
  - `GSSiK_Addon_Craft/` — crafteo remoto desde el almacén de red
  - `GSSiK_Addon_Builder/` — construcción remota desde el almacén de red
  - `GSSiK_Addon_Tablet/` — acceso al almacén de red desde una tablet portátil

Cada carpeta contiene el `Contents/` tal y como lo requiere el juego para cargar el mod (`mod.info`, `media/`, etc.).

## Contribuir

Las incidencias y sugerencias son bienvenidas vía Issues. Si vas a proponer un cambio, ten en cuenta que los addons dependen del Core mediante una API pública expuesta en `GlobalStorageSiK.CraftSession` (ver `GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_NetworkCraftSession.lua`).

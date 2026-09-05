# GlobalStorageSiK

Documentación para desarrolladores: [API pública de producto](docs/GSSIK_API.md) · [contrato de addons](docs/ADDON_API.md) · [framework SiK UI](docs/SIK_UI_API.md) · [inventario de arquitectura y API](docs/ARCHITECTURE_AND_API_INVENTORY.md) · [diagnóstico y logs](docs/DEBUGGING.md)

Mod de Project Zomboid (Build 42) que añade almacenamiento de red compartido entre contenedores/terminales.

## Estructura del repositorio

- `GlobalStorageSiK/` — mod Core (obligatorio, publicado en [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3750612158))
- `addons/` — addons opcionales que extienden el Core:
  - `GSSiK_Addon_Craft/` — crafteo remoto desde el almacén de red
  - `GSSiK_Addon_Builder/` — construcción remota desde el almacén de red
  - `GSSiK_Addon_Tablet/` — acceso al almacén de red desde una tablet portátil

Cada carpeta contiene el `Contents/` tal y como lo requiere el juego para cargar el mod (`mod.info`, `media/`, etc.).

## Contribuir

Las incidencias y sugerencias son bienvenidas vía Issues. Los addons e
integraciones consumen la API pública `GSSiK.API`, documentada en
[`docs/GSSIK_API.md`](docs/GSSIK_API.md). La sesión compartida de Craft y
Builder se expone como `GSSiK.API.WorkSession`; el antiguo
`GlobalStorageSiK.CraftSession` no es una API pública.

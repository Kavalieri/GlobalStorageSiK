# GlobalStorageSiK — directrices para Codex

Leer también las instrucciones del workspace y el `CLAUDE.md` más cercano antes de editar.

## Frontera Core/addons

- El Core es un enlace neutral: autoridad SP/MP, red, registro, sesiones, claim/return y eventos públicos.
- Cada addon posee sus hooks vanilla o de terceros, reglas de éxito/fallo, UI, textos, traducciones, opciones sandbox y diagnóstico.
- Los addons consumen únicamente `GlobalStorageSiK.AddonApi` y `GlobalStorageSiK.CraftSession`; no leen ni mutan estado privado del Core.
- Si falta una capacidad, añadir la primitiva pública mínima y reutilizable. No trasladar al Core conocimiento de Craft, Builder, Neat Crafting, Neat Building o Project Cook.
- Todo cambio de contrato actualiza juntos implementación, consumidores, `docs/ADDON_API.md`, validación y estas instrucciones.

## Concurrencia y release

- Antes de delegar, declarar objetivo, archivos/subsistema en propiedad, interfaces permitidas y validacion esperada. Dividir por responsabilidades independientes; nunca compartir simultaneamente un hotspot.
- El propietario de la API o contrato compartido coordina e integra a sus consumidores. Todo hallazgo que cambie contrato, riesgo, version o archivos comunes se comunica inmediatamente.
- Cada responsable entrega archivos tocados, resultado, comprobaciones, limites y riesgos. El responsable principal revisa el diff integrado y es el unico que decide commit/deploy/publicacion con la autorizacion requerida.
- Revisar `git status` y el diff antes de tocar hotspots. No sobrescribir cambios ajenos ni usar staging global durante trabajo paralelo.
- Un solo propietario simultáneo para `GS_Server.lua`, `GS_Config.lua`, `GS_NetworkCraftSession.lua`, `mod.info`, traducciones y contratos compartidos.
- Core usa `GlobalStorageSiK.isAuthoritative()`; SP real no se detecta con `isServer()`.
- No usar `print()` suelto. Core usa sus categorías de log; cada addon usa su logger y su sandbox propios.
- Versiones, metadata, patchnotes, JSON y Lua se validan antes de deploy. Steam y GitHub se publican solo con autorización explícita.

Referencia pública: [API de addons](docs/ADDON_API.md) y [diagnóstico](docs/DEBUGGING.md).

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
- Cada prueba DEV enumera el debug mínimo con los nombres sandbox exactos en español e inglés, el evento esperado y los logs a conservar. `>>> DETALLE / >>> DETAIL` solo se activa de forma dirigida.
- Toda línea indica `[CLI]`, `[SRV]`, `[HOST]` o `[SP]`. El relé neutral del dedicado se mantiene acotado y documentado; un addon decide sus categorías y solo solicita la suscripción mediante la API pública.
- Actualizar `docs/DEBUGGING.md` cuando cambien opciones, niveles, orígenes o ejemplos.
- Versiones, metadata, patchnotes, JSON y Lua se validan antes de deploy. Steam y GitHub se publican solo con autorización explícita.
- Para sintaxis, invocar el ejecutable Lua local por ruta absoluta y pasar cada ruta normalizada directamente a `-e "assert(loadfile('<ruta>'))"`. No usar `arg[1]` con `-e`: ese runtime no lo define y genera falsos fallos masivos sin evaluar archivos. Confirmar además que el binario arrancó; un error de ruta de PowerShell no cuenta como `FAILED=0`.

## Transferencias y trabajos incrementales

- Cada `InventoryItem`/`itemId` es exactamente una unidad física transferible. `InventoryItem:getCount()` puede contener multiplicadores de script o receta y nunca se usa para contar, agregar, dividir o confirmar inventario de red. Una cantidad N se resuelve como N itemId reales; no se fabrican porciones con `split()`/`setCount()`.
- Depósito, retirada y Auto Sort usan micro-lotes internos fijos; su tamaño no se expone en sandbox ni se acepta desde el cliente.
- Solo puede existir una petición en vuelo por cola lógica. Toda respuesta lleva un ID de operación y únicamente el propietario de esa cola puede consumirla o avanzar el siguiente lote.
- Una continuación debe demostrar progreso monótono. Los fallos ya resueltos no vuelven a encolarse; los IDs todavía no inspeccionados sí pueden formar el siguiente lote.
- Todo trabajo tiene condición terminal por éxito, fallo, cancelación, falta de progreso o timeout acotado. Al quedar sin trabajo debe retirar su `Events.OnTick`; nunca dejar polling latente esperando un ID o respuesta que quizá no llegue.
- No reenviar a ciegas operaciones no idempotentes. En retirada y depósito parcial, una respuesta perdida termina como timeout informado para evitar mover dos veces; el depósito por ID puede reintentarse solo de forma acotada porque el servidor ya no encuentra en origen un ID movido.
- Los locks son por red y se mantienen solo durante el micro-lote. Redes distintas pueden progresar de forma intercalada y una red ocupada no espera indefinidamente.

Referencia pública: [API de addons](docs/ADDON_API.md) y [diagnóstico](docs/DEBUGGING.md).

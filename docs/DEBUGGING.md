# Diagnóstico y logs

Los logs de diagnóstico están desactivados por defecto y no cambian la partida. La única excepción es el relé de servidor dedicado, que está preparado por defecto pero no transmite nada mientras el logger correspondiente siga apagado. No debe existir ningún `print()` suelto fuera de la implementación de un logger o del receptor que imprime una línea remota ya formada.

## Cómo leer una línea

```text
[12.3s][CLI] [GlobalStorageSiK:DEBUG:Network] requestManifest START networkId=...
[12.4s][SRV] [GlobalStorageSiK:DEBUG:Network] requestManifest END networkId=...
[12.5s][SRV] [GlobalStorageSiK:SYSTEM:Router] DETAIL sublog enabled category=Router; high-volume output may fill console.txt; use only for targeted diagnostics
```

- `[CLI]`: proceso de cliente remoto.
- `[SRV]`: proceso de servidor dedicado. La marca se conserva cuando la línea aparece en el `console.txt` del cliente.
- `[HOST]`: proceso que actúa como cliente y servidor en una partida alojada.
- `[SP]`: partida de un jugador; no usa transporte de red para duplicar sus propias líneas.
- `DEBUG`: evento resumido apto para una sesión de diagnóstico normal.
- `DETAIL`: sublog de alto volumen. Siempre está apagado por defecto y emite antes una advertencia `SYSTEM`.

El relé del dedicado agrupa y limita las líneas antes de enviarlas. No vuelve a envolverlas ni las registra una segunda vez. Aun así, no se deben activar sublogs `DETAIL` sin una prueba dirigida.

Los mensajes de diagnóstico son exclusivamente de consola. Nunca deben usar el halo sobre el personaje: ese espacio se reserva para progreso y resultados funcionales, cancelaciones y fallos que el jugador debe ver sin abrir el log. Los errores funcionales se muestran en rojo y durante más tiempo; comandos internos como `pingTerminalAccess`, payloads y comprobaciones periódicas permanecen en `console.txt` aunque el modo debug esté activo.

Al iniciar una partida, cada proceso escribe siempre una única identidad de runtime: `[CLI] [GlobalStorageSiK:SYSTEM:RuntimeIdentity] client | version=X.Y.Z-devN` en cliente y `[SRV] ... server | version=X.Y.Z-devN` en dedicado (`[SP]`/`[HOST]` según corresponda). No requiere opciones sandbox y permite confirmar el árbol efectivo antes de interpretar una prueba. La instalación DEV genera además `%USERPROFILE%\Zomboid\.sik-dev-client-identity.json` con versión, conteos y `sik-tree-sha256-v1` de cada override físico.

## Core

`GlobalStorageSiK.DebugMode` es el interruptor maestro del log general. Las categorías permiten reducir volumen: Network, TerminalAccess, Permissions, Craft, Inventory, Tooltip, Router y el árbol **SiK UI** (ver más abajo). Las opciones `DebugSkip*` están en la página separada **GSSiK: Excepciones para pruebas / GSSiK: Testing overrides** porque alteran validaciones; no son opciones de logging.

### Evidencias por sesión

Las ejecuciones diagnósticas se aíslan bajo `Lua/SiKDiagnostics/GlobalStorageSiK/<sessionId>/`. La sesión permanece estable durante el proceso y cada ejecución recibe un `runId` distinto, de modo que repetir una prueba no sobrescribe la anterior:

```text
taxonomy/audit-<runId>.log
taxonomy/unclassified-<runId>.log
taxonomy/excluded-internal-<runId>.log
taxonomy/corpus-<runId>.log
permissions/permissions-<runId>.log
session.json
```

`session.json` inventaría las evidencias generadas. El panel de staff muestra `sessionId`, `runId`, contadores y rutas relativas envueltas; no transmite el contenido completo de los informes al cliente. `excluded-internal-<runId>.log` contiene la lista completa y ordenada de proxies internos separados de `unclassified`, con la regla estructural aplicada (`BodyLocation=base:zeddmg`). La invariante del informe es `totalTypes = classified + unclassified + excludedInternal + pending + classifierErrors`; `reconciliationDelta` debe ser `0`. Auditoría y corpus no requieren activar categorías sandbox. El fichero de permisos solo se crea cuando están activados `Modo depuración (debug)` / `Debug mode` y `>> Identidad y permisos` / `>> Identity & permissions`. En dedicado, activa además `>> Reenviar logs del dedicado a clientes` / `>> Relay dedicated-server logs to clients` únicamente si necesitas el eco acotado en el cliente.

### Árbol "SiK UI" (dev36)

Antes de dev36 existían tres interruptores sueltos, sin relación visible entre sí: `DebugModeUI` (clics/árbol de widgets/solapes, mecanismo propio distinto del resto), `DebugCatUI` (apertura de ventana + nombrado de nodo, mezclados en una sola categoría) y `DebugCatSearch` (caja de búsqueda). Los tres quedaron **retirados y sustituidos** por un único árbol de categorías `DebugCat`, con el mismo mecanismo estándar que Network/Craft/Inventory/Router, agrupado bajo el prefijo visible "SiK UI:" para poder depurar el framework de interfaz propio (`GS_SiK_UI_Core.lua`, `GS_SiK_UI_Table.lua`, `GS_TerminalUI_Scroll.lua`, `GS_TerminalUI_TabRail.lua`, `GS_TerminalUI_Extensions.lua`) por partes. El nombrado de nodo (`NodeNaming`), al no ser parte del framework visual sino lógica de negocio, pasó a su propia categoría independiente en vez de perderse.

| Clave nueva | Sustituye a | Cubre |
|---|---|---|
| `DebugCatSiKUI` | `DebugModeUI` + la mitad "ventana" de `DebugCatUI` | Clics de botón, apertura/reutilización/refresco de la ventana del terminal, árbol de widgets y solapes (`GS_UIDebug.lua`). Traza general/maestra del framework. |
| `DebugCatSiKUITable` | (nueva, sin logging previo) | Geometría de columnas resuelta por `SiK_UI.Table` (Almacén, Zonas y nodos, Red, Permisos...) — solo cuando el ancho disponible cambia de verdad. |
| `DebugCatSiKUIScroll` | (nueva, sin logging previo) | Motor de scroll/lista virtual compartido: crecimiento del pool de filas y cambios de dataset. |
| `DebugCatSiKUITabs` | (nueva, sin logging previo) | Barra de pestañas lateral + contrato de registro Core/addon: creación/reutilización de panel, visibilidad, clic de activación/cancelación. |
| `DebugCatSiKUISearch` | `DebugCatSearch` | Caja de búsqueda de la pestaña Almacén (bytes vs. caracteres UTF-8 reales — diagnóstico de idiomas no-ASCII). |
| `DebugCatNodeNaming` | mitad "nombrado" de `DebugCatUI` | Aplicación del nombre visible de un contenedor a su objeto en el mundo. |

Al investigar algo de interfaz, activa `Modo depuración` + `DebugCatSiKUI` primero (cubre clics/apertura/solapes); añade la sub-categoría concreta (`Table`/`Scroll`/`Tabs`/`Search`) solo si el problema está claramente en esa pieza — no las actives todas a la vez sin necesidad.

### Glosario de opciones del Core

| Clave | Español / English | Volumen y función |
|---|---|---|
| `DebugMode` | `Modo depuración (debug)` / `Debug mode` | Interruptor maestro. Por sí solo no activa ninguna categoría. |
| `DebugRelayToClients` | `>> Reenviar logs del dedicado a clientes` / `>> Relay dedicated-server logs to clients` | Preparado por defecto. Envía por lotes acotados solo las líneas que otro logger haya activado. |
| `DebugCatNetwork` | `>> Trazas de red` / `>> Network traces` | Resumen de comandos y sincronización. |
| `DebugDetailNetwork` | `>>> DETALLE: payloads completos de red` / `>>> DETAIL: full network payloads` | Payloads completos; alto volumen. |
| `DebugCatTerminalAccess` | `>> Acceso a terminal` / `>> Terminal access` | Manifest, registro, permisos, alcance y apertura. |
| `DebugCatPermissions` | `>> Identidad y permisos` / `>> Identity & permissions` | UUID de personaje, unión acotada de rosters, altas idempotentes y posibles rotaciones de identidad. |
| `DebugCatCraft` | `>> Recetas y crafteo` / `>> Recipes & crafting` | Resumen de recetas y préstamos compartidos. |
| `DebugDetailCraft` | `>>> DETALLE: recetas y préstamos de red` / `>>> DETAIL: recipes and network loans` | Probes y decisiones individuales; alto volumen. |
| `DebugCatInventory` | `>> Inventario y transferencias` / `>> Inventory & transfers` | Depósitos, retiradas, snapshots y trabajos masivos resumidos. |
| `DebugDetailInventory` | `>>> DETALLE: taxonomía y objetos` / `>>> DETAIL: taxonomy and items` | Clasificación por objeto/tipo, consolidación por microlote, render por-frame del tooltip y muestras acotadas de la resolución nativa o vanilla; volumen masivo. |
| `DebugCatTooltip` | `>> Tooltip de red` / `>> Network tooltip` | Instalación/recuperación del hook, fallos y fallback del tooltip de cantidades. No registra cada frame. |
| `DebugCatRouter` | `>> Router` / `>> Router` | Resultado resumido de selección de destino. |
| `DebugDetailRouter` | `>>> DETALLE: enrutado por nodo` / `>>> DETAIL: routing per node` | Tier y capacidad de cada candidato; alto volumen. |
| `DebugCatRuleMigration` | `>> Migración de reglas legacy` / `>> Legacy rule migration` | Clasifica reglas persistidas como nativas, categorías fuente explícitas, vanilla, alias GS, externas retiradas o residuo técnico; conserva hasta tres muestras acotadas de `rules` o `categories`. |
| `DebugCatSiKUI` | `>> SiK UI: clics y widgets` / `>> SiK UI: clicks & widgets` | Clics, apertura/reutilización/refresco de ventana, árbol de widgets y solapes. Traza general del framework — ver árbol "SiK UI" arriba. |
| `DebugCatSiKUITable` | `>> SiK UI: geometría de tabla` / `>> SiK UI: table geometry` | Anchos de columna resueltos por `SiK_UI.Table`; solo al cambiar el ancho disponible. |
| `DebugCatSiKUIScroll` | `>> SiK UI: scroll y lista virtual` / `>> SiK UI: scroll & virtual list` | Pool de filas y cambios de dataset del motor de scroll/lista virtual. |
| `DebugCatSiKUITabs` | `>> SiK UI: pestañas y extensiones` / `>> SiK UI: tabs & extensions` | Registro/reutilización de panel, visibilidad y clic de pestaña. |
| `DebugCatSiKUISearch` | `>> SiK UI: caja de búsqueda` / `>> SiK UI: search box` | Bytes vs. caracteres UTF-8 reales en el cuadro de búsqueda de Almacén. |
| `DebugCatNodeNaming` | `>> Nombrado de terminal` / `>> Terminal naming` | Aplicación del nombre visible de un contenedor a su objeto en el mundo. |

Las líneas del Core usan componente y evento estables. Operaciones largas deben emitir estados significativos, no una línea por tick. Si un estado no cambió, no se repite.

Los reescaneos incrementales de zonas emiten una sola línea `ZoneScanJob complete`. `cookingExcluded` cuenta cámaras de cocción rechazadas durante el barrido y `removedIneligible` las entradas GS antiguas eliminadas del registro; esta limpieza afecta solo a metadata, nunca al contenido físico del aparato:

```text
[12.3s][SRV] [GlobalStorageSiK:INFO:ZoneScanJob] complete network=... durationMs=42 zones=2 nodes=18 instances=530 distinctTypes=47 snapshotRows=82 squares=225 loadedSquares=225 added=1 updated=17 offline=0 cookingExcluded=3 removedIneligible=1 limitHit=false
```

La identidad y sus migraciones pertenecen a `Identidad y permisos / Identity & permissions`. La inicialización, un cambio lógico del roster y cada vínculo reparado emiten líneas acotadas; nunca una línea por tick. El campo `account` procede del `IsoPlayer` autoritativo; los IDs se tratan como opacos y no deben editarse a mano:

```text
[12.3s][SRV] [GlobalStorageSiK:INFO:Permissions] identityMigration | owner network=... account=KavaAccount old=character:7 new=character:gsc_...
[12.4s][SRV] [GlobalStorageSiK:INFO:Permissions] permissionRoster | network=... members=3 online=7 faction=2 candidates=4
[12.5s][SRV] [GlobalStorageSiK:INFO:Permissions] addPermissionUser | source=online_character ... ok=true changed=false reason=already_member
```

`possibleIdentityRotation` significa únicamente que una cuenta/nombre aparece con UUID distintos. Puede representar dos personajes legítimos de la misma cuenta: se registra para revisión, pero jamás fusiona permisos, elimina filas ni transfiere al propietario.

### Prueba DEV: identidades y permisos

Opciones mínimas: `Modo depuración (debug)` / `Debug mode`, `>> Identidad y permisos` / `>> Identity & permissions` y, en dedicado, `>> Reenviar logs del dedicado a clientes` / `>> Relay dedicated-server logs to clients`. No actives ningún sublog `DETALLE / DETAIL`.

Comprueba en dedicado el propietario, un administrador y varios miembros con nombres latinos, chinos, cirílicos y homónimos. La fila visible conserva el nombre exacto del personaje, mientras `characterId` permanece opaco y único. Un miembro de facción conectado aparece una sola vez bajo Facción y conserva su UUID online; uno desconectado mantiene `factionUsername`. Los homónimos con UUID diferentes permanecen y muestran sufijo `[xxxxxx]`. Tras añadir, el UUID desaparece del selector y aparece una sola vez en miembros. Dos clics o dos administradores añadiendo el mismo UUID deben producir una sola mutación; la segunda respuesta será `ok=true changed=false reason=already_member`. Una selección que se desconecta antes del clic debe fallar con `invalid_or_stale_identity`. Conserva `console.txt` del cliente y dedicado.

Repite la presentación y las operaciones esenciales cambiando solo el idioma del cliente entre español, inglés, chino y ruso; añade cualquier otro idioma instalado como pasada de humo. Los UUID, roles, número de candidatos y resultados `ok/changed/reason` deben ser idénticos: únicamente cambia el texto localizado. Reinicia el cliente después de cada cambio de idioma y no reutilices capturas de una sesión anterior.

Si otro mod sustituye `ISToolTipInv.render` después de GS, el vigilante restaura el wrapper exterior y, con `DebugCatTooltip`, deja una única línea resumida:

```text
[12.3s][CLI] [GlobalStorageSiK:DEBUG:ItemNetworkTooltip] hook chain changed; GS outer wrapper restored
```

Para confirmar que un ítem concreto atraviesa el render solo durante un diagnóstico dirigido, activa además `DebugCatInventory` y `DebugDetailInventory`; las líneas resultantes usan el área `ItemNetworkTooltipDetail` y pueden repetirse cada frame.

## Craft y Builder

Cada addon tiene sandbox y logger independientes del Core:

- `DebugMode`: interruptor maestro del addon.
- `DebugOperations`: claims, espera de ACK, inicio, resolución y devolución.
- `DebugLifecycle`: apertura/cierre de UI, sesión e instalación de hooks.

Opciones visibles de Craft y Builder:

| Clave | Español / English | Uso |
|---|---|---|
| `DebugMode` | `Modo debug (Craft/Builder)` / `Debug mode (Craft/Builder)` | Interruptor maestro del addon. |
| `DebugLifecycle` | `>> Interfaz y sesiones` / `>> UI and session lifecycle` | Hooks, apertura/cierre y estado de sesión; volumen normal. |
| `DebugOperations` | `>>> DETALLE: operaciones de crafteo/construcción` / `>>> DETAIL: crafting/building operations` | Claims, ACK, unidades, resultados y devoluciones por `operationId`; alto volumen. |

Tablet solo expone `Modo debug (Tablet) / Debug mode (Tablet)`, de volumen normal. Los tres addons usan el relé neutral del Core cuando está habilitado.

Formato:

```text
[12.3s][CLI] [GSSiK_Addon_Craft:DETAIL][Operations] craftAttempt START operationId=Craft-...
```

El tiempo transcurrido permite medir esperas. `operationId` correlaciona cliente, servidor, claims y resultado; no abras un segundo identificador para el mismo intento.

En un lote correcto, `batchPlan` debe reflejar todas las entradas adicionales, los callbacks avanzan `PROGRESS 1/N` ... `END N/N` y los diagnósticos servidor conservan solo contenedores físicos. Un salto a todos los contenedores visibles de la UI (por ejemplo, `containers=30`) seguido de `resultCreated=false` indica que el panel repobló el `HandcraftLogic` entre acciones. Tras un lote exitoso, `operation_complete_return` debe contener herramientas o sobrantes reales; devolver exactamente los consumibles de una unidad es señal de que hubo un callback sin resultado creado.

### Origen de depósitos y devoluciones

El resumen servidor `depositItems` y su `actionResult.transfer` incluyen `origin`. No se debe inferir el origen solo por cercanía temporal con un timeout:

- `player`: depósito solicitado directamente por el jugador.
- `player_queue`: reintento de la cola iniciada por el jugador.
- `operation_result_deposit`: resultado creado enviado automáticamente a la red.
- `operation_complete_return`: herramienta o sobrante devuelto tras finalizar.
- `operation_abort_return`: préstamo devuelto al abortar o cancelar.
- `network_read_return`: libro, revista u otra literatura devuelta automáticamente a la red original al completar o cancelar la lectura.
- `return stuckActive`: advertencia única cuando una operación lleva cinco minutos sin señal de fin. No mueve objetos; evita que un cronómetro devuelva herramientas durante un lote largo.

Los orígenes de operación llevan también `operationId`. `origin=player`/`player_queue` identifica movimientos pedidos por el jugador; `operation_complete_return` y `operation_abort_return` identifican devoluciones automáticas tras una señal explícita del addon.

### Guardas terminales de transferencias

Las colas cliente usan `queueId` (depósito) o `withdrawId` (retirada). Una respuesta con otro ID se ignora y nunca libera el trabajo activo. Los siguientes mensajes son terminales y no deben repetirse por tick:

- `[CLI] [GlobalStorageSiK:ERROR:TransferQueue] response timeout`: el depósito por ID agotó sus reintentos acotados.
- `[CLI] [GlobalStorageSiK:ERROR:TransferQueue] partial response timeout`: un depósito parcial no se reenvía porque no es idempotente.
- `[CLI] [GlobalStorageSiK:ERROR:TransferQueue] non-progressing response`: el servidor devolvió tantos o más IDs pendientes que en el lote anterior; se corta para evitar bucle.
- `[CLI] [GlobalStorageSiK:ERROR:WithdrawClient] response timeout`: la retirada no se reenvía a ciegas; la cola continúa con el siguiente trabajo tras informar.
- `[SRV] [GlobalStorageSiK:ERROR:RedistributeJob] network remained busy` o `job made no progress`: Auto Sort termina tras espera acotada o cursor estancado.
- `[CLI] [GlobalStorageSiK:DEBUG:RedistributeJob] completed breakdown | tiers=1:12,4:3,5:2 topTypes=Base.Nails:8,...`: resumen acotado al terminar Auto Sort. `tiers` indica el nivel de destino (1=filtro/hoja exacta, 2=subcategoría, 3=categoría, 4=afinidad por `fullType`, 5=afinidad por ruta taxonómica canónica, 6=contenedor libre) y `topTypes` muestra como máximo ocho tipos; no emite una línea por objeto.

Al terminar cualquiera de estos casos, el correspondiente `Events.OnTick` se retira. Para diagnosticarlos activa `Modo depuración (debug)` / `Debug mode` y `>> Inventario y transferencias` / `>> Inventory & transfers`; añade `>> Router` / `>> Router` y `>>> DETALLE: enrutado por nodo` / `>>> DETAIL: routing per node` solo si se investiga la selección de destino.

### Prueba DEV: migración recuperable de reglas legacy

Opciones mínimas: `Modo depuración (debug)` / `Debug mode` y `>> Migración de reglas legacy` / `>> Legacy rule migration`. Mantén apagadas las categorías no relacionadas y todos los sublogs `>>> DETALLE / >>> DETAIL`. En dedicado, añade opcionalmente `>> Reenviar logs del dedicado a clientes` / `>> Relay dedicated-server logs to clients`; conserva siempre el `console.txt` del servidor.

Al abrir por primera vez una red heredada, el servidor emite `legacyRuleSanitizerInspection phase=capture` y hasta tres `legacyRuleSanitizerRecord` antes de mutar. Cada registro acotado identifica `network`, `ownerKind`, `ownerId`, `source`, `ruleIndex`, `op`, `type`, `value`, `nativePath` y `legacyValue`; nunca incluye payloads completos. Después aparecen `legacyRuleSanitizer ... pass=1` con conteos separados `rules=A->B` y `categories=C->D`, seguido de `pass=2` con `changedOwners=0` y `quarantined=0`. La postcondición exige `legacyRuleSanitizerInspection phase=postvalidate ... matches=0` antes de `legacyRuleSanitizerMarker ... version=3 status=written`; si quedan coincidencias, el marcador se retiene con `status=withheld` para permitir reintento. Las entradas retiradas permanecen recuperables y sin duplicados en `legacyJunkRules`, con `legacySource=rules|categories` y `legacyRuleIndex`.

Las claves de proveedores de categorías retirados se conservan literalmente y se marcan `DEPRECATED_EXTERNAL`: siguen visibles para que el editor las sustituya, pero no se interpretan ni participan en routing. Las reglas nuevas llevan procedencia explícita: `NATIVE` para una ruta propia y `SOURCE_CATEGORY` para una categoría segura declarada por el objeto. Un conjunto mínimo de alias GS históricos demostrados se enriquece de forma aditiva con `nativePath` y `legacyValue`; un alias desconocido sigue inactivo. `TECHNICAL_RESIDUE` identifica dimensiones como `B`, `F` o `W`; tampoco puede convertirse en una coincidencia.

### Prueba DEV: leer literatura y devolverla a la red

Opciones mínimas: `Modo depuración (debug)` / `Debug mode` y `>> Inventario y transferencias` / `>> Inventory & transfers`. En dedicado, añade `>> Reenviar logs del dedicado a clientes` / `>> Relay dedicated-server logs to clients`. No hace falta activar ningún sublog `DETALLE / DETAIL`.

Prueba por separado un libro de habilidad, una revista de receta y una revista o periódico normal: abre el menú contextual de la fila de red, elige `Leer y devolver a la red` / `Read and return to network`, deja terminar una lectura y cancela otra. Debe retirarse exactamente una instancia, encolarse la acción vanilla y regresar el mismo `itemId` al mismo nodo físico siempre que siga válido; si no, debe caer al router compartido. Espera `NetworkReadAction read queued`, después `return scheduled` y `return queued ... preferredNodeId=...`; el servidor debe registrar `depositItems origin=network_read_return operationId=Read-... preferredNodeId=...`. Si la devolución no puede encolarse durante 30 segundos, debe quedar una sola línea `return queue timeout`, cesar el `OnTick` y conservarse el objeto en el inventario del jugador. Guarda `console.txt` del cliente y, en dedicado, el del servidor.

### Prueba DEV: afinidad exacta y taxonómica

Opciones mínimas: `Modo depuración (debug)` / `Debug mode`, `>> Inventario y transferencias` / `>> Inventory & transfers` y `>> Router` / `>> Router`. En dedicado, añade `>> Reenviar logs del dedicado a clientes` / `>> Relay dedicated-server logs to clients`. Activa `>>> DETALLE: enrutado por nodo` / `>>> DETAIL: routing per node` solo para una repetición breve: es un sublog de alto volumen.

En una zona con dos contenedores sin categorías, coloca una revista de receta A en el primero y deposita una revista de receta B. Debe aparecer `RESULT tier=5 ... (afinidad de categoría)` si comparten identidad de routing; una copia exacta de B debe ganar tier 4. Repite con `Rechazar depósito sin contenedor adecuado` / `Reject deposit without a matching container` activado: tiers 4 y 5 siguen permitidos; un objeto sin afinidad ni filtro debe quedar en el inventario con `RESULT no_match`. Ejecuta Auto Sort con la misma disposición y comprueba que usa los mismos tiers y que no mueve un objeto que ya está en el mejor destino. Conserva `console.txt` del cliente y del dedicado.

### Prueba DEV: requisitos y montaje del lector/PC

Opciones mínimas: `Modo depuración (debug)` / `Debug mode` y `Recetas y crafteo` / `Recipes & crafting`. En dedicado, añade `Reenviar logs del dedicado a clientes` / `Relay dedicated-server logs to clients`. Mantén apagados todos los sublogs `DETALLE / DETAIL`.

Prueba el lector con tres distribuciones: todos los requisitos en el inventario principal, todos en contenedores físicos cercanos y una mezcla entre inventario, mochila equipada y contenedor. El modal y el servidor deben coincidir; debe aparecer una única salida, consumirse cada pieza de su origen real y conservarse soldador y destornillador. Repite retirando una pieza durante la barra: debe fallar con `reason=materials`, no crear salida y no consumir las demás. El evento esperado es `[SRV] [GlobalStorageSiK:INFO:Acquire] reader result | ok=true reason=success` o el motivo resumido del fallo. Repite al menos el caso mixto con el PC (`pc result`) y un disquete en blanco cercano (`program disk result`). Guarda `console.txt` del cliente y del servidor; en SP la marca será `[SP]` y no habrá relé.

## Reglas de emisión

- Agrupa en una línea los campos pequeños del mismo evento.
- Divide payloads extensos o listas grandes en cabecera + bloques acotados.
- No repitas estados por tick. Registra la entrada al estado y el cambio siguiente.
- No registres dos veces el mismo evento solo porque atraviesa un wrapper; distingue `START`, `WAIT`, `RESUME`, `END` y `ABORT`.
- Los errores incluyen motivo resumido y `operationId`; no vuelques objetos Java completos.
- Los logs compartidos de `CraftSession` se enrutan al sink del addon activo. Core no adopta categorías o textos específicos de Craft/Builder.

## Informe útil para reproducir

Indica versión de Core/addon, SP/host/dedicado/cliente, UI vanilla o mod externo, receta/objeto y el bloque completo desde `START` hasta `END` o `ABORT`. Para problemas de red, el `console.txt` del cliente puede contener conjuntamente `[CLI]` y `[SRV]` si el relé estaba habilitado; conserva también el log dedicado si está disponible.

Cada plan de pruebas DEV debe indicar, para cada caso, los nombres visibles exactos en español e inglés de las opciones mínimas que hay que activar. Debe dejar todos los demás sublogs apagados, señalar el prefijo o evento esperado y enumerar los ficheros que se deben conservar. `DETAIL` solo se usa cuando el caso necesita ese nivel.

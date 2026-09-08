# Diagnóstico y logs

Los logs de diagnóstico y el relé están desactivados por defecto. El servidor permite suscribirse y recibir únicamente a administradores; revalida en cada envío y elimina la suscripción al perder acceso o desconectarse. No debe existir ningún `print()` suelto fuera del logger o del receptor de una línea remota ya formada.

## Cómo leer una línea

```text
[12.3s][CLI] [GlobalStorageSiK:DEBUG:Network] requestManifest START networkId=...
[12.4s][SRV] [GlobalStorageSiK:DEBUG:Network] requestManifest END networkId=...
```

- `[CLI]`: proceso de cliente remoto.
- `[SRV]`: proceso de servidor dedicado. La marca se conserva cuando la línea aparece en el `console.txt` del cliente.
- `[HOST]`: proceso que actúa como cliente y servidor en una partida alojada.
- `[SP]`: partida de un jugador; no usa transporte de red para duplicar sus propias líneas.
- `DEBUG`: evento resumido apto para una sesión de diagnóstico normal.
- `DETAIL`: retirado; los valores heredados no reactivan sus emisores. Las categorías normales permanecen acotadas.

El relé del dedicado agrupa y limita las líneas, sin envolverlas ni duplicarlas. Requiere activación explícita y cuenta de administrador.

El diagnóstico pertenece exclusivamente a consola. El halo se reserva para errores funcionales relevantes, breves y no bloqueantes; progreso, éxito, información y cancelación se muestran en la UI propia. Capacidad es peso/encumbrance vanilla: se distingue el inventario del jugador del contenedor destino, no una cuadrícula espacial.

Al iniciar una partida, cada proceso escribe siempre una única identidad de runtime: `[CLI] [GlobalStorageSiK:SYSTEM:RuntimeIdentity] client | version=X.Y.Z-devN` en cliente y `[SRV] ... server | version=X.Y.Z-devN` en dedicado (`[SP]`/`[HOST]` según corresponda). No requiere opciones sandbox y permite confirmar el árbol efectivo antes de interpretar una prueba. La instalación DEV genera además `%USERPROFILE%\Zomboid\.sik-dev-client-identity.json` con versión, conteos y `sik-tree-sha256-v1` de cada override físico.

## Core

`GlobalStorageSiK.DebugMode` es el interruptor maestro del log general. Las categorías permiten reducir volumen: Network, TerminalAccess, Permissions, Craft, Inventory, Tooltip, Router y el árbol **SiK UI** (ver más abajo). Las opciones `DebugSkip*` están en la página separada **GSSiK: Excepciones para pruebas / GSSiK: Testing overrides** porque alteran validaciones; no son opciones de logging.

### Evidencias por sesión

Las ejecuciones diagnósticas se aíslan bajo `Lua/SiKDiagnostics/GlobalStorageSiK/<sessionId>/`. La sesión permanece estable durante el proceso y cada ejecución recibe un `runId` distinto, de modo que repetir una prueba no sobrescribe la anterior:

```text
taxonomy/audit-<runId>.log
taxonomy/unclassified-<runId>.log
taxonomy/excluded-internal-<runId>.log
taxonomy/census-<runId>.log
taxonomy/corpus-<runId>.log
permissions/permissions-<runId>.log
session.json
```

`session.json` inventaría las evidencias generadas. El panel de staff muestra `sessionId`, `runId`, contadores y rutas relativas envueltas; no transmite el contenido completo de los informes al cliente. `excluded-internal-<runId>.log` contiene la lista completa y ordenada de proxies internos separados de `unclassified`, con la regla estructural aplicada (`BodyLocation=base:zeddmg`). La invariante del informe es `totalTypes = classified + unclassified + excludedInternal + pending + classifierErrors`; `reconciliationDelta` debe ser `0`. Auditoría y corpus no requieren activar categorías sandbox. El fichero de permisos solo se crea cuando están activados `Modo depuración (debug)` / `Debug mode` y `>> Identidad y permisos` / `>> Identity & permissions`. En dedicado, activa además `Reenviar logs del dedicado a administradores` / `Relay dedicated-server logs to administrators` únicamente si necesitas el eco acotado en el cliente.

El censo `taxonomy/census-<runId>.log` es un TSV de diagnóstico autoritativo,
generado únicamente al solicitar la auditoría. Su esquema 2 conserva las nueve
columnas originales y añade módulo de script, categoría/tipo originales, tags
ordenados y estado de lectura, ruta calculada, ruta efectiva y estado de la
corrección mundial. Son 25 columnas; los lectores que comparen la cabecera
completa deben aceptar este esquema. `originModId` vacío con `originStatus=unknown`
significa que no hay un origen demostrado: el módulo de script no es un ModID.
`scriptTagsStatus` distingue lectura completa, ausente, truncada o fallida;
el límite es 128 tags de hasta 256 bytes cada uno.

Los tipos de mods ausentes con una corrección guardada aparecen como
`override_source_missing`, sin aumentar los contadores del catálogo cargado.
`review_default_changed` señala una diferencia respecto a la ruta calculada
que se guardó al aplicar la corrección. El archivo permanece en el proceso
autoritativo y no incluye autor, motivo privado ni historial de la corrección.
No requiere activar categorías sandbox adicionales.

### Adaptador de diagnóstico de SiK UI

El framework independiente es propietario de la inspección de montaje,
visibilidad, geometría, árboles de componentes y solapes. Global Storage no
duplica esos recorridos: `GS_UIDebug.lua` es únicamente un adaptador compatible
que conecta el interruptor Sandbox con `SiK.UI.Diagnostics` y con el logger del
producto. Las categorías específicas conservan únicamente contexto de producto.

| Clave nueva | Sustituye a | Cubre |
|---|---|---|
| `DebugCatSiKUI` | `DebugModeUI` + la mitad "ventana" de `DebugCatUI` | Activa únicamente el diagnóstico de integración Global Storage -> SiK UI. El diagnóstico interno de composición y ciclo de vida se activa en la página Sandbox propia de SiK UI Framework. |
| `DebugCatSiKUITabs` | (nueva, sin logging previo) | Barra de pestañas lateral + contrato de registro Core/addon: creación/reutilización de panel, visibilidad, clic de activación/cancelación. |
| `DebugCatSiKUISearch` | `DebugCatSearch` | Caja de búsqueda de la pestaña Almacén (bytes vs. caracteres UTF-8 reales — diagnóstico de idiomas no-ASCII). |
| `DebugCatNodeNaming` | mitad "nombrado" de `DebugCatUI` | Aplicación del nombre visible de un contenedor a su objeto en el mundo. |

Al investigar composición interna, activa en la página propia del framework
`Diagnóstico de composición y ciclo de vida` /
`Composition and lifecycle diagnostics`. Activa además en Global Storage
`Modo depuración (debug)` / `Debug mode` y `>> Integración con SiK UI` /
`>> SiK UI integration` si necesitas su canal de registro: incluye hechos del
consumidor y eventos del framework enviados al logger de Global Storage.
Ese canal se activa con los dos interruptores del Core; no depende del
interruptor independiente del framework. Añade una
categoría específica únicamente para esa superficie; no actives todo el árbol.

### Glosario de opciones del Core

| Clave | Español / English | Volumen y función |
|---|---|---|
| `DebugMode` | `Modo depuración (debug)` / `Debug mode` | Interruptor maestro. Por sí solo no activa ninguna categoría. |
| `DebugRelayToClients` | `Reenviar logs del dedicado a administradores` / `Relay dedicated-server logs to administrators` | No, por defecto. Lotes acotados solo para administradores suscritos; comprobación en suscripción y envío. |
| `DebugCatNetwork` | `>> Trazas de red` / `>> Network traces` | Resumen de comandos y sincronización. |
| `DebugCatTerminalAccess` | `>> Acceso a terminal` / `>> Terminal access` | Manifest, registro, permisos, alcance y apertura. |
| `DebugCatPermissions` | `>> Identidad y permisos` / `>> Identity & permissions` | UUID de personaje, unión acotada de rosters, altas idempotentes y posibles rotaciones de identidad. |
| `DebugCatCraft` | `>> Recetas y crafteo` / `>> Recipes & crafting` | Resumen de recetas y préstamos compartidos. |
| `DebugCatInventory` | `>> Inventario y transferencias` / `>> Inventory & transfers` | Depósitos, retiradas, snapshots y trabajos masivos resumidos. |
| `DebugCatTooltip` | `>> Tooltip de red` / `>> Network tooltip` | Instalación/recuperación del hook, fallos y fallback del tooltip de cantidades. No registra cada frame. |
| `DebugCatRouter` | `>> Router` / `>> Router` | Resultado resumido de selección de destino. |
| `DebugCatAddons` | `>> Instalación/desinstalación de addons` / `>> Addon install/uninstall` | Catálogo por addon con ID/ModID, registro, disponibilidad, causa y montaje; además, consumo/devolución de la unidad durante instalación o retirada. |
| `DebugCatRuleMigration` | `>> Migración de reglas legacy` / `>> Legacy rule migration` | Clasifica reglas persistidas como nativas, categorías fuente explícitas, vanilla, alias GS, externas retiradas o residuo técnico; conserva hasta tres muestras acotadas de `rules` o `categories`. |
| `DebugCatSiKUI` | `>> Integración con SiK UI` / `>> SiK UI integration` | Hechos de integración y eventos del framework enviados al logger del Core. Incluye tiempos acotados `shell_visible`, `state_refresh`, `tab_activate` y `refreshItemsTab_done`; no registra una línea por frame. Activa el canal registrado en `Diagnostics.registerSink`; el framework mantiene también su interruptor independiente. |
| `DebugCatRecordedMediaRuntime` | `>> DIAGNÓSTICO: identidad de medios grabados` / `>> DIAGNOSTIC: recorded-media identity` | Resumen acotado de filas VHS, títulos exactos/no resueltos, L3 Con enseñanza/Ocio y hasta cinco `mediaIndex` de muestra. |
| `DebugCatSiKUITabs` | `>> SiK UI: pestañas y extensiones` / `>> SiK UI: tabs & extensions` | Registro/reutilización de panel, visibilidad y clic de pestaña. |
| `DebugCatTabIcons` | `>> DIAGNÓSTICO: iconos de pestañas` / `>> DIAGNOSTIC: tab icons` | Ruta del asset, resolución de textura, tamaño nativo y tamaño final del slot; solo cambia con la geometría del rail. |
| `DebugCatExactWithdraw` | `>> DIAGNÓSTICO: retirada interactiva` / `>> DIAGNOSTIC: interactive withdrawal` | Arrastre, cantidad y filas semánticas exactas, destino, envío y capa del menú contextual. |
| `DebugCatOptionsTables` | `>> DIAGNÓSTICO: tablas de Opciones` / `>> DIAGNOSTIC: Options tables` | Conteos de Terminales/Miembros y rectángulos finales de bloque y tabla tras montar, refrescar o redimensionar. |
| `DebugCatSiKUISearch` | `>> SiK UI: caja de búsqueda` / `>> SiK UI: search box` | Bytes vs. caracteres UTF-8 reales en el cuadro de búsqueda de Almacén. |
| `DebugCatNodeNaming` | `>> Nombrado de terminal` / `>> Terminal naming` | Aplicación del nombre visible de un contenedor a su objeto en el mundo. |

Las líneas del Core usan componente y evento estables. Operaciones largas deben emitir estados significativos, no una línea por tick. Si un estado no cambió, no se repite.

### Prueba DEV: incidencias críticas de interfaz

Cada caso se activa por separado junto con `Modo depuración (debug)` / `Debug
mode`; todas las demás categorías permanecen apagadas:

- Iconos: activa `>> DIAGNÓSTICO: iconos de pestañas` / `>> DIAGNOSTIC: tab
  icons`, abre la terminal y cambia una vez el tamaño. El prefijo esperado es
  `[CLI] [GlobalStorageSiK:DEBUG:TabIcons]`; cada entrada debe indicar
  `resolved=true`, `native=56x56` y un `slot` de al menos `56x56`.
- Retirada interactiva: activa `>> DIAGNÓSTICO: retirada interactiva` / `>>
  DIAGNOSTIC: interactive withdrawal`. Arrastra una cabecera, una línea de
  detalle individual y una selección múltiple desde Almacén y desde el editor
  de contenedor; abre además su menú contextual. El prefijo esperado es `[CLI]
  [GlobalStorageSiK:DEBUG:ExactWithdraw]`; `amount` nunca será cero, el destino
  tendrá clave y el envío terminará en `accepted`. El menú debe quedar por
  encima del editor.
- Tablas de Opciones: activa `>> DIAGNÓSTICO: tablas de Opciones` / `>>
  DIAGNOSTIC: Options tables`, abre Opciones y redimensiona en ambos sentidos.
  El prefijo esperado es `[CLI] [GlobalStorageSiK:DEBUG:OptionsTables]`; los
  cuatro rectángulos deben existir y cada tabla debe quedar dentro de su bloque.

Conserva `console.txt` del cliente. En host/dedicado conserva también el
`console.txt` autoritativo si se prueba una transferencia; el eco al cliente
solo se activa si hace falta y estas categorías no generan trazas por tick.

### Prueba DEV: descubrimiento y montaje de addons

Activa únicamente `Modo depuración (debug)` / `Debug mode` y
`>> Instalación/desinstalación de addons` / `>> Addon install/uninstall`.
Mantén apagadas las categorías no relacionadas. Abre la pestaña Addons con Craft, Builder y Tablet
activos: cada ID debe aparecer exactamente una vez con `registered=true`,
`available=true`, `mounted=true` y `cause=available`. Repite retirando uno de
los tres ModID: los otros dos deben seguir montados y el ausente debe quedar
identificado por su ModID y por la causa accionable, sin traza por fotograma.

El prefijo esperado es `[CLI] [GlobalStorageSiK:DEBUG:Addons]`; conserva el
`console.txt` del cliente y, si la prueba es dedicada, el `console.txt` del
servidor. El eco de dedicado se activa solo si se necesita expresamente.

### Prueba DEV: identidad y clasificación de VHS

Opciones mínimas: `Modo depuración (debug)` / `Debug mode` y
`>> DIAGNÓSTICO: identidad de medios grabados` /
`>> DIAGNOSTIC: recorded-media identity`. En dedicado, añade
`Reenviar logs del dedicado a administradores` /
`Relay dedicated-server logs to administrators` solo si necesitas el eco en el
cliente. Mantén apagadas las categorías no relacionadas.

Deposita dos copias de una misma cinta con enseñanza, otra edición con
enseñanza distinta y una cinta de ocio. Tras reescanear y reabrir Almacén, cada
cabecera debe usar el nombre original localizado de su edición; las dos copias
idénticas forman una sola fila con cantidad 2 y las ediciones distintas nunca se
agrupan como `VHS comercial`. La búsqueda por una palabra del título debe
encontrar esa edición, y los tres selectores deben ofrecer
`Conocimiento y medios > Medios grabados > Con enseñanza/Ocio` /
`Knowledge and media > Recorded media > With learning/Leisure`. El tooltip de
la cinta docente conserva el anexo de red y muestra únicamente las habilidades
de esa edición; la cinta de ocio no genera un bloque `Enseña` vacío.

El evento esperado es una línea acotada
`[GlobalStorageSiK:DEBUG:RecordedMediaRuntime] projection` con `rows`, `exact`,
`unresolved`, `learning`, `leisure` y hasta cinco muestras `mediaIndex=título`.
`unresolved` debe ser `0` para cintas vanilla conocidas. Conserva
`console.txt` y `GlobalStorageSiK_Debug_RecordedMediaRuntime.log`; en dedicado,
conserva además el `console.txt` del servidor.

### Perfiles de rendimiento local

Estas opciones no son categorías de log. Controlan únicamente el ritmo de
depósitos/retiradas masivas y Auto-Sort en SP real o en un host con un solo
jugador humano. Dedicado, cliente remoto y pantalla dividida fuerzan `Seguro`.

| Opción visible ES / EN | Efecto y ejemplo |
|---|---|
| `Perfil de rendimiento local` / `Local performance profile` | `Seguro` usa 10 objetos/400 ms y 2 movimientos/1000 ms; `Rápido`, 25/75 ms y 5/150 ms; `Personalizado` usa los seis límites siguientes. |
| `>> Personalizado: unidades por lote` / `>> Custom: units per batch` | 1-100 objetos físicos validados por microlote. Con 25, 100 objetos requieren al menos cuatro lotes. |
| `>> Personalizado: espera entre lotes (ms)` / `>> Custom: delay between batches (ms)` | 0-1000 ms tras un ACK antes del siguiente lote. `0` elimina la espera, no la regla de una petición en vuelo. |
| `>> Personalizado: movimientos Auto-Sort por paso` / `>> Custom: Auto-Sort moves per step` | 1-20 pares remove/add por paso acotado. |
| `>> Personalizado: espera tras mover (ms)` / `>> Custom: delay after a move step (ms)` | 0-2000 ms. `0` continúa en el próximo `OnTick`; nunca crea un bucle interno. |
| `>> Personalizado: objetos inspeccionados por paso` / `>> Custom: objects inspected per step` | 10-500 evaluaciones de categoría, reglas, afinidad y destino; inspeccionar no implica mover. |
| `>> Personalizado: presupuesto de CPU por paso (ms)` / `>> Custom: CPU budget per step (ms)` | 1-15 ms y siempre prevalece sobre los máximos de inspección/movimiento. |

Para comparar perfiles activa solo `Modo depuración (debug)` / `Debug mode` y
`>> Inventario y transferencias` / `>> Inventory & transfers`; en dedicado,
añade `Reenviar logs del dedicado a administradores` / `Relay dedicated-server logs to administrators`.
Las líneas agregadas incluyen `requested`,
`effective`, lote, esperas, movimientos, inspecciones y presupuesto CPU.

Prueba depósitos, retiradas y Auto-Sort de 10, 100 y un inventario enorme. En
Personalizado máximo/0 ms, un inventario corriente puede sentirse inmediato;
uno enorme debe continuar rápidamente sin congelar el juego, duplicar objetos
ni completar toda la transacción en un tick. Repite en host con un segundo
humano y en dedicado: `effective=safe` debe prevalecer. Conserva `console.txt`
de cliente y servidor.

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

Opciones mínimas: `Modo depuración (debug)` / `Debug mode`, `>> Identidad y permisos` / `>> Identity & permissions` y, en dedicado, `Reenviar logs del dedicado a administradores` / `Relay dedicated-server logs to administrators`. Las opciones DETAIL han sido retiradas.

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
- `DebugOperations`: solicitudes, esperas y resultados acotados por operación; requiere activación explícita.
- `DebugLifecycle`: apertura/cierre de UI, sesión e instalación de hooks.

Opciones visibles de Craft y Builder:

| Clave | Español / English | Uso |
|---|---|---|
| `DebugMode` | `Modo debug (Craft/Builder)` / `Debug mode (Craft/Builder)` | Interruptor maestro del addon. |
| `DebugLifecycle` | `>> Interfaz y sesiones` / `>> UI and session lifecycle` | Hooks, apertura/cierre y estado de sesión; volumen normal. |
| `DebugOperations` | `Operaciones` / `Operations` | Claims, ACK, unidades, resultados y devoluciones por `operationId`; DEBUG acotado y apagado por defecto. |

Tablet solo expone `Modo debug (Tablet) / Debug mode (Tablet)`, de volumen normal. Los tres addons usan el relé neutral del Core cuando está habilitado.

Formato:

```text
[12.3s][CLI] [GSSiK_Addon_Craft:DEBUG][Operations] craftAttempt START operationId=Craft-...
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

Al terminar cualquiera de estos casos, el correspondiente `Events.OnTick` se retira. Para diagnosticarlos activa `Modo depuración (debug)` / `Debug mode` y `>> Inventario y transferencias` / `>> Inventory & transfers`; añade `>> Router` / `>> Router` solo para investigar destino.

### Prueba DEV: migración recuperable de reglas legacy

Opciones mínimas: `Modo depuración (debug)` / `Debug mode` y `>> Migración de reglas legacy` / `>> Legacy rule migration`. Mantén apagadas las categorías no relacionadas. En dedicado, añade opcionalmente `Reenviar logs del dedicado a administradores` / `Relay dedicated-server logs to administrators`; conserva siempre el `console.txt` del servidor.

Al abrir por primera vez una red heredada, el servidor emite `legacyRuleSanitizerInspection phase=capture` y hasta tres `legacyRuleSanitizerRecord` antes de mutar. Cada registro acotado identifica `network`, `ownerKind`, `ownerId`, `source`, `ruleIndex`, `op`, `type`, `value`, `nativePath` y `legacyValue`; nunca incluye payloads completos. Después aparecen `legacyRuleSanitizer ... pass=1` con conteos separados `rules=A->B` y `categories=C->D`, seguido de `pass=2` con `changedOwners=0` y `quarantined=0`. La postcondición exige `legacyRuleSanitizerInspection phase=postvalidate ... matches=0` antes de `legacyRuleSanitizerMarker ... version=3 status=written`; si quedan coincidencias, el marcador se retiene con `status=withheld` para permitir reintento. Las entradas retiradas permanecen recuperables y sin duplicados en `legacyJunkRules`, con `legacySource=rules|categories` y `legacyRuleIndex`.

Las claves de proveedores de categorías retirados se conservan literalmente y se marcan `DEPRECATED_EXTERNAL`: siguen visibles para que el editor las sustituya, pero no se interpretan ni participan en routing. Las reglas nuevas llevan procedencia explícita: `NATIVE` para una ruta propia y `SOURCE_CATEGORY` para una categoría segura declarada por el objeto. Un conjunto mínimo de alias GS históricos demostrados se enriquece de forma aditiva con `nativePath` y `legacyValue`; un alias desconocido sigue inactivo. `TECHNICAL_RESIDUE` identifica dimensiones como `B`, `F` o `W`; tampoco puede convertirse en una coincidencia.

### Prueba DEV: leer literatura y devolverla a la red

Opciones mínimas: `Modo depuración (debug)` / `Debug mode` y `>> Inventario y transferencias` / `>> Inventory & transfers`. En dedicado, añade `Reenviar logs del dedicado a administradores` / `Relay dedicated-server logs to administrators`. No existen sublogs DETAIL activables.

Prueba por separado un libro de habilidad, una revista de receta y una revista o periódico normal: abre el menú contextual de la fila de red, elige `Leer y devolver a la red` / `Read and return to network`, deja terminar una lectura y cancela otra. Debe retirarse exactamente una instancia, encolarse la acción vanilla y regresar el mismo `itemId` al mismo nodo físico siempre que siga válido; si no, debe caer al router compartido. Espera `NetworkReadAction read queued`, después `return scheduled` y `return queued ... preferredNodeId=...`; el servidor debe registrar `depositItems origin=network_read_return operationId=Read-... preferredNodeId=...`. Si la devolución no puede encolarse durante 30 segundos, debe quedar una sola línea `return queue timeout`, cesar el `OnTick` y conservarse el objeto en el inventario del jugador. Guarda `console.txt` del cliente y, en dedicado, el del servidor.

### Prueba DEV: afinidad exacta y taxonómica

Opciones mínimas: `Modo depuración (debug)` / `Debug mode`, `>> Inventario y transferencias` / `>> Inventory & transfers` y `>> Router` / `>> Router`. En dedicado, añade `Reenviar logs del dedicado a administradores` / `Relay dedicated-server logs to administrators`.

En una zona con dos contenedores sin categorías, coloca una revista de receta A en el primero y deposita una revista de receta B. Debe aparecer `RESULT tier=5 ... (afinidad de categoría)` si comparten identidad de routing; una copia exacta de B debe ganar tier 4. Repite con `Rechazar depósito sin contenedor adecuado` / `Reject deposit without a matching container` activado: tiers 4 y 5 siguen permitidos; un objeto sin afinidad ni filtro debe quedar en el inventario con `RESULT no_match`. Ejecuta Auto Sort con la misma disposición y comprueba que usa los mismos tiers y que no mueve un objeto que ya está en el mejor destino. Conserva `console.txt` del cliente y del dedicado.

### Prueba DEV: requisitos y montaje del lector/PC

Opciones mínimas: `Modo depuración (debug)` / `Debug mode` y `Recetas y crafteo` / `Recipes & crafting`. En dedicado, añade `Reenviar logs del dedicado a administradores` / `Relay dedicated-server logs to administrators`. Mantén apagadas las categorías no relacionadas.

Prueba el lector con tres distribuciones: todos los requisitos en el inventario principal, todos en contenedores físicos cercanos y una mezcla entre inventario, mochila equipada y contenedor. El modal y el servidor deben coincidir; debe aparecer una única salida, consumirse cada pieza de su origen real y conservarse soldador y destornillador. Repite retirando una pieza durante la barra: debe fallar con `reason=materials`, no crear salida y no consumir las demás. El evento esperado es `[SRV] [GlobalStorageSiK:INFO:Acquire] reader result | ok=true reason=success` o el motivo resumido del fallo. Repite al menos el caso mixto con el PC (`pc result`) y un disquete en blanco cercano (`program disk result`). Guarda `console.txt` del cliente y del servidor; en SP la marca será `[SP]` y no habrá relé.

## Reglas de emisión

### Ayudas corregidas en 1.5.1-dev1

- `No exigir alcance de red` / `Skip network reach requirement` modifica el
  fallback global del alcance de contenedores durante el escaneo de zonas.
  Cada red puede sustituirlo; no cambia la distancia de enlace terminal-red.
- `>> Comprobación de lectura` / `>> Literature read check` registra la
  caché/sonda de recetas aprendidas y las rutas de literatura de Almacén:
  título de instancia, páginas, estado de red y nombre cliente. No se limita
  a una sonda aislada. Requiere `Modo depuración (debug)` / `Debug mode`.
- `>> Migración de reglas antiguas` / `>> Legacy rule migration` conserva
  su categoría independiente y registra la migración recuperable, muestras
  acotadas y la segunda pasada idempotente. Requiere el modo de depuración.

Conservar `console.txt` del cliente y del dedicado; en SP las líneas propias
usan `[SP]`. Mantener apagadas las categorías no necesarias para cada caso.

- Agrupa en una línea los campos pequeños del mismo evento.
- Divide payloads extensos o listas grandes en cabecera + bloques acotados.
- No repitas estados por tick. Registra la entrada al estado y el cambio siguiente.
- No registres dos veces el mismo evento solo porque atraviesa un wrapper; distingue `START`, `WAIT`, `RESUME`, `END` y `ABORT`.
- Los errores incluyen motivo resumido y `operationId`; no vuelques objetos Java completos.
- Los logs compartidos de `CraftSession` se enrutan al sink del addon activo. Core no adopta categorías o textos específicos de Craft/Builder.

## Informe útil para reproducir

Indica versión de Core/addon, SP/host/dedicado/cliente, UI vanilla o mod externo, receta/objeto y el bloque completo desde `START` hasta `END` o `ABORT`. Para problemas de red, el `console.txt` del cliente puede contener conjuntamente `[CLI]` y `[SRV]` si el relé estaba habilitado; conserva también el log dedicado si está disponible.

Cada plan de pruebas DEV indica los nombres visibles exactos ES/EN de las opciones mínimas, deja las demás categorías apagadas, señala el evento esperado y los ficheros que se deben conservar. DETAIL está retirado, incluidos valores heredados.

## Política de volumen y migración del cierre 1.5.0

Core limita INFO/DEBUG por categoría a 20 líneas y 8192 bytes de mensaje por segundo; un mensaje de más de 1024 bytes se sustituye por un resumen de omisión. La siguiente ventana activa informa cuántas líneas se omitieron. No hay listener de mantenimiento. WARN, ERROR e identidad de arranque no se ocultan por esta cuota.

Craft/Builder limitan cada categoría a 20 líneas por segundo y sustituyen mensajes de más de 1024 bytes. Framework conserva un solo sink de integración del producto; `GS_UIDebug` no duplica el evento recibido por `GS_UI_Framework`.

Retiradas: `DebugDetailNetwork`, `DebugDetailCraft`, `DebugDetailInventory`, `DebugDetailRouter`, `DebugDetailCapacityBonus` y `OperationHaloFeedback`. Sus valores antiguos no habilitan trazas o halos. Se conservan las categorías normales, todas OFF por defecto; `ZoneScanJob` y `NativeProduct` pertenecen a Inventario y `WithdrawClient` a Retirada interactiva.

Para la corrección runtime activa: activa `Modo depuración (debug)` / `Debug mode`, `>> Inventario y transferencias` / `>> Inventory & transfers` y `>> DIAGNÓSTICO: retirada interactiva` / `>> DIAGNOSTIC: interactive withdrawal`. Espera IDs de operación, revisión, solicitados y confirmados coherentes; un escaneo invalidado termina como `INVALIDATED_BY_MUTATION`/`STALE_RETRY`, nunca `zone_error` por esa sola causa. Conserva `console.txt` de cliente y dedicado. El relé opcional requiere administrador; un jugador normal no recibe diagnóstico del servidor.

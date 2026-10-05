# Diagnóstico y logs

## Recuperación de una retirada mixta

Tras `selection_stale`, una selección global solicita `terminalManifestRequest`
con la sesión y los tokens confirmados: incluso un manifiesto sin cambios debe
responder. Reutiliza los bloques vigentes; no inicia un reescaneo. Las selecciones
dirigidas a un nodo conservan `getNodeContents`; el catálogo legacy conserva su
ruta. El servidor sigue validando revisión, permisos, IDs y destino físico.

Una réplica completa comprometida puede renovar por copia el selector consumido
aunque `snapshotCertified=false` para la captura global. Esta confirmación viaja
dentro del callback local después de commit/Ready y sus cercas de sesión y
vista, o se reutiliza mediante una prueba local de ese mismo commit vigente. No cambia la certificación global ni las filas compartidas; no autoriza
vistas parciales, rechazadas o sustituidas. Se conserva un único retry.

Con NetTrace habilitado, `Withdraw: selection refresh` registra como máximo el
primer descarte y el desenlace por intento. Incluye gesto, jugador/red, etapa,
motivo, último descarte, revisión del snapshot/inventario/fila, apertura, secuencia
de vista, parcialidad y confirmación de réplica. `retry_scheduled` significa que
el selector está listo; `withdrawItem` y su ACK acreditan envío y resultado.
Los descartes del catálogo son sólo diagnóstico y nunca reanudan la retirada.

ACK y NACK correlacionados elevan el mínimo `requiredRevision` de la operación.
Una vista completa más antigua no consume el retry ni prolonga su espera. Antes
de enviar otra fila retenida, se reutiliza el commit vigente si alcanza ese mínimo;
en otro caso se pide un refresco y se espera. El token del delta identifica las
mismas filas comprometidas. La prueba se invalida al cambiar jugador, apertura,
red, ámbito, época, topología, filas o confirmación de caché.

La traza incluye `requiredRevision`, `refreshReason`, `refreshWaitMs` y `retryCount`.
`continuation_scheduled` distingue la renovación preventiva entre filas del
`retry_scheduled` posterior a un NACK. Las respuestas duplicadas o sin el ID de
retirada en vuelo no consumen la espera. Los tiempos pertenecen al reloj cliente;
no son un benchmark ni deben combinarse con timestamps de servidor.

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

### Routing y AutoSort en candidata routing-r1

El pie identifica `Core 1.5.8-dev3 [routing-r1-20261004]`; si el servidor difiere,
añade `/ SRV:<candidata>` (o `unknown` mientras falta su estado). La versión
pública y las versiones de addons siguen siendo independientes de esta identidad.

Con DEBUG de Inventory, AutoSort emite inicio, cambios de fase, progreso agregado
cada cinco segundos y cierre. No genera una línea por unidad. `activeMs` mide
los pasos de selección/movimiento y su batch físico; `waitMs = durationMs-activeMs`
incluye esperas, planificación y reconciliación, no es CPU o tiempo ocioso puro.
`plannedWaitMs` suma las pausas programadas; `replicaMs` mide la espera final de
verificación. `maxStepMs` y `overruns` exponen los excesos del presupuesto blando
de 5 ms: una llamada física atómica o una búsqueda de afinidad pueden excederlo.

`optimal` identifica origen óptimo; `noDestination`, `full`, `absent` y
`sourceUnavailable` son omisiones distintas y no significan «ya bien colocado».
`planBuilds/planHits/matching/candidateVisits/affinityReads/physicalValidations`
explican qué trabajo se reutilizó y cuál fue necesario. `publicationNodes` cuenta
nodos únicos tocados, `publicationWindows` ventanas liberadas: ninguno equivale
a snapshots enviados ni a recargas completas. La réplica mantiene sus trazas,
tokens y créditos existentes; correlacionar revisiones y pedidos para medirla.

DEBUG de Router añade un resumen `depositComplete` por tarea de depósito, con
movidos/omitidos/fallidos y los contadores del plan vigente. Una reconstrucción
por cambio de reglas reinicia esos contadores; no son un acumulado histórico.
Los tiers explícitos 1–3 y afinidades 4–6 conservan su significado; `priority`
indica que una prioridad sin empate decidió sin necesitar consultar afinidad.

Las capturas diferidas se liberan en checkpoints de tres segundos, y al cerrar
el trabajo físico. La publicación y verificación siguen sujetas al presupuesto
global y pueden tardar más. El job no anuncia éxito hasta verificar sus nodos,
incluidos snapshots sin cambios; un nodo ausente o no cargado produce fallo
explícito. `snapshotCertified` no certifica toda la red por terminar el journal.
`globalRecovery=true` agenda una única recuperación incremental global tras un
job con mutaciones, sin incrementar otra vez la revisión. Conserva la intención
si el jugador se desconecta; la siguiente sesión autorizada permite reanudarla.
Los jobs sin movimientos no la agendan. Esta captura usa el presupuesto existente
de ZoneScanJob (7 ms), separado del deadline compartido de 5 ms; duración y
replicaMs del journal no incluyen su terminación. Confirmar además
`snapshotCertified=true/reconcilePending=false` para acreditar el cierre global.
La sesión ordena las referencias capturadas; nuevas altas externas pueden quedar
para otra pasada, aunque sí cuentan al decidir destinos por afinidad actual.
Cerrar la ventana conserva el job existente; esta candidata no añade cancelación.

### Network traces (Core 1.5.5-dev1 work in progress)

`Modo depuración (debug)` / `Debug mode` plus `>> Trazas de red` /
`>> Network traces` enables bounded DEBUG records from `NetTrace` without DETAIL.
`C->S`, `S<-C`, `S->C` and `C<-S` identify send/receive direction. Server responses
with `ok` report `decision=ACK` or `decision=NACK`; the summary includes the
localization key and reason, and any request/revision/target IDs supplied by the
command. This instrumentation does not add transactional IDs to commands that
do not yet have them and does not prove that a mutation was persisted.

Only a fixed scalar allowlist is read. Traces do not enumerate the network
registry, dump catalogs or add timing fields to the wire payload. Records fit
inside the logger's normal per-category budget; catalog fragments, receipts,
keepalive and debug relay echoes remain excluded. Preserve the client/server
`console.txt` and the session's `debug/network-<runId>.log` for a future authorized
runtime check. Automated author checks are not a PZ runtime reproduction.

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

En Corpus, `failedCases` cuenta cada caso fallido una sola vez. Los contadores
`classificationFailures`, `evidenceFailures` y `facetAttributeFailures` cuentan
casos por causa y pueden solaparse: un objeto con ruta y faceta incorrectas
aparece en ambos. No deben sumarse para calcular los casos fallidos.
`requiredMissingFailures` identifica los casos obligatorios ausentes. Por bloque,
`facetAttributeChecks` y `facetAttributeCorrect` cuentan comprobaciones de campos,
no objetos; un objeto puede declarar varias. Desde `1.5.2-dev1`, el encabezado
conserva también las causas secundarias que antes solo aparecían en el detalle.
Para comprobarlo, ejecuta Corpus desde Staff y conserva `taxonomy/corpus-<runId>.log`;
no requiere activar opciones sandbox. El resumen y las divergencias deben
coincidir aunque el mismo objeto falle en más de una dimensión.

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

El cierre también incluye `scanSteps`, `scanUnits`, `scanCpuMs`, `scanChargedMs` y
`scanPeakMs`. El scanner reparte un presupuesto global de 160 ms de crédito por
segundo entre todas las redes, con reserva máxima de 8 ms; no se multiplica por
jugador. Cada paso busca 3–7 ms según el ritmo observado, hasta 768 unidades de
cursor y un máximo global de 16.384 unidades por segundo. El quantum crece o baja
según el coste medido. Una unidad de descubrimiento ya no recorre una baldosa
entera: cede entre objetos y compartimentos, además de entre instancias.
`scanCpuMs` suma tiempo de los pasos medido por el reloj; `scanChargedMs` añade
un milisegundo conservador por paso útil para cubrir su resolución. Una llamada
nativa individual y la publicación atómica pueden superar el objetivo temporal;
`scanPeakMs` permite identificarlo. Estos contadores no miden el transporte del
catálogo. Conservar logs y comparar misma red/carga con caché fría y caliente.

Antes de publicar se verifica por pasos la estructura observada: baldosas,
listas de objetos, compartimentos y referencias de instancias. Si un índice
cambia durante la captura, se descarta todo el staging y se conserva la vista
confirmada. La publicación es un único cambio lógico; no bloquea el mundo PZ
ni promete que todas las zonas se observaron en el mismo instante. Los estados
mutables de objetos conservan la detección normal por nodos y las transferencias
revalidan siempre el objeto real. Una transferencia ya confirmada protege sólo
su nodo frente al cuerpo anterior del escaneo, sin eximir su resolución física.

Las referencias de prueba se limitan a 262.144 por trabajo, compartidas por sus
zonas, y se liberan al completar, rechazar, cancelar o borrar la red. El límite
es de referencias, no una medida del heap Lua/Java. `scan_capture_budget` termina
con fallo explícito sin publicar un resultado parcial. La interferencia admite
como máximo dos recapturas automáticas coalescidas; después se muestra fallo
`snapshot_stale` y se conserva la vista previa. Un nuevo reescaneo explícito
puede iniciar otro intento. La cola respeta su backoff incluso si venció el
plazo de fuerza, para que una red ocupada no monopolice la selección.


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

El tooltip instala su integración una sola vez, con reintentos de arranque
acotados. No mantiene un vigilante que vuelva a envolver `ISToolTipInv.render`.
Cuando TooltipLib está disponible, registra un proveedor y evita añadir dos
veces el anexo de red en inventarios reales. Si otro mod sustituye después la
cadena sin delegar, conserva el orden de carga y `console.txt` para diagnóstico;
no se intenta ganar la prioridad reinstalando hooks. Activa únicamente
`Modo depuración (debug)` / `Debug mode` y `>> Tooltip de red` /
`>> Network tooltip`: las líneas de `ItemNetworkTooltip` describen la instalación
y sus fallos, sin trazas por objeto o frame.

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

### Prueba DEV: recarga de sopletes con propano de red

Activa solo `Modo debug (Craft)` / `Debug mode (Craft)` y `Operaciones` /
`Operations`. Desde un terminal accesible con la impresora instalada, recarga
un soplete usando un depósito de propano parcial y después uno lleno. Repite
desde su menú contextual y desde Global Storage, con varios sopletes en el
inventario principal y en una bolsa propia abierta. El objetivo explícito debe
ser el elegido; una selección agregada usa un candidato no lleno del inventario
activo propio, nunca de un contenedor del mundo ni de otro jugador. Si el
objetivo desaparece, no debe sustituirse por otro.

Cancela mientras se esperan materiales, cierra y reabre la sesión y repite con
dos jugadores, muerte y reconexión. El registro `craftAttempt START/WAIT/RESUME`
debe corresponder a una sola operación por activación; una operación cancelada
no puede emitir un nuevo `RESUME` cuando llegue un material tardío. La línea
`pending craft abort failed` indica un fallo de cleanup que debe investigarse.
Para seguir el reembolso añade al Core únicamente `Modo depuración (debug)` /
`Debug mode` y `>> Inventario y transferencias` / `>> Inventory & transfers`.
Conserva los `console.txt` del cliente y del dedicado.

Compara gas y estado antes y después con la receta vanilla `RefillBlowTorch`:
esta receta crea el soplete de resultado a partir del consumido y conserva el
depósito. No se exige conservar el ID del soplete consumido; sí evitar cualquier
consumo o resultado duplicado y devolver el depósito exacto y sus sobrantes.

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

## Core 1.5.3-dev1 — catalog transport

Enable only `Modo depuración (debug)` / `Debug mode` and
`>> DIAGNÓSTICO: transporte de catálogos` / `>> DIAGNOSTIC: catalog transport`
for the focused transport test. The latter maps to `DebugCatCatalogTransport`
and defaults to false. It records `CatalogTransport` events `queued`, `completed`
and `failed` with batch, row count, encoded bytes and reason; no per-item dump.
Preserve client `console.txt` and the dedicated server console log. Origin follows
the common `[CLI]`, `[SRV]`, `[HOST]` or `[SP]` logger context. Do not enable unrelated
categories or high-volume detail for this test. The trace describes transport,
not permission acceptance or persistence success. See [CATALOG_TRANSPORT.md](CATALOG_TRANSPORT.md).

Core 1.5.4-dev1.1 distinguishes bounded phase timings under the same category:
`state_envelope_built` is only the early state envelope; `catalog_rows_built`
confirms real rows and reports build work and elapsed time. `encoded` confirms
wire preparation; `completed` confirms the exact client receipt. `queued` alone
does not mean that rows have been built.
`applied` reports `receiveMs` (first accepted fragment to decoding) and
`decodeApplyMs` (decode plus consumer dispatch). These are not button-to-frame
or rendered-UI readiness timings; deferred UI work is outside consumer dispatch.
The same category also records `shell_visible` (shell registered, not proof of a
rendered frame) and `ui_ready` with `waitMs` from that opening to successful UI
refresh. For a cold open and ten consecutive warm opens, preserve both events
with player/openSeq, plus state_envelope_built/catalog_rows_built/queued/applied/completed. Compare PZ frame/input
observations separately; no timing here certifies FPS or renderer latency.

`progress` is globally sampled at most once every two seconds and includes phase,
current/total node, remaining work, retained base and authorization time.
`resumed`, `detached`, `preparation_retired`, `base_restored` and `deadline` explain
reopen/retention/cancellation. Reconciliation is a separate sampled phase. A
10-second preparation/encoding deadline produces a causal error even if work is
still advancing; it is a failed opening, not a performance pass.

Core 1.5.3-dev1.2 adds `delta_sent`, `delta_applied`, `delta_fallback` and
`delta_recovery` under the same focused category. They report only revisions and
changed/removed row counts. A normal one-item transfer must show its independent
`actionResult` ACK and a bounded delta; it must not show a new full `queued`
catalog or a restarted `ZoneScanJob`. `delta_fallback` followed by `queued` is
valid only when there is no exact cached base or the complete delta exceeds the
safe frame budget. Preserve the same client/server logs; no detail category is
needed.

## Core 1.5.8-dev1: measured sizing and opt-in phase profiles

Final frame validation now computes envelope and data bytes in one traversal.
The sender and receiver reuse that result for accounting instead of validating
and counting the same data again. Unicode, depth, cycle, type and byte limits
remain unchanged. No frame size, send cap, work budget, request window, snapshot
format or progressive-view cadence has been increased.

With both Debug mode and Catalog transport diagnostics enabled, each server
batch records `profile_work` (validate/build/encode/frame/size/send active elapsed
milliseconds, maximum call and call count) and `profile_yields` (shared scheduler
exit reason, phase at exit, pending updates and maximum transport update time).
The client records `profile_client` after successful consumer application with
unique accepted fragment sizing, active decode work/maxima/steps, decode yields
and consumer dispatch time. Existing failed/rejected events retain error evidence.

These measurements use the process millisecond clock, not a CPU profiler.
`frame` covers framing initialization and framing steps; `validate` covers update
validation visits, including cached visits. `send` includes the engine port and
may include nested client work under synchronous SP callbacks; do not sum nested
server/client timings as independent CPU. A scheduler maximum is not a whole PZ
tick or rendered frame. Yield counters describe a shared limit encountered while
a batch remains pending, not work uniquely charged to that recipient. ACK waits
are separate from ready-to-send work. A zero millisecond sample can be below timer
resolution. Wall latency and active work must remain separate.

No profile table is created when the existing diagnostic gate is off. Profiles
are bounded by the existing session/job lifetime and known phase/reason keys;
there is no timer, item log, persistent cache or network payload addition. Final
send profiling survives a synchronous receipt. Category quotas remain in force:
a trace containing `diagnostics throttled` or missing terminal profiles is an
incomplete measurement, not a zero-cost phase. Compare an equivalent run with
traces disabled and retain all incomplete/error runs.

The development Lua 5.1 fixtures preserve byte counts, exact limits, cache reuse,
permission fences and four observer progress. Native Kahlua/TableNetworkUtils
checks validate serialization, not dedicated runtime speed. Dedicated TEST must
first prove server/client parity against the candidate; cold replication and
physical capture are separate experiments. Keep issue #1 open and credit iceriny.
## Core 1.5.8-dev2: bounded continuation and terminal measurements

The research selector defaults to control. With Debug mode and Catalog transport diagnostics enabled, call GlobalStorageSiK.InitialLoadProfile.select("drain1024") or select("drain4096") on the authoritative process before opening. Selection does not change existing openings. Each acknowledged opening pins a profile ID/hash and correlation ID. The selector is private and does not replace the player performance profiles.

The two variants continue existing 256-work catalog-build steps within one shared 2 ms client slice, up to 1024 or 4096 work. Four local observers still rotate through that same slice. A step can overrun the soft deadline; the next step then stops. Node requests, 24 KB frames, server limits and cache budgets retain the control values. Work ceilings are experimental, not approved dedicated pressure limits.

A terminal JSON summary is written once per role and opening to SiKDiagnostics/GlobalStorageSiK/initial-load/client-XX.json or server-XX.json under the process Lua cache directory. It bypasses progress-log throttling, retains at most 64 files per role, caps records at 16 KiB and shares a 64-record/minute allowance. Archive files before rotation or process restart. Failed exports or missing/corrupt/correlated summaries invalidate a measurement. There is no live relay.

Summaries contain active phase durations, scheduler exit counts, byte reservations, queue/receive/ACK waits, manifest metadata counts and first applied/full usable boundaries. Metadata totals accumulate inside existing manifest loops; diagnostic code never scans inventory contents. Zero calls means unobserved/inapplicable, not evidence of zero cost. phaseCoverage covers these replication instrumentation points only; physical capture, whole-engine tick/frame, JVM heap/GC, unique item types and inventory digest remain unknown until independently observed. Wall time and nested active work must not be summed as independent CPU.

Local fixtures are screening evidence only. Dedicated improvement, first-view equivalence, pressure and gameplay regressions remain pending. Keep issue #1 open; original analysis credited to iceriny.

Scope correlation in dev2 preserves the exact scope up to 1024 Lua string units. The raw scopeHash is unknown until the offline collector computes SHA-256 of its UTF-8 representation. A changed or oversized scope marks coverage incomplete and cannot qualify; never hash a truncated prefix. The collector must match both role summaries and retain their source hashes.

## Core 1.5.8-dev3: diagnostic preparation

Client manifest totals are now read from the accepted replica, including cold bootstrap and notModified. The private client console helpers GlobalStorageSiK.InitialLoadDiagnostics.select(0,"control"), exportClient(0), and exportServer(0) provide an admin-only research path; the server revalidates admin/debug/input and rejects active replication. Selection is proved by the server response and the next pinned opening ACK, not by the local send return. No gameplay UI or budget changes.

Oracles export already confirmed snapshots after the measured complete boundary. The native codec preserves fullType/count/itemIds and all row fields, with exact opening/scope/token/revision/profile identity. Export is cancellable on lost validity, bounded to one process job, 128 encode work or at most 32 tokens/32 KiB conservative write per tick, 16 MiB codec, 64 MiB file, four files per role and a 120 s timeout/60 s throttle. Footer records success/failure and encode/write maxima; atomic engine/file operations may overrun a soft time budget. Archive the returned oracle path before rotation. There is no automatic physical scan or inventory relay. Offline snapshot agreement is not physical freshness, pressure, gameplay or dedicated performance proof.

For cold-replica comparison, use one remote client with one local player, archive evidence, exit and restart only that client; keep server snapshots unchanged. Dedicated engine/JVM capture and pressure policy remain external. Technical fixture tests do not establish the >=50% target, runtime API availability or first-view/pressure equivalence. Issue #1 remains open; credit iceriny.

### Persisted oracle request results (same increment, r4)

After the measured complete boundary, an admin may explicitly call GlobalStorageSiK.InitialLoadDiagnostics.exportPair(0). In remote MP it requests both existing client and server snapshots with one requestId. A local client rejection prevents the remote export. In authoritative SP only the server role applies; this is not an MP pair. No physical scan is added. Alternatively Systems can explicitly armCapture(0) before the cold opening: a bounded once-per-second observer waits for certified completeUsable and a 2.5-second quiet interval, then exports the pair with one request ID. Default behavior is unchanged; arming expires after 180 seconds or on lost admin/debug/player identity. disarmCapture(0) records cancellation and removes the observer. Do not include the export in the measured interval.

Archive oracle-result-client-00..03.json and oracle-result-server-00..03.json from SiKDiagnostics/GlobalStorageSiK/initial-load/ on the relevant hosts, plus each referenced oracle-ROLE-00..03.jsonl. Results are bounded to 8 KiB, four slots per role, one disk write per second per process and one pending latest result per role. Pending phases may coalesce; coalescedResults counts omissions. Match content by requestId/role/sequence/slot, never by filename or modification time. Capture after terminal completion and a three-second flush allowance; absence or overwritten history blocks comparison.

Status sent/started means request/operation progress. Only terminal=true with status complete and writerStatus closed, a valid matching oracle footer, certified identity and both roles can enable offline snapshot comparison. A callback does not prove result-file persistence. The in-memory result exposes persisted/persistenceReason after the actual writer attempt; failure to persist must be treated as missing evidence. The JSON deliberately does not certify its own successful write/close.

Pre-start rejections distinguish oracle_disabled, oracle_busy, oracle_events, oracle_writer, oracle_throttle, oracle_image, oracle_uncertified, oracle_reconcile_pending, oracle_validity_error, oracle_validity_failed and oracle_scope. Catalog preflight retains oracle_replication_busy, absent/unconfirmed-image reasons, admin/input gates and request throttling. Unauthorized or malformed network input stays silent. Complete node counts do not substitute for snapshot certification.

The exporter retains its 120-second limit; remote observation waits 135 seconds including a 15-second terminal-response allowance. Missing response yields oracle_result_timeout; late/unrequested replies cannot convert it to success. Validity change, debug shutdown, cancellation and writer failure produce correlated failed terminal records. No automatic retry. Existing exportClient/exportServer helpers remain available.

Use the delivered check-initial-load-oracle-results.js with explicit client result, server result, expected requestId and output JSON. Keep each referenced JSONL beside its result copy. It checks strict UTF-8/JSON, identity, flags, role, slot and footer before allowing the existing typed content comparator. ORACLE_CAPTURE_READY is a capture gate only; physical freshness, engine pressure, first view, gameplay and >=50% dedicated A/B remain pending. Preserve issue #1 and attribution to iceriny.

### Combined initial-load research profiles (r4)

Debug CatalogTransport selection now includes group2/group4 (logical credits per batch), frame32/frame48, reuse4 and combined2/combined4. Control remains one node and 24 KB. Cold grouping starts after the first partial view; warm reopen and deltas keep their existing path. There is still one acknowledged job per recipient and unchanged global four-frame/4-ms server and shared 2-ms client budgets. Batch limit remains 16 MiB. Immutable node snapshots avoid redundant deep copies and permit exact cached token/frame sizing on the trusted server producer; clients fully validate every received frame and block. A group that exceeds retention/batch quota falls back to one block for that opening. Transfer item availability and authoritative commit checks remain unchanged. Apply remains a separate indivisible update; no handoff pressure guarantee is claimed. Only measured local screening and native serializer checks are available; dedicated pressure, first view and >=50% A/B remain pending. Select control to roll back the opt-in experiment.

## Core 1.5.8-dev3 r7: compact complete replication

The r7 candidate uses `final7` without requiring debug mode. Each acknowledged opening pins its profile ID/hash and correlation ID. Debug diagnostics may select a research profile before opening; selection does not change active openings. Compact transport retains complete item data and the 1024-action quantum. Compression and technical checks do not certify ingame duration.

For r7 comparison, capture the full opening and warm reopening with the same physical inventory and player access as r6. Preserve first-view, full-usable, bytes, recoveries and console evidence. Do not infer runtime improvement from the standalone fixtures.

## Core 1.5.8-dev3 r8: fewer encoding resumptions

The r8 candidate uses `final8`. Complete r7 wire data is retained. Already validated scalar/reference values emit without an extra stack frame; record schemas are reused only after exact key-set and cardinality validation. Batch-local hint memory is included in the existing 64 KiB schema cache and transport reservation. The 1024-action quantum, four credits, 48 KB frames, eight-node view cadence and global budgets remain unchanged. Explicit `final7` and historical profiles retain their pins.

Existing NetTrace can report group units/rows/largest node, preparation/staging/consumer/post-consumer timings, UI construction versus refresh, and known/previous/current metadata tokens. Metadata comparison examines at most 2048 characters; `prefix_scan_truncated` denotes an unknown later difference. These diagnostics neither omit fresh metadata nor authorize preload. Offline reductions in work/calls are not ingame time or pressure acceptance. Normal testing needs no new launcher or preprocessing script.

## Core 1.5.8-dev3 r9: streamlined short strings

The r9 candidate uses final9. Short strings fuse initialization, bounded UTF scanning and final emission. Validated keys/references reuse exact accounted tokens; containers close early only after their final immediate scalar. Wire data, dictionary admission, global quotas and final8 pins remain unchanged. Existing NetTrace can emit one aggregate encoder_fastpath per batch. Terminal state refresh applies capacity once while external and inventory-only refreshes still update counts. Offline work reductions do not establish ingame latency or pressure acceptance.

## Core 1.5.8-dev3 r10: bounded repeated records and partial view deadline

The r10 candidate uses final10. Repeated scalar records with up to eight keys reuse an admitted schema only after exact key/cardinality and value validation, preserving wire tokens and accounting. Earlier profiles retain their paths and pins. Partial bootstrap views also flush on a soft one-second deadline while the next body is in flight; warm complete views remain atomic. Credits, frame sizes and global budgets remain unchanged. Existing encoder_fastpath includes the fused record count. Offline equality/work checks do not establish ingame latency or pressure acceptance.

## Core 1.5.8-dev3 r11: bounded codec overhead and phase diagnostics

Normal openings use final11. Admitted scalar records can commit identical tokens and accounting once when the complete record fits the current frame. Decoding places up to eight validated record scalars directly, charging every scalar to the unchanged quantum; long literals and complex values retain the general parser. ASCII takes the same exact UTF validation path with less dispatch. Wire values, quotas, permissions, ACK and physical operations remain intact. Existing CatalogTransport diagnostics add decode validation/parse/mixed regions, maximum update gap, packed scalar counts and gated visual refresh phases. These measurements do not attribute gaps to GC/network or establish runtime latency/pressure acceptance. The r10 soft view deadline and atomic warm view remain.

## Core 1.5.8-dev3 routing-r2: deposit decisions and AutoSort costs

The terminal footer identifies the local and server candidate separately. For this
candidate both must show `routing-r2-20261004`. The initial-load codec remains
`final11`; a matching version number alone does not identify the routing candidate.

Deposit selection retains per-item order, filter specificity, zone/container
priorities, live capacity and validated preferred returns. Candidate configuration
is checked again after task yields and physical attempts, including callbacks.
Static matches survive only an equivalent candidate configuration and container
identity. Positive affinity witnesses retain at most two item references per
node/type, with a 4096-key session cap. Each use verifies physical containment and
fullType; an invalid witness falls back to a fresh affinity lookup. They never
certify absence, capacity or a final destination. Full competitors can be pruned
before affinity work; accepting an item alone does not establish an optimal origin.

Existing debug summaries remain aggregate. `Router depositComplete` reports
`selectionMs` and `mutationMs`, static `planBuilds/planHits`, candidate-list
`candidateListHits/candidateListRebuilds`, `matching`, `candidateVisits`,
`physicalValidations`, `affinityReads`, `witnessHits/witnessMisses` and
`capacityPrunes`. `noMatch`, `full`, `noDestination` and `refMissing` distinguish
rejections and missing input references; the last does not assert physical loss.
This terminal summary covers deposit tasks, including their cancellation/replay
contract; other existing synchronous internal deposit paths do not emit it.

AutoSort `finishJob` separates `attempted`, successful `moved`, `failed` and
`skipped`. Skip causes are `optimal`, `noDestination`, `full`, `absent` and
`sourceUnavailable`. Only `optimal` means the selected origin was best under the
rules observed at that check. `routingCost` adds witness and capacity-pruning
counts; `replicaCost` retains publication nodes/windows, recovery and replica time.
No-op steps have no movement pause. Physical attempts, including failed attempts
or exceptions, consume the existing bounded quota and shared movement window.
Waiting networks retain their cursor and recompute selection after yielding.

`activeMs`, `selectionMs` and `mutationMs` use the process millisecond clock,
not a CPU profiler. `waitMs` is wall duration minus instrumented active work;
`plannedWaitMs` and its `moveWaitMs/creditWaitMs/readerWaitMs` breakdown are planned
delays already inside wall time, not additive measured waits. `busyWaitMs` records
lock retry delays separately. `affinityReads` counts explicit inventory traversal
items, not native containment cost or all physical work. A deadline is soft: one
selection or engine call can overrun it. No increase of server work budgets,
movement quotas or replication windows is implied. Global recovery remains when
required; existing scan/replica revisions do not certify universal physical freshness.

Local fixtures and compiler checks establish technical behavior only. Dedicated
deposit destinations, no-op duration, pressure, custody and final replication
remain runtime checks. Keep issue #1 open and credit iceriny.

## Routing candidate r3: mixed withdrawal selectors and personal targets

The local/server footer identifies `routing-r3-20261004`. This correction keeps
the r2 routing rules, movement budgets and codec. A retained exact-group row is
copied for the waiting withdrawal only when it belongs to the newly accepted,
complete certified view. Its old integer revision may adopt that view revision;
missing, future, negative or fractional revisions cannot. Shared catalog rows
and exact physical child IDs remain unchanged. The existing single stale retry
and server-side exact validation remain in force.

Withdrawal consumers receive full/notModified/delta catalog changes after their
transaction succeeds. Node replicas defer notification and completed-revision
accounting until the physical replica cache commits and emits Ready. Partial,
rejected or superseded views cannot wake a waiting withdrawal. Observer failure
does not roll back an already committed catalog.

`player:main` is captured by exact identity before world-wrapper classification
and resolves directly to the requesting player's current physical inventory.
The network-node and access checks still follow resolution. Other explicit
targets keep their identity and failure behavior; there is no destination
fallback. Existing bounded NetTrace lines now include `rowKey`,
`selectionRevision` and `targetKey`. A rejected withdrawal destination emits one
debug-only `Withdraw: destination rejected` summary with `targetStage`:
`key_schema`, `key_unresolved`, `network_node` or `access_denied`.

SYS23 establishes two stale gestures and a later pre-slice target rejection. Its
trace lacks the actual key and resolver stage, so this correction does not
attribute the failure to r2 or claim that the defensive main-identity case
reproduces vanilla runtime. Offline fixture conservation and compiler checks
are technical evidence only; candidate TEST and acceptance remain pending.

## Routing candidate r6: authoritative withdrawal receipt

The local/server footer identifies `routing-r6-20261005`. Withdrawal tasks flush
exact node snapshots, apply their own inventory invalidation, then seal the final
`transfer.inventoryRevision` before receipt capture and delivery. Replaying the
receipt preserves that revision and never repeats a physical movement or adopts
later mutations. A partial task that finishes after death/disconnection still
invalidates its confirmed movements and queues authorized watchers; silent close
suppresses the actor response while preserving the final receipt. Unavailability
is a failure with the actual moved count retained.

Under Network NetTrace, ACK/NACK summaries expose the nested
`transfer.inventoryRevision`, `transfer.reason`, `transfer.moved`,
`transfer.slices` and `transfer.selectionMode`. `Inventory: revision` emits one
bounded record per authoritative revision with network, previous/new revision,
cause and operation. Causes distinguish `withdraw_task`, other `transfer`,
`reconcile`, `scan_content`, `topology`, `classification`, `classification_override`
and generic `inventory_dirty`. The generic cause does not identify its individual
caller. Trace identifiers sanitize controls and are length bounded; diagnostic
failure in the revision trace cannot change the committed mutation.

Before dispatching an unticketed exact group, the worker reads the current view
revision from the same opening and network as a minimum floor. Retained rows in
a new gesture, including views committed between enqueue and dispatch, reuse the
existing fenced complete-view path to copy only the consumed selector. A revision
floor does not certify a partial view. Shared rows, exact IDs and tickets remain
untouched. The single stale retry, capacity, permissions, quotas and routing rules
remain unchanged. This correction
retains serial requests between selected types; it does not implement a new
heterogeneous server batch. Technical fixtures do not establish dedicated runtime
acceptance or a measured latency gain. Keep the failed runtime evidence and test
only the corrected candidate.

## Routing candidate r7: heterogeneous gesture

Footer identity is `routing-r7-20261005`; public version and initial-load codec
are unchanged. Supported multi-row gestures issue one `withdrawItem/exact_batch`
and one aggregate ACK. `WithdrawTasks` logs request ID, selectors, nodes/rows/IDs
visited, refs, slices, checkpoints, elapsedMs, admissionElapsedMs, activeWorkMs and
waitMs. Times are aggregated wall-clock measurements through the final task flush,
before Server completion invalidation, revision sealing and delivery. activeWorkMs
measures advanceTask and final flush; waitMs is the residual elapsed time. These
are neither strict CPU measurements nor admission-to-ACK timing. No per-object
diagnostic is added. Long tasks checkpoint at a one-second window. Finish is
flush -> invalidation -> revision -> receipt -> delivery, also for deposit/SP.

Admission runs under existing shared `update(1,deadline)` and its 5-ms target;
maximum movement remains ten units/slice. Legacy tickets and batches share four
selection slots per player. The 100,000 batch-reference quota is shared between
batch jobs and released after cancel/error/expiry; admission expires after 30s,
and a sealed task without physical progress expires after 30s. Original actor,
opening/epoch, source snapshot/scope/access/routing and physical destination remain
authority fences. Other networks cannot invalidate admission. Local missing
selectors continue siblings; global failures stop with confirmed moves retained.

Offline control: two four-type gestures use two requests versus eight in r6,
with zero stale NACKs and zero explicit refreshes in that fixture. Physical/world,
access and wire leaves are simulated. Dedicated CPU, latency and runtime/visual
acceptance remain pending Systems; these counters do not establish those claims.

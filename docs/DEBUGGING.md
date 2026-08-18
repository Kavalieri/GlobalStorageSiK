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

## Core

`GlobalStorageSiK.DebugMode` es el interruptor maestro del log general. Las categorías permiten reducir volumen: Network, TerminalAccess, Craft, Inventory, Tooltip, UI y Router. `DebugModeUI` controla por separado volcados de árbol y solapes visuales. Las opciones `DebugSkip*` están en la página separada **GSSiK: Excepciones para pruebas / GSSiK: Testing overrides** porque alteran validaciones; no son opciones de logging.

### Glosario de opciones del Core

| Clave | Español / English | Volumen y función |
|---|---|---|
| `DebugMode` | `Modo depuración (debug)` / `Debug mode` | Interruptor maestro. Por sí solo no activa ninguna categoría. |
| `DebugRelayToClients` | `>> Reenviar logs del dedicado a clientes` / `>> Relay dedicated-server logs to clients` | Preparado por defecto. Envía por lotes acotados solo las líneas que otro logger haya activado. |
| `DebugModeUI` | `>> Interfaz: clics y widgets` / `>> UI: clicks & widgets` | Clics, árbol de widgets, posiciones y solapes. Puede ser voluminoso. |
| `DebugCatNetwork` | `>> Trazas de red` / `>> Network traces` | Resumen de comandos y sincronización. |
| `DebugDetailNetwork` | `>>> DETALLE: payloads completos de red` / `>>> DETAIL: full network payloads` | Payloads completos; alto volumen. |
| `DebugCatTerminalAccess` | `>> Acceso a terminal` / `>> Terminal access` | Manifest, registro, permisos, alcance y apertura. |
| `DebugCatCraft` | `>> Recetas y crafteo` / `>> Recipes & crafting` | Resumen de recetas y préstamos compartidos. |
| `DebugDetailCraft` | `>>> DETALLE: recetas y préstamos de red` / `>>> DETAIL: recipes and network loans` | Probes y decisiones individuales; alto volumen. |
| `DebugCatInventory` | `>> Inventario y transferencias` / `>> Inventory & transfers` | Depósitos, retiradas, snapshots y trabajos masivos resumidos. |
| `DebugDetailInventory` | `>>> DETALLE: taxonomía y objetos` / `>>> DETAIL: taxonomy and items` | Clasificación por objeto/tipo, consolidación por microlote y render por-frame del tooltip; volumen masivo. |
| `DebugCatTooltip` | `>> Tooltip de red` / `>> Network tooltip` | Instalación/recuperación del hook, fallos y fallback del tooltip de cantidades. No registra cada frame. |
| `DebugCatUI` | `>> Ventana del terminal (apertura)` / `>> Terminal window (opening)` | Apertura/reutilización de la ventana y nombrado de nodos. |
| `DebugCatRouter` | `>> Router` / `>> Router` | Resultado resumido de selección de destino. |
| `DebugDetailRouter` | `>>> DETALLE: enrutado por nodo` / `>>> DETAIL: routing per node` | Tier y capacidad de cada candidato; alto volumen. |

Las líneas del Core usan componente y evento estables. Operaciones largas deben emitir estados significativos, no una línea por tick. Si un estado no cambió, no se repite.

Los reescaneos incrementales de zonas emiten una sola línea `ZoneScanJob complete`. `cookingExcluded` cuenta cámaras de cocción rechazadas durante el barrido y `removedIneligible` las entradas GS antiguas eliminadas del registro; esta limpieza afecta solo a metadata, nunca al contenido físico del aparato:

```text
[12.3s][SRV] [GlobalStorageSiK:INFO:ZoneScanJob] complete network=... durationMs=42 zones=2 nodes=18 instances=530 distinctTypes=47 snapshotRows=82 squares=225 loadedSquares=225 added=1 updated=17 offline=0 cookingExcluded=3 removedIneligible=1 limitHit=false
```

La migración de identidades MP antiguas pertenece a `Acceso a terminal / Terminal access` y emite una sola línea por vínculo reparado. El campo `account` procede del `IsoPlayer` autoritativo; los IDs se tratan como opacos y no deben editarse a mano:

```text
[12.3s][SRV] [GlobalStorageSiK:INFO:Permissions] identityMigration | owner network=... account=KavaAccount old=character:7 new=character:gsc_...
```

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
- `[CLI] [GlobalStorageSiK:DEBUG:RedistributeJob] completed breakdown | tiers=1:12,4:3 topTypes=Base.Nails:8,...`: resumen acotado al terminar Auto Sort. `tiers` indica el nivel de destino (1=filtro/hoja exacta, 2=subcategoría, 3=categoría, 4=afinidad, 5=contenedor libre) y `topTypes` muestra como máximo ocho tipos; no emite una línea por objeto.

Al terminar cualquiera de estos casos, el correspondiente `Events.OnTick` se retira. Para diagnosticarlos activa `Modo depuración (debug)` / `Debug mode` e `Inventario y transferencias` / `Inventory & transfers`; añade `Router` y `DETALLE: enrutado por nodo` / `DETAIL: routing by node` solo si se investiga la selección de destino.

### Prueba DEV: leer literatura y devolverla a la red

Opciones mínimas: `Modo depuración (debug)` / `Debug mode` e `Inventario y transferencias` / `Inventory & transfers`. En dedicado, añade `Reenviar logs del dedicado a clientes` / `Relay dedicated-server logs to clients`. No hace falta activar ningún sublog `DETALLE / DETAIL`.

Prueba por separado un libro de habilidad, una revista de receta y una revista o periódico normal: abre el menú contextual de la fila de red, elige `Leer y devolver a la red` / `Read and return to network`, deja terminar una lectura y cancela otra. Debe retirarse exactamente una instancia, encolarse la acción vanilla y regresar el mismo `itemId` a la misma red. Espera `NetworkReadAction read queued`, después `return scheduled` y `return queued`; el servidor debe registrar `depositItems origin=network_read_return operationId=Read-...`. Si la devolución no puede encolarse durante 30 segundos, debe quedar una sola línea `return queue timeout`, cesar el `OnTick` y conservarse el objeto en el inventario del jugador. Guarda `console.txt` del cliente y, en dedicado, el del servidor.

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

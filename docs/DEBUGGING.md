# Diagnóstico y logs

Todos los diagnósticos están desactivados por defecto y no cambian la partida. No debe existir ningún `print()` suelto fuera de la implementación de un logger.

## Core

`GlobalStorageSiK.DebugMode` es el interruptor maestro del log general. Las categorías permiten reducir volumen: Network, TerminalAccess, Craft, Inventory, Tooltip, UI y Router. `DebugModeUI` controla por separado volcados de árbol y solapes visuales. Las opciones `DebugSkip*` alteran validaciones y solo deben usarse en entornos de prueba.

Las líneas del Core usan componente y evento estables. Operaciones largas deben emitir estados significativos, no una línea por tick. Si un estado no cambió, no se repite.

## Craft y Builder

Cada addon tiene sandbox y logger independientes del Core:

- `DebugMode`: interruptor maestro del addon.
- `DebugOperations`: claims, espera de ACK, inicio, resolución y devolución.
- `DebugLifecycle`: apertura/cierre de UI, sesión e instalación de hooks.

Formato:

```text
[12.3s] [GSSiK_Addon_Craft:DEBUG][Operations] craftAttempt START operationId=Craft-...
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
- `return stuckActive`: advertencia única cuando una operación lleva cinco minutos sin señal de fin. No mueve objetos; evita que un cronómetro devuelva herramientas durante un lote largo.

Los orígenes de operación llevan también `operationId`. `origin=player`/`player_queue` identifica movimientos pedidos por el jugador; `operation_complete_return` y `operation_abort_return` identifican devoluciones automáticas tras una señal explícita del addon.

## Reglas de emisión

- Agrupa en una línea los campos pequeños del mismo evento.
- Divide payloads extensos o listas grandes en cabecera + bloques acotados.
- No repitas estados por tick. Registra la entrada al estado y el cambio siguiente.
- No registres dos veces el mismo evento solo porque atraviesa un wrapper; distingue `START`, `WAIT`, `RESUME`, `END` y `ABORT`.
- Los errores incluyen motivo resumido y `operationId`; no vuelques objetos Java completos.
- Los logs compartidos de `CraftSession` se enrutan al sink del addon activo. Core no adopta categorías o textos específicos de Craft/Builder.

## Informe útil para reproducir

Indica versión de Core/addon, SP/host/dedicado/cliente, UI vanilla o mod externo, receta/objeto y el bloque completo desde `START` hasta `END` o `ABORT`. Para problemas de red incluye servidor y cliente con el mismo `operationId`.

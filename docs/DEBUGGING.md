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

## Reglas de emisión

- Agrupa en una línea los campos pequeños del mismo evento.
- Divide payloads extensos o listas grandes en cabecera + bloques acotados.
- No repitas estados por tick. Registra la entrada al estado y el cambio siguiente.
- No registres dos veces el mismo evento solo porque atraviesa un wrapper; distingue `START`, `WAIT`, `RESUME`, `END` y `ABORT`.
- Los errores incluyen motivo resumido y `operationId`; no vuelques objetos Java completos.
- Los logs compartidos de `CraftSession` se enrutan al sink del addon activo. Core no adopta categorías o textos específicos de Craft/Builder.

## Informe útil para reproducir

Indica versión de Core/addon, SP/host/dedicado/cliente, UI vanilla o mod externo, receta/objeto y el bloque completo desde `START` hasta `END` o `ABORT`. Para problemas de red incluye servidor y cliente con el mismo `operationId`.

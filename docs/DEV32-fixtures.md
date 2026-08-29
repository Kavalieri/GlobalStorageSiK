# Core 1.4.3-dev32.2 — fixtures estáticas y matriz de recuperación

Estas fixtures describen los invariantes que debe preservar la validación de
Sistemas. No son pruebas ingame ejecutadas por Desarrollo.

La evidencia automática es `tests/topology_recovery_regression.lua`: carga el
dispatcher real de `GS_Server.lua` con transporte simulado y comprueba sus
paquetes `actionResult`, además de ejecutar la fusión de escaneo real. Se lanza
con Lua 5.1 desde la raíz del repositorio; no certifica PZ ni TEST.

| Caso | Preparación / estímulo | Resultado esperado |
| --- | --- | --- |
| Progreso del escaneo | Red con dos zonas cargadas; iniciar reescaneo. | `scanStatus` informa zona y avance monótono; el trabajo termina en `COMPLETED`, nunca queda pendiente y certifica el snapshot. |
| Zona con excepción | Forzar un contenedor inaccesible en una zona y mantener otra sana. | Se registra `zone_failed`, se continúa con la siguiente zona y se libera el job. |
| Estados terminales | Ejercer éxito, error local/global, cancelación, timeout y cancelación sin job. | Solo se publican `IDLE`, `RUNNING`, `COMPLETED`, `FAILED`, `CANCELLED` o `TIMED_OUT`; `ok=true` y avance de `snapshotRevision` solo ocurren en `COMPLETED`. |
| Sin avance | Bloquear el cursor sin variar su token durante más de 30 s. | Termina como `TIMED_OUT`, informa al terminal y limpia watcher, estado y referencias del job; el snapshot no se certifica. |
| Cancelación admin | Administrador cancela un escaneo activo. | Un único cierre `CANCELLED`, `scanActive=false`, no hay lock ni watcher vivo; la configuración existente no cambia ni se presenta como éxito. |
| Mismo ID físico | Reescanear un cofre con el mismo ID después de cambiar contenido, capacidad o nombre físico. | Se actualizan snapshot, capacidad, nombre físico, presencia y `lastSeenMs`; se conservan nombre visible, reglas, prioridad, notas, pertenencia y zona. La capacidad no forma parte de la identidad. |
| Anomalía de firma del mismo ID | El mismo ID reaparece con tipo, sprite o índice de contenedor inesperado. | Se conserva la firma anterior y se registra anomalía `SIG`; no se normaliza silenciosamente ni se toca configuración lógica. |
| Cofre sustituido o de tipo distinto | Retirar un cofre y descubrir otro con ID/firma física diferente, incluso en la misma posición. | El anterior queda offline y el nuevo entra como alta limpia. No se copian filtros ni reglas; la firma incompatible se rechaza, sin migración confirmable. |
| Carrera borrar zona | Escaneo activo + borrar zona por administrador. | Primero se cancela el escaneo; después se elimina atómicamente la zona y todos sus nodos lógicos. Objetos e inventarios físicos no se tocan. |
| Excluir / eliminar nodo | Configurar reglas y cobertura, excluir; después eliminar lógico. | Excluir conserva reglas y reservas. Eliminar suprime ficha, reglas y reservas; el siguiente descubrimiento crea una ficha limpia. |
| Re-vinculación compatible | Nodo origen offline con firma persistida y descubrimiento reciente, online, limpio y de firma idéntica en la misma red. | El servidor emite token corto; al confirmar revalida red, permisos, origen, destino, firma, recencia y revisión. Copia una vez la configuración lógica completa; el destino conserva identidad física, snapshot, capacidad y su zona. Si cambia la zona, recalcula reservas antes de mutar. |
| Re-vinculación ambigua | Dos o más altas compatibles. | El servidor no emite token hasta que el jugador elige uno de su lista autoritativa; el cliente resalta exactamente esa lista. La confirmación posterior revalida la opción elegida. |
| Rechazos de revinculación | Origen online o ajeno, destino offline/no limpio, firma incompatible, token caducado o revisión/red/permisos alterados. | No se muta ningún registro ni se libera cobertura. El motivo se devuelve como estado breve y texto localizado; no existe selección automática ni migración por capacidad. |
| Preflight de cambio de zona | El candidato compatible pertenece a otra zona con rutas o ítems ya reservados. | La zona física del destino gana. Las reglas trasladadas recalculan sus exclusiones contra los hermanos de destino; una colisión deja origen y destino intactos. |
| Harness automático | Ejecutar `tests/topology_recovery_regression.lua`. | Pasa propuesta única, selección ambigua autoritativa, token obsoleto, permisos, firma incompatible, preflight de cobertura, revinculación exitosa, mismo ID, anomalía `SIG` y nuevo ID sin herencia. |

## QA runtime que corresponde a Sistemas/Kava

En MP dedicado, conservar `server-console.txt`, `console.txt` del cliente y el
registro persistente antes/después de cada caso. Activar únicamente el
diagnóstico de escaneo dirigido si hay fallo; no certificar SP, Hosted ni
pantalla dividida como `PASS`: siguen siendo `COMPATIBILIDAD_TEORICA`.

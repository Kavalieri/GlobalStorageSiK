# Core 1.4.3-dev32 — fixtures estáticas y matriz de recuperación

Estas fixtures describen los invariantes que debe preservar la validación de
Sistemas. No son pruebas ingame ejecutadas por Desarrollo.

| Caso | Preparación / estímulo | Resultado esperado |
| --- | --- | --- |
| Progreso del escaneo | Red con dos zonas cargadas; iniciar reescaneo. | `scanStatus` informa zona y avance monótono; el trabajo termina en `COMPLETED`, nunca queda pendiente. |
| Zona con excepción | Forzar un contenedor inaccesible en una zona y mantener otra sana. | Se registra `zone_failed`, se continúa con la siguiente zona y se libera el job. |
| Sin avance | Bloquear el cursor sin variar su token durante más de 30 s. | Termina como `TIMED_OUT`, informa al terminal y limpia watcher, estado y referencias del job. |
| Cancelación admin | Administrador cancela un escaneo activo. | Un único cierre, `scanActive=false`, no hay lock ni watcher vivo; la configuración existente no cambia. |
| Carrera borrar zona | Escaneo activo + borrar zona por administrador. | Primero se cancela el escaneo; después se elimina atómicamente la zona y todos sus nodos lógicos. Objetos e inventarios físicos no se tocan. |
| Excluir / eliminar nodo | Configurar reglas y cobertura, excluir; después eliminar lógico. | Excluir conserva reglas y reservas. Eliminar suprime ficha, reglas y reservas; el siguiente descubrimiento crea una ficha limpia. |
| Re-vinculación | Nodo origen y descubrimiento nuevo sin configuración en la misma red. | Solo un destino automático y limpio acepta la re-vinculación; conserva la configuración del origen y elimina su ficha anterior. Cualquier destino configurado se rechaza. |

## QA runtime que corresponde a Sistemas/Kava

En MP dedicado, conservar `server-console.txt`, `console.txt` del cliente y el
registro persistente antes/después de cada caso. Activar únicamente el
diagnóstico de escaneo dirigido si hay fallo; no certificar SP, Hosted ni
pantalla dividida como `PASS`: siguen siendo `COMPATIBILIDAD_TEORICA`.

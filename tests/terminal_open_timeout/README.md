# Terminal open timeout contract

`terminal_open_timeout_contract.lua` ejecuta el bloque real de
`GS_TerminalUI_Api.lua` que contiene `OPEN_TIMEOUT_MS`, el mapa privado de
deadlines, `requestOpenAt`, `requestOpenNetwork`, cancelación y expiración,
y carga el `GS_TerminalAccessGuard.lua` real. Usa un shell de borde: su
`onClose` invoca `cancelPendingOpen`; el feedback de fallo cierra el shell y
registra el motivo, sin recrear una vista de error. Dobla solo PZ/transportes,
reloj, jugadores y feedback.
Cubre ACK perdido físico/remoto, expiración a 10 s, `closeTerminal` una vez,
`open_timeout` una sola vez, callback síncrono dentro del envío, segunda
apertura, cuatro jugadores, reloj atrás y cancelación. Las regresiones nuevas
verifican que el callback de timeout se invoque exactamente una vez y pueda
abrir otra solicitud sin cancelación explícita, y que cancelar una solicitud
remota cierre su shell y no altere la secuencia/pending de otro jugador.

Ejecutar desde el workspace o `GlobalStorageSiK-Repo`:

```text
lua51.exe GlobalStorageSiK-Repo/tests/terminal_open_timeout/terminal_open_timeout_contract.lua
```

No certifica callbacks de PZ real, hooks Guard completos, persistencia ni MP.

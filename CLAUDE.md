# GlobalStorageSiK (Core) — Instrucciones para Claude

Repo público: [github.com/Kavalieri/GlobalStorageSiK](https://github.com/Kavalieri/GlobalStorageSiK). Contiene el Core (`GlobalStorageSiK/`) y los addons publicados (`addons/GSSiK_Addon_{Craft,Builder,Tablet}/`). Cada addon tiene su propio `CLAUDE.md` con sus reglas específicas — este fichero cubre solo lo compartido y lo exclusivo del Core.

Ver también `../CLAUDE.md` (raíz de Mods PZ) para la estructura general del entorno de trabajo y el flujo de deploy.

## Reglas críticas (compartidas por Core y todos los addons)

1. **NO eliminar funcionalidad que funcione** — solo mejorar o añadir
2. **Coordenadas como identidad de terminal** — no marcar ítems de inventario con networkId (no fiable en B42 MP)
3. **SP real: `isServer()` e `isClient()` dan AMBOS `false`** — cualquier gate `if isServer() then <lógica autoritativa> end` se salta siempre en SP real. Usar `GlobalStorageSiK.isAuthoritative()` (`GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/shared/GS_Config.lua`) en vez de `isServer()` a pelo — cubre servidor dedicado, host LAN y SP real; solo devuelve `false` para un cliente MP puro.
4. **B42 pickup**: recoger un terminal devuelve PC vanilla, nunca `GS_TerminalUnit`
5. **setCustomName(true) ANTES de setName(name)** — orden obligatorio en B42, si no el nombre no persiste
6. **Kahlua no soporta `next()` de forma fiable** — revienta la función que lo llama en silencio (solo visible en consola real del servidor, no en el cliente ni con pcall normal). Usar siempre un contador explícito para comprobar "tabla no vacía" en vez de `next(t) ~= nil`.

## Reglas exclusivas del Core

- **API pública para addons**: `GlobalStorageSiK.CraftSession` (`GlobalStorageSiK/Contents/mods/GlobalStorageSiK/42/media/lua/client/GS_NetworkCraftSession.lua`) expone sesión de red, claim/return de ítems, inyección de contenedores y registro de hooks/tick por addon (`registerAddonHooks`, `registerTickHandler`, `getActiveSession`, `claimNetworkItem`, `isNetworkContainer`, `newOperationId`, etc.). El Core NO conoce clases de crafteo/construcción concretas — eso vive en cada addon.
- Un addon que quiera engancharse a la sesión de red debe registrarse contra esta API, nunca leer variables internas del Core directamente (quedaron privadas tras la migración Core→addons).
- `patchnote_<lang>.txt` = SOLO la nota de la versión que se sube ahora, nunca el historial completo (Steam ya guarda el historial en su propia página de Change Notes).

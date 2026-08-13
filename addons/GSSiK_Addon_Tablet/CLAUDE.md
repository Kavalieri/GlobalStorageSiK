# GSSiK_Addon_Tablet — Instrucciones para Claude

Addon de acceso remoto al almacén de red desde una tablet portátil (ítem). Reglas compartidas Core/addons en `../../CLAUDE.md` — aquí solo lo exclusivo de Tablet.

## Reglas críticas

1. **Acceso gateado por ítem físico**: `GSSiK_Addon_Tablet_Access.lua` expone `hasCraftTablet(...)` / `hasBuilderTablet(...)` — comprobar el uso de estas funciones en vez de reimplementar la detección de si el jugador lleva la tablet encima.
2. **Alcance inalámbrico depende de una antena instalada**: `getWirelessRangeForNetwork(...)` devuelve `range=0` si no hay antena instalada en la red — no asumir alcance infinito ni fijo.
3. **DebugMode propio**: sandbox option `GSSiK_Addon_Tablet.DebugMode`, logging vía `GSSiK_Addon_Tablet.Log.debug(...)` (gateado por `GSSiK_Addon_Tablet_Sandbox.isDebugMode()`) — no usar `print()` suelto.
4. Este addon aún no tiene gotchas de motor confirmados propios más allá de los ya documentados a nivel Core (SP `isAuthoritative`, orden `setCustomName`/`setName`, `next()` en Kahlua). Si se descubre uno nuevo, documentarlo aquí.

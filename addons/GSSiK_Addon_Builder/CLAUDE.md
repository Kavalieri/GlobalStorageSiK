# GSSiK_Addon_Builder — Instrucciones para Claude

Addon de construcción remota desde el almacén de red. Depende de la API `GlobalStorageSiK.CraftSession` del Core (ver `../../CLAUDE.md`). Reglas compartidas Core/addons en ese fichero — aquí solo lo exclusivo de Builder.

## Reglas críticas

1. **No existe opción "in-place" para construir, ni siquiera en teoría**: `ISBuildIsoEntity.ConsumeBuildEntityItems` (la ruta real de consumo de materiales al construir) SOLO revisa la baldosa bajo el jugador (1 tile) y el inventario propio del jugador — NUNCA contenedores de red inyectados, confirmado leyendo el Lua vanilla. Por tanto Builder SIEMPRE mueve materiales al inventario antes de construir; no hay variante floor-doable que evitar mover como en Craft.
2. **Hook único**: `ISBuildingObject.tryBuild` (parcheado como `patchedTryBuild`) es el punto de entrada — a diferencia de Craft, aquí no hay una segunda UI alternativa tipo "Neat" que soportar.
3. Comparte con Craft el mismo patrón de reclamo/devolución vía `GlobalStorageSiK.CraftSession.claimNetworkItem(...)` — cualquier fix de "no vuelve al almacén" o "dupe item id" en Craft probablemente aplica aquí también, revisar los dos a la vez.

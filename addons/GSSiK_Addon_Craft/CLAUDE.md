# GSSiK_Addon_Craft — Instrucciones para Claude

Addon de crafteo remoto desde el almacén de red. Depende de la API `GlobalStorageSiK.CraftSession` del Core (ver `../../CLAUDE.md`). Reglas compartidas Core/addons en ese fichero — aquí solo lo exclusivo de Craft.

## Reglas críticas

1. **Diseño v1.0 (definitivo, no revisar sin motivo fuerte)**: se mueven herramientas y materiales al inventario del jugador para craftear, y se devuelven al terminar (validando antes que el crafteo fue efectivo). Esto aplica **incluso a recetas `CanBeDoneFromFloor`**, no solo a las que necesitan herramienta.
2. **Por qué no hay crafteo 100% "in-place" desde el almacén**: confirmado por pruebas A/B con logging estructurado (`CraftDiag`) que `HandcraftLogic.performCurrentRecipe()` (nativo, servidor) devuelve `itemsCreados=0` en cuanto `self.containers` incluye CUALQUIER contenedor inyectado de red — incluso si el ítem realmente necesario ya está en el inventario del jugador. Es una limitación del motor, no un bug nuestro. Revisar esto en una tarea futura dedicada si se quiere retomar; no asumir que es fácil de arreglar.
3. **`isCanBeDoneFromFloor()` es un flag POR RECETA**, no por ítem/input — no existe forma de separar "herramienta" vs "material consumido" dentro de una misma receta no-floor vía Lua.
4. **Dos superficies de UI a soportar siempre**: vanilla (`ISWidgetHandCraftControl`) y el mod "Neat Crafting" (`NC_CraftActionPanel`, clase completamente separada con métodos casi idénticos) — si el addon "Neat Crafting" está activo, nuestros hooks sobre `ISWidgetHandCraftControl` NUNCA se disparan. Comprobar `GlobalStorageSiK.Libs.hasNeatCrafting()` y enganchar ambas rutas.
5. **`fixMovedItems()` de vanilla es un check de un solo disparo** en el momento de construir la acción — si el claim servidor (~300-400ms) no ha llegado aún, vanilla se queda con una referencia obsoleta. Por eso el arranque real de `startHandcraft` se difiere con polling por tick hasta confirmación del servidor (`checkPendingCraftStarts`/`checkPendingNeatCraftStarts`), nunca se llama a `originalStartHandcraft` de forma síncrona.
6. **Guardia `claimedItemIds`**: vanilla puede re-evaluar su propia lista de ingredientes al reanudar un `startHandcraft` diferido y volver a pedir un ítem YA reclamado, provocando "Dupe item ID". Comprobar siempre este guard antes de reclamar.
7. **`pendingReturns` se indexa por `itemId` (número), nunca por referencia al objeto `InventoryItem`** — tras el round-trip cliente→servidor→cliente el objeto puede ser una instancia distinta para el mismo ítem lógico.
8. **Devolución de préstamos**: usar siempre `GlobalStorageSiK.Transfer.depositItem` (sistema de prioridad existente), no rastrear un `originalContainer` propio.

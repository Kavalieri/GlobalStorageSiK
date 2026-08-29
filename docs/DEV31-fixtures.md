# Core 1.4.3-dev31 — fixtures de proyección vanilla y cobertura

Estas fixtures describen la aceptación de `GS_VanillaInventoryTaxonomy.lua`.
No son pruebas ejecutables ni certifican una partida: Desarrollo solo valida
sintaxis y contrato estático; Sistemas/Kava ejecutan el runtime MP dedicado.

## Invariantes estáticas

| Caso | Entrada | Resultado esperado |
|---|---|---|
| Ruta nativa | Una instancia visible con ruta nativa ya resuelta | Texto L1 `>` L2 `>` L3 y un único color L1; no se muta el item. |
| Identidad GS | `GlobalStorageSiK.GS_FloppyDisk` | `Global Storage SiK > Disquetes > Grabados`, nunca DisplayCategory vanilla ni clave externa. |
| Fallback seguro | Item sin ruta nativa o ruta `other/*` | Solo `DisplayCategory`/`Category` vanilla de la lista blanca; si ninguna es válida, `Misc`. Nunca `F`, `W`, `native:*` ni categoría externa. |
| Vista limitada | Fila fuera del viewport | No se encola ni clasifica hasta hacerse visible. |
| Render | `ISInventoryPane:renderdetails()` | Consulta solo la caché del panel; no llama a `CategoryResolution.resolve`, no recorre ScriptManager y no escribe en el item. |
| Aislamiento | Dos paneles/jugadores | Cada panel usa su propio estado y caché débil; cerrar/ocultar o cuatro segundos sin render limpia esa caché. |

## Recipientes mutables — sonda runtime pendiente

Opciones mínimas: `Modo depuración (debug)` / `Debug mode`,
`>> Inventario y transferencias` / `>> Inventory & transfers` y
`>>> DETALLE: taxonomía y objetos` / `>>> DETAIL: taxonomy and items`.
Mantener apagado todo lo demás; el último es de alto volumen y solo se activa
durante esta prueba dirigida.

En un cliente remoto del servidor dedicado, usar `Base.WaterBottle` o
`Base.Canteen` y repetir: vacío, lleno con agua, vaciado, lleno con una bebida
y una mezcla que vanilla permita. Conservar `console.txt` del cliente y del
dedicado, más la evidencia de sesión de Inventario si se generó.

La línea esperada en cliente es
`[CLI] [GlobalStorageSiK:DETAIL:VanillaInventoryProjection] fluid probe` e
incluye `amount`, `capacity`, `mixture`, `fluidType` y `projected`. Al llenar
o vaciar debe cambiar una sola vez la firma de esa instancia visible. Agua o
bebida pura se proyectan como `food_drink/beverage`; combustible puro como
`vehicles/consumable`; una mezcla, una API incompleta o una categoría no
confirmada conserva la ruta de recipiente. No se acepta inferencia por nombre
ni por `fullType` mutable.

## Coste y ciclo de vida — sonda runtime pendiente

Con el mismo único bloque de detalle activo, mantener abierto el inventario
diez segundos sin cambiar el recipiente, desplazarlo fuera de la vista y
volver a mostrarlo; después cerrar y reabrir el panel. Conservar ambos
`console.txt`. No debe aparecer una nueva línea `fluid probe` mientras la
firma de una instancia visible no cambie. La implementación limita el trabajo
a filas visibles, procesa como máximo doce entradas por tick y elimina la
caché del panel al ocultarlo o tras cuatro segundos sin render; el ensayo debe
detectar cualquier repetición, coste visible o ruta antigua tras reabrir.

Tras cada transición, comprobar además que ordenar, buscar, selección simple y
múltiple, equipar, transferir y el menú contextual vanilla siguen operativos.
En MP dedicado debe verse el mismo resultado tras la sincronización. SP,
Hosted y pantalla dividida quedan como `COMPATIBILIDAD_TEORICA`: la caché está
asociada al panel/vista y no a un estado global, pero no se certifican runtime
en esta ronda.

## Cobertura de reglas — fixture estática y QA runtime pendiente

La fixture aislada de `GS_RuleCoverage.lua` cubre una Familia con dos detalles:
una reserva de un detalle deja disponible su hermano; una regla de Familia se
guarda con la rama reservada en `coverageExclusions`; AND no convierte una
categoría en reserva y un ítem exacto ya asociado a otro destino se rechaza.
La comprobación es estática y no certifica una partida.

Para la validación MP dedicado, no activar opciones de diagnóstico ajenas: el
caso no introduce una traza nueva. Abrir **Zonas y nodos / Zones and nodes** y
repetir, primero entre dos zonas de la misma red y después entre dos
contenedores de una misma zona:

1. Asignar un Detalle a un destino y abrir el selector del hermano: ese mismo
   Detalle ya no aparece, pero sus hermanos sí.
2. Asignar después la Familia en otro destino: el selector y el resumen solo
   deben representar las ramas que quedan; al depositar, la rama original no
   puede hacer match en la regla nueva.
3. Intentar con dos clientes añadir simultáneamente la misma Familia, Detalle
   o Ítem exacto: solo uno puede recibir `Contenedor actualizado` / `Container
   updated` o `Zona actualizada` / `Zone updated`; el otro recibe
   `Esta categoría u objeto ya está asignado a otro destino.` / `This category
   or item is already assigned to another destination.`
4. Configurar una zona con OR, AND y NOT distinguibles y un nodo con sus tres
   reglas propias. Cerrar/reabrir terminal y reconectar un cliente: conservar
   el orden y la lista completa en el resumen heredado; probar depósito con un
   ítem que cumpla cada caso.

Conservar `console.txt` de cliente y dedicado, además del estado persistente
de la red antes y después de reconectar. No marcar SP, Hosted ni pantalla
dividida como `PASS`: quedan como `COMPATIBILIDAD_TEORICA`.

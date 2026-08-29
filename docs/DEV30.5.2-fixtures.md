# Core 1.4.3-dev30.5.2 — fixtures focales

Estas fixtures acotan exclusivamente la corrección de precedencia de comida y
el resize de Red. No sustituyen el corpus ni una prueba runtime en PZ.

## Precedencia `isSpice()`

El corpus contractual debe quedar en `521/521` para L1, L2 y L3.

| Caso | Señal específica | Resultado esperado |
|---|---|---|
| `Base.RiceBowlClay` | tag `base:ricerecipe` | `food_drink/pantry`, sin L3, fuente `script_item_type` |
| `Base.CannedTomatoOpen` | `ScriptItem.cannedFood` | `food_drink/produce`, sin L3, fuente `script_item_type` |
| `Base.CannedMushroomSoup` | `ScriptItem.cannedFood` | `food_drink/prepared_meal`, sin L3, fuente `script_item_type` |
| `Base.CannedPineapple` | `ScriptItem.cannedFood` | `food_drink/other_food`, sin L3, fuente `script_item_type` |
| `Base.Pepper`, `Base.Salt`, `Base.SeasoningSalt` | ninguna identidad alimentaria específica anterior | `food_drink/ingredient/spice`, fuente `script_item_is_spice` |

La política es estructural: cuando `ItemType=base:food` y una conserva o plato
de arroz aporta su señal oficial, esa identidad decide L2 antes de `isSpice()`.
No hay exclusiones por `fullType` o por nombre individual.

## Resize de Red

Precondición: dos zonas visibles con estados distintos, una fila de contenedor
seleccionada, orden no predeterminado y scroll interior distinto de cero.

1. Conservar la referencia de `scroll._gsNetUi` y de `collapsedZones`.
2. Redimensionar estrecho → amplio → estrecho.
3. Comprobar que ambas referencias son las mismas y que se preservan los dos
   estados de expansión, selección, orden y offsets de scroll aplicables.

La operación no solicita estado nuevo ni recrea el árbol: solo actualiza
geometría mediante `refreshScroll()` y el layout existente de Nodes.

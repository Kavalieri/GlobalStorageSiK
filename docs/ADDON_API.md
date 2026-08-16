# Global Storage SiK — API para addons

Esta API permite extender Global Storage sin depender de sus tablas internas. El Core proporciona el enlace con la red; el addon conserva toda la lógica específica de su función.

## Principio de responsabilidad

El Core es propietario de autoridad SP/MP, acceso a red, registro, sesión, traslado temporal y devolución. El addon es propietario de sus ventanas, hooks vanilla o de terceros, validación funcional, significado de éxito/fallo, mensajes, traducciones, sandbox y logs.

No accedas a variables `local`, registros internos ni tablas de persistencia. Si falta una primitiva general, propón una ampliación pequeña de esta API.

## Registro compartido: `GlobalStorageSiK.AddonApi`

Disponible desde código `shared` mediante `require "GS_AddonApi"`.

```lua
GlobalStorageSiK.AddonApi.register({
    id = "Example",
    modId = "GSSiK_Addon_Example",
    itemType = "GSSiK_Addon_Example.ExampleModule",
    magazineType = "GSSiK_Addon_Example.ExampleMagazine",
    recipeNames = { "Make Example Module" },
    moduleRecipeName = "Make Example Module",
    moduleSkillLevel = 5,
    installDiskItem = "GSSiK_Addon_Example.GS_FloppyDisk_Example",
})
```

Funciones públicas:

- `register(def)`: registra la definición del addon.
- `isModActive(addonId)`: indica si su Mod ID está activo.
- `getDefinition(addonId)` y `listActive()`: consultan definiciones registradas.
- `playerKnowsMagazine(player, addonId)`: comprueba el conocimiento del módulo.
- `isInstalledOnTerminal(networkId, anchor, addonId)`: comprueba instalación en un terminal concreto.

## Sesiones cliente: `GlobalStorageSiK.CraftSession`

Disponible desde código `client` mediante `require "GS_NetworkCraftSession"`. Solo debe usarse para acciones temporales que necesitan pedir objetos prestados a la red.

### Ciclo de sesión

```lua
local ok, reason = GlobalStorageSiK.CraftSession.begin({
    player = player,
    networkId = networkId,
    terminalAnchor = anchor,
    addonId = "Example",
    knownInstalled = true,
    accessMode = "terminal",
    uiMode = "example",
})

if not ok then
    -- El addon traduce y muestra reason.
    return
end
```

Usa `getActiveSession(addonId)`, `getStatus(addonId)`, `validateAccess(player)` y `endSession(reason)` para consultar y cerrar. Solo puede existir una sesión activa a la vez.

### Hooks y tick del addon

```lua
GlobalStorageSiK.CraftSession.registerAddonHooks("Example", installHooks, uninstallHooks)
GlobalStorageSiK.CraftSession.registerTickHandler("Example", onAddonTick)
```

Las funciones de instalación deben ser idempotentes y restaurar exactamente los métodos originales. El Core no debe conocer las clases que engancha el addon.

### Préstamo y devolución

Genera un ID por intento y úsalo en todas las trazas:

```lua
local operationId = GlobalStorageSiK.CraftSession.newOperationId("Example")
local waitingIds, waitingCount, claimed =
    GlobalStorageSiK.CraftSession.claimRecipeItems(
        player, logic, selectedInputs, networkId, operationId, batchCount)
```

Para un objeto individual usa `claimNetworkItem(player, item, sourceContainer, networkId, operationId)`. `isNetworkContainer` e `isItemClaimed` evitan reclamos incorrectos o duplicados. En MP, espera a que cada `itemId` aparezca realmente en el inventario antes de iniciar la acción.

Al finalizar:

- `markOperationComplete(operationId)`: éxito confirmado. Permite devolver herramientas/sobrantes y, si se configuró, enviar el resultado.
- `abortOperation(operationId)`: fallo o cancelación. Descarta cualquier snapshot de resultado y devuelve todo préstamo que siga existiendo, incluso si llega tarde por red.

El addon decide cuándo ocurrió un fallo y cómo explicarlo al jugador. `abortOperation` deliberadamente no contiene UI, traducciones ni razones específicas.

### Contenedores y HandcraftLogic

`narrowContainersForAction(panel, items, addonId)` devuelve una función `restore()`. Llámala siempre, incluso tras error. `tableToArrayList(items)` facilita construir listas Java para APIs vanilla.

La inyección de contenedores sirve para selección y visualización. Si el motor no puede consumir de contenedores remotos, el addon debe reclamar los objetos y ejecutar la acción con contenedores locales; esa política no pertenece al Core.

### Diagnóstico

```lua
GlobalStorageSiK.CraftSession.registerDebugSink("Example", function(message)
    Example.Log.debug("Operations", message)
end)
```

`debugLog(message)` enruta la traza al logger del addon activo. Nunca uses `print()` directo. Consulta [DEBUGGING.md](DEBUGGING.md).

## Compatibilidad y autoridad

- En SP real, `isServer()` e `isClient()` pueden ser ambos `false`. Para mutaciones usa `GlobalStorageSiK.isAuthoritative()`.
- Los mensajes MP deben ser planos, acotados y revalidados por el proceso autoritativo.
- `InventoryItem` puede cambiar de instancia tras sincronización; conserva `itemId`, no la referencia Java.
- No uses `next(table)` en Kahlua; mantén contadores explícitos.

## Estabilidad

La API se versiona junto al Core. Un cambio incompatible requiere migración documentada y revisión de todos los addons oficiales. Las funciones no documentadas aquí se consideran internas.

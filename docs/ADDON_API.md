# Global Storage SiK — API para addons

Esta API permite extender Global Storage sin depender de sus tablas internas. El Core proporciona el enlace con la red; el addon conserva toda la lógica específica de su función.

## Principio de responsabilidad

El Core es propietario de autoridad SP/MP, acceso a red, registro, sesión, traslado temporal, devolución y del framework visual compartido SiK UI. El addon es propietario del contenido y comportamiento de sus pestañas, hooks vanilla o de terceros, validación funcional, significado de éxito/fallo, mensajes, traducciones, sandbox y logs. Un addon no crea otra ventana del terminal ni duplica su superficie.

El proveedor interno vigente es `GlobalStorageSiK.SiK_UI` (`GS_SiK_UI_Core.lua`). Sustituye por completo los nombres retirados Chrome/`createNeat*`; no existe un shim. La referencia pública completa para terceros se documentará después de validar en juego el contrato integrado. Los addons oficiales de este repositorio deben usar ya los nombres SiK UI.

Desde Core `1.3.86-dev32`, el scroll normal y la lista virtual son también propios: `GlobalStorageSiK.TerminalScroll` concentra desplazamiento/barra/recorte y `GlobalStorageSiK.SiK_UI.VirtualList.create(...)` crea el pool virtual usado por Almacén.

Desde `1.3.86-dev33`, `GlobalStorageSiK.SiK_UI.Table` recibe descriptores de columnas parametrizables (`key`, título, ancho fijo/fraccional/flexible, mínimos, alineación, padding y valores a medir) y comparte el layout resultante entre cabecera, filas y clics. Sus métricas visuales comunes viven en `Table.DEFAULTS`, con sobrescrituras por instancia. `SiK_UI.Modal/Window` centraliza confirmaciones, altura por contenido, Escape y geometría de editores; `SiK_UI.Palette` gobierna únicamente la apariencia local. Estos contratos siguen siendo internos durante la DEV: los addons oficiales pueden consumirlos, pero no se promete estabilidad pública a terceros hasta completar la prueba en juego y la documentación formal del framework.

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

## Pestañas cliente declarativas: `GlobalStorageSiK.TerminalExtensions`

Disponible desde código `client` mediante `require "GS_TerminalUI_Extensions"`. El addon registra una definición una sola vez; no construye, adjunta ni vuelve a pintar un panel por cada cambio de estado.

```lua
GlobalStorageSiK.TerminalExtensions.registerDefinition("example", {
    module = Example.TerminalPanel,
    titleKey = "IGUI_Example_Tab",
    iconPath = "media/ui/Example/Tab.png",
    panelField = "examplePanel",
})
```

El módulo debe exponer `buildPanel(panel, terminal)` y `refresh(panel, terminal)`; `layout(panel, innerW, innerH)` es opcional. Si necesita instalar comportamiento adicional una sola vez sobre el panel, puede aportar `setupPanel(panel, terminal)` en la definición.

Para reflejar la instalación de una disquetera/periférico o cualquier otra regla del addon:

```lua
GlobalStorageSiK.TerminalExtensions.setTabVisible(terminal, "example", visible)
```

Al pasar a visible, el Core crea como máximo un panel para esa combinación `terminal + tabKey`, llama una sola vez a `buildPanel`/`setupPanel` y registra el icono. Ocultar retira el slot lateral, no destruye el panel; volver a mostrar reutiliza la misma instancia. Activar la pestaña adjunta exclusivamente ese panel al `contentHost`, aplica primero el layout y después llama a `refresh`. Esto evita ventanas superpuestas, `addChild` duplicados y reconstrucciones al recibir otro `terminalState`.

`registerTab(terminal, tabKey, opts)` se conserva para compatibilidad con consumidores antiguos, pero el contrato recomendado para código nuevo y addons oficiales es `registerDefinition`.

Los addons también pueden aportar una apertura interna al panel de staff sin que el Core conozca su implementación:

```lua
GlobalStorageSiK.TerminalExtensions.registerStaffAction("example.vanilla", {
    labelKey = "IGUI_Example_OpenVanilla",
    order = 30,
    invoke = function(dashboard)
        Example.openVanillaForStaff(dashboard)
    end,
})
```

`registerStaffAction(actionKey, opts)` es idempotente por clave. `getStaffActions()` devuelve un snapshot ordenado por `order` y después por clave; puede filtrar una acción mediante el callback opcional `isAvailable`. El Core solo presenta y ejecuta la acción. Detección de mods externos, elección de UI y sesiones siguen siendo responsabilidad del addon.

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
local waitingIds, waitingCount, claimed, batchShortfall =
    GlobalStorageSiK.CraftSession.claimRecipeItems(
        player, logic, selectedInputs, networkId, operationId, batchCount)
```

Para un objeto individual usa `claimNetworkItem(player, item, sourceContainer, networkId, operationId)`. `isNetworkContainer` e `isItemClaimed` evitan reclamos incorrectos o duplicados. Si una segunda acción encolada reutiliza una herramienta ya prestada y ahora visible como local, `retainClaimedItem(itemId, operationId)` añade esa operación al mismo lease sin mover ni duplicar el objeto; la herramienta solo vuelve cuando terminan todas las operaciones asociadas. `claimRecipeItems` adopta automáticamente esos inputs compartidos. En MP, espera a que cada `itemId` aparezca realmente en el inventario antes de iniciar la acción.

Al finalizar:

- `markOperationComplete(operationId)`: éxito confirmado. Permite devolver herramientas/sobrantes y, si se configuró, enviar el resultado.
- `abortOperation(operationId)`: fallo o cancelación. Descarta cualquier snapshot de resultado y devuelve todo préstamo que siga existiendo, incluso si llega tarde por red.

El addon decide cuándo ocurrió un fallo y cómo explicarlo al jugador. `abortOperation` deliberadamente no contiene UI, traducciones ni razones específicas.

### Contenedores y HandcraftLogic

`narrowContainersForAction(panel, items, addonId)` devuelve una función `restore()`. Llámala siempre, incluso tras error. `tableToArrayList(items)` facilita construir listas Java para APIs vanilla.

Si una llamada vanilla vuelve a consultar `ISInventoryPaneContextMenu.getContainers` justo antes de serializar una acción, usa la suspensión acotada:

```lua
local ok, result = GlobalStorageSiK.CraftSession.withContainerInjectionSuspended(
    originalVanillaMethod, action)
```

La función restaura la inyección incluso si la llamada falla y admite anidamiento. El addon sigue siendo responsable de decidir en qué punto de su flujo resulta necesario aislar contenedores físicos.

La inyección de contenedores sirve para selección y visualización. Si el motor no puede consumir de contenedores remotos, el addon debe reclamar los objetos y ejecutar la acción con contenedores locales; esa política no pertenece al Core.

`claimRecipeItems(..., batchCount)` amplía los consumibles seleccionados para todas las unidades del lote. La clasificación usa `CraftRecipeData:getAllNotKeepInputItems()`; `getAllPutBackInputItems()` no identifica herramientas y no debe usarse para ese fin. Los objetos `keep` no se multiplican. Cada `InventoryItem`/`itemId` asignado por `CraftRecipeData` o encontrado en los contenedores cuenta como una sola entrada consumible: `InventoryItem:getCount()` no representa capacidad disponible para este contrato y no debe usarse para reducir el número de IDs requeridos (por ejemplo, tres objetos `Base.Nails` no cubren por sí solos los nueve clavos de un lote de tres recetas que consume tres por unidad). El cuarto retorno, `batchShortfall`, indica cuántas entradas adicionales no pudieron reclamarse; si es mayor que cero, el addon debe abortar, explicar el fallo y no iniciar una receta parcial. El consumidor debe conservar la cantidad solicitada cuando difiera la llamada vanilla hasta recibir los ACK.

`CraftSession.CLAIM_RECIPE_CONTRACT_VERSION` vale `2` desde que existe ese cuarto retorno. Como Core y addons son elementos Workshop independientes, un consumidor debe tolerar una actualización escalonada: si `batchShortfall` no es numérico, una receta de una unidad puede tratarlo como cero; un lote debe abortarse y pedir que se actualice Core, nunca continuar parcialmente.

El Core no controla el ciclo de vida concreto del panel ni sus refrescos entre unidades. Si un addon encola varias acciones que comparten el mismo `HandcraftLogic`, debe mantener el aislamiento de contenedores físicos durante todo el lote: un refresco intermedio que vuelva a inyectar contenedores virtuales puede hacer que una acción emita el callback de completado sin crear resultado. El addon llama `markOperationComplete(operationId)` solo después de la última unidad real y conserva en su propio código cualquier adaptación específica de Vanilla, Neat u otra interfaz.

Los comandos automáticos `depositItems` incluyen `origin` y, cuando existe, `operationId`. Valores actuales emitidos: `operation_result_deposit`, `operation_complete_return` y `operation_abort_return`. Los depósitos iniciados por el jugador usan `player` o `player_queue`. El servidor valida esos valores, los refleja en `actionResult.transfer` y escribe un único resumen `Deposit`, de modo que un addon o una revisión de logs no confunda una devolución automática con una transferencia manual. Una operación sin callback solo genera `return stuckActive`: el Core no devuelve préstamos por tiempo porque un lote legítimo puede durar varios minutos.

### Diagnóstico

```lua
GlobalStorageSiK.CraftSession.registerDebugSink("Example", function(message)
    Example.Log.debug("Operations", message)
end)
```

`debugLog(message)` enruta la traza al logger del addon activo. Nunca uses `print()` directo. Consulta [DEBUGGING.md](DEBUGGING.md).

### Relé neutral de diagnósticos

El Core expone `GlobalStorageSiK.DebugRelay` como transporte neutral. No contiene categorías ni decisiones específicas de Craft, Builder u otro addon.

```lua
local ok, relay = pcall(require, "GS_DebugRelay")
if ok and relay then
    relay.requestClientSubscription("ExampleAddon")
    relay.emit(alreadyFormattedLine)
end
```

- `processTag()` devuelve `CLI`, `SRV`, `HOST` o `SP` para formar una sola línea con origen estable.
- `requestClientSubscription(source)` declara que el addon cliente quiere recibir lotes mientras su propio diagnóstico esté activo.
- `emit(line)` entrega una línea ya formada al sink del dedicado; en otros procesos no crea una segunda copia.
- `printRemotePayload(payload)` pertenece al receptor Core y no debe usarse para volver a loguear el payload.

El servidor limita cola, tamaño de línea, bytes por lote y frecuencia de envío. Un addon no abre comandos de red propios si puede reutilizar este contrato. El addon sigue siendo responsable de su logger, categorías, sandbox, textos y decisión de cuándo suscribirse.

## Acceso a contenedores por zona

Los permisos se conceden a zonas y se aplican a todos los contenedores que
pertenecen a ellas. Un addon no debe interpretar ni copiar la tabla persistente
de restricciones. Para comprobar una zona usa:

```lua
local allowed = GlobalStorageSiK.Permissions.canAccessZone(player, networkId, zoneId)
```

Para trabajar con la salida de `Network.getLiveContainers`, usa el filtro
neutral del Core:

```lua
local live = GlobalStorageSiK.Network.getLiveContainers(networkId)
live = GlobalStorageSiK.Permissions.filterLiveContainers(player, networkId, live)
```

`CraftingBridge.collectNetworkContainers(networkId, player)` y
`mergeContainerLists(base, networkId, player)` ya aplican el mismo contrato
cuando se proporciona el jugador. La validación cliente solo mejora la UI: el
proceso autoritativo vuelve a filtrar depósitos, retiradas y reclamos por ID.

`GlobalStorageSiK.Permissions.getCharacterId(player)` devuelve una identidad
opaca de la encarnación concreta: un UUID generado por el proceso autoritativo
y persistido en `player:getModData()`. Cuenta, Steam ID y `sqlId` se conservan
solo para auditoría y migración; B42 puede reutilizar la cuenta y la fila/ranura
persistente cuando se crea otro personaje, por lo que nunca autorizan solos.
Un addon puede compararla durante una operación, pero no debe construirla,
separarla ni persistir una copia propia: el Core posee su esquema y sus
migraciones. Los nombres visibles, `SurvivorDesc:getID()`, `OnlineID` y
`getPlayerNum()` son presentación o IDs temporales, nunca claves persistentes.
El espacio de nombres del mundo ya lo aporta el `GlobalModData` de esa partida;
la misma cuenta o personaje en otro mundo no comparte registros de red GS.

La ausencia de una excepción significa acceso permitido. Por ello los miembros
existentes y las zonas creadas en el futuro empiezan habilitados. Owner, admins
de red y staff del servidor tienen acceso total.

## Acceso remoto inalámbrico y selector de red

Un addon registra un proveedor inalámbrico neutral desde código `shared`:

```lua
GlobalStorageSiK.TerminalAccess.registerWirelessProvider({
    id = "ExampleWireless",
    capabilities = { remoteTerminal = true },
    hasAccess = function(player) return true end,
    getRange = function(player) return 24 end,
    getRangeForNetwork = function(player, networkId, anchor) return 12 end,
})
```

`id` y `hasAccess` son obligatorios. Registrar de nuevo el mismo `id` sustituye
la definición anterior sin duplicarla. `getRange` es solo el techo de búsqueda;
`getRangeForNetwork` decide el alcance real para la red/ancla concreta. El Core
recorre únicamente terminales activos registrados, permisos y proveedores; el
addon conserva la política de ítems, tiers y capacidades.

En cliente, los ítems remotos se conectan sin crear comandos propios:

```lua
GlobalStorageSiK.ItemActions.registerTabletItem(fullType, labelKey, onUse)
local requestId = GlobalStorageSiK.TerminalUI.requestRemoteNetworks(callback, player)
GlobalStorageSiK.TerminalUI.cancelRemoteNetworkRequest(requestId, player)
local openId = GlobalStorageSiK.TerminalUI.requestOpenNetwork(networkId, player, callback)
GlobalStorageSiK.TerminalUI.cancelOpenNetworkRequest(openId, player)
GlobalStorageSiK.Client.registerTransientCleanup("MyAddonUi", cleanupCallback)
```

Solo hay una solicitud pendiente por `playerNum`; una nueva reemplaza la
anterior y las respuestas tardías se descartan por `requestId`. El servidor
limita frecuencia y cardinalidad. El callback recibe `(networks, reason)`: cada
fila contiene `networkId` opaco, nombre, `selectable`, razón, distancia, alcance,
`providerId` y capacidades acotadas cuando existen. Las redes del jugador que
no están disponibles pueden mostrarse deshabilitadas para explicar el motivo,
pero `requestOpenNetwork` vuelve a validar permiso, terminal, proveedor, antena
y alcance antes de abrir. Su callback recibe `(accepted, reason, payload)` solo
para la respuesta exacta correlacionada por `playerNum + requestId`; el modal no
se cierra al enviar. El consumidor cancela descubrimiento y apertura al cerrar,
registra su limpieza transitoria para muerte/cambio de sesión y no instala
`OnTick` ni listeners globales.

## Acciones contextuales de ítem

Los addons pueden declarar operaciones sobre ítems del inventario real o filas
serializadas del Almacén sin añadir conocimiento específico al Core:

```lua
GlobalStorageSiK.ItemActions.registerProvider({
    id = "example.item-actions",
    addonId = "Example",
    capabilities = { "craft" },
    actions = {
        { id = "craft", labelKey = "IGUI_Example_Craft" },
    },
    appliesTo = function(context, actionId) return actionId == "craft" end,
    buildRequest = function(actionId, context)
        return { actionId = actionId, source = context.extra.source }
    end,
    executeRequest = function(request, context) return true end,
})
```

Registrar de nuevo el mismo `id` sustituye atómicamente su definición. El Core
valida, ordena y compone el menú; el addon conserva aplicabilidad, payload y
ejecución. `context.items` solo vive durante el gesto y puede contener
`InventoryItem` o snapshots de Almacén, por lo que no debe conservarse ninguna
referencia Java. `buildRequest` devuelve datos Lua planos y acotados.

`executeRequest` debe reutilizar la API autoritativa existente del addon. Craft
y Builder usan `GlobalStorageSiK.CraftSession`: esta revalida addon, red,
alcance, sesión e insumos y conserva el flujo de claim/return. El registro no
crea comandos cliente-servidor nuevos ni convierte `appliesTo` en autoridad.
Para dirigir la UI vanilla sin autoejecutar, las firmas públicas son
`CraftSession.openHandcraft(mode, recipe, itemString)` y
`CraftSession.openBuild(mode, recipe, itemString)`: se pasa una receta exacta o
un filtro `!fullType`, nunca ambos. El jugador confirma en vanilla y ese clic
atraviesa los hooks autoritativos del addon.

## Compatibilidad y autoridad

- En SP real, `isServer()` e `isClient()` pueden ser ambos `false`. Para mutaciones usa `GlobalStorageSiK.isAuthoritative()`.
- Los mensajes MP deben ser planos, acotados y revalidados por el proceso autoritativo.
- `InventoryItem` puede cambiar de instancia tras sincronización; conserva `itemId`, no la referencia Java.
- No uses `next(table)` en Kahlua; mantén contadores explícitos.

## Estabilidad

La API se versiona junto al Core. Un cambio incompatible requiere migración documentada y revisión de todos los addons oficiales. Las funciones no documentadas aquí se consideran internas.

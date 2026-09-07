# Global Storage SiK integration guide

This document explains the supported boundary for addons. The complete method,
result-code and lifecycle reference lives in [API.md](API.md); neutral visual
composition belongs to [SiK UI Framework](FRAMEWORK.md).

## Ownership model

Core owns network authority, permissions, installation records, remote-access
revalidation, bounded requests and shared work-session mechanics. An addon owns
its recipes or actions, third-party hooks, success and failure semantics,
translations, sandbox options, diagnostics and product assets.

There are only two public integration roots:

- `GSSiK.API`, loaded from `GSSiK_API` in shared code or
  `GSSiK_API_Client` in client code;
- `SiK.UI`, loaded from `SiK_UI` for neutral client-side presentation.

The private `GlobalStorageSiK` namespace, internal registries, terminal state,
taxonomy modules and `GS_*` implementation modules are not addon APIs. The old
`GlobalStorageSiK.SiK_UI`, `GlobalStorageSiK.AddonApi`,
`GlobalStorageSiK.CraftSession` and `GlobalStorageSiK.TerminalExtensions` routes
are retired and have no supported alias.

## Minimal addon flow

Declare both dependencies in the addon `mod.info`:

```text
require=SiKUIFramework,GlobalStorageSiK
```

Register shared product data through the public facade:

```lua
require "GSSiK_API"

local ok, code, registration = GSSiK.API.Addon.register({
    id = "example.addon",
    modId = "ExampleAddon",
    itemType = "ExampleAddon.Module",
    magazineType = "ExampleAddon.Magazine",
    recipeNames = { "Make Example Module" },
    moduleRecipeName = "Make Example Module",
    moduleSkillLevel = 5,
    installDiskItem = "ExampleAddon.NetworkDisk",
})

if not ok then
    error("Example addon registration failed: " .. tostring(code))
end
```

Keep the returned registration and call `registration:dispose()` at the
consumer lifecycle boundary. Descriptors returned by the API are copies; do
not retain Java objects, callback payloads or private Core state.

Client surfaces use the client facade:

```lua
local API = require "GSSiK_API_Client"
require "SiK_UI"
local Surface = require "ExampleAddon/UI/Generated/TabExample"
local Context = require "ExampleAddon/UI/TabExampleContext"

local ok, code, tabRegistration = API.Terminal.registerTab({
    key = "example",
    titleKey = "IGUI_Example_Tab",
    iconPath = "media/ui/ExampleAddon/Tab.png",
    surface = Surface,
    builder = SiK.UI.SurfaceHost.mount,
    contextFactory = Context.create,
    panelField = "examplePanel",
    order = 100,
})
```

The exact descriptor schema and available helpers are versioned in
[API.md](API.md). A terminal tab contributes content to the existing terminal;
it must not create another terminal window or duplicate the shell.

## Capability negotiation

Call `GSSiK.API.Capabilities.describe()` or
`GSSiK.API.Capabilities.has(name, minimumVersion)` before using an optional
capability. Current public capabilities are `Access`, `Addon`, `Diagnostics`,
`Installation`, `ItemActions`, `RemoteAccess`, `Terminal` and `WorkSession`.

`Network`, `Storage`, `Taxonomy` and `Events` are not public capabilities.
Their internal tables and modules must not be imported. If an integration needs
one, propose the smallest bounded plain-data contract rather than reading Core
internals.

## Work sessions

Craft and Builder use `GSSiK.API.WorkSession`. It owns the generic lifecycle for
opening a supported activity, claiming exact inputs, waiting for authoritative
acknowledgements, completing or aborting an operation, returning borrowed items
and disposing temporary handles. The addon still decides when its own action
has succeeded or failed.

Do not use the retired `CraftSession` name. Do not start a partial batch when a
claim reports a shortfall. Always close the session and dispose scoped handles
on completion, cancellation, UI close, death or reconnect.

## Authority and data rules

- The client requests; the authoritative process revalidates identity,
  permission, terminal, range, revision and payload.
- SP authority uses the Core authority helper; `isServer()` alone does not
  cover singleplayer.
- Messages and descriptors remain plain, bounded data.
- Persist stable IDs, not live `InventoryItem` or UI references.
- Registrations and requests are lifecycle resources and must be disposed.
- Addon diagnostics use their own logger and categories, optionally transported
  through `GSSiK.API.Diagnostics`; never use loose `print()` calls.

## Compatibility

The API is versioned with Core. An incompatible change requires a documented
migration and review of every official addon. Undocumented functions and all
private namespaces are unstable and unsupported.

## Resumen en español

Los addons cargan únicamente `GSSiK.API` para mecánicas de producto y `SiK.UI`
para presentación neutral. Core conserva autoridad, permisos y validación; cada
addon conserva su comportamiento, recursos, textos, sandbox y diagnóstico. No
se importan internals ni namespaces retirados, se negocian capacidades, se
conservan y liberan los handles, y toda mutación vuelve a validarse en el
proceso autoritativo.

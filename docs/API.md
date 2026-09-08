# GSSiK product API

`GSSiK.API` is the public product API of Global Storage SiK. It exposes
Global Storage mechanics to addons and other integrations. It is not a UI
toolkit: reusable visual components belong to the independent `SiK.UI`
framework (`SiKUIFramework`, ModID `SiKUIFramework`).

The public namespaces are deliberately separate:

- `SiK.UI` — neutral reusable UI framework.
- `GSSiK.API` — Global Storage SiK product mechanics.
- `MMSiK.API` — Manure Manager SiK product mechanics.
- `SCLGSiK.API` — SiK Corpse Loot Guard product mechanics.

Neither Global Storage nor this API creates aliases for the other product APIs
or for `SiK.UI`.

## Loading and scope

Load only the module for the execution side that needs it:

```lua
-- shared
require "GSSiK_API"

-- client-only extensions (also loads the shared API)
require "GSSiK_API_Client"
```

`GSSiK_API_Client` loads the client-only `WorkSession` and `Terminal`
extensions. Never require those client modules from server code. Client calls
request work; they never grant authority. Persistent mutations are still
revalidated by the authoritative Core process.

All Global Storage API calls use the result convention below unless a specific
method says otherwise:

```lua
local ok, code, value = GSSiK.API.Addon.get("example.addon")
if not ok then
    -- code is a stable string such as ERR_SCHEMA or ERR_NOT_FOUND
    return
end
```

Public descriptor tables are copies. Do not retain or mutate internal product
objects, Java objects, registries, terminal state, or callback-owned payloads.

## Capability negotiation

`GSSiK.API.Capabilities.describe()` returns a fresh descriptor:

```lua
{
    api = "GSSiK.API",
    apiVersion = "1.0.0",
    capabilities = {
        { name = "Access", version = "1.0.0" },
        { name = "Addon", version = "1.0.0" },
        { name = "Diagnostics", version = "1.0.0" },
        { name = "Installation", version = "1.0.0" },
        { name = "ItemActions", version = "1.0.0" },
        { name = "RemoteAccess", version = "1.0.0" },
        { name = "Terminal", version = "1.0.0" },
        { name = "WorkSession", version = "1.0.0" },
    },
}
```

`Capabilities.has(name[, minimumVersion])` returns `true, "OK"` when the
named contract is available and compatible. It returns `false` with
`ERR_SCHEMA`, `ERR_CAPABILITY_UNAVAILABLE`, or `ERR_CAPABILITY_VERSION`
otherwise. A capability descriptor is not permission to load a client module
on the server; apply the scope rules above.

The following names are **not implemented public capabilities** and must not
be treated as available: `Network`, `Storage`, `Taxonomy`, and `Events`.

### Display descriptors are not a public capability

The current product resolves category path/colour, fluid composition and
quantity, recorded-media identity/title/teachings, stable group/selection IDs
and inventory revision before the UI groups, searches or renders a row. Those
fields are one internal product truth shared by warehouse rows, child rows,
tooltips and transfer selection.

They are not currently exposed as `GSSiK.API.Taxonomy`,
`GSSiK.API.Storage` or another undocumented namespace. Integrations must not
read the private snapshot, index, recorded-media or taxonomy modules directly.
If a reusable external capability is added later, it must publish bounded
plain-data descriptors and preserve the same identity and authority rules.

## Shared capabilities

### `Addon`

`Addon.register(definition)` atomically registers or replaces a validated addon
definition and its optional disk program. It returns `ok, code, registration`.
The registration has a generation-safe `registration:dispose()` method: an old
handle cannot remove a newer replacement with the same addon ID.

`Addon.get(addonId)` returns a copied public descriptor.
`Addon.listActive()` returns copied descriptors for active addons.

The registry owns definition validation, capacity limits, disk-program pairing,
and rollback-safe disposal. Consumers must not use Core registries directly.

An addon definition may provide
`resolveRecipeBookRequirement(recipeName) -> boolean|nil`:

- `true` or `false` is an explicit addon-owned override for that recipe;
- `nil` is an explicit abstention, including an unknown recipe or an unset
  addon-specific option;
- the callback may read only state owned by that addon. It must never read
  `SandboxVars.GlobalStorageSiK` or the private `GlobalStorageSiK` namespace.

`Addon.resolveRecipeBookRequirement(addonId, recipeName)` invokes that callback
through the public boundary. It returns `true, "OK", override` for a boolean
override, and `true, "OK", nil` when the addon has no callback or abstains. The
Core recipe policy is the sole owner of the configured Global Storage fallback;
addons must not duplicate or precompute it.

Malformed IDs or recipe names return `ERR_SCHEMA`, and an unknown addon returns
`ERR_NOT_FOUND`. A callback exception or a result other than boolean/`nil`
returns `ERR_INTERNAL`. These typed errors do not authorize a consumer to read
private Core state; the Core policy decides its own safe fallback.

### `Access`

`Access.registerProvider(definition)` registers one validated remote-access
provider and returns `ok, code, registration`. Provider IDs are generation
scoped and the returned `dispose()` removes only that generation. The Core owns
provider validation, limits and lifetime; the addon owns its policy callbacks
and its own sandbox/debug categories.

### `Installation`

`Installation.get(networkId, anchor, addonId)` returns a plain-data copy of one
installed-addon record. `anchor` contains numeric `x`, `y`, and optional `z`.

`Installation.isInstalled(networkId, anchor, addonId)` returns
`ok, code, installed`.

Both calls reject malformed identifiers and coordinates with `ERR_SCHEMA`, use
`ERR_NOT_FOUND` for no installation, and never return a live addon record.

### `Diagnostics`

`Diagnostics.processTag()` returns the normalized process tag when the relay is
available. `Diagnostics.subscribe(channel)` requests a bounded relay channel.
`Diagnostics.emit(line)` emits one already formatted line through that optional
relay. They use `ERR_SCHEMA`, `ERR_UNAVAILABLE`, or `ERR_INTERNAL` when they
cannot complete. The addon remains responsible for categories, sandbox gates,
and message content.

## Client-only capabilities

### `RemoteAccess`

`RemoteAccess.list(player, callback)` requests accessible remote networks.
`RemoteAccess.open(networkId, player[, callback])` requests opening one remote
network. Their callbacks receive `callback(ok, code, copiedPayload)`.

Both return `ok, code, handle`. `handle:cancel()` completes the callback with
`ERR_CANCELLED`; `handle:dispose()` silently releases it. One active request is
kept per player, and lifecycle cleanup releases requests on transient client
cleanup. A server acceptance is still required for `open`.

`RemoteAccess.registerCleanup(id, handler)` registers product-owned cleanup and
returns a generation-safe disposable registration.

### `ItemActions`

`ItemActions.registerTablet(definition)` registers a validated tablet item
(`fullType`, `labelKey`, `onUse`).

`ItemActions.registerProvider(definition)` registers a validated provider with
its bounded action declaration and request callbacks. Both return
`ok, code, registration`; the registration is generation-safe and disposable.
They are an action integration contract, not a shortcut around server
authorization.

### `Terminal`

`Terminal.registerTab(definition)` and
`Terminal.registerStaffAction(actionKey, definition)` register client terminal
extensions and return disposable generation-safe registrations.

`Terminal.current()`, `Terminal.player(terminal)`, and
`Terminal.state(terminal)` provide the currently open terminal, its player, and
a projected state copy. `Terminal.isAddonInstalled`, `Terminal.isTabEnabled`,
`Terminal.setTabVisible`, and `Terminal.refresh` are client presentation
helpers. They neither mutate persistent network state nor bypass permissions.

### `WorkSession`

`WorkSession` replaces the former public `CraftSession` name; `GSSiK.API.CraftSession`
is deliberately cleared and is not a supported public alias.

This client capability owns the lifecycle shared by craft and builder flows:

- lifecycle: `registerLifecycle`, `begin`, `endSession`, `get`, `status`,
  `getOpenFailure`, `reportOpenFailure`;
- opening: `openHandcraft`, `openBuild`;
- operations: `startOperation`, `claimRecipeInputs`, `claimItem`,
  `completeOperation`, `abortOperation`;
- scoped helpers: `narrowInputs`, `withContainerInjectionSuspended`,
  `setResultDestination`, `getResultDestination`.

Operations are bounded to their player and return `ERR_OPERATION`, `ERR_OWNER`,
`ERR_SOURCE`, `ERR_REQUEST`, `ERR_SESSION`, `ERR_SCHEMA`, or `ERR_UNAVAILABLE`
when relevant. `narrowInputs` returns a disposable/restore handle. Consumers
must close sessions and dispose temporary handles on every completion,
cancellation, reconnect, or UI close.

While terminal access is provisionally revoked or being revalidated, `begin`,
`startOperation`, `claimRecipeInputs` and `claimItem` return `ERR_SESSION` before
starting work or moving items. This applies to local SP calls as well as MP.
Completion, abort and return paths remain available for already accepted work;
an outstanding response does not grant a new session.
Consumers must consume a rejected `ERR_SESSION` attempt while their remote
session is active; calling the original vanilla start as a fallback would bypass
the access gate with network inputs still attached. Core supplies the common
access feedback; the addon retains ownership of its action lifecycle.

`Diagnostics.registerWorkSessionSink(addonId, callback)` is the optional
client-side observer registration for session diagnostics. It is generation
safe and disposable.

## Error and lifecycle rules

Common codes are `OK`, `ERR_SCHEMA`, `ERR_CAPACITY`, `ERR_NOT_FOUND`,
`ERR_INTERNAL`, and `ERR_UNAVAILABLE`. Client request paths may additionally
return `ERR_REQUEST`, `ERR_CANCELLED`, or `ERR_PAYLOAD`; work sessions add the
operation codes listed above.

Every registration or request handle owned by a consumer must be retained and
disposed at the consumer's unload/close boundary. An API handle is a lifecycle
resource, not a static configuration record.

## What does not belong here

Do not add a public wrapper merely to rename one vanilla call. A `GSSiK.API`
entry must provide reusable product value: validation and normalization, stable
result codes, lifetime management, defensive projections, observability, or
authoritative revalidation. If vanilla already supplies the entire needed
contract, use vanilla directly. If the need is visual and reusable, use or
extend `SiK.UI` instead.

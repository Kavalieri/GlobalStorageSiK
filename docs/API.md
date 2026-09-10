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
        { name = "ItemLease", version = "1.0.0" },
        { name = "DeviceLease", version = "1.0.0" },
        { name = "ItemPresentation", version = "1.0.0" },
        { name = "InventoryView", version = "1.0.0" },
        { name = "RemoteAccess", version = "1.0.0" },
        { name = "Search", version = "1.0.0" },
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

### `Search`

`Search.registerTokenProvider({id, priority=0, resolve})` returns
`ok, code, registration`. Load `GSSiK_API` on the consuming side. Core installs
no provider; without one, search text and native results remain unchanged.
Tokens augment item text search only. They never identify a player, grant a
permission, translate a name, or change an item's native taxonomy.

The ID is 1–64 ASCII letters/digits/underscore/dot/hyphen, beginning with a
letter or digit; priority is an integer from -1000 to 1000. Up to 16 providers
run in descending priority, then ascending ID order. Replacing an ID is atomic;
an older `registration:dispose()` cannot remove its replacement. Unknown
definition fields or metatables return `ERR_SCHEMA`; capacity returns
`ERR_CAPACITY`. Registration during a resolver returns `ERR_BUSY`.

`resolve(source)` receives a fresh plain table with `fullType`, localized
`displayName`, `catalogEpoch` and `languageEpoch`. It receives no live row,
inventory item, player or Java reference. Return a dense array of at most 16
nonempty strings, each at most 128 native string units and at most 1024 units
in total. Limits reject oversize tokens; they never cut Unicode strings.
Core applies its existing Unicode-preserving search normalization, deduplicates
tokens and retains at most 64 across providers. Equal-priority overlapping
tokens are deterministic and additive, not competing classification claims.

Resolvers run on a source cache miss, not per frame. Cache keys cover fullType,
localized display text, catalogue/language epochs and registration generation;
targeted catalogue invalidation evicts the affected fullTypes. Results, including
empty lists, are cached (up to 4096 sources). An exception or malformed result
contributes no tokens and quarantines that provider for the current epoch.
Providers must do bounded synchronous work; there is no preemption of third-party
Lua callbacks and no background polling or built-in pinyin engine.

Taxonomy adapter discovery is a separate **internal, inactive** boundary in
`GS_TaxonomyAdapterRegistry.lua`. It is not a public capability and the native
classifier does not load or call it. No third-party adapter ships in this DEV.
The registry accepts bounded descriptors (`id`, exact `targetModId`, integer
`priority`, `detect`, `fingerprint`, `collectEvidence`); an explicit diagnostic
`discover(activeModIds)` checks only active targets, boolean detection and a
bounded stable fingerprint. Failures contribute no candidate. Descending
priority and ascending ID provide deterministic discovery; equal top priorities
for one target are reported as conflicts. Every result remains inactive,
including the highest priority candidate, and `collectEvidence` is never run.
This reserves the boundary for future script evidence without accepting mutable
translated categories as native paths or changing current classifier hashes
when the registry is empty.

### `Addon`

`Addon.register(definition)` atomically registers or replaces a validated addon
definition and its optional disk program. It returns `ok, code, registration`.
The registration has a generation-safe `registration:dispose()` method: an old
handle cannot remove a newer replacement with the same addon ID.

`Addon.get(addonId)` returns a copied public descriptor.
`Addon.listActive()` returns copied descriptors for active addons.

The registry owns definition validation, capacity limits, disk-program pairing,
and rollback-safe disposal. Consumers must not use Core registries directly.

The optional `diskProgram` descriptor may include `titleKey` (a non-empty
translation key, at most 128 bytes) for the program card title. Without it the
card uses the output item's localized name. `menuTextKey` remains the complete
recording action label. The card resolves `manualItem` for its Learn requirement
and `outputItem` for its Result row. Recording consumes a blank disk and delivers
the programmed disk to the player's inventory; registering a program or recording
its disk does not install an addon or change terminal components.

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

### `ItemLease` (Core 1.5.2-dev1)

Shared facade, authoritative process only (including real single player).
There is one persistent slot per character/addon, with a monotonic sequence.
An unresolved physical unit never expires or authorizes a manufactured replacement.

- `get(player, addonId)` returns `ok, reason, recordCopy, nextSequence`.
- `checkAccess(player, addonId, networkId, anchor)` validates access, the exact
  physical terminal and its installed addon. `check(player, addonId, sequence)`
  applies those checks to the current loan.
- `listCandidates(player, args, inspect)` accepts `addonId`, `networkId`, integer
  `anchor={x,y,z}`, and optional `node`/`offset` cursor hints. The trusted callback
  `inspect(item)` returns a nonempty fingerprint of at most 240 bytes to include
  an item. Returns `ok, reason, page`; the page contains `rows`, `hasMore`, `node`
  `offset` and `inventoryRevision`. Rows expose `itemId`, `fullType`,
  `sourceNodeId`, `fingerprint`.
  One call inspects at most 1024 items/128 nodes and emits at most 100 rows.
  Cursors are not snapshots or authorization; later mutations revalidate identity.
- `borrow(player, args, inspect)` additionally requires `sequence`, exact
  `itemId`, `fullType`, `sourceNodeId`, and addon-owned `contextKey`. It moves one
  permitted unit through Core transfer/locking/sync and returns `ok, reason,
  recordCopy`. Replays cannot withdraw twice; unresolved loans prevent a new loan.
- `consume(player, addonId, sequence, contextKey, invoke, verify)` brackets a
  synchronous trusted vanilla operation. `invoke(item)` performs it;
  `verify(fingerprint)` confirms its resulting device/content state. Success also
  requires the original unit to have left the player's main inventory.
- `replace(player, addonId, sequence, contextKey, invoke, verify, matches)`
  brackets synchronous vanilla ejection. `verify()` confirms empty device state;
  `matches(item, fingerprint)` identifies the successor. Only one newly created
  matching ID may be accepted; existing identical items are never substitutes.
  The before/after main-inventory observation is capped at 8192 items.
- `returnItem(player, addonId, sequence)` uses normal Core deposit permissions,
  capacity and routing, preferring the source node. It may reconcile an exact ID
  already deposited into the same accessible network. It does not require the
  addon to remain installed. Failure retains the physical item and recovery record.
- `adoptActive(player, addonId, ref, verify)` recovers responsibility for an
  abandoned device after death/disconnection. `ref` comes from the trusted
  persisted device record (`ownerId`, `sequence`, `contextKey`), never a client
  claim. Core requires a living authorized recipient, an absent/dead original
  owner (including local split-screen), an exact active source and no pending
  recipient loan. `verify(fingerprint)` validates the actual device/content.
  Under the network lock it creates an active recipient record with that
  recipient's next sequence and settles the original record with `handoffTo`
  and `handoffSequence`. No item moves or is created by adoption. The addon
  immediately cancels the old queue and stops/returns via `replace`/`returnItem`.
  A failed deposit remains `held` for ordinary exact recovery by the recipient,
  even if the device subsequently disappears. An online living owner cannot
  be displaced; a stale adoption cannot claim a second unit.

Callbacks belong to trusted addon code, never network payloads. The addon owns
device validation, user commands, lifecycle and recovery UI. Core owns exact
identity and transfer integrity. States are `withdrawing`, `held`, `consuming`,
`active`, `replacing`, `settled`, or conservatively `unresolved`. Copies are
diagnostic data, not writable handles. No client may attest consumption or
replacement. This API does not recreate destroyed media or guess after an
ambiguous interrupted engine operation.

### `DeviceLease` (Core 1.5.2-dev1)

Shared capability version `1.0.0`, authoritative process only, including real SP.
This custody contract belongs to a physical terminal, not to the character that
started it. It does not move items through a player inventory or retain a player.

- `validate(addonId, networkId, anchor)` validates the active addon, installed
  peripheral, physical terminal and its current network; no player is required.
- `get(addonId, networkId, anchor)` returns `ok, reason, recordCopy` (or nil).
- `open(player, {addonId, networkId, anchor, sequence})` authorizes the current
  actor using `ItemLease.checkAccess`, captures accessible source node IDs and
  opens `idle` custody. The sequence must be the previous sequence + 1 (first 1).
  Pending custody rejects new starts. At most 128 nonclosed contexts may exist.
- `check(key)` applies `validate` to a nonclosed context. Later transitions do
  not require the initiating player to remain connected, alive or nearby.
- `consume(key, {itemId, fullType, sourceNodeId}, inspect, invoke, verify)` checks
  the current terminal and exact unit in an originally authorized node. The
  trusted `inspect(item)` returns a fingerprint of 1–240 bytes. Core persists
  intent, calls `invoke(item)` synchronously and requires both absence of that
  unit from its source and `verify(fingerprint) == true` before `active`.
- `release(key, invoke, verify, matches)` requires `active` custody and the
  original source container with room for the recorded weight. It snapshots
  existing IDs, persists intent, calls `invoke(sourceContainer)`, then requires
  `verify() == true` and exactly one newly created unit of the same fullType for
  which `matches(item, fingerprint) == true`. Success returns `idle` with
  `originalItemId` and `returnedItemId`. Existing identical units do not qualify.
  Source absence/capacity failure never calls the native eject operation.
- `close(key)` accepts only `idle` or already `closed`, retaining the sequence
  against replay. It never abandons an active unit.

All calls return `ok, reason` and, where applicable, a defensive record copy;
the internal allowed-node grant is not exposed. Keys use length-prefixed addon
and network identities plus integer anchor coordinates. Copy data is not a
writable handle or proof of authorization. Callbacks are trusted addon code,
never client payloads; no client may attest a native operation's outcome.

The same network lock used by transfers serializes consumption and release.
The native callback owns its one physical mutation and synchronization; Core
refreshes the affected node snapshot and inventory revision, without repeating
the move. Return observes at most 8192 items. States `consuming`/`replacing` are
durable intent; an ambiguous native result remains `unresolved` and is not
retried. Recovery of a blocked destination may retry `release`; recovery of an
ambiguous interrupted operation requires inspection, never a manufactured item.
The addon owns device lifetime, power, commands, queue and streaming behavior.

### `ItemPresentation` (client, Core 1.5.2-dev1)

`ItemPresentation.icon(fullType)` returns the cached inventory texture and a
status code. This simple signature represents the type icon, not all dynamic
food or movable variants.

`ItemPresentation.create(surface, {terminal=terminal})` returns `handle, code`.
The handle owns one reusable tooltip pool and delegates to the same private
inventory presenter used by the warehouse. It installs no vanilla wrapper,
global listener or periodic task.

- `handle:bind(row, candidate)` returns `binding, code`. Required fields:
  `networkId`, `sourceNodeId`, `itemId`, `fullType`, `inventoryRevision`; optional
  `mediaIndex`, `displayName`. It copies presentation data and rejects stale
  network/revision bindings. Do not mutate the returned binding.
- `handle:show(binding)` is called from the row's render callback. It validates
  the current revision and visible ancestor rectangles, then delegates to the
  existing physical-item resolver or bounded remote detail request. The returned
  mode is explicitly `local-vanilla` or `remote-snapshot`; a remote projection is
  not the original vanilla item tooltip and never calls its `DoTooltip`.
- `handle:hide([row])` hides that row or the pool's current owner. Call when the
  surface is hidden, a row recycled, or a drag begins.
- `handle:dispose()` releases details, tooltip handles and references. Call at
  host destruction; it is idempotent. A failed/stale rebind still cleans the
  previously bound row at disposal.

Local vanilla mode uses an exact loaded item and rechecks its container/identity;
fullType alone can never substitute another unit. Remote replies are correlated
by the existing Core detail service. The facade does not alter third-party
tooltip ordering or extend compatibility claims beyond that existing method.

### `Terminal`

`Terminal.registerTab(definition)` and
`Terminal.registerStaffAction(actionKey, definition)` register client terminal
extensions and return disposable generation-safe registrations.

`Terminal.current()`, `Terminal.player(terminal)`, and
`Terminal.state(terminal)` provide the currently open terminal, its player, and
a projected state copy. `Terminal.isAddonInstalled`, `Terminal.isTabEnabled`,
`Terminal.setTabVisible`, and `Terminal.refresh` are client presentation
helpers. They neither mutate persistent network state nor bypass permissions.

`Terminal.activate(terminal, tabKey)` ensures and selects an already registered,
currently available tab (`tabKey` at most 48 bytes). It returns `true, "OK"` or
`false, code`; visibility and addon requirements remain enforced. Custom mounted
hosts must release their transient resources in `dispose()`, including when an
addon is uninstalled and its tab is removed.

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

### `InventoryView` (client, Core 1.5.2-dev1)

`InventoryView.create(panel, options)` returns `handle, code`. `options.terminal`
is a live terminal; optional `acceptItem(InventoryItem)` restricts deposits (all
items in a mixed drag must pass), `onChanged(ok, result)` observes transfer ACK,
`onSelectionChanged(refs)` observes physical selection, and `onLayoutChanged()`
requests local layout. This facade delegates to the existing Core inventory
adapter, deposit/withdraw queue and server validation. It grants no authority.

The consumer creates a `SiK.UI.Table` with `row = handle.row`, then calls
`handle:setTable(table)`. It may replace the descriptor's cells while retaining
the canonical hierarchy and other row callbacks. Keep the table viewport bounded;
do not size it to every group in a large catalogue.

`handle:setGroups(groups, inventoryRevision)` accepts ordered groups
`{key=string, items={ref,...}}`; each ref contains numeric `itemId`, string
`fullType` and `sourceNodeId`, optional numeric `mediaIndex` and `displayName`.
Refs are consumer-owned read-only presentation data; do not mutate their identity
after binding. Each group has one fullType, distinct key (up to 200 bytes) and
nonempty items. IDs are unique across the whole view; at most 16,384 physical
units/groups are accepted. Invalid input leaves the previous model intact.
On success, use `handle.roots` as table rows, `row.rowKey` as key, and expansion
`childrenOf=row._sikChildren or {}`, `hasChildren=row.expandable == true`.
These bridge fields are presentation only, never copied into addon network calls.
Forward Table `onExpansionChange` to `handle:expand(context.key, context.expanded)`.
Hierarchy is Core-standard parents and exact physical children; a selected parent
represents all its captured children, including those on other detail pages.

`selectedItems()` expands selected parents and returns physical refs once in
display order. `selectItems({[tostring(itemId)]=true})` reapplies model selection
after filtering/refresh/vanilla replacement; `selectionKeys()` supplies the keys
for `Table:setSelectedKeys`. `setEnabled(false)` makes old rows inert during a
refresh and disables deposits. `isInteracting()` prevents recycling a click,
expansion or drag; `setGroups` returns `ERR_BUSY` until that gesture ends.

Observe terminal inventory revision changes and ACK to coalesce an on-demand
catalogue refresh. Hidden consumers do not poll or rebuild; `hide()` releases
hover/gesture state and `dispose()` additionally cancels this view's drag and
detaches its drop target/monitor. Dispose before destroying the Table. Late
completion callbacks cannot re-enter a disposed consumer. Recreate the view when
changing network. Physical floor deposits retain the same ACK callback as other
deposits. The authoritative transfer path continues to enforce access, physical
identity, destination capacity and DeviceLease locks; this facade creates no items
and cannot release a tape from device custody.

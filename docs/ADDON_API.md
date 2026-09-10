# Addon API entry point

The current public contract is [GSSiK product API](API.md). Load `GSSiK_API`
for shared capabilities and `GSSiK_API_Client` for client capabilities.

`GSSiK.API.Search.registerTokenProvider` is the optional, bounded search token
extension introduced in Core 1.5.2-dev1. Its full schema, cache lifetime,
Unicode rules and generation-safe disposal live in `API.md`.

Private `GlobalStorageSiK` registries are implementation details. This entry
point does not add aliases or a public taxonomy capability.

Optional disk-program presentation (`titleKey`, Learn from `manualItem`, Result
from `outputItem`) is documented in `API.md`, under `Addon`. Recording produces
a disk in the player inventory; it is separate from terminal installation.

`ItemLease` is the authoritative single-unit loan contract introduced in Core
1.5.2-dev1. Its exact-identity transitions, trusted callbacks, bounded catalog
and recovery rules are documented in `API.md`. It does not expose a general
storage registry or accept client assertions about item replacement.
Its `adoptActive` operation transfers recovery responsibility for an abandoned
device to an authorized character, without creating or moving an item. The
addon stops the queue and completes the existing exact replace/return cycle.

`DeviceLease` is the separate authoritative custody contract for persistent world
devices. It authorizes a start through a player, then owns the operation by
addon/network/terminal coordinates, with no retained player reference. Its
`validate/get/open/check/consume/release/close` operations are documented in
`API.md`. This is the Multimedia playback contract; `ItemLease` still supplies
its access checks and read-only catalogue.

`Terminal.activate(terminal, tabKey)` selects a registered, currently available
tab through the public client facade. Consumers do not call terminal internals.

`InventoryView` is the client facade for grouped physical inventories: it reuses
Core selection, context menus, exact withdrawals, drag/drop and tooltips. The
addon supplies filtered groups and observes completion; it does not call private
transfer clients. See `docs/API.md` for the lifecycle and reference schema.

`ItemPresentation` is the client facade for inventory icons and exact-bound
tooltip lifecycle. It reuses Core's existing presenter, distinguishing loaded
`local-vanilla` items from `remote-snapshot` projections. See `API.md` for
`create/bind/show/hide/dispose`; no addon should install another vanilla hook.

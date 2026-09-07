# SiK UI and product API architecture

This document describes the current public boundaries of the SiK ecosystem. It
is an implementation inventory, not a compatibility promise for private
symbols.

## 1. Exact public boundaries

The ecosystem has two deliberately different public families:

| Family | Public root | Purpose |
|---|---|---|
| UI framework | `SiK.UI` | Build reusable Project Zomboid interfaces from a neutral component system. |
| Global Storage product API | `GSSiK.API` | Safely consume Global Storage networks, access, sessions, item operations, addons and events. |
| Manure Manager product API | `MMSiK.API` | Safely consume Manure Manager domain capabilities and client actions. |
| Corpse Loot Guard product API | `SCLGSiK.API` | Safely consume the diagnostic capture and audit domain. |

`SiK.UI` is not a product API. Product APIs do not own visual components. A
wrapper that merely renames a vanilla call is neither a useful product API nor
a reason to enlarge one of these namespaces.

The only framework entry point is:

```lua
require "SiK_UI"
local UI = SiK.UI
```

There is no public or private compatibility alias named
`GlobalStorageSiK.SiK_UI`, `GS_SiK_UI` or `SiK_UI.Layout`. Product code loads
`GS_UI_Framework` only as a strict dependency guard: it exposes no fallback,
no copied implementation and no second namespace.

## 2. Repository and dependency graph

`SiKUIFramework-Repo` is an independent Git repository and publishes the exact
ModID `SiKUIFramework`. It must load and operate without Global Storage, its
addons, their assets, translations or namespaces.

```text
SiKUIFramework (SiK.UI)
        ^
        | public dependency
GlobalStorageSiK (GSSiK.API)
        ^
        | public product API only
Craft / Builder / Tablet

ManureManagerSiK (MMSiK.API)      SiKCorpseLootGuard (SCLGSiK.API)
```

Consumers that render SiK UI declare the framework dependency explicitly. A
missing framework is an explicit load failure; hidden fallbacks and copied
subsets are prohibited. Official addons consume only documented public roots.

## 3. Framework composition model

A surface is data plus bindings. Runtime composition follows one hierarchy:

```text
Surface
  -> Window or Modal
    -> Tabs and Block
      -> Table, List, Form, Card or CardCollection
        -> Controls and optional framework capabilities
```

The public framework families are:

| Family | Responsibility |
|---|---|
| `Namespace`, `Version` | Stable root and compatibility metadata. |
| `Surface`, `Builder`, `Factories`, `Bindings` | Validate a declarative tree, resolve injected data/actions, construct it and dispose it. |
| `Capabilities` | Optional registered behavior without inventing a second widget. |
| `Viewport`, `Metrics`, `Layout`, `Theme`, `Icon` | Geometry, density, responsive profiles, palettes and visual assets. |
| `Window`, `Modal`, `Block`, `Scroll` | Shared shell, chrome, clipping, resize and scroll ownership. |
| `VirtualList`, `Table` | Bounded data presentation, row reuse, headers, columns, selection and optional expansion/pagination. |
| `Form`, `Card`, `CardCollection`, `Tabs` | Reusable composition pieces. |
| `Controls` | Buttons, fields, combos, search, toggles, status and other atomic controls. |
| `Tooltip`, `Menu`, `Drag`, `DragGhost` | Reusable interaction presentation and lifecycle. |
| `FocusStack`, `State` | Per-player focus/Escape ordering and reversible view state. |

`Table.create(options)` has one signature. Its parent belongs in
`options.parent`; a table is identified inside a surface by `componentId`, not
by creating a dotted or derived surface ID.

Expandable rows are a Table capability. Pagination is an option of that
capability: warehouse children may paginate, while zone children may use the
owning Block scroll. It is not a separate expandable-row widget.

## 4. One source for HTML and Lua

Declarative surface specifications are the source consumed by both generators.
Generated HTML and generated Lua record the same source hash. A surface remains
`staged` until its exact HTML has been validated by Kava and a deliberate
runtime owner promotes it to `required`; promotion records the active route but
does not replace the later runtime parity certification.

The current generated product surfaces are:

| Surface ID | State | Rule |
|---|---|---|
| `tab-options` | required / active | This is the only surface ID. `Estado` and `Admin` are internal tabs/components; the product context supplies data/actions. |
| `tab-warehouse` | required / active | Warehouse search, filters and Table are built by the generated tree; product code supplies descriptors, selection and callbacks. |

The visual HTML is not a parallel framework. Every rendered selector and every
generated Lua node must resolve to the same registered SiK UI component,
metric, state and interaction contract.

## 5. Product integration

Global Storage supplies only product data, actions and authority to framework
components. Representative seams are:

| Product seam | Owner |
|---|---|
| Framework dependency check and product bindings | `GS_UI_Framework` and product UI modules |
| Shared access, installation and addon contracts | `GSSiK.API.Access`, `Installation`, `Addon` |
| Client terminal and remote-session contracts | `GSSiK.API.Terminal`, `RemoteAccess` |
| Work sessions and item-action providers | `GSSiK.API.WorkSession`, `ItemActions` |
| Capability negotiation and diagnostics | `GSSiK.API.Capabilities`, `Diagnostics` |
| Exact recorded-media identity and tooltip payload | Global Storage recorded-media/snapshot modules |
| Taxonomy and localisation | Global Storage taxonomy registries |

`Network`, `Storage`, `Taxonomy` and `Events` are not implemented public
capabilities in the current API. Product internals may implement those concerns,
but documentation and consumers must not infer public methods from their names.

### Immutable display descriptors

Category path/colour, fluid identity/composition/quantity, recorded-media title
and teachings, group/selection identity and inventory revision are Global
Storage domain data. They are resolved before rows reach `SiK.UI` and are not
reinterpreted by Table, Tooltip, search, pagination or generated surfaces.

- a VHS row and its tooltip use the same recorded-media identity; only exact
  duplicates group, and a resolved title is never replaced by a generic VHS
  label;
- liquid grouping, tooltip and transfer consume the same canonical product
  descriptor;
- family/category colours are supplied as descriptor data and do not become a
  framework taxonomy;
- semantic selection stores stable item/group identities, not visible row
  indexes.

These descriptors remain internal product contracts today. Their existence
does not create undocumented `GSSiK.API.Taxonomy` or `GSSiK.API.Storage`
capabilities.

Coordinates, permissions, identity, expected revisions and payload bounds are
revalidated by the authoritative product process. The framework never grants
product authority.

## 6. Vanilla-first and bridge policy

Before adding behavior, check whether Project Zomboid already supplies the
correct lifecycle and semantics. Vanilla remains the substrate for inventory,
tooltips, context menus, drag, focus and world feedback.

A neutral bridge may live in SiK UI only when it adds reusable value such as
input validation, normalization, per-player lifecycle, cleanup, stable
payloads, cancellation, viewport safety or optional observability. Product
meaning and authority are injected parameters. If a bridge adds no reusable
contract, product code calls vanilla directly rather than publishing an empty
wrapper.

This produces three review classes:

| Class | Meaning | Destination |
|---|---|---|
| A | Unavoidable vanilla substrate or exact bridge | Inside the relevant SiK UI component, or direct vanilla when no reusable value exists. |
| B | Repeated visible chrome, geometry or interaction | Must be constructed by SiK UI. |
| C | Product data, commands, authority or domain semantics | Stays in the owning product and is injected through public bindings/callbacks. |

An allowlist of direct vanilla constructors is a migration ledger, not an
architectural exemption. New hand-painted standard components are forbidden.

## 7. Runtime surface inventory

The maintained inventory is
`Documentacion/development/SIK_UI_SURFACE_INVENTORY.md`, backed by
`Documentacion/UI/catalog/sik-ui.manifest.json`.

The current contract contains:

- 34 runtime visual surfaces: 32 owned by Global Storage and 2 by Manure
  Manager (`manure-zone-picker`, `manure-result-window`).
- 5 world/feedback surfaces: `zone-picker`, `zone-highlight`,
  `node-highlight`, `halo-feedback` and `transient-tooltip`.
- 1 component catalog and 2 documentation auxiliaries.

The inventory records `surfaceId -> owner -> symbol -> stage -> caller` and is
the authority for discovering missing, duplicated or incorrectly promoted
surfaces. Vanilla context menus are bridges, not additional custom surfaces.

## 8. Lifecycle and cleanup

Every constructed tree owns its handlers, pooled rows, tooltips, drag state,
focus entries and transient objects. Disposal is recursive and idempotent.
Closing, player death, reconnect and reopening must not retain handlers,
tooltips, drag ghosts or pools.

Visible layers register with the per-player focus/Escape stack. No permanent
polling loop or global listener may be introduced as the primary route for a
component lifecycle.

## 9. Migration and deprecation state

The former embedded `GS_SiK_UI_*` family has been removed. It is not a source,
fallback, migration target or compatibility surface. Direct private imports
such as `require "SiK/UI/Table"` are prohibited in products; consumers enter
through `require "SiK_UI"` and the public root.

The product boundary gate currently confirms that Core, the official Craft,
Builder and Tablet addons, and Manure Manager enter through public roots. That
does not mean all surfaces are declarative or visually certified.
`tab-options` and `tab-warehouse` generated artifacts are active required
routes. Runtime parity remains pending Kava/Systems validation, and imperative
product composition remains in owners such as
`GS_TerminalUI_Tabs.lua`, editors and dashboards. Manure Manager has removed
`MM_UIChrome.lua`; its custom surfaces now consume public `SiK.UI` components,
but still require their own visual/runtime acceptance.

Remaining product-local visual constructors are migration debt. Priority is:

1. shared table/list/scroll and expandable-row composition;
2. high-volume editors and dashboards;
3. shell sections, tab rails, cards, forms and modal chrome;
4. world/vanilla bridges where a neutral lifecycle component adds real value.

Migration preserves approved runtime appearance unless a surface has an
explicitly validated redesign. A generated or migrated surface does not become
active merely because static tests pass.

## 10. Review checklist

Before exposing or consuming a new element:

1. Confirm whether vanilla already provides the correct behavior.
2. Search the exact public framework or product API for an existing contract.
3. Classify the requirement as A, B or C.
4. Extend an existing versatile component before inventing a near-duplicate.
5. Define input, output, lifecycle, cleanup, error and cancellation behavior.
6. Add the surface/component to the catalog and declarative source where
   applicable.
7. Generate HTML and Lua from the same source hash.
8. Keep generated runtime code staged until visual validation and an explicit
   product promotion; then require runtime parity before release acceptance.
9. Prove standalone isolation, consumer boundaries, addon public-only access,
   lifecycle cleanup and absence of duplicated implementations.
10. Treat runtime evidence from Kava/Systems as superior to mockups and static
    tests; reopen both sides if they diverge.

## Resumen

`SiK.UI` es el framework público y neutral de construcción visual.
`GSSiK.API`, `MMSiK.API` y `SCLGSiK.API` son APIs públicas de producto y no se
mezclan con la UI. El framework vive en su propio repositorio y no depende de
Global Storage. La interfaz se compone con piezas registradas, y HTML y Lua se
generan desde la misma especificación. Los datos y la autoridad permanecen en
el producto. No quedan clones embebidos ni aliases del namespace antiguo en
Core y `MM_UIChrome` se ha retirado de Manure; los artefactos generados siguen
en staging y los constructores visuales locales restantes son deuda de
migración explícita, no una segunda forma válida de construir la interfaz.

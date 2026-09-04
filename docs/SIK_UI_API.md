# SiK UI consumer boundary for Global Storage

Global Storage consumes the independent `SiKUIFramework` ModID. This file is
only the Global Storage integration and migration note; it is **not** a second
SiK UI API reference.

The canonical framework documentation lives in the standalone repository:

- `SiKUIFramework-Repo/README.md`
- `SiKUIFramework-Repo/docs/SIK_UI_API.md`
- `SiKUIFramework-Repo/docs/RUNTIME_REFERENCE.md`
- `SiKUIFramework-Repo/docs/SIK_UI_COMPONENT_CATALOG.md`
- `SiKUIFramework-Repo/docs/SIK_UI_LIFECYCLE_AND_OWNERSHIP.md`
- `SiKUIFramework-Repo/docs/SIK_UI_DATA_SPEC_SCHEMA.md`
- `SiKUIFramework-Repo/docs/MIGRATION_AND_DEPRECATION_LEDGER.md`

Global Storage mechanics are documented separately in
[`GSSiK.API`](GSSIK_API.md).

## Dependency and loading

An external visual consumer declares `SiKUIFramework` in `mod.info` and loads:

```lua
require "SiK_UI"
local UI = SiK.UI
```

Global Storage declares the same ModID dependency. Its client modules use the
private product guard `require "GS_UI_Framework"`; that guard validates the
dependency and returns the existing public `SiK.UI` root. It is not an API for
addons, does not copy framework modules and supplies no fallback.

If `SiKUIFramework` or its public root is unavailable, loading fails explicitly.
The product must not continue through hand-painted substitutes, a hidden
embedded copy or a compatibility namespace.

## Exact separation

| Owner | Supplies | Never supplies |
|---|---|---|
| `SiK.UI` | neutral visual composition, geometry, controls, tables/lists, windows/modals, interactions and lifecycle | storage identity, permissions, network commands or domain policy |
| `GSSiK.API` | bounded Global Storage capabilities, validation, stable results and product lifecycle | generic visual construction |
| Global Storage internals | product projections, authoritative handlers and temporary migration composition | a second public framework or undocumented addon API |

`GlobalStorageSiK.SiK_UI`, `GS_SiK_UI`, `require "GS_SiK_UI"` and the former
`GS_SiK_UI_*` files are retired routes. They are not aliases or fallbacks.
Products and addons must not import `SiK/UI/*.lua` private implementation files.

Product callbacks inject semantic data/actions into public framework
components. They do not make a Table responsible for permissions, make a
Button authoritative, or move Global Storage taxonomy/VHS/fluid logic into the
framework.

## Surface source and current state

Product-owned `*.surface.json` files are data-only inputs to the standalone
catalog validator and generator. Generated HTML, Lua and provenance must carry
the same surface-spec hash. The HTML is a structural preview, not a parallel
runtime and not evidence of ingame parity.

The exact Options/Admin surface identifier is:

```text
tab-options
```

There are no aliases for that ID. The generated `tab-options` and
`tab-warehouse` artifacts are `required` and have reachable
`SiK.UI.buildSurface` owners in the product. This records the active runtime
route; it does not certify ingame visual parity, which remains a product QA and
Kava/Systems runtime gate.

The former Core framework clones and separate TerminalScroll/Sections/TabRail
modules have been removed; Manure has also removed `MM_UIChrome`. Imperative
composition still exists inside product surface owners, so surface migration
is not globally complete. The maintained 34+5 owner map is
`Documentacion/development/SIK_UI_SURFACE_INVENTORY.md`.

## Product display data

Warehouse category path/colour, VHS identity/title/teachings, fluid identity,
group/selection IDs and revision are immutable Global Storage descriptors
resolved before presentation. SiK UI renders the supplied values and preserves
semantic selection; it does not invent generic names, regroup items or expose
an implicit taxonomy API.

## Vanilla bridges and lifecycle

Use vanilla directly when it already provides the complete required behavior.
A neutral framework bridge is justified only when it adds reusable validation,
normalization, player context, cleanup, cancellation/error semantics, bounded
payloads or observability. Product mutations remain product callbacks/API
operations.

Every product owner disposes the framework tree, focus registration, tooltip,
drag state, pooled rows and temporary handlers that it creates. Reopening may
restore local view state, but it must request current product data; network
identity, permissions and revisions are not UI state.

## Validation and authority

Boundary, manifest, provenance, lifecycle and geometry gates produce evidence
only. They do not approve exceptions or overrule Kava or Systems. A passing
static gate cannot promote a staged surface or claim an ingame result. Runtime
evidence reopens the HTML/runtime pair when they diverge.

## Resumen en español

La única autoridad pública de interfaz es la documentación del repositorio
independiente `SiKUIFramework` y su namespace `SiK.UI`. Este fichero solo fija
cómo lo consume Global Storage: dependencia obligatoria y fallo explícito si
falta, sin copias ni aliases; datos y autoridad mediante `GSSiK.API` o lógica
interna; `tab-options` como identificador único; y artefactos generados
`tab-options`/`tab-warehouse` conectados como ruta runtime obligatoria, todavía
pendientes de la certificación visual ingame.

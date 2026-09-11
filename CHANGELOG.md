# Changelog

## 1.5.2 - 2026-09-11

### Global Storage SiK

- Added sequential multi-reading, disk programming through every supported route and rule configuration from exact items to broad categories.
- Added per-player opacity control and permission-aware option tools.
- Reduced redundant server requests during inventory opening and refresh.
- Expanded the shared taxonomy used by search, filters, rules and auto-sort.
- Preserved vanilla tooltips while providing exact SiK annexes for remote items.
- Fixed rule gesture runtime errors, overly broad group filters, detail-removal flicker and unnecessary table pagers.

### Craft 1.5.2

- Added network-propane blowtorch refilling through the existing vanilla action.
- Aligned GS 3D Printer disk programming requirements, result and wording.

### Builder 1.5.2

- Aligned GS Digital Blueprint disk programming with the shared requirements/result format.
- Widened crafting and installation surfaces without changing building loans or returns.

### Tablet 1.5.2

- Aligned WiFi Antenna disk programming, installation surfaces, names and item categories.

### Multimedia 0.1.0

- Introduced the installable GS Multimedia Player and its progression, components and programmed disk.
- Added a network VHS catalog with search, filters, multi-selection and playback queues.
- Added radio and volume controls plus authoritative exact-tape custody, return and recovery.
- Uses Project Zomboid recorded content and learning/XP rules without adding XP or animated video.

## 1.5.1 - 2026-09-08

### Global Storage SiK

#### Added

- Ground and external-container transfers with drag, drop and selection actions, capacity checks and explicit results.
- World taxonomy editor with permission checks, revision control and server acknowledgement.
- Scrollable item annexes and recipe learning details for recordings.

#### Improved

- On-demand refreshes while preserving terminal detection and access monitoring.
- Exact local-instance tooltips and summaries for unloaded remote items.
- Taxonomy and corpus diagnostics with persistent reports per session.

#### Fixed

- Single-item double-click withdrawals and captured destinations when accessible bags are unequipped or dropped.
- Backpack, seed, container, fluid and prop classification; preservation of original inventory categories.
- Food states, permissions, persisted zones and reader-dependent programming.
- Staff resizing and tab visibility, pagination, scan headers and deposit progress.
- Missing translation keys and text corrections across ten languages.

### Craft 1.5.1

- Strengthened access checks during network crafting.
- Corrected missing translation keys and text across ten languages.
- Aligned the displayed version with the installed addon.

### Builder 1.5.1

- Strengthened access checks during network building.
- Corrected missing translation keys and text across ten languages.
- Aligned the displayed version with the installed addon.

### Tablet 1.5.1

- Harmonized tablet translations and option terminology across ten languages.

## 1.5.0 — 2026-09-06

### Global Storage SiK

- Exposes the public `GSSiK.API` for access, addon installation and shared work sessions.
- Separates product rules and addon actions from the standalone `SiK.UI` framework.
- Introduces the standalone SiK UI dependency and a coherent, resizable shell
  across storage, network, options, administration, addons and editors.
- Adds exact expandable item details and transfers for fluids, media and
  variable instances without collapsing their physical identity.
- Unifies native L1/L2/L3 taxonomy, search, filters, rules, deposit routing and
  auto-sort, including exact Matches and Comfrey Cataplasm mappings.
- Adds deterministic rule specificity, zone/container priority and affinity
  ordering with authoritative transfer locks and bounded micro-batches.
- Improves network scans, cache invalidation, permissions, terminal lifecycle,
  installation/blocked states and structured diagnostics.

Compatibility: Project Zomboid 42.20+, `SiKUIFramework` required. SP, host and
dedicated/client paths are implemented.

### Craft 1.5.0

- Integrates network crafting and optional cooking into the shared session and
  SiK UI contracts while preserving claimed-instance returns.

Dependencies: `SiKUIFramework` and `GlobalStorageSiK`. Vanilla and Neat
Crafting paths are supported; Project Cook integration is optional and depends on the installed environment.

### Builder 1.5.0

- Integrates building material claims and returns into the shared work-session
  and SiK UI contracts.

Dependencies: `SiKUIFramework` and `GlobalStorageSiK`.

### Tablet 1.5.0

- Adds tiered tablets, authoritative accessible-network selection and antenna
  range validation through the Core remote-access API.

Dependencies: `SiKUIFramework` and `GlobalStorageSiK`.

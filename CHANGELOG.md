# Changelog

## 1.5.0 — 2026-09-06

### Global Storage SiK

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
Crafting paths are supported; Project Cook remains an optional runtime-tested
integration.

### Builder 1.5.0

- Integrates building material claims and returns into the shared work-session
  and SiK UI contracts.

Dependencies: `SiKUIFramework` and `GlobalStorageSiK`.

### Tablet 1.5.0

- Adds tiered tablets, authoritative accessible-network selection and antenna
  range validation through the Core remote-access API.

Dependencies: `SiKUIFramework` and `GlobalStorageSiK`.

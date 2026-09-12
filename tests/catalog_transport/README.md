# Catalog transport harness

`catalog_transport_harness.lua` loads the real `GS_CatalogCodec.lua` and probes
the private catalog transport boundary without reproducing its encoder or
decoder.  The fixture covers 1,500 long Spanish/CJK/emoji rows, 64 nodes in
multiple zones, scalar values, false/empty/sparse tables, deep nesting, and
strings split across UTF-8 boundaries.

The runner also calculates frame bytes independently from the returned token
arrays using the B42 `TableNetworkUtils` wire primitives (table count, type
byte, short UTF-8 string length, and primitive widths).  It checks the 24,000
byte frame cap, the 16 MiB batch cap, and token accounting.  Negative probes
cover unsupported values, cycles, depth, non-finite numbers, duplicate keys,
missing/extra tokens, and malformed chunks.

Run from this repository root:

```text
lua51 tests/catalog_transport/catalog_transport_harness.lua
```

This is a Lua 5.1 harness only. It does not claim Project Zomboid runtime,
network, dedicated-server, or QA evidence. A failure in the real codec is
reported as a harness failure for root to triage; this directory contains no
production workaround.

`catalog_transport_kahlua_runner.lua` is executed by
`CatalogTransportKahluaHost.java` using the actual J2SEPlatform, LuaCompiler
and KahluaThread from Project Zomboid's jar, without opening the game.
The Java host uses reflection: compile with JDK21 `javac -J-Xmx256m -encoding UTF-8
-d <temporary-classes> CatalogTransportKahluaHost.java` (no jar compilation
classpath); run the game's JRE25 with `-Xmx512m -cp <temporary-classes>;<game-jar>
CatalogTransportKahluaHost <game-jar> <runner.lua> <GS_CatalogCodec.lua>`.
Pass every path as a separate correctly quoted argument.

Executed on 2026-09-12: PASS native Unicode, UTF-8 boundaries and segmented
long string. This is Kahlua execution, not PZ gameplay or network delivery.
The integration harness separately exercises real server/client modules,
progress-sensitive timeouts, reordering, deduplication, supersession and the
client progress callback. It verifies accepted ACK `0/unknown`, unique-part
progress, silent exact/stale duplicates, and replacement fencing during a
reentrant progress callback.

`catalog_transport_scheduler_harness.lua` loads the real server module and
checks the four-frame update allowance, two-player and eventual fairness,
idle-session exclusion, synchronous SP receipt, reentrant clear, and the
24,000-byte wire cap. The older one-send-per-recipient scheduler would fail
its first assertion; this is a semantic runtime harness rather than a source
presence check.

`catalog_cache_token_harness.lua` extracts and executes the real client cache
token function. It checks explicit network precedence, per-player active
fallback/isolation, cache misses, and that no opening `networkId` or
`terminalHint` is synthesized. It also executes the real catalog store/clear
functions to verify one catalog per player, full row retention, `cachedAt`,
300-second TTL expiry and backwards-clock invalidation.

`catalog_cache_not_modified_harness.lua` extracts and executes the real server
`notModified` predicate with minimal `Index` and `ZoneScanJob` stubs. It checks
network identity (including legacy nil), revision/scope equality, snapshot
revision, pending sync, scan-needed, and active-scan fences. It does not load
the complete server or certify opening/search handlers; those remain subject
to server-context and PZ runtime validation.

`catalog_loading_lifecycle_harness.lua` executes the real loading module and
the real `showPending`, `dispatchOpening`, and `catalogProgress` API bodies
with minimal window, Events, and native-control doubles. It checks immediate
shell visibility, deferred/cancelled dispatch, ACK progress retention, stale
progress fencing, refresh-free loading completion, player isolation, and
native enabled-state restoration while keeping Close outside the body lock. It
also extracts the real deferred `applyTerminalState` path for generation
fencing and refresh error closure/reporting.

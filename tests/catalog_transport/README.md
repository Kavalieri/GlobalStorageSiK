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
progress-sensitive timeouts, reordering, deduplication and supersession.
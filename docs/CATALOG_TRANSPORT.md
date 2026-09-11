# Catalog transport — Core 1.5.3-dev1

The private terminal wire protocol uses `terminalOpenAck`,
`terminalCatalogChunk`, `terminalCatalogAck` and `terminalCatalogError`.
Consumers continue to receive a complete `terminalState`; partial chunks never
enter inventory caches or addon callbacks. This is not a new addon API.

Authorization produces a small ACK before building the inventory. It confirms
access only, never an empty catalog. The pending opening remains until a
complete catalog is assembled. Every frame is correlated by authoritative
player, network, opening sequence, inventory revision, catalog scope and batch.
The latest batch supersedes unfinished work. Exact duplicates do not extend
deadlines; conflicting duplicates fail closed. A receipt only releases transient
transport memory and cannot grant permission or mutate inventory.

`GS_Server.gsSendServerCommand` routes every terminalState emitter through the
same encoder: opening, inventorySync, scan completion, taxonomy, transfer and
observer refresh. During opening, inventory-only refresh is promoted to a full
state. Before each frame the server rechecks permission, the active opening,
terminal link, strict physical/radio range, revision and scope. Revision changes
coalesce a replacement snapshot; access loss aborts the session.

The exact TableNetworkUtils cost includes key/value types and UTF-8 bytes.
Frames are capped at 24,000 bytes including a 128-byte envelope allowance.
Strings use at most 4,096 UTF-8 bytes per token fragment, preserving UTF-16
surrogate pairs in Kahlua. The native signed-short string limit is never raised.
Primitive tables, strings, finite numbers and booleans are round-tripped without
executable deserialization, truncation or replacement text.

Transient admission limits are 16 MiB encoded bytes, 500,000 tokens, 4,096 chunks
and depth 32 per batch, 256 sessions and a 64 MiB conservative global reservation
estimate (twice wire bytes + 64 bytes/token + 128 bytes/chunk). This estimate is
not a guarantee about JVM heap. Oversized work fails explicitly; it does not
truncate data or increase engine buffers. Existing ticks send at most four
frames globally, round robin. A server job expires after 60 seconds without
progress/receipt. The client expires incomplete work after 10 seconds without
a new fragment; opening without a catalog has a 60-second inactivity deadline
after its ACK. Ordinary access ACK timeout remains 10 seconds.

Close, supersession, error, death and disconnection release transient work.
The existing access watcher covers active/pending consumers and detaches when
unused. Authorized scans continue independently of their observers. No change
is made to persistence, quantities, item identity, permissions or taxonomy.

Recovery uses the approved modal with separate unconfirmed-access and confirmed-
access/catalog-failure copy. Its information control gives the specific failure
(timeout, incomplete/conflicting data, encoding, budget, busy server, changed
access, unavailable cache, send/apply failure). Close never retries or scans.
ES and EN have dedicated copy; other locale files carry explicit English fallback.

## Validation scope

Authorial harnesses exercise the real codec and transport modules with at least
1,500 rows, 64 nodes, UTF-8/CJK/emoji, ordering, duplicates, revision replacement
and cleanup. Lua 5.1 and Kahlua compilation are development gates. These checks
do not prove dedicated-server packet delivery or the rendered PZ modal; those
remain explicit runtime checks for Sistemas/Kava on the frozen candidate.

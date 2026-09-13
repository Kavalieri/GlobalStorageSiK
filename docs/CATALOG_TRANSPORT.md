# Catalog transport — Core 1.5.4

This private protocol carries complete catalog states, revisioned deltas and
on-demand detail pages. It does not change the public addon API. Server and
client must use matching Core versions; compact protocol 2 tokens are not
understood by an older Core client. The decoder retains protocol 1 support for
bounded compatibility traffic.

## Session and publication

~~~mermaid
stateDiagram-v2
    [*] --> AccessCheck
    AccessCheck --> AccessConfirmed: terminalOpenAck
    AccessConfirmed --> Building: reserve B1
    Building --> Encoding: immutable rows ready
    Encoding --> Framing: immutable encoded tokens
    Framing --> Receiving: final envelope and bounded terminalCatalogChunk
    Receiving --> Applying: all fragments decoded
    Applying --> Confirmed: consumer succeeds, terminalCatalogAck
    Confirmed --> Building: coalesced change from exact ACK base
    Applying --> Recovering: rejection or exception
    Recovering --> Building: one full recovery
    Receiving --> Closed: revoked or superseded
    Confirmed --> Closed: close, death or revoked access
~~~

Authorization is acknowledged before catalog construction. It cannot install an
empty inventory or acknowledge catalog contents. Every batch binds the
authoritative recipient, local-player slot, network, opening sequence, authorized
zone scope, captured inventory revision and batch ID.

One batch is immutable from reservation through consumer ACK. A scan, transfer
or later inventory revision records one pending refresh intent; it never replaces
unfinished B1. After B1 is acknowledged, B2 derives from exactly that observer's
acknowledged rows and revision. A newer content revision does not revoke an
older authorized snapshot. Changed permissions, scope, terminal binding, range,
death or opening sequence do revoke it.

Rows and index contributions are shared only by network and authorized scope.
Opening metadata, ACK state and recovery belong to each recipient. A shared
publication never regresses when two revisions finish in a different order.
Index outputs and acknowledged rows remain immutable.

## Incremental work and cache

A hot opening with the same network, scope and revision keeps the known catalog
usable after the access ACK. A same-scope confirmed client view from the preceding
120 seconds can also remain visible while a newer revision is prepared. Actions
still carry the applied view's revision and are revalidated by the server.
A notModified batch carries metadata rather than another full catalog.

Published node snapshots provide per-node contributions. Changed parents are
recomputed from changed contributions; unchanged snapshots and parents are
reused. Initial construction and sorting use explicit budgeted phases.
Snapshot producers replace node tables atomically; table identity is the in-memory
node revision. Ordinary contributions copy visible fields and find one minimum
representative ID in bounded blocks; they do not canonicalize unitDetails or the
complete physical ID arrays. Initial rendering uses published snapshots and does
not wait for a full physical reconciliation cycle.
Categories consume the same prepared rows instead of rebuilding the index.
The classification stamp is checked again between index completion and category
publication. A changed stamp aborts that preparation without publishing mixed
taxonomy. A normal inventory revision advance still leaves captured B1 valid.

The reconciler inspects registered, watched networks and yields between physical
items and comparisons. A replacement node snapshot commits only after identity,
membership, old snapshot reference and physical contents are revalidated.
Unloaded or unrepresentable nodes retain their prior image without fabricated
empty counts. Food, fluid and condition changes affect their actual node.
A no-change cycle produces no content revision.
Periodic cycles are diagnostic background work and do not broadcast manual
scan progress. `CatalogTransport reconcile` records phase, nodes, units,
compared steps, changed nodes and discarded captures. Actual changes still
publish through the revisioned catalog path; manual scans keep their progress.

Construction uses 4,096 work units and reconciliation uses 32 physical/comparison
work units, each with a 4 ms soft tick budget. Codec work has an 8,192-token,
4 ms soft budget. These cooperative
budgets are checked between operations, not a guarantee that each engine call
takes less than 4 ms. Sending is limited to four frames per server update.
An authorization call that already exhausts the wall budget permits one useful
1 ms preparation/encoding slice, then stops further recipients for that update.
The cursor rotates fairly; authorization wall time is reported independently.
Comparison cursors batch at most 128 primitives, signature cursors 32, and UTF
encoding scans at most 32 codepoints per primitive. Wire/schema checks are unchanged.
Engine latency and end-to-end percentiles require runtime measurement.
Sorting up to 64 entries is a bounded synchronous primitive; larger collections
retain the incremental merge cursor. This preserves exact canonical signatures.

## Wire and memory bounds

Frames use the native table serializer size model, including UTF-16 accounting
for Unicode strings. The frame ceiling is 24,000 bytes with envelope margin.
Codec.frame builds the actual transport envelope; Codec.frameSize is shared by
framing and both transport endpoints, including the unchanged 128-byte command
reserve. Base revision and full/delta/notModified intent are established before
queueing. A late builder result is also reflected in the final job classification.
Before sending any fragment, the finalized envelope determines the exact token
budget. Existing chunk sizes enable a zero-copy fast path; otherwise a bounded
framing cursor repartitions the existing token stream without rebuilding rows,
discarding the base, requesting a full or notifying a UI failure. Part count and
total bytes are finalized before the first send; numeric values have fixed wire
size. ACKs remain premature while framing. The frame event reports part, total,
frameBytes, frameBudget, payloadBytes, chunkBytes and overheadBytes; framed reports
the final batch dimensions. Validation still runs on the actual outgoing frame.
Protocol 2 uses typed scalar tokens, bounded string fragments and explicit table
boundaries. Physical item arrays do not appear in ordinary parent rows.

Codec limits are 16 MiB encoded batch, 500,000 tokens, 4,096 fragments and nesting
depth 32. Transport reservation limits are 32 MiB per recipient and 64 MiB
globally, including retained bases and conservative transient estimates. The
server admits at most 256 sessions. Capacity failure is explicit; rows are not
silently truncated to fit.
The prepared-row cache separately caps 128 entries, 16 MiB per entry and 32 MiB
globally; it evicts by use order and expires entries after 120 seconds. Invalidated
images and historical revisions remain available only as exact authorized delta
bases, under the same limits. Shared preparation retains detached work for 30
seconds, with 64 entries and a 32 MiB budget. A compatible reopen retargets an
unencoded full to the new openSeq without restarting its work or deadline.
Index has its own 32 MiB cache budget. Each codec job may memoize at most 2,048
validated short strings within 256 KiB, included in transport reservations.
Memoization changes work cost without changing wire tokens or Unicode checks.

ACKs require the exact in-flight identity and all fragments sent. Duplicate,
premature and stale ACKs cannot advance the base. Exact duplicate fragments do
not extend deadlines. Conflicting fragments, malformed schema, capacity failure
and timeout fail the affected batch.
A builder only renews its progress deadline when it actually advances or finishes.
The 10-second response target is separate from the lifetime of shared work.
While preparation or encoding progresses, terminalCatalogPending reports a
recoverable request_timeout and renews the pre-fragment client response lease
only for increasing work under the current authorized session and batch.
It neither cancels preparation nor extends fragment inactivity deadlines.
No progress for 60 seconds produces catalog_stalled. Detached work receives a
bounded background slice and remains reusable for 30 seconds after detachment.
The dedicated requirement remains usable cold rows within 10 seconds; a pending
notification is not evidence of meeting that requirement.
Cold node contributions are not canonically serialized. Changed nodes compare
their affected parent contributions lazily; parent construction uses an inverted
contribution list rather than scanning every node for every parent. Snapshot
capture maintains exact minimum representatives; legacy snapshots cache a
bounded incremental first lookup without mutating the published snapshot.
Events distinguish state_envelope_built, catalog_rows_built, encoded and completed;
elapsed time includes queued work. Progress reports phase, node/total, remaining
work and retained base at a global maximum of one sample every two seconds.

Ordinary variantSummary entries group visible/searchable semantics, including
book title, media identity, native path and visible food states. variantCount
still counts distinct physical snapshot variants; it need not equal summary length.
Each semantic summary keeps a minimum exact representative for sequential reading.
Condition, exact fluid/food state and other physical detail remain in revisioned
detail pages. Parent search indexes visible semantics rather than physical keys;
there is no silent row or search-string truncation.

## Consumer commit and recovery

No partial fragment reaches catalog caches, UI or addon consumers. The actual
client consumer must complete before ACK. Rejections and exceptions retain the
original stage and bounded cause in CatalogTransport consumer_failed.
The catalog_apply classification is not the sole diagnostic.

A recoverable failure retains the last valid catalog and requests one full
recovery. Changed access fails closed. Recovery and legacy direct deltas use
the same current-session fences. A detail ACK does not advance the catalog base.
Detail acceptance also finishes its captured loading state before ACK, within
the consumer rollback journal. A late detail cannot finish a newer load/window
or opening sequence. Rejected details retain the prior image and show failure.

B1 applies during managed transfers so its ACK can release B2. Confirmed
microbatch withdrawals project a per-player overlay over B1 without changing
acknowledged counts. Only affected rows await the new revision; unrelated safe
rows remain usable. A later accepted catalog retires overlay events exactly
once. Transfer action ACKs remain independent from catalog ACKs.

## Incremental presentation

Core 1.5.4 uses Framework 1.0.3 `Table:patchRows` for catalog deltas,
detail pages and managed transfer completion. The initial image uses `setRows`;
deltas reuse unchanged root descriptors, semantic entries, projected blocks and
the viewport pool. Selection, focus, expansion, child page and scroll survive
updates for retained keys. A missing patch API produces an explicit consumer
failure instead of silently rebuilding the full table.

Confirmed withdrawals contribute their pending keys immediately. A later
catalog retires their overlay even when a concurrent deposit leaves the final
count unchanged. Completing a managed transfer compares its final catalog with
the previous source to include concurrent changes outside its action log.
This comparison and ordering scan references/content across the catalog;
only affected roots are localized, filtered and reprojected. It is not an
O(1) operation. Detail caches and rollback state are scoped by player and network.

## Exact detail pages

Ordinary rows omit systematic itemIds, unitDetails and unitNodeIds.
getItemDetails names a parent row and expected inventory revision. Pages are
bounded to 25 detail rows and use the fragmented session transport. A grouped
detail row may identify multiple physical units. The pending
descriptor queue is bounded to 64 per player and coalesces repeated row
requests. A busy queue rejects that request explicitly.

Detail consumers require matching player, network and applied catalog revision.
The existing detail-page producer still scans and sorts the selected parent's
physical units before slicing its output. It is separate from cold parent loading;
its peak cost on very large expanded groups remains a dedicated runtime check.
Late pages cannot satisfy a new network/revision request. Duplicate physical
IDs are reported as ItemIdentity duplicate_physical_id separately from transport
errors, and exact selection is rejected. Authoritative transfer validation still
checks permissions, revision and physical objects.
Dragging a parent requests its complete authoritative group regardless of
expansion or visible page (`amount=0`). The withdrawal worker sends bounded
microbatches and stops at capacity, access, range or cancellation limits.
A child drag requests one unit; multiple selected children retain their exact
selection. Selected children covered by a selected parent are not duplicated.

## Audited producers and lifecycle

All terminalState producers converge in GS_Server.gsSendServerCommand:
initial opening, configuration refreshes, completed scans, redistribution and
addon-triggered state refreshes. Inventory watchers enqueue revisioned intents.
Transfer confirmations schedule catalog work after their action result.
Detail pages and ACKs use the same player/session authority checks.

Closing, replacing a sequence, revocation, death and player cleanup release
transient jobs. Catalog and manual scan progress update header state; idle
background reconciliation preserves Connected. Successful completion clears
progress, including a completed detail page, instead of retaining 100%.
Manual scan status is ordered by scan start and progress/completion timestamps
within the same opening, player, network and scope. A delayed full catalog must
not restore an older RUNNING state after live completion. This merge changes no
inventory revisions or rows. The reconciler checks the live Java list size before
each capture/verification read and discards interfered captures for a later cycle.

Development evidence and the immutable QA result identify the tested candidate.
Static Lua/Kahlua checks and engine doubles do not certify PZ dedicated, host,
split-screen or in-game timing.

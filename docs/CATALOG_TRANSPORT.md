# Catalog transport — Core 1.5.6

A container is the authoritative inventory unit. A network publishes a manifest
of container revisions; the terminal catalog is a derived client view. Server
and client require matching Core builds. Framework 1.0.5 supplies the
retained search resize contract. Multimedia 0.1.1 consumes the additive
ItemLease 1.1.0 snapshot candidate API; Craft and Builder retain their public
WorkSession interfaces.

## Opening and synchronization

The server confirms player, network, opening sequence, scope and replica epoch
before the client negotiates its cache. A cache key includes epoch, local-player
slot, network and authorized scope. A known manifest token returns minimal
`manifestNotModified`; otherwise the response contains current node records and
configuration metadata. Only missing or changed node snapshots are requested.
One immutable node block completes the existing framed transport and consumer
ACK before the next block is sent. Removed nodes are removed from the replica.
A changed classification stamp rebuilds the local derived presentation.

An authorized zone insertion snapshots valid sessions before mutation and
revalidates their access against the exact additive scope afterwards. The server
emits `terminalOpenAck` with `topologyTransition=true` and `previousCatalogScope`,
retaining `openSeq` and `replicaEpoch`. The client fences old batches, advances its
scope and negotiates a new manifest while retaining confirmed blocks and rows.
Consecutive additions may share the original base scope; late intermediate ACKs
cannot roll the session back. Other scope changes are revocations. A topology
revision is established before the directed scan captures its starting revision.

Additive ACKs carry the pending `topologyZones` metadata, so accepted empty zones
appear before their directed scan discovers children. A validated manifest can
patch zone/node metadata before inventory blocks complete. These updates retain
the last confirmed inventory revision and rows; they do not grant new transfer
authority. Only affected table roots are patched, preserving unrelated rows,
selection and expansion. Older scan metadata cannot replace a newer live result.

Refreshes during a manifest round are coalesced until `terminalReplicaReady`.
The ACK-to-node handoff belongs to that round even when no wire job is active;
a refresh must not erase its accepted node request. Recovery waits for an active
frame receipt before replacing the round. Topology transitions explicitly retire
the old round and fence old-scope traffic before negotiating the new scope.

Client category composition is pure during replica bootstrap. It merges manifest
metadata, categories detected in the received node replicas and built-in defaults;
it does not require or create a client Network/Zones registry entry. The legacy
category helpers also return bounded empty results when their registry or network
is absent.

Confirmed replicas use a byte LRU (32 MiB, 16 scopes), with no age expiry.
Ordinary closing does not expire confirmed content. Safe retention after distance
loss remains pending: current access-denial paths can explicitly purge the cache;
this is not time expiry. Revocation, death, a different epoch or incompatible scope
invalidate the corresponding player's replica. Transient jobs still have bounded timeouts. An interrupted or
corrupt block preserves independently confirmed nodes and the last complete
visible catalog; recovery requests missing blocks. Bootstrap and loss of the
cache can require all authorized nodes. They do not reinstate periodic full
physical reconciliation.

Node content revisions, inventory mutation fences and routing revisions are
separate. A metadata-only manifest change at the same inventory revision commits
a complete *local* derived view, never an invalid same-revision content delta.
All actions remain subject to current server permissions and physical identity.

A deterministic replica consumer failure fences that `openSeq`, manifest token and
revision after the first rejection. The server releases queued work and will not
resend the rejected identity; the client preserves its last confirmed view. A new
opening is required to negotiate a different session. Progress belongs to the
whole manifest operation rather than individual transport batches. It is monotonic,
remains below 100 percent while actions are fenced, and reaches 100 percent once,
only after the complete view has been applied and `terminalReplicaReady` accepted.

## Mutation and external changes

Deposits, withdrawals, redistribution, ItemLease, DeviceItemLease and the shared
Craft/Builder WorkSession update the affected container snapshots immediately.
The operational registry persists locally and coalesces bounded observer
notifications by network; it no longer broadcasts the full registry after each
movement. Capacity reads consume committed snapshot totals.

Object/container events mark the matching registered container. Argument-less
or scalar container events cannot identify a target and never dirty a network.
An incremental probe provides a fallback for physical edits without a reliable
event: 16 work units / 1 ms per update, adaptive 1–10 second node intervals.
This still visits physical units over time; it does not capture/compare every
snapshot whenever a UI is watching. Dirty reconciliation uses 32 work units /
4 ms, commits only after identity, membership and contents are revalidated, and
reports the exact node and trigger. Unloaded or interfered containers retain
the last confirmed image. Legacy snapshots are unconfirmed until directed
reconciliation establishes the current schema; they are not silently certified.

## Derived view and bounds

The shared Index reuses node contributions and maintains a parent-to-node
reverse index. A changed parent reads its contributors instead of all network
contributions. A valid incremental generation visits only changed node IDs and
affected parents. A keyed dense compatibility store journals those parents;
Framework's ordered provider updates their positions without a global array
copy, sort or projection. Bootstrap, classification changes and exceptional
rollback may materialize the complete view. Explicit range selection can also
request the complete navigable row order.
Client build/view work is cooperative (256 work units / 2 ms). Engine call
latency is outside these soft budgets and requires runtime measurement.

The manifest supports 8,192 nodes. Server topology/session reservations and
replica reservations fail explicitly at capacity; rows are not silently truncated.
Deleted networks release topology reservations. Node views have separate bounded
pending queues. The existing CatalogCodec uses 24,000-byte frames including the
final envelope, typed flat tokens, bounded string fragments and explicit table
boundaries. Limits remain 16 MiB per encoded batch, 500,000 tokens, 4,096 fragments
and depth 32. Existing transport reservations remain 32 MiB per recipient and
64 MiB globally. The replica budget also charges decoded snapshots and derived
views. A cold opening may present acknowledged blocks progressively after four
nodes, with actions fenced until the complete view is accepted. That preview
never becomes the confirmed cache token or emits the complete-view ACK. Warm
openings keep the last confirmed image while a replacement is assembled.

Cold per-node wire size can exceed the previous global parent serialization.
The benefit is reuse at reopening and directed replacement; this DEV does not
claim smaller cold traffic or the dedicated cold-load latency target from a
headless harness. Trace events distinguish cache hit/miss/eviction with compact
scope/epoch/key fingerprints, node requests, notModified, recovery, build/view
and application timing. Fingerprints are diagnostic, not authorization tokens.
Debug changes neither requests nor response bytes and never logs bulk payloads.

## Container editor and addons

The mounted container editor requests its own node every two seconds, with
node revision/classification hints and player/network/view/sequence fences.
Unchanged replies contain no rows. Another node's inventory revision does not
reload this editor. Its Index build cannot read unrelated nodes. Unavailable,
excluded, disabled or unconfirmed contents clear rows/details and forget the
revision hint so re-enabling fetches a usable node image. The editor still needs
authenticated terminal/session authority and minimal zone metadata; routing
controls may independently need the wider rule context.

Multimedia enumerates committed snapshot candidates in pages of 16, validates
scope/topology and swaps only a complete list while preserving selection.
Older media metadata can consult RecordedMedia definitions without scanning
physical storage. Physical insertion, ejection and item claims continue through
authoritative leases with exact source/destination updates.

Craft/Builder claims carry an exact sourceNodeId. The server revalidates that
node's network, zone, permissions and physical item; an invalid hint has no
network-wide fallback. Craft/Builder loans share reservations and transfer confirmations. Cancellation
before arrival, ACK before physical replication, failed return and recipe result
deposits preserve custody. Pending returns retain their exact identity; an
uncertain return is not blindly resent. Runtime reconnect/restart recovery still
requires dedicated testing: this revision does not add a durable loan ledger.

## Routing, withdrawals and presentation

Routing requests carry expectedRoutingRevision, epoch/sequence and an idempotent
requestId. Bounded receipts replay ACK/NACK without applying an intention twice.
Conflicts keep the draft. Modals close only after a matching ACK, including an
ACK arriving after a locally reported timeout; explicit retries retain the same
pending ID. Withdrawal receipts similarly retire evicted sequences instead of
executing old requests again. Repeated pending clicks coalesce at the client.

Grouped food names reflect shared vanilla Food.getName states or an explicit
mixed summary. Aggregate tooltips do not use an arbitrary child's physical
attributes; expanded children retain exact detail. Quantity has 8 px right
padding. Search and local rule fields reflow existing controls, preserving text
and selection. Framework Table:patchRoots and its ordered provider are the
ordinary incremental path; initial/recovered views use setRows under consumer
rollback/ACK fences. Untouched parents retain their identity and captured
revision; a withdrawal captures the current accepted revision at the gesture.
Stale visible child pages request fresh detail on demand, with pending-request
deduplication and send-failure backoff. Media titles use a localized render cache
and reproject only the hovered parent, without mutating published rows.
Metadata-only manifests update configuration independently of inventory revision;
the routing client observes the new revision only after the delta is accepted.

Detail pages remain bounded and revisioned. The selected parent detail producer
may scan/sort that parent's units before slicing; large expanded groups remain
a runtime performance check. Child transfers require exact identities, and a
selected parent covers its authoritative group without duplicating selected
children.

## Compatibility and validation

Authorized zone deletion and logical node removal use the same server-stack
ticket as additions. The server validates access before mutation and again against
the exact expected resulting scope before confirming. Ordinary scope mismatches
remain `catalog_access_changed`; permission, terminal and range loss are not
converted into topology transitions.

The access ACK carries a session-local `topologySequence`, its cumulative
`topologyBaseSequence`, and `catalogBatchFloor`. These are distinct from the
network-wide `topologyRevision` in manifests. Pending additions and tombstones
are accumulated until ReplicaReady; reordered intermediate ACKs cannot undo the
latest transition, even when a scope returns to the same string. Zone tombstones
cover their nodes without enumerating containers in the ACK. Manifest/node bodies
and client requests carry the session sequence as an additional identity fence.

Every accepted topology mutation replaces the server catalog session object after
fresh authority validation. `openSeq` continues to correlate the mounted UI opening;
`topologySequence` identifies the renewed catalog authorization. It is checked in
chunk envelopes, decoded bodies, receipts, errors and node requests as well as ACKs.
Recovery remains bounded across these renewals. A later explicit UI opening rebases
this generation only after its fresh access ACK. Cache confirmation also compares
terminal coordinates and access mode; a different terminal cannot reuse the entry.
Topology derivation requires a completely confirmed view, never a bootstrap draft.

Verified replica deltas compare installed-addon descriptors and Craft/Builder flags
by content. Changed metadata refreshes existing addon/option presenters and tab
visibility using the accepted rows; ordinary inventory deltas keep their incremental
path. Floor destination checks invoke `CanBeDroppedOnFloor` only for `Moveable`;
ordinary inventory items retain the same capacity and transactional validation.

The client immediately removes confirmed zone/node metadata from the mounted
table, drops only affected immutable blocks and marks their derived contributions
dirty. The next manifest reuses unaffected blocks and the existing incremental
view machinery removes inventory contributions. Last confirmed inventory remains
visible during that short transition; server revision/access checks still govern
every transfer. This is separate from the pending retention policy for temporary
terminal/range loss.

Saved node tables retain the existing persistence location and add schema,
revision and signature metadata. No destructive world migration is performed.
A downgrade is an operational recovery decision requiring the prior complete
mod set and backed-up world; mixed client/server versions are unsupported.
The previous full-catalog transport remains for fenced legacy/detail consumers,
not the ordinary negotiated opening path.

Lua 5.1/Kahlua compilation and deterministic engine-boundary fixtures establish
technical behavior only. Dedicated MP remains the primary runtime gate, with SP,
hosted and split-screen checks for authority, physical replication, lifecycle,
food changes, routing NACKs, cache timing and native input focus. QA certification
and Systems runtime acceptance are separate from publication.

The world zone picker rearms the terminal access watcher when restoring a visible terminal, including cancellation. Catalog decoding remains subject to fresh access validation and shared token limits; an authorized batch can begin one bounded decoder step even when access validation consumed the wall-time slice. Progressive global capacity presenters explicitly show loading until the replica is confirmed.

# RFC: synchronous multi-node replication (bare-metal durability tier)

**Status: design exploration — no implementation.**

## Why

Bare-metal deployment changes the durability calculus. Litestream
(and the in-BEAM async shipper of RFC 02) are *asynchronous*: RPO is
one sync interval, so a `kill -9`, power loss, or OOM between commit
and ship loses the unshipped tail. On bare metal the durable target
is peer machines in the same rack, not S3 — which means we can do
strictly better than litestream:

**Synchronous replication** — a commit acks only after its WAL frames
are on ≥ quorum of peer nodes' stable storage — gives RPO = 0 on any
single-node failure (bounded loss only on simultaneous multi-node
loss). That is a *stronger* guarantee than litestream provides, and
it comes with a bonus: failover stops being "restore from a replica"
(download + WAL replay, the path the kind smoke test exercises today)
and becomes "promote a replica already resident and fsynced on the
target" — faster and loss-free.

This is an *additional tier*, not a replacement. Litestream stays a
first-class option for cloud/S3 deployments and cheap async tiers.

## Durability as a per-database mode

Generalize the existing `litestream_enabled` flag into a replication
*mode*, chosen per database so a fleet can mix tiers:

- `none` — local file only (current non-premium default).
- `litestream` — async → S3 sidecar. RPO ≈ sync interval. Cloud.
- `async_shipper` — RFC 02's in-BEAM shipper. Same RPO shape, no
  sidecar, one code path for all tiers.
- `sync_quorum` — **new.** RPO = 0 on single-node failure. The
  bare-metal HA tier this RFC proposes.

To give "decent guarantees everywhere" on bare metal you would make
`sync_quorum` the fleet default while keeping the others available.

## The grain problem (why this isn't just "turn on DRBD")

DRBD's unit of replication is a **block device**, writable on exactly
one node (single-primary; dual-primary needs a cluster FS — a
non-starter here). This system's unit is **per-database placement**:
any DB active on any node, with live single-DB drain and rebalance
(`on_owner_node/3`, per-DB reassignment in `data_plane.ex`). Those two
grains do not compose for free — any block-level answer must be
per-database to match placement, which is what drives the options
below.

## Options

### A. App-level synchronous WAL quorum (recommended)

Extend RFC 02's in-BEAM WAL shipper with a synchronous ack path.
Instead of (or in addition to) shipping segments async to S3, the
owning `Database.Server` streams new WAL frames to R follower nodes
over `gen_rpc` and returns commit success only after ≥ quorum of them
fsync-ack. Reuses the single-writer property (frame boundaries are
quiescent), the existing cluster RPC layer, and the placement rows as
the single source of truth for ownership.

- *Follower placement.* Pick R replica nodes per DB; extend the
  placement controller to keep them current alongside the active
  owner. Followers hold the reconstructed `-wal` + latest snapshot.
- *Ack policy.* Quorum tunable per tier (1-of-2 for latency, 2-of-2
  for max durability).
- *Backpressure.* Reuse RFC 02's max-WAL-bytes knob; in sync mode a
  write blocks on peer ack rather than S3 confirm — never data loss.
- *Failover.* Promote a follower that already has snapshot + segments
  fsynced; skip the restore/replay step entirely. Fence the old owner
  via the placement lease before promoting (split-brain guard reuses
  today's failover logic).
- *Cost.* Commit latency += peer RTT + peer fsync. On a fast LAN this
  is tens to low-hundreds of µs per commit.

Fits the existing architecture with no new infra, kernel modules, or
LVM. It is a *superset* of RFC 02: build the async shipper first, then
add the synchronous ack + follower placement.

### B. LINSTOR-managed per-database DRBD

Each DB file on its own LVM logical volume, a DRBD resource (Protocol
C, R replicas) on top, with LINSTOR orchestrating volume placement and
primary promotion. The placement controller drives LINSTOR instead of
running an activation-restore.

- Pro: replication is proven, off-the-shelf; no WAL-shipping code to
  own or get right.
- Con: heavy stack (LVM + DRBD kernel module + LINSTOR control plane +
  fencing/STONITH), thousands of DRBD resources carry real per-resource
  memory/connection overhead, and LINSTOR becomes a *second* source of
  placement truth to reconcile against the metadb. Biggest operational
  lift.

Keep as the fallback if we decide not to own replication code.

### C. Node-level DRBD / distributed block store

Node-level DRBD (one replicated device per node) is simpler but breaks
fine-grained placement — the whole device is primary on one node, so
DBs fail over as a node-sized unit and single-DB drain is impossible.
Rejected. Ceph RBD decouples storage (any node mounts any DB, n-way
replicated) and matches the grain, but you run a Ceph cluster and pay
network-fsync latency on every write — viable only if a storage
cluster is wanted for other reasons.

### D. SQLite-on-Raft (dqlite / rqlite / LiteFS)

Real quorum durability with built-in leader election, but it replaces
the placement controller and single-writer model wholesale. Largest
rewrite; only relevant if abandoning the current data-plane design.
Out of scope as an incremental tier.

## Recommendation

Option A. It is the only path that (1) beats litestream's RPO, (2)
keeps litestream and the async shipper as coexisting modes, and (3)
fits the existing single-writer + placement + `gen_rpc` architecture
without importing a storage stack. Option B (LINSTOR) is the fallback
if we choose not to maintain replication code.

## Plan (when picked up)

1. Land RFC 02's in-BEAM async shipper first — shared capture,
   segment format, and restore machinery.
2. Follower placement: record R replica nodes per DB in placement
   rows; controller keeps followers current and re-replicates to
   restore R after a node loss.
3. Sync ack path in `Database.Server`: on commit, ship frames to
   followers and block the reply until quorum fsync-ack; quorum
   tunable per replication mode.
4. Failover: promote = activate on a follower that already holds
   snapshot + segments; skip restore. Fence old owner via placement
   lease before promote.
5. Expose replication mode per DB (`none | litestream | async_shipper
   | sync_quorum`); preserve `litestream_enabled` semantics under the
   `litestream` mode.

## Open questions

- Quorum policy per tier: 1-of-2 vs 2-of-2 latency/durability tradeoff.
- Re-replication cost when a node dies (restoring R for its followers).
- Does `sync_quorum` still ship an idle snapshot on idle-stop? Likely
  yes — cold restore and manual backups still need the snapshot path.
- Read scaling: could followers serve stale reads later? Non-goal now.

## Non-goals

Cross-region synchronous replication, multi-writer, and replacing
idle snapshots / manual backups — those remain the cold-start and
point-in-time path regardless of the chosen live-replication tier.

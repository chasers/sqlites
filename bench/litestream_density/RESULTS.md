# Litestream density benchmark — results

2026-07-04, litestream 0.5.13, macOS arm64 (M-series, 10 cores),
file:// replicas, 1s sync interval, small (~12KB) WAL-mode databases,
write load = 50–100 random db inserts/s. Method: `run.sh`.

| databases | initial sync | RSS idle | RSS under load | CPU under load |
|-----------|--------------|----------|----------------|----------------|
| 1,000     | 17s          | 447MB    | 448MB          | ~107%          |
| 10,000    | ~150s        | 3.7GB    | 3.8GB          | 294–439%       |

**~370–450KB RSS and meaningful CPU per replicated database.** CPU is
high even without writes (the sync loop polls every db each interval).

## Extrapolation to the design target (100k dbs/node)

- RSS: **~37GB** per node just for the litestream sidecar
- CPU: **>10 cores** of polling overhead
- Initial sync after node replacement: **~25 minutes**

Verdict: **vanilla per-database litestream does not scale to the 1M
target**. Sharding litestream across processes divides CPU but not
total memory. Per-database continuous replication needs either a much
lighter shipper or a change in the durability model.

## Options (decision needed)

1. **Tiered durability** — default tier: periodic snapshot shipping
   (`VACUUM INTO` → S3, machinery already exists via Smolsqls.Backups)
   on a changed-db sweep every N minutes; RPO = N minutes. Premium
   tier: litestream registered dynamically per database (0.5 control
   socket) for continuous replication, capacity-capped per node.
   Matches the per-tenant limits model.
2. **In-BEAM WAL shipper** — the data plane already runs one process
   per hot database; ship WAL segments to S3 from the Server on
   checkpoint boundaries. Marginal memory ~KB/db instead of ~400KB.
   Highest engineering cost; litestream-quality correctness is
   nontrivial (checkpointing coordination, generations).
3. **Bounded litestream** — register only *hot* databases with the
   sidecar (activation/idle hooks); cold databases rely on their last
   snapshot. RPO for cold dbs = age of last snapshot before idling
   (bounded: snapshot-on-idle makes this ~0 for cleanly idled dbs).

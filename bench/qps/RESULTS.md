# QPS benchmark — results

2026-07-04. Local numbers: macOS arm64 (M-series, 10 cores), dev env,
full app, queries through `DataPlane.query/3` (`local_bench.exs`).
Latency numbers: 3-pod kind cluster on a 4GB Docker VM.

## Single-node throughput (local)

| scenario | result |
|---|---|
| single db, sequential inserts | **~9,900 writes/s** |
| single db, 50 concurrent writers | **~9,450 writes/s** (GenServer serialization holds; no collapse under contention) |
| single db, 50 concurrent reads | **~25,000 reads/s** (still serialized through the writer — headroom exists via read replicas on the same file if ever needed) |
| 100 dbs, 50 concurrent writers | ~12,650 writes/s (caller-pool bound, not database bound) |
| activation storm: 1,000 cold dbs, concurrent first queries | 0.6s total — **~1,650 activations/s** |

The activation number sizes cold-start recovery: a node with 100k
databases would warm its entire set in ~60s of sustained storm, and in
practice traffic warms only what it touches.

## Query latency (kind cluster, cross-pod)

| path | avg latency (SELECT 1, n=2000) |
|---|---|
| owner pod handles its own query | **35µs** |
| query arrives at non-owner, hops via gen_rpc | **387µs** |

The hop costs ~350µs in kind's virtualized network — an 11× ratio but
both are far below the ~1ms HTTP/Hrana protocol overhead above them.
Placement-aware routing (sending clients to the owner) is an
optimization, not a requirement.

## Not measured

- Hrana WebSocket connection ceiling per node — needs a proper
  load-generation harness; deferred until the protocol surface work.
- Sustained mixed read/write soak (hours) — deferred to a real cluster.

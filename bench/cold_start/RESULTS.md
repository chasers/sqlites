# Cold-start latency — results

How long a caller waits for a first result when a database is **not hot**.
Measured **in-cluster** on the kind 3-pod cluster (`bench/cold_start/run.sh`),
against the **real MinIO/S3** object store over the cluster network — the only
path that exercises a real S3 GET on the cold-restore path. Single kind node,
~3.9 GiB RAM shared across all pods (3× smolsqls + postgres + minio +
operator), no per-pod memory limit.

Run: `2026-07-07`, `bench/cold_start/cold_start.exs` via `run.sh smolsqls-0`.

## Scenario A — brand-new db (create → ready)

Placement starts the database server (opens the empty `exqlite` file) at
**create** time, so a brand-new db is already hot on its first query. The
user-visible cost is the `create_database/2` call; the first query is served
warm.

| step | p50 | p99 | max |
|---|---|---|---|
| `create_database/2` | 4.8ms | 19.0ms | 19.0ms |
| first query (server warm from create) | 152µs | 572µs | 572µs |
| end-to-end create → ready | 4.9ms | 19.5ms | 19.5ms |

n=30. A new database is queryable ~5ms after `create` returns; there is no
separate cold first-query penalty because create already placed and opened it.

## Scenario B — cold pull from the object store (solo restore latency)

Warm a db to a target size, `idle_stop_database/1` (ships a `VACUUM INTO`
snapshot to MinIO), wipe the local file on the **owning node**, then time the
**solo** first query that restores from the store + opens + serves. Solo (not
a 200-concurrent storm) is the real single-request cold-start number;
`bench/qps/activation_restore.exs` covers aggregate throughput under a storm.

| db size | restored on-disk | p50 | p99 | max | n |
|---|---|---|---|---|---|
| empty | 8 KB | 4.3ms | 7.0ms | 7.0ms | 5 |
| ~1 MB | 984 KiB | 5.7ms | 5.9ms | 5.9ms | 5 |
| ~10 MB | 9.6 MiB | 26.9ms | 28.0ms | 28.0ms | 5 |
| ~100 MB | 95.5 MiB | 229.9ms | 237.3ms | 237.3ms | 4 |
| ~1 GB | 0.93 GiB | 1.73s | 1.81s | 1.81s | 2 |

Below ~1 MB the cost is a fixed **~4–7ms floor** — activation, syn
registration, an 8 KB MinIO GET, opening the connection. Above ~10 MB it is
bytes-dominated at roughly **~2.0ms/MiB** (10 MiB → 27ms, 100 MiB → 230ms,
0.93 GiB → 1.73s), consistent with in-cluster network + disk-write
throughput.

Empty → 100 MB were measured on the pre-fix build; the 1 GB row is post-fix
(see below). Streaming to disk vs buffering is the same I/O for small files —
the fix changes memory, not latency — so the small-bucket numbers stand.

### ~1 GB used to OOM-kill the owning pod — fixed by streaming

Before the fix, the 1 GB bucket **could not complete**: restoring it
OOM-killed `smolsqls-0` (`OOMKilled`, exit 137, restart 19→20).
`Smolsqls.ObjectStore.S3.fetch_to_file/2` read the **entire object into a
single in-memory binary** (`Req.get(...) |> body` then `File.write!`), so a
cold pull's peak memory was ~the db size — fatal for a 1 GB db on this
~3.9 GiB node. The **ship** side (`put_file/2`, `File.read!` + `Req.put
body:`) had the same flaw and would OOM first, on `idle_stop`.

Both paths now **stream**: the restore downloads into a `.partial` file via
`Req … into: File.stream!` and atomically renames on success; the ship
uploads with `body: File.stream!(path, 1 MiB)` + explicit `content-length`
(`UNSIGNED-PAYLOAD` sigv4). The full 1 GB cycle now completes with **0 pod
restarts** — ship ~3.8s, restore ~1.7s, `[[1000]]` rows intact. This matters
in prod because the default `max_size_bytes` is **1 GiB**
(`config :smolsqls, Smolsqls.Limits`), so a legitimately-sized database that
goes cold could previously OOM its node on the next request.

## Environment caveats

- Numbers are from a single kind node under memory pressure (minio has 36
  historical restarts); treat ±20% as noise, especially the tail.
- MinIO is same-node in kind, so the network hop is loopback-fast — real S3
  (cross-AZ) will add round-trip latency on top of every restore, most
  visibly on the small-db floor.
- `litestream stop failed … database not found` warnings during the run are
  benign: these dbs have litestream disabled, so the stop is a no-op.

## See also

- `bench/qps/RESULTS.md` — activation **storm** throughput (cache-hit vs
  restore) and idle-stop ship cost, against a local-FS object store.

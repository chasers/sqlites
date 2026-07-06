# Dirty scheduler saturation — results

Does a slow SQLite query pause the BEAM? Short answer: **no.** exqlite
runs every query NIF on a dirty IO scheduler
(`ERL_NIF_DIRTY_JOB_IO_BOUND`), so a long query ties up one dirty-io
thread, not one of the normal schedulers that run every other process.

Local numbers: macOS arm64 (M-series, 10 cores), `mix run --no-start
bench/schedulers/dirty_pool.exs` (2026-07-05). Raw exqlite against
in-memory connections — deliberately **outside** the smolsqls stack, so
neither the per-database GenServer serialization nor the 30s
`statement_timeout` canceller is in the way. Each "slow query" is a
recursive-CTE `count(*)` that spins inside a single `multi_step` call,
so it holds its dirty-io thread continuously. Bound auto-calibrated to a
~2.4s solo query. Treat ±15% as noise (10 CPU-bound threads on 10 cores
lose turbo clock and cache to each other run-to-run).

## Scheduler pool (default `+SDio`)

| class | count | note |
|---|---|---|
| normal | 10 | run every Erlang process; must stay free |
| dirty cpu | 10 | unused by exqlite |
| dirty io | 10 | **where every SQLite query lands** |

`+SDio` is unset in `rel/vm.args.eex`, so the dirty-io pool is the OTP
default of 10 — the effective ceiling on concurrent in-flight queries
per node.

## Experiment A — pin the pool, watch the BEAM

20 slow queries in flight against a pool of 10:

| metric | value |
|---|---|
| dirty-io utilization | **100%** (pinned) |
| dirty-cpu utilization | 0% (CPU-bound CTE still runs on the *io* pool) |
| normal utilization | **0%** (idle — nothing else was blocked) |
| per-query wall time | 3.9s min · 7.7s max (queued in two waves) |
| heartbeat overshoot (10ms sleeps, normal scheduler) | **p50 1.6ms · p99 ~47ms · max ~50–60ms** |

The heartbeat is a process doing `Process.sleep(10)` in a loop on a
normal scheduler; its overshoot is the proxy for "is the VM still
ticking." It stayed responsive throughout.

**The nuance in the tail:** the ~50ms spikes are *not* the BEAM
scheduling badly — normal-scheduler utilization was literally 0%, so
there was endless idle BEAM capacity. They're OS-level contention: with
all 10 physical cores burning on dirty-io threads, a woken normal
scheduler occasionally waits tens of ms for the OS to hand it a core.
Contrast the failure mode this avoids — a 2.4s query on a *normal*
scheduler stalls that scheduler for 2400ms, and 10 of them wedge the
whole VM for seconds. Dirty schedulers turn "multi-second full freeze"
into "occasional tens-of-ms blip under full CPU load."

## Experiment B — the ceiling

| concurrent queries | wall time | vs solo |
|---|---|---|
| 10 (fills the pool) | ~3.6s | ~1.5× |
| 20 (2× the pool) | ~7.5s | ~3.1× |

Up to 10 run truly in parallel; beyond that they queue for a dirty-io
thread, so wall time steps up in waves (~2 waves ≈ 2× a single wave).
The >1× on the pool-filling wave is the same CPU-contention tax as
above — 10 fully-busy threads each run slower than one alone. SQLite
throughput stalls at the pool size; the normal schedulers never do.

## What this means for the real path

Production adds the two guardrails this raw test strips out:

- **Each database is its own GenServer** (`DataPlane.Database.Server`),
  so a single database serializes its own queries — one slow query
  blocks that one database, which is the "one writer per file" model
  anyway, not the node.
- **`statement_timeout` (default 30s)** — the canceller in `server.ex`
  calls `Sqlite3.cancel/1` until a runaway statement aborts, so no
  single query holds a dirty-io thread longer than ~30s (worst case
  ≈ 2× the cap; see the note in `server.ex`, dirty NIFs outlive the
  process that spawned them).

So to actually saturate a node's dirty-io pool you need **>10 distinct
databases each running a heavy query at the same instant on the same
node**, each capped at ~30s. If that becomes a real workload shape, the
knob is `+SDio` in `rel/vm.args.eex`.

## Not measured

- The real `DataPlane.Router.query/3` path across N databases (GenServer
  + statement-timeout interplay under saturation) — this bench isolates
  the scheduler behavior only.
- Behavior when dirty-io work is genuinely IO-bound (disk stalls on
  cold-file activation) rather than CPU-bound — different contention
  profile; the CTE here is pure CPU.

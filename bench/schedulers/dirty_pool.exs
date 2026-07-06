# Does a slow SQLite query pause the BEAM?
#
#   mix run --no-start bench/schedulers/dirty_pool.exs
#
# exqlite runs every query NIF on a dirty IO scheduler
# (ERL_NIF_DIRTY_JOB_IO_BOUND). This probes what that buys us by driving
# slow queries — each one a recursive CTE that spins inside a single
# multi_step call — against independent connections, so every query
# occupies one dirty IO scheduler thread at once.
#
# Experiment A: oversaturate the pool and measure whether the *normal*
# schedulers stay responsive (a heartbeat that should keep ticking on
# time) and where the CPU time actually lands (per-scheduler-class
# utilization).
#
# Experiment B: the ceiling — with a pool of N dirty IO schedulers,
# submitting 2N concurrent slow queries runs them in two waves, so wall
# time roughly doubles even though the machine isn't otherwise busy.

alias Exqlite.Sqlite3

defmodule Probe do
  def now_ms, do: System.monotonic_time(:microsecond) / 1000

  def open_conns(count) do
    for _ <- 1..count do
      {:ok, conn} = Sqlite3.open(":memory:")
      conn
    end
  end

  @doc "Run a recursive-CTE count(*) and return its wall time in ms."
  def slow_query(conn, bound) do
    sql =
      "WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c WHERE x < #{bound}) " <>
        "SELECT count(*) FROM c"

    start = now_ms()
    {:ok, stmt} = Sqlite3.prepare(conn, sql)
    {:ok, _cols} = Sqlite3.columns(conn, stmt)
    {:ok, _rows} = Sqlite3.fetch_all(conn, stmt)
    Sqlite3.release(conn, stmt)
    now_ms() - start
  end

  @doc "Calibrate the CTE bound so one query takes ~target_ms."
  def calibrate(conn, target_ms) do
    probe_bound = 4_000_000
    elapsed = slow_query(conn, probe_bound)
    max(round(probe_bound * target_ms / elapsed), 1_000_000)
  end

  # Per-scheduler-class utilization across a window, using
  # scheduler_wall_time_all (sorted: normal, then dirty-cpu, then dirty-io).
  def utilization(snap1, snap2, counts) do
    per =
      Enum.zip(snap1, snap2)
      |> Enum.map(fn {{_, a1, t1}, {_, a2, t2}} ->
        case t2 - t1 do
          0 -> 0.0
          dt -> (a2 - a1) / dt * 100
        end
      end)

    {normal, rest} = Enum.split(per, counts.normal)
    {dirty_cpu, dirty_io} = Enum.split(rest, counts.dirty_cpu)

    %{
      normal: avg(normal),
      dirty_cpu: avg(dirty_cpu),
      dirty_io: avg(dirty_io)
    }
  end

  defp avg([]), do: 0.0
  defp avg(xs), do: Enum.sum(xs) / length(xs)

  def pct(sorted, p), do: Enum.at(sorted, min(length(sorted) - 1, floor(length(sorted) * p)))

  def r(n), do: Float.round(n / 1, 1)
end

counts = %{
  normal: :erlang.system_info(:schedulers),
  dirty_cpu: :erlang.system_info(:dirty_cpu_schedulers),
  dirty_io: :erlang.system_info(:dirty_io_schedulers)
}

online = :erlang.system_info(:schedulers_online)

IO.puts("== schedulers ==")
IO.puts("  normal:     #{counts.normal} (#{online} online)")
IO.puts("  dirty cpu:  #{counts.dirty_cpu}")
IO.puts("  dirty io:   #{counts.dirty_io}   <- SQLite queries land here")
IO.puts("")

pool = counts.dirty_io
conns = Probe.open_conns(2 * pool)
[cal_conn | _] = conns

IO.puts("== calibrating slow query to ~2.5s ==")
bound = Probe.calibrate(cal_conn, 2500)
solo = Probe.slow_query(cal_conn, bound)
IO.puts("  recursive CTE to #{bound} rows -> #{Float.round(solo, 0)}ms solo")
IO.puts("")

# ---------------------------------------------------------------------------
IO.puts("== Experiment A: pin all #{pool} dirty-io schedulers, watch the BEAM ==")
saturators = Enum.take(conns, 2 * pool)

tasks = Enum.map(saturators, fn conn -> Task.async(fn -> Probe.slow_query(conn, bound) end) end)

:erlang.system_flag(:scheduler_wall_time, true)
snap1 = Enum.sort(:erlang.statistics(:scheduler_wall_time_all))

# Heartbeat on a normal scheduler: sleep 10ms, 200 times, record the
# overshoot. If the normal schedulers were blocked this would balloon.
jitters =
  for _ <- 1..200 do
    t0 = Probe.now_ms()
    Process.sleep(10)
    Probe.now_ms() - t0 - 10
  end

snap2 = Enum.sort(:erlang.statistics(:scheduler_wall_time_all))
durations = Task.await_many(tasks, 120_000)

util = Probe.utilization(snap1, snap2, counts)
sorted_jitter = Enum.sort(jitters)

IO.puts("  in-flight queries:      #{length(tasks)} (pool is #{pool})")

IO.puts(
  "  query wall time:        min #{Probe.r(Enum.min(durations))}ms  max #{Probe.r(Enum.max(durations))}ms"
)

IO.puts("")
IO.puts("  scheduler utilization during the storm:")
IO.puts("    normal:    #{Probe.r(util.normal)}%   <- headroom for everything else")
IO.puts("    dirty cpu: #{Probe.r(util.dirty_cpu)}%")
IO.puts("    dirty io:  #{Probe.r(util.dirty_io)}%   <- pinned by SQLite")
IO.puts("")
IO.puts("  heartbeat overshoot (10ms sleeps, normal scheduler):")

IO.puts(
  "    p50 #{Probe.r(Probe.pct(sorted_jitter, 0.5))}ms  p99 #{Probe.r(Probe.pct(sorted_jitter, 0.99))}ms  max #{Probe.r(List.last(sorted_jitter))}ms"
)

IO.puts("    -> the VM kept ticking on time while every dirty-io thread was busy")
IO.puts("")

# ---------------------------------------------------------------------------
IO.puts("== Experiment B: the ceiling (pool = #{pool} threads) ==")

run_wave = fn n ->
  batch = Enum.take(conns, n)
  start = Probe.now_ms()

  batch
  |> Enum.map(fn conn -> Task.async(fn -> Probe.slow_query(conn, bound) end) end)
  |> Task.await_many(120_000)

  Probe.now_ms() - start
end

wall_pool = run_wave.(pool)
wall_double = run_wave.(2 * pool)

IO.puts(
  "  #{pool} concurrent (fills the pool):   #{Probe.r(wall_pool)}ms  (~#{Float.round(wall_pool / solo, 2)}x solo)"
)

IO.puts(
  "  #{2 * pool} concurrent (2x the pool):     #{Probe.r(wall_double)}ms  (~#{Float.round(wall_double / solo, 2)}x solo)"
)

IO.puts("")
IO.puts("  -> up to #{pool} slow queries run truly in parallel; beyond that they")
IO.puts("     queue for a dirty-io thread, so wall time steps up in waves.")
IO.puts("     SQLite throughput stalls; the normal schedulers never do.")

Enum.each(conns, &Sqlite3.close/1)

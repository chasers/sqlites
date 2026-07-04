# Applies write traffic: updates `rate` randomly-chosen databases per
# second for `duration` seconds.
#
#   mix run bench/litestream_density/writer.exs <count> <work_dir> <rate> <duration_s>

[count, work_dir, rate, duration] = System.argv()
count = String.to_integer(count)
rate = String.to_integer(rate)
duration = String.to_integer(duration)

db_dir = Path.join(work_dir, "dbs")

IO.puts("writing to #{rate} dbs/s for #{duration}s (pool of #{count})")

for _tick <- 1..duration do
  tick_start = System.monotonic_time(:millisecond)

  1..rate
  |> Task.async_stream(
    fn _ ->
      i = :rand.uniform(count)
      path = Path.join(db_dir, "db-#{i}.db")
      {:ok, conn} = Exqlite.Sqlite3.open(path)
      :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA busy_timeout=2000")
      :ok = Exqlite.Sqlite3.execute(conn, "INSERT INTO t (v) VALUES ('w')")
      Exqlite.Sqlite3.close(conn)
    end,
    max_concurrency: 32,
    timeout: 10_000
  )
  |> Stream.run()

  elapsed = System.monotonic_time(:millisecond) - tick_start
  if elapsed < 1000, do: Process.sleep(1000 - elapsed)
end

IO.puts("writer done")

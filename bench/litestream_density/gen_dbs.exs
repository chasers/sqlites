# Creates N small WAL-mode SQLite databases and a litestream config
# replicating all of them to a file:// replica directory.
#
#   mix run bench/litestream_density/gen_dbs.exs <count> <work_dir>

[count, work_dir] = System.argv()
count = String.to_integer(count)

db_dir = Path.join(work_dir, "dbs")
replica_dir = Path.join(work_dir, "replica")
File.mkdir_p!(db_dir)
File.mkdir_p!(replica_dir)

IO.puts("creating #{count} databases in #{db_dir}")

start = System.monotonic_time(:millisecond)

for i <- 1..count do
  path = Path.join(db_dir, "db-#{i}.db")
  {:ok, conn} = Exqlite.Sqlite3.open(path)
  :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA journal_mode=WAL")
  :ok = Exqlite.Sqlite3.execute(conn, "CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)")
  :ok = Exqlite.Sqlite3.execute(conn, "INSERT INTO t (v) VALUES ('seed')")
  :ok = Exqlite.Sqlite3.close(conn)

  if rem(i, 10_000) == 0, do: IO.puts("  #{i}...")
end

elapsed = System.monotonic_time(:millisecond) - start
IO.puts("created in #{elapsed}ms")

config_entries =
  for i <- 1..count do
    "  - path: #{Path.join(db_dir, "db-#{i}.db")}\n    replicas:\n      - url: file://#{replica_dir}/db-#{i}"
  end

config = "dbs:\n" <> Enum.join(config_entries, "\n") <> "\n"
File.write!(Path.join(work_dir, "litestream.yml"), config)
IO.puts("wrote litestream.yml (#{count} dbs)")

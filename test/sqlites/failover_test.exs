defmodule Sqlites.FailoverTest do
  use Sqlites.DataCase

  import Sqlites.Fixtures

  alias Sqlites.ControlPlane
  alias Sqlites.ControlPlane.Database
  alias Sqlites.DataPlane
  alias Sqlites.Failover

  test "evacuate/1 reassigns a dead node's databases to survivors" do
    tenant = tenant_fixture()

    databases =
      for _ <- 1..3 do
        database = database_fixture(tenant)

        {:ok, database} =
          database
          |> Database.placement_changeset(%{
            status: :active,
            node: "sqlites@dead-node",
            file_path: "/var/lib/sqlites/data/#{tenant.id}/#{database.id}.db"
          })
          |> Repo.update()

        database
      end

    assert {:ok, %{reassigned: 3}} = Failover.evacuate("sqlites@dead-node")

    self_node = to_string(Node.self())

    for database <- databases do
      assert ControlPlane.get_database(database.id).node == self_node
    end
  end

  test "evacuate/1 refuses when the dead node is the only node" do
    assert {:error, :no_survivors} = Failover.evacuate(to_string(Node.self()))
  end

  test "activation restores the litestream replica when the file is missing" do
    tenant = tenant_fixture()
    database = database_fixture(tenant)
    {:ok, database} = ControlPlane.update_database_settings(database, %{litestream_enabled: true})

    data_dir = Application.fetch_env!(:sqlites, :data_dir)
    file_path = Path.join([data_dir, tenant.id, database.id <> ".db"])

    {:ok, database} =
      database
      |> Database.placement_changeset(%{
        status: :active,
        node: to_string(Node.self()),
        file_path: file_path
      })
      |> Repo.update()

    refute File.exists?(file_path)

    fixture = seed_replica_fixture(database)
    stub = write_restore_stub(fixture)

    previous = Application.get_env(:sqlites, Sqlites.DataPlane.Litestream)

    Application.put_env(:sqlites, Sqlites.DataPlane.Litestream,
      enabled: true,
      replica_url_prefix: "s3://bucket/ls",
      binary: stub
    )

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:sqlites, Sqlites.DataPlane.Litestream)
        value -> Application.put_env(:sqlites, Sqlites.DataPlane.Litestream, value)
      end

      DataPlane.Supervisor.stop_database(database.id)
      File.rm(file_path)
    end)

    assert {:ok, %{rows: [["survived-failover"]]}} =
             DataPlane.query(database.id, "SELECT v FROM t")
  end

  test "activation for a non-replicated database falls back to its latest backup" do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)

    {:ok, _} = DataPlane.query(database.id, "CREATE TABLE t (v TEXT)")
    {:ok, _} = DataPlane.query(database.id, "INSERT INTO t VALUES ('from-backup')")
    {:ok, _backup} = Sqlites.Backups.trigger(database)
    on_exit(fn -> Sqlites.Backups.delete_all(database) end)

    :ok = DataPlane.Supervisor.stop_database(database.id)
    File.rm!(database.file_path)
    File.rm(database.file_path <> "-wal")
    File.rm(database.file_path <> "-shm")

    assert {:ok, %{rows: [["from-backup"]]}} = DataPlane.query(database.id, "SELECT v FROM t")
  end

  test "activation fails rather than starting from an empty file" do
    tenant = tenant_fixture()
    database = database_fixture(tenant)

    {:ok, _} =
      database
      |> Database.placement_changeset(%{
        status: :active,
        node: to_string(Node.self()),
        file_path: "/nonexistent/dir/#{database.id}.db"
      })
      |> Repo.update()

    assert {:error, :database_file_missing} = DataPlane.query(database.id, "SELECT 1")
  end

  defp seed_replica_fixture(database) do
    data_dir = Application.fetch_env!(:sqlites, :data_dir)
    fixture = Path.join([data_dir, "fixtures", database.id <> ".db"])
    File.mkdir_p!(Path.dirname(fixture))

    {:ok, conn} = Exqlite.Sqlite3.open(fixture)
    :ok = Exqlite.Sqlite3.execute(conn, "CREATE TABLE t (v TEXT)")
    :ok = Exqlite.Sqlite3.execute(conn, "INSERT INTO t VALUES ('survived-failover')")
    :ok = Exqlite.Sqlite3.close(conn)

    on_exit(fn -> File.rm(fixture) end)
    fixture
  end

  defp write_restore_stub(fixture) do
    data_dir = Application.fetch_env!(:sqlites, :data_dir)

    stub =
      Path.join([data_dir, "fixtures", "litestream-stub-#{System.unique_integer([:positive])}"])

    File.mkdir_p!(Path.dirname(stub))

    File.write!(stub, """
    #!/bin/sh
    if [ "$1" = "restore" ]; then mkdir -p "$(dirname "$3")" && cp #{fixture} "$3"; exit 0; fi
    exit 0
    """)

    File.chmod!(stub, 0o755)
    on_exit(fn -> File.rm(stub) end)
    stub
  end
end

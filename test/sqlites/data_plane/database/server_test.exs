defmodule Sqlites.DataPlane.Database.ServerTest do
  use ExUnit.Case, async: false

  alias Sqlites.DataPlane.Database.Server

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    database_id = "server-test-#{System.unique_integer([:positive])}"
    file_path = Path.join(tmp_dir, database_id <> ".db")

    start_supervised!({Server, database_id: database_id, file_path: file_path})

    %{database_id: database_id, file_path: file_path}
  end

  test "runs DDL, writes, and reads", %{database_id: database_id} do
    assert {:ok, _} = Server.query(database_id, "CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)")

    assert {:ok, %{num_changes: 2, last_insert_rowid: 2}} =
             Server.query(database_id, "INSERT INTO t (v) VALUES (?), (?)", ["a", "b"])

    assert {:ok, %{columns: ["id", "v"], rows: [[1, "a"], [2, "b"]]}} =
             Server.query(database_id, "SELECT * FROM t ORDER BY id")
  end

  test "returns errors for bad SQL without crashing", %{database_id: database_id} do
    assert {:error, message} = Server.query(database_id, "SELEC nope")
    assert message =~ "syntax error"

    assert {:error, message} = Server.query(database_id, "SELECT ?", [])
    assert message =~ "expected 1 arguments"

    assert {:ok, %{rows: [[1]]}} = Server.query(database_id, "SELECT 1")
  end

  test "registers in syn and is discoverable", %{database_id: database_id} do
    pid = Sqlites.DataPlane.Registry.whereis(database_id)
    assert is_pid(pid)
    assert {:ok, node} = Sqlites.DataPlane.Registry.owner_node(database_id)
    assert node == Node.self()
  end

  test "serializes concurrent writes through the single owner", %{database_id: database_id} do
    assert {:ok, _} = Server.query(database_id, "CREATE TABLE counter (n INTEGER)")
    assert {:ok, _} = Server.query(database_id, "INSERT INTO counter VALUES (0)")

    1..50
    |> Task.async_stream(
      fn _ -> Server.query(database_id, "UPDATE counter SET n = n + 1") end,
      max_concurrency: 20
    )
    |> Stream.run()

    assert {:ok, %{rows: [[50]]}} = Server.query(database_id, "SELECT n FROM counter")
  end

  test "stops after the idle TTL, kept alive by queries", %{tmp_dir: tmp_dir} do
    database_id = "ttl-test-#{System.unique_integer([:positive])}"
    file_path = Path.join(tmp_dir, database_id <> ".db")

    start_supervised!(
      {Server, database_id: database_id, file_path: file_path, idle_ttl: 300},
      id: :ttl_server
    )

    for _ <- 1..3 do
      Process.sleep(150)
      assert {:ok, _} = Server.query(database_id, "SELECT 1")
    end

    pid = Sqlites.DataPlane.Registry.whereis(database_id)
    assert is_pid(pid)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    assert Sqlites.DataPlane.Registry.whereis(database_id) == :undefined
  end

  test "persists data across a restart", %{database_id: database_id, file_path: file_path} do
    assert {:ok, _} = Server.query(database_id, "CREATE TABLE t (v TEXT)")
    assert {:ok, _} = Server.query(database_id, "INSERT INTO t VALUES ('kept')")

    :ok = Server.stop(database_id)
    start_supervised!({Server, [database_id: database_id, file_path: file_path]}, id: :restarted)

    assert {:ok, %{rows: [["kept"]]}} = Server.query(database_id, "SELECT v FROM t")
  end
end

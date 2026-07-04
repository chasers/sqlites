defmodule Sqlites.DistributedTest do
  @moduledoc """
  Multi-node tests: spins up a real peer BEAM node, places a database
  server there, and verifies that `:syn` makes it discoverable across
  the cluster and that `Router.query/3` reaches it over `gen_rpc`
  (never Erlang distribution for the data path).

  Excluded by default; run with `mix test --include distributed`.
  Requires `epmd` to be running (`epmd -daemon`).
  """

  use ExUnit.Case, async: false

  @moduletag :distributed
  @moduletag :tmp_dir

  @peer_gen_rpc_port 15370

  alias Sqlites.DataPlane.Registry
  alias Sqlites.DataPlane.Router

  setup_all do
    unless Node.alive?() do
      {:ok, _} = :net_kernel.start(:sqlites_primary, %{name_domain: :shortnames})
    end

    :ok
  end

  setup %{tmp_dir: tmp_dir} do
    {:ok, peer_pid, peer_node} = :peer.start_link(%{name: peer_name()})

    :ok = :erpc.call(peer_node, :code, :add_paths, [:code.get_path()])

    :ok =
      :erpc.call(peer_node, Application, :put_env, [
        :gen_rpc,
        :tcp_server_port,
        @peer_gen_rpc_port,
        [persistent: true]
      ])

    {:ok, _} = :erpc.call(peer_node, Application, :ensure_all_started, [:syn])
    {:ok, _} = :erpc.call(peer_node, Application, :ensure_all_started, [:gen_rpc])
    {:ok, _} = :erpc.call(peer_node, Application, :ensure_all_started, [:exqlite])
    :ok = :erpc.call(peer_node, Sqlites.DataPlane.Registry, :init, [])

    previous_config = Application.get_env(:gen_rpc, :client_config_per_node)

    Application.put_env(
      :gen_rpc,
      :client_config_per_node,
      {:internal, %{peer_node => @peer_gen_rpc_port}}
    )

    on_exit(fn ->
      Application.put_env(:gen_rpc, :client_config_per_node, previous_config)
    end)

    %{peer_pid: peer_pid, peer_node: peer_node, tmp_dir: tmp_dir}
  end

  test "a database on a peer node is discoverable via syn and queryable via gen_rpc",
       %{peer_pid: peer_pid, peer_node: peer_node, tmp_dir: tmp_dir} do
    database_id = "dist-db-#{System.unique_integer([:positive])}"
    file_path = Path.join(tmp_dir, database_id <> ".db")

    {:ok, remote_pid} = start_remote_server(peer_node, database_id, file_path)

    assert node(remote_pid) == peer_node

    wait_until(fn -> Registry.whereis(database_id) == remote_pid end)
    assert {:ok, ^peer_node} = Registry.owner_node(database_id)

    assert {:ok, _} = Router.query(database_id, "CREATE TABLE t (v TEXT)")

    assert {:ok, %{num_changes: 1}} =
             Router.query(database_id, "INSERT INTO t VALUES (?)", ["from-primary"])

    assert {:ok, %{rows: [["from-primary"]]}} = Router.query(database_id, "SELECT v FROM t")

    assert File.exists?(file_path)
  end

  test "syn deregisters the database when the peer goes down",
       %{peer_pid: peer_pid, peer_node: peer_node, tmp_dir: tmp_dir} do
    database_id = "dist-db-#{System.unique_integer([:positive])}"
    file_path = Path.join(tmp_dir, database_id <> ".db")

    {:ok, remote_pid} = start_remote_server(peer_node, database_id, file_path)

    wait_until(fn -> Registry.whereis(database_id) == remote_pid end)

    :peer.stop(peer_pid)

    wait_until(fn -> Registry.whereis(database_id) == :undefined end)
    assert {:error, :database_not_running} = Router.query(database_id, "SELECT 1")
  end

  defp start_remote_server(peer_node, database_id, file_path) do
    via = :erpc.call(peer_node, Sqlites.DataPlane.Registry, :via, [database_id])

    :erpc.call(peer_node, GenServer, :start, [
      Sqlites.DataPlane.Database.Server,
      [database_id: database_id, file_path: file_path],
      [name: via]
    ])
  end

  defp peer_name do
    :"sqlites_peer_#{System.unique_integer([:positive])}"
  end

  defp wait_until(fun, attempts \\ 100)

  defp wait_until(fun, 0) do
    assert fun.()
  end

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      wait_until(fun, attempts - 1)
    end
  end
end

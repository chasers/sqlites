defmodule Smolsqls.NetsplitTest do
  @moduledoc """
  Live WAN-partition tests: boots a peer BEAM whose control channel rides
  `:standard_io` (not Erlang distribution), so the test keeps driving both
  nodes with `:peer.call/4` while distribution between them is severed. The
  partition itself is a cookie mismatch + `disconnect_node`, which also blocks
  reconnection until healed.

  Excluded by default; run with `mix test --include distributed`.
  Requires `epmd` (`epmd -daemon`).
  """

  use ExUnit.Case, async: false

  @moduletag :distributed
  @moduletag :tmp_dir

  alias Smolsqls.DataPlane.Database.Server
  alias Smolsqls.DataPlane.Registry
  alias Smolsqls.DataPlane.SynHandler

  @peer_gen_rpc_port 15_470

  setup_all do
    unless Node.alive?() do
      {:ok, _} = :net_kernel.start(:smolsqls_primary, %{name_domain: :shortnames})
    end

    :ok
  end

  setup do
    cookie = :erlang.get_cookie()

    {:ok, peer_pid, peer_node} =
      :peer.start_link(%{
        name: :"smolsqls_ns_#{System.unique_integer([:positive])}",
        connection: :standard_io
      })

    :peer.call(peer_pid, :erlang, :set_cookie, [cookie])
    :peer.call(peer_pid, :code, :add_paths, [:code.get_path()])

    peer_env =
      for app <- [:smolsqls, :phoenix, :logger, :gen_rpc], do: {app, Application.get_all_env(app)}

    :peer.call(peer_pid, Application, :put_all_env, [peer_env, [persistent: true]])

    :peer.call(peer_pid, Application, :put_env, [
      :gen_rpc,
      :tcp_server_port,
      @peer_gen_rpc_port,
      [persistent: true]
    ])

    {:ok, _} = :peer.call(peer_pid, Application, :ensure_all_started, [:smolsqls])
    :peer.call(peer_pid, Ecto.Adapters.SQL.Sandbox, :mode, [Smolsqls.Repo, :auto])

    true = Node.connect(peer_node)

    previous = Application.get_env(:gen_rpc, :client_config_per_node)

    Application.put_env(
      :gen_rpc,
      :client_config_per_node,
      {:internal, %{peer_node => @peer_gen_rpc_port}}
    )

    on_exit(fn -> Application.put_env(:gen_rpc, :client_config_per_node, previous) end)

    %{peer_pid: peer_pid, peer_node: peer_node, cookie: cookie}
  end

  test "sever isolates the peer over distribution; heal reconnects", ctx do
    assert ctx.peer_node in Node.list()
    assert Node.self() in peer_node_list(ctx)

    sever(ctx)

    refute ctx.peer_node in Node.list()
    refute Node.self() in peer_node_list(ctx)

    heal(ctx)

    assert ctx.peer_node in Node.list()
    assert Node.self() in peer_node_list(ctx)
  end

  test "a conflicting registration across a healed partition resolves to one deterministic writer",
       %{peer_pid: peer_pid, peer_node: peer_node, tmp_dir: tmp_dir} = ctx do
    id = "ns-db-#{System.unique_integer([:positive])}"
    peer_file = Path.join(tmp_dir, "peer-#{id}.db")
    local_file = Path.join(tmp_dir, "local-#{id}.db")

    peer_via = :peer.call(peer_pid, Registry, :via, [id])

    {:ok, peer_server} =
      :peer.call(peer_pid, GenServer, :start, [
        Server,
        [database_id: id, file_path: peer_file],
        [name: peer_via]
      ])

    wait_until(fn -> Registry.owner_node(id) == {:ok, peer_node} end)

    sever(ctx)
    wait_until(fn -> Registry.owner_node(id) == {:error, :not_found} end)

    {:ok, local_server} =
      GenServer.start(Server, [database_id: id, file_path: local_file], name: Registry.via(id))

    heal(ctx)

    winner = SynHandler.pick_winner(id, local_server, peer_server)

    if winner == local_server do
      wait_until(fn -> not peer_alive?(ctx, peer_server) end)
      assert Process.alive?(local_server)
      wait_until(fn -> Registry.owner_node(id) == {:ok, Node.self()} end)
    else
      wait_until(fn -> not Process.alive?(local_server) end)
      assert peer_alive?(ctx, peer_server)
      wait_until(fn -> Registry.owner_node(id) == {:ok, peer_node} end)
    end
  end

  defp peer_alive?(ctx, pid), do: :peer.call(ctx.peer_pid, Process, :alive?, [pid])

  defp peer_node_list(ctx), do: :peer.call(ctx.peer_pid, Node, :list, [])

  defp sever(ctx) do
    :erlang.set_cookie(ctx.peer_node, :partitioned)
    :peer.call(ctx.peer_pid, :erlang, :set_cookie, [Node.self(), :partitioned])
    :erlang.disconnect_node(ctx.peer_node)

    wait_until(fn ->
      ctx.peer_node not in Node.list() and Node.self() not in peer_node_list(ctx)
    end)
  end

  defp heal(ctx) do
    :erlang.set_cookie(ctx.peer_node, ctx.cookie)
    :peer.call(ctx.peer_pid, :erlang, :set_cookie, [Node.self(), ctx.cookie])

    wait_until(fn -> Node.connect(ctx.peer_node) == true and ctx.peer_node in Node.list() end)
  end

  defp wait_until(fun, attempts \\ 100)
  defp wait_until(fun, 0), do: assert(fun.())

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      wait_until(fun, attempts - 1)
    end
  end
end

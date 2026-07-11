defmodule Smolsqls.DataPlane.SynHandlerTest do
  use ExUnit.Case, async: true

  alias Smolsqls.DataPlane.SynHandler

  defp start_server do
    {:ok, pid} = Agent.start(fn -> :ok end)
    pid
  end

  test "is wired as the :syn event handler at boot" do
    assert Application.get_env(:syn, :event_handler) == SynHandler
  end

  test "pick_winner is independent of argument order" do
    a = start_server()
    b = start_server()

    assert SynHandler.pick_winner("db-x", a, b) == SynHandler.pick_winner("db-x", b, a)
    assert SynHandler.pick_winner("db-x", a, b) in [a, b]
  end

  test "resolve_registry_conflict keeps the winner and stops the local loser without shipping" do
    a = start_server()
    b = start_server()

    winner = SynHandler.resolve_registry_conflict(:scope, "db-y", {a, %{}, 1}, {b, %{}, 2})
    loser = if winner == a, do: b, else: a

    assert winner == SynHandler.pick_winner("db-y", a, b)

    ref = Process.monitor(loser)
    assert_receive {:DOWN, ^ref, :process, ^loser, :normal}, 2_000
    assert Process.alive?(winner)
  end
end

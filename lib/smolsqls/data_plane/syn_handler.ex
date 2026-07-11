defmodule Smolsqls.DataPlane.SynHandler do
  @moduledoc """
  `:syn` event handler for the database registry. Its job is deterministic,
  graceful resolution of registry conflicts — two `Database.Server`s
  registered under the same database id, which happens when a network
  partition heals or a node-death/reassign race briefly produces two writers.

  `:syn`'s default resolution keeps the process with the higher registration
  timestamp (millisecond precision, so ties and clock skew make the winner
  differ between nodes) and hard-kills the loser. This handler instead:

    * picks the winner by a pure function of the database id and the two
      owning node names, so every node resolves the same conflict to the same
      process regardless of timing; and
    * stops the losing server gracefully and WITHOUT shipping — the loser's
      snapshot must never clobber the winner's object-store state — the same
      no-ship path `Fence` uses.

  It does not by itself stop two writers from both accepting writes *during* a
  partition; it makes the moment they become visible to each other resolve
  deterministically and cleanly, without flapping.
  """

  @behaviour :syn_event_handler

  require Logger

  @stop_timeout :timer.seconds(5)

  @impl true
  def resolve_registry_conflict(
        _scope,
        database_id,
        {pid1, _meta1, _time1},
        {pid2, _meta2, _time2}
      ) do
    winner = pick_winner(database_id, pid1, pid2)
    loser = if winner == pid1, do: pid2, else: pid1

    if node(loser) == Node.self(), do: stop_loser(database_id, loser)

    winner
  end

  @doc false
  @spec pick_winner(term(), pid(), pid()) :: pid()
  def pick_winner(database_id, pid1, pid2) do
    [lower, higher] = Enum.sort_by([pid1, pid2], &{Atom.to_string(node(&1)), &1})

    case :erlang.phash2(database_id, 2) do
      0 -> lower
      1 -> higher
    end
  end

  defp stop_loser(database_id, loser) do
    Logger.warning(
      "syn registry conflict for #{database_id}: stopping local writer #{inspect(loser)} without ship"
    )

    Smolsqls.Telemetry.syn_conflict_resolved()
    spawn(fn -> graceful_stop(loser) end)
    :ok
  end

  defp graceful_stop(pid) do
    GenServer.stop(pid, :normal, @stop_timeout)
  catch
    :exit, _ -> Process.exit(pid, :kill)
  end
end

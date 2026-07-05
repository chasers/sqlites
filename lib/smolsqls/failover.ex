defmodule Smolsqls.Failover do
  @moduledoc """
  Evacuates a dead node: every database placed on it is reassigned to
  the surviving nodes. No data moves here — the next query for each
  database activates it on its new owner, and activation restores the
  litestream replica when the file isn't on the local volume. Only
  queried databases pay restore cost, and only when queried.

  Manual trigger (run from any live node):

      bin/smolsqls rpc 'Smolsqls.Failover.evacuate("smolsqls@dead-node...")'

  Automatic promotion on nodedown is deliberately not wired yet.
  """

  import Ecto.Query

  require Logger

  alias Smolsqls.ControlPlane.Database
  alias Smolsqls.Repo

  @spec evacuate(String.t()) :: {:ok, %{reassigned: non_neg_integer()}} | {:error, term()}
  def evacuate(dead_node) when is_binary(dead_node) do
    survivors =
      [Node.self() | Node.list()]
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == dead_node))

    if survivors == [] do
      {:error, :no_survivors}
    else
      ids =
        Database
        |> where([d], d.node == ^dead_node)
        |> select([d], d.id)
        |> Repo.all()

      reassigned =
        ids
        |> Enum.with_index()
        |> Enum.group_by(fn {_id, index} -> Enum.at(survivors, rem(index, length(survivors))) end)
        |> Enum.reduce(0, fn {survivor, entries}, acc ->
          chunk_ids = Enum.map(entries, fn {id, _} -> id end)

          {count, _} =
            Database
            |> where([d], d.id in ^chunk_ids and d.node == ^dead_node)
            |> Repo.update_all(set: [node: survivor, updated_at: DateTime.utc_now()])

          acc + count
        end)

      Logger.warning("failover: reassigned #{reassigned} database(s) from #{dead_node}")
      {:ok, %{reassigned: reassigned}}
    end
  end
end

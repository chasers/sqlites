defmodule Sqlites.DataPlane.Registry do
  @moduledoc """
  Cluster-wide process registry for database servers, backed by `:syn`.
  Registration metadata carries the owning node so lookups can decide
  between a local call and a `gen_rpc` hop without a second round trip.
  """

  @scope :sqlites_databases

  def scope, do: @scope

  def init do
    :syn.add_node_to_scopes([@scope])
  end

  def via(database_id) do
    {:via, :syn, {@scope, database_id, %{node: Node.self()}}}
  end

  @spec whereis(String.t()) :: pid() | :undefined
  def whereis(database_id) do
    case :syn.lookup(@scope, database_id) do
      {pid, _meta} -> pid
      :undefined -> :undefined
    end
  end

  @spec owner_node(String.t()) :: {:ok, node()} | {:error, :not_found}
  def owner_node(database_id) do
    case :syn.lookup(@scope, database_id) do
      {pid, _meta} -> {:ok, node(pid)}
      :undefined -> {:error, :not_found}
    end
  end
end

defmodule Sqlites.DataPlane.Router do
  @moduledoc """
  Routes a query to whichever node owns the database's `Server` process.
  Local databases are called directly; remote ones go over `gen_rpc`
  so query/result traffic stays off Erlang distribution — erl_dist
  carries only cluster membership and `:syn` gossip.
  """

  alias Sqlites.ControlPlane
  alias Sqlites.DataPlane.Database.Server
  alias Sqlites.DataPlane.Registry

  @gen_rpc_timeout :timer.seconds(35)

  @spec query(String.t(), String.t(), [term()]) ::
          {:ok, Server.query_result()} | {:error, term()}
  def query(database_id, sql, args \\ []) do
    case Registry.owner_node(database_id) do
      {:ok, node} -> dispatch(node, database_id, sql, args)
      {:error, :not_found} -> activate_and_query(database_id, sql, args)
    end
  end

  defp activate_and_query(database_id, sql, args) do
    with %ControlPlane.Database{} = database <- ControlPlane.lookup_database(database_id),
         {:ok, pid} <- Sqlites.DataPlane.activate_database(database) do
      dispatch(node(pid), database_id, sql, args)
    else
      nil -> {:error, :database_not_running}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Entry point for remote nodes: executed on the owning node via
  `:gen_rpc.call/5`, where the `:syn` lookup resolves to a local pid.
  """
  @spec local_query(String.t(), String.t(), [term()]) ::
          {:ok, Server.query_result()} | {:error, term()}
  def local_query(database_id, sql, args) do
    case Registry.whereis(database_id) do
      pid when is_pid(pid) -> Server.query(pid, sql, args)
      :undefined -> {:error, :database_not_running}
    end
  end

  defp dispatch(node, database_id, sql, args) do
    if node == Node.self() do
      local_query(database_id, sql, args)
    else
      case :gen_rpc.call(
             node,
             __MODULE__,
             :local_query,
             [database_id, sql, args],
             @gen_rpc_timeout
           ) do
        {:badrpc, reason} -> {:error, {:badrpc, reason}}
        {:badtcp, reason} -> {:error, {:badtcp, reason}}
        result -> result
      end
    end
  end
end

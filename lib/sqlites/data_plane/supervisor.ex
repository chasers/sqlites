defmodule Sqlites.DataPlane.Supervisor do
  @moduledoc """
  Supervises the per-database `Database.Server` processes running on
  this node. The control plane decides placement; this supervisor only
  ever starts servers for databases assigned to the local node.

  Starts are partitioned across one `DynamicSupervisor` per scheduler
  via `PartitionSupervisor`, keyed by database id: starts of different
  databases parallelize, while concurrent starts of the same database
  hash to the same partition and serialize — preserving the
  single-activation guarantee.
  """

  alias Sqlites.DataPlane.Database.Server

  def child_spec(_opts) do
    PartitionSupervisor.child_spec(child_spec: DynamicSupervisor, name: __MODULE__)
  end

  @spec start_database(String.t(), String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_database(database_id, file_path, opts \\ []) do
    spec = {Server, Keyword.merge(opts, database_id: database_id, file_path: file_path)}

    case DynamicSupervisor.start_child(partition_for(database_id), spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop_database(String.t()) :: :ok
  def stop_database(database_id) do
    Server.stop(database_id)
  end

  defp partition_for(database_id) do
    {:via, PartitionSupervisor, {__MODULE__, database_id}}
  end
end

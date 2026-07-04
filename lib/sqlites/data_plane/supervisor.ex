defmodule Sqlites.DataPlane.Supervisor do
  @moduledoc """
  Supervises the per-database `Database.Server` processes running on
  this node. The control plane decides placement; this supervisor only
  ever starts servers for databases assigned to the local node.
  """

  use DynamicSupervisor

  alias Sqlites.DataPlane.Database.Server

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_database(String.t(), String.t()) :: {:ok, pid()} | {:error, term()}
  def start_database(database_id, file_path) do
    spec = {Server, database_id: database_id, file_path: file_path}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop_database(String.t()) :: :ok
  def stop_database(database_id) do
    Server.stop(database_id)
  end
end

defmodule Sqlites.DataPlane do
  @moduledoc """
  Public API for the data plane: placing a database's server on this
  node, tearing it down, and executing queries routed to whichever node
  owns the file.
  """

  alias Sqlites.ControlPlane
  alias Sqlites.ControlPlane.Database
  alias Sqlites.DataPlane.{Placement, Registry, Router, Supervisor}

  @gen_rpc_timeout :timer.seconds(15)

  @spec place_database(Database.t()) :: {:ok, Database.t()} | {:error, term()}
  def place_database(%Database{} = database) do
    node = Placement.pick_node()

    if node == Node.self() do
      place_database_locally(database)
    else
      place_database_on(node, database)
    end
  end

  @doc """
  Executed on the node chosen by placement — locally or via `gen_rpc`.
  """
  @spec place_database_locally(Database.t()) :: {:ok, Database.t()} | {:error, term()}
  def place_database_locally(%Database{} = database) do
    file_path = file_path_for(database)

    with {:ok, _pid} <- Supervisor.start_database(database.id, file_path) do
      ControlPlane.mark_placed(database, Node.self(), file_path)
    end
  end

  defp place_database_on(node, database) do
    case :gen_rpc.call(node, __MODULE__, :place_database_locally, [database], @gen_rpc_timeout) do
      {:badrpc, reason} -> {:error, {:badrpc, reason}}
      {:badtcp, reason} -> {:error, {:badtcp, reason}}
      result -> result
    end
  end

  @spec remove_database(Database.t()) :: {:ok, Database.t()} | {:error, term()}
  def remove_database(%Database{} = database) do
    owner =
      case database.node do
        nil -> Node.self()
        node_name -> String.to_existing_atom(node_name)
      end

    if owner == Node.self() do
      remove_database_locally(database)
    else
      case :gen_rpc.call(
             owner,
             __MODULE__,
             :remove_database_locally,
             [database],
             @gen_rpc_timeout
           ) do
        {:badrpc, reason} -> {:error, {:badrpc, reason}}
        {:badtcp, reason} -> {:error, {:badtcp, reason}}
        result -> result
      end
    end
  end

  @doc """
  Executed on the node that owns the database file — locally or via
  `gen_rpc`.
  """
  @spec remove_database_locally(Database.t()) :: {:ok, Database.t()} | {:error, term()}
  def remove_database_locally(%Database{} = database) do
    :ok = Supervisor.stop_database(database.id)

    if database.file_path do
      File.rm(database.file_path)
      File.rm(database.file_path <> "-wal")
      File.rm(database.file_path <> "-shm")
    end

    ControlPlane.delete_database(database)
  end

  @spec query(String.t(), String.t(), [term()]) ::
          {:ok, Sqlites.DataPlane.Database.Server.query_result()} | {:error, term()}
  def query(database_id, sql, args \\ []) do
    Router.query(database_id, sql, args)
  end

  @spec owner_node(String.t()) :: {:ok, node()} | {:error, :not_found}
  def owner_node(database_id), do: Registry.owner_node(database_id)

  defp file_path_for(%Database{} = database) do
    data_dir()
    |> Path.join(database.tenant_id)
    |> Path.join(database.id <> ".db")
  end

  defp data_dir do
    Application.fetch_env!(:sqlites, :data_dir)
  end
end

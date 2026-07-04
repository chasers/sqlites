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
    on_owner_node(database, :remove_database_locally, [database])
  end

  defp on_owner_node(%Database{} = database, function, args) do
    owner =
      case database.node do
        nil -> Node.self()
        node_name -> String.to_existing_atom(node_name)
      end

    if owner == Node.self() do
      apply(__MODULE__, function, args)
    else
      case :gen_rpc.call(owner, __MODULE__, function, args, @gen_rpc_timeout) do
        {:badrpc, reason} -> {:error, {:badrpc, reason}}
        {:badtcp, reason} -> {:error, {:badtcp, reason}}
        result -> result
      end
    end
  end

  @doc """
  Starts the database's server on its owning node if it isn't running —
  the activate-on-miss path for lazily woken databases.
  """
  @spec activate_database(Database.t()) :: {:ok, pid()} | {:error, term()}
  def activate_database(%Database{status: :active, file_path: file_path} = database)
      when is_binary(file_path) do
    on_owner_node(database, :activate_database_locally, [database])
  end

  def activate_database(%Database{}), do: {:error, :database_not_active}

  @spec activate_database_locally(Database.t()) :: {:ok, pid()} | {:error, term()}
  def activate_database_locally(%Database{} = database) do
    Supervisor.start_database(database.id, database.file_path)
  end

  @spec restore_from_file(Database.t(), Path.t()) :: :ok | {:error, term()}
  def restore_from_file(%Database{} = database, backup_path) do
    on_owner_node(database, :restore_from_file_locally, [database, backup_path])
  end

  @doc """
  Executed on the node that owns the database file — locally or via
  `gen_rpc`. Drains the writer, swaps in the backup, and restarts it.
  """
  @spec restore_from_file_locally(Database.t(), Path.t()) :: :ok | {:error, term()}
  def restore_from_file_locally(%Database{} = database, backup_path) do
    if File.exists?(backup_path) and is_binary(database.file_path) do
      :ok = Supervisor.stop_database(database.id)
      File.rm(database.file_path <> "-wal")
      File.rm(database.file_path <> "-shm")
      File.cp!(backup_path, database.file_path)

      case Supervisor.start_database(database.id, database.file_path) do
        {:ok, _pid} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :backup_not_found}
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

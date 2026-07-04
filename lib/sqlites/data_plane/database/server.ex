defmodule Sqlites.DataPlane.Database.Server do
  @moduledoc """
  Owns the single connection to one SQLite database file and serializes
  all access to it. Exactly one of these runs per database across the
  whole cluster, registered in `:syn` under the `:sqlites_databases`
  scope so any node can locate it.
  """

  use GenServer, restart: :transient

  alias Exqlite.Sqlite3
  alias Sqlites.DataPlane.Registry

  @type query_result :: %{
          columns: [String.t()],
          rows: [[term()]],
          num_changes: integer(),
          last_insert_rowid: integer()
        }

  def start_link(opts) do
    database_id = Keyword.fetch!(opts, :database_id)
    GenServer.start_link(__MODULE__, opts, name: Registry.via(database_id))
  end

  @spec query(pid() | String.t(), String.t(), [term()]) ::
          {:ok, query_result()} | {:error, term()}
  def query(server, sql, args \\ [])

  def query(pid, sql, args) when is_pid(pid) do
    GenServer.call(pid, {:query, sql, args}, :timer.seconds(30))
  end

  def query(database_id, sql, args) when is_binary(database_id) do
    GenServer.call(Registry.via(database_id), {:query, sql, args}, :timer.seconds(30))
  end

  @spec stop(String.t()) :: :ok
  def stop(database_id) do
    case Registry.whereis(database_id) do
      pid when is_pid(pid) -> GenServer.stop(pid, :normal)
      :undefined -> :ok
    end
  end

  @impl true
  def init(opts) do
    database_id = Keyword.fetch!(opts, :database_id)
    file_path = Keyword.fetch!(opts, :file_path)

    File.mkdir_p!(Path.dirname(file_path))

    case Sqlite3.open(file_path) do
      {:ok, conn} ->
        :ok = Sqlite3.execute(conn, "PRAGMA journal_mode=WAL")
        :ok = Sqlite3.execute(conn, "PRAGMA foreign_keys=ON")
        :ok = Sqlite3.set_busy_timeout(conn, :timer.seconds(5))
        {:ok, %{database_id: database_id, file_path: file_path, conn: conn}}

      {:error, reason} ->
        {:stop, {:sqlite_open_failed, reason}}
    end
  end

  @impl true
  def handle_call({:query, sql, args}, _from, state) do
    {:reply, run_query(state.conn, sql, args), state}
  end

  @impl true
  def terminate(_reason, %{conn: conn}) do
    Sqlite3.close(conn)
  end

  defp run_query(conn, sql, args) do
    with {:ok, statement} <- Sqlite3.prepare(conn, sql),
         :ok <- Sqlite3.bind(statement, args),
         {:ok, columns} <- Sqlite3.columns(conn, statement),
         {:ok, rows} <- Sqlite3.fetch_all(conn, statement),
         {:ok, num_changes} <- Sqlite3.changes(conn),
         {:ok, last_insert_rowid} <- Sqlite3.last_insert_rowid(conn) do
      Sqlite3.release(conn, statement)

      {:ok,
       %{
         columns: columns,
         rows: rows,
         num_changes: num_changes,
         last_insert_rowid: last_insert_rowid
       }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  rescue
    e in ArgumentError -> {:error, e.message}
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end

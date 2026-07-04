defmodule Sqlites.Infra.Local do
  @moduledoc """
  Dev/test infra adapter. Backups are consistent snapshots taken with
  `VACUUM INTO` through the database's single-writer server, stored
  under `<data_dir>/backups/<database_id>/`.
  """

  @behaviour Sqlites.Infra

  alias Sqlites.ControlPlane.Database
  alias Sqlites.DataPlane

  @impl true
  def provision(%Database{}), do: :ok

  @impl true
  def deprovision(%Database{} = database) do
    File.rm_rf(backups_dir(database))
    :ok
  end

  @impl true
  def trigger_backup(%Database{} = database) do
    backup_id = generate_backup_id()
    path = backup_path(database, backup_id)
    File.mkdir_p!(Path.dirname(path))

    case DataPlane.query(database.id, "VACUUM INTO ?", [path]) do
      {:ok, _result} ->
        %File.Stat{size: size, mtime: mtime} = File.stat!(path, time: :posix)
        {:ok, %{id: backup_id, created_at: DateTime.from_unix!(mtime), size_bytes: size}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def list_backups(%Database{} = database) do
    dir = backups_dir(database)

    backups =
      case File.ls(dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".db"))
          |> Enum.map(fn file ->
            %File.Stat{size: size, mtime: mtime} = File.stat!(Path.join(dir, file), time: :posix)

            %{
              id: Path.rootname(file),
              created_at: DateTime.from_unix!(mtime),
              size_bytes: size
            }
          end)
          |> Enum.sort_by(& &1.created_at, {:desc, DateTime})

        {:error, :enoent} ->
          []
      end

    {:ok, backups}
  end

  @impl true
  def restore(%Database{} = database, backup_id) do
    DataPlane.restore_from_file(database, backup_path(database, backup_id))
  end

  defp generate_backup_id do
    Base.hex_encode32(:crypto.strong_rand_bytes(10), case: :lower, padding: false)
  end

  defp backup_path(database, backup_id) do
    Path.join(backups_dir(database), backup_id <> ".db")
  end

  defp backups_dir(database) do
    Application.fetch_env!(:sqlites, :data_dir)
    |> Path.join("backups")
    |> Path.join(database.id)
  end
end

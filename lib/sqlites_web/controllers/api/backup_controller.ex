defmodule SqlitesWeb.Api.BackupController do
  use SqlitesWeb, :controller

  alias Sqlites.Backups
  alias Sqlites.ControlPlane

  action_fallback SqlitesWeb.Api.FallbackController

  def index(conn, %{"database_id" => database_id}) do
    with {:ok, database} <- fetch_database(conn, database_id) do
      render(conn, :index, backups: Backups.list(database))
    end
  end

  def create(conn, %{"database_id" => database_id}) do
    with {:ok, database} <- fetch_database(conn, database_id),
         {:ok, backup} <- Backups.trigger(database) do
      conn
      |> put_status(:created)
      |> render(:show, backup: backup)
    end
  end

  def restore(conn, %{"database_id" => database_id, "backup_id" => backup_id}) do
    with {:ok, database} <- fetch_database(conn, database_id),
         :ok <- Backups.restore(database, backup_id) do
      send_resp(conn, :accepted, "")
    end
  end

  defp fetch_database(conn, id) do
    case ControlPlane.get_database(conn.assigns.current_tenant, id) do
      nil -> {:error, :not_found}
      database -> {:ok, database}
    end
  end
end

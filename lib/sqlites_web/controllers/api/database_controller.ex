defmodule SqlitesWeb.Api.DatabaseController do
  use SqlitesWeb, :controller

  alias Sqlites.ControlPlane
  alias Sqlites.DataPlane
  alias Sqlites.Infra

  action_fallback SqlitesWeb.Api.FallbackController

  def index(conn, _params) do
    databases = ControlPlane.list_databases(conn.assigns.current_tenant)
    render(conn, :index, databases: databases)
  end

  def create(conn, params) do
    tenant = conn.assigns.current_tenant

    with {:ok, database} <- ControlPlane.create_database(tenant, params),
         {:ok, database} <- DataPlane.place_database(database),
         :ok <- Infra.provision(database) do
      conn
      |> put_status(:created)
      |> render(:show, database: database, include_token: true)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, database} <- fetch_database(conn, id) do
      render(conn, :show, database: database, include_token: true)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, database} <- fetch_database(conn, id),
         {:ok, database} <- ControlPlane.mark_deleting(database),
         :ok <- Infra.deprovision(database),
         {:ok, _database} <- DataPlane.remove_database(database) do
      send_resp(conn, :no_content, "")
    end
  end

  defp fetch_database(conn, id) do
    case ControlPlane.get_database(conn.assigns.current_tenant, id) do
      nil -> {:error, :not_found}
      database -> {:ok, database}
    end
  end
end

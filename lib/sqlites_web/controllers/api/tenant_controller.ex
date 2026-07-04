defmodule SqlitesWeb.Api.TenantController do
  use SqlitesWeb, :controller

  alias Sqlites.ControlPlane

  action_fallback SqlitesWeb.Api.FallbackController

  def create(conn, params) do
    with {:ok, tenant} <- ControlPlane.create_tenant(params) do
      conn
      |> put_status(:created)
      |> render(:show, tenant: tenant, include_api_key: true)
    end
  end

  def show(conn, _params) do
    render(conn, :show, tenant: conn.assigns.current_tenant, include_api_key: false)
  end

  def update(conn, params) do
    with {:ok, tenant} <- ControlPlane.update_tenant(conn.assigns.current_tenant, params) do
      render(conn, :show, tenant: tenant, include_api_key: false)
    end
  end

  def delete(conn, _params) do
    with {:ok, _tenant} <- Sqlites.delete_tenant(conn.assigns.current_tenant) do
      send_resp(conn, :no_content, "")
    end
  end
end

defmodule SqlitesWeb.SessionController do
  use SqlitesWeb, :controller

  alias Sqlites.ControlPlane

  def create(conn, %{"api_key" => api_key}) do
    case ControlPlane.authenticate_tenant(api_key) do
      {:ok, _tenant} ->
        conn
        |> put_session(:api_key, api_key)
        |> redirect(to: ~p"/dashboard")

      {:error, :unauthorized} ->
        conn
        |> put_flash(:error, "Invalid API key")
        |> redirect(to: ~p"/")
    end
  end

  def signup(conn, params) do
    case ControlPlane.create_tenant(params) do
      {:ok, tenant} ->
        conn
        |> put_session(:api_key, tenant.api_key)
        |> put_flash(
          :info,
          "Tenant created. Your API key (save it, it is shown only once): #{tenant.api_key}"
        )
        |> redirect(to: ~p"/dashboard")

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Could not create tenant: #{inspect(changeset.errors)}")
        |> redirect(to: ~p"/")
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: ~p"/")
  end
end

defmodule Sqlites.ControlPlane do
  @moduledoc """
  Tenant-facing metadata: tenants and the databases they own. This context
  never touches a SQLite file directly — placement and file lifecycle are
  carried out by `Sqlites.DataPlane` and, in a deployed cluster, by the
  Kubernetes operator.
  """

  import Ecto.Query

  alias Sqlites.Repo
  alias Sqlites.ControlPlane.{Tenant, Database}

  def create_tenant(attrs) do
    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert()
  end

  def get_tenant(id), do: Repo.get(Tenant, id)

  def get_tenant_by_slug(slug), do: Repo.get_by(Tenant, slug: slug)

  def authenticate_tenant(api_key) when is_binary(api_key) do
    case Repo.get_by(Tenant, api_key: api_key) do
      %Tenant{} = tenant -> {:ok, tenant}
      nil -> {:error, :unauthorized}
    end
  end

  def update_tenant(%Tenant{} = tenant, attrs) do
    tenant
    |> Tenant.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_tenant(%Tenant{} = tenant) do
    Repo.delete(tenant)
  end

  def list_databases(%Tenant{id: tenant_id}) do
    Database
    |> where([d], d.tenant_id == ^tenant_id)
    |> order_by([d], asc: d.inserted_at)
    |> Repo.all()
  end

  def get_database(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Database, uuid)
      :error -> nil
    end
  end

  def get_database_by_auth_token(auth_token) when is_binary(auth_token) do
    Repo.get_by(Database, auth_token: auth_token)
  end

  def authenticate_database(id, auth_token)
      when is_binary(id) and is_binary(auth_token) do
    with %Database{auth_token: stored} = database when is_binary(stored) <- get_database(id),
         true <- Plug.Crypto.secure_compare(stored, auth_token) do
      {:ok, database}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def get_database(%Tenant{id: tenant_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        Database
        |> where([d], d.tenant_id == ^tenant_id and d.id == ^uuid)
        |> Repo.one()

      :error ->
        nil
    end
  end

  def create_database(%Tenant{} = tenant, attrs) do
    %Database{}
    |> Database.create_changeset(Map.put(attrs, "tenant_id", tenant.id))
    |> Repo.insert()
  end

  def mark_placed(%Database{} = database, node, file_path) do
    database
    |> Database.placement_changeset(%{
      status: :active,
      node: to_string(node),
      file_path: file_path
    })
    |> Repo.update()
  end

  def mark_deleting(%Database{} = database) do
    database
    |> Database.placement_changeset(%{status: :deleting})
    |> Repo.update()
  end

  def delete_database(%Database{} = database) do
    Repo.delete(database)
  end
end

defmodule Sqlites.ControlPlane do
  @moduledoc """
  Tenant-facing metadata: tenants and the databases they own. This context
  never touches a SQLite file directly — placement and file lifecycle are
  carried out by `Sqlites.DataPlane` and, in a deployed cluster, by the
  Kubernetes operator.

  Request-path reads (`authenticate_tenant/1`, `authenticate_database/2`,
  `get_database_by_auth_token/1`, `lookup_database/1`) are served from
  `Sqlites.ReadModel` when it is ready, so Postgres never sits on the
  data path. Writes go to Postgres (the source of truth) and are also
  applied to the local read model immediately; other nodes converge via
  the WAL feed.
  """

  import Ecto.Query

  alias Sqlites.ControlPlane.{Database, Tenant}
  alias Sqlites.ReadModel
  alias Sqlites.Repo

  def create_tenant(attrs) do
    %Tenant{}
    |> Tenant.changeset(attrs)
    |> Repo.insert()
    |> write_through(&ReadModel.put_tenant/1)
  end

  def get_tenant(id), do: Repo.get(Tenant, id)

  def get_tenant_by_slug(slug), do: Repo.get_by(Tenant, slug: slug)

  def authenticate_tenant(api_key) when is_binary(api_key) do
    lookup =
      if ReadModel.ready?() do
        ReadModel.get_tenant_by_api_key(api_key)
      else
        Repo.get_by(Tenant, api_key: api_key)
      end

    case lookup do
      %Tenant{} = tenant -> {:ok, tenant}
      nil -> {:error, :unauthorized}
    end
  end

  def update_tenant(%Tenant{} = tenant, attrs) do
    tenant
    |> Tenant.update_changeset(attrs)
    |> Repo.update()
    |> write_through(&ReadModel.put_tenant/1)
  end

  def delete_tenant(%Tenant{} = tenant) do
    tenant
    |> Repo.delete()
    |> write_through(&ReadModel.delete_tenant(&1.id))
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

  @doc """
  Hot-path database lookup, served from the read model when ready.
  """
  @spec lookup_database(String.t()) :: Database.t() | nil
  def lookup_database(id) when is_binary(id) do
    if ReadModel.ready?() do
      ReadModel.get_database(id)
    else
      get_database(id)
    end
  end

  def get_database_by_auth_token(auth_token) when is_binary(auth_token) do
    if ReadModel.ready?() do
      ReadModel.get_database_by_auth_token(auth_token)
    else
      Repo.get_by(Database, auth_token: auth_token)
    end
  end

  def authenticate_database(id, auth_token)
      when is_binary(id) and is_binary(auth_token) do
    with %Database{auth_token: stored} = database when is_binary(stored) <- lookup_database(id),
         true <- Plug.Crypto.secure_compare(stored, auth_token) do
      {:ok, database}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def create_database(%Tenant{} = tenant, attrs) do
    %Database{}
    |> Database.create_changeset(Map.put(attrs, "tenant_id", tenant.id))
    |> Repo.insert()
    |> write_through(&ReadModel.put_database/1)
  end

  def update_database_settings(%Database{} = database, attrs) do
    database
    |> Database.settings_changeset(attrs)
    |> Repo.update()
    |> write_through(&ReadModel.put_database/1)
  end

  def mark_placed(%Database{} = database, node, file_path) do
    database
    |> Database.placement_changeset(%{
      status: :active,
      node: to_string(node),
      file_path: file_path
    })
    |> Repo.update()
    |> write_through(&ReadModel.put_database/1)
  end

  def mark_deleting(%Database{} = database) do
    database
    |> Database.placement_changeset(%{status: :deleting})
    |> Repo.update()
    |> write_through(&ReadModel.put_database/1)
  end

  def delete_database(%Database{} = database) do
    database
    |> Repo.delete()
    |> write_through(&ReadModel.delete_database(&1.id))
  end

  defp write_through({:ok, record} = result, apply_fun) do
    if ReadModel.ready?(), do: apply_fun.(record)
    result
  end

  defp write_through(result, _apply_fun), do: result
end

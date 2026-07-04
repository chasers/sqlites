defmodule Sqlites.ReadModel do
  @moduledoc """
  Full in-memory replica of the request-path metadb tables (`tenants`,
  `databases`), so auth and placement reads never touch Postgres.
  Postgres remains the sole source of truth for writes; these tables
  are written only by the COPY snapshot, the WAL replication feed, and
  local write-through from control-plane mutations.

  When the read model is ready, a miss here definitively means the row
  does not exist. Timestamps are not replicated (hot paths don't read
  them); rows loaded via snapshot/WAL carry `nil` timestamps.
  """

  use GenServer

  alias Sqlites.ControlPlane.{Database, Tenant}

  @databases __MODULE__.Databases
  @databases_by_token __MODULE__.DatabasesByToken
  @tenants __MODULE__.Tenants
  @tenants_by_api_key __MODULE__.TenantsByApiKey

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__, timeout: :timer.minutes(5))
  end

  @impl true
  def init(opts) do
    for table <- [@databases, @databases_by_token, @tenants, @tenants_by_api_key] do
      :ets.new(table, [:set, :named_table, :public, read_concurrency: true])
    end

    if Keyword.get(opts, :snapshot, true) do
      Sqlites.ReadModel.Snapshot.load()
      mark_ready()
    end

    {:ok, %{}}
  end

  @spec ready?() :: boolean()
  def ready? do
    :persistent_term.get({__MODULE__, :ready}, false)
  end

  def mark_ready do
    :persistent_term.put({__MODULE__, :ready}, true)
  end

  def mark_not_ready do
    :persistent_term.erase({__MODULE__, :ready})
    :ok
  end

  @spec get_database(String.t()) :: Database.t() | nil
  def get_database(id) do
    case :ets.lookup(@databases, id) do
      [{^id, database}] -> database
      [] -> nil
    end
  end

  @spec get_database_by_auth_token(String.t()) :: Database.t() | nil
  def get_database_by_auth_token(auth_token) do
    case :ets.lookup(@databases_by_token, auth_token) do
      [{^auth_token, id}] -> get_database(id)
      [] -> nil
    end
  end

  @spec get_tenant(String.t()) :: Tenant.t() | nil
  def get_tenant(id) do
    case :ets.lookup(@tenants, id) do
      [{^id, tenant}] -> tenant
      [] -> nil
    end
  end

  @spec get_tenant_by_api_key(String.t()) :: Tenant.t() | nil
  def get_tenant_by_api_key(api_key) do
    case :ets.lookup(@tenants_by_api_key, api_key) do
      [{^api_key, id}] -> get_tenant(id)
      [] -> nil
    end
  end

  @spec put_database(Database.t()) :: :ok
  def put_database(%Database{} = database) do
    case get_database(database.id) do
      %Database{auth_token: old_token} when old_token != database.auth_token ->
        :ets.delete(@databases_by_token, old_token)

      _ ->
        :ok
    end

    :ets.insert(@databases, {database.id, database})
    :ets.insert(@databases_by_token, {database.auth_token, database.id})
    :ok
  end

  @spec delete_database(String.t()) :: :ok
  def delete_database(id) do
    case get_database(id) do
      %Database{auth_token: token} -> :ets.delete(@databases_by_token, token)
      nil -> :ok
    end

    :ets.delete(@databases, id)
    :ok
  end

  @spec put_tenant(Tenant.t()) :: :ok
  def put_tenant(%Tenant{} = tenant) do
    case get_tenant(tenant.id) do
      %Tenant{api_key: old_key} when old_key != tenant.api_key ->
        :ets.delete(@tenants_by_api_key, old_key)

      _ ->
        :ok
    end

    :ets.insert(@tenants, {tenant.id, tenant})
    :ets.insert(@tenants_by_api_key, {tenant.api_key, tenant.id})
    :ok
  end

  @spec delete_tenant(String.t()) :: :ok
  def delete_tenant(id) do
    case get_tenant(id) do
      %Tenant{api_key: api_key} -> :ets.delete(@tenants_by_api_key, api_key)
      nil -> :ok
    end

    :ets.delete(@tenants, id)
    :ok
  end

  @spec truncate(:databases | :tenants) :: :ok
  def truncate(:databases) do
    :ets.delete_all_objects(@databases)
    :ets.delete_all_objects(@databases_by_token)
    :ok
  end

  def truncate(:tenants) do
    :ets.delete_all_objects(@tenants)
    :ets.delete_all_objects(@tenants_by_api_key)
    :ok
  end
end

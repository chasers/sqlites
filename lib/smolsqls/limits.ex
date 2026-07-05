defmodule Smolsqls.Limits do
  @moduledoc """
  Per-tenant/per-database limits. Limits are rows, not config: the
  `limits` map on `databases` overrides the one on `tenants`, which
  overrides the cluster defaults from `config :smolsqls, Smolsqls.Limits`.
  Both maps ride the read model, so resolution at the protocol edge
  and at activation is ETS-only. Changes take effect on the next
  activation (or next request, for edge limits).

  Known keys (string keys in the stored maps):

    * `max_databases` — per tenant, enforced at create time
    * `max_size_bytes` — `PRAGMA max_page_count` at activation
    * `rate_limit_rps` — per database at the protocol edge; nil = off
    * `query_timeout_ms` — caller-side query timeout
    * `statement_timeout_ms` — server-side interrupt of a running
      statement; nil = off
    * `txn_timeout_ms` — idle-in-transaction cap on the writer lease
      (auto-ROLLBACK when it fires)
    * `idle_ttl_ms` — overrides the cluster `:database_idle_ttl`
    * `max_hot_ms` — recycle a server after this long hot; nil = off

  Only these keys resolve; anything else in a `limits` map is ignored.
  There is deliberately no public mutation path yet — limits are set
  with internal tooling directly on the rows.
  """

  alias Smolsqls.ControlPlane.Database
  alias Smolsqls.ControlPlane.Tenant

  @keys [
    :max_databases,
    :max_size_bytes,
    :rate_limit_rps,
    :query_timeout_ms,
    :statement_timeout_ms,
    :txn_timeout_ms,
    :idle_ttl_ms,
    :max_hot_ms
  ]

  @type t :: %{
          max_databases: pos_integer() | nil,
          max_size_bytes: pos_integer() | nil,
          rate_limit_rps: pos_integer() | nil,
          query_timeout_ms: pos_integer() | nil,
          statement_timeout_ms: pos_integer() | nil,
          txn_timeout_ms: pos_integer() | nil,
          idle_ttl_ms: pos_integer() | nil,
          max_hot_ms: pos_integer() | nil
        }

  @spec resolve(Database.t() | nil, Tenant.t() | nil) :: t()
  def resolve(database, tenant \\ nil) do
    tenant = tenant || lookup_tenant(database)

    Map.new(@keys, fn key -> {key, resolve_key(key, database, tenant)} end)
  end

  @spec max_databases(Tenant.t()) :: pos_integer() | nil
  def max_databases(%Tenant{} = tenant) do
    resolve_key(:max_databases, nil, tenant)
  end

  defp resolve_key(key, database, tenant) do
    with :error <- fetch_limit(database, key),
         :error <- fetch_limit(tenant, key) do
      default(key)
    else
      {:ok, value} -> value
    end
  end

  defp fetch_limit(nil, _key), do: :error
  defp fetch_limit(%{limits: nil}, _key), do: :error
  defp fetch_limit(%{limits: limits}, key), do: Map.fetch(limits, Atom.to_string(key))

  defp default(key) do
    Application.get_env(:smolsqls, __MODULE__, [])[key]
  end

  defp lookup_tenant(%Database{tenant_id: tenant_id}) when is_binary(tenant_id) do
    Smolsqls.ControlPlane.lookup_tenant(tenant_id)
  end

  defp lookup_tenant(_database), do: nil
end

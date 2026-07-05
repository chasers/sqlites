defmodule Smolsqls.Telemetry do
  @moduledoc """
  Data-plane telemetry: event names, emission helpers, and the
  periodic measurements polled by `SmolsqlsWeb.Telemetry`. Everything
  here lands on the Prometheus endpoint (`GET /metrics`); the alert
  conditions worth paging on are documented in `docs/alerts.md`.

  Events:

    * `[:smolsqls, :query]` — `%{count, duration_ms}`, tags `result`
      (`ok` | `error` | `badrpc`), `remote` (`true` | `false`)
    * `[:smolsqls, :activation]` — `%{count, duration_ms}`, tag `path`
      (`cache_hit` | `litestream` | `idle_snapshot` | `backup` |
      `missing`)
    * `[:smolsqls, :idle_snapshot, :ship]` — `%{count, duration_ms}`,
      tag `result` (`ok` | `error`)
    * `[:smolsqls, :cache_evictor, :sweep]` — `%{evicted, freed_bytes}`
    * `[:smolsqls, :node_operation]` — `%{count, reassigned}`, tags
      `kind` (`drain` | `evacuate`), `result` (`ok` | `error` |
      `cancelled`)
    * `[:smolsqls, :rate_limiter, :rejected]` — `%{count}`
    * `[:smolsqls, :fence, :stopped]` — `%{count}`
    * `[:smolsqls, :hot_servers]` — `%{count}` (polled)
  """

  @spec query(integer(), atom() | String.t(), boolean()) :: :ok
  def query(duration_ms, result, remote) do
    :telemetry.execute(
      [:smolsqls, :query],
      %{count: 1, duration_ms: duration_ms},
      %{result: to_string(result), remote: to_string(remote)}
    )
  end

  @spec activation(String.t(), integer()) :: :ok
  def activation(path, duration_ms \\ 0) do
    :telemetry.execute(
      [:smolsqls, :activation],
      %{count: 1, duration_ms: duration_ms},
      %{path: path}
    )
  end

  @spec ship(integer(), atom()) :: :ok
  def ship(duration_ms, result) do
    :telemetry.execute(
      [:smolsqls, :idle_snapshot, :ship],
      %{count: 1, duration_ms: duration_ms},
      %{result: to_string(result)}
    )
  end

  @spec eviction_sweep(non_neg_integer(), non_neg_integer()) :: :ok
  def eviction_sweep(evicted, freed_bytes) do
    :telemetry.execute(
      [:smolsqls, :cache_evictor, :sweep],
      %{evicted: evicted, freed_bytes: freed_bytes},
      %{}
    )
  end

  @spec node_operation(String.t(), atom(), non_neg_integer()) :: :ok
  def node_operation(kind, result, reassigned \\ 0) do
    :telemetry.execute(
      [:smolsqls, :node_operation],
      %{count: 1, reassigned: reassigned},
      %{kind: kind, result: to_string(result)}
    )
  end

  @spec rate_limited() :: :ok
  def rate_limited do
    :telemetry.execute([:smolsqls, :rate_limiter, :rejected], %{count: 1}, %{})
  end

  @spec fenced() :: :ok
  def fenced do
    :telemetry.execute([:smolsqls, :fence, :stopped], %{count: 1}, %{})
  end

  @doc """
  Poller measurement: how many database servers are hot on this node.
  """
  @spec emit_hot_servers() :: :ok
  def emit_hot_servers do
    count = :syn.registry_count(Smolsqls.DataPlane.Registry.scope(), Node.self())
    :telemetry.execute([:smolsqls, :hot_servers], %{count: count}, %{})
  end
end

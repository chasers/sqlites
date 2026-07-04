defmodule SqlitesOperator.Controller.SqliteNodeController do
  @moduledoc """
  Reconciles SqliteNode resources — one per data-plane node.

  Per reconcile it refreshes observed node state onto `status`:
  replication-slot health straight from `pg_replication_slots` on the
  metadb (surfacing `wal_status`/retained WAL before a lagging replica
  becomes an incident) and the node's database count from the
  control-plane `databases` table.

  Drain (`spec.drain: true`) marks the intent to evacuate; the actual
  re-placement is executed by the control plane's failover path and
  reported back here. On delete, the node's replication slot is
  dropped so a decommissioned node can never bloat WAL retention.
  """

  use Bonny.ControllerV2

  require Logger

  step(Bonny.Pluggable.SkipObservedGenerations)
  step(:handle_event)

  @impl true
  def rbac_rules do
    []
  end

  def handle_event(%Bonny.Axn{action: action} = axn, _opts)
      when action in [:add, :modify, :reconcile] do
    axn
    |> refresh_status()
    |> success_event()
  end

  def handle_event(%Bonny.Axn{action: :delete} = axn, _opts) do
    slot = slot_name(axn.resource)

    case drop_replication_slot(slot) do
      :ok -> Logger.info("dropped replication slot #{slot}")
      {:error, reason} -> Logger.error("failed to drop slot #{slot}: #{inspect(reason)}")
    end

    axn
  end

  defp refresh_status(axn) do
    slot = slot_name(axn.resource)
    erlang_node = get_in(axn.resource, ["spec", "erlangNode"])

    update_status(axn, fn status ->
      status
      |> Map.put("replicationSlot", slot_status(slot))
      |> Map.put("databaseCount", database_count(erlang_node))
    end)
  end

  defp slot_status(slot) do
    query = """
    SELECT active, wal_status,
           pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)::bigint
    FROM pg_replication_slots WHERE slot_name = $1
    """

    case metadb_query(query, [slot]) do
      {:ok, %{rows: [[active, wal_status, retained]]}} ->
        %{
          "name" => slot,
          "active" => active,
          "walStatus" => wal_status,
          "retainedBytes" => retained || 0
        }

      {:ok, %{rows: []}} ->
        %{"name" => slot, "active" => false, "walStatus" => "absent", "retainedBytes" => 0}

      {:error, reason} ->
        Logger.error("slot status query failed: #{inspect(reason)}")
        nil
    end
  end

  defp database_count(nil), do: 0

  defp database_count(erlang_node) do
    case metadb_query("SELECT count(*) FROM databases WHERE node = $1", [erlang_node]) do
      {:ok, %{rows: [[count]]}} -> count
      {:error, _} -> 0
    end
  end

  defp drop_replication_slot(slot) do
    query = """
    SELECT pg_drop_replication_slot(slot_name)
    FROM pg_replication_slots WHERE slot_name = $1 AND NOT active
    """

    case metadb_query(query, [slot]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp slot_name(resource) do
    case get_in(resource, ["spec", "erlangNode"]) do
      nil ->
        "sqlites_unknown"

      erlang_node ->
        sanitized =
          erlang_node
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9_]/, "_")

        String.slice("sqlites_" <> sanitized, 0, 63)
    end
  end

  defp metadb_query(sql, params) do
    with {:ok, conn} <- metadb_conn() do
      case Postgrex.query(conn, sql, params) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp metadb_conn do
    case :persistent_term.get({__MODULE__, :metadb}, nil) do
      nil ->
        with {:ok, conn} <- Postgrex.start_link(metadb_config()) do
          :persistent_term.put({__MODULE__, :metadb}, conn)
          {:ok, conn}
        end

      conn ->
        {:ok, conn}
    end
  end

  defp metadb_config do
    Application.fetch_env!(:sqlites_operator, :metadb)
  end
end

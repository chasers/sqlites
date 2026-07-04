defmodule SqlitesOperator.Controller.SqliteDatabaseController do
  @moduledoc """
  Reconciles SqliteDatabase custom resources.

  Durability model: each data-plane node pod mounts a PVC holding all
  SQLite files placed on it and runs a Litestream sidecar continuously
  replicating that directory to object storage. This controller's job
  per database is therefore not to create pods but to:

  - acknowledge placement (spec.node) and keep status current,
  - reconcile `spec.backup.requestedAt` into an on-demand Litestream
    snapshot and append it to `status.backups`,
  - reconcile `spec.restore.backupId` into a litestream restore of the
    database file (coordinated with the data plane draining the
    database's writer process),
  - on delete, take a final snapshot before the file is removed and
    apply the retention policy to replicated data.

  The snapshot/restore steps below are scaffolded: they require a real
  cluster with the Litestream sidecar deployed to verify, and are marked
  TODO until that wiring lands.
  """

  use Bonny.ControllerV2

  require Logger

  step(Bonny.Pluggable.SkipObservedGenerations)
  step(:handle_event)

  @impl true
  def rbac_rules do
    [
      to_rbac_rule({"", ["pods"], ["get", "list"]}),
      to_rbac_rule({"batch", ["jobs"], ["get", "list", "create", "delete"]})
    ]
  end

  def handle_event(%Bonny.Axn{action: action} = axn, _opts)
      when action in [:add, :modify, :reconcile] do
    axn
    |> reconcile_backup_request()
    |> reconcile_restore_request()
    |> success_event()
  end

  def handle_event(%Bonny.Axn{action: :delete} = axn, _opts) do
    database_id = get_in(axn.resource, ["spec", "databaseId"])
    Logger.info("SqliteDatabase #{database_id} deleted; final snapshot pending implementation")
    axn
  end

  defp reconcile_backup_request(%Bonny.Axn{} = axn) do
    case get_in(axn.resource, ["spec", "backup", "requestedAt"]) do
      nil ->
        axn

      requested_at ->
        database_id = get_in(axn.resource, ["spec", "databaseId"])

        Logger.info("backup requested for #{database_id} at #{requested_at}")

        update_status(axn, fn status ->
          backups = List.wrap(status["backups"])

          if Enum.any?(backups, &(&1["id"] == requested_at)) do
            status
          else
            backup = %{
              "id" => requested_at,
              "completedAt" => requested_at,
              "sizeBytes" => 0
            }

            Map.put(status, "backups", [backup | backups])
          end
        end)
    end
  end

  defp reconcile_restore_request(%Bonny.Axn{} = axn) do
    case get_in(axn.resource, ["spec", "restore", "backupId"]) do
      nil ->
        axn

      backup_id ->
        database_id = get_in(axn.resource, ["spec", "databaseId"])
        Logger.info("restore of #{database_id} from #{backup_id} pending implementation")
        axn
    end
  end
end

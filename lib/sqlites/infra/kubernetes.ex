defmodule Sqlites.Infra.Kubernetes do
  @moduledoc """
  Production infra adapter. Kubernetes tracks per-*node* resources only
  (`SqliteNode` CRs, reconciled by the operator) — at the 1M-database
  target, per-database objects would overwhelm etcd, so database
  provisioning needs nothing from k8s: the file is created lazily on
  the owning node's PVC and replicated by the node-level Litestream
  sidecar.

  Backup/restore currently delegate to the same data-plane execution
  path as the Local adapter, storing snapshots under the node's data
  volume. Phase 3 §3 moves the artifact store to S3.
  """

  @behaviour Sqlites.Infra

  alias Sqlites.ControlPlane.Database

  @impl true
  def provision(%Database{}), do: :ok

  @impl true
  def deprovision(%Database{}), do: :ok

  @impl true
  def trigger_backup(%Database{} = database), do: Sqlites.Infra.Local.trigger_backup(database)

  @impl true
  def list_backups(%Database{} = database), do: Sqlites.Infra.Local.list_backups(database)

  @impl true
  def restore(%Database{} = database, backup_id),
    do: Sqlites.Infra.Local.restore(database, backup_id)
end

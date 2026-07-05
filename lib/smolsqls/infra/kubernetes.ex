defmodule Smolsqls.Infra.Kubernetes do
  @moduledoc """
  Production infra adapter. Kubernetes tracks per-*node* resources only
  (`SqliteNode` CRs, reconciled by the operator) — at the 1M-database
  target, per-database objects would overwhelm etcd, so database
  provisioning needs nothing from k8s: the file is created lazily on
  the owning node's PVC and replicated by the node-level Litestream
  sidecar. Backups run through `Smolsqls.Backups` against S3.
  """

  @behaviour Smolsqls.Infra

  alias Smolsqls.ControlPlane.Database

  @impl true
  def provision(%Database{}), do: :ok

  @impl true
  def deprovision(%Database{}), do: :ok
end

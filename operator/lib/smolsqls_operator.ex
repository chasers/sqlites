defmodule SmolsqlsOperator do
  @moduledoc """
  Kubernetes operator owning the durability story for smolsqls: PVC-backed
  database files, Litestream replication, and CRD-driven backup/restore
  requested by the control plane through `SqliteDatabase` resources.
  """
end

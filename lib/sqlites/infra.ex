defmodule Sqlites.Infra do
  @moduledoc """
  Port between the control plane and the infrastructure layer. Since
  the per-node CR redesign, per-database infrastructure needs are nil —
  files are created lazily on the owning node's PVC and replicated by
  the node-level Litestream sidecar — so this port covers only
  provisioning hooks kept for adapters that need them. Backups moved to
  `Sqlites.Backups`, executed by the data plane against the object
  store.
  """

  alias Sqlites.ControlPlane.Database

  @callback provision(Database.t()) :: :ok | {:error, term()}
  @callback deprovision(Database.t()) :: :ok | {:error, term()}

  def provision(database), do: adapter().provision(database)
  def deprovision(database), do: adapter().deprovision(database)

  defp adapter do
    Application.fetch_env!(:sqlites, :infra_adapter)
  end
end

defmodule Sqlites.Infra do
  @moduledoc """
  Port between the control plane and the infrastructure layer that owns
  database file durability. In production the adapter manipulates
  `SqliteDatabase` custom resources that the Kubernetes operator
  reconciles; in dev/test a local adapter implements the same contract
  against the filesystem.
  """

  alias Sqlites.ControlPlane.Database

  @type backup :: %{id: String.t(), created_at: DateTime.t(), size_bytes: non_neg_integer()}

  @callback provision(Database.t()) :: :ok | {:error, term()}
  @callback deprovision(Database.t()) :: :ok | {:error, term()}
  @callback trigger_backup(Database.t()) :: {:ok, backup()} | {:error, term()}
  @callback list_backups(Database.t()) :: {:ok, [backup()]} | {:error, term()}
  @callback restore(Database.t(), backup_id :: String.t()) :: :ok | {:error, term()}

  def provision(database), do: adapter().provision(database)
  def deprovision(database), do: adapter().deprovision(database)
  def trigger_backup(database), do: adapter().trigger_backup(database)
  def list_backups(database), do: adapter().list_backups(database)
  def restore(database, backup_id), do: adapter().restore(database, backup_id)

  defp adapter do
    Application.fetch_env!(:sqlites, :infra_adapter)
  end
end

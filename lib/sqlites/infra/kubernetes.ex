defmodule Sqlites.Infra.Kubernetes do
  @moduledoc """
  Production infra adapter. Every operation is expressed as a change to
  the database's `SqliteDatabase` custom resource; the operator
  reconciles the spec and reports results on the CR's status. The
  control plane never talks to pods, PVCs, or Litestream directly.
  """

  @behaviour Sqlites.Infra

  alias Sqlites.ControlPlane.Database

  @api_version "sqlites.supabase.com/v1alpha1"
  @kind "SqliteDatabase"

  @impl true
  def provision(%Database{} = database) do
    resource = %{
      "apiVersion" => @api_version,
      "kind" => @kind,
      "metadata" => %{
        "name" => cr_name(database),
        "namespace" => namespace(),
        "labels" => %{
          "sqlites.supabase.com/database-id" => database.id,
          "sqlites.supabase.com/tenant-id" => database.tenant_id
        }
      },
      "spec" => %{
        "databaseId" => database.id,
        "tenantId" => database.tenant_id,
        "node" => database.node
      }
    }

    run(K8s.Client.apply(resource, field_manager: "sqlites-control-plane", force: true))
  end

  @impl true
  def deprovision(%Database{} = database) do
    run(K8s.Client.delete(@api_version, @kind, namespace: namespace(), name: cr_name(database)))
  end

  @impl true
  def trigger_backup(%Database{} = database) do
    requested_at = DateTime.to_iso8601(DateTime.utc_now())
    patch = cr_patch(database, %{"spec" => %{"backup" => %{"requestedAt" => requested_at}}})

    case run(K8s.Client.patch(patch)) do
      :ok -> {:ok, %{id: requested_at, created_at: DateTime.utc_now(), size_bytes: 0}}
      error -> error
    end
  end

  @impl true
  def list_backups(%Database{} = database) do
    operation =
      K8s.Client.get(@api_version, @kind, namespace: namespace(), name: cr_name(database))

    with {:ok, cr} <- K8s.Client.run(conn(), operation) do
      backups =
        cr
        |> get_in(["status", "backups"])
        |> List.wrap()
        |> Enum.map(fn backup ->
          {:ok, created_at, _offset} = DateTime.from_iso8601(backup["completedAt"])

          %{
            id: backup["id"],
            created_at: created_at,
            size_bytes: backup["sizeBytes"] || 0
          }
        end)

      {:ok, backups}
    end
  end

  @impl true
  def restore(%Database{} = database, backup_id) do
    patch = cr_patch(database, %{"spec" => %{"restore" => %{"backupId" => backup_id}}})
    run(K8s.Client.patch(patch))
  end

  defp cr_patch(database, changes) do
    Map.merge(
      %{
        "apiVersion" => @api_version,
        "kind" => @kind,
        "metadata" => %{"name" => cr_name(database), "namespace" => namespace()}
      },
      changes
    )
  end

  defp run(operation) do
    case K8s.Client.run(conn(), operation) do
      {:ok, _resource} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp cr_name(%Database{id: id}), do: "db-" <> id

  defp namespace do
    Application.get_env(:sqlites, :k8s_namespace, "sqlites")
  end

  defp conn do
    case :persistent_term.get({__MODULE__, :conn}, nil) do
      nil ->
        {:ok, conn} = K8s.Conn.from_service_account()
        :persistent_term.put({__MODULE__, :conn}, conn)
        conn

      conn ->
        conn
    end
  end
end

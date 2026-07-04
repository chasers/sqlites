defmodule SqlitesOperator.Operator do
  @moduledoc """
  Entry point wiring the SqliteDatabase CRD to its controller.
  """

  use Bonny.Operator, default_watch_namespace: "sqlites"

  step(Bonny.Pluggable.Logger, level: :info)
  step(:delegate_to_controller)
  step(Bonny.Pluggable.ApplyStatus)
  step(Bonny.Pluggable.ApplyDescendants)

  @impl Bonny.Operator
  def controllers(watching_namespace, _opts) do
    [
      %{
        query:
          K8s.Client.watch("sqlites.supabase.com/v1alpha1", "SqliteDatabase",
            namespace: watching_namespace
          ),
        controller: SqlitesOperator.Controller.SqliteDatabaseController
      }
    ]
  end

  @impl Bonny.Operator
  def crds do
    [
      Bonny.API.CRD.new!(
        group: "sqlites.supabase.com",
        scope: :Namespaced,
        names: Bonny.API.CRD.kind_to_names("SqliteDatabase", ["sqldb"]),
        versions: [SqlitesOperator.API.V1Alpha1.SqliteDatabase]
      )
    ]
  end
end

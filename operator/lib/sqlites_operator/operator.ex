defmodule SqlitesOperator.Operator do
  @moduledoc """
  Entry point wiring the SqliteNode CRD to its controller. Sized for
  the 1M-database target: kubernetes tracks per-*node* resources only
  (hundreds of objects); per-database metadata never reaches etcd.
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
          K8s.Client.watch("sqlites.supabase.com/v1alpha1", "SqliteNode",
            namespace: watching_namespace
          ),
        controller: SqlitesOperator.Controller.SqliteNodeController
      }
    ]
  end

  @impl Bonny.Operator
  def crds do
    [
      Bonny.API.CRD.new!(
        group: "sqlites.supabase.com",
        scope: :Namespaced,
        names: Bonny.API.CRD.kind_to_names("SqliteNode", ["sqlnode"]),
        versions: [SqlitesOperator.API.V1Alpha1.SqliteNode]
      )
    ]
  end
end

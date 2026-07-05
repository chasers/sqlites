defmodule SmolsqlsOperator.Operator do
  @moduledoc """
  Entry point wiring the SqliteNode CRD to its controller. Sized for
  the 1M-database target: kubernetes tracks per-*node* resources only
  (hundreds of objects); per-database metadata never reaches etcd.
  """

  use Bonny.Operator, default_watch_namespace: "smolsqls"

  step(Bonny.Pluggable.Logger, level: :info)
  step(:delegate_to_controller)
  step(Bonny.Pluggable.ApplyStatus)
  step(Bonny.Pluggable.ApplyDescendants)

  @impl Bonny.Operator
  def controllers(watching_namespace, _opts) do
    [
      %{
        query:
          K8s.Client.watch("smolsqls.supabase.com/v1alpha1", "SqliteNode",
            namespace: watching_namespace
          ),
        controller: SmolsqlsOperator.Controller.SqliteNodeController
      }
    ]
  end

  @impl Bonny.Operator
  def crds do
    [
      Bonny.API.CRD.new!(
        group: "smolsqls.supabase.com",
        scope: :Namespaced,
        names: Bonny.API.CRD.kind_to_names("SqliteNode", ["sqlnode"]),
        versions: [SmolsqlsOperator.API.V1Alpha1.SqliteNode]
      )
    ]
  end
end

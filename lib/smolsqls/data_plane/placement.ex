defmodule Smolsqls.DataPlane.Placement do
  @moduledoc """
  Chooses which cluster node should own a new database. V1 picks the
  node running the fewest database servers; in a k8s deployment the
  operator further constrains placement via volume affinity.
  """

  alias Smolsqls.DataPlane.Registry

  @spec pick_node() :: node()
  def pick_node do
    [Node.self() | Node.list()]
    |> Enum.min_by(&database_count/1)
  end

  defp database_count(node) do
    :syn.registry_count(Registry.scope(), node)
  end
end

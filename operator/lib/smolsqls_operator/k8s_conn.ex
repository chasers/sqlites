defmodule SmolsqlsOperator.K8sConn do
  @moduledoc """
  Builds the `%K8s.Conn{}` for the current environment: kubeconfig in
  dev, in-cluster service account in prod.
  """

  @spec get!(atom()) :: K8s.Conn.t()
  def get!(:prod) do
    {:ok, conn} = K8s.Conn.from_service_account()
    conn
  end

  def get!(_env) do
    {:ok, conn} = K8s.Conn.from_file("~/.kube/config")
    conn
  end
end

defmodule SqlitesOperator.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: SqlitesOperator.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  defp children do
    if Application.get_env(:sqlites_operator, :start_operator, false) do
      [{SqlitesOperator.Operator, conn: SqlitesOperator.K8sConn.get!(operator_env())}]
    else
      []
    end
  end

  defp operator_env do
    Application.get_env(:sqlites_operator, :env, :dev)
  end
end

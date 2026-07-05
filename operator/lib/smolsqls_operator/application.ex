defmodule SmolsqlsOperator.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: SmolsqlsOperator.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  defp children do
    if Application.get_env(:smolsqls_operator, :start_operator, false) do
      [{SmolsqlsOperator.Operator, conn: SmolsqlsOperator.K8sConn.get!(operator_env())}]
    else
      []
    end
  end

  defp operator_env do
    Application.get_env(:smolsqls_operator, :env, :dev)
  end
end

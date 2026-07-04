defmodule SqlitesOperator.MixProject do
  use Mix.Project

  def project do
    [
      app: :sqlites_operator,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SqlitesOperator.Application, []}
    ]
  end

  defp deps do
    [
      {:bonny, "~> 1.4"},
      {:postgrex, "~> 0.19"}
    ]
  end
end

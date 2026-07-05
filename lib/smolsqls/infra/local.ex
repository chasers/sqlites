defmodule Smolsqls.Infra.Local do
  @moduledoc """
  Dev/test infra adapter — per-database provisioning needs nothing
  locally; files are created lazily by the data plane.
  """

  @behaviour Smolsqls.Infra

  alias Smolsqls.ControlPlane.Database

  @impl true
  def provision(%Database{}), do: :ok

  @impl true
  def deprovision(%Database{}), do: :ok
end

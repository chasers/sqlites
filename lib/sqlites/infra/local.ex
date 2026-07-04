defmodule Sqlites.Infra.Local do
  @moduledoc """
  Dev/test infra adapter — per-database provisioning needs nothing
  locally; files are created lazily by the data plane.
  """

  @behaviour Sqlites.Infra

  alias Sqlites.ControlPlane.Database

  @impl true
  def provision(%Database{}), do: :ok

  @impl true
  def deprovision(%Database{}), do: :ok
end

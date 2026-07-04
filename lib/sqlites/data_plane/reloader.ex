defmodule Sqlites.DataPlane.Reloader do
  @moduledoc """
  On node boot, restarts the `Database.Server` for every database the
  control plane has placed on this node, so a node restart brings its
  databases back online without operator intervention.
  """

  use Task, restart: :transient

  import Ecto.Query

  require Logger

  alias Sqlites.ControlPlane.Database
  alias Sqlites.DataPlane.Supervisor
  alias Sqlites.Repo

  def start_link(_opts) do
    Task.start_link(__MODULE__, :run, [])
  end

  def run do
    if Application.get_env(:sqlites, :reload_databases_on_boot, true) do
      reload()
    end
  end

  defp reload do
    node_name = to_string(Node.self())

    Database
    |> where([d], d.node == ^node_name and d.status == :active)
    |> Repo.all()
    |> Enum.each(fn database ->
      case Supervisor.start_database(database.id, database.file_path) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          Logger.error("failed to restart database #{database.id}: #{inspect(reason)}")
      end
    end)
  end
end

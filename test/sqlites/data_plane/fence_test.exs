defmodule Sqlites.DataPlane.FenceTest do
  use Sqlites.DataCase

  import Sqlites.Fixtures

  alias Sqlites.ControlPlane
  alias Sqlites.DataPlane.Fence
  alias Sqlites.DataPlane.Registry
  alias Sqlites.Repo

  test "stops a misplaced server only after two consecutive sightings" do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)
    pid = Registry.whereis(database.id)
    assert is_pid(pid)

    {:ok, _} =
      database
      |> ControlPlane.Database.placement_changeset(%{status: :active, node: "sqlites@elsewhere"})
      |> Repo.update()

    flagged = Fence.sweep()
    assert MapSet.member?(flagged, database.id)
    assert Process.alive?(pid)

    ref = Process.monitor(pid)
    Fence.sweep(flagged)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
  end

  test "leaves correctly placed servers alone" do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)
    pid = Registry.whereis(database.id)

    flagged = Fence.sweep()
    refute MapSet.member?(flagged, database.id)

    Fence.sweep(flagged)
    assert Process.alive?(pid)
  end

  test "ignores servers without a placement row" do
    database_id = "fence-#{System.unique_integer([:positive])}"

    data_dir = Application.fetch_env!(:sqlites, :data_dir)
    file_path = Path.join([data_dir, "fence-test", database_id <> ".db"])
    on_exit(fn -> Sqlites.DataPlane.delete_local_files(file_path) end)

    {:ok, pid} = Sqlites.DataPlane.Supervisor.start_database(database_id, file_path)
    on_exit(fn -> Sqlites.DataPlane.Supervisor.stop_database(database_id) end)

    flagged = Fence.sweep()
    refute MapSet.member?(flagged, database_id)
    assert Process.alive?(pid)
  end
end

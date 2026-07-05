defmodule Smolsqls.DrainTest do
  use Smolsqls.DataCase

  import Smolsqls.Fixtures

  alias Smolsqls.ControlPlane
  alias Smolsqls.DataPlane
  alias Smolsqls.Drain
  alias Smolsqls.Drain.Request
  alias Smolsqls.Repo

  test "refuses to drain the only node" do
    assert {:error, :no_survivors} = Drain.drain(to_string(Node.self()))
  end

  test "reassigns cold shipped databases without touching their files" do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)

    {:ok, _} = DataPlane.query(database.id, "CREATE TABLE t (v TEXT)")
    assert :ok = DataPlane.idle_stop_database(database)

    {:ok, _} =
      database
      |> ControlPlane.Database.placement_changeset(%{status: :active, node: "smolsqls@gone"})
      |> Repo.update()

    assert {:ok, %{reassigned: 1, handed_off: 0}} = Drain.drain("smolsqls@gone")
    assert ControlPlane.get_database(database.id).node == to_string(Node.self())
    assert File.exists?(database.file_path)
  end

  test "worker claims a pending request, drains, and reports completion" do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)

    {:ok, _} = DataPlane.query(database.id, "CREATE TABLE t (v TEXT)")
    assert :ok = DataPlane.idle_stop_database(database)

    {:ok, _} =
      database
      |> ControlPlane.Database.placement_changeset(%{status: :active, node: "smolsqls@gone"})
      |> Repo.update()

    Repo.insert!(%Request{node: "smolsqls@gone", requested_at: DateTime.utc_now()})

    assert :ok = Smolsqls.Drain.Worker.poll()

    request = Repo.get!(Request, "smolsqls@gone")
    assert request.started_by == to_string(Node.self())
    assert request.completed_at
    assert request.reassigned == 1
    assert request.error == nil

    assert ControlPlane.get_database(database.id).node == to_string(Node.self())

    assert :ok = Smolsqls.Drain.Worker.poll()
  end

  test "worker records a failed drain on the request row" do
    Repo.insert!(%Request{node: to_string(Node.self()), requested_at: DateTime.utc_now()})

    assert :ok = Smolsqls.Drain.Worker.poll()

    request = Repo.get!(Request, to_string(Node.self()))
    assert request.completed_at
    assert request.error =~ "no_survivors"
  end

  test "worker evacuates a dead node's placement rows" do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)

    {:ok, _} =
      database
      |> ControlPlane.Database.placement_changeset(%{status: :active, node: "smolsqls@dead"})
      |> Repo.update()

    Repo.insert!(%Request{
      node: "smolsqls@dead",
      kind: "evacuate",
      requested_at: DateTime.utc_now()
    })

    assert :ok = Smolsqls.Drain.Worker.poll()

    request = Repo.get!(Request, "smolsqls@dead")
    assert request.completed_at
    assert request.reassigned == 1
    assert request.error == nil

    assert ControlPlane.get_database(database.id).node == to_string(Node.self())
  end

  test "worker cancels an evacuation when the node is connected" do
    Repo.insert!(%Request{
      node: to_string(Node.self()),
      kind: "evacuate",
      requested_at: DateTime.utc_now()
    })

    assert :ok = Smolsqls.Drain.Worker.poll()

    request = Repo.get!(Request, to_string(Node.self()))
    assert request.completed_at
    assert request.error =~ "reconnected"
  end
end

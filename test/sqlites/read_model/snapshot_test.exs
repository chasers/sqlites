defmodule Sqlites.ReadModel.SnapshotTest do
  use Sqlites.DataCase

  import Sqlites.Fixtures

  alias Sqlites.ReadModel
  alias Sqlites.ReadModel.Snapshot

  setup do
    start_supervised!({ReadModel, snapshot: false})
    :ok
  end

  test "loads tenants and databases into the read model via COPY" do
    tenant = tenant_fixture()
    database = database_fixture(tenant)
    placed = placed_database_fixture(tenant)

    assert :ok = Snapshot.load()

    loaded_tenant = ReadModel.get_tenant_by_api_key(tenant.api_key)
    assert loaded_tenant.id == tenant.id
    assert loaded_tenant.slug == tenant.slug

    loaded = ReadModel.get_database(database.id)
    assert loaded.tenant_id == tenant.id
    assert loaded.status == :pending
    assert loaded.node == nil
    assert ReadModel.get_database_by_auth_token(database.auth_token).id == database.id

    loaded_placed = ReadModel.get_database(placed.id)
    assert loaded_placed.status == :active
    assert loaded_placed.node == to_string(Node.self())
    assert loaded_placed.file_path == placed.file_path
  end

  test "authenticate paths serve from the read model once ready" do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)

    Snapshot.load()
    ReadModel.mark_ready()
    on_exit(&ReadModel.mark_not_ready/0)

    assert {:ok, %{id: tenant_id}} = Sqlites.ControlPlane.authenticate_tenant(tenant.api_key)
    assert tenant_id == tenant.id

    assert {:ok, %{id: db_id}} =
             Sqlites.ControlPlane.authenticate_database(database.id, database.auth_token)

    assert db_id == database.id

    assert {:error, :unauthorized} =
             Sqlites.ControlPlane.authenticate_database(database.id, "wrong")
  end
end

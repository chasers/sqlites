defmodule SqlitesTest do
  use Sqlites.DataCase

  import Sqlites.Fixtures

  alias Sqlites.ControlPlane
  alias Sqlites.DataPlane

  test "create_database/2 places and provisions" do
    tenant = tenant_fixture()

    assert {:ok, database} = Sqlites.create_database(tenant, %{"name" => "orchestrated"})
    on_exit(fn -> File.rm(database.file_path) end)

    assert database.status == :active
    assert {:ok, _} = DataPlane.query(database.id, "SELECT 1")

    DataPlane.Supervisor.stop_database(database.id)
  end

  test "remove_database/1 tears down process, file, and record" do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)

    assert {:ok, _} = Sqlites.remove_database(database)
    refute File.exists?(database.file_path)
    assert ControlPlane.get_database(database.id) == nil
    assert DataPlane.Registry.whereis(database.id) == :undefined
  end

  test "delete_tenant/1 drains every database before deleting the tenant" do
    tenant = tenant_fixture()
    database_a = placed_database_fixture(tenant)
    database_b = placed_database_fixture(tenant)

    assert {:ok, _} = Sqlites.delete_tenant(tenant)

    for database <- [database_a, database_b] do
      refute File.exists?(database.file_path)
      assert DataPlane.Registry.whereis(database.id) == :undefined
    end

    assert ControlPlane.get_tenant(tenant.id) == nil
  end
end

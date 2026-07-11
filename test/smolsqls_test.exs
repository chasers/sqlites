defmodule SmolsqlsTest do
  use Smolsqls.DataCase

  import Smolsqls.Fixtures

  alias Smolsqls.ControlPlane
  alias Smolsqls.DataPlane

  test "create_database/2 places and provisions" do
    tenant = tenant_fixture()

    assert {:ok, database} = Smolsqls.create_database(tenant, %{"name" => "orchestrated"})
    on_exit(fn -> File.rm(database.file_path) end)

    assert database.status == :active
    assert {:ok, _} = DataPlane.query(database.id, "SELECT 1")

    DataPlane.Supervisor.stop_database(database.id)
  end

  test "remove_database/1 tears down process, file, and record" do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)

    assert {:ok, _} = Smolsqls.remove_database(database)
    refute File.exists?(database.file_path)
    assert ControlPlane.get_database(database.id) == nil
    assert DataPlane.Registry.whereis(database.id) == :undefined
  end

  test "delete_tenant/1 refuses while the tenant has databases" do
    tenant = tenant_fixture()
    database_a = placed_database_fixture(tenant)
    database_b = placed_database_fixture(tenant)

    assert {:error, :tenant_has_databases} = Smolsqls.delete_tenant(tenant)
    assert ControlPlane.get_tenant(tenant.id) != nil

    assert {:ok, _} = Smolsqls.remove_database(database_a)
    assert {:error, :tenant_has_databases} = Smolsqls.delete_tenant(tenant)

    assert {:ok, _} = Smolsqls.remove_database(database_b)
    assert {:ok, _} = Smolsqls.delete_tenant(tenant)
    assert ControlPlane.get_tenant(tenant.id) == nil
  end

  defp branch_of(tenant) do
    source = placed_database_fixture(tenant)
    {:ok, _} = DataPlane.query(source.id, "CREATE TABLE t (v TEXT)")
    :ok = DataPlane.idle_stop_database(source)
    source = ControlPlane.get_database(source.id)

    {:ok, branch} =
      Smolsqls.branch_database(source, %{"name" => "branch-#{System.unique_integer([:positive])}"})

    on_exit(fn ->
      DataPlane.Supervisor.stop_database(branch.id)
      if branch.file_path, do: DataPlane.delete_local_files(branch.file_path)
    end)

    {source, branch}
  end

  test "remove_database/1 is blocked while the database has branches" do
    tenant = tenant_fixture()
    {source, branch} = branch_of(tenant)

    assert {:error, :has_branches} = Smolsqls.remove_database(source)
    assert ControlPlane.get_database(source.id) != nil

    assert {:ok, _} = Smolsqls.remove_database(branch)
    assert {:ok, _} = Smolsqls.remove_database(source)
    assert ControlPlane.get_database(source.id) == nil
  end

  test "delete_tenant/1 refuses even when the only database left is a branch" do
    tenant = tenant_fixture()
    {source, branch} = branch_of(tenant)

    assert {:error, :tenant_has_databases} = Smolsqls.delete_tenant(tenant)

    assert {:ok, _} = Smolsqls.remove_database(branch)
    assert {:error, :tenant_has_databases} = Smolsqls.delete_tenant(tenant)

    assert {:ok, _} = Smolsqls.remove_database(source)
    assert {:ok, _} = Smolsqls.delete_tenant(tenant)
    assert ControlPlane.get_tenant(tenant.id) == nil
  end
end

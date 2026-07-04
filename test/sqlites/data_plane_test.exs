defmodule Sqlites.DataPlaneTest do
  use Sqlites.DataCase

  import Sqlites.Fixtures

  alias Sqlites.ControlPlane
  alias Sqlites.DataPlane

  test "place_database/1 starts a server on this node and marks placement" do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)

    assert database.status == :active
    assert database.node == to_string(Node.self())
    assert File.exists?(database.file_path)
    assert {:ok, node} = DataPlane.owner_node(database.id)
    assert node == Node.self()
  end

  test "query/3 routes to the placed database" do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)

    assert {:ok, _} = DataPlane.query(database.id, "CREATE TABLE t (v TEXT)")
    assert {:ok, _} = DataPlane.query(database.id, "INSERT INTO t VALUES (?)", ["hi"])
    assert {:ok, %{rows: [["hi"]]}} = DataPlane.query(database.id, "SELECT v FROM t")
  end

  test "query/3 returns an error for an unplaced database" do
    assert {:error, :database_not_running} = DataPlane.query("no-such-db", "SELECT 1")
  end

  test "remove_database/1 stops the server, deletes the file and the record" do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)
    file_path = database.file_path

    assert {:ok, _} = DataPlane.remove_database(database)
    refute File.exists?(file_path)
    assert ControlPlane.get_database(database.id) == nil
    assert {:error, :not_found} = DataPlane.owner_node(database.id)
  end
end

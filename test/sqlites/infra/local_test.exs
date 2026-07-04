defmodule Sqlites.Infra.LocalTest do
  use Sqlites.DataCase

  import Sqlites.Fixtures

  alias Sqlites.DataPlane
  alias Sqlites.Infra.Local

  setup do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)

    {:ok, _} = DataPlane.query(database.id, "CREATE TABLE t (v TEXT)")
    {:ok, _} = DataPlane.query(database.id, "INSERT INTO t VALUES ('original')")

    on_exit(fn -> Local.deprovision(database) end)

    %{database: database}
  end

  test "trigger_backup/1 creates a listed backup", %{database: database} do
    assert {:ok, backup} = Local.trigger_backup(database)
    assert backup.size_bytes > 0

    assert {:ok, [listed]} = Local.list_backups(database)
    assert listed.id == backup.id
  end

  test "restore/2 brings back backed-up data", %{database: database} do
    {:ok, backup} = Local.trigger_backup(database)
    {:ok, _} = DataPlane.query(database.id, "DELETE FROM t")
    assert {:ok, %{rows: [[0]]}} = DataPlane.query(database.id, "SELECT count(*) FROM t")

    assert :ok = Local.restore(database, backup.id)
    assert {:ok, %{rows: [["original"]]}} = DataPlane.query(database.id, "SELECT v FROM t")
  end

  test "restore/2 with an unknown backup id fails", %{database: database} do
    assert {:error, :backup_not_found} = Local.restore(database, "nope")
  end

  test "list_backups/1 is empty for a fresh database", %{database: database} do
    assert {:ok, []} = Local.list_backups(database)
  end
end

defmodule Smolsqls.BackupsTest do
  use Smolsqls.DataCase

  import Smolsqls.Fixtures

  alias Smolsqls.Backups
  alias Smolsqls.DataPlane

  setup do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)

    {:ok, _} = DataPlane.query(database.id, "CREATE TABLE t (v TEXT)")
    {:ok, _} = DataPlane.query(database.id, "INSERT INTO t VALUES ('original')")

    on_exit(fn -> Backups.delete_all(database) end)

    %{database: database}
  end

  test "trigger/1 snapshots through the writer and records the artifact", %{database: database} do
    assert {:ok, backup} = Backups.trigger(database)
    assert backup.size_bytes > 0
    assert backup.object_key =~ "backups/#{database.tenant_id}/#{database.id}/"

    assert [listed] = Backups.list(database)
    assert listed.id == backup.id
  end

  test "restore/2 round-trips data through the object store", %{database: database} do
    {:ok, backup} = Backups.trigger(database)
    {:ok, _} = DataPlane.query(database.id, "DELETE FROM t")
    assert {:ok, %{rows: [[0]]}} = DataPlane.query(database.id, "SELECT count(*) FROM t")

    assert :ok = Backups.restore(database, backup.id)
    assert {:ok, %{rows: [["original"]]}} = DataPlane.query(database.id, "SELECT v FROM t")
  end

  test "restore/2 with an unknown backup id fails", %{database: database} do
    assert {:error, :backup_not_found} = Backups.restore(database, "nope")
    assert {:error, :backup_not_found} = Backups.restore(database, Ecto.UUID.generate())
  end

  test "delete_all/1 removes rows and artifacts", %{database: database} do
    {:ok, backup} = Backups.trigger(database)
    assert :ok = Backups.delete_all(database)

    assert Backups.list(database) == []

    assert {:error, :not_found} =
             Smolsqls.ObjectStore.fetch_to_file(backup.object_key, "/tmp/nope.db")
  end

  test "list/1 is empty for a fresh database", %{database: database} do
    assert Backups.list(database) == []
  end
end

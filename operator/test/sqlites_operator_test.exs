defmodule SqlitesOperatorTest do
  use ExUnit.Case

  test "crds/0 defines the SqliteDatabase CRD" do
    assert [crd] = SqlitesOperator.Operator.crds()
    assert crd.group == "sqlites.supabase.com"
    assert crd.names.kind == "SqliteDatabase"

    manifest = Bonny.API.CRD.to_manifest(crd)
    assert manifest.metadata.name == "sqlitedatabases.sqlites.supabase.com"
  end

  test "controllers/2 watches SqliteDatabase resources" do
    assert [%{controller: SqlitesOperator.Controller.SqliteDatabaseController}] =
             SqlitesOperator.Operator.controllers("sqlites", [])
  end
end

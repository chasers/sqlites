defmodule SqlitesOperatorTest do
  use ExUnit.Case

  test "crds/0 defines the SqliteNode CRD" do
    assert [crd] = SqlitesOperator.Operator.crds()
    assert crd.group == "sqlites.supabase.com"
    assert crd.names.kind == "SqliteNode"

    manifest = Bonny.API.CRD.to_manifest(crd)
    assert manifest.metadata.name == "sqlitenodes.sqlites.supabase.com"
  end

  test "controllers/2 watches SqliteNode resources" do
    assert [%{controller: SqlitesOperator.Controller.SqliteNodeController}] =
             SqlitesOperator.Operator.controllers("sqlites", [])
  end
end

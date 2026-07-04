defmodule Sqlites.ReadModelTest do
  use ExUnit.Case, async: false

  alias Sqlites.ControlPlane.{Database, Tenant}
  alias Sqlites.ReadModel

  setup do
    start_supervised!({ReadModel, snapshot: false})
    :ok
  end

  defp database(overrides \\ %{}) do
    struct!(
      %Database{
        id: Ecto.UUID.generate(),
        tenant_id: Ecto.UUID.generate(),
        name: "db",
        status: :active,
        auth_token: "token-#{System.unique_integer([:positive])}"
      },
      overrides
    )
  end

  test "stores and looks up databases by id and token" do
    db = database()
    assert :ok = ReadModel.put_database(db)

    assert %Database{id: id} = ReadModel.get_database(db.id)
    assert id == db.id
    assert %Database{} = ReadModel.get_database_by_auth_token(db.auth_token)

    assert ReadModel.get_database("missing") == nil
    assert ReadModel.get_database_by_auth_token("missing") == nil
  end

  test "token index follows token rotation" do
    db = database()
    ReadModel.put_database(db)

    rotated = %{db | auth_token: "rotated-token"}
    ReadModel.put_database(rotated)

    assert ReadModel.get_database_by_auth_token("rotated-token").id == db.id
    assert ReadModel.get_database_by_auth_token(db.auth_token) == nil
  end

  test "delete removes both entries" do
    db = database()
    ReadModel.put_database(db)
    assert :ok = ReadModel.delete_database(db.id)

    assert ReadModel.get_database(db.id) == nil
    assert ReadModel.get_database_by_auth_token(db.auth_token) == nil
  end

  test "tenant storage mirrors the same shape" do
    tenant = %Tenant{id: Ecto.UUID.generate(), name: "T", slug: "t", api_key: "sk_x"}
    ReadModel.put_tenant(tenant)

    assert %Tenant{} = ReadModel.get_tenant_by_api_key("sk_x")
    ReadModel.delete_tenant(tenant.id)
    assert ReadModel.get_tenant_by_api_key("sk_x") == nil
  end

  test "truncate clears a table and its index" do
    db = database()
    ReadModel.put_database(db)
    ReadModel.truncate(:databases)

    assert ReadModel.get_database(db.id) == nil
    assert ReadModel.get_database_by_auth_token(db.auth_token) == nil
  end
end

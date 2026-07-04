defmodule SqlitesWeb.Api.ApiFlowTest do
  use SqlitesWeb.ConnCase, async: false

  import Sqlites.Fixtures

  alias Sqlites.DataPlane

  defp authed(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  defp cleanup_database(body) do
    %{"data" => %{"id" => id}} = body

    on_exit(fn ->
      case Sqlites.ControlPlane.get_database(id) do
        nil -> :ok
        database -> DataPlane.remove_database(database)
      end
    end)

    body
  end

  describe "GET /v1" do
    test "returns a machine-readable endpoint index", %{conn: conn} do
      body = conn |> get(~p"/v1") |> json_response(200)
      assert body["service"] == "sqlites"
      assert is_list(body["endpoints"])
    end
  end

  describe "POST /v1/tenants" do
    test "signs up a tenant and returns the api key once", %{conn: conn} do
      body =
        conn
        |> post(~p"/v1/tenants", %{"name" => "Agent Org", "slug" => unique_slug()})
        |> json_response(201)

      assert "sk_" <> _ = body["data"]["api_key"]
    end

    test "returns validation errors", %{conn: conn} do
      body =
        conn
        |> post(~p"/v1/tenants", %{"name" => "Agent Org", "slug" => "BAD SLUG"})
        |> json_response(422)

      assert body["error"]["code"] == "validation_failed"
    end
  end

  describe "tenant self-service" do
    test "get, update, delete with the api key", %{conn: conn} do
      tenant = tenant_fixture()

      body = conn |> authed(tenant.api_key) |> get(~p"/v1/tenant") |> json_response(200)
      assert body["data"]["id"] == tenant.id
      refute Map.has_key?(body["data"], "api_key")

      body =
        conn
        |> authed(tenant.api_key)
        |> patch(~p"/v1/tenant", %{"name" => "Renamed"})
        |> json_response(200)

      assert body["data"]["name"] == "Renamed"

      conn |> authed(tenant.api_key) |> delete(~p"/v1/tenant") |> response(204)
      assert conn |> authed(tenant.api_key) |> get(~p"/v1/tenant") |> json_response(401)
    end

    test "rejects a missing api key", %{conn: conn} do
      assert conn |> get(~p"/v1/tenant") |> json_response(401)
    end
  end

  describe "database lifecycle" do
    test "create returns connection info; query works with the db token", %{conn: conn} do
      tenant = tenant_fixture()

      body =
        conn
        |> authed(tenant.api_key)
        |> post(~p"/v1/databases", %{"name" => "task-db"})
        |> json_response(201)
        |> cleanup_database()

      %{"data" => data} = body
      assert data["status"] == "active"
      assert data["connections"]["libsql"] =~ "libsql://"
      db_id = data["id"]
      db_token = data["auth_token"]

      assert conn
             |> authed(db_token)
             |> post(~p"/v1/databases/#{db_id}/query", %{"sql" => "CREATE TABLE t (v TEXT)"})
             |> json_response(200)

      result =
        conn
        |> authed(db_token)
        |> post(~p"/v1/databases/#{db_id}/query", %{
          "sql" => "INSERT INTO t VALUES (?)",
          "args" => ["hello"]
        })
        |> json_response(200)

      assert result["data"]["num_changes"] == 1

      result =
        conn
        |> authed(db_token)
        |> post(~p"/v1/databases/#{db_id}/query", %{"sql" => "SELECT v FROM t"})
        |> json_response(200)

      assert result["data"]["rows"] == [["hello"]]
    end

    test "query rejects the wrong token and bad SQL", %{conn: conn} do
      tenant = tenant_fixture()
      database = placed_database_fixture(tenant)

      assert conn
             |> authed("wrong")
             |> post(~p"/v1/databases/#{database.id}/query", %{"sql" => "SELECT 1"})
             |> json_response(401)

      body =
        conn
        |> authed(database.auth_token)
        |> post(~p"/v1/databases/#{database.id}/query", %{"sql" => "SELEC nope"})
        |> json_response(400)

      assert body["error"]["code"] == "query_error"
    end

    test "list and delete", %{conn: conn} do
      tenant = tenant_fixture()
      database = placed_database_fixture(tenant)

      body = conn |> authed(tenant.api_key) |> get(~p"/v1/databases") |> json_response(200)
      assert [%{"id" => id}] = body["data"]
      assert id == database.id

      conn |> authed(tenant.api_key) |> delete(~p"/v1/databases/#{database.id}") |> response(204)

      body = conn |> authed(tenant.api_key) |> get(~p"/v1/databases") |> json_response(200)
      assert body["data"] == []
    end

    test "cannot touch another tenant's database", %{conn: conn} do
      tenant = tenant_fixture()
      other_tenant = tenant_fixture()
      database = placed_database_fixture(tenant)

      assert conn
             |> authed(other_tenant.api_key)
             |> get(~p"/v1/databases/#{database.id}")
             |> json_response(404)
    end
  end

  describe "backups over the API" do
    test "trigger, list, restore", %{conn: conn} do
      tenant = tenant_fixture()
      database = placed_database_fixture(tenant)
      {:ok, _} = DataPlane.query(database.id, "CREATE TABLE t (v TEXT)")
      {:ok, _} = DataPlane.query(database.id, "INSERT INTO t VALUES ('keep')")
      on_exit(fn -> Sqlites.Backups.delete_all(database) end)

      body =
        conn
        |> authed(tenant.api_key)
        |> post(~p"/v1/databases/#{database.id}/backups")
        |> json_response(201)

      backup_id = body["data"]["id"]

      body =
        conn
        |> authed(tenant.api_key)
        |> get(~p"/v1/databases/#{database.id}/backups")
        |> json_response(200)

      assert [%{"id" => ^backup_id}] = body["data"]

      {:ok, _} = DataPlane.query(database.id, "DELETE FROM t")

      conn
      |> authed(tenant.api_key)
      |> post(~p"/v1/databases/#{database.id}/restore", %{"backup_id" => backup_id})
      |> response(202)

      assert {:ok, %{rows: [["keep"]]}} = DataPlane.query(database.id, "SELECT v FROM t")
    end
  end
end

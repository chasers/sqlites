defmodule SqlitesWeb.MetricsControllerTest do
  use SqlitesWeb.ConnCase, async: false

  import Sqlites.Fixtures

  test "GET /metrics exposes data-plane metrics in Prometheus format", %{conn: conn} do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)
    {:ok, _} = Sqlites.DataPlane.query(database.id, "SELECT 1")

    body = conn |> get(~p"/metrics") |> response(200)

    assert body =~ "sqlites_query_count"
    assert body =~ ~s(result="ok")
  end
end

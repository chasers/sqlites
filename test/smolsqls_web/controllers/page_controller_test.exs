defmodule SmolsqlsWeb.PageControllerTest do
  use SmolsqlsWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Sign in with your API key"
    assert response =~ "Create a tenant"
  end
end

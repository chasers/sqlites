defmodule SmolsqlsWeb.CorsPlugTest do
  use SmolsqlsWeb.ConnCase, async: true

  test "answers the CORS preflight for an API path", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://libsqlstudio.com")
      |> put_req_header("access-control-request-method", "POST")
      |> put_req_header("access-control-request-headers", "authorization")
      |> dispatch(@endpoint, "options", "/v3/pipeline")

    assert conn.status == 204
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    assert get_resp_header(conn, "access-control-allow-headers") == ["authorization"]
    assert "POST" in String.split(hd(get_resp_header(conn, "access-control-allow-methods")), ", ")
  end

  test "stamps Access-Control-Allow-Origin on API responses", %{conn: conn} do
    conn = get(conn, "/v3")

    assert conn.status == 200
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
  end

  test "GET /v2 and /v3 version probes return 200", %{conn: conn} do
    assert get(conn, "/v2").status == 200
    assert get(build_conn(), "/v3").status == 200
  end

  test "does not add CORS headers to browser (session) routes", %{conn: conn} do
    conn = get(conn, "/")

    assert get_resp_header(conn, "access-control-allow-origin") == []
  end
end

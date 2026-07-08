defmodule SmolsqlsWeb.CorsPlug do
  @moduledoc """
  Cross-origin and content-type compatibility for the token-authenticated
  HTTP API (`/v1`, `/v2`, `/v3`), so browser-based libSQL clients — e.g.
  [LibSQL Studio](https://libsqlstudio.com) — and plain `fetch` can reach
  it.

  These endpoints authenticate by bearer token, never a session cookie,
  so an open `Access-Control-Allow-Origin: *` exposes no ambient
  credentials: a hostile origin still has no token. The session-cookie
  browser routes live under `/` and are deliberately out of scope.

  Two behaviors, both of which must run before `Plug.Parsers`:

    * **CORS** — answers the `OPTIONS` preflight directly (`204`) and
      stamps `Access-Control-*` on every API response.
    * **Content type** — browsers send `fetch` bodies as
      `text/plain;charset=UTF-8`; the Hrana pipeline and query endpoints
      only speak JSON, so a `text/plain` body on these paths is re-typed
      to `application/json` so `Plug.Parsers` decodes it.
  """

  import Plug.Conn

  @api_prefixes ~w(v1 v2 v3)

  def init(opts), do: opts

  def call(conn, _opts) do
    if api_request?(conn) do
      conn
      |> normalize_content_type()
      |> handle_cors()
    else
      conn
    end
  end

  defp api_request?(%{path_info: [segment | _]}), do: segment in @api_prefixes
  defp api_request?(_conn), do: false

  defp handle_cors(%{method: "OPTIONS"} = conn) do
    conn
    |> put_cors_headers()
    |> put_resp_header("access-control-max-age", "86400")
    |> send_resp(:no_content, "")
    |> halt()
  end

  defp handle_cors(conn), do: put_cors_headers(conn)

  defp put_cors_headers(conn) do
    allow_headers =
      case get_req_header(conn, "access-control-request-headers") do
        [requested | _] -> requested
        [] -> "authorization, content-type"
      end

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> put_resp_header("access-control-allow-headers", allow_headers)
    |> put_resp_header("vary", "origin")
  end

  defp normalize_content_type(conn) do
    case get_req_header(conn, "content-type") do
      [type | _] ->
        if String.starts_with?(type, "text/plain") do
          put_req_header(conn, "content-type", "application/json")
        else
          conn
        end

      [] ->
        conn
    end
  end
end

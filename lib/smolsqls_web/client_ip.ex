defmodule SmolsqlsWeb.ClientIP do
  @moduledoc """
  Best-effort client IP for a connection: the first `x-forwarded-for`
  hop when present, else the peer address. Used to rate-limit signups.

  There is no proxy-aware `RemoteIp` plug yet; behind a load balancer
  that does not set `x-forwarded-for` this falls back to the peer, which
  may be the proxy. Revisit if deployed behind such a proxy.
  """

  @spec get(Plug.Conn.t()) :: String.t()
  def get(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded |> String.split(",") |> List.first() |> String.trim()

      [] ->
        conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end

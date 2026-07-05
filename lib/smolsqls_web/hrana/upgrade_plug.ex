defmodule SmolsqlsWeb.Hrana.UpgradePlug do
  @moduledoc """
  Intercepts WebSocket upgrade requests carrying a Hrana subprotocol —
  what a libSQL client sends after translating `libsql://host` to
  `wss://host` — and hands them to `SmolsqlsWeb.Hrana.Socket`. All other
  requests fall through to the router.
  """

  import Plug.Conn

  @supported_subprotocols ["hrana2", "hrana1"]

  def init(opts), do: opts

  def call(conn, _opts) do
    if websocket_upgrade?(conn) do
      case negotiate_subprotocol(conn) do
        {:ok, conn} ->
          conn
          |> WebSockAdapter.upgrade(SmolsqlsWeb.Hrana.Socket, [], timeout: :timer.minutes(10))
          |> halt()

        :no_hrana ->
          conn
      end
    else
      conn
    end
  end

  defp websocket_upgrade?(conn) do
    conn.method == "GET" and
      Enum.any?(get_req_header(conn, "upgrade"), &(String.downcase(&1) == "websocket"))
  end

  defp negotiate_subprotocol(conn) do
    requested =
      conn
      |> get_req_header("sec-websocket-protocol")
      |> Enum.flat_map(&String.split(&1, ~r/\s*,\s*/, trim: true))

    case Enum.find(@supported_subprotocols, &(&1 in requested)) do
      nil -> :no_hrana
      subprotocol -> {:ok, put_resp_header(conn, "sec-websocket-protocol", subprotocol)}
    end
  end
end

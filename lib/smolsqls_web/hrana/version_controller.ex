defmodule SmolsqlsWeb.Hrana.VersionController do
  @moduledoc """
  Hrana-over-HTTP version probe. Stock libSQL clients issue `GET /v2`
  or `GET /v3` to discover which protocol version the server serves
  before posting to `/vN/pipeline`; a `200` signals support. The
  pipeline endpoint itself is wire-compatible across the v2/v3 subset
  we implement, so both probes answer the same way.
  """

  use SmolsqlsWeb, :controller

  def check(conn, _params) do
    send_resp(conn, 200, "")
  end
end

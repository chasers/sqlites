defmodule SqlitesWeb.MetricsController do
  @moduledoc """
  Prometheus scrape endpoint. Unauthenticated by design — it is meant
  to be reachable only inside the cluster network; do not expose it on
  a public ingress.
  """

  use SqlitesWeb, :controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, TelemetryMetricsPrometheus.Core.scrape(:sqlites_prometheus))
  end
end

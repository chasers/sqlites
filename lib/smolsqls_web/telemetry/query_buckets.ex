defmodule SmolsqlsWeb.Telemetry.QueryBuckets do
  @moduledoc """
  Histogram boundaries for query-shaped latencies (ms).
  """

  use Peep.Buckets.Custom,
    buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1_000, 5_000, 30_000]
end

defmodule SqlitesWeb.Telemetry.TransferBuckets do
  @moduledoc """
  Histogram boundaries for snapshot ship/restore latencies (ms).
  """

  use Peep.Buckets.Custom,
    buckets: [10, 50, 100, 250, 500, 1_000, 2_500, 5_000, 15_000, 60_000]
end

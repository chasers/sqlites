defmodule Sqlites.Drain.Request do
  @moduledoc """
  A row in `node_drains` — the metadb-mediated node-operation bus. The
  operator (or an admin) inserts a request for a node; any data-plane
  node claims and executes it, then reports completion on the same
  row. One request per node at a time: repeating an operation requires
  deleting the node's row.

  `kind` selects the operation: `"drain"` (orderly evacuation of a
  live node — hot databases idle-stop and ship first) or `"evacuate"`
  (a dead node's placement rows are reassigned to survivors; cancelled
  at claim time if the node reconnected).
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:node, :string, autogenerate: false}
  schema "node_drains" do
    field :kind, :string, default: "drain"
    field :requested_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :started_by, :string
    field :completed_at, :utc_datetime_usec
    field :reassigned, :integer
    field :error, :string
  end
end

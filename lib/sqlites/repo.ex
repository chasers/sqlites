defmodule Sqlites.Repo do
  use Ecto.Repo,
    otp_app: :sqlites,
    adapter: Ecto.Adapters.Postgres
end

defmodule Smolsqls.Repo do
  use Ecto.Repo,
    otp_app: :smolsqls,
    adapter: Ecto.Adapters.Postgres
end

defmodule Smolsqls.Repo.Migrations.CreateReadModelPublication do
  use Ecto.Migration

  def up do
    execute "CREATE PUBLICATION smolsqls_read_model FOR TABLE tenants, databases"
  end

  def down do
    execute "DROP PUBLICATION smolsqls_read_model"
  end
end

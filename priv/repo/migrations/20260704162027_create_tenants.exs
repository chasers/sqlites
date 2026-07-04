defmodule Sqlites.Repo.Migrations.CreateTenants do
  use Ecto.Migration

  def change do
    create table(:tenants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :api_key, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenants, [:slug])
    create unique_index(:tenants, [:api_key])
  end
end

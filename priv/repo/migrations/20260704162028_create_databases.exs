defmodule Sqlites.Repo.Migrations.CreateDatabases do
  use Ecto.Migration

  def change do
    create table(:databases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :node, :string
      add :file_path, :string
      add :auth_token, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:databases, [:tenant_id, :name])
    create unique_index(:databases, [:auth_token])
    create index(:databases, [:node])
  end
end

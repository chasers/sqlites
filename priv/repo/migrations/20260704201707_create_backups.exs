defmodule Smolsqls.Repo.Migrations.CreateBackups do
  use Ecto.Migration

  def change do
    create table(:backups, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :database_id, references(:databases, type: :binary_id, on_delete: :delete_all),
        null: false

      add :object_key, :string, null: false
      add :size_bytes, :bigint, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:backups, [:database_id])
  end
end

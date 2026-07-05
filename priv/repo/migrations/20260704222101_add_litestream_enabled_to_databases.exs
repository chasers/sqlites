defmodule Smolsqls.Repo.Migrations.AddLitestreamEnabledToDatabases do
  use Ecto.Migration

  def change do
    alter table(:databases) do
      add :litestream_enabled, :boolean, null: false, default: false
    end
  end
end

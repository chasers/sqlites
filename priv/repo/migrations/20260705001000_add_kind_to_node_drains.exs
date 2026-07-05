defmodule Smolsqls.Repo.Migrations.AddKindToNodeDrains do
  use Ecto.Migration

  def up do
    alter table(:node_drains) do
      add :kind, :string, null: false, default: "drain"
    end
  end

  def down do
    alter table(:node_drains) do
      remove :kind
    end
  end
end

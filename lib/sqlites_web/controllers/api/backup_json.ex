defmodule SqlitesWeb.Api.BackupJSON do
  def index(%{backups: backups}) do
    %{data: Enum.map(backups, &data/1)}
  end

  def show(%{backup: backup}) do
    %{data: data(backup)}
  end

  defp data(backup) do
    %{
      id: backup.id,
      created_at: backup.created_at,
      size_bytes: backup.size_bytes
    }
  end
end

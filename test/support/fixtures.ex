defmodule Sqlites.Fixtures do
  @moduledoc """
  Test data helpers for tenants and databases.
  """

  alias Sqlites.ControlPlane

  def unique_slug, do: "org-#{System.unique_integer([:positive])}"

  def tenant_fixture(attrs \\ %{}) do
    {:ok, tenant} =
      attrs
      |> Enum.into(%{"name" => "Test Org", "slug" => unique_slug()})
      |> ControlPlane.create_tenant()

    tenant
  end

  def database_fixture(tenant, attrs \\ %{}) do
    {:ok, database} =
      ControlPlane.create_database(
        tenant,
        Enum.into(attrs, %{"name" => "db-#{System.unique_integer([:positive])}"})
      )

    database
  end

  def placed_database_fixture(tenant, attrs \\ %{}) do
    {:ok, database} =
      tenant
      |> database_fixture(attrs)
      |> Sqlites.DataPlane.place_database()

    ExUnit.Callbacks.on_exit(fn ->
      Sqlites.DataPlane.Supervisor.stop_database(database.id)

      if database.file_path do
        File.rm(database.file_path)
        File.rm(database.file_path <> "-wal")
        File.rm(database.file_path <> "-shm")
      end
    end)

    database
  end
end

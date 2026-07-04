defmodule Sqlites.ReadModel.Row do
  @moduledoc """
  Builds control-plane structs from the text-format column values that
  both the COPY snapshot and the pgoutput feed produce.
  """

  alias Sqlites.ControlPlane.{Database, Tenant}

  @database_columns ~w(id tenant_id name status node file_path auth_token)
  @tenant_columns ~w(id name slug api_key)

  def database_columns, do: @database_columns
  def tenant_columns, do: @tenant_columns

  @spec build_database(%{optional(String.t()) => String.t() | nil}) :: Database.t()
  def build_database(values) do
    %Database{
      id: Map.fetch!(values, "id"),
      tenant_id: Map.fetch!(values, "tenant_id"),
      name: Map.fetch!(values, "name"),
      status: status(Map.fetch!(values, "status")),
      node: Map.get(values, "node"),
      file_path: Map.get(values, "file_path"),
      auth_token: Map.fetch!(values, "auth_token")
    }
  end

  @spec build_tenant(%{optional(String.t()) => String.t() | nil}) :: Tenant.t()
  def build_tenant(values) do
    %Tenant{
      id: Map.fetch!(values, "id"),
      name: Map.fetch!(values, "name"),
      slug: Map.fetch!(values, "slug"),
      api_key: Map.fetch!(values, "api_key")
    }
  end

  defp status("pending"), do: :pending
  defp status("active"), do: :active
  defp status("deleting"), do: :deleting
  defp status("error"), do: :error
end

defmodule SqlitesWeb.Api.QueryController do
  use SqlitesWeb, :controller

  alias Sqlites.ControlPlane
  alias Sqlites.DataPlane

  action_fallback SqlitesWeb.Api.FallbackController

  def create(conn, %{"database_id" => database_id, "sql" => sql} = params) do
    args = Map.get(params, "args", [])

    with {:ok, token} <- bearer_token(conn),
         {:ok, database} <- ControlPlane.authenticate_database(database_id, token),
         {:ok, result} <- DataPlane.query(database.id, sql, args) do
      render(conn, :show, result: result)
    end
  end

  def create(_conn, _params), do: {:error, :missing_sql}

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :unauthorized}
    end
  end
end

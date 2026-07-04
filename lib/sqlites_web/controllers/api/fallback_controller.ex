defmodule SqlitesWeb.Api.FallbackController do
  use Phoenix.Controller, formats: [:json]

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "validation_failed", details: errors}})
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{code: "not_found", message: "resource not found"}})
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "unauthorized", message: "missing or invalid credentials"}})
  end

  def call(conn, {:error, :database_not_running}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      error: %{
        code: "database_not_running",
        message: "database is not currently placed on any node"
      }
    })
  end

  def call(conn, {:error, :missing_sql}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "missing_sql", message: "request body requires a \"sql\" field"}})
  end

  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "query_error", message: reason}})
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: %{code: "internal_error", message: inspect(reason)}})
  end
end

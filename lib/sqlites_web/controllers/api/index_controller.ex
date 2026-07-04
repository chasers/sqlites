defmodule SqlitesWeb.Api.IndexController do
  @moduledoc """
  Machine-readable API index so an agent can bootstrap the full
  lifecycle — signup, database CRUD, queries, backups — from the base
  URL alone.
  """

  use SqlitesWeb, :controller

  def index(conn, _params) do
    base = SqlitesWeb.Endpoint.url()

    json(conn, %{
      service: "sqlites",
      description:
        "Multitenant SQLite database service. Sign up for a tenant, create databases, " <>
          "connect with any libSQL client or plain HTTP. All management endpoints " <>
          "authenticate with 'Authorization: Bearer <tenant api_key>'; query endpoints " <>
          "authenticate with the per-database auth_token.",
      endpoints: [
        %{
          method: "POST",
          path: "#{base}/v1/tenants",
          auth: "none",
          body: %{name: "My Org", slug: "my-org"},
          returns: "tenant with api_key — store it, it is shown only once"
        },
        %{method: "GET", path: "#{base}/v1/tenant", auth: "tenant api_key"},
        %{
          method: "PATCH",
          path: "#{base}/v1/tenant",
          auth: "tenant api_key",
          body: %{name: "..."}
        },
        %{method: "DELETE", path: "#{base}/v1/tenant", auth: "tenant api_key"},
        %{method: "GET", path: "#{base}/v1/databases", auth: "tenant api_key"},
        %{
          method: "POST",
          path: "#{base}/v1/databases",
          auth: "tenant api_key",
          body: %{name: "my-task-db"},
          returns: "database with auth_token and ready-to-use connection strings"
        },
        %{method: "GET", path: "#{base}/v1/databases/:id", auth: "tenant api_key"},
        %{
          method: "PATCH",
          path: "#{base}/v1/databases/:id",
          auth: "tenant api_key",
          body: %{litestream_enabled: true},
          returns: "toggle continuous (litestream) replication for this database"
        },
        %{method: "DELETE", path: "#{base}/v1/databases/:id", auth: "tenant api_key"},
        %{
          method: "POST",
          path: "#{base}/v1/databases/:id/query",
          auth: "database auth_token",
          body: %{sql: "SELECT * FROM t WHERE id = ?", args: [1]},
          returns: "columns, rows, num_changes"
        },
        %{method: "GET", path: "#{base}/v1/databases/:id/backups", auth: "tenant api_key"},
        %{method: "POST", path: "#{base}/v1/databases/:id/backups", auth: "tenant api_key"},
        %{
          method: "POST",
          path: "#{base}/v1/databases/:id/restore",
          auth: "tenant api_key",
          body: %{backup_id: "..."}
        }
      ]
    })
  end
end

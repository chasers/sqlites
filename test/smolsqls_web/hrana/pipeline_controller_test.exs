defmodule SmolsqlsWeb.Hrana.PipelineControllerTest do
  use SmolsqlsWeb.ConnCase, async: false

  import Smolsqls.Fixtures

  setup do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)
    %{database: database}
  end

  defp pipeline(conn, token, requests, path \\ "/v2/pipeline") do
    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> post(path, %{"requests" => requests})
  end

  test "executes a pipeline of statements", %{conn: conn, database: database} do
    body =
      conn
      |> pipeline(database.auth_token, [
        %{type: "execute", stmt: %{sql: "CREATE TABLE t (v TEXT)", want_rows: false}},
        %{
          type: "execute",
          stmt: %{
            sql: "INSERT INTO t VALUES (?)",
            args: [%{type: "text", value: "over-http"}],
            want_rows: false
          }
        },
        %{type: "execute", stmt: %{sql: "SELECT v FROM t", want_rows: true}},
        %{type: "close"}
      ])
      |> json_response(200)

    assert body["baton"] == nil

    assert [
             %{"type" => "ok"},
             %{"type" => "ok"},
             %{
               "type" => "ok",
               "response" => %{
                 "result" => %{"rows" => [[%{"type" => "text", "value" => "over-http"}]]}
               }
             },
             %{"type" => "ok", "response" => %{"type" => "close"}}
           ] = body["results"]
  end

  test "store_sql is scoped to the pipeline", %{conn: conn, database: database} do
    body =
      conn
      |> pipeline(database.auth_token, [
        %{type: "store_sql", sql_id: 1, sql: "SELECT 42"},
        %{type: "execute", stmt: %{sql_id: 1, want_rows: true}}
      ])
      |> json_response(200)

    assert [_, %{"response" => %{"result" => %{"rows" => [[%{"value" => "42"}]]}}}] =
             body["results"]

    body =
      conn
      |> pipeline(database.auth_token, [
        %{type: "execute", stmt: %{sql_id: 1, want_rows: true}}
      ])
      |> json_response(200)

    assert [%{"type" => "error", "error" => %{"message" => message}}] = body["results"]
    assert message =~ "unknown sql_id"
  end

  test "rejects bad tokens and batons", %{conn: conn, database: database} do
    conn
    |> pipeline("wrong-token", [])
    |> json_response(401)

    body =
      conn
      |> put_req_header("authorization", "Bearer " <> database.auth_token)
      |> post(~p"/v2/pipeline", %{"baton" => "b", "requests" => []})
      |> json_response(400)

    assert body["error"]["message"] =~ "baton"
  end

  test "serves the same pipeline at /v3/pipeline", %{conn: conn, database: database} do
    body =
      conn
      |> pipeline(
        database.auth_token,
        [%{type: "execute", stmt: %{sql: "SELECT 1", want_rows: true}}],
        ~p"/v3/pipeline"
      )
      |> json_response(200)

    assert [%{"type" => "ok", "response" => %{"result" => %{"rows" => [[%{"value" => "1"}]]}}}] =
             body["results"]
  end

  test "decodes a text/plain body (browser fetch)", %{conn: conn, database: database} do
    body =
      conn
      |> put_req_header("authorization", "Bearer " <> database.auth_token)
      |> put_req_header("content-type", "text/plain;charset=UTF-8")
      |> post(
        ~p"/v2/pipeline",
        Jason.encode!(%{
          requests: [%{type: "execute", stmt: %{sql: "SELECT 1", want_rows: true}}]
        })
      )
      |> json_response(200)

    assert [%{"type" => "ok", "response" => %{"result" => %{"rows" => [[%{"value" => "1"}]]}}}] =
             body["results"]
  end

  test "conditional transactional batch reads within a transaction", %{
    conn: conn,
    database: database
  } do
    body =
      conn
      |> pipeline(database.auth_token, [
        %{type: "execute", stmt: %{sql: "CREATE TABLE t (v TEXT)", want_rows: false}},
        %{
          type: "execute",
          stmt: %{sql: "INSERT INTO t VALUES (?)", args: [%{type: "text", value: "x"}]}
        },
        %{
          type: "batch",
          batch: %{
            steps: [
              %{stmt: %{sql: "BEGIN IMMEDIATE"}},
              %{
                stmt: %{sql: "SELECT v FROM t", want_rows: true},
                condition: %{
                  type: "and",
                  conds: [
                    %{type: "ok", step: 0},
                    %{type: "not", cond: %{type: "is_autocommit"}}
                  ]
                }
              },
              %{stmt: %{sql: "COMMIT"}, condition: %{type: "ok", step: 1}},
              %{stmt: %{sql: "ROLLBACK"}, condition: %{type: "not", cond: %{type: "ok", step: 2}}}
            ]
          }
        },
        %{type: "close"}
      ])
      |> json_response(200)

    assert [
             %{"type" => "ok"},
             %{"type" => "ok"},
             %{
               "type" => "ok",
               "response" => %{"result" => %{"step_results" => steps, "step_errors" => errors}}
             },
             %{"type" => "ok"}
           ] = body["results"]

    assert [%{}, %{"rows" => [[%{"value" => "x"}]]}, %{}, nil] = steps
    assert [nil, nil, nil, nil] = errors
  end

  test "a rolled-back batch leaves no data (transactions are real)", %{
    conn: conn,
    database: database
  } do
    conn
    |> pipeline(database.auth_token, [
      %{type: "execute", stmt: %{sql: "CREATE TABLE t (v TEXT)", want_rows: false}},
      %{
        type: "batch",
        batch: %{
          steps: [
            %{stmt: %{sql: "BEGIN IMMEDIATE"}},
            %{
              stmt: %{sql: "INSERT INTO t VALUES ('rolled-back')"},
              condition: %{type: "ok", step: 0}
            },
            %{stmt: %{sql: "ROLLBACK"}, condition: %{type: "ok", step: 1}}
          ]
        }
      }
    ])
    |> json_response(200)

    body =
      conn
      |> pipeline(database.auth_token, [
        %{type: "execute", stmt: %{sql: "SELECT count(*) AS n FROM t", want_rows: true}}
      ])
      |> json_response(200)

    assert [%{"response" => %{"result" => %{"rows" => [[%{"value" => "0"}]]}}}] = body["results"]
  end

  test "errors in one request do not abort the pipeline", %{conn: conn, database: database} do
    body =
      conn
      |> pipeline(database.auth_token, [
        %{type: "execute", stmt: %{sql: "SELEC nope", want_rows: false}},
        %{type: "execute", stmt: %{sql: "SELECT 1", want_rows: true}}
      ])
      |> json_response(200)

    assert [%{"type" => "error"}, %{"type" => "ok"}] = body["results"]
  end
end

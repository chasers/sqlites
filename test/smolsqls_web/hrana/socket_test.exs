defmodule SmolsqlsWeb.Hrana.SocketTest do
  use Smolsqls.DataCase

  import Smolsqls.Fixtures

  alias SmolsqlsWeb.Hrana.Socket

  defp send_message(message, state) do
    {:push, {:text, payload}, state} =
      Socket.handle_in({Jason.encode!(message), opcode: :text}, state)

    {Jason.decode!(payload), state}
  end

  defp connected_state(database) do
    {:ok, state} = Socket.init([])

    {%{"type" => "hello_ok"}, state} =
      send_message(%{type: "hello", jwt: database.auth_token}, state)

    {%{"type" => "response_ok"}, state} =
      send_message(
        %{type: "request", request_id: 0, request: %{type: "open_stream", stream_id: 1}},
        state
      )

    state
  end

  defp execute(sql, args, state) do
    send_message(
      %{
        type: "request",
        request_id: 1,
        request: %{
          type: "execute",
          stream_id: 1,
          stmt: %{sql: sql, args: args, want_rows: true}
        }
      },
      state
    )
  end

  setup do
    tenant = tenant_fixture()
    database = placed_database_fixture(tenant)
    %{tenant: tenant, database: database}
  end

  test "rejects a bad auth token" do
    {:ok, state} = Socket.init([])
    {response, _state} = send_message(%{type: "hello", jwt: "wrong"}, state)
    assert %{"type" => "hello_error"} = response
  end

  test "rejects requests before hello" do
    {:ok, state} = Socket.init([])

    {response, _state} =
      send_message(
        %{type: "request", request_id: 7, request: %{type: "open_stream", stream_id: 1}},
        state
      )

    assert %{"type" => "response_error", "request_id" => 7} = response
  end

  test "executes statements with typed args and rows", %{database: database} do
    state = connected_state(database)

    {response, state} = execute("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)", [], state)
    assert %{"type" => "response_ok"} = response

    {response, state} =
      execute("INSERT INTO t (v) VALUES (?)", [%{type: "text", value: "hi"}], state)

    assert %{
             "response" => %{"result" => %{"affected_row_count" => 1, "last_insert_rowid" => "1"}}
           } =
             response

    {response, _state} = execute("SELECT id, v FROM t", [], state)

    assert %{
             "response" => %{
               "result" => %{
                 "cols" => [%{"name" => "id"}, %{"name" => "v"}],
                 "rows" => [
                   [%{"type" => "integer", "value" => "1"}, %{"type" => "text", "value" => "hi"}]
                 ]
               }
             }
           } = response
  end

  test "stored SQL via store_sql/sql_id", %{database: database} do
    state = connected_state(database)

    {response, state} =
      send_message(
        %{
          type: "request",
          request_id: 2,
          request: %{type: "store_sql", sql_id: 0, sql: "SELECT 42"}
        },
        state
      )

    assert %{"type" => "response_ok"} = response

    {response, _state} =
      send_message(
        %{
          type: "request",
          request_id: 3,
          request: %{type: "execute", stream_id: 1, stmt: %{sql_id: 0, want_rows: true}}
        },
        state
      )

    assert %{"response" => %{"result" => %{"rows" => [[%{"value" => "42"}]]}}} = response
  end

  test "returns response_error for bad SQL", %{database: database} do
    state = connected_state(database)
    {response, _state} = execute("SELEC nope", [], state)
    assert %{"type" => "response_error", "error" => %{"message" => message}} = response
    assert message =~ "syntax error"
  end

  describe "interactive transactions" do
    test "BEGIN/COMMIT round-trips and toggles autocommit", %{database: database} do
      state = connected_state(database)
      {_response, state} = execute("CREATE TABLE t (v TEXT)", [], state)

      {response, state} =
        send_message(%{type: "request", request_id: 9, request: %{type: "get_autocommit"}}, state)

      assert %{"response" => %{"is_autocommit" => true}} = response

      {response, state} = execute("BEGIN", [], state)
      assert %{"type" => "response_ok"} = response

      {response, state} =
        send_message(%{type: "request", request_id: 9, request: %{type: "get_autocommit"}}, state)

      assert %{"response" => %{"is_autocommit" => false}} = response

      {_response, state} = execute("INSERT INTO t VALUES ('committed')", [], state)
      {response, state} = execute("COMMIT", [], state)
      assert %{"type" => "response_ok"} = response

      {response, _state} = execute("SELECT v FROM t", [], state)
      assert %{"response" => %{"result" => %{"rows" => [[%{"value" => "committed"}]]}}} = response
    end

    test "ROLLBACK discards the transaction's writes", %{database: database} do
      state = connected_state(database)
      {_response, state} = execute("CREATE TABLE t (v TEXT)", [], state)

      {_response, state} = execute("BEGIN", [], state)
      {_response, state} = execute("INSERT INTO t VALUES ('discarded')", [], state)
      {response, state} = execute("ROLLBACK", [], state)
      assert %{"type" => "response_ok"} = response

      {response, _state} = execute("SELECT count(*) FROM t", [], state)
      assert %{"response" => %{"result" => %{"rows" => [[%{"value" => "0"}]]}}} = response
    end

    test "another connection fails fast while the lease is held", %{database: database} do
      state = connected_state(database)
      {_response, state} = execute("CREATE TABLE t (v TEXT)", [], state)
      {_response, state} = execute("BEGIN", [], state)
      {_response, state} = execute("INSERT INTO t VALUES ('mine')", [], state)

      other =
        Task.async(fn ->
          {:ok, other_state} = SmolsqlsWeb.Hrana.Socket.init([])

          {:push, {:text, hello}, other_state} =
            SmolsqlsWeb.Hrana.Socket.handle_in(
              {Jason.encode!(%{type: "hello", jwt: database.auth_token}), opcode: :text},
              other_state
            )

          assert %{"type" => "hello_ok"} = Jason.decode!(hello)

          {:push, {:text, payload}, _other_state} =
            SmolsqlsWeb.Hrana.Socket.handle_in(
              {Jason.encode!(%{
                 type: "request",
                 request_id: 1,
                 request: %{
                   type: "execute",
                   stream_id: 1,
                   stmt: %{sql: "SELECT 1", want_rows: true}
                 }
               }), opcode: :text},
              other_state
            )

          Jason.decode!(payload)
        end)

      response = Task.await(other)
      assert %{"type" => "response_error", "error" => %{"message" => message}} = response
      assert message =~ "open transaction"

      {response, _state} = execute("COMMIT", [], state)
      assert %{"type" => "response_ok"} = response
    end

    test "an abandoned transaction rolls back on the txn timeout", %{tenant: tenant} do
      database = placed_database_fixture(tenant, %{}, limits: %{"txn_timeout_ms" => 100})
      state = connected_state(database)

      {_response, state} = execute("CREATE TABLE t (v TEXT)", [], state)
      {_response, state} = execute("BEGIN", [], state)
      {_response, state} = execute("INSERT INTO t VALUES ('abandoned')", [], state)

      Process.sleep(200)

      {response, state} = execute("COMMIT", [], state)
      assert %{"type" => "response_error", "error" => %{"message" => message}} = response
      assert message =~ "no transaction"

      {response, _state} = execute("SELECT count(*) FROM t", [], state)
      assert %{"response" => %{"result" => %{"rows" => [[%{"value" => "0"}]]}}} = response
    end

    test "the lease dies with its owner", %{database: database} do
      state = connected_state(database)
      {_response, _state} = execute("CREATE TABLE t (v TEXT)", [], state)

      holder =
        Task.async(fn ->
          {:ok, other_state} = SmolsqlsWeb.Hrana.Socket.init([])

          {:push, {:text, _hello}, other_state} =
            SmolsqlsWeb.Hrana.Socket.handle_in(
              {Jason.encode!(%{type: "hello", jwt: database.auth_token}), opcode: :text},
              other_state
            )

          for sql <- ["BEGIN", "INSERT INTO t VALUES ('orphaned')"] do
            {:push, {:text, payload}, _s} =
              SmolsqlsWeb.Hrana.Socket.handle_in(
                {Jason.encode!(%{
                   type: "request",
                   request_id: 1,
                   request: %{
                     type: "execute",
                     stream_id: 1,
                     stmt: %{sql: sql, want_rows: false}
                   }
                 }), opcode: :text},
                other_state
              )

            assert %{"type" => "response_ok"} = Jason.decode!(payload)
          end

          :ok
        end)

      assert :ok = Task.await(holder)

      wait_until(fn ->
        {response, _} = execute("SELECT count(*) FROM t", [], connected_state(database))
        match?(%{"type" => "response_ok"}, response)
      end)

      {response, _state} = execute("SELECT count(*) FROM t", [], connected_state(database))
      assert %{"response" => %{"result" => %{"rows" => [[%{"value" => "0"}]]}}} = response
    end
  end

  defp wait_until(fun, attempts \\ 50)
  defp wait_until(fun, 0), do: assert(fun.())

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      wait_until(fun, attempts - 1)
    end
  end

  test "binds named args", %{database: database} do
    state = connected_state(database)

    {_response, state} = execute("CREATE TABLE t (a TEXT, b INTEGER)", [], state)

    {response, state} =
      send_message(
        %{
          type: "request",
          request_id: 4,
          request: %{
            type: "execute",
            stream_id: 1,
            stmt: %{
              sql: "INSERT INTO t VALUES (:a, @b)",
              named_args: [
                %{name: "a", value: %{type: "text", value: "named"}},
                %{name: "@b", value: %{type: "integer", value: "7"}}
              ],
              want_rows: false
            }
          }
        },
        state
      )

    assert %{"response" => %{"result" => %{"affected_row_count" => 1}}} = response

    {response, _state} = execute("SELECT a, b FROM t", [], state)

    assert %{
             "response" => %{
               "result" => %{
                 "rows" => [
                   [
                     %{"type" => "text", "value" => "named"},
                     %{"type" => "integer", "value" => "7"}
                   ]
                 ]
               }
             }
           } = response
  end

  test "describe returns cols and param count without executing", %{database: database} do
    state = connected_state(database)
    {_response, state} = execute("CREATE TABLE t (id INTEGER, v TEXT)", [], state)

    {response, _state} =
      send_message(
        %{
          type: "request",
          request_id: 5,
          request: %{type: "describe", stream_id: 1, sql: "SELECT id, v FROM t WHERE id = ?"}
        },
        state
      )

    assert %{
             "type" => "response_ok",
             "response" => %{
               "type" => "describe",
               "result" => %{
                 "cols" => [%{"name" => "id"}, %{"name" => "v"}],
                 "params" => [%{"name" => nil}],
                 "is_readonly" => true
               }
             }
           } = response
  end

  test "sequence executes a multi-statement script", %{database: database} do
    state = connected_state(database)

    {response, state} =
      send_message(
        %{
          type: "request",
          request_id: 6,
          request: %{
            type: "sequence",
            stream_id: 1,
            sql: "CREATE TABLE seq_t (v TEXT); INSERT INTO seq_t VALUES ('a'), ('b');"
          }
        },
        state
      )

    assert %{"type" => "response_ok", "response" => %{"type" => "sequence"}} = response

    {response, _state} = execute("SELECT count(*) FROM seq_t", [], state)
    assert %{"response" => %{"result" => %{"rows" => [[%{"value" => "2"}]]}}} = response
  end

  test "batch reports per-step errors", %{database: database} do
    state = connected_state(database)

    {response, _state} =
      send_message(
        %{
          type: "request",
          request_id: 8,
          request: %{
            type: "batch",
            stream_id: 1,
            batch: %{
              steps: [
                %{stmt: %{sql: "CREATE TABLE b (v TEXT)", want_rows: false}},
                %{stmt: %{sql: "INSERT INTO nope VALUES ('x')", want_rows: false}},
                %{stmt: %{sql: "INSERT INTO b VALUES ('x')", want_rows: false}}
              ]
            }
          }
        },
        state
      )

    assert %{
             "type" => "response_ok",
             "response" => %{
               "result" => %{
                 "step_results" => [%{}, nil, %{}],
                 "step_errors" => [nil, %{"message" => message}, nil]
               }
             }
           } = response

    assert message =~ "no such table"
  end
end

defmodule SqlitesWeb.Hrana.Socket do
  @moduledoc """
  WebSocket handler speaking a subset of the Hrana protocol (v1/v2) used
  by libSQL clients: `hello`, `open_stream`, `close_stream`, `execute`,
  `batch`. The database is identified by the per-database auth token
  carried in `hello`, so clients can connect to any host/path the
  cluster serves. Statements are routed to the owning node through
  `Sqlites.DataPlane`.
  """

  @behaviour WebSock

  alias Sqlites.ControlPlane
  alias Sqlites.DataPlane

  @impl true
  def init(_opts) do
    {:ok, %{database: nil, streams: MapSet.new(), sqls: %{}}}
  end

  @impl true
  def handle_in({payload, opcode: :text}, state) do
    case Jason.decode(payload) do
      {:ok, message} -> handle_message(message, state)
      {:error, _} -> {:stop, :normal, 1003, state}
    end
  end

  @impl true
  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  defp handle_message(%{"type" => "hello"} = message, state) do
    token = message["jwt"]

    case token && ControlPlane.get_database_by_auth_token(token) do
      %ControlPlane.Database{} = database ->
        reply(%{type: "hello_ok"}, %{state | database: database})

      _ ->
        reply(
          %{type: "hello_error", error: %{message: "invalid auth token", code: "AUTH_INVALID"}},
          state
        )
    end
  end

  defp handle_message(%{"type" => "request"} = message, %{database: nil} = state) do
    request_error(message["request_id"], "hello with a valid auth token required", state)
  end

  defp handle_message(
         %{"type" => "request", "request_id" => request_id, "request" => request},
         state
       ) do
    handle_request(request, request_id, state)
  end

  defp handle_message(_message, state), do: {:ok, state}

  defp handle_request(%{"type" => "open_stream", "stream_id" => stream_id}, request_id, state) do
    state = %{state | streams: MapSet.put(state.streams, stream_id)}
    respond_ok(request_id, %{type: "open_stream"}, state)
  end

  defp handle_request(%{"type" => "close_stream", "stream_id" => stream_id}, request_id, state) do
    state = %{state | streams: MapSet.delete(state.streams, stream_id)}
    respond_ok(request_id, %{type: "close_stream"}, state)
  end

  defp handle_request(
         %{"type" => "store_sql", "sql_id" => sql_id, "sql" => sql},
         request_id,
         state
       ) do
    state = %{state | sqls: Map.put(state.sqls, sql_id, sql)}
    respond_ok(request_id, %{type: "store_sql"}, state)
  end

  defp handle_request(%{"type" => "close_sql", "sql_id" => sql_id}, request_id, state) do
    state = %{state | sqls: Map.delete(state.sqls, sql_id)}
    respond_ok(request_id, %{type: "close_sql"}, state)
  end

  defp handle_request(%{"type" => "get_autocommit"}, request_id, state) do
    respond_ok(request_id, %{type: "get_autocommit", is_autocommit: true}, state)
  end

  defp handle_request(%{"type" => "execute", "stmt" => stmt}, request_id, state) do
    case execute_stmt(stmt, state) do
      {:ok, result} -> respond_ok(request_id, %{type: "execute", result: result}, state)
      {:error, message} -> request_error(request_id, message, state)
    end
  end

  defp handle_request(%{"type" => "batch", "batch" => %{"steps" => steps}}, request_id, state) do
    step_results =
      Enum.map(steps, fn %{"stmt" => stmt} ->
        execute_stmt(stmt, state)
      end)

    results =
      Enum.map(step_results, fn
        {:ok, result} -> result
        {:error, _} -> nil
      end)

    errors =
      Enum.map(step_results, fn
        {:ok, _} -> nil
        {:error, message} -> %{message: message}
      end)

    respond_ok(
      request_id,
      %{type: "batch", result: %{step_results: results, step_errors: errors}},
      state
    )
  end

  defp handle_request(request, request_id, state) do
    request_error(request_id, "unsupported request type #{request["type"]}", state)
  end

  defp execute_stmt(stmt, state) do
    case resolve_sql(stmt, state) do
      {:ok, sql} -> run_stmt(sql, stmt, state.database)
      {:error, message} -> {:error, message}
    end
  end

  defp resolve_sql(%{"sql" => sql}, _state) when is_binary(sql), do: {:ok, sql}

  defp resolve_sql(%{"sql_id" => sql_id}, state) do
    case Map.fetch(state.sqls, sql_id) do
      {:ok, sql} -> {:ok, sql}
      :error -> {:error, "unknown sql_id #{sql_id}"}
    end
  end

  defp resolve_sql(_stmt, _state), do: {:error, "stmt requires sql or sql_id"}

  defp run_stmt(sql, stmt, database) do
    args = Enum.map(stmt["args"] || [], &decode_value/1)

    case DataPlane.query(database.id, sql, args) do
      {:ok, result} ->
        {:ok,
         %{
           cols: Enum.map(result.columns, &%{name: &1}),
           rows: Enum.map(result.rows, fn row -> Enum.map(row, &encode_value/1) end),
           affected_row_count: result.num_changes,
           last_insert_rowid: to_string(result.last_insert_rowid)
         }}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp decode_value(%{"type" => "null"}), do: nil

  defp decode_value(%{"type" => "integer", "value" => value}) when is_binary(value),
    do: String.to_integer(value)

  defp decode_value(%{"type" => "integer", "value" => value}), do: value
  defp decode_value(%{"type" => "float", "value" => value}), do: value
  defp decode_value(%{"type" => "text", "value" => value}), do: value

  defp decode_value(%{"type" => "blob", "base64" => base64}),
    do: {:blob, Base.decode64!(base64, padding: false)}

  defp encode_value(nil), do: %{type: "null"}
  defp encode_value(value) when is_integer(value), do: %{type: "integer", value: to_string(value)}
  defp encode_value(value) when is_float(value), do: %{type: "float", value: value}

  defp encode_value(value) when is_binary(value) do
    if String.valid?(value) do
      %{type: "text", value: value}
    else
      %{type: "blob", base64: Base.encode64(value, padding: false)}
    end
  end

  defp respond_ok(request_id, response, state) do
    reply(%{type: "response_ok", request_id: request_id, response: response}, state)
  end

  defp request_error(request_id, message, state) do
    reply(
      %{type: "response_error", request_id: request_id, error: %{message: message}},
      state
    )
  end

  defp reply(message, state) do
    {:push, {:text, Jason.encode!(message)}, state}
  end
end

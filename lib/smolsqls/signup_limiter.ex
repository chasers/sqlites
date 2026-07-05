defmodule Smolsqls.SignupLimiter do
  @moduledoc """
  Fixed-window per-IP rate limit for account signups. Counts live in a
  public ETS table keyed by `{ip, window}`, so a check is one ETS read
  and a record is one `update_counter`; the owning process only sweeps
  expired windows.

  In memory and per node by design — the table is wiped on restart, and
  each node counts on its own. Signups are rare, so the resulting slack
  across a deploy or across nodes is acceptable, and it avoids a metadb
  table that would grow forever.

  `check/1` peeks the current window without counting; `record/1` bumps
  it, so a signup that fails to create (e.g. a taken slug) never counts
  against the caller. Configure with `config :smolsqls, :signup_rate_limit`.
  """

  use GenServer

  @table __MODULE__
  @default_max_per_ip 5
  @default_window_hours 24
  @sweep_interval :timer.minutes(30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec check(String.t()) :: :ok | {:error, :signup_rate_limited}
  def check(ip) when is_binary(ip) do
    if current_count(ip) >= max_per_ip(), do: {:error, :signup_rate_limited}, else: :ok
  end

  @spec record(String.t()) :: :ok
  def record(ip) when is_binary(ip) do
    key = key(ip)
    :ets.update_counter(@table, key, {2, 1}, {key, 0})
    :ok
  end

  @doc "Clears all counters. For tests."
  @spec reset() :: :ok
  def reset do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      _ ->
        :ets.delete_all_objects(@table)
        :ok
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :public, write_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    current = window(System.system_time(:second))

    :ets.select_delete(@table, [
      {{{:_, :"$1"}, :_}, [{:<, :"$1", current}], [true]}
    ])

    schedule_sweep()
    {:noreply, state}
  end

  defp current_count(ip) do
    case :ets.lookup(@table, key(ip)) do
      [{_key, count}] -> count
      [] -> 0
    end
  end

  defp key(ip), do: {ip, window(System.system_time(:second))}

  defp window(now_seconds), do: div(now_seconds, window_seconds())

  defp config, do: Application.get_env(:smolsqls, :signup_rate_limit, [])
  defp max_per_ip, do: Keyword.get(config(), :max_per_ip, @default_max_per_ip)
  defp window_seconds, do: Keyword.get(config(), :window_hours, @default_window_hours) * 3600

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end
end

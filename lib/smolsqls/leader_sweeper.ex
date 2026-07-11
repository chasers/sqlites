defmodule Smolsqls.LeaderSweeper do
  @moduledoc """
  Shared scaffolding for cluster-singleton sweepers — workers started on
  every node but gated so exactly one sweep runs cluster-wide at a time via
  a Postgres advisory lock.

  `use Smolsqls.LeaderSweeper` injects the GenServer timer loop
  (`start_link/1`, `init/1`, `handle_info(:sweep, _)`), the advisory-lock
  leader election (`as_leader/1`), and the config accessors
  (`interval/0`, `initial_delay/0`, `batch_size/0`, each overridable via
  `Application.get_env(:smolsqls, __MODULE__)`). The using module supplies
  its advisory-lock key and default interval as options and implements
  `sweep/0`, which should wrap its work in `as_leader/1`.

      use Smolsqls.LeaderSweeper, advisory_lock_key: 5_142_003, interval: :timer.hours(1)
  """

  alias Smolsqls.Repo

  defmacro __using__(opts) do
    advisory_lock_key = Keyword.fetch!(opts, :advisory_lock_key)
    default_interval = Keyword.fetch!(opts, :interval)

    quote do
      use GenServer

      @advisory_lock_key unquote(advisory_lock_key)

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
      end

      @impl true
      def init(_opts) do
        schedule_sweep(initial_delay())
        {:ok, %{}}
      end

      @impl true
      def handle_info(:sweep, state) do
        sweep()
        schedule_sweep(interval())
        {:noreply, state}
      end

      defp as_leader(fun), do: Smolsqls.LeaderSweeper.as_leader(@advisory_lock_key, fun)

      defp schedule_sweep(delay), do: Process.send_after(self(), :sweep, delay)

      defp config, do: Application.get_env(:smolsqls, __MODULE__, [])
      defp interval, do: config()[:interval] || unquote(default_interval)
      defp initial_delay, do: config()[:initial_delay] || :timer.minutes(1)
      defp batch_size, do: config()[:batch_size] || 500
    end
  end

  @doc """
  Runs `fun` only if this node wins the given advisory lock, releasing it
  afterwards; returns `nil` without running `fun` when another node holds
  the lock.
  """
  @spec as_leader(integer(), (-> result)) :: result | nil when result: term()
  def as_leader(advisory_lock_key, fun) do
    Repo.checkout(fn ->
      case Repo.query!("SELECT pg_try_advisory_lock($1)", [advisory_lock_key]) do
        %{rows: [[true]]} ->
          try do
            fun.()
          after
            Repo.query!("SELECT pg_advisory_unlock($1)", [advisory_lock_key])
          end

        _ ->
          nil
      end
    end)
  end
end

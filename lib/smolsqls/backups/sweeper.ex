defmodule Smolsqls.Backups.Sweeper do
  @moduledoc """
  Cluster singleton that upholds the daily-backup guarantee: every
  active database has a backup no older than the SLA window (`:sla_ms`,
  default 24h).

  On each tick a single node — chosen by a Postgres advisory lock, so
  exactly one sweep runs cluster-wide at a time — lists the databases
  whose newest backup is older than the window (or that have never been
  backed up) and produces an `:automatic` backup for each through
  `Smolsqls.Backups.trigger_automatic/1`. That promotes the existing
  idle snapshot for cold databases (a server-side object-store copy, no
  activation) and snapshots the live writer for hot ones. `:batch_size`
  bounds how many databases a single tick handles so a large fleet
  drains across ticks rather than stampeding owners or the object store.

  The worker is started on every node but gated by `enabled: true`; the
  advisory lock makes running it everywhere safe. This is a daily
  *artifact* floor, not point-in-time recovery.
  """

  use Smolsqls.LeaderSweeper, advisory_lock_key: 5_142_003, interval: :timer.hours(1)

  require Logger

  alias Smolsqls.Backups

  @doc """
  Runs one sweep if this node wins the advisory lock; otherwise a no-op.
  Returns the number of databases backed up (0 when not the leader).
  """
  @spec sweep() :: non_neg_integer()
  def sweep do
    as_leader(fn ->
      cutoff = DateTime.add(DateTime.utc_now(), -sla_ms(), :millisecond)
      due = Backups.due_for_backup(cutoff, limit: batch_size())
      backed_up = Enum.count(due, &(back_up(&1) == :ok))

      if due != [] do
        Logger.info("backup sweeper: #{backed_up}/#{length(due)} database(s) backed up")
      end

      Smolsqls.Telemetry.backup_sweep(length(due), backed_up)
      backed_up
    end) || 0
  end

  defp back_up(database) do
    case Backups.trigger_automatic(database) do
      {:ok, _backup} ->
        :ok

      {:error, reason} ->
        Logger.warning("backup sweeper: backup of #{database.id} failed: #{inspect(reason)}")
        :error
    end
  end

  defp sla_ms, do: config()[:sla_ms] || :timer.hours(24)
end

defmodule Sqlites.DataPlane.SupervisorTest do
  use ExUnit.Case, async: false

  alias Sqlites.DataPlane.Supervisor

  @moduletag :tmp_dir

  test "concurrent starts of the same database converge on one server", %{tmp_dir: tmp_dir} do
    database_id = "sup-race-#{System.unique_integer([:positive])}"
    file_path = Path.join(tmp_dir, database_id <> ".db")

    results =
      1..20
      |> Task.async_stream(
        fn _ -> Supervisor.start_database(database_id, file_path) end,
        max_concurrency: 20
      )
      |> Enum.map(fn {:ok, result} -> result end)

    pids = for {:ok, pid} <- results, do: pid
    assert length(pids) == 20
    assert [_single_pid] = Enum.uniq(pids)

    Supervisor.stop_database(database_id)
  end

  test "starts of different databases land on partitioned supervisors", %{tmp_dir: tmp_dir} do
    ids = for n <- 1..10, do: "sup-part-#{System.unique_integer([:positive])}-#{n}"

    pids =
      for database_id <- ids do
        {:ok, pid} =
          Supervisor.start_database(database_id, Path.join(tmp_dir, database_id <> ".db"))

        pid
      end

    supervisors = Enum.map(pids, fn pid -> :erlang.process_info(pid, :links) end)
    assert length(Enum.uniq(supervisors)) > 1

    partitions = PartitionSupervisor.partitions(Supervisor)
    assert partitions == System.schedulers_online()

    Enum.each(ids, &Supervisor.stop_database/1)
  end
end

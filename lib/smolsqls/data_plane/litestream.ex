defmodule Smolsqls.DataPlane.Litestream do
  @moduledoc """
  Hot-set replication: only databases with a running server are
  registered with the node's Litestream sidecar (dynamic registration
  over its control socket). `stop/1` performs a final sync before
  returning, so a cleanly idled database's replica is current — the
  replica is the single restore source for failover.

  Replica URLs are database-addressed (`<prefix>/<tenant>/<db>`), never
  node-addressed, so any node can restore any database.

  Disabled outside Kubernetes (`enabled: false`); all functions no-op.
  The `:binary` is configurable so tests can substitute a stub.
  """

  require Logger

  alias Smolsqls.ControlPlane.Database

  @spec enabled?() :: boolean()
  def enabled? do
    config()[:enabled] || false
  end

  @spec register(Database.t()) :: :ok | {:error, term()}
  def register(%Database{} = database) do
    if enabled?() do
      run([
        "register",
        "-socket",
        socket(),
        "-replica",
        replica_url(database),
        database.file_path
      ])
    else
      :ok
    end
  end

  @spec stop(Path.t()) :: :ok | {:error, term()}
  def stop(file_path) do
    if enabled?() do
      run(["stop", "-socket", socket(), file_path])
    else
      :ok
    end
  end

  @doc """
  Restores a database's replica to `dest_path` — the failover path for
  databases whose file is not on this node's volume.
  """
  @spec restore(Database.t(), Path.t()) :: :ok | {:error, term()}
  def restore(%Database{} = database, dest_path) do
    if enabled?() do
      File.mkdir_p!(Path.dirname(dest_path))
      run(["restore", "-o", dest_path, replica_url(database)])
    else
      {:error, :litestream_disabled}
    end
  end

  @spec replica_url(Database.t()) :: String.t()
  def replica_url(%Database{} = database) do
    "#{config()[:replica_url_prefix]}/#{database.tenant_id}/#{database.id}"
  end

  defp run(args) do
    case System.cmd(config()[:binary] || "litestream", args, stderr_to_stdout: true, env: env()) do
      {_output, 0} ->
        :ok

      {output, status} ->
        Logger.warning(
          "litestream #{hd(args)} failed (#{status}): #{String.slice(output, 0, 500)}"
        )

        {:error, {:litestream, status}}
    end
  end

  defp env do
    store = Application.get_env(:smolsqls, Smolsqls.ObjectStore, [])

    [
      {"LITESTREAM_ACCESS_KEY_ID", store[:access_key_id] || ""},
      {"LITESTREAM_SECRET_ACCESS_KEY", store[:secret_access_key] || ""}
    ]
  end

  defp socket do
    config()[:socket] || "/var/run/litestream/litestream.sock"
  end

  defp config do
    Application.get_env(:smolsqls, __MODULE__, [])
  end
end

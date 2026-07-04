defmodule SqlitesWeb.DatabaseLive.Index do
  use SqlitesWeb, :live_view

  alias Sqlites.ControlPlane
  alias Sqlites.DataPlane
  alias Sqlites.Infra

  @impl true
  def mount(_params, session, socket) do
    case authenticate(session) do
      {:ok, tenant} ->
        {:ok,
         socket
         |> assign(:tenant, tenant)
         |> assign(:page_title, "Databases")
         |> assign(:new_database_form, to_form(%{"name" => ""}))
         |> assign(:revealed_database_id, nil)
         |> load_databases()}

      {:error, :unauthorized} ->
        {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event("create", %{"name" => name}, socket) do
    tenant = socket.assigns.tenant

    with {:ok, database} <- ControlPlane.create_database(tenant, %{"name" => name}),
         {:ok, database} <- DataPlane.place_database(database),
         :ok <- Infra.provision(database) do
      {:noreply,
       socket
       |> put_flash(:info, "Database #{database.name} created")
       |> assign(:new_database_form, to_form(%{"name" => ""}))
       |> load_databases()}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, "Invalid name: #{inspect(changeset.errors[:name])}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Create failed: #{inspect(reason)}")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    tenant = socket.assigns.tenant

    with database when not is_nil(database) <- ControlPlane.get_database(tenant, id),
         {:ok, database} <- ControlPlane.mark_deleting(database),
         :ok <- Infra.deprovision(database),
         {:ok, _} <- DataPlane.remove_database(database) do
      {:noreply,
       socket
       |> put_flash(:info, "Database deleted")
       |> load_databases()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Delete failed")}
    end
  end

  def handle_event("backup", %{"id" => id}, socket) do
    tenant = socket.assigns.tenant

    with database when not is_nil(database) <- ControlPlane.get_database(tenant, id),
         {:ok, backup} <- Infra.trigger_backup(database) do
      {:noreply, put_flash(socket, :info, "Backup #{backup.id} created")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Backup failed")}
    end
  end

  def handle_event("toggle_connection", %{"id" => id}, socket) do
    revealed = if socket.assigns.revealed_database_id == id, do: nil, else: id
    {:noreply, assign(socket, :revealed_database_id, revealed)}
  end

  defp load_databases(socket) do
    assign(socket, :databases, ControlPlane.list_databases(socket.assigns.tenant))
  end

  defp authenticate(session) do
    case session["api_key"] do
      nil -> {:error, :unauthorized}
      api_key -> ControlPlane.authenticate_tenant(api_key)
    end
  end

  defp connection_string(database) do
    host = SqlitesWeb.Endpoint.host()
    port = SqlitesWeb.Endpoint.url() |> URI.parse() |> Map.get(:port)
    "libsql://#{host}:#{port}/#{database.id}?authToken=#{database.auth_token}"
  end

  defp query_url(database) do
    SqlitesWeb.Endpoint.url() <> "/v1/databases/#{database.id}/query"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-4xl space-y-8 py-8">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold">{@tenant.name}</h1>
            <p class="text-sm text-base-content/60">{length(@databases)} database(s)</p>
          </div>
          <form action={~p"/logout"} method="post">
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            <button class="btn btn-ghost btn-sm">Sign out</button>
          </form>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title text-base">New database</h2>
            <.form for={@new_database_form} phx-submit="create" class="flex gap-2">
              <input
                type="text"
                name="name"
                value={@new_database_form[:name].value}
                placeholder="database name (lowercase, dashes, underscores)"
                class="input input-bordered flex-1"
                required
              />
              <button class="btn btn-primary">Create</button>
            </.form>
          </div>
        </div>

        <div class="space-y-3">
          <div :for={database <- @databases} class="card bg-base-200">
            <div class="card-body space-y-2">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <span class="font-mono font-semibold">{database.name}</span>
                  <span class={[
                    "badge badge-sm",
                    database.status == :active && "badge-success",
                    database.status == :pending && "badge-warning",
                    database.status == :deleting && "badge-error"
                  ]}>
                    {database.status}
                  </span>
                  <span :if={database.node} class="text-xs text-base-content/50 font-mono">
                    {database.node}
                  </span>
                </div>
                <div class="flex gap-2">
                  <button
                    class="btn btn-ghost btn-sm"
                    phx-click="toggle_connection"
                    phx-value-id={database.id}
                  >
                    Connect
                  </button>
                  <button class="btn btn-ghost btn-sm" phx-click="backup" phx-value-id={database.id}>
                    Backup
                  </button>
                  <button
                    class="btn btn-ghost btn-sm text-error"
                    phx-click="delete"
                    phx-value-id={database.id}
                    data-confirm={"Delete #{database.name}? This destroys the data."}
                  >
                    Delete
                  </button>
                </div>
              </div>
              <div :if={@revealed_database_id == database.id} class="space-y-2 text-sm">
                <div>
                  <div class="text-xs text-base-content/60 mb-1">libSQL connection string</div>
                  <code class="block bg-base-300 rounded p-2 font-mono break-all">
                    {connection_string(database)}
                  </code>
                </div>
                <div>
                  <div class="text-xs text-base-content/60 mb-1">
                    HTTP — POST with Authorization: Bearer &lt;auth_token&gt;
                  </div>
                  <code class="block bg-base-300 rounded p-2 font-mono break-all">
                    {query_url(database)}
                  </code>
                </div>
              </div>
            </div>
          </div>
          <p :if={@databases == []} class="text-center text-base-content/50 py-8">
            No databases yet — create one above.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

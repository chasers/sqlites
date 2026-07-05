defmodule SmolsqlsWeb.AccountLive.IndexTest do
  use SmolsqlsWeb.ConnCase

  import Phoenix.LiveViewTest
  import Smolsqls.Fixtures

  alias Smolsqls.ControlPlane

  defp authed_conn(conn, tenant) do
    init_test_session(conn, %{api_key: tenant.api_key})
  end

  describe "mount" do
    test "redirects to / when unauthenticated", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/account")
    end

    test "lists the tenant's default key", %{conn: conn} do
      tenant = tenant_fixture()
      {:ok, _view, html} = live(authed_conn(conn, tenant), ~p"/account")

      assert html =~ "Account API keys"
      assert html =~ "default"
    end
  end

  describe "create_key" do
    test "creates a key and shows its secret once", %{conn: conn} do
      tenant = tenant_fixture()
      {:ok, view, _html} = live(authed_conn(conn, tenant), ~p"/account")

      html =
        view
        |> form("form[phx-submit=create_key]", %{"name" => "ci"})
        |> render_submit()

      assert html =~ "ci"
      assert html =~ "sk_"
      assert length(ControlPlane.list_tenant_api_keys(tenant)) == 2
    end
  end

  describe "reveal_key" do
    test "reveals an existing key's secret", %{conn: conn} do
      tenant = tenant_fixture()
      [key] = ControlPlane.list_tenant_api_keys(tenant)
      {:ok, view, html} = live(authed_conn(conn, tenant), ~p"/account")

      refute html =~ "sk_"

      html = render_click(view, "reveal_key", %{"key-id" => key.id})
      assert html =~ "sk_"
    end
  end

  describe "last-key lockout guard" do
    test "refuses to disable the only active key", %{conn: conn} do
      tenant = tenant_fixture()
      [key] = ControlPlane.list_tenant_api_keys(tenant)
      {:ok, view, _html} = live(authed_conn(conn, tenant), ~p"/account")

      html = render_click(view, "toggle_key", %{"key-id" => key.id})

      assert html =~ "Create another key"
      assert [%{enabled: true}] = ControlPlane.list_tenant_api_keys(tenant)
    end

    test "refuses to delete the only active key", %{conn: conn} do
      tenant = tenant_fixture()
      [key] = ControlPlane.list_tenant_api_keys(tenant)
      {:ok, view, _html} = live(authed_conn(conn, tenant), ~p"/account")

      html = render_click(view, "delete_key", %{"key-id" => key.id})

      assert html =~ "Create another key"
      assert length(ControlPlane.list_tenant_api_keys(tenant)) == 1
    end

    test "allows disable and delete once a second key exists", %{conn: conn} do
      tenant = tenant_fixture()
      [first] = ControlPlane.list_tenant_api_keys(tenant)
      {:ok, second} = ControlPlane.create_tenant_api_key(tenant, %{"name" => "second"})
      {:ok, view, _html} = live(authed_conn(conn, tenant), ~p"/account")

      render_click(view, "toggle_key", %{"key-id" => first.id})
      assert %{enabled: false} = ControlPlane.get_tenant_api_key(tenant, first.id)

      render_click(view, "toggle_key", %{"key-id" => first.id})
      assert %{enabled: true} = ControlPlane.get_tenant_api_key(tenant, first.id)

      render_click(view, "delete_key", %{"key-id" => second.id})
      assert length(ControlPlane.list_tenant_api_keys(tenant)) == 1
    end
  end
end

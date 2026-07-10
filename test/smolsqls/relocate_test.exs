defmodule Smolsqls.RelocateTest do
  use Smolsqls.DataCase

  import Smolsqls.Fixtures

  alias Smolsqls.ControlPlane
  alias Smolsqls.ControlPlane.Database
  alias Smolsqls.DataPlane

  @region "gcp-us-central1"
  @other_region "gcp-europe-west1"

  setup do
    Application.put_env(:smolsqls, :regions, [@region, @other_region])
    Application.put_env(:smolsqls, :default_region, @region)

    on_exit(fn ->
      Application.put_env(:smolsqls, :regions, [])
      Application.put_env(:smolsqls, :default_region, nil)
    end)

    :ok
  end

  describe "relocate_database/2 guards" do
    test "no-op when the region is unchanged" do
      tenant = tenant_fixture()
      db = database_fixture(tenant, %{"region" => @region})

      assert Smolsqls.relocate_database(db, @region) == {:ok, db}
    end

    test "rejects an unsupported region" do
      tenant = tenant_fixture()
      db = database_fixture(tenant, %{"region" => @region})

      assert Smolsqls.relocate_database(db, "mars-central1") == {:error, :unsupported_region}
    end

    test "rejects when the region system is dormant" do
      tenant = tenant_fixture()
      db = database_fixture(tenant, %{"region" => @region})
      Application.put_env(:smolsqls, :regions, [])

      assert Smolsqls.relocate_database(db, @other_region) == {:error, :regions_not_configured}
    end

    test "rejects when no live node serves the target region" do
      {:ok, _} = ControlPlane.upsert_node(to_string(Node.self()), @region)
      tenant = tenant_fixture()
      db = database_fixture(tenant, %{"region" => @region})

      assert Smolsqls.relocate_database(db, @other_region) ==
               {:error, :no_capacity_in_region}
    end
  end

  describe ":moving fence" do
    test "activation is refused while a database is moving" do
      moving = %Database{id: Ecto.UUID.generate(), status: :moving, file_path: "/tmp/x.db"}

      assert DataPlane.activate_database(moving) == {:error, :database_relocating}
    end

    test "mark_moving/1 fences, revert_moving/1 clears it" do
      tenant = tenant_fixture()
      db = database_fixture(tenant, %{"region" => @region})

      {:ok, moving} = ControlPlane.mark_moving(db)
      assert moving.status == :moving

      assert DataPlane.activate_database(%{moving | file_path: "/tmp/x.db"}) ==
               {:error, :database_relocating}

      {:ok, reverted} = ControlPlane.revert_moving(moving)
      assert reverted.status == :active
    end
  end

  describe "move_database/3" do
    test "flips region, cloud, and node and clears the fence" do
      tenant = tenant_fixture()
      db = database_fixture(tenant, %{"region" => @region})
      {:ok, moving} = ControlPlane.mark_moving(db)

      {:ok, moved} = ControlPlane.move_database(moving, @other_region, :smolsqls@other)

      assert moved.region == @other_region
      assert moved.cloud == "gcp"
      assert moved.node == "smolsqls@other"
      assert moved.status == :active
    end

    test "rejects a move to an unsupported region at the changeset" do
      tenant = tenant_fixture()
      db = database_fixture(tenant, %{"region" => @region})

      assert {:error, changeset} = ControlPlane.move_database(db, "mars-central1", :smolsqls@x)
      assert %{region: _} = errors_on(changeset)
    end
  end
end

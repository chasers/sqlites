defmodule Smolsqls.ReadModel.PgoutputTest do
  use ExUnit.Case, async: true

  alias Smolsqls.ReadModel.Pgoutput

  defp relation_message(id, name, columns) do
    header = <<?R, id::32, "public", 0, name::binary, 0, ?d, length(columns)::16>>

    cols =
      for col <- columns, into: <<>> do
        <<0::8, col::binary, 0, 25::32, -1::signed-32>>
      end

    header <> cols
  end

  defp tuple_data(values) do
    cols =
      for value <- values, into: <<>> do
        case value do
          nil -> <<?n>>
          value -> <<?t, byte_size(value)::32, value::binary>>
        end
      end

    <<length(values)::16>> <> cols
  end

  test "relation registration then insert decodes to a column map" do
    {:skip, relations} = Pgoutput.decode(relation_message(1, "databases", ["id", "name"]), %{})

    insert = <<?I, 1::32, ?N>> <> tuple_data(["abc", "mydb"])
    {{:insert, "databases", values}, _} = Pgoutput.decode(insert, relations)

    assert values == %{"id" => "abc", "name" => "mydb"}
  end

  test "null columns decode to nil" do
    {:skip, relations} = Pgoutput.decode(relation_message(2, "databases", ["id", "node"]), %{})

    insert = <<?I, 2::32, ?N>> <> tuple_data(["abc", nil])
    {{:insert, _, values}, _} = Pgoutput.decode(insert, relations)

    assert values == %{"id" => "abc", "node" => nil}
  end

  test "update skips the old tuple and decodes the new one" do
    {:skip, relations} = Pgoutput.decode(relation_message(3, "tenants", ["id", "name"]), %{})

    update =
      <<?U, 3::32, ?K>> <>
        tuple_data(["abc", nil]) <> <<?N>> <> tuple_data(["abc", "renamed"])

    {{:update, "tenants", values}, _} = Pgoutput.decode(update, relations)
    assert values == %{"id" => "abc", "name" => "renamed"}
  end

  test "delete decodes the key tuple" do
    {:skip, relations} = Pgoutput.decode(relation_message(4, "databases", ["id", "name"]), %{})

    delete = <<?D, 4::32, ?K>> <> tuple_data(["abc", nil])
    {{:delete, "databases", values}, _} = Pgoutput.decode(delete, relations)

    assert values["id"] == "abc"
  end

  test "begin, commit, and unknown messages" do
    assert {:begin, %{}} = Pgoutput.decode(<<?B, 0::64, 0::64, 0::32>>, %{})
    assert {{:commit, 42}, %{}} = Pgoutput.decode(<<?C, 0::8, 0::64, 42::64, 0::64>>, %{})
    assert {:skip, %{}} = Pgoutput.decode(<<?Y, "whatever">>, %{})
  end

  test "truncate resolves relation names" do
    {:skip, relations} = Pgoutput.decode(relation_message(5, "databases", ["id"]), %{})

    truncate = <<?T, 1::32, 0::8, 5::32>>
    {{:truncate, ["databases"]}, _} = Pgoutput.decode(truncate, relations)
  end
end

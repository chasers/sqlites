defmodule Sqlites.ReadModel.Pgoutput do
  @moduledoc """
  Minimal decoder for the pgoutput logical replication protocol
  (proto_version 1) — just what the read model feed needs: relation
  registration, insert/update/delete tuples decoded to column-name
  maps of text values, and truncate. Begin/commit/origin/type messages
  are surfaced or skipped.
  """

  @type relations :: %{optional(integer()) => %{name: String.t(), columns: [String.t()]}}
  @type event ::
          :begin
          | {:commit, end_lsn :: integer()}
          | {:insert, String.t(), map()}
          | {:update, String.t(), map()}
          | {:delete, String.t(), map()}
          | {:truncate, [String.t()]}
          | :skip

  @spec decode(binary(), relations()) :: {event(), relations()}
  def decode(<<?B, _final_lsn::64, _ts::64, _xid::32>>, relations) do
    {:begin, relations}
  end

  def decode(<<?C, _flags::8, _commit_lsn::64, end_lsn::64, _ts::64>>, relations) do
    {{:commit, end_lsn}, relations}
  end

  def decode(<<?R, id::32, rest::binary>>, relations) do
    {_namespace, rest} = cstring(rest)
    {name, rest} = cstring(rest)
    <<_replident::8, ncols::16, rest::binary>> = rest
    columns = decode_relation_columns(rest, ncols, [])
    {:skip, Map.put(relations, id, %{name: name, columns: columns})}
  end

  def decode(<<?I, relation_id::32, ?N, tuple::binary>>, relations) do
    relation = Map.fetch!(relations, relation_id)
    {{:insert, relation.name, decode_tuple(tuple, relation.columns)}, relations}
  end

  def decode(<<?U, relation_id::32, rest::binary>>, relations) do
    relation = Map.fetch!(relations, relation_id)
    new_tuple = skip_to_new_tuple(rest)
    {{:update, relation.name, decode_tuple(new_tuple, relation.columns)}, relations}
  end

  def decode(<<?D, relation_id::32, kind, tuple::binary>>, relations) when kind in [?K, ?O] do
    relation = Map.fetch!(relations, relation_id)
    {{:delete, relation.name, decode_tuple(tuple, relation.columns)}, relations}
  end

  def decode(<<?T, ncols::32, _flags::8, rest::binary>>, relations) do
    ids = for <<id::32 <- rest>>, do: id

    names =
      ids
      |> Enum.take(ncols)
      |> Enum.map(&get_in(relations, [&1, :name]))
      |> Enum.reject(&is_nil/1)

    {{:truncate, names}, relations}
  end

  def decode(_message, relations), do: {:skip, relations}

  defp decode_relation_columns(_rest, 0, acc), do: Enum.reverse(acc)

  defp decode_relation_columns(<<_flags::8, rest::binary>>, n, acc) do
    {name, rest} = cstring(rest)
    <<_type_oid::32, _typmod::32, rest::binary>> = rest
    decode_relation_columns(rest, n - 1, [name | acc])
  end

  defp skip_to_new_tuple(<<?N, tuple::binary>>), do: tuple

  defp skip_to_new_tuple(<<kind, ncols::16, rest::binary>>) when kind in [?K, ?O] do
    rest |> skip_tuple_columns(ncols) |> skip_to_new_tuple()
  end

  defp skip_tuple_columns(rest, 0), do: rest

  defp skip_tuple_columns(<<?n, rest::binary>>, n), do: skip_tuple_columns(rest, n - 1)
  defp skip_tuple_columns(<<?u, rest::binary>>, n), do: skip_tuple_columns(rest, n - 1)

  defp skip_tuple_columns(<<?t, len::32, _value::binary-size(len), rest::binary>>, n) do
    skip_tuple_columns(rest, n - 1)
  end

  defp decode_tuple(<<ncols::16, rest::binary>>, columns) do
    {values, _rest} = decode_tuple_columns(rest, ncols, [])

    columns
    |> Enum.zip(values)
    |> Map.new()
  end

  defp decode_tuple_columns(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp decode_tuple_columns(<<?n, rest::binary>>, n, acc),
    do: decode_tuple_columns(rest, n - 1, [nil | acc])

  defp decode_tuple_columns(<<?u, rest::binary>>, n, acc),
    do: decode_tuple_columns(rest, n - 1, [:unchanged | acc])

  defp decode_tuple_columns(<<?t, len::32, value::binary-size(len), rest::binary>>, n, acc) do
    decode_tuple_columns(rest, n - 1, [value | acc])
  end

  defp cstring(binary) do
    [string, rest] = :binary.split(binary, <<0>>)
    {string, rest}
  end
end

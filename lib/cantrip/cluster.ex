defmodule Cantrip.Cluster do
  @moduledoc """
  Helpers for explicit BEAM-cluster setup.

  Cantrip does not perform cluster discovery. Operators still use the normal
  BEAM tools (`--name` / `--sname`, cookies, `Node.connect/1`, libcluster,
  Kubernetes headless services, etc.). This module covers the Cantrip-specific
  handoff once nodes are connected: make Mnesia aware of extra DB nodes and
  replicate loom tables across them.
  """

  @type copy_type :: :disc_copies | :ram_copies

  @doc """
  Connects Mnesia to already-connected DB nodes.

  Returns `{:ok, connected_nodes}` using Mnesia's
  `change_config(:extra_db_nodes, nodes)` result. This intentionally does not
  discover or connect distributed Erlang nodes; do that before calling this.
  """
  @spec connect_mnesia([node()], keyword()) :: {:ok, [node()]} | {:error, term()}
  def connect_mnesia(nodes, opts \\ []) when is_list(nodes) do
    mnesia = Keyword.get(opts, :mnesia, :mnesia)
    timeout = Keyword.get(opts, :timeout, 5_000)
    nodes = nodes |> Enum.reject(&(&1 in [nil, node()])) |> Enum.uniq()

    with {:ok, connected} <- change_extra_db_nodes(mnesia, nodes),
         :ok <- wait_for_schema(mnesia, connected, timeout) do
      {:ok, connected}
    end
  end

  @doc """
  Replicates a Mnesia loom table to the given nodes.

  The local node is converted to `copy_type` via
  `change_table_copy_type/3`; remote nodes are added via
  `add_table_copy/3`. Existing copies are treated as success.
  """
  @spec replicate_table(atom(), [node()], keyword()) :: :ok | {:error, term()}
  def replicate_table(table, nodes, opts \\ []) when is_atom(table) and is_list(nodes) do
    mnesia = Keyword.get(opts, :mnesia, :mnesia)
    copy_type = Keyword.get(opts, :copy_type, :disc_copies)
    timeout = Keyword.get(opts, :timeout, 5_000)
    nodes = [node() | nodes] |> Enum.reject(&is_nil/1) |> Enum.uniq()

    with :ok <- validate_copy_type(copy_type),
         :ok <- ensure_local_copy_type(mnesia, table, copy_type),
         :ok <- add_remote_copies(mnesia, table, nodes -- [node()], copy_type),
         :ok <- call(mnesia, :wait_for_tables, [[table], timeout]) do
      :ok
    end
  end

  defp change_extra_db_nodes(_mnesia, []), do: {:ok, []}

  defp change_extra_db_nodes(mnesia, nodes) do
    case call(mnesia, :change_config, [:extra_db_nodes, nodes]) do
      {:ok, connected} -> {:ok, connected}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp wait_for_schema(_mnesia, [], _timeout), do: :ok

  defp wait_for_schema(mnesia, _nodes, timeout) do
    case call(mnesia, :wait_for_tables, [[:schema], timeout]) do
      :ok -> :ok
      {:timeout, bad_tables} -> {:error, {:timeout, bad_tables}}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp ensure_local_copy_type(mnesia, table, copy_type) do
    case call(mnesia, :change_table_copy_type, [table, node(), copy_type]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, ^table, _node}} -> :ok
      {:aborted, {:already_exists, ^table, _node, ^copy_type}} -> :ok
      {:aborted, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp add_remote_copies(mnesia, table, nodes, copy_type) do
    Enum.reduce_while(nodes, :ok, fn remote_node, :ok ->
      case call(mnesia, :add_table_copy, [table, remote_node, copy_type]) do
        {:atomic, :ok} -> {:cont, :ok}
        {:aborted, {:already_exists, ^table, ^remote_node}} -> {:cont, :ok}
        {:aborted, {:already_exists, ^table, ^remote_node, ^copy_type}} -> {:cont, :ok}
        {:aborted, reason} -> {:halt, {:error, reason}}
        other -> {:halt, {:error, other}}
      end
    end)
  end

  defp validate_copy_type(type) when type in [:disc_copies, :ram_copies], do: :ok
  defp validate_copy_type(type), do: {:error, {:invalid_copy_type, type}}

  defp call(mnesia, function, args), do: apply(mnesia, function, args)
end

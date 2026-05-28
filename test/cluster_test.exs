defmodule Cantrip.ClusterTest do
  use ExUnit.Case, async: true

  defmodule FakeMnesia do
    def change_config(:extra_db_nodes, nodes), do: {:ok, nodes}
    def wait_for_tables(_tables, _timeout), do: :ok
    def change_table_copy_type(_table, _node, _copy_type), do: {:atomic, :ok}
    def add_table_copy(_table, _node, _copy_type), do: {:atomic, :ok}
  end

  defmodule ExistingCopyMnesia do
    def change_config(:extra_db_nodes, nodes), do: {:ok, nodes}
    def wait_for_tables(_tables, _timeout), do: :ok

    def change_table_copy_type(table, _node, _copy_type),
      do: {:aborted, {:already_exists, table, node()}}

    def add_table_copy(table, node, _copy_type), do: {:aborted, {:already_exists, table, node}}
  end

  defmodule TimeoutSchemaMnesia do
    def change_config(:extra_db_nodes, nodes), do: {:ok, nodes}
    def wait_for_tables(_tables, _timeout), do: {:timeout, [:schema]}
  end

  test "connect_mnesia joins extra db nodes and waits for schema" do
    assert {:ok, [:"agents@host-b"]} =
             Cantrip.Cluster.connect_mnesia([:"agents@host-b"], mnesia: FakeMnesia)
  end

  test "replicate_table configures local and remote table copies" do
    assert :ok =
             Cantrip.Cluster.replicate_table(:cantrip_loom, [:"agents@host-b"],
               mnesia: FakeMnesia,
               copy_type: :disc_copies
             )
  end

  test "replicate_table treats existing copies as success" do
    assert :ok =
             Cantrip.Cluster.replicate_table(:cantrip_loom, [:"agents@host-b"],
               mnesia: ExistingCopyMnesia,
               copy_type: :disc_copies
             )
  end

  test "replicate_table rejects unsupported copy types" do
    assert {:error, {:invalid_copy_type, :unknown}} =
             Cantrip.Cluster.replicate_table(:cantrip_loom, [], copy_type: :unknown)
  end

  test "connect_mnesia preserves schema timeout details" do
    assert {:error, {:timeout, [:schema]}} =
             Cantrip.Cluster.connect_mnesia([:"agents@host-b"], mnesia: TimeoutSchemaMnesia)
  end
end

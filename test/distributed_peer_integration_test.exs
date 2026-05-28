defmodule Cantrip.DistributedPeerIntegrationTest do
  use ExUnit.Case, async: false

  alias Cantrip.FakeLLM
  alias Cantrip.Test.SleepingLLM

  @moduletag :integration
  @moduletag timeout: :timer.seconds(20)

  setup do
    previous_timeout = Application.get_env(:cantrip, :rpc_timeout)

    on_exit(fn ->
      if previous_timeout do
        Application.put_env(:cantrip, :rpc_timeout, previous_timeout)
      else
        Application.delete_env(:cantrip, :rpc_timeout)
      end
    end)

    :ok
  end

  test "remote new/cast works on a real peer and remote timeout does not hang caller" do
    with :ok <- ensure_distributed(),
         {:ok, peer_pid, peer_node} <- start_peer() do
      on_exit(fn -> stop_peer(peer_pid) end)

      assert {:module, Cantrip} = :rpc.call(peer_node, :code, :ensure_loaded, [Cantrip], 5_000)

      assert {:ok, _apps} =
               :rpc.call(peer_node, Application, :ensure_all_started, [:cantrip], 5_000)

      {:ok, cantrip} =
        Cantrip.new(
          node: peer_node,
          llm: {FakeLLM, FakeLLM.new([%{content: "peer ok"}])},
          identity: %{system_prompt: "Answer directly."},
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 1}]}
        )

      assert cantrip.node == peer_node
      assert {:ok, "peer ok", next, _loom, meta} = Cantrip.cast(cantrip, "say ok")
      assert next.node == peer_node
      assert meta.terminated

      Application.put_env(:cantrip, :rpc_timeout, 100)

      {:ok, slow} =
        Cantrip.new(
          node: peer_node,
          llm: {SleepingLLM, %{sleep_ms: 5_000}},
          identity: %{system_prompt: "Sleep."},
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 1}]}
        )

      started_at = System.monotonic_time(:millisecond)
      assert {:error, message, returned} = Cantrip.cast(slow, "hang")
      elapsed_ms = System.monotonic_time(:millisecond) - started_at

      assert elapsed_ms < 2_000
      assert returned.node == peer_node
      assert message =~ ":timeout"
    else
      {:skip, reason} ->
        IO.puts("Skipping distributed peer integration test: #{inspect(reason)}")
        assert true
    end
  end

  defp ensure_distributed do
    if Node.alive?() do
      :ok
    else
      name = :"cantrip_test_#{System.unique_integer([:positive])}@127.0.0.1"

      case :net_kernel.start([name, :longnames]) do
        {:ok, _pid} -> :ok
        {:error, reason} -> {:skip, reason}
      end
    end
  end

  defp start_peer do
    peer_node = :"cantrip_peer_#{System.unique_integer([:positive])}@127.0.0.1"
    args = Enum.flat_map(:code.get_path(), fn path -> [~c"-pa", path] end)

    case :peer.start_link(%{name: peer_node, connection: :standard_io, args: args}) do
      {:ok, pid, node} -> {:ok, pid, node}
      {:error, reason} -> {:skip, reason}
    end
  end

  defp stop_peer(pid) do
    :peer.stop(pid)
  catch
    :exit, _reason -> :ok
  end
end

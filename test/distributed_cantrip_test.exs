defmodule Cantrip.DistributedCantripTest do
  use ExUnit.Case, async: false

  alias Cantrip.FakeLLM

  defmodule FakeRPC do
    def call(node, module, function, args, timeout) do
      send(Process.whereis(__MODULE__), {:rpc_call, node, module, function, args, timeout})
      apply(module, function, args)
    end
  end

  defmodule BadRPC do
    def call(_node, _module, _function, _args, _timeout), do: {:badrpc, :timeout}
  end

  setup do
    Process.register(self(), FakeRPC)
    previous = Application.get_env(:cantrip, :rpc_module)
    previous_timeout = Application.get_env(:cantrip, :rpc_timeout)
    Application.put_env(:cantrip, :rpc_module, FakeRPC)

    on_exit(fn ->
      if previous do
        Application.put_env(:cantrip, :rpc_module, previous)
      else
        Application.delete_env(:cantrip, :rpc_module)
      end

      if previous_timeout do
        Application.put_env(:cantrip, :rpc_timeout, previous_timeout)
      else
        Application.delete_env(:cantrip, :rpc_timeout)
      end

      if Process.whereis(FakeRPC) == self(), do: Process.unregister(FakeRPC)
    end)

    :ok
  end

  test "Cantrip.new builds remote root cantrips through rpc and tags the handle" do
    remote = :"agents@127.0.0.1"

    assert {:ok, cantrip} =
             Cantrip.new(
               node: remote,
               llm: {FakeLLM, FakeLLM.new([%{content: "hello"}])},
               identity: %{system_prompt: "Answer directly."},
               circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 1}]}
             )

    assert cantrip.node == remote
    assert_receive {:rpc_call, ^remote, Cantrip, :__remote_new__, [attrs], 30_000}
    refute Map.has_key?(attrs, :node)
  end

  test "remote calls use configured rpc timeout and surface badrpc timeout" do
    remote = :"agents@127.0.0.1"
    Application.put_env(:cantrip, :rpc_module, BadRPC)
    Application.put_env(:cantrip, :rpc_timeout, 250)

    assert {:error, message} =
             Cantrip.new(
               node: remote,
               llm: {FakeLLM, FakeLLM.new([%{content: "hello"}])},
               identity: %{system_prompt: "Answer directly."},
               circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 1}]}
             )

    assert message =~ "failed to build cantrip"
    assert message =~ ":timeout"
  end

  test "unknown string node fails closed instead of falling back to local execution" do
    assert {:error, message} =
             Cantrip.new(%{
               "node" => "definitely-not-connected@127.0.0.1",
               llm: {FakeLLM, FakeLLM.new([%{content: "hello"}])},
               identity: %{system_prompt: "Answer directly."},
               circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 1}]}
             })

    assert message =~ "unknown remote node"
    assert message =~ "definitely-not-connected@127.0.0.1"
  end

  test "Cantrip.cast runs remote handles through rpc and preserves remote node on next handle" do
    remote = :"agents@127.0.0.1"

    {:ok, cantrip} =
      Cantrip.new(
        node: remote,
        llm: {FakeLLM, FakeLLM.new([%{content: "hello"}])},
        identity: %{system_prompt: "Answer directly."},
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 1}]}
      )

    assert {:ok, "hello", next, loom, meta} = Cantrip.cast(cantrip, "say hello")

    assert next.node == remote
    assert meta.terminated
    assert length(loom.turns) == 1

    assert_receive {:rpc_call, ^remote, Cantrip, :__remote_cast__,
                    [_remote_cantrip, "say hello", _opts], 30_000}
  end

  test "remote child casts still graft child turns into the local parent observation" do
    remote = :"agents@127.0.0.1"
    {:ok, collector} = Agent.start_link(fn -> [] end)

    parent_llm = {FakeLLM, FakeLLM.new([%{content: "parent"}])}

    {:ok, parent} =
      Cantrip.new(
        llm: parent_llm,
        identity: %{system_prompt: "Parent"},
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 2}]}
      )

    parent_context =
      parent
      |> Cantrip.parent_context()
      |> Map.put(:observation_collector, collector)

    {:ok, child} =
      Cantrip.new(%{
        node: remote,
        parent_context: parent_context,
        llm: {FakeLLM, FakeLLM.new([%{content: "remote child"}])},
        identity: %{system_prompt: "Child"},
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 1}]}
      })

    assert child.node == remote

    assert {:ok, "remote child", next, child_loom, _meta} =
             Cantrip.cast(child, "work", parent_context: parent_context)

    assert next.node == remote

    assert [%{gate: "cast", result: "remote child", is_error: false, child_turns: turns}] =
             Agent.get(collector, & &1)

    assert turns == child_loom.turns
  end

  test "Familiar code can place a child cantrip on a remote node" do
    remote = :"agents@127.0.0.1"

    parent_code = """
    child_llm = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{content: "from remote"}])}

    {:ok, child} = Cantrip.new(%{
      node: #{inspect(remote)},
      llm: child_llm,
      identity: %{system_prompt: "Answer directly."},
      circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 1}]}
    })

    {:ok, result, _child, _loom, _meta} = Cantrip.cast(child, "work")
    done.(result)
    """

    parent_llm = {FakeLLM, FakeLLM.new([%{code: parent_code}])}
    {:ok, familiar} = Cantrip.Familiar.new(llm: parent_llm)

    assert {:ok, "from remote", _next, loom, _meta} = Cantrip.cast(familiar, "delegate remotely")

    assert_receive {:rpc_call, ^remote, Cantrip, :__remote_new__, [_attrs], 30_000}

    assert_receive {:rpc_call, ^remote, Cantrip, :__remote_cast__,
                    [_remote_cantrip, "work", _opts], 30_000}

    assert Enum.any?(loom.turns, fn turn ->
             turn.cantrip_id != List.first(loom.turns).cantrip_id
           end)
  end
end

defmodule Cantrip.InterruptSteerTest do
  use ExUnit.Case, async: true

  alias Cantrip.ACP.AgentHandler

  defmodule BlockingScriptLLM do
    @behaviour Cantrip.LLM

    @impl true
    def query(%{test_pid: test_pid, responses: [response | rest]} = state, request) do
      content = request.messages |> List.last() |> Map.fetch!(:content)
      send(test_pid, {:blocking_script_llm_started, self(), content, request.messages})

      receive do
        {:release_blocking_script_llm, ^content} ->
          {:ok, response(response), %{state | responses: rest}}
      after
        1_000 ->
          {:error, %{message: "blocking script llm was not released"}, state}
      end
    end

    defp response(%Cantrip.LLM.Response{} = response), do: response

    defp response(%{code: code} = attrs) when is_binary(code) do
      attrs
      |> Map.delete(:code)
      |> Map.put(:tool_calls, [%{id: "tc_script", gate: "elixir", args: %{"code" => code}}])
      |> response()
    end

    defp response(attrs) when is_map(attrs) do
      %Cantrip.LLM.Response{
        content: Map.get(attrs, :content),
        tool_calls: Map.get(attrs, :tool_calls, []),
        usage: %{}
      }
    end
  end

  defmodule FamiliarRuntimeFromProcess do
    @behaviour Cantrip.ACP.Runtime

    @impl true
    def new_session(params) do
      params =
        case Process.get(:interrupt_steer_test_llm) do
          nil -> params
          llm -> Map.put(params, "llm", llm)
        end

      Cantrip.ACP.Runtime.Familiar.new_session(params)
    end

    @impl true
    def prepare_prompt(session), do: Cantrip.ACP.Runtime.Familiar.prepare_prompt(session)

    @impl true
    def prompt(session, text), do: Cantrip.ACP.Runtime.Familiar.prompt(session, text)

    @impl true
    def cancel(session), do: Cantrip.ACP.Runtime.Familiar.cancel(session)
  end

  defmodule LifecycleStorage do
    @behaviour Cantrip.Loom.Storage

    @impl true
    def init(opts) do
      opts = Map.new(opts)
      path = Map.fetch!(opts, :path)
      lifecycle_path = Map.fetch!(opts, :lifecycle_path)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "", [:append])
      File.write!(lifecycle_path, "", [:append])
      {:ok, %{path: path, lifecycle_path: lifecycle_path}}
    end

    @impl true
    def append_event(%{path: path} = state, event) do
      encoded = event |> :erlang.term_to_binary() |> Base.encode64()
      File.write!(path, encoded <> "\n", [:append])
      {:ok, state}
    end

    @impl true
    def append_turn(state, turn), do: append_event(state, %{type: :turn, turn: turn})

    @impl true
    def annotate_reward(state, index, reward) do
      append_event(state, %{type: :reward, index: index, reward: reward})
    end

    @impl true
    def load(_state), do: {:ok, %{events: [], turns: []}}

    @impl true
    def flush(%{lifecycle_path: lifecycle_path} = state) do
      File.write!(lifecycle_path, "flush\n", [:append])
      {:ok, state}
    end

    @impl true
    def close(%{lifecycle_path: lifecycle_path}) do
      File.write!(lifecycle_path, "close\n", [:append])
      :ok
    end
  end

  test "interrupt stops the active episode at the next turn boundary and records loom events" do
    {:ok, cantrip} = code_cantrip([%{code: "x = 1"}])
    {:ok, pid} = Cantrip.summon(cantrip)

    task = Task.async(fn -> Cantrip.send(pid, "slow") end)
    assert_receive {:blocking_script_llm_started, llm_pid, "slow", _messages}, 1_000

    assert :ok = Cantrip.interrupt(pid)
    send(llm_pid, {:release_blocking_script_llm, "slow"})

    assert {:error, :interrupted, next_cantrip} = Task.await(task, 5_000)
    state = :sys.get_state(pid)

    assert next_cantrip.id == state.cantrip.id
    assert Enum.any?(state.loom.events, &match?(%{type: :interrupt_requested}, &1))
    assert Enum.any?(state.loom.events, &match?(%{type: :interrupted}, &1))
  end

  test "steer injects a message at the next turn boundary without killing the run" do
    {:ok, cantrip} =
      code_cantrip([
        %{code: "x = 1"},
        %{code: ~s|done.("steered")|}
      ])

    {:ok, pid} = Cantrip.summon(cantrip)
    task = Task.async(fn -> Cantrip.send(pid, "first") end)

    assert_receive {:blocking_script_llm_started, llm_pid, "first", _messages}, 1_000
    assert :ok = Cantrip.steer(pid, "change course")
    send(llm_pid, {:release_blocking_script_llm, "first"})

    assert_receive {:blocking_script_llm_started, llm_pid2, "change course", messages}, 5_000
    assert List.last(messages) == %{role: :user, content: "change course"}
    send(llm_pid2, {:release_blocking_script_llm, "change course"})

    assert {:ok, "steered", _next, loom, _meta} = Task.await(task, 5_000)
    assert Enum.any?(loom.events, &match?(%{type: :steer_queued}, &1))
    assert Enum.any?(loom.events, &match?(%{type: :steer_delivered}, &1))
    assert Enum.any?(loom.intents, &(&1.utterance.content == "change course"))
  end

  test "mid-turn sends queue and run in order at episode boundaries" do
    {:ok, cantrip} =
      conversation_cantrip([
        %{tool_calls: [%{gate: "done", args: %{answer: "one"}}]},
        %{tool_calls: [%{gate: "done", args: %{answer: "two"}}]}
      ])

    {:ok, pid} = Cantrip.summon(cantrip)
    first = Task.async(fn -> Cantrip.send(pid, "first") end)

    assert_receive {:blocking_script_llm_started, llm_pid, "first", _messages}, 1_000

    second = Task.async(fn -> Cantrip.send(pid, "second") end)
    refute Task.yield(second, 50)

    send(llm_pid, {:release_blocking_script_llm, "first"})
    assert {:ok, "one", _next, _loom, _meta} = Task.await(first, 1_000)

    assert_receive {:blocking_script_llm_started, llm_pid2, "second", _messages}, 1_000
    send(llm_pid2, {:release_blocking_script_llm, "second"})
    assert {:ok, "two", _next, loom, _meta} = Task.await(second, 1_000)

    assert Enum.any?(loom.events, &match?(%{type: :intent_queued}, &1))
    assert Enum.map(loom.intents, & &1.utterance.content) == ["first", "second"]
  end

  test "hard stop terminates immediately and closes the loom" do
    tmp = Path.join(System.tmp_dir!(), "cantrip-hard-stop-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    loom_path = Path.join(tmp, "loom.terms")
    lifecycle_path = Path.join(tmp, "lifecycle.log")

    storage = {LifecycleStorage, [path: loom_path, lifecycle_path: lifecycle_path]}

    {:ok, cantrip} =
      conversation_cantrip([%{tool_calls: [%{gate: "done", args: %{answer: "late"}}]}], storage)

    {:ok, pid} = Cantrip.summon(cantrip)

    task = Task.async(fn -> Cantrip.send(pid, "slow") end)
    assert_receive {:blocking_script_llm_started, _llm_pid, "slow", _messages}, 1_000

    assert :ok = Cantrip.hard_stop(pid)
    assert {:error, :hard_stopped, _next} = Task.await(task, 1_000)
    refute Process.alive?(pid)

    assert File.read!(lifecycle_path) == "flush\nclose\n"
    assert Enum.any?(read_terms(loom_path), &match?(%{type: :hard_stopped}, &1))
  end

  test "ACP session/cancel interrupts a Familiar prompt and returns cancelled stop reason" do
    llm = {BlockingScriptLLM, %{test_pid: self(), responses: [%{code: "x = 1"}]}}
    Process.put(:interrupt_steer_test_llm, llm)
    on_exit(fn -> Process.delete(:interrupt_steer_test_llm) end)

    table = AgentHandler.new(runtime: FamiliarRuntimeFromProcess)
    AgentHandler.handle_request(init_request(), table)

    {:ok, %ACP.NewSessionResponse{session_id: session_id}} =
      AgentHandler.handle_request({:new_session, %ACP.NewSessionRequest{cwd: "/tmp"}}, table)

    prompt =
      Task.async(fn ->
        AgentHandler.handle_request(
          {:prompt,
           %ACP.PromptRequest{
             session_id: session_id,
             prompt: [{:text, %ACP.TextContent{text: "slow"}}]
           }},
          table
        )
      end)

    assert_receive {:blocking_script_llm_started, llm_pid, "slow", _messages}, 500

    assert :ok =
             AgentHandler.handle_request(
               {:cancel, ACP.CancelNotification.new(session_id)},
               table
             )

    send(llm_pid, {:release_blocking_script_llm, "slow"})
    assert {:ok, %ACP.PromptResponse{stop_reason: :cancelled}} = Task.await(prompt, 500)
  end

  defp code_cantrip(responses, storage \\ :memory) do
    Cantrip.new(
      llm: {BlockingScriptLLM, %{test_pid: self(), responses: responses}},
      loom_storage: storage,
      circle: %{type: :code, gates: [:done], wards: [%{max_turns: 5}, %{require_done_tool: true}]}
    )
  end

  defp conversation_cantrip(responses, storage \\ :memory) do
    Cantrip.new(
      llm: {BlockingScriptLLM, %{test_pid: self(), responses: responses}},
      loom_storage: storage,
      circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 5}]}
    )
  end

  defp init_request do
    {:initialize,
     %ACP.InitializeRequest{
       protocol_version: 1,
       client_capabilities: %ACP.ClientCapabilities{},
       client_info: %{"name" => "test"}
     }}
  end

  defp read_terms(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(fn line -> line |> Base.decode64!() |> :erlang.binary_to_term() end)
  end
end

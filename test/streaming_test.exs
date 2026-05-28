defmodule Cantrip.StreamingTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  defmodule StreamingReqLLM do
    def generate_text(_model, _context, _opts), do: {:error, :sync_path_not_expected}

    def stream_text(model, context, _opts) do
      {:ok,
       %ReqLLM.StreamResponse{
         stream: [ReqLLM.StreamChunk.text("streamed "), ReqLLM.StreamChunk.text("answer")],
         metadata_handle: metadata_handle(),
         cancel: fn -> :ok end,
         model: LLMDB.Model.new!(%{provider: :anthropic, id: model}),
         context: context
       }}
    end

    defp metadata_handle do
      {:ok, handle} =
        ReqLLM.StreamResponse.MetadataHandle.start_link(fn ->
          %{usage: %{input_tokens: 5, output_tokens: 2}, finish_reason: :stop}
        end)

      handle
    end
  end

  defmodule BlockingLLM do
    @behaviour Cantrip.LLM

    @impl true
    def query(%{test_pid: test_pid} = state, _request) do
      send(test_pid, {:blocking_llm_started, self()})

      receive do
        :release_blocking_llm ->
          {:ok,
           %Cantrip.LLM.Response{
             content: nil,
             tool_calls: [%{gate: "done", args: %{answer: "released"}}],
             usage: %{}
           }, state}
      after
        5_000 ->
          {:error, %{message: "blocking llm was not released"}, state}
      end
    end
  end

  # Helper to extract event type from enveloped events
  defp event_type({_envelope, {type, _data}}), do: type
  defp event_type({type, _data}) when is_atom(type), do: type
  defp event_type(_), do: nil

  test "cast_stream emits step_start, tool events, and final_response" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "echo", args: %{text: "hi"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "finished"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    {stream, _task} = Cantrip.cast_stream(cantrip, "test streaming")

    events = Enum.to_list(stream)

    step_starts = Enum.filter(events, &(event_type(&1) == :step_start))
    assert length(step_starts) == 2

    tool_calls = Enum.filter(events, &(event_type(&1) == :tool_call))
    assert length(tool_calls) >= 2

    tool_results = Enum.filter(events, &(event_type(&1) == :tool_result))
    assert length(tool_results) >= 2

    finals = Enum.filter(events, &(event_type(&1) == :final_response))
    assert [final] = finals
    assert {_env, {:final_response, %{result: "finished"}}} = final

    last = List.last(events)
    assert {:done, {:ok, "finished", _cantrip, _loom, _meta}} = last
  end

  test "stream_to emits provider text deltas with trace_id in the event envelope" do
    trace_id = "stream-trace-#{System.unique_integer([:positive])}"

    llm =
      {Cantrip.LLMs.ReqLLM,
       %{client: StreamingReqLLM, model: "claude-test", stream: true, timeout_ms: 1_000}}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 3}]}
      )

    assert {:ok, "streamed answer", _cantrip, _loom, meta} =
             Cantrip.cast(cantrip, "stream please", trace_id: trace_id, stream_to: self())

    events = drain_cantrip_events()

    text_deltas = Enum.filter(events, &(event_type(&1) == :text_delta))

    assert [
             {%{trace_id: ^trace_id, entity_id: entity_id}, {:text_delta, "streamed "}},
             {%{trace_id: ^trace_id, entity_id: second_entity_id}, {:text_delta, "answer"}}
           ] = text_deltas

    assert second_entity_id == entity_id

    assert Enum.any?(events, fn
             {%{trace_id: ^trace_id, entity_id: ^entity_id}, {:usage, %{prompt_tokens: 5}}} ->
               true

             _ ->
               false
           end)

    assert meta.cumulative_usage.total_tokens == 7
  end

  test "cast_stream emits usage events" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
      )

    {stream, _task} = Cantrip.cast_stream(cantrip, "usage test")

    events = Enum.to_list(stream)
    usage_events = Enum.filter(events, &(event_type(&1) == :usage))
    assert usage_events != []
  end

  test "cast_stream emits step_complete with terminated flag" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
      )

    {stream, _task} = Cantrip.cast_stream(cantrip, "completion test")

    events = Enum.to_list(stream)
    step_completes = Enum.filter(events, &(event_type(&1) == :step_complete))
    assert [{_env, {:step_complete, %{terminated: true}}}] = step_completes
  end

  test "cast_stream emits a final response when max_turns truncates before done" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{code: "missing_binding"},
         %{code: "still_missing"}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 2}]}
      )

    {stream, _task} = Cantrip.cast_stream(cantrip, "trigger repeated eval errors")

    events = Enum.to_list(stream)

    finals = Enum.filter(events, &(event_type(&1) == :final_response))
    assert [{_env, {:final_response, %{result: result}}}] = finals
    assert result =~ "max_turns limit (2)"
    assert result =~ "Last eval error"

    last = List.last(events)
    assert {:done, {:ok, nil, _cantrip, _loom, meta}} = last
    assert meta.truncated
    assert meta.truncation_reason == "max_turns"
  end

  test "cast_stream applies backpressure before the caller starts consuming" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
      )

    flush_mailbox()
    {stream, task} = Cantrip.cast_stream(cantrip, "wait for consumer")

    Process.sleep(50)

    assert Process.alive?(task.pid)
    assert {:message_queue_len, queue_len} = Process.info(self(), :message_queue_len)
    assert queue_len <= 2

    assert {:done, {:ok, "ok", _cantrip, _loom, _meta}} = stream |> Enum.to_list() |> List.last()
  end

  test "closing cast_stream early shuts down the running task" do
    {:ok, cantrip} =
      Cantrip.new(
        llm: {BlockingLLM, %{test_pid: self()}},
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 10}]}
      )

    {stream, task} = Cantrip.cast_stream(cantrip, "start and stop")
    ref = Process.monitor(task.pid)

    assert [_first_event] = Enum.take(stream, 1)
    assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 500
  end

  defp drain_cantrip_events(acc \\ []) do
    receive do
      {:cantrip_event, event} -> drain_cantrip_events([event | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end

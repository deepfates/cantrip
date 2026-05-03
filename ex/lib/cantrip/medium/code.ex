defmodule Cantrip.Medium.Code do
  @moduledoc """
  Code medium boundary.

  This adapter delegates to the existing code evaluators while giving the
  runtime a behaviour-shaped target. It is a thin layer by design: the spike is
  about making the boundary visible before moving orchestration code.
  """

  @behaviour Cantrip.Medium

  @impl true
  def present(circle, _state) do
    %{
      tools: elixir_tools(),
      tool_choice: "required",
      capability_text: capability_text(circle)
    }
  end

  @spec capability_text(Cantrip.Circle.t()) :: String.t()
  def capability_text(%Cantrip.Circle{gates: gates} = circle) do
    gate_lines =
      circle
      |> Cantrip.Gate.names()
      |> Enum.map(fn name -> format_gate_description(name, Map.get(gates, name, %{})) end)
      |> Enum.join("\n")

    """
    You write Elixir code that executes in a persistent sandbox. \
    Respond ONLY with the elixir tool containing valid Elixir code. \
    Do not write prose or markdown.

    CRITICAL: NEVER use defmodule. Module definitions create a new scope \
    where host function bindings are invisible, causing "undefined variable" errors. \
    Write ALL code at the top level as a script. Use anonymous functions if you need helpers:

      summarize = fn text -> String.split(text, "\\n") |> length() end
      result = summarize.(data)
      done.(result)

    Available host functions (closure bindings, top-level only):
    #{gate_lines}

    Variables persist across turns. Store intermediate data in variables.
    Call done.(result) with your final answer when finished.
    Your done() result is what the caller sees - make it concise and informative.\
    """
  end

  @impl true
  def execute(code, state, %{circle: circle} = runtime) when is_binary(code) do
    {next_state, observations, result, terminated?} =
      case Cantrip.WardPolicy.sandbox(circle.wards) do
        :dune -> eval_dune(code, state, runtime)
        _ -> eval_unrestricted(code, state, runtime)
      end

    {:ok, next_state, observations, result, terminated?}
  end

  def execute(_code, state, _runtime) do
    {:error, state, [%{gate: "code", result: "code utterance must be a string", is_error: true}]}
  end

  @impl true
  def snapshot(state), do: state

  @impl true
  def restore(snapshot) when is_map(snapshot), do: snapshot
  def restore(_), do: %{}

  defp elixir_tools do
    [
      %{
        name: "elixir",
        parameters: %{
          type: "object",
          properties: %{
            code: %{type: "string", description: "Elixir code to execute in the sandbox"}
          },
          required: ["code"]
        }
      }
    ]
  end

  defp eval_dune(code, state, runtime) do
    eval_start = System.monotonic_time()

    result = Cantrip.CodeMedium.DuneSandbox.eval(code, state, runtime)
    emit_eval_stop(runtime, eval_start)
    result
  end

  defp eval_unrestricted(code, state, runtime) do
    timeout = Cantrip.WardPolicy.code_eval_timeout_ms(runtime.circle.wards)
    saved_child_llm = Map.get(state, :child_llm)
    saved_familiar_store = Map.get(state, :familiar_store)

    eval_start = System.monotonic_time()

    task =
      Task.async(fn ->
        {:ok, capture_pid} = StringIO.open("")
        Process.group_leader(self(), capture_pid)

        if saved_child_llm, do: Process.put(:cantrip_child_llm, saved_child_llm)
        if saved_familiar_store, do: Process.put(:cantrip_familiar_store, saved_familiar_store)

        result = Cantrip.CodeMedium.eval(code, state, runtime)
        child_llm = Process.get(:cantrip_child_llm)
        familiar_store = Process.get(:cantrip_familiar_store)
        {_, captured_output} = StringIO.contents(capture_pid)
        StringIO.close(capture_pid)

        {result, child_llm, familiar_store, captured_output}
      end)

    case Task.yield(task, timeout) do
      {:ok, {{next_state, obs, result, terminated}, child_llm, familiar_store, captured_output}} ->
        emit_eval_stop(runtime, eval_start)

        next_state =
          if child_llm,
            do: Map.put(next_state, :child_llm, child_llm),
            else: next_state

        next_state =
          if familiar_store && map_size(familiar_store) > 0,
            do: Map.put(next_state, :familiar_store, familiar_store),
            else: next_state

        {next_state, append_stdio(obs, captured_output), result, terminated}

      nil ->
        emit_eval_stop(runtime, eval_start)
        Task.shutdown(task, :brutal_kill)

        obs = [%{gate: "code", result: "code evaluation timed out", is_error: true}]
        {state, obs, nil, false}
    end
  catch
    :exit, reason ->
      obs = [
        %{gate: "code", result: "code evaluation crashed: #{inspect(reason)}", is_error: true}
      ]

      {state, obs, nil, false}
  end

  defp append_stdio(obs, captured) when is_binary(captured) do
    case String.trim(captured) do
      "" -> obs
      trimmed -> obs ++ [%{gate: "stdio", result: trimmed, is_error: false}]
    end
  end

  defp append_stdio(obs, _captured), do: obs

  defp emit_eval_stop(%{entity_id: entity_id}, started_at) when is_binary(entity_id) do
    duration = System.monotonic_time() - started_at
    :telemetry.execute([:cantrip, :code, :eval], %{duration: duration}, %{entity_id: entity_id})
  end

  defp emit_eval_stop(_runtime, _started_at), do: :ok

  defp format_gate_description(name, %{description: desc}) when is_binary(desc),
    do: "- #{name}.(#{gate_args_hint(name)}) - #{desc}"

  defp format_gate_description(name, %{"description" => desc}) when is_binary(desc),
    do: "- #{name}.(#{gate_args_hint(name)}) - #{desc}"

  defp format_gate_description("done", _gate),
    do: "- done.(answer) - complete the task and return the answer"

  defp format_gate_description("echo", _gate),
    do: "- echo.(opts) - echo text back"

  defp format_gate_description("call_entity", _gate),
    do: "- call_entity.(opts) - delegate to a child entity; opts must include :intent"

  defp format_gate_description("call_entity_batch", _gate),
    do: "- call_entity_batch.(list) - delegate to multiple child entities in parallel"

  defp format_gate_description("compile_and_load", _gate),
    do: "- compile_and_load.(opts) - compile and load an Elixir module"

  defp format_gate_description("read", _gate),
    do: "- read.(path) - read a file; path is relative to the working directory"

  defp format_gate_description("read_file", _gate),
    do: "- read_file.(path) - read a file; path is relative to the working directory"

  defp format_gate_description("list_dir", _gate),
    do: "- list_dir.(path) - list directory contents; path is relative to the working directory"

  defp format_gate_description("search", _gate),
    do: "- search.(opts) - search file contents; opts must include :pattern and :path"

  defp format_gate_description("cantrip", _gate),
    do: "- cantrip.(config) - construct a child cantrip; config includes :identity, :circle"

  defp format_gate_description("cast", _gate),
    do: "- cast.(cantrip_id, intent) - send an intent to a constructed child cantrip"

  defp format_gate_description("cast_batch", _gate),
    do:
      "- cast_batch.(items) - execute multiple child cantrips in parallel; items are [%{cantrip: id, intent: text}]"

  defp format_gate_description("dispose", _gate),
    do: "- dispose.(cantrip_id) - clean up a child cantrip's resources"

  defp format_gate_description(name, _gate),
    do: "- #{name}.(opts) - invoke the #{name} gate"

  defp gate_args_hint("done"), do: "answer"
  defp gate_args_hint("cast"), do: "cantrip_id, intent"
  defp gate_args_hint("cast_batch"), do: "items"
  defp gate_args_hint("dispose"), do: "cantrip_id"
  defp gate_args_hint(_), do: "opts"
end

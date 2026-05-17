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

    #{package_api_text(circle)}

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

    eval_start = System.monotonic_time()

    task =
      Task.async(fn ->
        {:ok, capture_pid} = StringIO.open("")
        Process.group_leader(self(), capture_pid)

        if saved_child_llm, do: Process.put(:cantrip_child_llm, saved_child_llm)

        result = Cantrip.CodeMedium.eval(code, state, runtime)
        child_llm = Process.get(:cantrip_child_llm)
        {_, captured_output} = StringIO.contents(capture_pid)
        StringIO.close(capture_pid)

        {result, child_llm, captured_output}
      end)

    case Task.yield(task, timeout) do
      {:ok, {{next_state, obs, result, terminated}, child_llm, captured_output}} ->
        emit_eval_stop(runtime, eval_start)

        next_state =
          if child_llm,
            do: Map.put(next_state, :child_llm, child_llm),
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

  # Capability lines come from `Cantrip.Gate.spec/1` (the single source of
  # truth for built-in metadata). A user-supplied `:description` on the gate
  # overrides the canonical text — the args hint stays per-name to keep the
  # signature readable in the prompt.
  defp format_gate_description(name, gate) do
    custom = Map.get(gate, :description) || Map.get(gate, "description")
    desc = custom || Cantrip.Gate.spec(name).description
    "- #{name}.(#{gate_args_hint(name)}) - #{desc}"
  end

  defp gate_args_hint("done"), do: "answer"
  defp gate_args_hint(_), do: "opts"

  defp package_api_text(circle) do
    case Cantrip.WardPolicy.sandbox(circle.wards) do
      :dune ->
        """
        Sandbox note: this circle is running under Dune. Remote module calls
        such as Cantrip.new/1 are restricted here; use the injected host
        closures above.
        """

      _ ->
        """
        Public package API (ordinary module calls, not closure bindings):
        - Cantrip.new(config) constructs a child cantrip and returns {:ok, child} or {:error, reason}
        - Cantrip.cast(child, intent) casts one child and returns {:ok, value, next_child, child_loom, meta} or {:error, reason, next_child}
        - Cantrip.cast_batch(items) casts children concurrently and returns {:ok, values, next_children, child_looms, meta} or {:error, reason}
        """
    end
  end
end

defmodule Cantrip.Medium.Code do
  @moduledoc false

  @behaviour Cantrip.Medium

  alias Cantrip.{Circle, Gate}

  @reserved_bindings [
    :done,
    :compile_and_load,
    :loom,
    :folded_summary
  ]

  @builtin_gate_atoms ~w(done echo read_file list_dir search compile_and_load mix)a

  @type runtime :: %{
          required(:circle) => Circle.t(),
          optional(:execute_gate) => (String.t(), map() -> map()),
          optional(:parent_context) => map(),
          optional(:compile_and_load) => (map() -> map())
        }
  @type state :: %{optional(:binding) => keyword()}

  @impl true
  def present(circle, _state) do
    %{
      tools: elixir_tools(),
      tool_choice: "required",
      capability_text: capability_text(circle)
    }
  end

  @spec capability_text(Cantrip.Circle.t()) :: String.t()
  def capability_text(%Cantrip.Circle{} = circle) do
    """
    #{medium_intro_text()}

    #{branching_text()}

    #{host_functions_text(circle)}

    #{history_text()}

    #{package_api_text(circle)}

    #{child_policy_text(circle)}

    #{grain_text()}

    #{ending_text()}
    """
  end

  @impl true
  def execute(code, state, %{circle: circle} = runtime) when is_binary(code) do
    {:ok, child_spawn_counter} =
      Agent.start_link(fn -> Map.get(state, :children_spawned_total, 0) end)

    runtime = put_child_spawn_counter(runtime, child_spawn_counter)

    try do
      {next_state, observations, result, terminated?} =
        case Cantrip.WardPolicy.sandbox(circle.wards) do
          nil -> eval_port(code, state, runtime)
          :dune -> eval_dune(code, state, runtime)
          :port -> eval_port(code, state, runtime)
          :port_unrestricted -> eval_port(code, state, runtime)
          :unrestricted -> eval_unrestricted(code, state, runtime)
          other -> unsupported_sandbox(other, state)
        end

      next_state =
        Map.put(next_state, :children_spawned_total, Agent.get(child_spawn_counter, & &1))

      {:ok, next_state, observations, result, terminated?}
    after
      Agent.stop(child_spawn_counter)
    end
  end

  def execute(_code, state, _runtime) do
    {:error, state, [%{gate: "code", result: "code utterance must be a string", is_error: true}]}
  end

  defp unsupported_sandbox(value, state) do
    msg = "unsupported code sandbox: #{Cantrip.SafeFormat.inspect(value)}"
    {state, [%{gate: "code", result: msg, is_error: true}], nil, false}
  end

  @impl true
  def snapshot(%{port_session: _} = state), do: Cantrip.Medium.Code.Port.snapshot(state)
  def snapshot(%{child_handles: _} = state), do: Cantrip.Medium.Code.Port.snapshot(state)
  def snapshot(state), do: state

  @impl true
  def restore(%{port_session: _} = snapshot), do: Cantrip.Medium.Code.Port.restore(snapshot)
  def restore(snapshot) when is_map(snapshot), do: snapshot
  def restore(_), do: %{}

  defp put_child_spawn_counter(%{parent_context: %{} = parent_context} = runtime, counter) do
    %{runtime | parent_context: Map.put(parent_context, :child_spawn_counter, counter)}
  end

  defp put_child_spawn_counter(runtime, _counter), do: runtime

  @spec eval(String.t(), state(), runtime()) :: {state(), list(map()), term() | nil, boolean()}
  def eval(code, state, runtime) when is_binary(code) do
    {:ok, collector} = Agent.start_link(fn -> [] end)
    {:ok, child_llm_ref} = Agent.start_link(fn -> Map.get(state, :child_llm) end)

    runtime = Map.put(runtime, :observation_collector, collector)
    runtime = Map.put(runtime, :child_llm_ref, child_llm_ref)
    initial_binding = build_binding(Map.get(state, :binding, []), runtime)

    # Compatibility bridge for arbitrary evaluated Elixir code. Child runtime
    # state is carried explicitly in runtime/agents; this process value only
    # lets code call Cantrip.new/cast/cast_batch without hidden options.
    previous_parent_context = Process.get(:cantrip_parent_context)

    parent_context =
      if Map.get(runtime, :parent_context) do
        Map.put(runtime.parent_context, :observation_collector, collector)
        |> Map.put(:child_llm_ref, child_llm_ref)
      end

    if parent_context, do: Process.put(:cantrip_parent_context, parent_context)

    try do
      {binding, result, terminated} = eval_block(code, initial_binding, collector)
      observations = Agent.get(collector, & &1)

      child_llm = Agent.get(child_llm_ref, & &1)

      next_state =
        %{binding: persist_binding(binding)}
        |> maybe_put_child_llm(child_llm)

      {next_state, observations, result, terminated}
    after
      Agent.stop(collector)
      Agent.stop(child_llm_ref)
      restore_process_value(:cantrip_parent_context, previous_parent_context)
    end
  end

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
    result = Cantrip.Medium.Code.Dune.eval(code, state, runtime)
    emit_eval_stop(runtime, eval_start)
    result
  end

  defp eval_port(code, state, runtime) do
    eval_start = System.monotonic_time()
    result = Cantrip.Medium.Code.Port.eval(code, state, runtime)
    emit_eval_stop(runtime, eval_start)
    result
  end

  defp eval_unrestricted(code, state, runtime) do
    timeout = Cantrip.WardPolicy.code_eval_timeout_ms(runtime.circle.wards)

    eval_start = System.monotonic_time()
    telemetry_context = Cantrip.Telemetry.current_context()

    task =
      Task.async(fn ->
        with_telemetry_context(telemetry_context, fn ->
          {:ok, capture_pid} = StringIO.open("")
          Process.group_leader(self(), capture_pid)

          result = eval(code, state, runtime)
          {_, captured_output} = StringIO.contents(capture_pid)
          StringIO.close(capture_pid)

          {result, captured_output}
        end)
      end)

    case Task.yield(task, timeout) do
      {:ok, {{next_state, obs, result, terminated}, captured_output}} ->
        emit_eval_stop(runtime, eval_start)
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
        %{
          gate: "code",
          result: "code evaluation crashed: #{Cantrip.SafeFormat.inspect(reason)}",
          is_error: true
        }
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

  defp with_telemetry_context(%{entity_id: entity_id, trace_id: trace_id}, fun)
       when is_function(fun, 0) do
    Cantrip.Telemetry.with_context(entity_id, trace_id, fun)
  end

  defp with_telemetry_context(_context, fun) when is_function(fun, 0), do: fun.()

  defp emit_eval_stop(%{entity_id: entity_id, trace_id: trace_id}, started_at)
       when is_binary(entity_id) do
    duration = System.monotonic_time() - started_at

    Cantrip.Telemetry.execute(
      [:cantrip, :code, :eval],
      %{duration: duration},
      %{entity_id: entity_id, trace_id: trace_id}
    )
  end

  defp emit_eval_stop(_runtime, _started_at), do: :ok

  defp maybe_put_child_llm(state, nil), do: state
  defp maybe_put_child_llm(state, child_llm), do: Map.put(state, :child_llm, child_llm)

  defp restore_process_value(key, nil), do: Process.delete(key)
  defp restore_process_value(key, value), do: Process.put(key, value)

  defp eval_block(code, binding, collector) do
    if String.trim(code) == "" do
      {binding, nil, false}
    else
      gate_names = extract_gate_names(binding)
      code = add_dot_calls(code, gate_names)

      case Code.string_to_quoted(code) do
        {:ok, quoted} ->
          # Evaluate top-level statements one at a time so that any
          # bindings assigned before a `done.(...)` (or any other
          # control-flow throw) are preserved across the call boundary.
          # Without this, `done` short-circuits Code.eval_quoted and the
          # accumulated binding is lost, which breaks the natural
          # "compute then done" pattern across multi-send entities
          # (MEDIUM-3 / ENTITY-5).
          eval_statements(extract_statements(quoted), binding, collector)

        {:error, {line, error, token}} ->
          msg =
            "parse error at #{Cantrip.SafeFormat.inspect(line)}: " <>
              "#{Cantrip.SafeFormat.inspect(error)} #{Cantrip.SafeFormat.inspect(token)}"

          push_observation(collector, %{gate: "code", result: msg, is_error: true})
          {binding, nil, false}
      end
    end
  end

  # A top-level Elixir script parses to either a __block__ wrapping the
  # statements, or — for a single expression — a bare AST node.
  defp extract_statements({:__block__, _, stmts}), do: stmts
  defp extract_statements(single), do: [single]

  defp eval_statements([], binding, _collector), do: {binding, nil, false}

  defp eval_statements([stmt | rest], binding, collector) do
    try do
      {value, next_binding} = Code.eval_quoted(stmt, binding)

      if rest == [] do
        {next_binding, value, false}
      else
        eval_statements(rest, next_binding, collector)
      end
    rescue
      e ->
        push_observation(collector, %{
          gate: "code",
          result: Cantrip.SafeFormat.exception(e),
          is_error: true
        })

        {binding, nil, false}
    catch
      {:cantrip_done, answer} ->
        {binding, answer, true}

      {:cantrip_error, msg} ->
        push_observation(collector, %{gate: "code", result: msg, is_error: true})
        {binding, {:cantrip_error, msg}, true}
    end
  end

  defp build_binding(binding, runtime) do
    user_binding =
      binding
      |> Keyword.new()
      |> Keyword.drop(@reserved_bindings)

    done_fun = fn answer ->
      observation = Gate.execute(runtime.circle, "done", %{"answer" => answer})
      push_observation(runtime.observation_collector, observation)
      throw({:cantrip_done, answer})
    end

    binding =
      user_binding
      |> Keyword.put(:done, done_fun)
      |> Keyword.put(:loom, Map.get(runtime, :loom))
      |> maybe_put_folded_summary(runtime)
      |> put_circle_gate_bindings(runtime)

    binding =
      case Map.get(runtime, :compile_and_load) do
        nil ->
          binding

        gate_fun ->
          compile_and_load_fun = fn opts ->
            args =
              cond do
                is_map(opts) -> opts
                is_list(opts) -> Map.new(opts)
                true -> opts
              end

            payload = gate_fun.(args)
            push_observation(runtime.observation_collector, payload.observation)
            payload.value
          end

          Keyword.put(binding, :compile_and_load, compile_and_load_fun)
      end

    binding
  end

  defp persist_binding(binding) do
    binding
    |> Keyword.drop(@reserved_bindings)
    |> Enum.reject(fn {_k, v} -> transient_value?(v) end)
  end

  defp transient_value?(%Cantrip.Loom{}), do: true
  defp transient_value?(v) when is_function(v), do: true
  defp transient_value?(_), do: false

  # §6.8: when folding fired this turn, the substrate threads the
  # summary text through the medium runtime so the entity can read it
  # as a binding (`folded_summary`) alongside its other variables. The
  # binding is only present when folding occurred — its absence is
  # meaningful ("no fold this turn"), so we don't bind `nil` to it.
  defp maybe_put_folded_summary(binding, runtime) do
    case Map.get(runtime, :folded_summary) do
      summary when is_binary(summary) and summary != "" ->
        Keyword.put(binding, :folded_summary, summary)

      _ ->
        binding
    end
  end

  defp push_observation(collector, observation) do
    # Ensure every observation carries a stable tool_call_id from the moment
    # it's recorded. Downstream consumers (EventBridge, ACP, telemetry) can
    # rely on it being present without inventing fallbacks.
    observation =
      Map.put_new_lazy(observation, :tool_call_id, fn ->
        "call_" <> Integer.to_string(System.unique_integer([:positive]))
      end)

    Agent.update(collector, &(&1 ++ [observation]))
  end

  defp put_circle_gate_bindings(binding, runtime) do
    case Map.get(runtime, :execute_gate) do
      nil ->
        binding

      execute_gate ->
        runtime.circle
        |> Gate.names()
        |> Enum.reduce(binding, fn gate_name, acc ->
          case gate_binding_name(gate_name) do
            {:ok, binding_name} when binding_name not in @reserved_bindings ->
              gate_fun = fn opts ->
                # In code medium, models may pass bare values (strings, numbers)
                # rather than maps. Normalize maps/lists but pass bare values through
                # so gate handlers can interpret them directly.
                args =
                  cond do
                    is_map(opts) -> opts
                    is_list(opts) -> Map.new(opts)
                    true -> opts
                  end

                observation =
                  execute_gate.(gate_name, args)
                  |> Map.put(:args, Cantrip.Redact.term(args))

                push_observation(runtime.observation_collector, observation)
                observation.result
              end

              Keyword.put(acc, binding_name, gate_fun)

            _ ->
              acc
          end
        end)
    end
  end

  defp gate_binding_name(name) when is_atom(name), do: {:ok, name}

  defp gate_binding_name(name) when is_binary(name) do
    case Enum.find(@builtin_gate_atoms, &(Atom.to_string(&1) == name)) do
      nil -> {:ok, String.to_existing_atom(name)}
      atom -> {:ok, atom}
    end
  rescue
    ArgumentError -> :error
  end

  defp gate_binding_name(_), do: :error

  # Extract gate function names from bindings (all function-valued bindings)
  defp extract_gate_names(binding) do
    binding
    |> Enum.filter(fn {_k, v} -> is_function(v) end)
    |> Enum.map(fn {k, _v} -> Atom.to_string(k) end)
  end

  @doc false
  def add_dot_calls(code, gate_names) when gate_names == [], do: code

  def add_dot_calls(code, gate_names) do
    gate_set = MapSet.new(gate_names)

    case Code.string_to_quoted(code) do
      {:ok, quoted} ->
        quoted
        |> rewrite_gate_calls(gate_set)
        |> Macro.to_string()

      {:error, _reason} ->
        code
    end
  end

  @definition_forms [:def, :defp, :defmacro, :defmacrop]

  defp rewrite_gate_calls({form, meta, [head, body]}, gate_set)
       when form in @definition_forms and is_list(body) do
    {form, meta, [head, rewrite_gate_calls(body, gate_set)]}
  end

  defp rewrite_gate_calls({name, meta, args}, gate_set) when is_atom(name) and is_list(args) do
    args = Enum.map(args, &rewrite_gate_calls(&1, gate_set))

    if MapSet.member?(gate_set, Atom.to_string(name)) do
      {{:., meta, [{name, meta, nil}]}, meta, args}
    else
      {name, meta, args}
    end
  end

  defp rewrite_gate_calls(list, gate_set) when is_list(list) do
    Enum.map(list, &rewrite_gate_calls(&1, gate_set))
  end

  defp rewrite_gate_calls(tuple, gate_set) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&rewrite_gate_calls(&1, gate_set))
    |> List.to_tuple()
  end

  defp rewrite_gate_calls(other, _gate_set), do: other

  defp medium_intro_text do
    """
    You write Elixir code that executes in a persistent sandbox.
    Respond ONLY with the elixir tool containing valid Elixir code.
    Do not write prose or markdown.

    CRITICAL: Do not use defmodule for turn code. Gate functions, `loom`,
    `folded_summary`, and variables from prior turns are top-level bindings;
    module bodies cannot see those bindings. Write code at the top level as a
    script. Use anonymous functions if you need helpers:

        summarize = fn text -> String.split(text, "\\n") |> length() end
        result = summarize.(data)
        done.(result)

    Variables persist across turns. Store intermediate data in variables.
    """
  end

  defp branching_text do
    """
    Branching is pattern matching.

    Gate functions return their `result` value directly. Full gate
    observations, including `is_error`, are recorded in `loom.turns`; inspect
    the result value in your script when you need to recover:

        content = read_file.(path: path)

        case content do
          text when is_binary(text) -> text
          other -> inspect(other)
        end

    Reach for `case` and `with` before `if`. Elixir branch bindings are
    lexical: a variable assigned only inside an `if`, `case`, or `with` branch
    is not created in the outer scope. Assign the whole expression instead.
    """
  end

  defp host_functions_text(%Cantrip.Circle{gates: gates, wards: wards}) do
    sections =
      gates
      |> Enum.reject(fn {name, _gate} -> hidden_host_function?(name, wards) end)
      |> Enum.map(fn {name, gate} -> gate_teaching_section(name, gate) end)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n\n")

    """
    Available host functions (closure bindings, top-level only):
    #{sections}
    """
  end

  defp hidden_host_function?("done", _wards), do: true

  defp hidden_host_function?("compile_and_load", wards),
    do: Cantrip.WardPolicy.sandbox(wards) == :dune

  defp hidden_host_function?(_name, _wards), do: false

  defp gate_teaching_section(name, gate) do
    teaching =
      Map.get(gate, :teaching) ||
        Map.get(gate, "teaching") ||
        Cantrip.Gate.Spec.teaching(name) ||
        Map.get(gate, :description) ||
        Map.get(gate, "description") ||
        Cantrip.Gate.spec(name).description

    """
    ### #{name}.(#{gate_args_hint(name)})

    #{teaching}
    """
  end

  defp history_text do
    """
    Your history is in scope.

    The variables you bound in earlier turns are available by name. If you lose
    track, inspect `binding()`:

        keys = binding() |> Keyword.keys()

    The durable conversation is in `loom`. Human or parent prompts are
    `loom.intents`: maps with `role: "intent"` and
    `utterance: %{content: text}`. Entity actions are `loom.turns`: maps with
    `role: "turn"`, utterance, observation, metadata, and for code/bash turns
    the full medium `code_state` needed for replay.

    To read the conversation back chronologically, use
    `Cantrip.Loom.transcript(loom)`:

        loom
        |> Cantrip.Loom.transcript()
        |> Enum.map(fn
          %{role: "intent", utterance: %{content: text}} -> "you: " <> text
          %{role: "turn", utterance: %{content: c}} -> "me: " <> (c || "")
        end)

    Raw turns can be large because `:code_state` contains the full binding
    snapshot. For IEx-readable inspection, use bounded projections:

        Cantrip.Loom.bounded_turn(List.last(loom.turns))
        Cantrip.Loom.bounded_turns(loom)
        Cantrip.Loom.bounded_transcript(loom)
    """
  end

  defp grain_text do
    """
    The grain of this medium:

    - Your turn code is top-level scripts. Use anonymous functions for in-turn
      helpers.
    - Heredocs need their own opening line. Prefer single-line strings unless
      you genuinely need multi-line.
    - Pipe into `then(fn v -> ... end)`, not into `(fn v -> ... end).()`.
    - Each `Cantrip.cast` is an LLM round-trip. For more than a couple, use
      `Cantrip.cast_batch`; children start concurrently, bounded by the
      `max_concurrent_children` ward, and results are returned in request order.
    """
  end

  defp ending_text do
    """
    Ending:

    #{Cantrip.Gate.Spec.teaching("done")}
    """
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

      :port ->
        """
        Port sandbox note: this circle runs Dune-restricted Elixir in a
        separate child BEAM. Ambient File/System/Process/spawn-style authority
        is denied. Gate closures call back to the parent runtime. Public
        package calls such as Cantrip.new/1, Cantrip.cast/2, and
        Cantrip.cast_batch/1 are proxied to the parent, so child cantrip
        composition remains available while LLM-written Elixir stays outside
        the host BEAM. Parent-to-child casts are depth-bounded and run with
        wards composed from the parent and child circles.
        """

      nil ->
        """
        Port sandbox note: this circle runs Dune-restricted Elixir in a
        separate child BEAM by default. Ambient File/System/Process/spawn-style
        authority is denied. Gate closures call back to the parent runtime.
        Public package calls such as Cantrip.new/1, Cantrip.cast/2, and
        Cantrip.cast_batch/1 are proxied to the parent, so child cantrip
        composition remains available while LLM-written Elixir stays outside
        the host BEAM. Parent-to-child casts are depth-bounded and run with
        wards composed from the parent and child circles.
        """

      _ ->
        """
        Public package API (ordinary module calls, not closure bindings):
        - Cantrip.new(config) constructs a child cantrip and returns {:ok, child} or {:error, reason}
        - Cantrip.cast(child, intent) casts one child and returns {:ok, value, next_child, child_loom, meta} or {:error, reason, next_child}
        - Cantrip.cast_batch(items) casts children concurrently, bounded by max_concurrent_children, and returns {:ok, values, next_children, child_looms, meta} or {:error, reason}
        Parent-to-child casts are depth-bounded and run with wards composed from the parent and child circles.
        """
    end
  end

  defp child_policy_text(circle) do
    constraints =
      [
        child_list_constraint(circle.wards, :child_medium_allowlist, "child mediums"),
        child_list_constraint(circle.wards, :child_gate_allowlist, "child gate allowlist"),
        child_list_constraint(circle.wards, :child_gate_denylist, "child gate denylist"),
        child_value_constraint(circle.wards, :child_max_turns_ceiling, "child max_turns ceiling"),
        child_value_constraint(circle.wards, :child_max_depth_ceiling, "child max_depth ceiling"),
        child_value_constraint(circle.wards, :max_children_total, "total child casts")
      ]
      |> Enum.reject(&is_nil/1)

    case constraints do
      [] ->
        ""

      constraints ->
        """
        Child constraints declared by this circle:
        #{Enum.map_join(constraints, "\n", &"- #{&1}")}
        """
    end
  end

  defp child_list_constraint(wards, key, label) do
    case Cantrip.WardPolicy.get(wards, key) do
      values when is_list(values) -> "#{label}: #{Enum.map_join(values, ", ", &to_string/1)}"
      value when not is_nil(value) -> "#{label}: #{value}"
      nil -> nil
    end
  end

  defp child_value_constraint(wards, key, label) do
    case Cantrip.WardPolicy.get(wards, key) do
      nil -> nil
      value -> "#{label}: #{value}"
    end
  end
end

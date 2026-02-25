defmodule Cantrip.CodeMedium do
  @moduledoc """
  Code medium that executes turn code on the BEAM with persistent bindings.

  The runtime injects a tiny host API into each evaluation:
  - `done/1` terminates the turn and reports the final answer through the circle.
  - `call_agent/1` synchronously delegates to a child entity and returns its value.
  """

  alias Cantrip.Circle

  @reserved_bindings [
    :done,
    :call_agent,
    :call_entity,
    :call_agent_batch,
    :call_entity_batch,
    :compile_and_load
  ]

  @type runtime :: %{
          required(:circle) => Circle.t(),
          optional(:execute_gate) => (String.t(), map() -> map()),
          required(:call_agent) => (map() -> map()),
          optional(:call_agent_batch) => (list(map()) -> map()),
          optional(:compile_and_load) => (map() -> map())
        }
  @type state :: %{optional(:binding) => keyword()}

  @spec eval(String.t(), state(), runtime()) :: {state(), list(map()), term() | nil, boolean()}
  def eval(code, state, runtime) when is_binary(code) do
    initial_binding = build_binding(Map.get(state, :binding, []), runtime)

    Process.put(:cantrip_code_observations, [])
    {binding, result, terminated} = eval_block(code, initial_binding)

    observations = Process.get(:cantrip_code_observations, [])
    Process.delete(:cantrip_code_observations)

    next_state = %{binding: persist_binding(binding)}
    {next_state, observations, result, terminated}
  end

  defp eval_block(code, binding) do
    if String.trim(code) == "" do
      {binding, nil, false}
    else
      case Code.string_to_quoted(code) do
        {:ok, quoted} ->
          try do
            {value, next_binding} = Code.eval_quoted(quoted, binding)
            {next_binding, value, false}
          rescue
            e ->
              push_observation(%{gate: "code", result: Exception.message(e), is_error: true})
              {binding, nil, false}
          catch
            {:cantrip_done, answer} ->
              {binding, answer, true}
          end

        {:error, {line, error, token}} ->
          msg = "parse error at #{inspect(line)}: #{inspect(error)} #{inspect(token)}"
          push_observation(%{gate: "code", result: msg, is_error: true})
          {binding, nil, false}
      end
    end
  end

  defp build_binding(binding, runtime) do
    user_binding =
      binding
      |> Keyword.new()
      |> Keyword.drop(@reserved_bindings)

    done_fun = fn answer ->
      observation = Circle.execute_gate(runtime.circle, "done", %{"answer" => answer})
      push_observation(observation)
      throw({:cantrip_done, answer})
    end

    call_agent_fun = fn opts ->
      payload = runtime.call_agent.(normalize_opts(opts))
      push_observation(payload.observation)
      payload.value
    end

    binding =
      user_binding
      |> Keyword.put(:done, done_fun)
      |> Keyword.put(:call_agent, call_agent_fun)
      |> Keyword.put(:call_entity, call_agent_fun)
      |> put_circle_gate_bindings(runtime)

    binding =
      case Map.get(runtime, :call_agent_batch) do
        nil ->
          binding

        batch_fun ->
          call_agent_batch_fun = fn opts ->
            payload = batch_fun.(normalize_batch(opts))
            push_observation(payload.observation)
            payload.value
          end

          binding
          |> Keyword.put(:call_agent_batch, call_agent_batch_fun)
          |> Keyword.put(:call_entity_batch, call_agent_batch_fun)
      end

    case Map.get(runtime, :compile_and_load) do
      nil ->
        binding

      gate_fun ->
        compile_and_load_fun = fn opts ->
          payload = gate_fun.(normalize_opts(opts))
          push_observation(payload.observation)
          payload.value
        end

        Keyword.put(binding, :compile_and_load, compile_and_load_fun)
    end
  end

  defp persist_binding(binding) do
    binding
    |> Keyword.drop(@reserved_bindings)
    |> Enum.reject(fn {_k, v} -> is_function(v) end)
  end

  defp push_observation(observation) do
    observations = Process.get(:cantrip_code_observations, [])
    Process.put(:cantrip_code_observations, observations ++ [observation])
  end

  defp put_circle_gate_bindings(binding, runtime) do
    case Map.get(runtime, :execute_gate) do
      nil ->
        binding

      execute_gate ->
        runtime.circle
        |> Circle.gate_names()
        |> Enum.reduce(binding, fn gate_name, acc ->
          binding_name = String.to_atom(gate_name)

          if binding_name in @reserved_bindings do
            acc
          else
            gate_fun = fn opts ->
              observation = execute_gate.(gate_name, normalize_opts(opts))
              push_observation(observation)
              observation.result
            end

            Keyword.put(acc, binding_name, gate_fun)
          end
        end)
    end
  end

  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(_), do: %{}

  defp normalize_batch(opts) when is_list(opts) do
    Enum.map(opts, &normalize_opts/1)
  end

  defp normalize_batch(_), do: []
end

defmodule Cantrip.CodeMedium do
  @moduledoc """
  Code medium that executes turn code on the BEAM with persistent bindings.

  The runtime injects a tiny host API into each evaluation:
  - `done/1` terminates the turn and reports the final answer through the circle.
  - `call_agent/1` synchronously delegates to a child entity and returns its value.
  """

  alias Cantrip.Circle

  @reserved_bindings [:done, :call_agent]

  @type runtime :: %{required(:circle) => Circle.t(), required(:call_agent) => (map() -> map())}
  @type state :: %{optional(:binding) => keyword()}

  @spec eval(String.t(), state(), runtime()) :: {state(), list(map()), term() | nil, boolean()}
  def eval(code, state, runtime) when is_binary(code) do
    statements = split_statements(code)
    initial_binding = build_binding(Map.get(state, :binding, []), runtime)

    Process.put(:cantrip_code_observations, [])

    {binding, result, terminated} =
      Enum.reduce_while(statements, {initial_binding, nil, false}, fn statement,
                                                                      {binding, _result, _term} ->
        case eval_statement(statement, binding) do
          {:ok, next_binding} ->
            {:cont, {next_binding, nil, false}}

          {:done, next_binding, answer} ->
            {:halt, {next_binding, answer, true}}
        end
      end)

    observations = Process.get(:cantrip_code_observations, [])
    Process.delete(:cantrip_code_observations)

    next_state = %{binding: persist_binding(binding)}
    {next_state, observations, result, terminated}
  end

  defp eval_statement("", binding), do: {:ok, binding}

  defp eval_statement(statement, binding) do
    try do
      {_value, next_binding} = Code.eval_string(statement, binding)
      {:ok, next_binding}
    catch
      {:cantrip_done, answer} ->
        {:done, binding, answer}
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

    user_binding
    |> Keyword.put(:done, done_fun)
    |> Keyword.put(:call_agent, call_agent_fun)
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

  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(_), do: %{}

  defp split_statements(code) do
    code
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end

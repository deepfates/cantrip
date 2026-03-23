defmodule Cantrip.FakeLLM do
  @moduledoc """
  Deterministic llm used in tests.
  """

  @behaviour Cantrip.LLM

  def new(responses, opts \\ []) when is_list(responses) do
    shared = Keyword.get(opts, :shared, false)

    counter_ref =
      if shared do
        ref = make_ref()
        table = :ets.new(:fake_llm_shared, [:public, :set])
        :ets.insert(table, {ref, 0})
        {table, ref}
      else
        nil
      end

    %{
      responses: responses,
      index: 0,
      record_inputs: Keyword.get(opts, :record_inputs, false),
      invocations: [],
      shared_counter: counter_ref
    }
  end

  def invocations(state), do: Enum.reverse(state.invocations)

  @impl true
  def query(state, request) do
    state = maybe_record(state, request)

    index =
      case state.shared_counter do
        {table, ref} ->
          [{_, idx}] = :ets.lookup(table, ref)
          :ets.update_counter(table, ref, {2, 1})
          idx
        nil ->
          state.index
      end

    response = Enum.at(state.responses, index, %{content: "ok"})
    state = %{state | index: index + 1}

    case response[:error] || response["error"] do
      nil -> {:ok, response, state}
      err -> {:error, err, state}
    end
  end

  defp maybe_record(%{record_inputs: false} = state, _request), do: state

  defp maybe_record(state, request) do
    %{state | invocations: [request | state.invocations]}
  end
end

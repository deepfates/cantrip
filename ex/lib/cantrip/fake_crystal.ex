defmodule Cantrip.FakeCrystal do
  @moduledoc """
  Deterministic crystal used in tests.
  """

  @behaviour Cantrip.Crystal

  def new(responses, opts \\ []) when is_list(responses) do
    %{
      responses: responses,
      index: 0,
      record_inputs: Keyword.get(opts, :record_inputs, false),
      invocations: []
    }
  end

  def invocations(state), do: Enum.reverse(state.invocations)

  @impl true
  def query(state, request) do
    state = maybe_record(state, request)
    response = Enum.at(state.responses, state.index, %{content: "ok"})
    state = %{state | index: state.index + 1}

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

defmodule Cantrip.FakeCrystal do
  @behaviour Cantrip.Crystal

  @moduledoc false

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

    response =
      case Enum.at(state.responses, state.index) do
        nil -> %{content: "done"}
        r -> r
      end

    {:ok, normalize(response), %{state | index: state.index + 1}}
  end

  defp maybe_record(%{record_inputs: false} = state, _request), do: state

  defp maybe_record(state, request) do
    %{state | invocations: [request | state.invocations]}
  end

  defp normalize(%{raw_response: raw}) do
    choice = raw[:choices] |> List.first() |> Map.get(:message, %{})
    usage = raw[:usage] || %{}

    %{
      content: choice[:content],
      tool_calls: choice[:tool_calls] || [],
      usage: usage
    }
  end

  defp normalize(other), do: other
end

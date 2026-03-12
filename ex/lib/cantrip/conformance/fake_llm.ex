defmodule Cantrip.Conformance.FakeLLM do
  @moduledoc "Deterministic scripted LLM for conformance tests."

  @behaviour Cantrip.LLM

  defstruct responses: [], index: 0

  @type t :: %__MODULE__{responses: list(map()), index: non_neg_integer()}

  @spec new(list(map())) :: t()
  def new(responses) when is_list(responses), do: %__MODULE__{responses: responses, index: 0}

  @impl true
  def query(%__MODULE__{} = state, _request) do
    case Enum.fetch(state.responses, state.index) do
      {:ok, response} ->
        {:ok, response, %{state | index: state.index + 1}}

      :error ->
        raise RuntimeError, "conformance fake llm responses exhausted at index #{state.index}"
    end
  end
end

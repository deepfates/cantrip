defmodule Cantrip.Crystal do
  @moduledoc """
  Crystal behaviour and contract validator.
  """

  @type request :: map()

  @type response :: %{
          optional(:content) => String.t() | nil,
          optional(:tool_calls) => list(map()) | nil,
          optional(:usage) => map(),
          optional(:raw_response) => map()
        }

  @callback query(state :: term(), request()) ::
              {:ok, response(), term()} | {:error, term(), term()}

  @spec invoke(module(), term(), request()) ::
          {:ok, map(), term()} | {:error, term(), term()}
  def invoke(module, state, request) do
    case module.query(state, request) do
      {:ok, response, next_state} ->
        response = normalize(response)

        case validate_response(response) do
          :ok -> {:ok, response, next_state}
          {:error, reason} -> {:error, reason, next_state}
        end

      {:error, reason, next_state} ->
        {:error, reason, next_state}
    end
  end

  @spec validate_response(map()) :: :ok | {:error, String.t()}
  def validate_response(response) do
    content = Map.get(response, :content)
    tool_calls = Map.get(response, :tool_calls)
    code = Map.get(response, :code)

    cond do
      is_nil(content) and is_nil(tool_calls) and is_nil(code) ->
        {:error, "crystal returned neither content nor tool_calls"}

      duplicate_tool_call_ids?(tool_calls || []) ->
        {:error, "duplicate tool call ID"}

      true ->
        :ok
    end
  end

  @spec normalize(map()) :: map()
  def normalize(%{raw_response: raw}) do
    choice = raw[:choices] |> List.first() |> Map.get(:message, %{})

    %{
      content: choice[:content],
      tool_calls: choice[:tool_calls] || [],
      usage: raw[:usage] || %{}
    }
  end

  def normalize(response), do: response

  defp duplicate_tool_call_ids?(calls) do
    ids =
      calls
      |> Enum.map(fn call -> call[:id] || call["id"] end)
      |> Enum.reject(&is_nil/1)

    length(ids) != length(Enum.uniq(ids))
  end
end

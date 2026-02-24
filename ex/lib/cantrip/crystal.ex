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
  def normalize(%{tool_calls: tool_calls} = response) when is_list(tool_calls), do: response

  def normalize(%{raw_response: raw} = response) when is_map(raw) do
    atom_choices = Map.get(raw, :choices)
    string_choices = Map.get(raw, "choices")

    cond do
      is_list(atom_choices) and atom_choices != [] ->
        choice = atom_choices |> List.first() |> Map.get(:message, %{})

        %{
          content: Map.get(choice, :content),
          tool_calls: Map.get(choice, :tool_calls, []) || [],
          usage: Map.get(raw, :usage, %{}) || %{}
        }

      is_list(string_choices) and string_choices != [] ->
        choice = string_choices |> List.first() |> Map.get("message", %{})

        %{
          content: Map.get(choice, "content"),
          tool_calls: Map.get(choice, "tool_calls", []) || [],
          usage: Map.get(raw, "usage", %{}) || %{}
        }

      true ->
        response
    end
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

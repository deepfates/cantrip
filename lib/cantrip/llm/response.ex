defmodule Cantrip.LLM.Response do
  @moduledoc """
  This is the response shape every LLM provider answer becomes before the
  runtime reads it. If you implement `Cantrip.LLM`, prefer returning this shape;
  raw provider maps are accepted only when they satisfy the same boundary
  contract.

  Normalized provider response boundary object.

  LLM adapters may speak provider-specific data shapes internally, but the rest
  of Cantrip consumes this struct. Required keys are enforced at construction so
  provider contract drift fails at the boundary instead of being papered over by
  downstream `Map.get/3` defaults.
  """

  @enforce_keys [:content, :tool_calls, :usage]
  defstruct [:content, :tool_calls, :usage, :raw_response, :stop_reason]

  @type t :: %__MODULE__{
          content: String.t() | nil,
          tool_calls: list(map()),
          usage: map(),
          raw_response: term(),
          stop_reason: atom() | nil
        }

  @spec new(map() | t()) :: {:ok, t()} | {:error, String.t()}
  def new(%__MODULE__{} = response), do: {:ok, response}

  def new(response) when is_map(response) do
    response = normalize_legacy_response(response)

    with :ok <- reject_tool_result(response),
         {:ok, content} <- fetch_required(response, :content),
         {:ok, tool_calls} <- fetch_required(response, :tool_calls),
         {:ok, usage} <- fetch_required(response, :usage),
         :ok <- validate_tool_calls(tool_calls),
         :ok <- validate_usage(usage) do
      {:ok,
       %__MODULE__{
         content: normalize_content(content),
         tool_calls: tool_calls,
         usage: usage,
         raw_response: Map.get(response, :raw_response),
         stop_reason: normalize_stop_reason(Map.get(response, :stop_reason))
       }}
    end
  end

  def new(_response), do: {:error, "llm response must be a map or %Cantrip.LLM.Response{}"}

  defp reject_tool_result(response) do
    if Map.has_key?(response, :tool_result) or Map.has_key?(response, "tool_result") do
      {:error, "tool result without matching tool call"}
    else
      :ok
    end
  end

  defp fetch_required(map, key) do
    if Map.has_key?(map, key) do
      {:ok, Map.fetch!(map, key)}
    else
      {:error, "llm response missing required #{key}"}
    end
  end

  defp validate_tool_calls(tool_calls) when is_list(tool_calls), do: :ok
  defp validate_tool_calls(_tool_calls), do: {:error, "llm response tool_calls must be a list"}

  defp validate_usage(usage) when is_map(usage), do: :ok
  defp validate_usage(_usage), do: {:error, "llm response usage must be a map"}

  defp normalize_content(""), do: nil
  defp normalize_content(content), do: content

  defp normalize_stop_reason(reason) when is_atom(reason), do: reason
  defp normalize_stop_reason(_reason), do: nil

  defp normalize_legacy_response(%{raw_response: raw} = response) when is_map(raw) do
    atom_choices = Map.get(raw, :choices)
    string_choices = Map.get(raw, "choices")

    cond do
      is_list(atom_choices) and atom_choices != [] ->
        choice = atom_choices |> List.first() |> Map.get(:message, %{})

        %{
          content: Map.get(choice, :content),
          tool_calls: Map.get(choice, :tool_calls, []) || [],
          usage: Map.get(raw, :usage, %{}) || %{},
          raw_response: Map.get(response, :raw_response)
        }

      is_list(string_choices) and string_choices != [] ->
        choice = string_choices |> List.first() |> Map.get("message", %{})

        %{
          content: Map.get(choice, "content"),
          tool_calls: Map.get(choice, "tool_calls", []) || [],
          usage: Map.get(raw, "usage", %{}) || %{},
          raw_response: Map.get(response, :raw_response)
        }

      true ->
        response
    end
  end

  defp normalize_legacy_response(%{tool_calls: tool_calls} = response) when is_list(tool_calls),
    do: response

  defp normalize_legacy_response(response), do: response
end

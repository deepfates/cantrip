defmodule Cantrip.LLMs.Helpers do
  @moduledoc false

  @doc """
  Extracts an error message from an API response body.

  Looks for `body["error"]["message"]`; falls back to `inspect(body)`.
  """
  @spec extract_error(term()) :: String.t()
  def extract_error(%{"error" => %{"message" => message}}) when is_binary(message),
    do: Cantrip.SafeFormat.message(message)

  def extract_error(body), do: Cantrip.SafeFormat.inspect(body)

  @doc """
  Normalizes opts to a map: keyword lists become maps, maps pass through, anything else becomes `%{}`.
  """
  @spec normalize_opts(term()) :: map()
  def normalize_opts(opts) when is_map(opts), do: opts
  def normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  def normalize_opts(_), do: %{}

  @known_keys ~w(gates intent context system_prompt llm wards circle_type medium_opts)

  @doc """
  Converts string keys to atom keys for known option names, then passes through `normalize_opts/1`.

  Unknown string keys are preserved as-is.
  """
  @spec atomize_known_keys(term()) :: map()
  def atomize_known_keys(opts) do
    opts
    |> normalize_opts()
    |> Enum.map(fn
      {k, v} when is_binary(k) and k in @known_keys -> {String.to_existing_atom(k), v}
      pair -> pair
    end)
    |> Map.new()
  end

  @message_atoms ~w(role content tool_calls tool_call_id gate)a
  @tool_spec_atoms ~w(name description parameters)a
  @tool_call_atoms ~w(id gate args)a

  @doc """
  Ensures a message map has atom keys for known fields, including nested tool_calls.
  """
  @spec normalize_message(map()) :: map()
  def normalize_message(msg) when is_map(msg) do
    msg = ensure_atom_keys(msg, @message_atoms)

    case msg[:tool_calls] do
      tcs when is_list(tcs) -> %{msg | tool_calls: Enum.map(tcs, &normalize_tool_call/1)}
      _ -> msg
    end
  end

  @doc """
  Ensures a tool spec map has atom keys for known fields.
  """
  @spec normalize_tool_spec(map()) :: map()
  def normalize_tool_spec(tool) when is_map(tool), do: ensure_atom_keys(tool, @tool_spec_atoms)

  @doc """
  Ensures a tool call map has atom keys for known fields.
  """
  @spec normalize_tool_call(map()) :: map()
  def normalize_tool_call(tc) when is_map(tc), do: ensure_atom_keys(tc, @tool_call_atoms)

  defp ensure_atom_keys(map, known_atoms) do
    Enum.reduce(known_atoms, map, fn atom_key, acc ->
      str_key = Atom.to_string(atom_key)

      case {Map.has_key?(acc, atom_key), Map.pop(acc, str_key)} do
        {true, _} -> acc
        {false, {nil, _}} -> acc
        {false, {val, rest}} -> Map.put(rest, atom_key, val)
      end
    end)
  end
end

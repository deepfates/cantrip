defmodule Cantrip.LLMs.Helpers do
  @moduledoc """
  Shared helper functions for LLM adapters.
  """

  @doc """
  Extracts code from a markdown-fenced response, stripping the fence markers.

  If the content contains a fenced code block (optionally tagged `elixir`),
  returns the trimmed interior. Otherwise returns the trimmed content as-is.
  Returns `nil` for non-binary input.
  """
  @spec extract_code(term()) :: String.t() | nil
  def extract_code(content) when not is_binary(content), do: nil

  def extract_code(content) do
    text = String.trim(content)

    case Regex.run(~r/```(?:elixir)?\s*\n([\s\S]*?)\n```/i, text) do
      [_, code] -> String.trim(code)
      _ -> text
    end
  end

  @doc """
  Extracts an error message from an API response body.

  Looks for `body["error"]["message"]`; falls back to `inspect(body)`.
  """
  @spec extract_error(term()) :: String.t()
  def extract_error(%{"error" => %{"message" => message}}) when is_binary(message), do: message
  def extract_error(body), do: inspect(body)

  @doc """
  Normalizes opts to a map: keyword lists become maps, maps pass through, anything else becomes `%{}`.
  """
  @spec normalize_opts(term()) :: map()
  def normalize_opts(opts) when is_map(opts), do: opts
  def normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  def normalize_opts(_), do: %{}

  @known_keys ~w(gates intent context system_prompt llm wards)

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
end

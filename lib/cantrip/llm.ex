defmodule Cantrip.LLM do
  @moduledoc """
  Implement this behaviour to provide a model backend. The runtime calls
  `query/2` with a normalized request and expects a normalized response or an
  error tuple with updated provider state.

  LLM behaviour and contract validator.
  """

  @type request :: map()

  alias Cantrip.LLM.Response

  @type response :: Response.t()

  @callback query(state :: term(), request()) ::
              {:ok, response() | map(), term()} | {:error, term(), term()}

  @req_llm_prefixes %{
    "openai_compatible" => "openai",
    "openai" => "openai",
    "anthropic" => "anthropic",
    "gemini" => "google",
    "google" => "google"
  }

  @doc """
  Resolve the configured LLM from the process environment.

  ReqLLM is the only built-in provider adapter. `CANTRIP_LLM_PROVIDER`
  selects the ReqLLM provider prefix and defaults to `openai_compatible`.
  Provider-specific env vars override the generic `CANTRIP_*` values.
  """
  @spec from_env(keyword() | map()) :: {:ok, {module(), map()}} | {:error, String.t()}
  def from_env(opts \\ []) do
    opts = Map.new(opts)
    provider = env(opts, :provider, "CANTRIP_LLM_PROVIDER", "openai_compatible")

    case Map.fetch(@req_llm_prefixes, provider) do
      {:ok, prefix} ->
        build_req_llm(provider, prefix, opts)

      :error ->
        {:error, "unsupported llm provider: #{provider}"}
    end
  end

  defp build_req_llm(provider, prefix, opts) do
    model = provider_model(provider, opts)

    if model in [nil, ""] do
      {:error, missing_model_error(provider)}
    else
      state = %{
        model: "#{prefix}:#{model}",
        stream: parse_bool(env(opts, :stream, "CANTRIP_STREAM"), false),
        timeout_ms: parse_int(env(opts, :timeout_ms, "CANTRIP_TIMEOUT_MS"), 60_000),
        temperature: parse_float(env(opts, :temperature, "CANTRIP_TEMPERATURE")),
        max_tokens: parse_int(env(opts, :max_tokens, "CANTRIP_MAX_TOKENS"), nil)
      }

      state =
        state
        |> maybe_put(:base_url, provider_base_url(provider, opts))
        |> maybe_put(:api_key, provider_api_key(provider, opts))

      {:ok, {Cantrip.LLMs.ReqLLM, state}}
    end
  end

  defp provider_model(provider, opts) when provider in ["openai_compatible", "openai"],
    do: option_or_env_first(opts, :model, ["OPENAI_MODEL", "CANTRIP_MODEL"])

  defp provider_model("anthropic", opts),
    do: option_or_env_first(opts, :model, ["ANTHROPIC_MODEL", "CANTRIP_MODEL"])

  defp provider_model(provider, opts) when provider in ["gemini", "google"],
    do: option_or_env_first(opts, :model, ["GEMINI_MODEL", "CANTRIP_MODEL"])

  defp provider_model(_provider, opts), do: option_or_env_first(opts, :model, ["CANTRIP_MODEL"])

  defp provider_base_url(provider, opts) when provider in ["openai_compatible", "openai"],
    do: option_or_env_first(opts, :base_url, ["OPENAI_BASE_URL", "CANTRIP_BASE_URL"])

  defp provider_base_url(_provider, _opts), do: nil

  defp provider_api_key(provider, opts) when provider in ["openai_compatible", "openai"],
    do: option_or_env_first(opts, :api_key, ["OPENAI_API_KEY", "CANTRIP_API_KEY"])

  defp provider_api_key("anthropic", opts),
    do: option_or_env_first(opts, :api_key, ["ANTHROPIC_API_KEY", "CANTRIP_API_KEY"])

  defp provider_api_key(provider, opts) when provider in ["gemini", "google"],
    do: option_or_env_first(opts, :api_key, ["GEMINI_API_KEY", "CANTRIP_API_KEY"])

  defp provider_api_key(_provider, _opts), do: nil

  defp missing_model_error(provider) when provider in ["openai_compatible", "openai"],
    do: "missing CANTRIP_MODEL or OPENAI_MODEL"

  defp missing_model_error("anthropic"), do: "missing CANTRIP_MODEL or ANTHROPIC_MODEL"

  defp missing_model_error(provider) when provider in ["gemini", "google"],
    do: "missing CANTRIP_MODEL or GEMINI_MODEL"

  defp missing_model_error(_provider), do: "missing CANTRIP_MODEL"

  defp env(opts, key, env_key, default \\ nil) do
    case fetch_option(opts, key) do
      {:ok, value} -> value
      :error -> trim_env(System.get_env(env_key)) || default
    end
  end

  defp option_or_env_first(opts, option_key, env_keys) do
    case fetch_option(opts, option_key) do
      {:ok, value} when value not in [nil, ""] -> value
      _ -> env_first(env_keys)
    end
  end

  defp fetch_option(opts, key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(opts, key) -> {:ok, Map.fetch!(opts, key)}
      Map.has_key?(opts, string_key) -> {:ok, Map.fetch!(opts, string_key)}
      true -> :error
    end
  end

  defp env_first(keys) do
    Enum.find_value(keys, fn key ->
      case trim_env(System.get_env(key)) do
        nil -> nil
        "" -> nil
        val -> val
      end
    end)
  end

  # Env-provided secrets (especially CI-injected ones) frequently carry a
  # trailing newline. An untrimmed value smuggled into an HTTP header like
  # `x-api-key` is rejected as a non-printable character, so normalize here.
  defp trim_env(nil), do: nil
  defp trim_env(value) when is_binary(value), do: String.trim(value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec request(module(), term(), request()) ::
          {:ok, Response.t(), term()} | {:error, term(), term()}
  def request(module, state, req) do
    case module.query(state, req) do
      {:ok, response, next_state} ->
        with {:ok, response} <- Response.new(response),
             :ok <- validate_response(response) do
          {:ok, response, next_state}
        else
          {:error, reason} -> {:error, reason, next_state}
        end

      {:error, reason, next_state} ->
        {:error, reason, next_state}
    end
  end

  @spec validate_response(Response.t()) :: :ok | {:error, String.t()}
  def validate_response(%Response{} = response) do
    cond do
      is_nil(response.content) and response.tool_calls == [] ->
        {:error, "llm returned neither content nor tool_calls"}

      duplicate_tool_call_ids?(response.tool_calls) ->
        {:error, "duplicate tool call ID"}

      true ->
        :ok
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil
  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value / 1

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp parse_bool(value, _default) when is_boolean(value), do: value
  defp parse_bool(nil, default), do: default
  defp parse_bool("", default), do: default

  defp parse_bool(value, default) when is_binary(value) do
    case String.downcase(value) do
      "true" -> true
      "1" -> true
      "yes" -> true
      "false" -> false
      "0" -> false
      "no" -> false
      _ -> default
    end
  end

  defp parse_bool(_value, default), do: default

  defp duplicate_tool_call_ids?(calls) do
    ids =
      calls
      |> Enum.map(fn call -> call[:id] || call["id"] end)
      |> Enum.reject(&is_nil/1)

    length(ids) != length(Enum.uniq(ids))
  end
end
